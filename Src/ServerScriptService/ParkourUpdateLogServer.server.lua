-- ParkourUpdateLogServer V1
-- NEW Script: ServerScriptService > ParkourUpdateLogServer
-- Does not modify Builder, Discover, draft saves, barriers, or guest permissions.
-- The only remotely writable action is a player's cosmetic "read" marker.
-- Reviewed developer release notes arrive via GitHub -> Roblox Open Cloud.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local CONFIG = {
	FeedStore = "ParkourUpdateLogs_V1",
	FeedKey = "release_feed_v1",
	ReadStore = "ParkourUpdateLogRead_V1",
	PollSeconds = 120,
	PersistReadState = true,
	-- Default false: real feed. Turn true ONLY to preview the sample UI in Studio.
	StudioDemo = false,
	MaxEntries = 20,
	MaxBodyBytes = 4000,
}

local existing = RS:FindFirstChild("ParkourUpdateLogEvent")
if existing and not existing:IsA("RemoteEvent") then
	error("ParkourUpdateLogEvent already exists but is not a RemoteEvent.")
end
local remote = existing or Instance.new("RemoteEvent")
remote.Name = "ParkourUpdateLogEvent"
remote.Parent = RS

local demo = RunService:IsStudio() and CONFIG.StudioDemo
local feedStore = DataStoreService:GetDataStore(CONFIG.FeedStore)
local readStore = DataStoreService:GetDataStore(CONFIG.ReadStore)
local freshRead = Instance.new("DataStoreGetOptions")
freshRead.UseCache = false
local cache = {entries = {}, fingerprint = ""}
local serviceStatus = "loading"
local checkedAt = 0
local readers = {}
local connections = {}
local writesInFlight = 0
local shuttingDown = false

local function positiveInteger(value)
	return type(value) == "number" and value == value
		and value > 0 and value < math.huge and value % 1 == 0
end

local function releaseNumber(id)
	if type(id) ~= "string" then return 0 end
	return tonumber(id:match("^gh%-(%d+)$")) or 0
end

local function newer(a, b)
	local at = tonumber(a.publishedAt) or 0
	local bt = tonumber(b.publishedAt) or 0
	return at > bt or (at == bt and releaseNumber(a.id) > releaseNumber(b.id))
end

local function validString(value, maxBytes)
	return type(value) == "string" and #value > 0 and #value <= maxBytes
		and utf8.len(value) ~= nil
end

local function sanitizeFeed(raw)
	if type(raw) ~= "table" or raw.schemaVersion ~= 1 or type(raw.entries) ~= "table" then
		return nil, "Unrecognized update-log schema."
	end
	if type(raw.fingerprint) ~= "string" or #raw.fingerprint > 80 then
		return nil, "Invalid update-log fingerprint."
	end
	local result = {entries = {}, fingerprint = raw.fingerprint}
	local ids = {}
	for index, entry in ipairs(raw.entries) do
		if index > CONFIG.MaxEntries then return nil, "Too many update entries." end
		if type(entry) ~= "table"
			or not validString(entry.id, 64) or releaseNumber(entry.id) <= 0
			or ids[entry.id]
			or not validString(entry.title, 160)
			or not validString(entry.version, 64)
			or not validString(entry.body, CONFIG.MaxBodyBytes)
			or not positiveInteger(entry.publishedAt) then
			return nil, "Invalid update entry. Keeping the previous feed."
		end
		ids[entry.id] = true
		table.insert(result.entries, {
			id = entry.id, title = entry.title, version = entry.version,
			publishedAt = entry.publishedAt, body = entry.body,
		})
	end
	table.sort(result.entries, newer)
	return result
end

local function packetFor(player)
	local reader = readers[player]
	local seen = reader and reader.seen or {publishedAt = 0, id = ""}
	local latest = cache.entries[1]
	return {
		entries = cache.entries, fingerprint = cache.fingerprint,
		status = serviceStatus, checkedAt = checkedAt, demo = demo,
		seenReady = reader ~= nil and reader.loaded,
		unread = latest ~= nil and newer(latest, seen),
		seenPublishedAt = seen.publishedAt, seenId = seen.id,
	}
end

local function send(player)
	if player.Parent == Players then
		remote:FireClient(player, "State", packetFor(player))
	end
end

local function broadcast()
	for _, player in ipairs(Players:GetPlayers()) do send(player) end
end

local function cleanSeen(value)
	if type(value) ~= "table" then return {publishedAt = 0, id = ""} end
	if not positiveInteger(value.publishedAt) or releaseNumber(value.id) <= 0 then
		return {publishedAt = 0, id = ""}
	end
	return {publishedAt = value.publishedAt, id = value.id}
end

local function watchPlayer(player)
	if readers[player] then return end
	local reader = {
		seen = {publishedAt = 0, id = ""}, loaded = false,
		lastRequest = -math.huge, lastRead = -math.huge,
		writing = false, pendingWrite = nil,
	}
	readers[player] = reader
	task.spawn(function()
		if CONFIG.PersistReadState and not demo then
			local ok, stored = false, nil
			for attempt = 1, 3 do
				ok, stored = pcall(function()
					return readStore:GetAsync("reader_" .. tostring(player.UserId))
				end)
				if ok then break end
				task.wait(attempt)
			end
			if readers[player] ~= reader then return end
			if ok then
				local old = cleanSeen(stored)
				-- A client might have opened the window while the read yielded.
				if newer(old, reader.seen) then reader.seen = old end
			else
				warn("[UPDATE LOG] Read-marker load failed for " .. player.Name .. "; using session state.")
			end
		end
		if readers[player] ~= reader then return end
		reader.loaded = true
		send(player)
	end)
end

local function persistSeen(player, reader, value)
	if not CONFIG.PersistReadState or demo then return end
	if not reader.pendingWrite or newer(value, reader.pendingWrite) then
		reader.pendingWrite = {publishedAt = value.publishedAt, id = value.id}
	end
	if reader.writing then return end
	reader.writing = true
	writesInFlight = writesInFlight + 1
	task.spawn(function()
		while reader.pendingWrite do
			local desired = reader.pendingWrite
			reader.pendingWrite = nil
			local ok, err
			for attempt = 1, 3 do
				ok, err = pcall(function()
					readStore:UpdateAsync("reader_" .. tostring(player.UserId), function(old)
						local prior = cleanSeen(old)
						-- Never regress a newer marker written by another server.
						if not newer(desired, prior) then return nil end
						return desired
					end)
				end)
				if ok then break end
				task.wait(attempt)
			end
			if not ok then
				warn("[UPDATE LOG] Read-marker save failed; NEW may return on another visit: " .. tostring(err))
			end
		end
		reader.writing = false
		writesInFlight = writesInFlight - 1
	end)
end

remote.OnServerEvent:Connect(function(player, action, id)
	local reader = readers[player]
	if not reader then watchPlayer(player); reader = readers[player] end
	local now = os.clock()
	if action == "Request" then
		if now - reader.lastRequest < 2 then return end
		reader.lastRequest = now
		send(player) -- cached response; clients cannot force DataStore reads
	elseif action == "Read" then
		if now - reader.lastRead < 1 then return end
		reader.lastRead = now
		local latest = cache.entries[1]
		if type(id) ~= "string" or #id > 64 or not latest or id ~= latest.id then
			send(player)
			return
		end
		if newer(latest, reader.seen) then
			reader.seen = {publishedAt = latest.publishedAt, id = latest.id}
			persistSeen(player, reader, reader.seen)
		end
		send(player)
	end
end)

Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function(player) readers[player] = nil end)
for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end

local function refreshFeed()
	local ok, raw = pcall(function()
		local value = feedStore:GetAsync(CONFIG.FeedKey, freshRead)
		if value == nil then
			-- First-run bootstrap only. Never replace an existing release feed.
			feedStore:UpdateAsync(CONFIG.FeedKey, function(old)
				if old ~= nil then return nil end
				return {
					schemaVersion = 1, sourceRepository = "", entries = {},
					fingerprint = "", generatedAt = 0,
				}
			end)
			value = feedStore:GetAsync(CONFIG.FeedKey, freshRead)
		end
		return value
	end)
	if not ok then
		local oldStatus = serviceStatus
		serviceStatus = #cache.entries > 0 and "stale" or "unavailable"
		warn("[UPDATE LOG] Feed read failed; previous content retained: " .. tostring(raw))
		if oldStatus ~= serviceStatus then broadcast() end
		return false
	end
	local clean, why = sanitizeFeed(raw)
	if not clean then
		serviceStatus = #cache.entries > 0 and "stale" or "unavailable"
		warn("[UPDATE LOG] " .. tostring(why))
		broadcast()
		return false
	end
	local changed = clean.fingerprint ~= cache.fingerprint or serviceStatus ~= "ready"
	cache = clean
	serviceStatus = "ready"
	checkedAt = os.time()
	if changed then broadcast() end
	return true
end

task.spawn(function()
	if demo then
		cache = {
			fingerprint = "studio-demo-v1",
			entries = {{
				id = "gh-1", version = "DEMO", title = "Update-log preview (not a released update)",
				publishedAt = 1,
				body = "NEW\n� Your published, reviewed release notes appear here.\n\nIMPROVEMENTS\n� Navy/cyan update cards with a NEW badge.\n\nThis is sample text for Studio only. No DataStore writes are made in demo mode.",
			}},
		}
		serviceStatus = "ready"
		checkedAt = os.time()
		broadcast()
		return
	end
	print("[UPDATE LOG] Universe ID (for GitHub ROBLOX_UNIVERSE_ID): " .. tostring(game.GameId))
	while not shuttingDown do
		refreshFeed()
		task.wait(CONFIG.PollSeconds + math.random(-8, 8))
	end
end)

game:BindToClose(function()
	shuttingDown = true
	local deadline = os.clock() + 8
	while writesInFlight > 0 and os.clock() < deadline do task.wait(0.1) end
end)

print("[UPDATE LOG] Server V1 loaded" .. (demo and " -- STUDIO DEMO ONLY" or ""))

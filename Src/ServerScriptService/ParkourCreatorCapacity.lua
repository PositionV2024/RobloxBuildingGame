-- ParkourCreatorCapacity V1.1 - HARD CAP 5
-- NEW ModuleScript: ServerScriptService > ParkourCreatorCapacity
-- Required by the supplied ArrivalServer and InviteServer; do NOT run as a Script.
-- Session-only capacity. Does NOT write draft/settings DataStores.
-- Players.MaxPlayers is READ ONLY. This module enforces a lower admission limit.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MemoryStoreService = game:GetService("MemoryStoreService")

local Capacity = {}
local HARD_CAP = 5
local DEFAULT_LIMIT = 2 -- total players, including the owner.
local RECORD_TTL = 60
local REFRESH_SECONDS = 10
local STALE_AFTER = 35
local directory = MemoryStoreService:GetHashMap("ParkourCreatorCapacity_V1")

local remote = RS:FindFirstChild("ParkourCreatorServerSizeEvent")
if remote then
	assert(remote:IsA("RemoteEvent"), "ParkourCreatorServerSizeEvent must be a RemoteEvent")
else
	remote = Instance.new("RemoteEvent")
	remote.Name = "ParkourCreatorServerSizeEvent"
	remote.Parent = RS
end

local ownerId = nil
local limit = math.max(1, math.floor(Players.MaxPlayers))
local members = {} -- [UserId] = admitted Player; incoming overflow never enters this table.
local closed = false
local revision = 0
local publishDirty = false
local publishing = false
local requestTimes = {}

local function allowedMaximum()
	return math.max(1,math.min(HARD_CAP,math.floor(Players.MaxPlayers)))
end

local function isInteger(value)
	return type(value) == "number" and value == value
		and value ~= math.huge and value ~= -math.huge and value % 1 == 0
end

local function memberCount()
	local count = 0
	for _, member in pairs(members) do
		if member.Parent == Players then count = count + 1 end
	end
	return count
end

local function sessionIsOpen()
	return ownerId ~= nil and not closed
		and tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId")) == ownerId
		and workspace:GetAttribute("ParkourPrivateCreatorServer") == true
		and Players:GetPlayerByUserId(ownerId) ~= nil
		and workspace:GetAttribute("ParkourCreatorSessionClosing") ~= true
		and workspace:GetAttribute("ParkourCreatorOwnerPresent") ~= false
end

function Capacity.IsOwner(player)
	return player ~= nil and player.Parent == Players
		and player.UserId == ownerId and sessionIsOpen()
end

local function getState(player)
	return {
		available = Capacity.IsOwner(player),
		limit = limit,
		occupancy = memberCount(),
		maximum = allowedMaximum(),
		revision = revision,
	}
end

local function pushOwnerState()
	local owner = ownerId and Players:GetPlayerByUserId(ownerId)
	if owner then remote:FireClient(owner, "State", getState(owner)) end
end

-- Coalesced writes: no MemoryStore call/yield inside TryAdmit or SetLimit.
-- This shared record is a pre-teleport check only; the destination's local
-- admission table is the FINAL authority, including simultaneous arrivals.
local function queuePublish()
	if RunService:IsStudio() or game.PrivateServerId == "" or ownerId == nil then return end
	publishDirty = true
	if publishing then return end
	publishing = true
	task.defer(function()
		local failures = 0
		while publishDirty and ownerId ~= nil do
			publishDirty = false
			local data = {
				ownerUserId = ownerId,
				privateServerId = game.PrivateServerId,
				jobId = game.JobId,
				limit = limit,
				occupancy = memberCount(),
				open = sessionIsOpen(),
				updatedAt = os.time(),
			}
			local ok, err = pcall(function()
				directory:SetAsync("server_" .. game.PrivateServerId, data, RECORD_TTL)
			end)
			if not ok then
				failures = failures + 1
				warn("[SERVER SIZE] Capacity publication failed: " .. tostring(err))
				if failures >= 3 then break end
				publishDirty = true
				task.wait(failures)
			else
				failures = 0
			end
		end
		publishing = false -- periodic refresh retries if the service was unavailable.
	end)
end

local function changed()
	revision = revision + 1
	workspace:SetAttribute("ParkourCreatorPlayerLimit", limit)
	workspace:SetAttribute("ParkourCreatorPlayerCount", memberCount())
	workspace:SetAttribute("ParkourCreatorPlaceMaximum", allowedMaximum())
	pushOwnerState()
	queuePublish()
end

function Capacity.Initialize(owner)
	if not owner or owner.Parent ~= Players then return false end
	if ownerId ~= nil then return ownerId == owner.UserId and not closed end
	ownerId = owner.UserId
	closed = false
	local maximum = allowedMaximum()
	limit = math.clamp(DEFAULT_LIMIT or maximum, 1, maximum)
	members[owner.UserId] = owner
	owner:SetAttribute("ParkourCreatorCapacityAdmitted", true)
	-- On a script restart, retain guests already admitted to this session.
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= owner and player:GetAttribute("ParkourCreatorGuest") == true
			and tonumber(player:GetAttribute("ParkourCreatorOwnerUserId")) == owner.UserId then
			members[player.UserId] = player
			player:SetAttribute("ParkourCreatorCapacityAdmitted", true)
		end
	end
	limit = math.min(maximum, math.max(limit, memberCount()))
	changed()
	return true
end

function Capacity.HasRoom(ownerUserId)
	if ownerUserId ~= ownerId or not sessionIsOpen() then
		return false, "This Creator session is no longer accepting guests."
	end
	if memberCount() >= limit then
		return false, string.format("Your server is full (%d/%d). Increase SERVER SIZE or wait for someone to leave.", memberCount(), limit)
	end
	return true
end

function Capacity.TryAdmit(player)
	if not player or player.Parent ~= Players then return false, "Player has left." end
	if members[player.UserId] == player then return true end
	if not sessionIsOpen() then return false, "The Creator has left this server." end
	if memberCount() >= limit then return false, "This Creator server is full. Please try again later." end
	-- No yield between the count check and the insertion: two simultaneous
	-- arrivals cannot claim the same final space in THIS server instance.
	members[player.UserId] = player
	player:SetAttribute("ParkourCreatorCapacityAdmitted", true)
	changed()
	return true
end

function Capacity.Remove(player)
	if not player then return end
	local hadMember = members[player.UserId] ~= nil
	members[player.UserId] = nil
	if player.UserId == ownerId then closed = true end
	if hadMember then changed() end
end

function Capacity.Close()
	if ownerId == nil or closed then return end
	closed = true
	changed()
end

function Capacity.SetLimit(player, value)
	if not Capacity.IsOwner(player) then return false, "Only the Creator owner can change the server size." end
	local maximum = allowedMaximum()
	if not isInteger(value) or value < 1 or value > maximum then
		return false, string.format("Choose a whole number from 1 to %d.", maximum)
	end
	local occupancy = memberCount()
	if value < occupancy then
		return false, string.format("%d players are already inside. Choose at least %d; nobody will be kicked.", occupancy, occupancy)
	end
	if limit ~= value then limit = value; changed() end
	return true, string.format("Server size set to %d players, including you.", limit)
end

function Capacity.CheckRemoteSession(session)
	if type(session) ~= "table" then return false, "Creator routing information is unavailable." end
	local expectedOwner = tonumber(session.ownerUserId)
	if expectedOwner == ownerId then return Capacity.HasRoom(expectedOwner) end
	if RunService:IsStudio() then return false, "Create the Studio owner session before accepting an invite." end
	local privateId = session.privateServerId
	if type(privateId) ~= "string" or privateId == "" then
		return false, "Creator capacity information is unavailable. Please try again."
	end
	local ok, data = pcall(function()
		return directory:GetAsync("server_" .. privateId)
	end)
	if not ok or type(data) ~= "table" then
		return false, "Could not check the Creator server size. Please ask for another invitation."
	end
	if tonumber(data.ownerUserId) ~= expectedOwner or data.open ~= true
		or os.time() - (tonumber(data.updatedAt) or 0) > STALE_AFTER then
		return false, "That Creator server is unavailable or is no longer accepting guests."
	end
	local maximum = tonumber(data.limit)
	local count = tonumber(data.occupancy)
	if not maximum or not count then return false, "Creator capacity information is unavailable." end
	if count >= maximum then return false, "That Creator server is full. Ask the owner to increase SERVER SIZE." end
	return true
end

function Capacity.Notify(player, title, message)
	if player and player.Parent == Players then
		remote:FireClient(player, "Notice", tostring(title), tostring(message))
	end
end

remote.OnServerEvent:Connect(function(player, action, value)
	if action ~= "Get" and action ~= "Apply" then return end
	local now = os.clock()
	if now - (requestTimes[player] or -math.huge) < 0.15 then
		if action == "Apply" then remote:FireClient(player, "Result", false, "Please wait briefly and try again.", getState(player)) end
		return
	end
	requestTimes[player] = now
	if action == "Get" then
		remote:FireClient(player, "State", getState(player))
	else
		local ok, message = Capacity.SetLimit(player, value)
		remote:FireClient(player, "Result", ok, message, getState(player))
	end
end)

Players.PlayerRemoving:Connect(function(player)
	requestTimes[player] = nil
	Capacity.Remove(player)
end)

task.spawn(function()
	while true do
		task.wait(REFRESH_SECONDS)
		if ownerId ~= nil then queuePublish() end
	end
end)

game:BindToClose(function()
	if ownerId == nil or RunService:IsStudio() or game.PrivateServerId == "" then return end
	-- Write a closed record, rather than deleting an unrelated session record.
	pcall(function()
		directory:SetAsync("server_" .. game.PrivateServerId, {
			ownerUserId = ownerId, privateServerId = game.PrivateServerId,
			limit = limit, occupancy = 0, open = false, updatedAt = os.time(),
		}, RECORD_TTL)
	end)
end)

return Capacity

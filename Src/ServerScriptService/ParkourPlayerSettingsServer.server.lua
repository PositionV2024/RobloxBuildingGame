-- ServerScriptService > ParkourPlayerSettingsServer
-- Persistent settings for Builder preferences that are not keybindings.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local DSS=game:GetService("DataStoreService")

local store=DSS:GetDataStore("ParkourPlayerSettings_V1")

local event=RS:FindFirstChild("ParkourPlayerSettingsEvent") or Instance.new("RemoteEvent")
event.Name="ParkourPlayerSettingsEvent"
event.Parent=RS

local get=RS:FindFirstChild("ParkourPlayerSettingsGet") or Instance.new("RemoteFunction")
get.Name="ParkourPlayerSettingsGet"
get.Parent=RS

local cache={}
local lastSave={}
local SAVE_COOLDOWN=2

local DEFAULTS={
	AutoSaveInterval=60,
	SelectRange=45,
}

local function sanitize(data)
	if type(data)~="table" then
		return {
			AutoSaveInterval=DEFAULTS.AutoSaveInterval,
			SelectRange=DEFAULTS.SelectRange,
		}
	end

	return {
		AutoSaveInterval=math.clamp(
			math.round(tonumber(data.AutoSaveInterval) or DEFAULTS.AutoSaveInterval),
			30,300
		),
		SelectRange=math.clamp(
			math.round(tonumber(data.SelectRange) or DEFAULTS.SelectRange),
			15,100
		),
	}
end

local function load(player)
	if cache[player] then return cache[player] end

	local ok,data=pcall(function()
		return store:GetAsync("settings_"..player.UserId)
	end)

	cache[player]=sanitize(ok and data or nil)
	return cache[player]
end

local function save(player,data)
	local clean=sanitize(data)
	cache[player]=clean

	local ok,err=pcall(function()
		store:SetAsync("settings_"..player.UserId,clean)
	end)

	if not ok then
		warn("[PLAYER SETTINGS] Save failed for "..player.Name..": "..tostring(err))
	end

	return ok
end

get.OnServerInvoke=function(player)
	return load(player)
end

event.OnServerEvent:Connect(function(player,action,data)
	if action~="Save" then return end

	local now=os.clock()
	if now-(lastSave[player] or -SAVE_COOLDOWN)<SAVE_COOLDOWN then return end
	lastSave[player]=now

	save(player,data)
end)

Players.PlayerRemoving:Connect(function(player)
	-- Save the latest cached values once more on leave.
	if cache[player] then
		save(player,cache[player])
	end
	cache[player]=nil
	lastSave[player]=nil
end)

game:BindToClose(function()
	for _,player in ipairs(Players:GetPlayers()) do
		if cache[player] then
			pcall(function()
				store:SetAsync("settings_"..player.UserId,cache[player])
			end)
		end
	end
end)

print("? Parkour Player Settings Server V1 loaded")

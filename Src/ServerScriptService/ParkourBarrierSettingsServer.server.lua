-- ParkourBarrierSettingsServer V4.1 - EXPLICIT GLOBAL SCOPE
-- ServerScriptService
--
-- OWNER:
--   Loads/saves their ParkourBarrierSettings_V1 data.
--   APPLY immediately broadcasts the sanitized barrier state to every guest.
--
-- GUEST:
--   Cannot save/change barrier settings.
--   Receives the owner's current live barrier state when joining/requesting it.
--
-- This remains separate from plot drafts and keybind DataStores.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local DataStoreService=game:GetService("DataStoreService")
local RunService=game:GetService("RunService")

-- DataStore: ParkourBarrierSettings_V1
-- Scope: global | Key: barrier_<owner UserId>
-- Combined reference: global/barrier_<owner UserId>.
-- Do NOT include "global/" in GetAsync/SetAsync keys: the scope supplies it.
-- The previous script used this same scope implicitly. No migration is needed.
local Store=DataStoreService:GetDataStore("ParkourBarrierSettings_V1","global")

local remote=RS:FindFirstChild("ParkourBarrierSettingsEvent")
if not remote then
	remote=Instance.new("RemoteEvent")
	remote.Name="ParkourBarrierSettingsEvent"
	remote.Parent=RS
end

local DEFAULTS={Style="DEFAULT",Color="BLUE",Glow=.25,Speed=5,Spacing=8,TrailCount=4,Direction="RIGHT",Facing="RIGHT",WaveAmplitude=1.8}
local STYLES={DEFAULT=true,PULSE_WAVE=true}
local COLORS={BLUE=true,CYAN=true,GREEN=true,PURPLE=true,PINK=true,RED=true,ORANGE=true,GOLD=true,WHITE=true}
local FOUR_WAY={UP=true,DOWN=true,LEFT=true,RIGHT=true}
local cache={}
local saving={}
local liveSessionSettings=nil
local liveOwnerUserId=nil

local function copyDefaults() local t={} for k,v in pairs(DEFAULTS) do t[k]=v end return t end
local function copyTable(source) local t={} for k,v in pairs(source or {}) do t[k]=v end return t end

local function sanitize(data)
	data=type(data)=="table" and data or {}
	local clean=copyDefaults()

	-- Backward compatible: old records do not have Style, so they remain DEFAULT.
	local style=tostring(data.Style or "DEFAULT"):upper()
	if STYLES[style] then clean.Style=style end

	local color=tostring(data.Color or ""):upper()
	if COLORS[color] then clean.Color=color end
	clean.Glow=math.clamp(tonumber(data.Glow) or clean.Glow,0,1)
	clean.Speed=math.clamp(tonumber(data.Speed) or clean.Speed,1,15)
	clean.Spacing=math.clamp(math.round(tonumber(data.Spacing) or clean.Spacing),4,20)
	clean.TrailCount=math.clamp(math.round(tonumber(data.TrailCount) or clean.TrailCount),0,8)
	clean.WaveAmplitude=math.clamp(tonumber(data.WaveAmplitude) or clean.WaveAmplitude,.5,3)
	local direction=tostring(data.Direction or ""):upper()
	if FOUR_WAY[direction] then clean.Direction=direction end
	local facing=tostring(data.Facing or ""):upper()
	if FOUR_WAY[facing] then clean.Facing=facing end
	return clean
end

local function isOwner(player)
	if RunService:IsStudio() and player:GetAttribute("ParkourCreatorGuest")~=true then return true end
	local workspaceOwner=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))
	if workspaceOwner and workspaceOwner==player.UserId then return true end
	return player:GetAttribute("ParkourCreatorOwner")==true
		and player:GetAttribute("ParkourPrivateCreator")==true
end

local function isCollaborator(player)
	return player:GetAttribute("ParkourCreatorGuest")==true
		and player:GetAttribute("ParkourGuestPermissionRole")=="Collaborator"
		and player:GetAttribute("ParkourCanCollaborate")==true
end

local function load(player)
	if cache[player] then return cache[player] end
	local ok,data=pcall(function() return Store:GetAsync("barrier_"..tostring(player.UserId)) end)
	if not ok then
		warn("[BARRIER SETTINGS] Load failed for "..player.Name..": "..tostring(data))
		data=copyDefaults()
	end
	cache[player]=sanitize(data)
	return cache[player]
end

local function broadcastSession(exceptPlayer)
	if not liveSessionSettings then return end
	for _,other in ipairs(Players:GetPlayers()) do
		if other~=exceptPlayer then
			remote:FireClient(other,"SessionUpdated",copyTable(liveSessionSettings))
		end
	end
end

local function applyLiveCollaborator(player,data)
	if not isCollaborator(player) then
		warn("[BARRIER SETTINGS] Rejected guest change from "..player.Name)
		return false
	end
	if not liveSessionSettings then return false end

	local clean=sanitize(data)
	liveSessionSettings=copyTable(clean)
	broadcastSession(player)
	remote:FireClient(player,"SessionUpdated",copyTable(clean))
	print("[BARRIER SETTINGS] Collaborator "..player.Name.." changed live session settings")
	return true
end

local function saveOwner(player,data)
	if not isOwner(player) then
		-- Collaborators may modify the live reserved-session barrier, but
		-- they never write to the owner's personal DataStore.
		if isCollaborator(player) then
			return applyLiveCollaborator(player,data)
		end
		warn("[BARRIER SETTINGS] Rejected non-owner save from "..player.Name)
		return false
	end
	if saving[player] then return false end
	saving[player]=true

	local clean=sanitize(data)
	cache[player]=clean
	liveOwnerUserId=player.UserId
	liveSessionSettings=copyTable(clean)
	broadcastSession(player)

	local ok,err=pcall(function()
		Store:SetAsync("barrier_"..tostring(player.UserId),clean)
	end)
	saving[player]=nil

	if not ok then
		warn("[BARRIER SETTINGS] Save failed for "..player.Name..": "..tostring(err))
		return false
	end
	print("[BARRIER SETTINGS] Saved + synced for "..player.Name
		.." | ParkourBarrierSettings_V1 | global/barrier_"..tostring(player.UserId))
	return true
end

remote.OnServerEvent:Connect(function(player,action,data)
	if action=="Load" then
		if not isOwner(player) and workspace:GetAttribute("ParkourPrivateCreatorServer")==true then
			for _=1,20 do task.wait(.05) if isOwner(player) then break end end
		end
		if not isOwner(player) then
			if liveSessionSettings then remote:FireClient(player,"SessionUpdated",copyTable(liveSessionSettings)) end
			return
		end
		local loaded=load(player)
		liveOwnerUserId=player.UserId
		liveSessionSettings=copyTable(loaded)
		remote:FireClient(player,"Loaded",copyTable(loaded))
		broadcastSession(player)

	elseif action=="LoadSession" then
		if liveSessionSettings then remote:FireClient(player,"SessionUpdated",copyTable(liveSessionSettings)) end

	elseif action=="Save" then
		saveOwner(player,data)
	end
end)

local function watchPlayer(player)
	player:GetAttributeChangedSignal("ParkourCreatorGuest"):Connect(function()
		if player:GetAttribute("ParkourCreatorGuest")==true and liveSessionSettings then
			remote:FireClient(player,"SessionUpdated",copyTable(liveSessionSettings))
		end
	end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _,player in ipairs(Players:GetPlayers()) do watchPlayer(player) end

Players.PlayerRemoving:Connect(function(player)
	cache[player]=nil
	saving[player]=nil
	if player.UserId==liveOwnerUserId then
		liveOwnerUserId=nil
		-- Keep the last live state visible to remaining guests after owner leaves.
	end
end)

print("? ParkourBarrierSettingsServer V4.1 explicit global scope loaded")

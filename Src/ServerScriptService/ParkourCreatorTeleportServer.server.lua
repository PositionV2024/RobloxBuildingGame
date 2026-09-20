-- ParkourCreatorTeleportServer V4
-- ServerScriptService
--
-- Explicitly reserves Creator server and registers its routing information
-- in MemoryStore so invited players can later be routed to the SAME server.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local TeleportService=game:GetService("TeleportService")
local RunService=game:GetService("RunService")

local Registry=require(script.Parent:WaitForChild("ParkourCreatorSessionRegistry"))

local remote=RS:FindFirstChild("ParkourCreatePrivateServer") or Instance.new("RemoteEvent")
remote.Name="ParkourCreatePrivateServer"
remote.Parent=RS

local busy={}

local function studio(player)
	player:SetAttribute("ParkourPrivateCreator",true)
	player:SetAttribute("ParkourLoadSavedDraft",true)
	remote:FireClient(player,"StudioCreatorReady")
	busy[player]=nil
	print("[STUDIO CREATOR] CREATE pressed -> simulation started")
end

local function create(player)
	local ok,accessCode,privateServerId=pcall(function()
		return TeleportService:ReserveServerAsync(game.PlaceId)
	end)

	if not ok then
		busy[player]=nil
		warn("[CREATOR RESERVE] "..tostring(accessCode))
		remote:FireClient(player,"Failed","Could not reserve your Creator server.")
		return
	end

	if not Registry.Register(player.UserId,accessCode,privateServerId) then
		busy[player]=nil
		remote:FireClient(player,"Failed","Could not register your Creator session.")
		return
	end

	local options=Instance.new("TeleportOptions")
	options.ReservedServerAccessCode=accessCode
	options:SetTeleportData({
		ParkourCreatorSession=true,
		CreatorUserId=player.UserId,
		LoadSavedDraft=true,
		SessionRole="Owner",
	})

	local teleported,err=pcall(function()
		TeleportService:TeleportAsync(game.PlaceId,{player},options)
	end)

	if not teleported then
		Registry.Remove(player.UserId)
		busy[player]=nil
		warn("[CREATOR TELEPORT] "..tostring(err))
		remote:FireClient(player,"Failed","Could not open your Creator server.")
	end
end

remote.OnServerEvent:Connect(function(player,action)
	if action~="Create" or busy[player] then return end
	busy[player]=true
	if RunService:IsStudio() then
		studio(player)
	else
		create(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	busy[player]=nil
end)

print("? ParkourCreatorTeleportServer V4 registry enabled")

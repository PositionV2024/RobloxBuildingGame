-- ParkourReturnToPublicServer V1
-- Put in ServerScriptService.
-- Returns the Creator OWNER from their reserved Creator server to a normal
-- server of the same Place. Studio uses a local simulation instead.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local TeleportService=game:GetService("TeleportService")
local RunService=game:GetService("RunService")

local remote=RS:FindFirstChild("ParkourReturnToPublicServer")
if not remote then
	remote=Instance.new("RemoteEvent")
	remote.Name="ParkourReturnToPublicServer"
	remote.Parent=RS
end

local busy={}

local function isCreatorOwner(player)
	if RunService:IsStudio() then
		return player:GetAttribute("ParkourPrivateCreator")==true
			or player:GetAttribute("ParkourCreatorOwner")==true
	end

	local ownerId=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))
	return ownerId==player.UserId
		and player:GetAttribute("ParkourCreatorOwner")==true
end

remote.OnServerEvent:Connect(function(player,action)
	if action~="Return" and action~="GuestReturn" then return end
	if busy[player] then return end

	local ownerReturn=(action=="Return")
	local guestReturn=(action=="GuestReturn")

	if ownerReturn and not isCreatorOwner(player) then
		remote:FireClient(player,"Failed","Only the Creator server owner can return this way.")
		return
	end

	if guestReturn and player:GetAttribute("ParkourCreatorGuest")~=true then
		remote:FireClient(player,"Failed","You are not a guest in a Creator server.")
		return
	end

	busy[player]=true

	-- Studio cannot perform the real reserved -> public server flow reliably.
	if RunService:IsStudio() then
		player:SetAttribute("ParkourPrivateCreator",false)
		player:SetAttribute("ParkourCreatorOwner",false)
		player:SetAttribute("ParkourCreatorGuest",false)
		player:SetAttribute("ParkourLoadSavedDraft",false)

		if ownerReturn then
			workspace:SetAttribute("ParkourPrivateCreatorServer",false)
			workspace:SetAttribute("ParkourCreatorOwnerUserId",nil)
		end

		remote:FireClient(player,"StudioReturned")
		busy[player]=nil
		print("[RETURN PUBLIC] Studio return simulation completed for "..player.Name)
		return
	end

	-- Normal teleport to the same PlaceId, WITHOUT a reserved-server access code.
	-- This leaves the private Creator instance and joins an available public server.
	local options=Instance.new("TeleportOptions")
	options:SetTeleportData({
		ParkourReturnToDiscover=true
	})

	local ok,err=pcall(function()
		TeleportService:TeleportAsync(
			game.PlaceId,
			{player},
			options
		)
	end)

	if not ok then
		busy[player]=nil
		warn("[RETURN PUBLIC] Teleport failed for "..player.Name..": "..tostring(err))
		remote:FireClient(player,"Failed",tostring(err))
	end
end)

Players.PlayerRemoving:Connect(function(player)
	busy[player]=nil
end)

print("? ParkourReturnToPublicServer V1 loaded")

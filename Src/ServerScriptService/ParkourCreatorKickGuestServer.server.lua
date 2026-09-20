-- ParkourCreatorKickGuestServer V2 - TRANSITION RETURN
-- ServerScriptService
-- Owner requests removal -> guest sees transition -> server returns guest to public server.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local TeleportService=game:GetService("TeleportService")
local RunService=game:GetService("RunService")

local remote=RS:FindFirstChild("ParkourCreatorKickGuestEvent")
if not remote then
	remote=Instance.new("RemoteEvent")
	remote.Name="ParkourCreatorKickGuestEvent"
	remote.Parent=RS
end

local busy={}

local function isCreatorOwner(player)
	local ownerId=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))
	if ownerId then return ownerId==player.UserId end
	return RunService:IsStudio()
		and player:GetAttribute("ParkourPrivateCreator")==true
		and player:GetAttribute("ParkourCreatorGuest")~=true
end

local function returnGuest(target)
	if not target or not target.Parent then return end

	if RunService:IsStudio() then
		target:SetAttribute("ParkourPrivateCreator",false)
		target:SetAttribute("ParkourCreatorGuest",false)
		target:SetAttribute("ParkourCreatorRole",nil)
		target:SetAttribute("ParkourCreatorOwnerUserId",nil)
		remote:FireClient(target,"StudioReturned")
		busy[target.UserId]=nil
		return
	end

	local options=Instance.new("TeleportOptions")
	options:SetTeleportData({
		ParkourReturnToDiscover=true,
		RemovedFromCreatorServer=true,
	})

	local ok,err=pcall(function()
		TeleportService:TeleportAsync(game.PlaceId,{target},options)
	end)

	if not ok then
		warn("[CREATOR KICK] Public return failed: "..tostring(err))
		remote:FireClient(target,"ReturnFailed")
		busy[target.UserId]=nil
	end
end

remote.OnServerEvent:Connect(function(player,value)
	-- Guest tells server its transition is covering the screen.
	if value=="ReturnTransitionReady" then
		if busy[player.UserId] then
			returnGuest(player)
		end
		return
	end

	local targetUserId=tonumber(value)
	if not targetUserId or busy[targetUserId] then return end

	if not isCreatorOwner(player) then
		warn("[CREATOR KICK] Rejected non-owner request from "..player.Name)
		return
	end
	if targetUserId==player.UserId then return end

	local target=Players:GetPlayerByUserId(targetUserId)
	if not target then return end
	if target:GetAttribute("ParkourCreatorGuest")~=true
		and target:GetAttribute("ParkourCreatorRole")~="Collaborator" then
		warn("[CREATOR KICK] "..target.Name.." is not a Creator guest")
		return
	end

	busy[targetUserId]=true
	print("[CREATOR KICK] "..player.Name.." removed guest "..target.Name)

	-- Let the guest cover their screen before teleporting.
	remote:FireClient(target,"PrepareReturnToLobby")

	-- Safety fallback if the client never acknowledges.
	task.delay(4,function()
		if busy[targetUserId] and target.Parent then
			returnGuest(target)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	busy[player.UserId]=nil
end)

print("? ParkourCreatorKickGuestServer V2 transition return loaded")

-- ParkourCreatorGuestPermissionServer V1
-- ServerScriptService
-- Server-authoritative guest role management.
-- Grantable roles: Viewer, Collaborator
-- RemovePermission clears the granted role without removing/kicking the guest.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")

local remote=RS:FindFirstChild("ParkourCreatorGuestPermissionEvent") or Instance.new("RemoteEvent")
remote.Name="ParkourCreatorGuestPermissionEvent"
remote.Parent=RS

local ALLOWED={
	Viewer=true,
	Collaborator=true,
}

local function ownerId()
	return tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))
end

local function isOwner(player)
	local id=ownerId()
	if id then return player.UserId==id end
	return RunService:IsStudio()
		and player:GetAttribute("ParkourPrivateCreator")==true
		and player:GetAttribute("ParkourCreatorGuest")~=true
end

local function isGuest(player)
	return player
		and player.Parent==Players
		and player.UserId~=ownerId()
		and (
			player:GetAttribute("ParkourCreatorGuest")==true
			or player:GetAttribute("ParkourCreatorRole")=="Collaborator"
			or player:GetAttribute("ParkourPrivateCreator")==true
		)
end

local function currentRole(target)
	local role=target:GetAttribute("ParkourGuestPermissionRole")
	if ALLOWED[role] then return role end
	return nil
end

local function sendState(owner,target)
	remote:FireClient(
		owner,
		"RoleState",
		target.UserId,
		currentRole(target)
	)
end

remote.OnServerEvent:Connect(function(player,action,targetUserId,value)
	if action=="RequestRole" then
		if not isOwner(player) then return end
		local target=Players:GetPlayerByUserId(tonumber(targetUserId) or 0)
		if target and isGuest(target) then
			sendState(player,target)
		end
		return
	end

	if action~="SetRole" and action~="RemovePermission" then return end

	if not isOwner(player) then
		warn("[GUEST PERMISSIONS] Rejected non-owner request from "..player.Name)
		return
	end

	local target=Players:GetPlayerByUserId(tonumber(targetUserId) or 0)
	if not target or not isGuest(target) then
		remote:FireClient(player,"PermissionFailed","Guest is no longer in this Creator server.")
		return
	end

	if action=="SetRole" then
		local role=tostring(value or "")
		if not ALLOWED[role] then
			remote:FireClient(player,"PermissionFailed","Invalid guest role.")
			return
		end

		target:SetAttribute("ParkourGuestPermissionRole",role)
		target:SetAttribute("ParkourCanCollaborate",role=="Collaborator")
		target:SetAttribute("ParkourCanViewCreator",true)

		remote:FireClient(target,"YourRoleChanged",role)
		remote:FireClient(player,"PermissionChanged",target.UserId,role,target.Name)
		sendState(player,target)

		print("[GUEST PERMISSIONS] "..player.Name.." set "..target.Name.." to "..role)
	else
		target:SetAttribute("ParkourGuestPermissionRole",nil)
		target:SetAttribute("ParkourCanCollaborate",false)
		target:SetAttribute("ParkourCanViewCreator",true)

		remote:FireClient(target,"YourRoleChanged",nil)
		remote:FireClient(player,"PermissionChanged",target.UserId,nil,target.Name)
		sendState(player,target)

		print("[GUEST PERMISSIONS] "..player.Name.." removed permissions from "..target.Name)
	end
end)

-- Guests start safe: no edit permission until the owner grants Collaborator.
local function initialize(player)
	if player.UserId==ownerId() then return end
	task.defer(function()
		task.wait(.2)
		if player.Parent==Players and isGuest(player) then
			if player:GetAttribute("ParkourGuestPermissionRole")==nil then
				player:SetAttribute("ParkourCanCollaborate",false)
				player:SetAttribute("ParkourCanViewCreator",true)
			end
		end
	end)
end

Players.PlayerAdded:Connect(initialize)
for _,p in ipairs(Players:GetPlayers()) do initialize(p) end

print("? ParkourCreatorGuestPermissionServer V1 loaded")

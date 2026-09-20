-- ParkourCreatorArrivalClient V3 - PERMISSION-AWARE BUILDER UI
-- StarterPlayer > StarterPlayerScripts
--
-- Single controller for Creator arrival + Builder UI visibility.
--
-- OWNER:
--   Enters Creator mode normally and always gets Builder UI.
--
-- GUEST:
--   Viewer / no permission -> Builder UI hidden
--   Collaborator            -> Builder UI shown immediately
--   Permission removed      -> Builder UI hidden immediately
--
-- IMPORTANT:
-- The server remains authoritative. Hiding/showing the UI is only UX;
-- ParkourBuilderServer V7.1 still validates edit permission server-side.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local creatorModeRemote=RS:WaitForChild("ParkourCreatorModeEvent")

local arrived=false
local ownerCreatorEntered=false

local function getBuilder()
	return playerGui:FindFirstChild("ParkourBuilderUI")
end

local function isOwner()
	local workspaceOwner=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))

	if workspaceOwner and workspaceOwner==player.UserId then
		return true
	end

	return player:GetAttribute("ParkourCreatorOwner")==true
		or player:GetAttribute("ParkourCreatorRole")=="Owner"
end

local function isGuest()
	return player:GetAttribute("ParkourCreatorGuest")==true
		or (
			player:GetAttribute("ParkourCreatorRole")=="Collaborator"
			and not isOwner()
		)
end

local function canGuestBuild()
	return isGuest()
		and player:GetAttribute("ParkourGuestPermissionRole")=="Collaborator"
		and player:GetAttribute("ParkourCanCollaborate")==true
end

local function updateBuilderUI()
	local builder=getBuilder()
	if not builder then return end

	-- IMPORTANT:
	-- Never let guest-permission changes hide the OWNER'S tools.
	-- Owner wins before every other role/permission check.
	if isOwner()
		or player:GetAttribute("ParkourCreatorOwner")==true then
		builder.Enabled=true
		return
	end

	-- Only an EXPLICIT guest is controlled by guest permissions.
	-- Do not disable BuilderUI for an unknown/in-between attribute state,
	-- because Creator attributes can replicate at slightly different times.
	if player:GetAttribute("ParkourCreatorGuest")==true then
		builder.Enabled=canGuestBuild()
		return
	end

	-- Not an explicit guest: leave the existing Builder UI state alone.
	-- This prevents another player's permission update / replication race
	-- from hiding the Creator owner's tools.
end

local function hideDiscover()
	local discover=playerGui:FindFirstChild("ParkourDiscoverUI")
	if discover then
		discover.Enabled=false
	end
end

local function enterPrivateCreator()
	if player:GetAttribute("ParkourPrivateCreator")~=true
		and player:GetAttribute("ParkourCreatorGuest")~=true then
		return
	end

	if not arrived then
		arrived=true
		hideDiscover()

		print(
			"✓ Private Creator session detected | Role: "
				..tostring(player:GetAttribute("ParkourCreatorRole") or
					(isOwner() and "Owner" or "Guest"))
		)
	end

	-- Only the OWNER enters the existing owner Creator/draft flow.
	-- Guests must never trigger owner-style draft loading.
	if isOwner() and not ownerCreatorEntered then
		ownerCreatorEntered=true
		creatorModeRemote:FireServer("EnterCreator")
	end

	-- Owner always sees tools.
	-- Guest sees them only after explicit Collaborator permission.
	updateBuilderUI()
end

local function permissionChanged()
	enterPrivateCreator()
	updateBuilderUI()

	if isGuest() then
		local role=player:GetAttribute("ParkourGuestPermissionRole")
		if role=="Collaborator"
			and player:GetAttribute("ParkourCanCollaborate")==true then
			print("✓ Guest Builder UI enabled | Collaborator")
		else
			print("✓ Guest Builder UI disabled | "..tostring(role or "No Permission"))
		end
	end
end

-- Creator/session identity can arrive asynchronously.
player:GetAttributeChangedSignal("ParkourPrivateCreator"):Connect(permissionChanged)
player:GetAttributeChangedSignal("ParkourCreatorOwner"):Connect(permissionChanged)
player:GetAttributeChangedSignal("ParkourCreatorGuest"):Connect(permissionChanged)
player:GetAttributeChangedSignal("ParkourCreatorRole"):Connect(permissionChanged)

-- Permission changes happen live while the guest is already in the server.
player:GetAttributeChangedSignal("ParkourGuestPermissionRole"):Connect(permissionChanged)
player:GetAttributeChangedSignal("ParkourCanCollaborate"):Connect(permissionChanged)

-- If PlayerGui recreates the Builder UI after this script starts,
-- immediately apply the correct permission state to the new instance.
playerGui.ChildAdded:Connect(function(child)
	if child.Name=="ParkourBuilderUI" then
		task.defer(updateBuilderUI)
	end
end)

-- Initial state may already be present before this LocalScript runs.
task.defer(function()
	task.wait(.1)
	enterPrivateCreator()
	updateBuilderUI()
end)

print("✓ ParkourCreatorArrivalClient V3.1 owner-safe permission UI loaded")

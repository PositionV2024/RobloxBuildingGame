-- ParkourCreatorArrivalServer V5.6 - SERVER CAPACITY + VIEWER DEFAULT + GUEST STAY
-- ServerScriptService
--
-- Fixes the V5.4 nil-call bug:
--   * notifySessionActivity is defined BEFORE setupPlayer uses it.
--   * removeFromClosedSession is defined BEFORE setupPlayer uses it.
--
-- Owner leaves:
--   * Existing guests stay.
--   * Existing guests receive OWNER LEFT.
--   * New arrivals after closure are returned to a public server.
--
-- Role rules:
--   * Owner gets clean Owner state.
--   * New guests start Viewer/no build permission.
--   * Collaborator must be explicitly granted later.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local RS=game:GetService("ReplicatedStorage")
local TeleportService=game:GetService("TeleportService")
local Capacity=require(script.Parent:WaitForChild("ParkourCreatorCapacity"))
local returningOverflow={}


local ownerLeftRemote=RS:FindFirstChild("ParkourCreatorOwnerLeftEvent") or Instance.new("RemoteEvent")
ownerLeftRemote.Name="ParkourCreatorOwnerLeftEvent"
ownerLeftRemote.Parent=RS

local activityRemote=RS:FindFirstChild("ParkourCreatorSessionActivityEvent") or Instance.new("RemoteEvent")
activityRemote.Name="ParkourCreatorSessionActivityEvent"
activityRemote.Parent=RS

local creatorServerConfirmed=false
local creatorOwnerUserId=nil
local sessionClosing=false

local function markPublic(player)
	player:SetAttribute("ParkourPrivateCreator",false)
	player:SetAttribute("ParkourCreatorOwner",false)
	player:SetAttribute("ParkourCreatorGuest",false)
	player:SetAttribute("ParkourCreatorRole",nil)
	player:SetAttribute("ParkourCreatorOwnerUserId",nil)

	player:SetAttribute("ParkourGuestPermissionRole",nil)
	player:SetAttribute("ParkourCanCollaborate",false)
	player:SetAttribute("ParkourCanViewCreator",false)

	player:SetAttribute("ParkourLoadSavedDraft",false)
end

local function markOwner(player,loadSavedDraft)
	-- Clear stale guest/collaborator state from an older session.
	player:SetAttribute("ParkourCreatorGuest",false)
	player:SetAttribute("ParkourGuestPermissionRole",nil)
	player:SetAttribute("ParkourCanCollaborate",false)
	player:SetAttribute("ParkourCanViewCreator",false)

	-- Establish fresh owner state.
	player:SetAttribute("ParkourPrivateCreator",true)
	player:SetAttribute("ParkourCreatorOwner",true)
	player:SetAttribute("ParkourCreatorOwnerUserId",player.UserId)
	player:SetAttribute("ParkourCreatorRole","Owner")

	if loadSavedDraft~=nil then
		player:SetAttribute("ParkourLoadSavedDraft",loadSavedDraft==true)
	end
end

local function markGuest(player)
	-- A new guest is NEVER a Collaborator by default.
	player:SetAttribute("ParkourCreatorOwner",false)
	player:SetAttribute("ParkourPrivateCreator",true)
	player:SetAttribute("ParkourCreatorGuest",true)

	player:SetAttribute("ParkourGuestPermissionRole",nil)
	player:SetAttribute("ParkourCanCollaborate",false)
	player:SetAttribute("ParkourCanViewCreator",true)
	player:SetAttribute("ParkourCreatorRole","Viewer")
	player:SetAttribute("ParkourLoadSavedDraft",false)

	-- This identifies which owner's session the guest belongs to.
	player:SetAttribute("ParkourCreatorOwnerUserId",creatorOwnerUserId)
end

-- IMPORTANT: defined before setupPlayer.
local function notifySessionActivity(action,guest)
	for _,other in ipairs(Players:GetPlayers()) do
		if other~=guest and other:GetAttribute("ParkourPrivateCreator")==true then
			activityRemote:FireClient(
				other,
				action,
				guest.UserId,
				guest.Name,
				guest.DisplayName
			)
		end
	end
end

-- IMPORTANT: defined before setupPlayer.
local function removeFromClosedSession(player,reason)
	-- Existing guests are allowed to remain. This function is only called
	-- for a NEW PlayerAdded after the owner has already left.
	if not player or player.Parent~=Players or returningOverflow[player] then return end
	returningOverflow[player]=true
	local message=reason or "This Creator session has ended. Returning to Discover."
	-- Keep a rejected arrival read-only during its brief public-return transfer.
	-- Do not turn it into a non-guest while it is still in this Creator server.
	markGuest(player)
	player:SetAttribute("ParkourCreatorCapacityAdmitted",false)
	player:SetAttribute("ParkourCreatorAdmissionMessage",message)
	Capacity.Notify(player,"CANNOT JOIN",message)

	if RunService:IsStudio() then
		warn("[CREATOR] New arrival rejected because Creator session is closed: "..player.Name)
		return
	end

	local options=Instance.new("TeleportOptions")
	options:SetTeleportData({
		ParkourReturnToDiscover=true,
		CreatorSessionClosed=reason==nil,
		CreatorServerFull=reason~=nil,
		CreatorCapacityReturn=true,
	})

	local ok,err=pcall(function()
		TeleportService:TeleportAsync(game.PlaceId,{player},options)
	end)

	if not ok then
		warn("[CREATOR] Could not return late arrival to public server: "..tostring(err))
		-- Only this rejected NEW arrival is disconnected if the return fails.
		-- Existing admitted guests are never removed to enforce a lower limit.
		player:Kick(message.." Please rejoin from Discover.")
	end
end

-- Catch failures reported AFTER TeleportAsync initially succeeded.
TeleportService.TeleportInitFailed:Connect(function(player,result,errorMessage,placeId,options)
	if not returningOverflow[player] or not options then return end
	local ok,data=pcall(function() return options:GetTeleportData() end)
	if not ok or type(data)~="table" or data.CreatorCapacityReturn~=true then return end
	warn("[CREATOR] Rejected-arrival return did not start: "..tostring(errorMessage))
	if player.Parent==Players then
		player:Kick("Unable to join this Creator server or return to Discover. Please rejoin.")
	end
end)

local function setupPlayer(player)
	-- Studio keeps its existing CREATE simulation. A hook below registers
	-- the simulated owner after CREATE; accepting a guest claims a seat there.
	if RunService:IsStudio() then
		if player:GetAttribute("ParkourPrivateCreator")~=true then markPublic(player) end
		return
	end

	-- Owner already left: reject only NEW arrivals.
	if sessionClosing then
		removeFromClosedSession(player)
		return
	end

	local joinData=player:GetJoinData()
	local data=joinData and joinData.TeleportData

	local validCreatorOwnerArrival=
		type(data)=="table"
		and data.ParkourCreatorSession==true
		and tonumber(data.CreatorUserId)==player.UserId

	-- First valid CREATE arrival establishes this reserved Creator server.
	if not creatorServerConfirmed then
		if validCreatorOwnerArrival then
			creatorServerConfirmed=true
			creatorOwnerUserId=player.UserId

			workspace:SetAttribute("ParkourPrivateCreatorServer",true)
			workspace:SetAttribute("ParkourCreatorOwnerUserId",creatorOwnerUserId)
			workspace:SetAttribute("ParkourCreatorSessionClosing",false)
			workspace:SetAttribute("ParkourCreatorOwnerPresent",true)

			Capacity.Initialize(player)
			markOwner(player,data.LoadSavedDraft==true)

			print("? Creator server established by "..player.Name)
			return
		end

		-- A guest who reaches a reserved instance before its owner is established
		-- must not be treated as a public creator or bypass the admission check.
		if game.PrivateServerId~="" and type(data)=="table"
			and data.ParkourCreatorSession==true then
			removeFromClosedSession(player,"The Creator server is not ready. Please request another invitation.")
			return
		end
		-- Ordinary public server.
		markPublic(player)
		return
	end

	-- Confirmed Creator server: owner reconnect/arrival.
	if player.UserId==creatorOwnerUserId then
		markOwner(
			player,
			type(data)=="table" and data.LoadSavedDraft==true
		)
		return
	end

	-- Final, non-yielding admission gate. Do this BEFORE giving a guest its role.
	local admitted,reason=Capacity.TryAdmit(player)
	if not admitted then
		removeFromClosedSession(player,reason)
		return
	end

	-- Every invited arrival starts safely as Viewer.
	-- PermissionServer may promote them later.
	markGuest(player)

	task.defer(function()
		if player.Parent==Players then
			notifySessionActivity("GuestJoined",player)
		end
	end)
end

local function closeCreatorSession(owner)
	if sessionClosing then return end
	sessionClosing=true

	-- Existing guests stay in this reserved server.
	Capacity.Close()
	workspace:SetAttribute("ParkourCreatorSessionClosing",true)
	workspace:SetAttribute("ParkourCreatorOwnerPresent",false)

	print("[CREATOR] Owner "..owner.Name.." left - existing guests remain")

	task.defer(function()
		for _,other in ipairs(Players:GetPlayers()) do
			if other~=owner then
				ownerLeftRemote:FireClient(other,owner.UserId,owner.Name)
			end
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

Players.PlayerRemoving:Connect(function(player)
	returningOverflow[player]=nil
	if creatorServerConfirmed
		and creatorOwnerUserId
		and player.UserId==creatorOwnerUserId then

		closeCreatorSession(player)
		return
	end

	if player:GetAttribute("ParkourCreatorGuest")==true
		and player:GetAttribute("ParkourCreatorCapacityAdmitted")==true then
		notifySessionActivity("GuestLeft",player)
	end
end)

-- Studio-only bridge for the existing simulated CREATE button.
-- In a published reserved server, the normal arrival path above owns setup.
if RunService:IsStudio() then
	local function watchStudioPlayer(player)
		local function identifyStudioOwner()
			if creatorServerConfirmed or player.Parent~=Players then return end
			if player:GetAttribute("ParkourPrivateCreator")~=true then return end
			if player:GetAttribute("ParkourCreatorGuest")==true then return end
			local role=player:GetAttribute("ParkourCreatorRole")
			if role=="Collaborator" or role=="Viewer" then return end
			local existingOwner=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))
			if existingOwner and existingOwner~=player.UserId then return end
			creatorServerConfirmed=true
			creatorOwnerUserId=player.UserId
			workspace:SetAttribute("ParkourPrivateCreatorServer",true)
			workspace:SetAttribute("ParkourCreatorOwnerUserId",player.UserId)
			workspace:SetAttribute("ParkourCreatorOwnerPresent",true)
			workspace:SetAttribute("ParkourCreatorSessionClosing",false)
			Capacity.Initialize(player)
			markOwner(player,player:GetAttribute("ParkourLoadSavedDraft")==true)
		end
		player:GetAttributeChangedSignal("ParkourPrivateCreator"):Connect(identifyStudioOwner)
		player:GetAttributeChangedSignal("ParkourCreatorOwner"):Connect(identifyStudioOwner)
		task.defer(identifyStudioOwner)
	end
	Players.PlayerAdded:Connect(watchStudioPlayer)
	for _,player in ipairs(Players:GetPlayers()) do watchStudioPlayer(player) end
end

-- Script-restart safety.
for _,player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer,player)
end

print("[CREATOR] ArrivalServer V5.6 capacity admission loaded")

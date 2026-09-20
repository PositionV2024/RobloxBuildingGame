-- ParkourCreatorInviteServer V4.7 - SHARED TIMED INVITES + CAPACITY CHECKS
-- ServerScriptService
--
-- Invitation expiry is stored in ParkourCreatorSessionRegistry (MemoryStore),
-- so Owner and Recipient can be in DIFFERENT Roblox servers.
--
-- No local active={} table is used as authority.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local TeleportService=game:GetService("TeleportService")
local RunService=game:GetService("RunService")
local MessagingService=game:GetService("MessagingService")

local Registry=require(script.Parent:WaitForChild("ParkourCreatorSessionRegistry"))
local Capacity=require(script.Parent:WaitForChild("ParkourCreatorCapacity"))
local accepting={} -- duplicate ACCEPT requests cannot start multiple teleports.


local remote=RS:FindFirstChild("ParkourCreatorInviteEvent") or Instance.new("RemoteEvent")
remote.Name="ParkourCreatorInviteEvent"
remote.Parent=RS

local TOPIC="ParkourCreatorInvites_V2"
local RESULT_TOPIC="ParkourCreatorInviteResults_V1"
local DURATION=10

local function tellOwnerReleased(ownerUserId,friendUserId)
	local owner=Players:GetPlayerByUserId(ownerUserId)
	if owner then
		remote:FireClient(owner,"InviteReleased",friendUserId)
	end
end

local function sendOwnerResult(ownerUserId,friendUserId,result,inviteExpiresAt)
	local owner=Players:GetPlayerByUserId(ownerUserId)
	if owner then
		remote:FireClient(owner,"InviteResult",friendUserId,result)
		return
	end

	local ok,err=pcall(function()
		MessagingService:PublishAsync(RESULT_TOPIC,{
			ownerUserId=ownerUserId,
			friendUserId=friendUserId,
			result=result,
			expiresAt=inviteExpiresAt,
		})
	end)
	if not ok then
		warn("[CREATOR INVITE RESULT] "..tostring(err))
	end
end

local function release(ownerUserId,friendUserId)
	Registry.RemoveInvite(ownerUserId,friendUserId)
	tellOwnerReleased(ownerUserId,friendUserId)
end

local function invitePlayer(owner,friendUserId)
	friendUserId=tonumber(friendUserId)

	if not friendUserId or friendUserId==owner.UserId then
		remote:FireClient(owner,"InviteFailed","Choose another player.")
		return
	end

	-- Check the live destination server before creating an invitation.
	local hasRoom,capacityMessage=Capacity.HasRoom(owner.UserId)
	if not hasRoom then
		-- A targeted result unlocks only this player's button in the existing client.
		remote:FireClient(owner,"InviteResult",friendUserId,"Full")
		Capacity.Notify(owner,"SERVER SIZE",capacityMessage)
		return
	end

	local session=Registry.Get(owner.UserId)
	if not session or tonumber(session.ownerUserId)~=owner.UserId then
		remote:FireClient(owner,"InviteFailed","Your Creator session is not active.")
		return
	end

	-- Shared MemoryStore check: blocks duplicate active invitation.
	local existing=Registry.GetInvite(owner.UserId,friendUserId)
	if existing then
		remote:FireClient(
			owner,
			"InviteFailed",
			"That player already has an active invitation."
		)
		return
	end

	local stillRoom,roomMessage=Capacity.HasRoom(owner.UserId)
	if not stillRoom then
		remote:FireClient(owner,"InviteResult",friendUserId,"Full")
		Capacity.Notify(owner,"SERVER SIZE",roomMessage)
		return
	end
	local created,expiresAt=Registry.Invite(owner.UserId,friendUserId,DURATION)
	if not created then
		remote:FireClient(owner,"InviteFailed","Could not create invitation.")
		return
	end

	local friend=Players:GetPlayerByUserId(friendUserId)

	if friend then
		remote:FireClient(
			friend,
			"InviteReceived",
			owner.UserId,
			owner.Name,
			expiresAt
		)
	else
		local ok,err=pcall(function()
			MessagingService:PublishAsync(TOPIC,{
				targetUserId=friendUserId,
				ownerUserId=owner.UserId,
				ownerName=owner.Name,
				expiresAt=expiresAt,
			})
		end)

		if not ok then
			release(owner.UserId,friendUserId)
			remote:FireClient(owner,"InviteFailed","Could not send cross-server invite.")
			warn("[CREATOR INVITE] "..tostring(err))
			return
		end
	end

	remote:FireClient(owner,"InviteSent",friendUserId,expiresAt)

	print(
		"[CREATOR INVITE] "..owner.Name..
			" invited UserId "..friendUserId..
			" for "..DURATION.." seconds"
	)

	-- Cosmetic owner-side unlock notification.
	-- Registry itself remains authoritative.
	task.delay(DURATION+.2,function()
		-- IMPORTANT:
		-- This delayed task belongs ONLY to the invitation whose expiresAt
		-- was created above. If the guest declined and was invited again,
		-- the new invitation has a different expiresAt and this OLD task
		-- must not expire the new invitation.
		-- Read the raw session record here instead of Registry.GetInvite().
		-- GetInvite() intentionally returns nil once expiresAt <= os.time(),
		-- which previously caused this callback to return BEFORE notifying
		-- the Creator that the invitation timed out.
		local sessionNow=Registry.Get(owner.UserId)
		local storedInvite=
			sessionNow
			and type(sessionNow.invited)=="table"
			and sessionNow.invited[tostring(friendUserId)]
			or nil

		if type(storedInvite)~="table" then
			-- Declined/accepted/removed already.
			return
		end

		if tonumber(storedInvite.expiresAt)~=tonumber(expiresAt) then
			-- A newer invitation exists. Never expire/unlock that newer invite.
			return
		end

		Registry.RemoveInvite(owner.UserId,friendUserId)

		-- Exactly this invitation expired: notify Creator so their button
		-- unlocks and their timeout toast appears.
		sendOwnerResult(owner.UserId,friendUserId,"Expired",expiresAt)

		-- Close the recipient popup for THIS invitation.
		local friendNow=Players:GetPlayerByUserId(friendUserId)
		if friendNow then
			remote:FireClient(friendNow,"InviteExpired",owner.UserId,expiresAt)
		else
			pcall(function()
				MessagingService:PublishAsync(RESULT_TOPIC,{
					ownerUserId=owner.UserId,
					friendUserId=friendUserId,
					result="RecipientExpired",
					expiresAt=expiresAt,
				})
			end)
		end
	end)
end

local function accept(friend,ownerUserId)
	ownerUserId=tonumber(ownerUserId)
	if not ownerUserId then return end

	-- This reads MemoryStore, so it works even though friend is in another server.
	local invite=Registry.GetInvite(ownerUserId,friend.UserId)
	if not invite then
		remote:FireClient(friend,"InviteFailed","That invitation has expired.")
		return
	end

	local session=Registry.Get(ownerUserId)
	if not session then
		release(ownerUserId,friend.UserId)
		remote:FireClient(friend,"InviteFailed","That Creator session is no longer active.")
		return
	end

	-- Check the destination's shared capacity snapshot before teleporting.
	-- Invitations do not reserve seats. ArrivalServer rechecks locally so
	-- simultaneous accepts cannot overfill the admitted session.
	local hasRoom,capacityMessage=Capacity.CheckRemoteSession(session)
	if not hasRoom then
		Registry.RemoveInvite(ownerUserId,friend.UserId)
		sendOwnerResult(ownerUserId,friend.UserId,"Full")
		remote:FireClient(friend,"InviteExpired",ownerUserId)
		Capacity.Notify(friend,"CANNOT JOIN",capacityMessage)
		return
	end
	if friend.Parent~=Players then return end
	-- Reading MemoryStore may take time; do not accept after the original deadline.
	if invite.expiresAt<=os.time() then
		remote:FireClient(friend,"InviteExpired",ownerUserId)
		return
	end
	if RunService:IsStudio() then
		local admitted,reason=Capacity.TryAdmit(friend)
		if not admitted then
			Registry.RemoveInvite(ownerUserId,friend.UserId)
			sendOwnerResult(ownerUserId,friend.UserId,"Full")
			remote:FireClient(friend,"InviteExpired",ownerUserId)
			Capacity.Notify(friend,"CANNOT JOIN",reason)
			return
		end
	end

	-- Consume invitation before routing.
	Registry.RemoveInvite(ownerUserId,friend.UserId)
	sendOwnerResult(ownerUserId,friend.UserId,"Accepted")

	if RunService:IsStudio() then
		-- Match published ArrivalServer: an accepted invitation is NOT build permission.
		friend:SetAttribute("ParkourCreatorOwner",false)
		friend:SetAttribute("ParkourCreatorGuest",true)
		friend:SetAttribute("ParkourGuestPermissionRole",nil)
		friend:SetAttribute("ParkourCanCollaborate",false)
		friend:SetAttribute("ParkourCanViewCreator",true)
		friend:SetAttribute("ParkourLoadSavedDraft",false)
		friend:SetAttribute("ParkourPrivateCreator",true)
		friend:SetAttribute("ParkourCreatorOwnerUserId",ownerUserId)
		friend:SetAttribute("ParkourCreatorRole","Viewer")
		remote:FireClient(friend,"StudioInviteAccepted",ownerUserId)
		return
	end

	local accessCode=session.accessCode
	if type(accessCode)~="string" or accessCode=="" then
		remote:FireClient(friend,"InviteFailed","Creator routing information is unavailable.")
		return
	end

	local options=Instance.new("TeleportOptions")
	options.ReservedServerAccessCode=accessCode
	options:SetTeleportData({
		ParkourCreatorSession=true,
		CreatorUserId=ownerUserId,
		LoadSavedDraft=false,
		SessionRole="Collaborator",
		InvitedUserId=friend.UserId,
	})

	local ok,err=pcall(function()
		TeleportService:TeleportAsync(game.PlaceId,{friend},options)
	end)

	if not ok then
		warn("[CREATOR INVITE TELEPORT] "..tostring(err))
		remote:FireClient(friend,"InviteFailed","Could not join the Creator server.")
	end
end

remote.OnServerEvent:Connect(function(player,action,value)
	if action=="Invite" then
		invitePlayer(player,value)

	elseif action=="Accept" then
		if accepting[player] then return end
		accepting[player]=true
		local ok,err=pcall(accept,player,value)
		if not ok then
			warn("[CREATOR INVITE] Accept failed: "..tostring(err))
			Capacity.Notify(player,"CANNOT JOIN","The invitation could not be processed. Please try again.")
		end
		-- Leave a short guard after the yielding teleport call completes.
		task.delay(2,function() accepting[player]=nil end)

	elseif action=="Decline" or action=="Expire" then
		local ownerUserId=tonumber(value)
		if ownerUserId then
			local currentInvite=Registry.GetInvite(ownerUserId,player.UserId)
			local inviteExpiresAt=currentInvite and currentInvite.expiresAt or nil

			Registry.RemoveInvite(ownerUserId,player.UserId)

			local result=(action=="Decline") and "Rejected" or "Expired"
			sendOwnerResult(ownerUserId,player.UserId,result,inviteExpiresAt)

			print("[CREATOR INVITE] UserId "..player.UserId.." "..result.." invitation from "..ownerUserId)
		end
	end
end)

local okSub,subErr=pcall(function()
	MessagingService:SubscribeAsync(TOPIC,function(message)
		local data=message.Data
		if type(data)~="table" then return end

		local targetId=tonumber(data.targetUserId)
		local ownerId=tonumber(data.ownerUserId)
		local target=targetId and Players:GetPlayerByUserId(targetId)

		if not target or not ownerId then return end

		-- Calculate remaining time from the SHARED expiry timestamp.
		local invite=Registry.GetInvite(ownerId,targetId)
		if not invite then return end

		remote:FireClient(
			target,
			"InviteReceived",
			ownerId,
			tostring(data.ownerName or "Friend"),
			invite.expiresAt
		)
	end)
end)

if not okSub then
	warn("[CREATOR INVITE SUBSCRIBE] "..tostring(subErr))
end

local okResultSub,resultErr=pcall(function()
	MessagingService:SubscribeAsync(RESULT_TOPIC,function(message)
		local data=message.Data
		if type(data)~="table" then return end

		local ownerId=tonumber(data.ownerUserId)
		local friendId=tonumber(data.friendUserId)
		local result=tostring(data.result or "")

		if not ownerId or not friendId then return end

		if result=="RecipientExpired" then
			local friend=Players:GetPlayerByUserId(friendId)
			if friend then
				remote:FireClient(friend,"InviteExpired",ownerId)
			end
		else
			local owner=Players:GetPlayerByUserId(ownerId)
			if owner then
				remote:FireClient(owner,"InviteResult",friendId,result)
			end
		end
	end)
end)

if not okResultSub then
	warn("[CREATOR INVITE RESULT SUBSCRIBE] "..tostring(resultErr))
end

Players.PlayerRemoving:Connect(function(player) accepting[player]=nil end)
print("[CREATOR] InviteServer V4.7 capacity preflight loaded")

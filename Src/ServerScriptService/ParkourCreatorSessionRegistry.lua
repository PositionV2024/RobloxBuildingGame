-- ParkourCreatorSessionRegistry V2
-- ModuleScript: ServerScriptService > ParkourCreatorSessionRegistry
--
-- Cross-server Creator routing + timed invitations.
-- Uses MemoryStore, NOT persistent DataStore.
-- Access codes remain server-only.

local MemoryStoreService=game:GetService("MemoryStoreService")

local Registry={}
local Sessions=MemoryStoreService:GetHashMap("ParkourCreatorSessions_V1")

local TTL=60*60*2
local DEFAULT_INVITE_SECONDS=10

local function key(ownerUserId)
	return "creator_"..tostring(ownerUserId)
end

function Registry.Register(ownerUserId,accessCode,privateServerId)
	local record={
		ownerUserId=ownerUserId,
		accessCode=accessCode,
		privateServerId=privateServerId,
		updatedAt=os.time(),
		invited={},
	}

	local ok,err=pcall(function()
		Sessions:SetAsync(key(ownerUserId),record,TTL)
	end)

	if not ok then
		warn("[CREATOR REGISTRY] Register failed: "..tostring(err))
		return false
	end
	return true
end

function Registry.Get(ownerUserId)
	local ok,value=pcall(function()
		return Sessions:GetAsync(key(ownerUserId))
	end)
	if not ok then
		warn("[CREATOR REGISTRY] Get failed: "..tostring(value))
		return nil
	end
	return value
end

function Registry.Invite(ownerUserId,friendUserId,duration)
	duration=math.clamp(tonumber(duration) or DEFAULT_INVITE_SECONDS,1,60)
	local expiresAt=os.time()+duration

	local ok,value=pcall(function()
		return Sessions:UpdateAsync(key(ownerUserId),function(old)
			if type(old)~="table" then return nil end

			old.invited=type(old.invited)=="table" and old.invited or {}
			local id=tostring(friendUserId)
			local existing=old.invited[id]

			-- Do not replace an invitation that is still active.
			if type(existing)=="table"
				and tonumber(existing.expiresAt)
				and existing.expiresAt>os.time() then
				return old
			end

			old.invited[id]={
				expiresAt=expiresAt,
			}
			old.updatedAt=os.time()
			return old
		end,TTL)
	end)

	if not ok then
		warn("[CREATOR REGISTRY] Invite failed: "..tostring(value))
		return false
	end

	return value~=nil,expiresAt
end

function Registry.GetInvite(ownerUserId,userId)
	local record=Registry.Get(ownerUserId)
	if not record or type(record.invited)~="table" then
		return nil
	end

	local invite=record.invited[tostring(userId)]
	if type(invite)~="table" then
		-- Old V1 boolean invites are intentionally no longer considered valid.
		return nil
	end

	local expiresAt=tonumber(invite.expiresAt)
	if not expiresAt or expiresAt<=os.time() then
		Registry.RemoveInvite(ownerUserId,userId)
		return nil
	end

	return {
		expiresAt=expiresAt,
		remaining=math.max(0,expiresAt-os.time()),
	}
end

function Registry.IsInvited(ownerUserId,userId)
	return Registry.GetInvite(ownerUserId,userId)~=nil
end

function Registry.RemoveInvite(ownerUserId,userId)
	local ok,err=pcall(function()
		Sessions:UpdateAsync(key(ownerUserId),function(old)
			if type(old)~="table" then return nil end
			old.invited=type(old.invited)=="table" and old.invited or {}
			old.invited[tostring(userId)]=nil
			old.updatedAt=os.time()
			return old
		end,TTL)
	end)

	if not ok then
		warn("[CREATOR REGISTRY] RemoveInvite failed: "..tostring(err))
	end
	return ok
end

function Registry.Remove(ownerUserId)
	local ok,err=pcall(function()
		Sessions:RemoveAsync(key(ownerUserId))
	end)
	if not ok then
		warn("[CREATOR REGISTRY] Remove failed: "..tostring(err))
	end
	return ok
end

return Registry

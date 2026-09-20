-- ParkourCreatorServersServer V1
-- NEW Script: ServerScriptService > ParkourCreatorServersServer
-- Requires your EXISTING ParkourCreatorCapacity and ParkourCreatorSessionRegistry.
-- Also requires the NEW ParkourCreatorBrowserRules ModuleScript beside this Script.
-- No DataStoreService writes. This feature does NOT replace the invitation system.
-- Access codes remain server-side; destination ArrivalServer V5.6 is the final capacity gate.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local function dependency(name)
	local module = script.Parent:WaitForChild(name, 15)
	assert(module and module:IsA("ModuleScript"), "[CREATOR BROWSER] Missing ModuleScript: " .. name)
	return require(module)
end
local Rules = dependency("ParkourCreatorBrowserRules")
local Capacity = dependency("ParkourCreatorCapacity")
local Registry = dependency("ParkourCreatorSessionRegistry")
assert(type(Capacity.IsOwner)=="function" and type(Capacity.TryAdmit)=="function"
	and type(Capacity.CheckRemoteSession)=="function", "Use ParkourCreatorCapacity V1.1 or a compatible version")
assert(type(Registry.Get)=="function", "ParkourCreatorSessionRegistry.Get is required")
local CFG = Rules.Config
local STUDIO = RunService:IsStudio()
local INSTANCE = HttpService:GenerateGUID(false)
local TOPIC_PREFIX = "ParkourJoinWakeV1_"
local DIRECTORY_NAME = "ParkourCreatorBrowse_V1"
local INBOX_PREFIX = "ParkourCreatorJoinInbox_V1_"
local directory = not STUDIO and MemoryStoreService:GetSortedMap(DIRECTORY_NAME) or nil
local remote = RS:FindFirstChild("ParkourCreatorServersEvent")
if remote then
	assert(remote:IsA("RemoteEvent"), "ParkourCreatorServersEvent must be a RemoteEvent")
else
	remote = Instance.new("RemoteEvent")
	remote.Name = "ParkourCreatorServersEvent"
	remote.Parent = RS
end

local readyClients, outgoing, lastResult, requestTimes, rateTimes, requestBusy = {}, {}, {}, {}, {}, {}
local cursors, browseBusy, mapCache, studioRecords = {}, {}, {}, {}
local ownerInbox, ownerInboxSignature = {}, ""
local pollInboxBusy, pollOutBusy, publishBusy, dirty = false, {}, false, false
local listingPublished, localListing, shuttingDown = false, nil, false
local lastWarning, lastRouteCheck, cachedRoute = {}, -math.huge, nil
local lastOwner, requestsOpen, ownerNoticeSent = nil, true, false
local listCache = {} -- coalesces browse requests in the same public server

local function clock() return DateTime.now().UnixTimestampMillis / 1000 end
local function present(p) return p ~= nil and p.Parent == Players end
local function safeSend(p, action, data)
	if present(p) then remote:FireClient(p, action, data) end
end
local function warning(label, err)
	if os.clock() - (lastWarning[label] or -math.huge) < 15 then return end
	lastWarning[label] = os.clock()
	warn("[CREATOR BROWSER] " .. label .. ": " .. tostring(err))
end
local function gate(p, name, interval)
	rateTimes[p] = rateTimes[p] or {}
	local now = os.clock()
	if now - (rateTimes[p][name] or -math.huge) < interval then return false end
	rateTimes[p][name] = now
	return true
end
local function creatorOwner()
	if shuttingDown then return nil end
	if not STUDIO and (game.PrivateServerId == "" or game.PrivateServerOwnerId ~= 0) then return nil end
	local id = tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))
	local p = id and Players:GetPlayerByUserId(id)
	if p and Capacity.IsOwner(p) then return p end
	return nil
end
local function requesterAllowed(p)
	if not present(p) then return false end
	if p:GetAttribute("ParkourCreatorGuest") == true
		or p:GetAttribute("ParkourCreatorOwner") == true
		or p:GetAttribute("ParkourPrivateCreator") == true then return false end
	-- Studio uses one local server for a simulated owner plus a lobby test player.
	return STUDIO or game.PrivateServerId == ""
end
local function fail(p, message)
	safeSend(p, "Error", {message=message})
end
local function getMap(id)
	if not Rules.Token(id) then error("Invalid internal session identifier") end
	if STUDIO then
		studioRecords[id] = studioRecords[id] or {}
		return studioRecords[id]
	end
	if not mapCache[id] then mapCache[id] = MemoryStoreService:GetSortedMap(INBOX_PREFIX .. id) end
	return mapCache[id]
end
local function readRequest(id, key)
	local ok, result = pcall(function()
		local map = getMap(id)
		if STUDIO then
			local item = map[key]
			if item and item.removeAt > clock() then return table.clone(item.value) end
			map[key] = nil
			return nil
		end
		return map:GetAsync(key)
	end)
	if not ok then warning("Request read", result) end
	return ok, result
end
local function updateRequest(id, key, fn)
	local ok, result = pcall(function()
		local map = getMap(id)
		if STUDIO then
			local item = map[key]
			local old = item and item.removeAt > clock() and table.clone(item.value) or nil
			local value = fn(old)
			if value == nil then return nil end
			map[key] = {value=table.clone(value), removeAt=clock()+CFG.RecordTTL}
			return table.clone(value)
		end
		return map:UpdateAsync(key, function(old)
			local value = fn(old)
			if value == nil then return nil end
			return value, value.createdAt
		end, CFG.RecordTTL)
	end)
	if not ok then warning("Request update", result) end
	return ok, result
end
local function change(id, key, expected, event, message)
	return updateRequest(id, key, function(old)
		local value = Rules.Transition(old, expected, event, clock())
		if value then value.message = message or Rules.Messages[value.state] end
		return value
	end)
end

local pollInbox, pollOutgoing -- functions referenced by message wake-ups
local function wake(id)
	if not Rules.Token(id) then return end
	if id == INSTANCE then
		task.defer(function()
			if pollInbox then pollInbox() end
			for p in pairs(outgoing) do if pollOutgoing then task.spawn(pollOutgoing, p) end end
		end)
	elseif not STUDIO then
		task.spawn(function()
			local ok, err = pcall(function()
				MessagingService:PublishAsync(TOPIC_PREFIX .. id, {wake=true})
			end)
			if not ok then warning("Message wake-up (polling will retry)", err) end
		end)
	end
end
local function statusPacket(r)
	return {
		id=r.id, sessionId=r.targetInstance, ownerUserId=r.ownerUserId,
		ownerUsername=r.ownerUsername, state=r.state, revision=r.revision,
		expiresAt=r.expiresAt, approvedUntil=r.approvedUntil, transferUntil=r.transferUntil,
		message=r.message or Rules.Messages[r.state], serverNow=clock(),
	}
end
local function deliverStatus(p, r)
	local state = outgoing[p]
	if state and state.id ~= r.id then return end
	if state and state.lastRevision == r.revision then return end
	if state then state.lastRevision = r.revision end
	local packet = statusPacket(r)
	lastResult[p] = packet
	safeSend(p, "RequestStatus", packet)
	if Rules.Terminal(r.state) and outgoing[p] == state then outgoing[p] = nil end
end
local function failOutgoing(p, state, event, message)
	if outgoing[p] ~= state then return end
	local ok, r = change(state.sessionId, state.key, state.id, event, message)
	if ok and r and r.id == state.id then
		deliverStatus(p, r)
		wake(state.sessionId)
	else
		-- Clear only this local attempt. Never fabricate a database success.
		local packet = {id=state.id, sessionId=state.sessionId, state="Failed", revision=999,
			message=message or "The request could not be completed. Please try again.", serverNow=clock()}
		lastResult[p] = packet
		safeSend(p, "RequestStatus", packet)
		if outgoing[p] == state then outgoing[p] = nil end
	end
end

local function routeFor(owner)
	if STUDIO then return {ownerUserId=owner.UserId, privateServerId="STUDIO"} end
	if os.clock()-lastRouteCheck >= 10 then
		lastRouteCheck = os.clock()
		cachedRoute = Registry.Get(owner.UserId)
	end
	if type(cachedRoute)=="table" and tonumber(cachedRoute.ownerUserId)==owner.UserId
		and cachedRoute.privateServerId==game.PrivateServerId
		and type(cachedRoute.accessCode)=="string" and cachedRoute.accessCode~="" then
		return cachedRoute
	end
	return nil
end
local function makeListing()
	local owner = creatorOwner()
	if not owner then return nil end
	local count = tonumber(workspace:GetAttribute("ParkourCreatorPlayerCount"))
	local limit = tonumber(workspace:GetAttribute("ParkourCreatorPlayerLimit"))
	if not Rules.Integer(count) or not Rules.Integer(limit) or count < 1 or limit < 1 then return nil end
	local route = routeFor(owner)
	if not route and not ownerNoticeSent then
		ownerNoticeSent=true
		warning("Routing unavailable", "SessionRegistry must contain this owner's reserved access code. The row is not joinable until existing invitation routing is ready.")
	end
	return {
		sessionId=INSTANCE, ownerUserId=owner.UserId, username=owner.Name,
		displayName=owner.DisplayName, privateServerId=STUDIO and "STUDIO" or game.PrivateServerId,
		jobId=game.JobId, placeId=game.PlaceId, count=count, limit=math.min(5,limit),
		open=true, ready=route~=nil, accepting=requestsOpen, updatedAt=clock(),
	}
end
local function queuePublish()
	dirty=true
	if publishBusy then return end
	publishBusy=true
	task.spawn(function()
		while dirty and not shuttingDown do
			dirty=false
			local d=makeListing()
			localListing=d
			if not STUDIO then
				local ok, err=pcall(function()
					if d then
						directory:SetAsync(INSTANCE,d,CFG.DirectoryTTL,INSTANCE)
						listingPublished=true
					elseif listingPublished then
						directory:RemoveAsync(INSTANCE)
						listingPublished=false
					end
				end)
				if not ok then warning("Directory publish",err) end
			end
		end
		publishBusy=false
	end)
end
local function readListing(id)
	if id==INSTANCE then return true, makeListing() end
	if STUDIO then return true, nil end
	local ok,d=pcall(function() return directory:GetAsync(id) end)
	if not ok then warning("Directory lookup",d) end
	return ok,d
end

local function directoryPage(cursor)
	if STUDIO then
		local d=makeListing()
		return true, d and {{key=INSTANCE,sortKey=INSTANCE,value=d}} or {}
	end
	local cacheKey=cursor and cursor.key or "FIRST"
	local c=listCache[cacheKey]
	if c and clock()-c.at<5 then return c.ok,c.items end
	local ok,items=pcall(function()
		return directory:GetRangeAsync(Enum.SortDirection.Ascending,CFG.PageSize,cursor)
	end)
	if not ok then warning("Directory page",items) end
	-- Bounded cache; a public server does not keep an unlimited page history.
	local n=0; for _ in pairs(listCache) do n=n+1 end
	if n>=24 then table.clear(listCache) end
	listCache[cacheKey]={at=clock(),ok=ok,items=items}
	return ok,items
end
local function browse(p,payload)
	if not requesterAllowed(p) then
		safeSend(p,"Directory",{sequence=payload.sequence,rows={},message="Use Creator Servers from Discover, not from inside a Creator session."})
		return
	end
	local cursor=payload.more and cursors[p] or nil
	if payload.more and not cursor then
		safeSend(p,"Directory",{sequence=payload.sequence,rows={},append=true,hasMore=false})
		return
	end
	local ok,items=directoryPage(cursor)
	if not present(p) then return end
	if not ok then
		safeSend(p,"Directory",{sequence=payload.sequence,rows={},append=payload.more==true,
			error=true,message="Creator listings are temporarily unavailable. Press REFRESH to retry."})
		return
	end
	local rows={}
	for _,item in ipairs(items) do
		local d=item.value
		if Rules.ValidListing(d,clock(),game.PlaceId) then table.insert(rows,Rules.PublicListing(d)) end
	end
	local last=items[#items]
	cursors[p]=(#items==CFG.PageSize and last) and {key=last.key,sortKey=last.sortKey} or nil
	safeSend(p,"Directory",{sequence=payload.sequence,rows=rows,append=payload.more==true,
		hasMore=cursors[p]~=nil,serverNow=clock(),studio=STUDIO})
end

local function inboxRows()
	local ok,items=pcall(function()
		if STUDIO then
			local rows={}
			for key,item in pairs(getMap(INSTANCE)) do
				if item.removeAt>clock() then table.insert(rows,{key=key,value=table.clone(item.value)}) end
			end
			table.sort(rows,function(a,b) return a.value.createdAt>b.value.createdAt end)
			return rows
		end
		return getMap(INSTANCE):GetRangeAsync(Enum.SortDirection.Descending,CFG.InboxSize)
	end)
	if not ok then warning("Owner inbox",items) end
	return ok,items
end
pollInbox=function(force)
	if pollInboxBusy then return end
	local owner=creatorOwner()
	if not owner and not lastOwner then return end
	pollInboxBusy=true
	local ok,items=inboxRows()
	if not ok then pollInboxBusy=false; return end
	local display={}
	for _,item in ipairs(items) do
		local r=item.value
		if type(r)=="table" and r.targetInstance==INSTANCE then
			local event=nil
			if (r.state=="Pending" or r.state=="Approved") then
				if not owner or owner.UserId~=r.ownerUserId then event="OwnerLeft"
				elseif not requestsOpen then event="Closed"
				elseif not Rules.Active(r,clock()) then event="Expire" end
			elseif r.state=="Transferring" and not Rules.Active(r,clock()) then event="Expire" end
			if event then
				local changed,new=change(INSTANCE,item.key,r.id,event)
				if changed and new then r=new; wake(r.sourceInstance) end
			end
			if owner and r.ownerUserId==owner.UserId and r.state=="Pending" and Rules.Active(r,clock()) then
				table.insert(display,{id=r.id,requesterUserId=r.requesterUserId,
					username=r.username,displayName=r.displayName,expiresAt=r.expiresAt,createdAt=r.createdAt})
			end
		end
	end
	table.sort(display,function(a,b) return a.createdAt<b.createdAt end)
	ownerInbox=display
	local sigParts={tostring(requestsOpen)}
	for _,r in ipairs(display) do table.insert(sigParts,r.id) end
	local signature=table.concat(sigParts,"|")
	if owner and readyClients[owner] and (force or ownerInboxSignature~=signature) then
		safeSend(owner,"Inbox",{rows=display,requestsOpen=requestsOpen,serverNow=clock()})
		ownerInboxSignature=signature
	end
	pollInboxBusy=false
end

local function sendRequest(p,sessionId)
	if not requesterAllowed(p) then fail(p,"Return to Discover before requesting another Creator server."); return end
	if outgoing[p] then fail(p,"You already have a join request. Wait for a response or cancel it."); return end
	local remaining=CFG.RequestCooldown-(clock()-(requestTimes[p] or -math.huge))
	if remaining>0 then fail(p,"Wait "..math.ceil(remaining).." seconds before another request."); return end
	requestTimes[p]=clock()
	local ok,d=readListing(sessionId)
	if not present(p) then return end
	if not ok or not Rules.ValidListing(d,clock(),game.PlaceId) or not d.ready then
		fail(p,"That Creator session is unavailable. Refresh the list."); return
	end
	if d.ownerUserId==p.UserId then fail(p,"You cannot request to join yourself."); return end
	if not d.accepting then fail(p,"That Creator has paused join requests."); return end
	if d.count>=d.limit then fail(p,"That Creator server is full."); return end
	if not requesterAllowed(p) then return end
	local createdAt=clock()
	local id=HttpService:GenerateGUID(false)
	local key=tostring(p.UserId)
	local r={id=id,requesterUserId=p.UserId,username=p.Name,displayName=p.DisplayName,
		ownerUserId=d.ownerUserId,ownerUsername=d.username,
		targetInstance=d.sessionId,privateServerId=d.privateServerId,
		sourceInstance=INSTANCE,sourcePlaceId=game.PlaceId,
		createdAt=createdAt,expiresAt=createdAt+CFG.RequestSeconds,
		state="Pending",revision=1,updatedAt=createdAt,message=Rules.Messages.Pending}
	local wrote,stored=updateRequest(sessionId,key,function(old)
		if Rules.Active(old,clock()) then return nil end
		return r
	end)
	if not wrote or not stored or stored.id~=id then
		fail(p,"A request is already active, or the request service is busy. Please wait and retry."); return
	end
	if not requesterAllowed(p) then
		change(sessionId,key,id,"Cancel")
		return
	end
	outgoing[p]={id=id,sessionId=sessionId,key=key,lastRevision=0,createdAt=createdAt,
		originalExpiresAt=r.expiresAt,processing=false,startedTransfer=false}
	deliverStatus(p,stored)
	wake(sessionId)
end

local function respond(owner,payload)
	if not Capacity.IsOwner(owner) or creatorOwner()~=owner then return end
	local key=tostring(payload.requesterUserId)
	local ok,r=readRequest(INSTANCE,key)
	if not ok or type(r)~="table" or r.id~=payload.id or r.ownerUserId~=owner.UserId
		or r.targetInstance~=INSTANCE then
		safeSend(owner,"Decision",{id=payload.id,ok=false,message="That request is no longer available."}); return
	end
	if r.state~="Pending" or not Rules.Active(r,clock()) then
		change(INSTANCE,key,r.id,"Expire")
		safeSend(owner,"Decision",{id=r.id,ok=false,message="That request has already ended."})
		wake(r.sourceInstance); task.defer(pollInbox,true); return
	end
	local event=payload.approve and "Approve" or "Decline"
	if payload.approve then
		local hasRoom=Capacity.HasRoom(owner.UserId)
		if not requestsOpen then event="Closed"
		elseif not hasRoom then event="Full"
		elseif not routeFor(owner) then event="Fail" end
	end
	-- Check identity again after yielding reads; owner departure cannot approve late.
	if creatorOwner()~=owner then event="OwnerLeft" end
	local changed,new=change(INSTANCE,key,r.id,event)
	safeSend(owner,"Decision",{id=r.id,ok=changed and new~=nil,
		message=new and (new.state=="Approved" and "Approved. Guest will join as a Viewer."
			or Rules.Messages[new.state]) or "Request changed before this response. Refreshing..."})
	if changed and new then wake(new.sourceInstance) end
	task.defer(pollInbox,true)
end

local function beginTransfer(p,state,r)
	if outgoing[p]~=state or state.processing or state.startedTransfer then return end
	state.processing=true
	if not requesterAllowed(p) then state.processing=false; failOutgoing(p,state,"Cancel","You left Discover, so this request was cancelled."); return end
	local route, reason
	local ok,d=readListing(state.sessionId)
	if not ok or not Rules.ValidListing(d,clock(),game.PlaceId) or not d.ready
		or d.ownerUserId~=r.ownerUserId or d.privateServerId~=r.privateServerId then
		state.processing=false; failOutgoing(p,state,"OwnerLeft"); return
	end
	if STUDIO then
		route={ownerUserId=r.ownerUserId,privateServerId="STUDIO"}
	else
		route=Registry.Get(r.ownerUserId)
		if type(route)~="table" or tonumber(route.ownerUserId)~=r.ownerUserId
			or route.privateServerId~=r.privateServerId
			or type(route.accessCode)~="string" or route.accessCode=="" then
			state.processing=false; failOutgoing(p,state,"OwnerLeft"); return
		end
	end
	local room; room,reason=Capacity.CheckRemoteSession(route)
	if not room then state.processing=false; failOutgoing(p,state,"Full",reason); return end
	if outgoing[p]~=state or not requesterAllowed(p) then state.processing=false; return end
	local changed,new=change(state.sessionId,state.key,state.id,"BeginTransfer")
	if not changed or not new or new.state~="Transferring" then
		state.processing=false; return
	end
	state.startedTransfer=true
	state.transferUntil=new.transferUntil
	state.processing=false
	deliverStatus(p,new)
	wake(state.sessionId)
	-- Cosmetic transition delay; never trust a client acknowledgement for admission.
	task.delay(0.85,function()
		if outgoing[p]~=state then return end
		if not requesterAllowed(p) then
			if present(p) then failOutgoing(p,state,"Fail","You left Discover before the teleport could start.") end
			return
		end
		if STUDIO then
			local owner=creatorOwner()
			if not owner or owner.UserId~=r.ownerUserId then failOutgoing(p,state,"Fail"); return end
			local admitted,why=Capacity.TryAdmit(p)
			if not admitted then failOutgoing(p,state,"Fail",why); return end
			p:SetAttribute("ParkourCreatorOwner",false)
			p:SetAttribute("ParkourCreatorGuest",true)
			p:SetAttribute("ParkourGuestPermissionRole",nil)
			p:SetAttribute("ParkourCanCollaborate",false)
			p:SetAttribute("ParkourCanViewCreator",true)
			p:SetAttribute("ParkourLoadSavedDraft",false)
			p:SetAttribute("ParkourCreatorOwnerUserId",r.ownerUserId)
			p:SetAttribute("ParkourCreatorRole","Viewer")
			p:SetAttribute("ParkourPrivateCreator",true)
			local root=workspace:FindFirstChild("ParkourCreator")
			local spawn=root and root:FindFirstChild("CreatorSpawn")
			if spawn and spawn:IsA("BasePart") and p.Character then p.Character:PivotTo(spawn.CFrame*CFrame.new(0,3,0)) end
			local accepted,arrived=change(state.sessionId,state.key,state.id,"Arrive")
			if accepted and arrived then deliverStatus(p,arrived) end
			safeSend(p,"StudioJoined",{ownerUserId=r.ownerUserId})
			task.defer(pollInbox,true)
			return
		end
		local options=Instance.new("TeleportOptions")
		options.ReservedServerAccessCode=route.accessCode
		options:SetTeleportData({
			ParkourCreatorSession=true,CreatorUserId=r.ownerUserId,
			LoadSavedDraft=false,SessionRole="Viewer",InvitedUserId=p.UserId,
			ParkourJoinRequestId=state.id,ParkourJoinTargetInstance=state.sessionId,
		})
		local sent,err=pcall(function() TeleportService:TeleportAsync(game.PlaceId,{p},options) end)
		if not sent then
			warning("Join teleport",err)
			failOutgoing(p,state,"Fail","Roblox could not start the teleport. Please try again.")
		end
	end)
end

pollOutgoing=function(p)
	local state=outgoing[p]
	if not state or pollOutBusy[p] then return end
	pollOutBusy[p]=true
	local ok,r=readRequest(state.sessionId,state.key)
	if outgoing[p]~=state then pollOutBusy[p]=nil; return end
	if not ok then
		local deadline=state.transferUntil or (state.originalExpiresAt+CFG.ApprovalSeconds+5)
		if clock()>deadline then failOutgoing(p,state,"Fail","The request service stopped responding. Please try again.") end
		pollOutBusy[p]=nil; return
	end
	if type(r)~="table" or r.id~=state.id or r.requesterUserId~=p.UserId or r.sourceInstance~=INSTANCE then
		failOutgoing(p,state,"Fail","That join request is no longer valid.")
		pollOutBusy[p]=nil; return
	end
	if not Rules.Terminal(r.state) and not Rules.Active(r,clock()) then
		local changed,new=change(state.sessionId,state.key,state.id,"Expire")
		if changed and new then r=new; wake(state.sessionId) end
	end
	deliverStatus(p,r)
	if r.state=="Approved" and outgoing[p]==state then beginTransfer(p,state,r) end
	pollOutBusy[p]=nil
end

TeleportService.TeleportInitFailed:Connect(function(p,result,message,placeId,options)
	local state=outgoing[p]
	if not state or not state.startedTransfer or not options then return end
	local ok,data=pcall(function() return options:GetTeleportData() end)
	if not ok or type(data)~="table" or data.ParkourJoinRequestId~=state.id then return end
	warning("Join teleport failed",message)
	task.spawn(failOutgoing,p,state,"Fail","Teleport failed. You are still in this server; please try again.")
end)

local function checkArrival(p)
	if STUDIO then return end
	local ok,j=pcall(function() return p:GetJoinData() end)
	local data=ok and j and j.TeleportData
	if type(data)~="table" or not Rules.Token(data.ParkourJoinRequestId)
		or not Rules.Token(data.ParkourJoinTargetInstance) then return end
	local id=data.ParkourJoinRequestId
	-- Admission/role initialization belongs to the EXISTING ArrivalServer.
	task.spawn(function()
		for _=1,40 do
			if not present(p) then return end
			if p:GetAttribute("ParkourCreatorCapacityAdmitted")==true
				and p:GetAttribute("ParkourCreatorGuest")==true then break end
			task.wait(0.2)
		end
		if not present(p) or p:GetAttribute("ParkourCreatorCapacityAdmitted")~=true then return end
		local okRead,r=readRequest(data.ParkourJoinTargetInstance,tostring(p.UserId))
		if not okRead or type(r)~="table" or r.id~=id or r.requesterUserId~=p.UserId
			or r.targetInstance~=INSTANCE or r.privateServerId~=game.PrivateServerId
			or tonumber(p:GetAttribute("ParkourCreatorOwnerUserId"))~=r.ownerUserId then return end
		local changed,new=change(INSTANCE,tostring(p.UserId),id,"Arrive")
		if changed and new then
			lastResult[p]=statusPacket(new)
			safeSend(p,"RequestStatus",lastResult[p])
			wake(r.sourceInstance)
		end
	end)
end

remote.OnServerEvent:Connect(function(p,action,data)
	if type(action)~="string" or not gate(p,"all",0.08) then return end
	if action=="Ready" or action=="Sync" then
		if not gate(p,"sync",1) then return end
		readyClients[p]=true
		safeSend(p,"Hello",{studio=STUDIO,owner=creatorOwner()==p,requestSeconds=CFG.RequestSeconds})
		if outgoing[p] then task.spawn(pollOutgoing,p)
		elseif lastResult[p] then safeSend(p,"RequestStatus",lastResult[p]) end
		if creatorOwner()==p then task.spawn(pollInbox,true) end
	elseif action=="Browse" then
		if type(data)~="table" or not Rules.Integer(data.sequence) or data.sequence<1 then return end
		if browseBusy[p] or not gate(p,"browse",1) then
			safeSend(p,"Directory",{sequence=data.sequence,error=true,message="Please wait briefly before refreshing.",rows={}}); return
		end
		browseBusy[p]=true
		task.spawn(function()
			local ok,err=pcall(browse,p,data)
			browseBusy[p]=nil
			if not ok then warning("Browse handler",err); safeSend(p,"Directory",{sequence=data.sequence,error=true,rows={},message="Could not load Creator servers."}) end
		end)
	elseif action=="Request" then
		if type(data)~="table" or not Rules.Token(data.sessionId) then return end
		if requestBusy[p] then return end
		requestBusy[p]=true
		task.spawn(function()
			local ok,err=pcall(sendRequest,p,data.sessionId)
			requestBusy[p]=nil
			if not ok then warning("Send request",err); fail(p,"Could not send this request. Please try again.") end
		end)
	elseif action=="Cancel" then
		if type(data)~="table" or not Rules.Token(data.id) or not gate(p,"cancel",0.5) then return end
		local state=outgoing[p]
		if state and state.id==data.id then
			if state.startedTransfer then fail(p,"The approved teleport has already started.")
			else task.spawn(failOutgoing,p,state,"Cancel") end
		end
	elseif action=="Respond" then
		if type(data)~="table" or not Rules.Token(data.id) or not Rules.Integer(data.requesterUserId)
			or type(data.approve)~="boolean" or not gate(p,"respond",0.25) then return end
		task.spawn(function()
			local ok,err=pcall(respond,p,data)
			if not ok then warning("Respond handler",err); safeSend(p,"Decision",{id=data.id,ok=false,message="Could not process response. Please try again."}) end
		end)
	elseif action=="SetOpen" then
		if type(data)~="table" or type(data.open)~="boolean" or creatorOwner()~=p or not gate(p,"open",0.5) then return end
		requestsOpen=data.open
		workspace:SetAttribute("ParkourCreatorJoinRequestsOpen",requestsOpen)
		queuePublish(); task.spawn(pollInbox,true)
	end
end)

local function watch(p)
	checkArrival(p)
	for _,attr in ipairs({"ParkourCreatorOwner","ParkourCreatorGuest","ParkourPrivateCreator"}) do
		p:GetAttributeChangedSignal(attr):Connect(function()
			local state=outgoing[p]
			if state and not state.startedTransfer and not requesterAllowed(p) then
				task.spawn(failOutgoing,p,state,"Cancel","Request cancelled because you left Discover.")
			end
			queuePublish()
		end)
	end
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(p)
	local state=outgoing[p]
	if state and not state.startedTransfer then
		task.spawn(function() change(state.sessionId,state.key,state.id,"Cancel"); wake(state.sessionId) end)
	end
	outgoing[p]=nil; lastResult[p]=nil; readyClients[p]=nil; rateTimes[p]=nil
	requestTimes[p]=nil; requestBusy[p]=nil; cursors[p]=nil; browseBusy[p]=nil; pollOutBusy[p]=nil
	if lastOwner==p then task.defer(pollInbox,true) end
	task.defer(queuePublish)
end)
for _,p in ipairs(Players:GetPlayers()) do watch(p) end

for _,attr in ipairs({"ParkourPrivateCreatorServer","ParkourCreatorOwnerUserId","ParkourCreatorPlayerCount",
	"ParkourCreatorPlayerLimit","ParkourCreatorSessionClosing","ParkourCreatorOwnerPresent"}) do
	workspace:GetAttributeChangedSignal(attr):Connect(function()
		queuePublish()
		task.defer(pollInbox,true)
	end)
end

-- MessagingService is a wake-up optimization, NOT the source of truth.
-- Canonical MemoryStore polling still delivers results when messages are missed.
if not STUDIO then
	task.spawn(function()
		while not shuttingDown do
			local ok,connection=pcall(function()
				return MessagingService:SubscribeAsync(TOPIC_PREFIX..INSTANCE,function(message)
					if type(message.Data)~="table" or message.Data.wake~=true then return end
					task.spawn(pollInbox)
					for p in pairs(outgoing) do task.spawn(pollOutgoing,p) end
				end)
			end)
			if ok then
				script.Destroying:Connect(function() connection:Disconnect() end)
				break
			end
			warning("Subscribe (polling remains active)",connection)
			task.wait(15)
		end
	end)
end

queuePublish()
task.spawn(function()
	while not shuttingDown do
		local owner=creatorOwner()
		if owner and lastOwner~=owner then
			lastOwner=owner; requestsOpen=true; ownerInboxSignature=""
			workspace:SetAttribute("ParkourCreatorJoinRequestsOpen",true)
			queuePublish()
			if readyClients[owner] then safeSend(owner,"Hello",{owner=true,studio=STUDIO,requestSeconds=CFG.RequestSeconds}) end
		end
		pollInbox()
		task.wait(CFG.InboxRefreshSeconds)
	end
end)
task.spawn(function()
	while not shuttingDown do
		for p in pairs(outgoing) do task.spawn(pollOutgoing,p) end
		task.wait(CFG.ResultRefreshSeconds)
	end
end)
task.spawn(function()
	while not shuttingDown do task.wait(CFG.DirectoryRefreshSeconds); queuePublish() end
end)
game:BindToClose(function()
	shuttingDown=true
	if not STUDIO and listingPublished then pcall(function() directory:RemoveAsync(INSTANCE) end) end
end)
print("[CREATOR BROWSER] V1 ready. Real listings; owner-approved joins; no plot/settings DataStore writes.")

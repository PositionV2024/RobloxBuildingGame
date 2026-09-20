-- MAKE YOUR OWN PARKOUR - V3 SERVER
-- REPLACE ServerScriptService > ParkourBuilderServer
-- Adds Start block + timed Test Mode while keeping V2 object behavior.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local DataStoreService=game:GetService("DataStoreService")
local DraftStore=DataStoreService:GetDataStore("ParkourDrafts_V1")
local PublishedStore=DataStoreService:GetDataStore("PublishedParkours_V1")
local CreatorIndex=DataStoreService:GetDataStore("ParkourCreatorIndex_V1")
local DiscoverIndex=DataStoreService:GetDataStore("ParkourDiscoverIndex_V1")
local remote=RS:WaitForChild("ParkourBuilderEvent")
local root=workspace:WaitForChild("ParkourCreator")

local objects=root:WaitForChild("PlacedObjects")
local history,redoStack,testing,testStarted={},{},{},{}
local rotateBurst={}

-- Creator-mode spawn is handled here so the builder itself is authoritative.
local creatorModeRemote=RS:FindFirstChild("ParkourCreatorModeEvent") or Instance.new("RemoteEvent")
creatorModeRemote.Name="ParkourCreatorModeEvent"
creatorModeRemote.Parent=RS
local creatorMode={}
local loadDraft -- defined later; used when CREATE enters creator mode

local function getCreatorSpawnCF()
	local spawn=root:FindFirstChild("CreatorSpawn")
	if spawn and spawn:IsA("BasePart") then
		return spawn.CFrame*CFrame.new(0,3,0)
	end
	warn("[BUILDER] CreatorSpawn missing from Workspace.ParkourCreator")
	return nil
end

local function sendToCreatorSpawn(p)
	local target=getCreatorSpawnCF()
	if not target then return end
	local ch=p.Character
	if not ch then
		p:LoadCharacter()
		ch=p.CharacterAdded:Wait()
	end
	local hum=ch:FindFirstChildOfClass("Humanoid")
	local r=ch:WaitForChild("HumanoidRootPart",3)
	if not r then return end
	if hum then
		hum.WalkSpeed=16
		hum.JumpPower=50
		hum.AutoRotate=true
	end
	r.AssemblyLinearVelocity=Vector3.zero
	r.AssemblyAngularVelocity=Vector3.zero
	ch:PivotTo(target)
	print("[BUILDER] "..p.Name.." spawned at CreatorSpawn")
end

local function resetCreatorWorkspace(p)
	-- Remove only this player's editable objects. Published/saved data is untouched.
	for _,obj in ipairs(objects:GetChildren()) do
		if obj:GetAttribute("Owner")==p.UserId then
			obj:Destroy()
		end
	end

	-- Reset editor history/test/checkpoint state for a genuinely fresh creation.
	history[p]={}
	redoStack[p]={}
	testing[p]=false
	testStarted[p]=nil
	p:SetAttribute("CheckpointCF",nil)

	-- Reset verification state if these tables exist in this server version.
	if verified then verified[p]=nil end
	if verifiedTime then verifiedTime[p]=nil end

	print("[BUILDER] "..p.Name.." creator workspace reset")
end

creatorModeRemote.OnServerEvent:Connect(function(p,action)
	if action=="EnterCreator" then
		creatorMode[p]=true

		-- CREATE now resumes the player's work instead of wiping the plot.
		-- 1. If a saved draft exists, load that draft.
		-- 2. If no saved draft exists, leave any remaining objects in the plot untouched.
		-- Only transient editor/test history is reset.
		history[p]={}
		redoStack[p]={}
		testing[p]=false
		testStarted[p]=nil
		p:SetAttribute("CheckpointCF",nil)
		if verified then verified[p]=nil end
		if verifiedTime then verifiedTime[p]=nil end

		task.spawn(function()
			local loadedSaved=false
			if loadDraft then
				loadedSaved=loadDraft(p,true)==true
			end

			if loadedSaved then
				print("[BUILDER] "..p.Name.." resumed last saved draft")
			else
				print("[BUILDER] "..p.Name.." has no saved draft; keeping remaining plot objects")
				remote:FireClient(p,"ResumeExistingPlot",count and count(p) or 0)
			end

			task.wait(.15)
			if creatorMode[p] then
				sendToCreatorSpawn(p)
			end
		end)
	elseif action=="LeaveCreator" then
		creatorMode[p]=nil
	end
end)


-- =========================================================
-- RESERVED CREATOR GUEST PERMISSIONS
-- Owner always edits. Guests may edit only when explicitly promoted
-- to Collaborator by ParkourCreatorGuestPermissionServer.
-- =========================================================
local function creatorOwnerUserIdFor(player)
	local workspaceOwner=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))

	if workspaceOwner
		and (
			player.UserId==workspaceOwner
				or (
					player:GetAttribute("ParkourCreatorGuest")==true
					and player:GetAttribute("ParkourCanCollaborate")==true
				)
		) then
		return workspaceOwner
	end

	-- Normal/public Creator flow: player owns their own objects.
	return player.UserId
end

local function canEditCreator(player)
	local workspaceOwner=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))

	-- Reserved Creator server owner.
	if workspaceOwner and player.UserId==workspaceOwner then
		return true
	end

	-- Reserved Creator guest requires explicit Collaborator permission.
	if workspaceOwner and player:GetAttribute("ParkourCreatorGuest")==true then
		return player:GetAttribute("ParkourCanCollaborate")==true
			and player:GetAttribute("ParkourGuestPermissionRole")=="Collaborator"
	end

	-- Existing ordinary/public Creator behavior remains unchanged.
	return true
end

local function isReservedGuest(player)
	local workspaceOwner=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))
	return workspaceOwner~=nil
		and player.UserId~=workspaceOwner
		and player:GetAttribute("ParkourCreatorGuest")==true
end

local function denyEdit(player)
	remote:FireClient(player,"Notice","You need Collaborator permission to edit this parkour.")
end

local MAX_OBJECTS,GRID,LIMIT=100,2,76

local saveCooldown={}
local explicitClear={}
local SAVE_COOLDOWN=5
local verified={}
local verifiedTime={}
local TYPES={
	Platform={Color3.fromRGB(105,170,220),Enum.Material.SmoothPlastic,Vector3.new(10,2,10)},
	KillBlock={Color3.fromRGB(225,70,70),Enum.Material.Neon,Vector3.new(10,2,10)},
	BouncePad={Color3.fromRGB(80,220,120),Enum.Material.Neon,Vector3.new(10,2,10)},
	SpeedPad={Color3.fromRGB(235,195,65),Enum.Material.Neon,Vector3.new(10,1,10)},
	Checkpoint={Color3.fromRGB(170,90,225),Enum.Material.Neon,Vector3.new(10,1,10)},
	Start={Color3.fromRGB(80,235,160),Enum.Material.Neon,Vector3.new(12,1,12)},
	Finish={Color3.fromRGB(75,220,235),Enum.Material.Neon,Vector3.new(12,1,12)}
}
local function getBuildPlot()
	local creator=workspace:FindFirstChild("ParkourCreator")
	if not creator then return nil end
	return creator:FindFirstChild("BuildPlot")
end

local function positionInsidePlot(pos,size)
	local plot=getBuildPlot()
	if not plot then return false end

	local plotCF,plotSize
	if plot:IsA("BasePart") then
		plotCF,plotSize=plot.CFrame,plot.Size
	elseif plot:IsA("Model") then
		plotCF,plotSize=plot:GetBoundingBox()
	else
		return false
	end

	local lp=plotCF:PointToObjectSpace(pos)
	local hx=math.max(0,plotSize.X/2-size.X/2)
	local hz=math.max(0,plotSize.Z/2-size.Z/2)
	return math.abs(lp.X)<=hx and math.abs(lp.Z)<=hz
end

local function snap(n)return math.round(n/GRID)*GRID end
local function pos(v)return Vector3.new(math.clamp(snap(v.X),-LIMIT,LIMIT),math.clamp(math.max(3,snap(v.Y)),3,120),math.clamp(snap(v.Z),-LIMIT,LIMIT))end
local function valid(p,o)return o and o:IsA("BasePart")and o:IsDescendantOf(objects)and o:GetAttribute("Owner")==creatorOwnerUserIdFor(p) end
local function count(p)local ownerId=creatorOwnerUserIdFor(p);local n=0;for _,o in ipairs(objects:GetChildren())do if o:GetAttribute("Owner")==ownerId then n+=1 end end;return n end
local function snapObj(o)return{type=o:GetAttribute("ObjectType"),cf=o.CFrame,size=o.Size}end
local function push(p,e)history[p]=history[p]or{};table.insert(history[p],e);if#history[p]>50 then table.remove(history[p],1)end;redoStack[p]={}end
local function findType(p,t)local ownerId=creatorOwnerUserIdFor(p);for _,o in ipairs(objects:GetChildren())do if o:GetAttribute("Owner")==ownerId and o:GetAttribute("ObjectType")==t then return o end end end

local function make(p,t,cf,size)
	local d=TYPES[t]or TYPES.Platform;local o=Instance.new("Part");o.Name=t;o.Size=size or d[3];o.CFrame=cf;o.Anchored=true;o.CanCollide=true;o.Color=d[1];o.Material=d[2];o:SetAttribute("Owner",creatorOwnerUserIdFor(p));o:SetAttribute("ObjectType",t);o.Parent=objects
	o.Touched:Connect(function(hit)
		if not testing[p] then return end
		local ch=hit:FindFirstAncestorOfClass("Model");local hum=ch and ch:FindFirstChildOfClass("Humanoid");local pl=hum and Players:GetPlayerFromCharacter(ch);if not hum or pl~=p then return end
		if t=="KillBlock"then hum.Health=0
		elseif t=="BouncePad"then local r=ch:FindFirstChild("HumanoidRootPart");if r then r.AssemblyLinearVelocity=Vector3.new(r.AssemblyLinearVelocity.X,75,r.AssemblyLinearVelocity.Z)end
		elseif t=="SpeedPad"then hum.WalkSpeed=32;task.delay(1.5,function()if hum.Parent then hum.WalkSpeed=16 end end)
		elseif t=="Checkpoint"then p:SetAttribute("CheckpointCF",o.CFrame+Vector3.new(0,4,0))
		elseif t=="Finish"and testStarted[p]then local elapsed=os.clock()-testStarted[p];testing[p]=false;testStarted[p]=nil;verified[p]=true;verifiedTime[p]=elapsed;remote:FireClient(p,"VerificationChanged",true,elapsed);remote:FireClient(p,"Finished",elapsed)
			-- Finishing a test automatically ends Test Mode and returns player to CreatorSpawn.
			testing[p]=false
			testStarted[p]=nil
			p:SetAttribute("CheckpointCF",nil)
			remote:FireClient(p,"TestMode",false)
			task.delay(.15,function()
				if p.Parent then sendToCreatorSpawn(p) end
			end)end
	end)
	return o
end


local function serializeCF(cf)
	local c={cf:GetComponents()}
	return c
end

local function deserializeCF(c)
	if type(c)~="table" or #c<12 then return CFrame.new() end
	return CFrame.new(table.unpack(c))
end

local function serializeDraft(p)
	local data={version=1,objects={}}
	for _,o in ipairs(objects:GetChildren()) do
		if o:IsA("BasePart") and o:GetAttribute("Owner")==p.UserId then
			table.insert(data.objects,{
				type=o:GetAttribute("ObjectType") or "Platform",
				cf=serializeCF(o.CFrame),
				size={o.Size.X,o.Size.Y,o.Size.Z}
			})
		end
	end
	return data
end

local function clearOwned(p)
	for _,o in ipairs(objects:GetChildren()) do
		if o:GetAttribute("Owner")==p.UserId then o:Destroy() end
	end
	history[p]={}
	redoStack[p]={}
end

local function saveDraft(p,allowEmpty)
	local data=serializeDraft(p)
	local objectCount=#data.objects

	-- SAFE SAVE:
	-- Never let a temporary/accidental empty workspace overwrite a good draft.
	-- Empty saves are allowed only after the player explicitly cleared the plot.
	if objectCount==0 and not allowEmpty and not explicitClear[p] then
		local okExisting,existing=pcall(function()
			return DraftStore:GetAsync("draft_"..p.UserId)
		end)

		if not okExisting then
			warn("[SAFE SAVE] Could not verify existing draft for "..p.Name.."; empty save blocked.")
			remote:FireClient(p,"Notice","Empty auto-save skipped to protect your previous draft.")
			return false
		end

		if type(existing)=="table" and type(existing.objects)=="table" and #existing.objects>0 then
			warn("[SAFE SAVE] Blocked empty overwrite for "..p.Name.." ("..#existing.objects.." saved objects protected)")
			remote:FireClient(p,"Notice","Empty auto-save skipped � previous draft protected")
			return false
		end
	end

	local ok,err=pcall(function()
		DraftStore:SetAsync("draft_"..p.UserId,data)
	end)

	if ok then
		-- Once a deliberate empty state has safely reached DataStore, consume
		-- the clear flag. Future unexpected empty states are protected again.
		if objectCount==0 then explicitClear[p]=nil end
		remote:FireClient(p,"DraftSaved",objectCount)
		return true
	else
		warn("Draft save failed for "..p.Name..": "..tostring(err))
		remote:FireClient(p,"Notice","Draft save failed. Try again.")
		return false
	end
end

loadDraft=function(p,silentNoDraft)
	local ok,data=pcall(function()
		return DraftStore:GetAsync("draft_"..p.UserId)
	end)
	if not ok then
		warn("Draft load failed for "..p.Name..": "..tostring(data))
		remote:FireClient(p,"Notice","Draft load failed. Keeping current plot.")
		return false
	end
	if type(data)~="table" or type(data.objects)~="table" or #data.objects==0 then
		if not silentNoDraft then
			remote:FireClient(p,"Notice","No saved draft found.")
		end
		return false
	end
	clearOwned(p)
	local loaded=0
	for _,d in ipairs(data.objects) do
		if loaded>=MAX_OBJECTS then break end
		if type(d)=="table" and TYPES[d.type] and type(d.size)=="table" then
			local size=Vector3.new(
				tonumber(d.size[1]) or 10,
				tonumber(d.size[2]) or 2,
				tonumber(d.size[3]) or 10
			)
			make(p,d.type,deserializeCF(d.cf),size)
			loaded+=1
		end
	end
	if loaded>0 then explicitClear[p]=nil end
	remote:FireClient(p,"DraftLoaded",loaded)
	return true
end


local function invalidateVerification(p)
	if verified[p] then
		verified[p]=false
		verifiedTime[p]=nil
		remote:FireClient(p,"VerificationChanged",false)
	end
end

local function validationSummary(p)
	local start=findType(p,"Start")
	local finish=findType(p,"Finish")
	local total=count(p)
	local problems={}
	if not start then table.insert(problems,"Missing START block") end
	if not finish then table.insert(problems,"Missing FINISH block") end
	if total<3 then table.insert(problems,"Course needs at least 3 objects") end
	if not verified[p] then table.insert(problems,"Creator has not completed this version") end
	return #problems==0,problems,total
end


local function cleanText(text,maxLen)
	text=tostring(text or "")
	text=text:gsub("[%c\r\n]"," ")
	text=text:match("^%s*(.-)%s*$") or ""
	return text:sub(1,maxLen)
end

local function makeParkourId(p)
	-- UserId + millisecond-ish server timestamp + random suffix.
	return tostring(p.UserId).."_"..tostring(math.floor(os.time())).."_"..tostring(math.random(1000,9999))
end

local function publishCourse(p,title,description,difficulty)
	local ready,problems,total=validationSummary(p)
	if not ready then
		remote:FireClient(p,"PublishResult",false,"Course is not verified.")
		return
	end

	title=cleanText(title,40)
	description=cleanText(description,160)
	difficulty=cleanText(difficulty,12)

	if #title<3 then
		remote:FireClient(p,"PublishResult",false,"Title must be at least 3 characters.")
		return
	end

	local allowed={Easy=true,Medium=true,Hard=true,Extreme=true}
	if not allowed[difficulty] then difficulty="Medium" end

	local id=makeParkourId(p)
	local course=serializeDraft(p)
	local record={
		id=id,
		title=title,
		description=description,
		difficulty=difficulty,
		creatorUserId=p.UserId,
		creatorName=p.Name,
		publishedAt=os.time(),
		verifiedTime=verifiedTime[p],
		objectCount=total,
		plays=0,
		likes=0,
		course=course
	}

	local ok,err=pcall(function()
		PublishedStore:SetAsync("parkour_"..id,record)
		DiscoverIndex:UpdateAsync("published_ids",function(old)
			old=type(old)=="table" and old or {}
			-- Avoid duplicate ID entries.
			for _,existing in ipairs(old) do if existing==id then return old end end
			table.insert(old,1,id)
			while #old>100 do table.remove(old) end
			return old
		end)
		CreatorIndex:UpdateAsync("creator_"..p.UserId,function(old)
			old=type(old)=="table" and old or {}
			table.insert(old,1,id)
			while #old>25 do table.remove(old) end
			return old
		end)
	end)

	if not ok then
		warn("Publish failed for "..p.Name..": "..tostring(err))
		remote:FireClient(p,"PublishResult",false,"Publishing failed. Try again.")
		return
	end

	remote:FireClient(p,"PublishResult",true,id,title)
end

remote.OnServerEvent:Connect(function(p,a,b,c)
	local EDIT_ACTIONS={
		Place=true,Move=true,Rotate=true,RotateBy=true,
		Scale=true,Delete=true,Undo=true,Redo=true,
	}

	if EDIT_ACTIONS[a] and not canEditCreator(p) then
		denyEdit(p)
		return
	end

	-- Guests never control the owner's persistent draft/publish/test lifecycle.
	if isReservedGuest(p) and (
		a=="ClearPlot" or a=="Publish" or a=="SaveDraft"
			or a=="LoadDraft" or a=="ValidatePublish" or a=="Test"
		) then
		remote:FireClient(p,"Notice","Only the Creator owner can use this action.")
		return
	end

	if a=="ClearPlot" then
		explicitClear[p]=true
		for _,obj in ipairs(objects:GetChildren()) do
			if obj:GetAttribute("Owner")==p.UserId then obj:Destroy() end
		end
		history[p]={};redoStack[p]={};testing[p]=false;testStarted[p]=nil
		p:SetAttribute("CheckpointCF",nil)
		if verified then verified[p]=nil end
		if verifiedTime then verifiedTime[p]=nil end
		-- Clearing is an intentional destructive action, so persist the empty
		-- draft immediately instead of waiting for the next autosave.
		saveDraft(p,true)
		remote:FireClient(p,"ClearPlotResult",true)
		print("[BUILDER] "..p.Name.." cleared creator plot and saved the empty draft")
		return
	end
	if a=="Publish"then
		if typeof(b)=="table" then
			publishCourse(p,b.title,b.description,b.difficulty)
		end
	elseif a=="Place"and typeof(b)=="Vector3"then
		if count(p)>=MAX_OBJECTS then return end

		local t="Platform"
		local rotationY=0
		local scale=Vector3.new(1,1,1)

		if typeof(c)=="string" and TYPES[c] then
			t=c
		elseif typeof(c)=="table" then
			if type(c.type)=="string" and TYPES[c.type] then t=c.type end
			rotationY=tonumber(c.rotationY) or 0
			if type(c.scale)=="table" then
				scale=Vector3.new(
					math.clamp(tonumber(c.scale[1]) or 1,.5,3),
					math.clamp(tonumber(c.scale[2]) or 1,.5,3),
					math.clamp(tonumber(c.scale[3]) or 1,.5,3)
				)
			end
		end

		if(t=="Start"or t=="Finish")and findType(p,t)then
			remote:FireClient(p,"Notice","Only one "..t.." block is allowed.")
			return
		end

		local target=pos(b)
		local base=TYPES[t][3]
		local objectSize=Vector3.new(
			math.clamp(base.X*scale.X,4,30),
			math.clamp(base.Y*scale.Y,1,12),
			math.clamp(base.Z*scale.Z,4,30)
		)

		if not positionInsidePlot(target,objectSize) then
			remote:FireClient(p,"Notice","You can only place blocks inside your plot.")
			return
		end

		local cf=CFrame.new(target)*CFrame.Angles(0,math.rad(rotationY),0)
		local o=make(p,t,cf,objectSize)
		explicitClear[p]=nil
		push(p,{kind="Create",obj=o})
		invalidateVerification(p)
		remote:FireClient(p,"Created",o)
	elseif a=="Move"and valid(p,b)and typeof(c)=="Vector3"then
		local target=pos(c)
		if not positionInsidePlot(target,b.Size) then
			remote:FireClient(p,"Notice","You cannot move blocks outside your plot.")
			return
		end
		local before=b.CFrame;b.Position=target;push(p,{kind="Transform",obj=b,before=before,after=b.CFrame});invalidateVerification(p)
	elseif a=="Rotate"and valid(p,b)then local before=b.CFrame;b.CFrame*=CFrame.Angles(0,math.rad(15),0);push(p,{kind="Transform",obj=b,before=before,after=b.CFrame});invalidateVerification(p)
	elseif a=="RotateBy"and valid(p,b)and typeof(c)=="number"then
		local degrees=(c<0) and -1 or 1
		local before=b.CFrame
		local position=b.Position
		local rotated=b.CFrame*CFrame.Angles(0,math.rad(degrees),0)
		b.CFrame=CFrame.new(position)*rotated.Rotation

		-- Coalesce a rapid rotation burst into one Undo entry instead of
		-- creating 30+ history entries per second.
		local now=os.clock()
		local burst=rotateBurst[p]
		if burst and burst.obj==b and now-burst.last<.35 then
			burst.after=b.CFrame
			burst.last=now
		else
			burst={obj=b,before=before,after=b.CFrame,last=now}
			rotateBurst[p]=burst
			push(p,{kind="Transform",obj=b,before=before,after=b.CFrame})
		end

		-- Keep the most recent history entry's after-state current.
		local h=history[p]
		if h and #h>0 and burst then
			h[#h].after=b.CFrame
		end

		invalidateVerification(p)
		remote:FireClient(p,"Rotated",degrees)
	elseif a=="Scale"and valid(p,b)and typeof(c)=="number"then local before=b.Size;local d=c>0 and 2 or-2;b.Size=Vector3.new(math.clamp(b.Size.X+d,4,30),math.clamp(b.Size.Y,1,12),math.clamp(b.Size.Z+d,4,30));push(p,{kind="Size",obj=b,before=before,after=b.Size});invalidateVerification(p)
	elseif a=="Delete"and valid(p,b)then local d=snapObj(b);push(p,{kind="Delete",data=d});b:Destroy();invalidateVerification(p)
	elseif a=="Undo"then invalidateVerification(p);local h=history[p];if not h or#h==0 then return end;local e=table.remove(h);redoStack[p]=redoStack[p]or{};table.insert(redoStack[p],e);if e.kind=="Create"and e.obj and e.obj.Parent then e.data=snapObj(e.obj);e.obj:Destroy()elseif e.kind=="Delete"then e.obj=make(p,e.data.type,e.data.cf,e.data.size)elseif e.kind=="Transform"and e.obj and e.obj.Parent then e.obj.CFrame=e.before elseif e.kind=="Size"and e.obj and e.obj.Parent then e.obj.Size=e.before end
	elseif a=="Redo"then invalidateVerification(p);local r=redoStack[p];if not r or#r==0 then return end;local e=table.remove(r);history[p]=history[p]or{};table.insert(history[p],e);if e.kind=="Create"then e.obj=make(p,e.data.type,e.data.cf,e.data.size)elseif e.kind=="Delete"and e.obj and e.obj.Parent then e.data=snapObj(e.obj);e.obj:Destroy()elseif e.kind=="Transform"and e.obj and e.obj.Parent then e.obj.CFrame=e.after elseif e.kind=="Size"and e.obj and e.obj.Parent then e.obj.Size=e.after end
	elseif a=="ValidatePublish"then
		local ok,problems,total=validationSummary(p)
		remote:FireClient(p,"ValidationResult",ok,problems,total,verifiedTime[p])
	elseif a=="SaveDraft"then
		local now=os.clock()
		local remaining=SAVE_COOLDOWN-(now-(saveCooldown[p] or -SAVE_COOLDOWN))
		if remaining>0 then
			remote:FireClient(p,"SaveCooldown",remaining)
		else
			saveCooldown[p]=now
			remote:FireClient(p,"Saving")
			saveDraft(p)
		end
	elseif a=="LoadDraft"then
		if testing[p]then remote:FireClient(p,"Notice","Exit Test Mode before loading a draft.")else loadDraft(p);invalidateVerification(p)end
	elseif a=="Test"then
		if testing[p]then
			-- Manual EXIT TEST: clear test state and return to the CreatorSpawn.
			testing[p]=false
			testStarted[p]=nil
			p:SetAttribute("CheckpointCF",nil)
			remote:FireClient(p,"TestMode",false)
			task.delay(.1,function()
				if p.Parent then sendToCreatorSpawn(p) end
			end)
			return
		end
		local start=findType(p,"Start");local finish=findType(p,"Finish")
		if not start or not finish then remote:FireClient(p,"Notice","Place a START and FINISH block before testing.");return end
		testing[p]=true;testStarted[p]=os.clock();p:SetAttribute("CheckpointCF",nil)
		if p.Character then local r=p.Character:FindFirstChild("HumanoidRootPart");if r then r.CFrame=start.CFrame+Vector3.new(0,4,0)end end
		remote:FireClient(p,"TestMode",true)
	end
end)

Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function(ch)
		task.wait(.2)
		if creatorMode[p] then
			sendToCreatorSpawn(p)
			return
		end
		if testing[p] then
			local target=p:GetAttribute("CheckpointCF") or (findType(p,"Start") and (findType(p,"Start").CFrame+Vector3.new(0,4,0)))
			local r=ch:FindFirstChild("HumanoidRootPart")
			if target and r then r.CFrame=target end
		end
	end)
end)
Players.PlayerRemoving:Connect(function(p)
	-- A Collaborator/Viewer leaving must never save or destroy the owner's plot.
	if not isReservedGuest(p) then
		-- Protect a good draft from being overwritten if the workspace is
		-- unexpectedly empty during shutdown/teleport/script transitions.
		saveDraft(p,explicitClear[p]==true)
		for _,o in ipairs(objects:GetChildren()) do
			if o:GetAttribute("Owner")==p.UserId then o:Destroy() end
		end
	end
	history[p]=nil
	redoStack[p]=nil
	testing[p]=nil
	testStarted[p]=nil
	saveCooldown[p]=nil
	verified[p]=nil
	verifiedTime[p]=nil
	creatorMode[p]=nil
	explicitClear[p]=nil
end)
game:BindToClose(function()
	for _,p in ipairs(Players:GetPlayers()) do
		if not isReservedGuest(p) then
			saveDraft(p,explicitClear[p]==true)
		end
	end
end)
print("Parkour Builder V7.1 + Guest Permission Enforcement loaded")

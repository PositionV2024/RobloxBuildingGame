-- MAKE YOUR OWN PARKOUR - TASK 18 COMMUNITY PLAY SERVER
-- Create ServerScriptService > ParkourCommunityPlayServer
-- Loads published courses into an isolated play area and tracks plays/completion.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local DSS=game:GetService("DataStoreService")

local PublishedStore=DSS:GetDataStore("PublishedParkours_V1")
local VisitorStore=DSS:GetDataStore("ParkourVisitors_V1")
local remote=RS:FindFirstChild("ParkourCommunityEvent") or Instance.new("RemoteEvent")
remote.Name="ParkourCommunityEvent";remote.Parent=RS

local leaderboardRemote=RS:FindFirstChild("ParkourLeaderboardEvent")
if not leaderboardRemote then
	leaderboardRemote=Instance.new("RemoteEvent")
	leaderboardRemote.Name="ParkourLeaderboardEvent"
	leaderboardRemote.Parent=RS
end

local sessions={}
local BASE=Vector3.new(350,25,0)

local COLORS={
	Platform=Color3.fromRGB(105,170,220),KillBlock=Color3.fromRGB(225,70,70),
	BouncePad=Color3.fromRGB(80,220,120),SpeedPad=Color3.fromRGB(235,195,65),
	Checkpoint=Color3.fromRGB(170,90,225),Start=Color3.fromRGB(80,235,160),
	Finish=Color3.fromRGB(75,220,235)
}
local MATERIALS={KillBlock=Enum.Material.Neon,BouncePad=Enum.Material.Neon,SpeedPad=Enum.Material.Neon,Checkpoint=Enum.Material.Neon,Start=Enum.Material.Neon,Finish=Enum.Material.Neon}

local function cfFrom(t)
	if type(t)~="table"or#t<12 then return CFrame.new()end
	return CFrame.new(table.unpack(t))
end

local function cleanup(p)
	local s=sessions[p]
	if s and s.model then s.model:Destroy()end
	sessions[p]=nil
end

local function behavior(p,o,t)
	o.Touched:Connect(function(hit)
		local s=sessions[p];if not s or s.finished then return end
		local ch=hit:FindFirstAncestorOfClass("Model");if ch~=p.Character then return end
		local hum=ch:FindFirstChildOfClass("Humanoid");local root=ch:FindFirstChild("HumanoidRootPart");if not hum then return end
		if t=="KillBlock"then hum.Health=0
		elseif t=="BouncePad"and root then root.AssemblyLinearVelocity=Vector3.new(root.AssemblyLinearVelocity.X,75,root.AssemblyLinearVelocity.Z)
		elseif t=="SpeedPad"then hum.WalkSpeed=32;task.delay(1.5,function()if hum.Parent then hum.WalkSpeed=16 end end)
		elseif t=="Checkpoint"then s.checkpoint=o.CFrame+Vector3.new(0,4,0)
		elseif t=="Finish"then
			s.finished=true
			local elapsed=os.clock()-s.started
			remote:FireClient(p,"Finished",elapsed,s.title)
			-- Submit only after the server itself detects the Finish block.
			leaderboardRemote:FireClient(p,"SubmitVerified",s.id,elapsed)
		end
	end)
end


local function recordVisit(p,id)
	local visitorKey="visitors_"..id
	local uniqueKey="visited_"..id.."_"..p.UserId
	local firstVisit=false

	pcall(function()
		VisitorStore:UpdateAsync(uniqueKey,function(old)
			if old==true then return true end
			firstVisit=true
			return true
		end)

		VisitorStore:UpdateAsync(visitorKey,function(old)
			old=type(old)=="table" and old or {count=0,recent={}}
			old.recent=type(old.recent)=="table" and old.recent or {}

			if firstVisit then old.count=(old.count or 0)+1 end

			-- One current entry per visitor.
			local nextRecent={}
			for _,v in ipairs(old.recent) do
				if tonumber(v.userId)~=p.UserId then table.insert(nextRecent,v) end
			end
			table.insert(nextRecent,1,{
				userId=p.UserId,
				name=p.Name,
				visitedAt=os.time()
			})
			while #nextRecent>6 do table.remove(nextRecent) end
			old.recent=nextRecent
			return old
		end)
	end)
end

local function loadCourse(p,id)
	cleanup(p)
	local ok,data=pcall(function()return PublishedStore:GetAsync("parkour_"..id)end)
	if not ok or type(data)~="table"or type(data.course)~="table"or type(data.course.objects)~="table"then
		remote:FireClient(p,"PlayError","Unable to load this parkour.");return
	end

	local model=Instance.new("Model");model.Name="CommunityParkour_"..p.UserId;model.Parent=workspace
	local startCF=nil
	for _,d in ipairs(data.course.objects)do
		if type(d)=="table"and type(d.size)=="table"then
			local t=d.type or"Platform";local localCF=cfFrom(d.cf)
			local worldCF=CFrame.new(BASE)*localCF
			local o=Instance.new("Part");o.Name=t;o.Size=Vector3.new(tonumber(d.size[1])or 10,tonumber(d.size[2])or 2,tonumber(d.size[3])or 10);o.CFrame=worldCF;o.Anchored=true;o.CanCollide=true;o.Color=COLORS[t]or COLORS.Platform;o.Material=MATERIALS[t]or Enum.Material.SmoothPlastic;o.Parent=model
			behavior(p,o,t)
			if t=="Start"then startCF=worldCF+Vector3.new(0,4,0)end
		end
	end
	if not startCF then model:Destroy();remote:FireClient(p,"PlayError","Published course has no START.");return end

	sessions[p]={model=model,id=id,title=data.title or"Parkour",start=startCF,checkpoint=nil,started=os.clock(),finished=false}
	recordVisit(p,id)
	-- Increment play count once when loaded.
	pcall(function()
		PublishedStore:UpdateAsync("parkour_"..id,function(old)
			if type(old)=="table"then old.plays=(old.plays or 0)+1 end
			return old
		end)
	end)

	if not p.Character then p:LoadCharacter();task.wait(.5)end
	local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if root then root.CFrame=startCF end
	remote:FireClient(p,"PlayStarted",data.title or"Parkour",data.creatorName or"Unknown")
end

local function restartCourse(p)
	local s=sessions[p]
	if not s or not s.model then return end

	s.finished=false
	s.checkpoint=nil
	s.started=os.clock()

	local char=p.Character
	if not char then
		p:LoadCharacter()
		return
	end

	local hum=char:FindFirstChildOfClass("Humanoid")
	local root=char:FindFirstChild("HumanoidRootPart")
	if hum then
		hum.Health=hum.MaxHealth
		hum.WalkSpeed=16
	end
	if root then
		root.AssemblyLinearVelocity=Vector3.zero
		root.AssemblyAngularVelocity=Vector3.zero
		root.CFrame=s.start
	end

	remote:FireClient(p,"Restarted")
end

remote.OnServerEvent:Connect(function(p,action,id)
	if action=="Play"and type(id)=="string"and#id<100 then loadCourse(p,id)
	elseif action=="Restart"then restartCourse(p)
	elseif action=="Exit"then cleanup(p);remote:FireClient(p,"Exited")end
end)

local function hook(p)
	p.CharacterAdded:Connect(function(ch)
		task.wait(.25);local s=sessions[p];if s and not s.finished then
			local root=ch:FindFirstChild("HumanoidRootPart")
			if root then root.CFrame=s.checkpoint or s.start end
		end
	end)
end
Players.PlayerAdded:Connect(hook);for _,p in ipairs(Players:GetPlayers())do hook(p)end
Players.PlayerRemoving:Connect(cleanup)

print("Task 20-compatible Community Play server loaded")

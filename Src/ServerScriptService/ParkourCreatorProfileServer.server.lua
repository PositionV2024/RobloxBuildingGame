-- MAKE YOUR OWN PARKOUR - TASK 21 CREATOR PROFILES SERVER
-- Create ServerScriptService > ParkourCreatorProfileServer
-- Loads a creator's published courses and aggregate stats.

local RS=game:GetService("ReplicatedStorage")
local DSS=game:GetService("DataStoreService")
local Players=game:GetService("Players")

local PublishedStore=DSS:GetDataStore("PublishedParkours_V1")
local CreatorIndex=DSS:GetDataStore("ParkourCreatorIndex_V1")

local remote=RS:FindFirstChild("ParkourCreatorProfileEvent") or Instance.new("RemoteEvent")
remote.Name="ParkourCreatorProfileEvent"
remote.Parent=RS

local cooldown={}

local function safeCourse(id)
	local ok,data=pcall(function()
		return PublishedStore:GetAsync("parkour_"..id)
	end)
	if ok and type(data)=="table" then
		return {
			id=data.id or id,
			title=data.title or "Untitled Parkour",
			difficulty=data.difficulty or "Medium",
			plays=data.plays or 0,
			likes=data.likes or 0,
			dislikes=data.dislikes or 0,
			publishedAt=data.publishedAt or 0,
			objectCount=data.objectCount or 0
		}
	end
end

local function getProfile(requester,userId,fallbackName)
	userId=tonumber(userId)
	if not userId or userId<=0 then return end

	local ok,ids=pcall(function()
		return CreatorIndex:GetAsync("creator_"..userId)
	end)

	local courses={}
	local totalPlays,totalLikes,totalDislikes=0,0,0

	if ok and type(ids)=="table" then
		for _,id in ipairs(ids) do
			if #courses>=25 then break end
			local c=safeCourse(id)
			if c then
				table.insert(courses,c)
				totalPlays+=c.plays
				totalLikes+=c.likes
				totalDislikes+=c.dislikes
			end
		end
	end

	table.sort(courses,function(a,b)
		return (a.publishedAt or 0)>(b.publishedAt or 0)
	end)

	local creatorName=tostring(fallbackName or "Unknown")
	local online=Players:GetPlayerByUserId(userId)
	if online then creatorName=online.Name end

	remote:FireClient(requester,"Profile",{
		userId=userId,
		name=creatorName,
		creationCount=#courses,
		totalPlays=totalPlays,
		totalLikes=totalLikes,
		totalDislikes=totalDislikes,
		courses=courses
	})
end

remote.OnServerEvent:Connect(function(player,action,userId,name)
	if action~="GetProfile" then return end
	local now=os.clock()
	if cooldown[player] and now-cooldown[player]<.5 then return end
	cooldown[player]=now
	getProfile(player,userId,name)
end)

Players.PlayerRemoving:Connect(function(p)cooldown[p]=nil end)

print("Task 21 Creator Profiles server loaded")

-- MAKE YOUR OWN PARKOUR - TASK 16 DISCOVER SERVER
-- Create ServerScriptService > ParkourDiscoverServer
-- Requires Task 15's PublishedParkours_V1 / ParkourCreatorIndex_V1 stores.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local DSS=game:GetService("DataStoreService")

local PublishedStore=DSS:GetDataStore("PublishedParkours_V1")
local CreatorIndex=DSS:GetDataStore("ParkourCreatorIndex_V1")
local DiscoverIndex=DSS:GetDataStore("ParkourDiscoverIndex_V1")

local remote=RS:FindFirstChild("ParkourDiscoverEvent")
if not remote then
	remote=Instance.new("RemoteEvent")
	remote.Name="ParkourDiscoverEvent"
	remote.Parent=RS
end

local MAX_RESULTS=24

local function safeRecord(id)
	local ok,data=pcall(function()
		return PublishedStore:GetAsync("parkour_"..id)
	end)
	if ok and type(data)=="table" then
		-- Never send full course geometry to Discover UI.
		return {
			id=data.id or id,
			title=data.title or "Untitled Parkour",
			description=data.description or "",
			difficulty=data.difficulty or "Medium",
			creatorName=data.creatorName or "Unknown",
			creatorUserId=data.creatorUserId or 0,
			publishedAt=data.publishedAt or 0,
			verifiedTime=data.verifiedTime,
			objectCount=data.objectCount or 0,
			plays=data.plays or 0,
			likes=data.likes or 0
		}
	end
end

local function readIds()
	local ok,ids=pcall(function()
		return DiscoverIndex:GetAsync("published_ids")
	end)
	if not ok or type(ids)~="table" then return {} end
	return ids
end

local function discover(mode)
	local ids=readIds()
	local records={}
	for _,id in ipairs(ids) do
		if #records>=MAX_RESULTS then break end
		local rec=safeRecord(id)
		if rec then table.insert(records,rec) end
	end

	if mode=="MostPlayed" then
		table.sort(records,function(a,b)return (a.plays or 0)>(b.plays or 0) end)
	elseif mode=="MostLiked" then
		table.sort(records,function(a,b)return (a.likes or 0)>(b.likes or 0) end)
	else -- New
		table.sort(records,function(a,b)return (a.publishedAt or 0)>(b.publishedAt or 0) end)
	end
	return records
end

remote.OnServerEvent:Connect(function(player,action,arg)
	if action=="Discover" then
		remote:FireClient(player,"DiscoverResults",discover(arg or "New"),arg or "New")
	elseif action=="MyCreations" then
		local ok,ids=pcall(function()
			return CreatorIndex:GetAsync("creator_"..player.UserId)
		end)
		local results={}
		if ok and type(ids)=="table" then
			for _,id in ipairs(ids) do
				if #results>=MAX_RESULTS then break end
				local rec=safeRecord(id)
				if rec then table.insert(results,rec) end
			end
		end
		remote:FireClient(player,"DiscoverResults",results,"My Creations")
	end
end)

print("Task 16 Parkour Discover server loaded")

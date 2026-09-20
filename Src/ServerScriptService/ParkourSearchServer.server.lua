-- MAKE YOUR OWN PARKOUR - TASK 22 SEARCH SERVER
-- Create ServerScriptService > ParkourSearchServer
-- Searches published parkour titles and creator names from the Discover index.

local RS=game:GetService("ReplicatedStorage")
local DSS=game:GetService("DataStoreService")
local Players=game:GetService("Players")

local PublishedStore=DSS:GetDataStore("PublishedParkours_V1")
local DiscoverIndex=DSS:GetDataStore("ParkourDiscoverIndex_V1")

local remote=RS:FindFirstChild("ParkourSearchEvent") or Instance.new("RemoteEvent")
remote.Name="ParkourSearchEvent"
remote.Parent=RS

local cooldown={}
local MAX_RESULTS=20

local function normalize(s)
	s=tostring(s or ""):lower()
	s=s:gsub("^%s+",""):gsub("%s+$","")
	return s:sub(1,40)
end

local function summary(id)
	local ok,d=pcall(function()
		return PublishedStore:GetAsync("parkour_"..id)
	end)
	if ok and type(d)=="table" then
		return {
			id=d.id or id,
			title=d.title or "Untitled Parkour",
			description=d.description or "",
			difficulty=d.difficulty or "Medium",
			creatorName=d.creatorName or "Unknown",
			creatorUserId=d.creatorUserId or 0,
			publishedAt=d.publishedAt or 0,
			plays=d.plays or 0,
			likes=d.likes or 0,
			dislikes=d.dislikes or 0,
			objectCount=d.objectCount or 0
		}
	end
end

local function search(query)
	query=normalize(query)
	if #query<2 then return {} end

	local ok,ids=pcall(function()
		return DiscoverIndex:GetAsync("published_ids")
	end)
	if not ok or type(ids)~="table" then return {} end

	local results={}
	for _,id in ipairs(ids) do
		if #results>=MAX_RESULTS then break end
		local d=summary(id)
		if d then
			local title=normalize(d.title)
			local creator=normalize(d.creatorName)
			local idText=normalize(d.id)
			if title:find(query,1,true)
				or creator:find(query,1,true)
				or idText==query then
				table.insert(results,d)
			end
		end
	end

	table.sort(results,function(a,b)
		local aq=normalize(a.title)==query
		local bq=normalize(b.title)==query
		if aq~=bq then return aq end
		return (a.plays or 0)>(b.plays or 0)
	end)

	return results
end

remote.OnServerEvent:Connect(function(player,action,query)
	if action~="Search" then return end

	local now=os.clock()
	if cooldown[player] and now-cooldown[player]<.45 then return end
	cooldown[player]=now

	query=normalize(query)
	if #query<2 then
		remote:FireClient(player,"SearchResults",{},query)
		return
	end

	remote:FireClient(player,"SearchResults",search(query),query)
end)

Players.PlayerRemoving:Connect(function(p)
	cooldown[p]=nil
end)

print("Task 22 Parkour Search server loaded")

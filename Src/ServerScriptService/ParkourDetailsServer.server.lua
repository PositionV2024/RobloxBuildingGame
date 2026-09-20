-- MAKE YOUR OWN PARKOUR - TASK 17 DETAILS SERVER
-- Create ServerScriptService > ParkourDetailsServer
-- Returns metadata for one published parkour. Full course geometry stays server-side.

local RS=game:GetService("ReplicatedStorage")
local DSS=game:GetService("DataStoreService")
local PublishedStore=DSS:GetDataStore("PublishedParkours_V1")
local VisitorStore=DSS:GetDataStore("ParkourVisitors_V1")

local remote=RS:FindFirstChild("ParkourDetailsEvent")
if not remote then
	remote=Instance.new("RemoteEvent")
	remote.Name="ParkourDetailsEvent"
	remote.Parent=RS
end

remote.OnServerEvent:Connect(function(player,action,id)
	if action~="GetDetails" or type(id)~="string" or #id>80 then return end

	local ok,data=pcall(function()
		return PublishedStore:GetAsync("parkour_"..id)
	end)

	if not ok then
		remote:FireClient(player,"DetailsError","Unable to load this parkour.")
		return
	end
	if type(data)~="table" then
		remote:FireClient(player,"DetailsError","This parkour could not be found.")
		return
	end

	local visitorData={count=0,recent={}}
	pcall(function()
		local v=VisitorStore:GetAsync("visitors_"..id)
		if type(v)=="table" then visitorData=v end
	end)

	remote:FireClient(player,"Details",{
		id=data.id or id,
		title=data.title or "Untitled Parkour",
		description=data.description or "No description.",
		difficulty=data.difficulty or "Medium",
		creatorName=data.creatorName or "Unknown",
		creatorUserId=data.creatorUserId or 0,
		publishedAt=data.publishedAt or 0,
		verifiedTime=data.verifiedTime,
		objectCount=data.objectCount or 0,
		plays=data.plays or 0,
		likes=data.likes or 0,
		visitorCount=visitorData.count or 0,
		recentVisitors=visitorData.recent or {}
	})
end)

print("Task 17 Parkour Details server loaded")

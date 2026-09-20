-- MAKE YOUR OWN PARKOUR - CREATOR DELETE SYSTEM
-- Create ServerScriptService > ParkourDeleteServer
-- Lets ONLY the original creator delete a published parkour.

local RS=game:GetService("ReplicatedStorage")
local DSS=game:GetService("DataStoreService")

local PublishedStore=DSS:GetDataStore("PublishedParkours_V1")
local CreatorIndex=DSS:GetDataStore("ParkourCreatorIndex_V1")
local DiscoverIndex=DSS:GetDataStore("ParkourDiscoverIndex_V1")
local BestTimes=DSS:GetDataStore("ParkourBestTimes_V1")

local remote=RS:FindFirstChild("ParkourDeleteEvent") or Instance.new("RemoteEvent")
remote.Name="ParkourDeleteEvent"
remote.Parent=RS

local cooldown={}
local deleting={}

local function removeFromList(list,id)
	if type(list)~="table" then return {} end
	local new={}
	for _,v in ipairs(list) do
		if tostring(v)~=tostring(id) then table.insert(new,v) end
	end
	return new
end

remote.OnServerEvent:Connect(function(player,action,id)
	if action~="Delete" or type(id)~="string" or #id>100 then return end

	local now=os.clock()
	if cooldown[player] and now-cooldown[player]<2 then return end
	cooldown[player]=now

	local lock=tostring(player.UserId)..":"..id
	if deleting[lock] then return end
	deleting[lock]=true

	local ok,record=pcall(function()
		return PublishedStore:GetAsync("parkour_"..id)
	end)

	if not ok or type(record)~="table" then
		deleting[lock]=nil
		remote:FireClient(player,"DeleteResult",false,"Creation could not be found.")
		return
	end

	-- Critical security check: never trust the client.
	if tonumber(record.creatorUserId)~=player.UserId then
		deleting[lock]=nil
		warn(player.Name.." attempted to delete parkour they do not own: "..id)
		remote:FireClient(player,"DeleteResult",false,"You can only delete your own creations.")
		return
	end

	local success,err=pcall(function()
		-- Remove the actual published course.
		PublishedStore:RemoveAsync("parkour_"..id)

		-- Remove from creator profile / My Creations.
		CreatorIndex:UpdateAsync("creator_"..player.UserId,function(old)
			return removeFromList(old,id)
		end)

		-- Remove from Discover/Search global index.
		DiscoverIndex:UpdateAsync("published_ids",function(old)
			return removeFromList(old,id)
		end)

		-- Remove leaderboard for this course.
		BestTimes:RemoveAsync("times_"..id)
	end)

	deleting[lock]=nil

	if success then
		remote:FireClient(player,"DeleteResult",true,id)
	else
		warn("Delete failed: "..tostring(err))
		remote:FireClient(player,"DeleteResult",false,"Delete failed. Please try again.")
	end
end)

print("? Creator Delete System loaded")

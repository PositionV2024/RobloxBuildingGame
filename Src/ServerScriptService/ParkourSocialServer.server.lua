-- MAKE YOUR OWN PARKOUR - TASK 19 LIKES + FAVORITES SERVER
-- Create ServerScriptService > ParkourSocialServer
-- Likes affect public parkour stats. Favorites are saved per player.

local RS=game:GetService("ReplicatedStorage")
local DSS=game:GetService("DataStoreService")

local PublishedStore=DSS:GetDataStore("PublishedParkours_V1")
local LikeStore=DSS:GetDataStore("ParkourLikes_V1")
local DislikeStore=DSS:GetDataStore("ParkourDislikes_V1")
local FavoriteStore=DSS:GetDataStore("ParkourFavorites_V1")

local remote=RS:FindFirstChild("ParkourSocialEvent") or Instance.new("RemoteEvent")
remote.Name="ParkourSocialEvent";remote.Parent=RS

local cooldown={}
local COOLDOWN=.6

local function key(p,id)return tostring(p.UserId).."_"..id end

local function getState(p,id)
	local liked,disliked,favorited=false,false,false
	pcall(function()liked=LikeStore:GetAsync("like_"..key(p,id))==true end)
	pcall(function()disliked=DislikeStore:GetAsync("dislike_"..key(p,id))==true end)
	pcall(function()favorited=FavoriteStore:GetAsync("fav_"..key(p,id))==true end)
	return liked,disliked,favorited
end

local function toggleLike(p,id)
	local likeKey="like_"..key(p,id)
	local dislikeKey="dislike_"..key(p,id)
	local liked=false
	local wasDisliked=false

	local ok=pcall(function()
		wasDisliked=DislikeStore:GetAsync(dislikeKey)==true
		LikeStore:UpdateAsync(likeKey,function(old)
			liked=old~=true
			return liked
		end)

		if liked and wasDisliked then
			DislikeStore:SetAsync(dislikeKey,false)
		end

		PublishedStore:UpdateAsync("parkour_"..id,function(data)
			if type(data)=="table" then
				data.likes=math.max(0,(data.likes or 0)+(liked and 1 or -1))
				if liked and wasDisliked then
					data.dislikes=math.max(0,(data.dislikes or 0)-1)
				end
			end
			return data
		end)
	end)

	if not ok then remote:FireClient(p,"SocialError","Unable to update like.")return end

	local likes,dislikes=0,0
	pcall(function()
		local d=PublishedStore:GetAsync("parkour_"..id)
		if type(d)=="table"then likes=d.likes or 0;dislikes=d.dislikes or 0 end
	end)
	remote:FireClient(p,"LikeChanged",id,liked,likes,liked and wasDisliked,dislikes)
end

local function toggleDislike(p,id)
	local likeKey="like_"..key(p,id)
	local dislikeKey="dislike_"..key(p,id)
	local disliked=false
	local wasLiked=false

	local ok=pcall(function()
		wasLiked=LikeStore:GetAsync(likeKey)==true
		DislikeStore:UpdateAsync(dislikeKey,function(old)
			disliked=old~=true
			return disliked
		end)

		if disliked and wasLiked then
			LikeStore:SetAsync(likeKey,false)
		end

		PublishedStore:UpdateAsync("parkour_"..id,function(data)
			if type(data)=="table" then
				data.dislikes=math.max(0,(data.dislikes or 0)+(disliked and 1 or -1))
				if disliked and wasLiked then
					data.likes=math.max(0,(data.likes or 0)-1)
				end
			end
			return data
		end)
	end)

	if not ok then remote:FireClient(p,"SocialError","Unable to update dislike.")return end

	local likes,dislikes=0,0
	pcall(function()
		local d=PublishedStore:GetAsync("parkour_"..id)
		if type(d)=="table"then likes=d.likes or 0;dislikes=d.dislikes or 0 end
	end)
	remote:FireClient(p,"DislikeChanged",id,disliked,dislikes,disliked and wasLiked,likes)
end

local function toggleFavorite(p,id)
	local k="fav_"..key(p,id)
	local favorited=false
	local ok=pcall(function()
		FavoriteStore:UpdateAsync(k,function(old)
			favorited=old~=true
			return favorited
		end)
	end)
	if not ok then remote:FireClient(p,"SocialError","Unable to update favorite.")return end
	remote:FireClient(p,"FavoriteChanged",id,favorited)
end

remote.OnServerEvent:Connect(function(p,action,id)
	if type(id)~="string"or#id>100 then return end
	local now=os.clock()
	if cooldown[p]and now-cooldown[p]<COOLDOWN and(action=="ToggleLike"or action=="ToggleDislike"or action=="ToggleFavorite")then return end

	if action=="GetState"then
		local liked,disliked,fav=getState(p,id)
		remote:FireClient(p,"SocialState",id,liked,disliked,fav)
	elseif action=="ToggleLike"then
		cooldown[p]=now;toggleLike(p,id)
	elseif action=="ToggleDislike"then
		cooldown[p]=now;toggleDislike(p,id)
	elseif action=="ToggleFavorite"then
		cooldown[p]=now;toggleFavorite(p,id)
	end
end)

print("Task 19.1 Likes + Dislikes + Favorites server loaded")

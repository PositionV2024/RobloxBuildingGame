-- MAKE YOUR OWN PARKOUR - TASK 20 LEADERBOARDS SERVER
-- Create ServerScriptService > ParkourLeaderboardServer
-- Stores each player's BEST completion time per published parkour.
-- Returns the top 10 fastest verified runs.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local DSS=game:GetService("DataStoreService")

local BestTimes=DSS:GetDataStore("ParkourBestTimes_V1")
local remote=RS:FindFirstChild("ParkourLeaderboardEvent") or Instance.new("RemoteEvent")
remote.Name="ParkourLeaderboardEvent"
remote.Parent=RS

local MAX_ENTRIES=10
local requestCooldown={}

local function leaderboardKey(id)
	return "times_"..id
end

local function cleanEntries(entries)
	if type(entries)~="table" then return {} end
	local result={}
	for _,e in ipairs(entries) do
		if type(e)=="table"
			and tonumber(e.userId)
			and type(e.name)=="string"
			and tonumber(e.time)
			and e.time>0 then
			table.insert(result,{
				userId=tonumber(e.userId),
				name=e.name:sub(1,24),
				time=tonumber(e.time)
			})
		end
	end
	table.sort(result,function(a,b)return a.time<b.time end)
	while #result>MAX_ENTRIES do table.remove(result) end
	return result
end

local function submitTime(player,id,time)
	time=tonumber(time)
	if type(id)~="string" or #id>100 or not time or time<=0 or time>7200 then return end

	local updated={}
	local ok,err=pcall(function()
		updated=BestTimes:UpdateAsync(leaderboardKey(id),function(old)
			local entries=cleanEntries(old)
			local found=false

			for _,e in ipairs(entries) do
				if e.userId==player.UserId then
					found=true
					if time<e.time then
						e.time=time
						e.name=player.Name
					end
					break
				end
			end

			if not found then
				table.insert(entries,{
					userId=player.UserId,
					name=player.Name,
					time=time
				})
			end

			return cleanEntries(entries)
		end)
	end)

	if not ok then
		warn("Leaderboard submit failed: "..tostring(err))
		return
	end

	remote:FireClient(player,"Leaderboard",id,cleanEntries(updated))
end

local function getBoard(player,id)
	if type(id)~="string" or #id>100 then return end
	local now=os.clock()
	if requestCooldown[player] and now-requestCooldown[player]<.5 then return end
	requestCooldown[player]=now

	local ok,data=pcall(function()
		return BestTimes:GetAsync(leaderboardKey(id))
	end)

	if ok then
		remote:FireClient(player,"Leaderboard",id,cleanEntries(data))
	else
		remote:FireClient(player,"LeaderboardError",id)
	end
end

remote.OnServerEvent:Connect(function(player,action,id,time)
	if action=="Get" then
		getBoard(player,id)
	elseif action=="Submit" then
		submitTime(player,id,time)
	end
end)

Players.PlayerRemoving:Connect(function(p)
	requestCooldown[p]=nil
end)

print("Task 20 Parkour Leaderboard server loaded")

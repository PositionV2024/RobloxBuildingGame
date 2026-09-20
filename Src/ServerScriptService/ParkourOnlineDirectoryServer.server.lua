-- ParkourOnlineDirectoryServer V1.2 - PLAYER STATUS
-- ServerScriptService
--
-- MemoryStore cross-server online directory.
-- Adds status:
--   IN LOBBY
--   IN CREATOR SERVER

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local MemoryStoreService=game:GetService("MemoryStoreService")

local Directory=MemoryStoreService:GetSortedMap("ParkourOnlinePublicPlayers_V1")
local TTL=45
local REFRESH=15

local remote=RS:FindFirstChild("ParkourOnlineDirectoryEvent") or Instance.new("RemoteEvent")
remote.Name="ParkourOnlineDirectoryEvent"
remote.Parent=RS

local function key(id)
	return "player_"..tostring(id)
end

local function getStatus(p)
	-- Detect Creator mode from both the player's role attributes and
	-- the authoritative server-level Creator owner attribute.
	local ownerUserId=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))

	if p:GetAttribute("ParkourPrivateCreator")==true
		or p:GetAttribute("ParkourCreatorOwner")==true
		or p:GetAttribute("ParkourCreatorGuest")==true
		or ownerUserId~=nil then
		return "IN CREATOR SERVER"
	end

	return "IN LOBBY"
end

local function publish(p)
	if not p or not p.Parent then return end

	local data={
		userId=p.UserId,
		username=p.Name,
		displayName=p.DisplayName,
		status=getStatus(p),
	}

	local ok,err=pcall(function()
		Directory:SetAsync(key(p.UserId),data,TTL,os.time())
	end)
	if not ok then
		warn("[ONLINE DIRECTORY] Publish failed for "..p.Name..": "..tostring(err))
	end
end

local function remove(p)
	if not p then return end
	pcall(function()
		Directory:RemoveAsync(key(p.UserId))
	end)
end

local function watchPlayer(p)
	local function statusChanged()
		-- Publish immediately instead of waiting for the 15-second heartbeat.
		publish(p)
	end

	p:GetAttributeChangedSignal("ParkourPrivateCreator"):Connect(statusChanged)
	p:GetAttributeChangedSignal("ParkourCreatorOwner"):Connect(statusChanged)
	p:GetAttributeChangedSignal("ParkourCreatorGuest"):Connect(statusChanged)
	p:GetAttributeChangedSignal("ParkourCreatorRole"):Connect(statusChanged)

	task.defer(statusChanged)
end

workspace:GetAttributeChangedSignal("ParkourCreatorOwnerUserId"):Connect(function()
	for _,p in ipairs(Players:GetPlayers()) do
		task.spawn(publish,p)
	end
end)

Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(remove)

for _,p in ipairs(Players:GetPlayers()) do
	watchPlayer(p)
end

task.spawn(function()
	while true do
		task.wait(REFRESH)
		for _,p in ipairs(Players:GetPlayers()) do
			publish(p)
		end
	end
end)

remote.OnServerEvent:Connect(function(p,action)
	if action~="Request" then return end

	local out={}
	local foundSelf=false

	local ok,items=pcall(function()
		return Directory:GetRangeAsync(Enum.SortDirection.Descending,100)
	end)

	if ok and type(items)=="table" then
		for _,item in ipairs(items) do
			local d=item.value
			if type(d)=="table" and tonumber(d.userId) then
				local row={
					userId=tonumber(d.userId),
					username=tostring(d.username or ""),
					displayName=tostring(d.displayName or d.username or ""),
					status=tostring(d.status or "IN LOBBY"),
					isSelf=tonumber(d.userId)==p.UserId,
				}
				if row.isSelf then foundSelf=true end
				table.insert(out,row)
			end
		end
	else
		warn("[ONLINE DIRECTORY] Read failed: "..tostring(items))
	end

	-- Always show the requesting player immediately with their current local status.
	if not foundSelf then
		table.insert(out,1,{
			userId=p.UserId,
			username=p.Name,
			displayName=p.DisplayName,
			status=getStatus(p),
			isSelf=true,
		})
	end

	remote:FireClient(p,"Directory",out)
end)

print("? ParkourOnlineDirectoryServer V1.3 Creator status fix loaded")

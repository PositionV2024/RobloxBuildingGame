-- ServerScriptService > ParkourKeybindServer
local RS=game:GetService("ReplicatedStorage")
local DSS=game:GetService("DataStoreService")
local store=DSS:GetDataStore("ParkourKeybindSettings_V1")
local remote=RS:FindFirstChild("ParkourKeybindSaveEvent") or Instance.new("RemoteEvent")
remote.Name="ParkourKeybindSaveEvent";remote.Parent=RS

-- Builder asks this RemoteFunction for authoritative saved bindings on startup.
local getFunction=RS:FindFirstChild("ParkourKeybindGetFunction") or Instance.new("RemoteFunction")
getFunction.Name="ParkourKeybindGetFunction"
getFunction.Parent=RS

local lastSave={}
local SAVE_COOLDOWN=3

local allowed={Place=true,Move=true,Rotate=true,Scale=true,Delete=true,CancelTransform=true,ConfirmTransform=true,HideBuildUI=true,Platform=true,KillBlock=true,BouncePad=true,SpeedPad=true,Checkpoint=true,Start=true,Finish=true,Test=true}

local function sanitize(data)
	if type(data)~="table" then return nil end
	-- Migrate the old Scale + binding to the new single Scale mode.
	if data.Scale==nil and type(data.ScaleUp)=="string" then
		data.Scale=data.ScaleUp
	end
	local clean={}
	for action,key in pairs(data) do
		if allowed[action] and type(key)=="string" and #key<=30 and Enum.KeyCode[key] then clean[action]=key end
	end
	return clean
end

getFunction.OnServerInvoke=function(player)
	local ok,result=pcall(function()
		return store:GetAsync("keys_"..player.UserId)
	end)
	if ok and type(result)=="table" then
		return sanitize(result) or {}
	end
	return {}
end

remote.OnServerEvent:Connect(function(player,action,data)
	if action=="Load" then
		local ok,result=pcall(function() return store:GetAsync("keys_"..player.UserId) end)
		if ok then remote:FireClient(player,"Loaded",type(result)=="table" and (sanitize(result) or {}) or {}) end
	elseif action=="Save" then
		local now=os.clock()
		if now-(lastSave[player] or -SAVE_COOLDOWN)<SAVE_COOLDOWN then
			return
		end
		lastSave[player]=now
		local clean=sanitize(data)
		if not clean then remote:FireClient(player,"SaveError");return end
		local ok,err=pcall(function() store:SetAsync("keys_"..player.UserId,clean) end)
		if ok then remote:FireClient(player,"Saved") else warn(err);remote:FireClient(player,"SaveError") end
	end
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	lastSave[player]=nil
end)

print("? Parkour Key Binding Save Server V1.1 anti-spam loaded")

-- ParkourSharedPreviewServer V1
-- Put in ServerScriptService.
-- Relays the Creator OWNER'S temporary placement preview to GUESTS only.
-- No preview data is saved to DataStore and no real parkour object is created here.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")

local remote=RS:FindFirstChild("ParkourSharedPreviewEvent")
if not remote then
	remote=Instance.new("RemoteEvent")
	remote.Name="ParkourSharedPreviewEvent"
	remote.Parent=RS
end

local VALID_TYPES={
	Platform=true,KillBlock=true,BouncePad=true,SpeedPad=true,
	Checkpoint=true,Start=true,Finish=true,
}

local lastSend={}

local function sendToGuests(owner,action,data)
	for _,other in ipairs(Players:GetPlayers()) do
		if other~=owner and other:GetAttribute("ParkourCreatorGuest")==true then
			remote:FireClient(other,action,owner.UserId,data)
		end
	end
end

remote.OnServerEvent:Connect(function(player,action,data)
	-- Security: guests/public players can never broadcast fake build previews.
	if player:GetAttribute("ParkourCreatorOwner")~=true
		or player:GetAttribute("ParkourPrivateCreator")~=true then
		return
	end

	if action=="Hide" then
		sendToGuests(player,"Hide")
		return
	end

	if action~="Update" or type(data)~="table" then return end

	-- Server-side rate limit.
	local now=os.clock()
	if now-(lastSend[player] or 0)<1/15 then return end
	lastSend[player]=now

	local kind=tostring(data.Kind or "Place")
	if kind~="Place" and kind~="Move" and kind~="Rotate" and kind~="Scale" then return end
	if not VALID_TYPES[tostring(data.Type)] then return end
	if typeof(data.CFrame)~="CFrame" or typeof(data.Size)~="Vector3" then return end
	if typeof(data.Color)~="Color3" then return end

	-- Reject absurd client sizes.
	local size=data.Size
	if size.X<.1 or size.Y<.1 or size.Z<.1
		or size.X>40 or size.Y>20 or size.Z>40 then
		return
	end

	sendToGuests(player,"Update",{
		Kind=kind,
		Type=tostring(data.Type),
		CFrame=data.CFrame,
		Size=size,
		Color=data.Color,
	})
end)

Players.PlayerRemoving:Connect(function(player)
	lastSend[player]=nil
	if player:GetAttribute("ParkourCreatorOwner")==true then
		sendToGuests(player,"Hide")
	end
end)

print("? ParkourSharedPreviewServer V1 loaded")

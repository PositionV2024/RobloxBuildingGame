-- ParkourAutoSaveClient V2 - OWNER-ONLY AUTOSAVE
-- StarterPlayer > StarterPlayerScripts
--
-- Reserved Creator server:
--   Owner        -> autosaves the complete shared live plot.
--   Collaborator -> NEVER sends SaveDraft.
--   Viewer       -> NEVER sends SaveDraft.
--
-- Normal/non-reserved Creator mode keeps the existing autosave behavior.
--
-- Server remains authoritative: ParkourBuilderServer V7.1 also rejects
-- guest SaveDraft requests.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local TweenService=game:GetService("TweenService")
local RunService=game:GetService("RunService")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local remote=ReplicatedStorage:WaitForChild("ParkourBuilderEvent")

local MIN_INTERVAL=30
local MAX_INTERVAL=300
local DEFAULT_INTERVAL=60

local function getInterval()
	local n=tonumber(playerGui:GetAttribute("ParkourAutoSaveInterval")) or DEFAULT_INTERVAL
	return math.clamp(math.floor(n+.5),MIN_INTERVAL,MAX_INTERVAL)
end

local function isReservedCreatorServer()
	return workspace:GetAttribute("ParkourPrivateCreatorServer")==true
		or tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))~=nil
end

local function isReservedOwner()
	local ownerId=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))

	if ownerId and ownerId==player.UserId then
		return true
	end

	return player:GetAttribute("ParkourCreatorOwner")==true
		or player:GetAttribute("ParkourCreatorRole")=="Owner"
end

local function canAutoSave()
	-- Critical rule: an explicit guest NEVER owns the autosave.
	if player:GetAttribute("ParkourCreatorGuest")==true then
		return false
	end

	-- In a reserved Creator session, only its owner may autosave.
	if isReservedCreatorServer() then
		return isReservedOwner()
	end

	-- Preserve ordinary/non-reserved Builder autosave.
	return true
end

local requestPending=false
local token=0
local spinConnection=nil

local screen=Instance.new("ScreenGui")
screen.Name="ParkourAutoSaveUI"
screen.ResetOnSpawn=false
screen.IgnoreGuiInset=true
screen.DisplayOrder=1000
screen.Parent=playerGui

local toast=Instance.new("Frame")
toast.Name="Toast"
toast.Size=UDim2.fromOffset(250,58)
toast.AnchorPoint=Vector2.new(1,0)
toast.Position=UDim2.new(1,270,0,205)
toast.BackgroundColor3=Color3.fromRGB(9,27,43)
toast.BorderSizePixel=0
toast.Parent=screen

local corner=Instance.new("UICorner")
corner.CornerRadius=UDim.new(0,11)
corner.Parent=toast

local stroke=Instance.new("UIStroke")
stroke.Color=Color3.fromRGB(65,210,255)
stroke.Thickness=2
stroke.Parent=toast

local icon=Instance.new("TextLabel")
icon.Size=UDim2.fromOffset(44,44)
icon.Position=UDim2.fromOffset(7,7)
icon.BackgroundTransparency=1
icon.Text="↻"
icon.Font=Enum.Font.GothamBlack
icon.TextSize=26
icon.TextColor3=Color3.fromRGB(80,220,255)
icon.Parent=toast

local label=Instance.new("TextLabel")
label.Size=UDim2.new(1,-60,1,0)
label.Position=UDim2.fromOffset(56,0)
label.BackgroundTransparency=1
label.Text="AUTO SAVING..."
label.TextXAlignment=Enum.TextXAlignment.Left
label.Font=Enum.Font.GothamBlack
label.TextSize=14
label.TextColor3=Color3.new(1,1,1)
label.Parent=toast

local function slideIn()
	TweenService:Create(
		toast,
		TweenInfo.new(.3,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),
		{Position=UDim2.new(1,-18,0,205)}
	):Play()
end

local function slideOut(myToken)
	task.delay(1.5,function()
		if token~=myToken then return end
		TweenService:Create(
			toast,
			TweenInfo.new(.25,Enum.EasingStyle.Quart,Enum.EasingDirection.In),
			{Position=UDim2.new(1,270,0,205)}
		):Play()
	end)
end

local function saving()
	token+=1
	icon.Text="↻"
	icon.Rotation=0
	icon.TextColor3=Color3.fromRGB(80,220,255)
	label.Text="AUTO SAVING..."
	stroke.Color=Color3.fromRGB(65,210,255)

	if spinConnection then spinConnection:Disconnect() end
	local started=os.clock()
	spinConnection=RunService.RenderStepped:Connect(function()
		icon.Rotation=((os.clock()-started)*180)%360
	end)
	slideIn()
end

local function saved(count)
	token+=1
	local myToken=token
	if spinConnection then spinConnection:Disconnect();spinConnection=nil end
	icon.Rotation=0
	icon.Text="✓"
	icon.TextColor3=Color3.fromRGB(90,235,160)
	label.Text="AUTO SAVED • "..tostring(count or 0).." OBJECTS"
	stroke.Color=Color3.fromRGB(70,220,150)
	slideIn()
	slideOut(myToken)
end

local function cancelled()
	requestPending=false
	if spinConnection then spinConnection:Disconnect();spinConnection=nil end
end

remote.OnClientEvent:Connect(function(action,a)
	if not requestPending then return end

	if action=="Saving" then
		saving()
	elseif action=="DraftSaved" then
		requestPending=false
		saved(a)
	elseif action=="SaveCooldown" then
		cancelled()
	elseif action=="Notice" then
		cancelled()
	end
end)

local function builderIsOpen()
	local builder=playerGui:FindFirstChild("ParkourBuilderUI")
	if not builder then
		for _,child in ipairs(playerGui:GetChildren()) do
			if child:IsA("ScreenGui")
				and child.Name:lower():find("builder")
				and child.Enabled then
				return true
			end
		end
		return false
	end
	return builder.Enabled
end

task.spawn(function()
	while true do
		task.wait(getInterval())

		-- OWNER-ONLY reserved-session autosave.
		if canAutoSave() and builderIsOpen() and not requestPending then
			requestPending=true
			remote:FireServer("SaveDraft")

			task.delay(10,function()
				if requestPending then
					cancelled()
				end
			end)
		end
	end
end)

print("✓ ParkourAutoSaveClient V2 owner-only autosave loaded")

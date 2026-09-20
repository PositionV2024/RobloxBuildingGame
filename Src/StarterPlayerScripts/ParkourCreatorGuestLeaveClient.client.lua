-- ParkourCreatorGuestLeaveClient V1
-- StarterPlayer > StarterPlayerScripts
-- Shows LEAVE SERVER only to guests inside another player's Creator server.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local TweenService=game:GetService("TweenService")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local returnRemote=RS:WaitForChild("ParkourReturnToPublicServer")

local gui=Instance.new("ScreenGui")
gui.Name="ParkourCreatorGuestUI"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.DisplayOrder=900
gui.Parent=playerGui

local leave=Instance.new("TextButton")
leave.Name="LeaveServer"
leave.Size=UDim2.fromOffset(170,44)
leave.Position=UDim2.new(1,-190,0,20)
leave.BackgroundColor3=Color3.fromRGB(150,55,65)
leave.BorderSizePixel=0
leave.Text="LEAVE SERVER"
leave.Font=Enum.Font.GothamBlack
leave.TextSize=13
leave.TextColor3=Color3.new(1,1,1)
leave.Visible=false
leave.Parent=gui

local corner=Instance.new("UICorner")
corner.CornerRadius=UDim.new(0,10)
corner.Parent=leave

local stroke=Instance.new("UIStroke")
stroke.Color=Color3.fromRGB(235,105,115)
stroke.Transparency=.25
stroke.Thickness=1.5
stroke.Parent=leave

local transitionGui=Instance.new("ScreenGui")
transitionGui.Name="ParkourGuestReturnTransitionUI"
transitionGui.ResetOnSpawn=false
transitionGui.IgnoreGuiInset=true
transitionGui.DisplayOrder=1500
transitionGui.Enabled=false
transitionGui.Parent=playerGui

local overlay=Instance.new("Frame")
overlay.Size=UDim2.fromScale(1,1)
overlay.BackgroundColor3=Color3.fromRGB(5,14,25)
overlay.BackgroundTransparency=1
overlay.BorderSizePixel=0
overlay.Active=true
overlay.Parent=transitionGui

local icon=Instance.new("TextLabel")
icon.Size=UDim2.fromOffset(150,100); icon.Position=UDim2.new(.5,-75,.5,-190)
icon.BackgroundTransparency=1; icon.Text="◉  ➜"; icon.Font=Enum.Font.GothamBlack
icon.TextSize=52; icon.TextColor3=Color3.fromRGB(75,205,255); icon.TextTransparency=1; icon.Parent=overlay

local title=Instance.new("TextLabel")
title.Size=UDim2.new(1,-60,0,62); title.Position=UDim2.new(0,30,.5,-82)
title.BackgroundTransparency=1; title.Text="LEAVING CREATOR SERVER..."; title.Font=Enum.Font.GothamBlack
title.TextSize=30; title.TextColor3=Color3.new(1,1,1); title.TextTransparency=1; title.Parent=overlay

local sub=Instance.new("TextLabel")
sub.Size=UDim2.new(1,-60,0,34); sub.Position=UDim2.new(0,30,.5,-18); sub.BackgroundTransparency=1
sub.Text="Returning you to Discover"; sub.Font=Enum.Font.GothamMedium; sub.TextSize=17
sub.TextColor3=Color3.fromRGB(165,215,245); sub.TextTransparency=1; sub.Parent=overlay

local progressBack=Instance.new("Frame")
progressBack.Size=UDim2.fromOffset(470,16); progressBack.Position=UDim2.new(.5,-235,.5,43)
progressBack.BackgroundColor3=Color3.fromRGB(52,75,98); progressBack.BackgroundTransparency=.15
progressBack.BorderSizePixel=0; progressBack.Parent=overlay
local pbc=Instance.new("UICorner"); pbc.CornerRadius=UDim.new(1,0); pbc.Parent=progressBack

local progress=Instance.new("Frame")
progress.Size=UDim2.fromScale(0,1); progress.BackgroundColor3=Color3.fromRGB(65,205,255)
progress.BorderSizePixel=0; progress.Parent=progressBack
local pc=Instance.new("UICorner"); pc.CornerRadius=UDim.new(1,0); pc.Parent=progress

local dots=Instance.new("TextLabel")
dots.Size=UDim2.new(1,-60,0,30); dots.Position=UDim2.new(0,30,.5,78); dots.BackgroundTransparency=1
dots.Text="●   ●   ●"; dots.Font=Enum.Font.GothamBlack; dots.TextSize=17
dots.TextColor3=Color3.fromRGB(70,125,165); dots.TextTransparency=1; dots.Parent=overlay

local status=Instance.new("TextLabel")
status.Size=UDim2.new(1,-60,0,30); status.Position=UDim2.new(0,30,.5,112); status.BackgroundTransparency=1
status.Text="Leaving private Creator session..."; status.Font=Enum.Font.GothamMedium; status.TextSize=14
status.TextColor3=Color3.fromRGB(155,195,220); status.TextTransparency=1; status.Parent=overlay

local tip=Instance.new("TextLabel")
tip.Size=UDim2.fromOffset(340,72); tip.Position=UDim2.new(0,28,1,-100)
tip.BackgroundColor3=Color3.fromRGB(12,26,41); tip.BackgroundTransparency=.08; tip.BorderSizePixel=0
tip.Text="◈  DISCOVER\nBrowse and play community parkours"; tip.TextXAlignment=Enum.TextXAlignment.Left
tip.Font=Enum.Font.GothamBold; tip.TextSize=14; tip.TextColor3=Color3.fromRGB(205,225,240)
tip.TextTransparency=1; tip.Parent=overlay
local tc=Instance.new("UICorner"); tc.CornerRadius=UDim.new(0,11); tc.Parent=tip
local ts=Instance.new("UIStroke"); ts.Color=Color3.fromRGB(55,145,205); ts.Transparency=.35; ts.Parent=tip

local busy=false

local function showLeaveTransition()
	transitionGui.Enabled=true
	overlay.BackgroundTransparency=1; icon.TextTransparency=1; title.TextTransparency=1
	sub.TextTransparency=1; dots.TextTransparency=1; status.TextTransparency=1; tip.TextTransparency=1
	progress.Size=UDim2.fromScale(0,1)

	TweenService:Create(overlay,TweenInfo.new(.22),{BackgroundTransparency=.06}):Play()
	TweenService:Create(icon,TweenInfo.new(.22),{TextTransparency=0}):Play()
	TweenService:Create(title,TweenInfo.new(.22),{TextTransparency=0}):Play()
	TweenService:Create(sub,TweenInfo.new(.28),{TextTransparency=0}):Play()
	TweenService:Create(dots,TweenInfo.new(.28),{TextTransparency=0}):Play()
	TweenService:Create(status,TweenInfo.new(.28),{TextTransparency=0}):Play()
	TweenService:Create(tip,TweenInfo.new(.28),{TextTransparency=0}):Play()

	local tween=TweenService:Create(progress,TweenInfo.new(1.15,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=UDim2.fromScale(1,1)})
	tween:Play()
	task.wait(.55); dots.Text="●   ○   ○"; status.Text="Closing your guest session..."
	tween.Completed:Wait(); dots.Text="●   ●   ○"; status.Text="Opening Discover server..."
	returnRemote:FireServer("GuestReturn")
end

local function refresh()
	leave.Visible=player:GetAttribute("ParkourCreatorGuest")==true
end

player:GetAttributeChangedSignal("ParkourCreatorGuest"):Connect(refresh)
refresh()

leave.Activated:Connect(function()
	if busy or player:GetAttribute("ParkourCreatorGuest")~=true then return end
	busy=true
	leave.Active=false
	leave.Text="LEAVING..."
	task.spawn(showLeaveTransition)
end)

returnRemote.OnClientEvent:Connect(function(action,message)
	if action=="Failed" and busy then
		busy=false
		leave.Active=true
		leave.Text="LEAVE SERVER"
		transitionGui.Enabled=false
		warn("[GUEST RETURN] "..tostring(message or "Teleport failed"))
	elseif action=="StudioReturned" and busy then
		status.Text="Discover server ready!"
		dots.Text="●   ●   ●"
		task.wait(.25)
		transitionGui.Enabled=false
		busy=false
		leave.Active=true
		leave.Text="LEAVE SERVER"
		refresh()
	end
end)

print("✓ ParkourCreatorGuestLeaveClient V1 loaded")

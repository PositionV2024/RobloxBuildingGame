-- ParkourCreatorKickGuestClient V1 - RETURN TRANSITION
-- StarterPlayer > StarterPlayerScripts
-- Shows a Creator-style full-screen transition before a kicked guest returns to public Discover.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local TweenService=game:GetService("TweenService")

local player=Players.LocalPlayer
local pg=player:WaitForChild("PlayerGui")
local remote=RS:WaitForChild("ParkourCreatorKickGuestEvent")

local gui=Instance.new("ScreenGui")
gui.Name="ParkourKickReturnTransition"
gui.IgnoreGuiInset=true
gui.ResetOnSpawn=false
gui.DisplayOrder=5000
gui.Enabled=false
gui.Parent=pg

local bg=Instance.new("Frame")
bg.Size=UDim2.fromScale(1,1)
bg.BackgroundColor3=Color3.fromRGB(5,14,25)
bg.BackgroundTransparency=1
bg.BorderSizePixel=0
bg.Parent=gui

local icon=Instance.new("TextLabel")
icon.Size=UDim2.fromOffset(150,100)
icon.Position=UDim2.new(.5,-75,.5,-190)
icon.BackgroundTransparency=1
icon.Text="◉  ➜"
icon.Font=Enum.Font.GothamBlack
icon.TextSize=52
icon.TextColor3=Color3.fromRGB(75,205,255)
icon.TextTransparency=1
icon.Parent=bg

local title=Instance.new("TextLabel")
title.Size=UDim2.new(1,-60,0,62)
title.Position=UDim2.new(0,30,.5,-82)
title.BackgroundTransparency=1
title.Text="RETURNING TO LOBBY"
title.Font=Enum.Font.GothamBlack
title.TextSize=30
title.TextColor3=Color3.new(1,1,1)
title.TextTransparency=1
title.Parent=bg

local sub=Instance.new("TextLabel")
sub.Size=UDim2.new(1,-60,0,34)
sub.Position=UDim2.new(0,30,.5,-18)
sub.BackgroundTransparency=1
sub.Text="Teleporting to original server..."
sub.Font=Enum.Font.GothamMedium
sub.TextSize=17
sub.TextColor3=Color3.fromRGB(165,215,245)
sub.TextTransparency=1
sub.Parent=bg

local track=Instance.new("Frame")
track.Size=UDim2.fromOffset(470,14)
track.Position=UDim2.new(.5,-235,.5,43)
track.BackgroundColor3=Color3.fromRGB(52,75,98)
track.BorderSizePixel=0
track.Parent=bg
local tc=Instance.new("UICorner");tc.CornerRadius=UDim.new(1,0);tc.Parent=track

local bar=Instance.new("Frame")
bar.Size=UDim2.fromScale(0,1)
bar.BackgroundColor3=Color3.fromRGB(65,205,255)
bar.BorderSizePixel=0
bar.Parent=track
local bc=Instance.new("UICorner");bc.CornerRadius=UDim.new(1,0);bc.Parent=bar

local status=Instance.new("TextLabel")
status.Size=UDim2.new(1,-60,0,30)
status.Position=UDim2.new(0,30,.5,78)
status.BackgroundTransparency=1
status.Text="Leaving Creator server..."
status.Font=Enum.Font.GothamMedium
status.TextSize=14
status.TextColor3=Color3.fromRGB(155,195,220)
status.TextTransparency=1
status.Parent=bg

local running=false

local function showTransition()
	if running then return end
	running=true
	gui.Enabled=true
	bg.BackgroundTransparency=1
	icon.TextTransparency=1
	title.TextTransparency=1
	sub.TextTransparency=1
	status.TextTransparency=1
	bar.Size=UDim2.fromScale(0,1)

	TweenService:Create(bg,TweenInfo.new(.22),{BackgroundTransparency=.04}):Play()
	TweenService:Create(icon,TweenInfo.new(.22),{TextTransparency=0}):Play()
	TweenService:Create(title,TweenInfo.new(.22),{TextTransparency=0}):Play()
	TweenService:Create(sub,TweenInfo.new(.25),{TextTransparency=0}):Play()
	TweenService:Create(status,TweenInfo.new(.25),{TextTransparency=0}):Play()

	local progress=TweenService:Create(
		bar,
		TweenInfo.new(.9,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
		{Size=UDim2.fromScale(1,1)}
	)
	progress:Play()
	task.wait(.45)
	status.Text="Opening public Discover server..."
	progress.Completed:Wait()

	remote:FireServer("ReturnTransitionReady")
end

remote.OnClientEvent:Connect(function(action)
	if action=="PrepareReturnToLobby" then
		showTransition()
	elseif action=="StudioReturned" then
		status.Text="Returned to Discover"
		task.wait(.35)
		gui.Enabled=false
		running=false

		-- Restore Discover UI in Studio simulation.
		local discover=pg:FindFirstChild("ParkourDiscoverUI")
		if discover then discover.Enabled=true end
		local builder=pg:FindFirstChild("ParkourBuilderUI")
		if builder then builder.Enabled=false end
	elseif action=="ReturnFailed" then
		status.Text="Could not return to lobby."
		task.wait(1)
		gui.Enabled=false
		running=false
	end
end)

print("✓ ParkourCreatorKickGuestClient V1 return transition loaded")

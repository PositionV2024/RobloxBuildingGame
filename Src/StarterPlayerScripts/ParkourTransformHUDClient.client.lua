-- ParkourTransformHUDClient V4
-- StarterPlayer > StarterPlayerScripts
-- Visual-only companion for ParkourBuilderClient.
-- Adds Cancel + Confirm cards to the existing TransformDock.
-- Does NOT modify building, save, or transformation logic.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")

local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")

local NORMAL_SIZE=UDim2.fromOffset(112,96)
local ACTIVE_SIZE=UDim2.fromOffset(128,108)

local NORMAL_BG=Color3.fromRGB(12,38,59)
local DELETE_BG=Color3.fromRGB(67,24,35)
local CANCEL_BG=Color3.fromRGB(67,24,35)
local CONFIRM_BG=Color3.fromRGB(8,62,39)
local ACTIVE_BG=Color3.fromRGB(8,70,42)
local ACTIVE_GREEN=Color3.fromRGB(45,255,105)

local currentActive=nil
local configuredDock=nil

local function pretty(action,fallback)
	local key=playerGui:GetAttribute("ParkourBind_"..action) or fallback
	local names={
		Return="ENTER",
		KeypadEnter="NUM ENTER",
		Escape="ESC",
		Delete="DEL",
		Space="SPACE",
		LeftShift="LSHIFT",
		RightShift="RSHIFT",
		One="1",Two="2",Three="3",Four="4",Five="5",Six="6",Seven="7",
	}
	return names[key] or string.upper(tostring(key or "?"))
end

local function getBuilder()
	local g=playerGui:FindFirstChild("ParkourBuilderUI")
	return g and g:IsA("ScreenGui") and g or nil
end

local function getDock(builder)
	return builder and builder:FindFirstChild("TransformDock",true) or nil
end

local function makeExtraCard(dock,name,title,danger)
	local old=dock:FindFirstChild(name.."Dock")
	if old then return old end

	local b=Instance.new("TextButton")
	b.Name=name.."Dock"
	b.Size=NORMAL_SIZE
	b.BackgroundColor3=danger and CANCEL_BG or CONFIRM_BG
	b.BackgroundTransparency=.02
	b.BorderSizePixel=0
	b.Text=""
	b.AutoButtonColor=false
	b.ZIndex=172
	b.Parent=dock

	local c=Instance.new("UICorner")
	c.CornerRadius=UDim.new(0,12)
	c.Parent=b

	local border=Instance.new("UIStroke")
	border.Color=danger and Color3.fromRGB(255,65,80) or Color3.fromRGB(55,235,120)
	border.Thickness=1.5
	border.Transparency=.18
	border.Parent=b

	local icon=Instance.new("TextLabel")
	icon.Name="DockIcon"
	icon.Size=UDim2.new(1,0,0,48)
	icon.Position=UDim2.fromOffset(0,5)
	icon.BackgroundTransparency=1
	icon.Text=danger and "⊘" or "✓"
	icon.Font=Enum.Font.GothamBlack
	icon.TextSize=35
	icon.TextColor3=danger and Color3.fromRGB(255,70,85) or Color3.fromRGB(55,255,115)
	icon.TextStrokeTransparency=.35
	icon.ZIndex=174
	icon.Parent=b

	local label=Instance.new("TextLabel")
	label.Name="DockLabel"
	label.Size=UDim2.new(1,-6,0,42)
	label.Position=UDim2.new(0,3,1,-44)
	label.BackgroundTransparency=1
	label.Text=title
	label.TextWrapped=true
	label.Font=Enum.Font.GothamBlack
	label.TextSize=10
	label.TextColor3=Color3.new(1,1,1)
	label.TextStrokeTransparency=.78
	label.ZIndex=173
	label.Parent=b

	return b
end

local function configureDock(dock)
	if configuredDock==dock then return end
	configuredDock=dock

	-- Six cards need more horizontal room.
	dock.Size=UDim2.fromOffset(750,120)

	local layout=dock:FindFirstChildOfClass("UIListLayout")
	if layout then layout.Padding=UDim.new(0,7) end

	for _,name in ipairs({"DELETE","MOVE","ROTATE","SCALE"}) do
		local b=dock:FindFirstChild(name.."Dock")
		if b then b.Size=NORMAL_SIZE end
	end

	makeExtraCard(dock,"CANCEL","CANCEL TRANSFORM\n["..pretty("CancelTransform","Escape").."]",true)
	makeExtraCard(dock,"CONFIRM","CONFIRM TRANSFORM\n["..pretty("ConfirmTransform","Return").."]",false)
end

local function refreshExtraKeys()
	local builder=getBuilder()
	local dock=getDock(builder)
	if not dock then return end

	local cancel=dock:FindFirstChild("CANCELDock")
	local confirm=dock:FindFirstChild("CONFIRMDock")
	if cancel and cancel:FindFirstChild("DockLabel") then
		cancel.DockLabel.Text="CANCEL TRANSFORM\n["..pretty("CancelTransform","Escape").."]"
	end
	if confirm and confirm:FindFirstChild("DockLabel") then
		confirm.DockLabel.Text="CONFIRM TRANSFORM\n["..pretty("ConfirmTransform","Return").."]"
	end
end

for _,action in ipairs({"CancelTransform","ConfirmTransform"}) do
	playerGui:GetAttributeChangedSignal("ParkourBind_"..action):Connect(refreshExtraKeys)
end

local function detectMode()
	local builder=getBuilder()
	if not builder or not builder.Enabled then return nil end
	if workspace:FindFirstChild("MoveDestinationPreview") then return "MOVE" end
	if workspace:FindFirstChild("RotatePreview") then return "ROTATE" end
	if workspace:FindFirstChild("ScalePreview") then return "SCALE" end
	return nil
end

local function activeStroke(button)
	local st=button and button:FindFirstChild("TransformActiveBorder")
	if button and not st then
		st=Instance.new("UIStroke")
		st.Name="TransformActiveBorder"
		st.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
		st.Color=ACTIVE_GREEN
		st.Thickness=4
		st.Transparency=1
		st.Parent=button
	end
	return st
end

local function childZ(button,active)
	local icon=button and button:FindFirstChild("DockIcon")
	local label=button and button:FindFirstChild("DockLabel")
	if icon then
		icon.ZIndex=active and 181 or 173
		for _,d in ipairs(icon:GetDescendants()) do
			if d:IsA("GuiObject") then d.ZIndex=active and 182 or 174 end
		end
	end
	if label then
		label.ZIndex=active and 181 or 173
		label.TextTransparency=0
		label.TextColor3=Color3.new(1,1,1)
	end
end

local function normalBackground(button)
	if button.Name=="DELETEDock" then return DELETE_BG end
	if button.Name=="CANCELDock" then return CANCEL_BG end
	if button.Name=="CONFIRMDock" then return CONFIRM_BG end
	return NORMAL_BG
end

local function setNormal(button)
	if not button then return end
	local st=activeStroke(button)
	if st then st.Transparency=1 end
	button.ZIndex=172
	childZ(button,false)
	TweenService:Create(
		button,
		TweenInfo.new(.14,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
		{Size=NORMAL_SIZE,BackgroundColor3=normalBackground(button)}
	):Play()
end

local function setActive(button)
	if not button then return end
	local st=activeStroke(button)
	st.Transparency=0
	st.Thickness=4
	st.Color=ACTIVE_GREEN
	button.ZIndex=178
	childZ(button,true)
	TweenService:Create(
		button,
		TweenInfo.new(.17,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{Size=ACTIVE_SIZE,BackgroundColor3=ACTIVE_BG}
	):Play()
end

local function updateCards(dock,mode)
	local desired=nil
	if mode then desired=dock:FindFirstChild(mode.."Dock") end
	if desired==currentActive then return end

	for _,name in ipairs({"DELETE","MOVE","ROTATE","SCALE","CANCEL","CONFIRM"}) do
		setNormal(dock:FindFirstChild(name.."Dock"))
	end

	currentActive=desired
	if currentActive then setActive(currentActive) end
end

RunService.RenderStepped:Connect(function()
	local builder=getBuilder()
	local dock=getDock(builder)

	if not builder or not builder.Enabled or not dock or not dock.Visible then
		currentActive=nil
		return
	end

	configureDock(dock)
	refreshExtraKeys()
	updateCards(dock,detectMode())
end)

print("✓ ParkourTransformHUDClient V4 loaded")

-- ParkourBuildUIVisibilityClient V1
-- Put this as a SEPARATE LocalScript in:
-- StarterPlayer > StarterPlayerScripts
--
-- Press H to hide/show the Build Mode UI.
-- Does NOT modify ParkourBuilderClient, building logic, or saves.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Uses the player's configurable Settings binding.
local function getToggleKey()
	local keyName=playerGui:GetAttribute("ParkourBind_HideBuildUI") or "H"
	return Enum.KeyCode[keyName] or Enum.KeyCode.H
end

local hidden = false
local savedStates = {}

-- ScreenGuis that should remain visible while Build UI is hidden.
local KEEP_VISIBLE = {
	ParkourBuildUIVisibilityUI = true,
}

local helperGui = Instance.new("ScreenGui")
helperGui.Name = "ParkourBuildUIVisibilityUI"
helperGui.ResetOnSpawn = false
helperGui.IgnoreGuiInset = true
helperGui.DisplayOrder = 5000
helperGui.Parent = playerGui

local showButton = Instance.new("TextButton")
showButton.Name = "ShowUI"
showButton.Size = UDim2.fromOffset(126,38)
showButton.AnchorPoint = Vector2.new(1,1)
showButton.Position = UDim2.new(1,-16,1,-16)
showButton.BackgroundColor3 = Color3.fromRGB(12,30,46)
showButton.BackgroundTransparency = .08
showButton.BorderSizePixel = 0
showButton.Text = "HIDE UI ["..string.upper(getToggleKey().Name).."]"
showButton.Font = Enum.Font.GothamBlack
showButton.TextSize = 12
showButton.TextColor3 = Color3.fromRGB(225,245,255)
showButton.Visible = true
showButton.ZIndex = 10
showButton.Parent = helperGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0,9)
corner.Parent = showButton

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(40,165,235)
stroke.Thickness = 1.5
stroke.Transparency = .2
stroke.Parent = showButton

local function isBuilderRelated(gui)
	if not gui:IsA("ScreenGui") then
		return false
	end

	if KEEP_VISIBLE[gui.Name] then
		return false
	end

	local name = string.lower(gui.Name)

	-- Explicitly include the known Builder/HUD helper UIs.
	if name:find("parkourbuilder") then return true end
	if name:find("parkourtransform") then return true end
	if name:find("parkourautosave") then return true end

	-- Other build-specific Parkour ScreenGuis can opt in with this attribute.
	if gui:GetAttribute("ParkourBuildUI") == true then
		return true
	end

	return false
end

local function hideBuildUI()
	if hidden then return end
	hidden = true
	table.clear(savedStates)

	for _,child in ipairs(playerGui:GetChildren()) do
		if isBuilderRelated(child) then
			savedStates[child] = child.Enabled
			child.Enabled = false
		end
	end

	showButton.Visible = true
	showButton.Text = "SHOW UI ["..string.upper(getToggleKey().Name).."]"
end

local function showBuildUI()
	if not hidden then return end
	hidden = false

	-- Restore each GUI to the state it had before hiding.
	for gui,wasEnabled in pairs(savedStates) do
		if gui and gui.Parent == playerGui then
			gui.Enabled = wasEnabled
		end
	end

	table.clear(savedStates)
	showButton.Visible = true
	showButton.Text = "HIDE UI ["..string.upper(getToggleKey().Name).."]"
end

local function toggle()
	if hidden then
		showBuildUI()
	else
		hideBuildUI()
	end
end

showButton.MouseButton1Click:Connect(toggle)

playerGui:GetAttributeChangedSignal("ParkourBind_HideBuildUI"):Connect(function()
	local actionText=hidden and "SHOW UI [" or "HIDE UI ["
	showButton.Text=actionText..string.upper(getToggleKey().Name).."]"
end)

UIS.InputBegan:Connect(function(input,processed)
	if processed then return end
	if UIS:GetFocusedTextBox() then return end

	if input.KeyCode == getToggleKey() then
		toggle()
	end
end)

-- If another build-related GUI is created while UI is hidden,
-- hide it automatically too.
playerGui.ChildAdded:Connect(function(child)
	if not hidden then return end

	task.defer(function()
		if hidden and child.Parent == playerGui and isBuilderRelated(child) then
			savedStates[child] = child.Enabled
			child.Enabled = false
		end
	end)
end)



local function updateHelperVisibility()
	local builder=playerGui:FindFirstChild("ParkourBuilderUI")
	showButton.Visible = hidden or (builder and builder:IsA("ScreenGui") and builder.Enabled) or false
end

task.spawn(function()
	while true do
		updateHelperVisibility()
		task.wait(.25)
	end
end)

print("✓ ParkourBuildUIVisibilityClient V1.2 loaded")

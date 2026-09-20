-- MAKE YOUR OWN PARKOUR - BUILDER CLIENT V2 GROUPED UI
-- StarterPlayer > StarterPlayerScripts > ParkourBuilderClient
-- Compatible with ParkourBuilderServer V6.3.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local TweenService=game:GetService("TweenService")
local RunService=game:GetService("RunService")

local player=Players.LocalPlayer
local remote=RS:WaitForChild("ParkourBuilderEvent")
local sharedPreviewRemote=RS:WaitForChild("ParkourSharedPreviewEvent")
local returnPublicRemote=RS:WaitForChild("ParkourReturnToPublicServer")
local navigationEvent=RS:FindFirstChild("ParkourNavigationEvent") or Instance.new("BindableEvent")
navigationEvent.Name="ParkourNavigationEvent"
navigationEvent.Parent=RS
local playerGui=player:WaitForChild("PlayerGui")
local keybindEvent=RS:FindFirstChild("ParkourKeybindEvent") or Instance.new("BindableEvent")
keybindEvent.Name="ParkourKeybindEvent"
keybindEvent.Parent=RS
local keybindSaveRemote=RS:WaitForChild("ParkourKeybindSaveEvent")
local keybindGetFunction=RS:WaitForChild("ParkourKeybindGetFunction",10)

local DEFAULT_BINDS={
	Move="G",Rotate="E",Scale="R",Delete="Delete",CancelTransform="Escape",ConfirmTransform="Return",
	Platform="One",KillBlock="Two",BouncePad="Three",SpeedPad="Four",
	Checkpoint="Five",Start="Six",Finish="Seven",Test="F"
}
local keybinds={}
local refreshObjectButtonKeys -- forward declaration
for k,v in pairs(DEFAULT_BINDS) do
	-- Read the Settings client's current session binding first.
	-- Fall back to the default only when no saved/current binding exists.
	keybinds[k]=playerGui:GetAttribute("ParkourBind_"..k) or v
end

local function keyName(action)
	return keybinds[action] or DEFAULT_BINDS[action]
end

local applyingBindings=false

local function applyBindings(data)
	if type(data)~="table" then return end
	if applyingBindings then return end
	applyingBindings=true

	for action,key in pairs(data) do
		if DEFAULT_BINDS[action] and type(key)=="string" and Enum.KeyCode[key] then
			keybinds[action]=key

			-- SetAttribute only when the value actually changed.
			-- This prevents AttributeChanged -> BindingsChanged -> applyBindings recursion.
			local attr="ParkourBind_"..action
			if playerGui:GetAttribute(attr)~=key then
				playerGui:SetAttribute(attr,key)
			end
		end
	end

	applyingBindings=false

	-- One refresh is enough; don't recursively rebroadcast.
	if refreshObjectButtonKeys then
		refreshObjectButtonKeys()
	end
end

local function pullAuthoritativeBindings()
	if not keybindGetFunction then
		warn("[KEYBINDS] ParkourKeybindGetFunction missing; using session bindings")
		keybindSaveRemote:FireServer("Load")
		return
	end
	local ok,data=pcall(function()
		return keybindGetFunction:InvokeServer()
	end)
	if ok and type(data)=="table" then
		applyBindings(data)
		print("[KEYBINDS] authoritative bindings received")
		for action,key in pairs(data) do
			print("[KEYBINDS]",action,"=",key)
		end
	else
		warn("[KEYBINDS] could not retrieve authoritative bindings")
	end
end

local function syncBindingsFromSettings()
	for action,defaultKey in pairs(DEFAULT_BINDS) do
		local saved=playerGui:GetAttribute("ParkourBind_"..action)
		if type(saved)=="string" and Enum.KeyCode[saved] then
			keybinds[action]=saved
		elseif not keybinds[action] then
			keybinds[action]=defaultKey
		end
	end
end
syncBindingsFromSettings()
if keybinds.Move=="W" or keybinds.Move=="A" or keybinds.Move=="S" or keybinds.Move=="D" then
	keybinds.Move="G"
	playerGui:SetAttribute("ParkourBind_Move","G")
end

keybindEvent.Event:Connect(function(action,a,b)
	if action=="BindingsChanged" and type(a)=="table" then
		applyBindings(a)
	end
end)

for action,_ in pairs(DEFAULT_BINDS) do
	playerGui:GetAttributeChangedSignal("ParkourBind_"..action):Connect(function()
		if applyingBindings then return end

		local v=playerGui:GetAttribute("ParkourBind_"..action)
		if type(v)=="string" and Enum.KeyCode[v] then
			-- Update locally only. Do NOT fire BindingsChanged again:
			-- the attribute change itself is already the notification.
			keybinds[action]=v

			if refreshObjectButtonKeys then
				refreshObjectButtonKeys()
			end
		end
	end)
end


local old=playerGui:FindFirstChild("ParkourBuilderUI")
if old then old:Destroy() end

local gui=Instance.new("ScreenGui")
gui.Name="ParkourBuilderUI"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
-- SECURITY-SAFE DEFAULT:
-- Start hidden. It becomes visible only after this client positively
-- identifies the player as the reserved owner or an authorized Collaborator.
gui.Enabled=false
gui.Parent=playerGui

-- =========================================================
-- CREATOR / COLLABORATOR BUILDER UI AUTHORITY
-- ParkourBuilderClient creates ParkourBuilderUI, so it also owns its
-- permission-aware visibility. This removes the LocalScript load-order race.
-- =========================================================
local function isReservedOwner()
	local ownerId=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))
	return (ownerId~=nil and ownerId==player.UserId)
		or player:GetAttribute("ParkourCreatorOwner")==true
		or player:GetAttribute("ParkourCreatorRole")=="Owner"
end

local function isExplicitGuest()
	return player:GetAttribute("ParkourCreatorGuest")==true
end

local function guestCanBuild()
	return isExplicitGuest()
		and player:GetAttribute("ParkourGuestPermissionRole")=="Collaborator"
		and player:GetAttribute("ParkourCanCollaborate")==true
end

local function refreshPermissionVisibility()
	-- Transition always wins.
	if playerGui:GetAttribute("CreatorTransitionActive")==true then
		gui.Enabled=false
		return
	end

	-- OWNER: explicit positive authorization.
	if isReservedOwner() then
		gui.Enabled=true
		return
	end

	-- GUEST: only an explicitly granted Collaborator may see Builder.
	if isExplicitGuest() then
		gui.Enabled=guestCanBuild()
		return
	end

	-- Unknown/public/in-between state: keep Builder hidden.
	-- Never grant Build UI merely because role attributes have not arrived yet.
	gui.Enabled=false
end

player:GetAttributeChangedSignal("ParkourCreatorOwner"):Connect(refreshPermissionVisibility)
player:GetAttributeChangedSignal("ParkourCreatorRole"):Connect(refreshPermissionVisibility)
player:GetAttributeChangedSignal("ParkourCreatorGuest"):Connect(refreshPermissionVisibility)
player:GetAttributeChangedSignal("ParkourGuestPermissionRole"):Connect(refreshPermissionVisibility)
player:GetAttributeChangedSignal("ParkourCanCollaborate"):Connect(refreshPermissionVisibility)
workspace:GetAttributeChangedSignal("ParkourCreatorOwnerUserId"):Connect(refreshPermissionVisibility)

task.defer(function()
	task.wait(.15)
	refreshPermissionVisibility()
end)

-- Never allow Builder UI to show while Discover is performing its teleport transition.
playerGui:GetAttributeChangedSignal("CreatorTransitionActive"):Connect(function()
	if playerGui:GetAttribute("CreatorTransitionActive")==true then
		gui.Enabled=false
	else
		task.defer(refreshPermissionVisibility)
	end
end)


local selectedType="Platform"
local mode="Select"
local selectedObject=nil
local testing=false
local placementRotationY=0
local placementScale=Vector3.new(1,1,1)

local function corner(o,r)
	local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,r or 9);c.Parent=o
end
local function stroke(o,color)
	local s=Instance.new("UIStroke");s.Color=color or Color3.fromRGB(69,82,100);s.Transparency=.45;s.Thickness=1;s.Parent=o
end
local function btn(parent,text,w,h)
	local b=Instance.new("TextButton")
	b.Size=UDim2.fromOffset(w or 74,h or 48)
	b.BackgroundColor3=Color3.fromRGB(37,47,61)
	b.BorderSizePixel=0;b.Text=text;b.Font=Enum.Font.GothamBold;b.TextSize=11
	b.TextColor3=Color3.new(1,1,1);b.Parent=parent;corner(b,8)
	return b
end
-- BUTTON ICONS
-- These use Roblox-hosted Creator Store thumbnails / decal assets.
-- They are visual-only; no third-party models or scripts are inserted.
local BUTTON_ICONS={
	Platform="rbxthumb://type=Asset&id=12884184673&w=150&h=150",
	KillBlock="rbxthumb://type=Asset&id=18469325802&w=150&h=150",
	BouncePad="rbxthumb://type=Asset&id=14743725492&w=150&h=150",
	SpeedPad="rbxthumb://type=Asset&id=49610408&w=150&h=150",
	Checkpoint="rbxthumb://type=Asset&id=11426963868&w=150&h=150",
	Start="rbxthumb://type=Asset&id=132601982236823&w=150&h=150",
	Finish="rbxthumb://type=Asset&id=80525396862141&w=150&h=150",

	SELECT="rbxthumb://type=Asset&id=7990453298&w=150&h=150",
	UNDO="rbxassetid://5107220223",
	REDO="rbxassetid://5107220223",
	SAVE="rbxassetid://12665008484",
	LOAD="rbxassetid://12665008484",
	VALIDATE="rbxassetid://5107220223",
	PUBLISH="rbxthumb://type=Asset&id=56448011&w=150&h=150",
	CLEAR="rbxthumb://type=Asset&id=18469325802&w=150&h=150",
	TEST="rbxassetid://8215093343",
}

local function addButtonIcon(buttonObj,action)
	if not buttonObj then return end
	local image=BUTTON_ICONS[action]
	if not image then return end

	local oldIcon=buttonObj:FindFirstChild("ActionIcon")
	if oldIcon then oldIcon:Destroy() end

	local icon=Instance.new("ImageLabel")
	icon.Name="ActionIcon"
	icon.AnchorPoint=Vector2.new(.5,0)
	icon.Position=UDim2.new(.5,0,0,5)
	icon.Size=UDim2.fromOffset(22,22)
	icon.BackgroundTransparency=1
	icon.Image=image
	icon.ScaleType=Enum.ScaleType.Fit
	icon.ImageTransparency=.03
	icon.ZIndex=buttonObj.ZIndex+1
	icon.Parent=buttonObj

	-- Leave the lower half of the button for ACTION [KEY].
	buttonObj.TextYAlignment=Enum.TextYAlignment.Bottom
	buttonObj.TextXAlignment=Enum.TextXAlignment.Center
	buttonObj.TextSize=9
end

local SECTION_ICONS={
	["BUILD OBJECTS"]="rbxthumb://type=Asset&id=12884184673&w=150&h=150",
	["EDIT TOOLS"]="rbxassetid://7990453298",
	["HISTORY"]="rbxassetid://5107220223",
	["PROJECT"]="rbxassetid://12665008484",
	["TESTING"]="rbxassetid://8215093343",
}

local function cleanSectionTitle(titleText)
	return (titleText:gsub("^%S+%s+",""))
end

local function section(parent,titleText,subtitle,width,accent)
	local f=Instance.new("Frame")
	f.Size=UDim2.fromOffset(width,116);f.BackgroundColor3=Color3.fromRGB(20,31,45)
	f.BackgroundTransparency=.04;f.BorderSizePixel=0;f.Parent=parent;corner(f,10);stroke(f,accent)
	local bar=Instance.new("Frame");bar.Size=UDim2.new(1,0,0,4);bar.BackgroundColor3=accent;bar.BorderSizePixel=0;bar.Parent=f;corner(bar,10)
	local cleanTitle=cleanSectionTitle(titleText)

	local headerIcon=Instance.new("ImageLabel")
	headerIcon.Name="HeaderIcon"
	headerIcon.Size=UDim2.fromOffset(17,17)
	headerIcon.Position=UDim2.fromOffset(9,9)
	headerIcon.BackgroundTransparency=1
	headerIcon.Image=SECTION_ICONS[cleanTitle] or ""
	headerIcon.ScaleType=Enum.ScaleType.Fit
	headerIcon.ZIndex=3
	headerIcon.Parent=f

	local t=Instance.new("TextLabel")
	t.Name="HeaderTitle"
	t.Size=UDim2.new(1,-42,0,20)
	t.Position=UDim2.fromOffset(31,8)
	t.BackgroundTransparency=1
	t.Text=cleanTitle
	t.TextXAlignment=Enum.TextXAlignment.Left
	t.Font=Enum.Font.GothamBlack
	t.TextSize=12
	t.TextColor3=Color3.new(1,1,1)
	t.Parent=f
	local sub=Instance.new("TextLabel");sub.Size=UDim2.new(1,-16,0,16);sub.Position=UDim2.fromOffset(10,27);sub.BackgroundTransparency=1
	sub.Text=subtitle;sub.TextXAlignment=Enum.TextXAlignment.Left;sub.Font=Enum.Font.Gotham;sub.TextSize=9;sub.TextColor3=Color3.fromRGB(157,169,185);sub.Parent=f
	local body=Instance.new("Frame");body.Size=UDim2.new(1,-16,0,62);body.Position=UDim2.fromOffset(8,46);body.BackgroundTransparency=1;body.Parent=f
	local l=Instance.new("UIListLayout");l.FillDirection=Enum.FillDirection.Horizontal;l.Padding=UDim.new(0,5);l.VerticalAlignment=Enum.VerticalAlignment.Center;l.Parent=body
	return f,body
end

-- Header
local header=Instance.new("Frame")
header.Size=UDim2.new(1,0,0,58);header.BackgroundColor3=Color3.fromRGB(13,27,42);header.BorderSizePixel=0;header.Parent=gui
local brand=Instance.new("TextLabel")
brand.Size=UDim2.fromOffset(380,48);brand.Position=UDim2.fromOffset(20,5);brand.BackgroundTransparency=1
brand.Text="◈  PARKOUR BUILDER\n     MAKE YOUR OWN PARKOUR";brand.TextXAlignment=Enum.TextXAlignment.Left
brand.Font=Enum.Font.GothamBlack;brand.TextSize=16;brand.TextColor3=Color3.new(1,1,1);brand.Parent=header

local modeBadge=Instance.new("TextLabel")
modeBadge.Size=UDim2.fromOffset(200,40);modeBadge.Position=UDim2.new(1,-365,0,9)
modeBadge.BackgroundColor3=Color3.fromRGB(25,40,57);modeBadge.BorderSizePixel=0
modeBadge.Text="🔨  BUILD MODE\nCreate • Test • Publish";modeBadge.Font=Enum.Font.GothamBold
modeBadge.TextSize=11;modeBadge.TextColor3=Color3.fromRGB(220,230,240);modeBadge.Parent=header;corner(modeBadge,10);stroke(modeBadge,Color3.fromRGB(45,145,230))

local discover=btn(header,"←  DISCOVER",145,40)
discover.Position=UDim2.new(1,-155,0,9)

-- In the owner's reserved Creator server this button leaves the private
-- session, so label it RETURN instead of DISCOVER.
local function refreshReturnButton()
	local ownerUserId=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))
	local isReservedOwner=
		(ownerUserId~=nil and ownerUserId==player.UserId)
		or player:GetAttribute("ParkourCreatorOwner")==true
		or (
			RunService:IsStudio()
			and player:GetAttribute("ParkourPrivateCreator")==true
		)

	discover.Text=isReservedOwner and "←  RETURN" or "←  DISCOVER"
end

refreshReturnButton()
player:GetAttributeChangedSignal("ParkourCreatorOwner"):Connect(refreshReturnButton)
player:GetAttributeChangedSignal("ParkourPrivateCreator"):Connect(refreshReturnButton)
workspace:GetAttributeChangedSignal("ParkourCreatorOwnerUserId"):Connect(refreshReturnButton)

-- Group bar
local groups=Instance.new("ScrollingFrame")
groups.Size=UDim2.new(1,-24,0,126);groups.Position=UDim2.fromOffset(12,66)
groups.BackgroundTransparency=1;groups.BorderSizePixel=0;groups.ScrollBarThickness=3
groups.CanvasSize=UDim2.fromOffset(1470,0);groups.ScrollingDirection=Enum.ScrollingDirection.X;groups.Parent=gui
local gl=Instance.new("UIListLayout");gl.FillDirection=Enum.FillDirection.Horizontal;gl.Padding=UDim.new(0,8);gl.Parent=groups
gl:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	groups.CanvasSize=UDim2.fromOffset(gl.AbsoluteContentSize.X,0)
end)

local buildSec,buildBody=section(groups,"▣  BUILD OBJECTS","Place parkour elements",430,Color3.fromRGB(40,170,245))
local BUILD_EXPANDED_HEIGHT=116
local BUILD_COLLAPSED_HEIGHT=48
local buildCollapsed=false

local buildCollapse=Instance.new("TextButton")
buildCollapse.Name="CollapseBuildObjects"
buildCollapse.Size=UDim2.fromOffset(30,30)
buildCollapse.Position=UDim2.new(1,-36,0,7)
buildCollapse.BackgroundColor3=Color3.fromRGB(36,49,65)
buildCollapse.BorderSizePixel=0
buildCollapse.Text="▲"
buildCollapse.Font=Enum.Font.GothamBlack
buildCollapse.TextSize=14
buildCollapse.TextColor3=Color3.fromRGB(205,235,250)
buildCollapse.ZIndex=10
buildCollapse.Parent=buildSec
corner(buildCollapse,7)

local function setBuildObjectsCollapsed(collapsed)
	buildCollapsed=collapsed

	-- Header stays visible at all times.
	-- Only the subtitle and object-button body collapse.
	buildBody.Visible=not collapsed

	for _,child in ipairs(buildSec:GetChildren()) do
		if child:IsA("TextLabel") then
			if child.Text=="BUILD OBJECTS" then
				child.Visible=true
			elseif child.Text=="Place parkour elements" then
				child.Visible=not collapsed
			end
		end
	end

	if collapsed then
		-- Collapse vertically upward: keep full width, reduce only height.
		buildSec.Size=UDim2.fromOffset(430,BUILD_COLLAPSED_HEIGHT)
		buildCollapse.Text="▼"
	else
		buildSec.Size=UDim2.fromOffset(430,BUILD_EXPANDED_HEIGHT)
		buildCollapse.Text="▲"
	end

	task.defer(function()
		groups.CanvasSize=UDim2.fromOffset(gl.AbsoluteContentSize.X,0)
	end)
end

buildCollapse.MouseButton1Click:Connect(function()
	setBuildObjectsCollapsed(not buildCollapsed)
end)

-- EDIT TOOLS removed from the visible toolbar.
-- SELECT remains the default editor mode and transformations are accessed
-- from the selected object's floating transformation palette.
local editSec=Instance.new("Frame")
editSec.Name="HiddenEditTools"
editSec.Size=UDim2.fromOffset(0,0)
editSec.BackgroundTransparency=1
editSec.Visible=false
editSec.Parent=gui

local editBody=Instance.new("Frame")
editBody.Name="HiddenEditToolsBody"
editBody.Size=UDim2.fromOffset(0,0)
editBody.BackgroundTransparency=1
editBody.Visible=false
editBody.Parent=editSec
local histSec,histBody=section(groups,"↶  HISTORY","Undo / redo",150,Color3.fromRGB(185,80,230))
local projectSec,projectBody=section(groups,"▤  PROJECT","Load, validate, publish or clear",320,Color3.fromRGB(245,140,55))
local testSec,testBody=section(groups,"▶  TESTING","Playtest course",115,Color3.fromRGB(35,220,215))

local types={"Platform","KillBlock","BouncePad","SpeedPad","Checkpoint","Start","Finish"}
local typeButtons={}
for _,t in ipairs(types) do
	local b=btn(buildBody,t,56,54);typeButtons[t]=b
	addButtonIcon(b,t)
	b.MouseButton1Click:Connect(function()
		-- Enter placement mode directly. Visual/selection cleanup is handled
		-- by the mode cleanup loop after those systems are initialized.
		selectedObject=nil
		selectedType=t
		placementRotationY=0
		placementScale=Vector3.new(1,1,1)
		mode="Place"
	end)
end

local actionButtons={}
for _,name in ipairs({"SELECT","MOVE","ROTATE","SCALE +","SCALE -","DELETE"}) do
	local b=btn(editBody,name,72,54);actionButtons[name]=b
	addButtonIcon(b,name)
end
actionButtons["UNDO"]=btn(histBody,"UNDO",64,54)
addButtonIcon(actionButtons["UNDO"],"UNDO")
actionButtons["REDO"]=btn(histBody,"REDO",64,54)
addButtonIcon(actionButtons["REDO"],"REDO")
-- Mirror the shared directional icon so REDO reads opposite to UNDO.
local redoIcon=actionButtons["REDO"]:FindFirstChild("ActionIcon")
if redoIcon then redoIcon.Rotation=180 end
-- Manual SAVE button removed: Auto Save now handles draft saving.
-- Keep a hidden compatibility button because older callback code still references actionButtons["SAVE"].
actionButtons["SAVE"]=Instance.new("TextButton")
actionButtons["SAVE"].Name="HiddenSaveButton"
actionButtons["SAVE"].Visible=false
actionButtons["SAVE"].Active=false
actionButtons["SAVE"].Parent=gui

for _,name in ipairs({"LOAD","VALIDATE","PUBLISH"}) do
	actionButtons[name]=btn(projectBody,name,72,54)
	addButtonIcon(actionButtons[name],name)
end
actionButtons["CLEAR"]=btn(projectBody,"CLEAR",65,66)
actionButtons["CLEAR"].BackgroundColor3=Color3.fromRGB(145,55,65)
actionButtons["TEST"]=btn(testBody,"TEST",100,66)

local function refreshGuestProjectControls()
	local guest=isExplicitGuest()
	-- Collaborators edit the live working copy, but owner retains project authority.
	projectSec.Visible=not guest
	testSec.Visible=not guest
end

player:GetAttributeChangedSignal("ParkourCreatorGuest"):Connect(refreshGuestProjectControls)
task.defer(refreshGuestProjectControls)

-- Quick Tips removed from Builder UI.
local tips=nil
local tipsText=nil
local function refreshTips() end

-- BUILD OBJECT KEY LABELS
local objectActions={"Platform","KillBlock","BouncePad","SpeedPad","Checkpoint","Start","Finish"}

local function shortKey(action)
	-- Attributes are the authoritative current-session settings.
	local n=playerGui:GetAttribute("ParkourBind_"..action) or keyName(action)
	local prettyKeys={
		One="1",Two="2",Three="3",Four="4",Five="5",Six="6",Seven="7",
		Space="SPACE",LeftShift="LSHIFT",RightShift="RSHIFT"
	}
	return prettyKeys[n] or string.upper(n)
end

refreshObjectButtonKeys=function()
	for _,action in ipairs(objectActions) do
		local b=typeButtons[action]
		if b then
			local saved=playerGui:GetAttribute("ParkourBind_"..action)
			local key=saved or keybinds[action] or DEFAULT_BINDS[action] or "?"
			local prettyKeys={
				One="1",Two="2",Three="3",Four="4",Five="5",Six="6",Seven="7",
				Space="SPACE",LeftShift="LSHIFT",RightShift="RSHIFT"
			}
			local shown=prettyKeys[key] or string.upper(tostring(key))
			local displayName=action
			if action=="KillBlock" then displayName="KillBlock"
			elseif action=="BouncePad" then displayName="BouncePad"
			elseif action=="SpeedPad" then displayName="SpeedPad" end

			b.Text=displayName.." ["..shown.."]"
			b.TextWrapped=true
			b.TextSize=9
		end
	end
end

refreshObjectButtonKeys()

-- Ask Settings for the player's actual configured/saved bindings now that
-- the Builder buttons exist. This removes LocalScript load-order races.
-- Do not rely on LocalScript startup order. Ask both the Settings client
-- and the persistence server for the player's current saved bindings.
keybindSaveRemote.OnClientEvent:Connect(function(action,data)
	if action=="Loaded" and type(data)=="table" then
		applyBindings(data)
		refreshObjectButtonKeys()
		print("[KEYBINDS] Builder loaded saved bindings")
	end
end)

task.defer(function()
	pullAuthoritativeBindings()
	keybindEvent:Fire("RequestBindings")
	refreshObjectButtonKeys()
end)

keybindEvent.Event:Connect(function(action)
	if action=="BindingsChanged" then refreshObjectButtonKeys() end
end)
for _,action in ipairs(objectActions) do
	playerGui:GetAttributeChangedSignal("ParkourBind_"..action):Connect(refreshObjectButtonKeys)
end

-- TOOL / HISTORY / TEST KEY LABELS
local function prettyBinding(action,fallback)
	local key=playerGui:GetAttribute("ParkourBind_"..action) or keybinds[action] or fallback
	local prettyKeys={
		One="1",Two="2",Three="3",Four="4",Five="5",Six="6",Seven="7",
		Space="SPACE",LeftShift="LSHIFT",RightShift="RSHIFT",
		Delete="DEL"
	}
	return prettyKeys[key] or string.upper(tostring(key or "?"))
end

local function setButtonKey(buttonObj,label,keyText)
	if not buttonObj then return end
	buttonObj.Text=label.." ["..keyText.."]"
	buttonObj.TextWrapped=true
	buttonObj.TextSize=9
end

local function refreshToolButtonKeys()
	setButtonKey(actionButtons["SELECT"],"SELECT","CLICK")
	setButtonKey(actionButtons["MOVE"],"MOVE",prettyBinding("Move","G"))
	setButtonKey(actionButtons["ROTATE"],"ROTATE",prettyBinding("Rotate","E"))
	setButtonKey(actionButtons["SCALE +"],"SCALE +",prettyBinding("Scale","R"))
	setButtonKey(actionButtons["SCALE -"],"SCALE -","SHIFT+"..prettyBinding("Scale","R"))
	setButtonKey(actionButtons["DELETE"],"DELETE","DEL")

	setButtonKey(actionButtons["UNDO"],"UNDO","CTRL+Z")
	setButtonKey(actionButtons["REDO"],"REDO","CTRL+Y")
	setButtonKey(actionButtons["TEST"],"TEST",prettyBinding("Test","F"))
end

refreshToolButtonKeys()

local toolBindingActions={"Move","Rotate","Scale","Test"}
for _,action in ipairs(toolBindingActions) do
	playerGui:GetAttributeChangedSignal("ParkourBind_"..action):Connect(refreshToolButtonKeys)
end

keybindEvent.Event:Connect(function(action)
	if action=="BindingsChanged" then
		refreshToolButtonKeys()
	end
end)

-- Status card
local status=Instance.new("TextLabel")
status.Size=UDim2.fromOffset(420,62);status.Position=UDim2.new(0,14,1,-76)
status.BackgroundColor3=Color3.fromRGB(18,30,44);status.BackgroundTransparency=.03;status.BorderSizePixel=0
status.Text="▣  PLACE - Platform\n     Click a surface to place a Platform"
status.TextXAlignment=Enum.TextXAlignment.Left;status.Font=Enum.Font.GothamBlack;status.TextSize=14
status.TextColor3=Color3.new(1,1,1);status.Parent=gui;corner(status,11);stroke(status,Color3.fromRGB(40,160,245))

local function updateStatus(text)
	status.Text=text or ("▣  "..string.upper(mode).." - "..selectedType)
end

local function raycastMouse()
	local camera=workspace.CurrentCamera
	local mouse=UIS:GetMouseLocation()
	local ray=camera:ViewportPointToRay(mouse.X,mouse.Y)
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
	if player.Character then params.FilterDescendantsInstances={player.Character} end
	return workspace:Raycast(ray.Origin,ray.Direction*1000,params)
end
local function editableOwnerUserId()
	local ownerId=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))
	if ownerId and guestCanBuild() then
		return ownerId
	end
	return player.UserId
end

local function ownedTarget(hit)
	if not hit then return nil end
	local p=hit.Instance
	if not (p and p:IsA("BasePart") and p:GetAttribute("Owner")==editableOwnerUserId()) then return nil end

	local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	-- Default selection range = 45 studs.
	-- ParkourSelectRange can later be changed without rewriting this function.
	if (p.Position-root.Position).Magnitude >
		math.clamp(tonumber(playerGui:GetAttribute("ParkourSelectRange")) or 45,10,100) then
		return nil
	end

	return p
end

-- Forward declaration: MOVE/ROTATE callbacks below use this function,
-- while its full implementation is created later with the visual tools.
local clearAdvancedToolVisuals=function() end
local clearMoveVisuals=function() end
local clearRotateVisuals=function() end
local makeMoveGhost=function() end
local showRotateControls=function() end
local showScalePreview=function() end
local clearScalePreview=function() end

-- SELECT MODE
local selectHighlight=Instance.new("Highlight")
selectHighlight.Name="BuilderSelectionHighlight"
selectHighlight.FillColor=Color3.fromRGB(65,175,255)
selectHighlight.FillTransparency=.82
selectHighlight.OutlineColor=Color3.fromRGB(105,220,255)
selectHighlight.OutlineTransparency=0
selectHighlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
selectHighlight.Enabled=false
selectHighlight.Parent=workspace

local selectionUiSuspended=false

-- STRONG MOUSE HOVER OUTLINE
-- Separate from the blue selected-object highlight.
local hoverHighlight=Instance.new("Highlight")
hoverHighlight.Name="BuilderHoverHighlight"
hoverHighlight.FillColor=Color3.fromRGB(110,220,255)
hoverHighlight.FillTransparency=.92
hoverHighlight.OutlineColor=Color3.fromRGB(235,255,255)
hoverHighlight.OutlineTransparency=0
hoverHighlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
hoverHighlight.Enabled=false
hoverHighlight.Parent=workspace

-- HOVER CLICK-TO-SELECT PROMPT
-- Built inside a scope to avoid increasing this large script's top-level local count.
do
	local g=Instance.new("BillboardGui")
	g.Name="HoverClickToSelect"
	g.Size=UDim2.fromOffset(180,34)
	g.AlwaysOnTop=true
	g.LightInfluence=0
	g.MaxDistance=90
	g.Enabled=false
	g.Parent=playerGui

	local f=Instance.new("Frame")
	f.Size=UDim2.fromScale(1,1)
	f.BackgroundColor3=Color3.fromRGB(20,25,34)
	f.BackgroundTransparency=.08
	f.BorderSizePixel=0
	f.Parent=g

	local c=Instance.new("UICorner")
	c.CornerRadius=UDim.new(0,9)
	c.Parent=f

	local st=Instance.new("UIStroke")
	st.Color=Color3.fromRGB(225,245,255)
	st.Thickness=1.5
	st.Transparency=.15
	st.Parent=f

	local t=Instance.new("TextLabel")
	t.Size=UDim2.fromScale(1,1)
	t.BackgroundTransparency=1
	t.Text="◉  Click to select"
	t.Font=Enum.Font.GothamBold
	t.TextSize=13
	t.TextColor3=Color3.new(1,1,1)
	t.Parent=f
end

local selectionGui=Instance.new("Frame")
selectionGui.Name="SelectionTransformPalette"
selectionGui.Size=UDim2.fromOffset(390,62)
selectionGui.AnchorPoint=Vector2.new(.5,1)
selectionGui.BackgroundTransparency=1
selectionGui.Visible=false
selectionGui.ZIndex=120
selectionGui.Parent=gui

local paletteFrame=Instance.new("Frame")
paletteFrame.Size=UDim2.fromScale(1,1)
paletteFrame.BackgroundColor3=Color3.fromRGB(10,27,43)
paletteFrame.BackgroundTransparency=.06
paletteFrame.BorderSizePixel=0
paletteFrame.ZIndex=121
paletteFrame.Parent=selectionGui
local pfc=Instance.new("UICorner");pfc.CornerRadius=UDim.new(0,11);pfc.Parent=paletteFrame
local pfs=Instance.new("UIStroke");pfs.Color=Color3.fromRGB(65,185,245);pfs.Transparency=.15;pfs.Thickness=2;pfs.Parent=paletteFrame

local paletteLayout=Instance.new("UIListLayout")
paletteLayout.FillDirection=Enum.FillDirection.Horizontal
paletteLayout.HorizontalAlignment=Enum.HorizontalAlignment.Center
paletteLayout.VerticalAlignment=Enum.VerticalAlignment.Center
paletteLayout.Padding=UDim.new(0,5)
paletteLayout.Parent=paletteFrame

local function paletteButton(text,w)
	local b=Instance.new("TextButton")
	b.Size=UDim2.fromOffset(w or 68,42)
	b.BackgroundColor3=Color3.fromRGB(38,58,78)
	b.BorderSizePixel=0
	b.Text=text
	b.Font=Enum.Font.GothamBlack
	b.TextSize=11
	b.TextColor3=Color3.new(1,1,1)
	b.ZIndex=122
	b.Active=true
	b.AutoButtonColor=true
	b.Parent=paletteFrame
	local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,8);c.Parent=b
	return b
end

local selectMove=paletteButton("MOVE",66)
local selectRotate=paletteButton("ROTATE",72)
local selectScaleUp=paletteButton("SCALE +",72)
local selectScaleDown=paletteButton("SCALE -",72)
local selectDelete=paletteButton("DELETE",70)
selectDelete.BackgroundColor3=Color3.fromRGB(145,55,65)

local function hideSelectionPalette()
	selectionGui.Visible=false
end

local function clearSelection()
	selectionUiSuspended=false
	selectedObject=nil
	selectHighlight.Adornee=nil
	selectHighlight.Enabled=false
	hideSelectionPalette()
end

local function selectObject(obj)
	clearAdvancedToolVisuals()
	if obj and obj.Parent and obj:GetAttribute("Owner")==editableOwnerUserId() then
		selectedObject=obj
		selectHighlight.Adornee=obj
		selectHighlight.Enabled=true
		selectionGui.Visible=false
		updateStatus("SELECTED • "..tostring(obj.Name).." • use the transformation HUD below")
	else
		clearSelection()
		updateStatus("SELECT • click one of your objects")
	end
end

-- Track the selected object in screen space. Unlike TextButtons inside a
-- BillboardGui, these are ordinary ScreenGui buttons and reliably receive clicks.
RunService.RenderStepped:Connect(function()
	-- Strong hover outline while in Select mode.
	if mode=="Select" and not testing then
		local hoverHit=raycastMouse()
		local hoverObject=ownedTarget(hoverHit)

		-- Don't stack hover and selected highlights on the same object.
		if hoverObject and hoverObject~=selectedObject then
			hoverHighlight.Adornee=hoverObject
			hoverHighlight.Enabled=true
			if playerGui:FindFirstChild("HoverClickToSelect") then
				playerGui.HoverClickToSelect.Adornee=hoverObject
				playerGui.HoverClickToSelect.StudsOffset=Vector3.new(0,hoverObject.Size.Y/2+2.15,0)
				playerGui.HoverClickToSelect.Enabled=true
			end
		else
			hoverHighlight.Adornee=nil
			hoverHighlight.Enabled=false
			if playerGui:FindFirstChild("HoverClickToSelect") then
				playerGui.HoverClickToSelect.Adornee=nil
				playerGui.HoverClickToSelect.Enabled=false
			end
		end
	else
		hoverHighlight.Adornee=nil
		hoverHighlight.Enabled=false
		if playerGui:FindFirstChild("HoverClickToSelect") then
			playerGui.HoverClickToSelect.Adornee=nil
			playerGui.HoverClickToSelect.Enabled=false
		end
	end

	-- Legacy floating MOVE / ROTATE / SCALE / DELETE palette removed.
	-- The permanent bottom transformation HUD is now the only transform UI.
	selectionGui.Visible=false
end)

selectMove.MouseButton1Click:Connect(function()
	if not selectedObject or not selectedObject.Parent then
		updateStatus("SELECT • object is no longer available")
		return
	end
	local obj=selectedObject
	hideSelectionPalette()
	clearRotateVisuals()
	mode="Move"
	selectedObject=obj
	makeMoveGhost(obj)
	updateStatus("MOVE • preview destination, click to confirm")
end)

selectRotate.MouseButton1Click:Connect(function()
	if not selectedObject or not selectedObject.Parent then
		updateStatus("SELECT • object is no longer available")
		return
	end
	local obj=selectedObject
	hideSelectionPalette()
	clearMoveVisuals()
	mode="Rotate"
	selectedObject=obj
	showRotateControls(obj)
	updateStatus("ROTATE • use the -1° / +1° arrows")
end)

selectScaleUp.MouseButton1Click:Connect(function()
	if selectedObject and selectedObject.Parent then
		showScalePreview(selectedObject,1)
	end
end)

selectScaleDown.MouseButton1Click:Connect(function()
	if selectedObject and selectedObject.Parent then
		showScalePreview(selectedObject,-1)
	end
end)

selectDelete.MouseButton1Click:Connect(function()
	if selectedObject and selectedObject.Parent then
		remote:FireServer("Delete",selectedObject)
		clearSelection()
		mode="Select"
		updateStatus("SELECT • click one of your objects")
	end
end)

-- SELECT-ONLY TRANSFORMATION POLICY
-- Move / Rotate / Scale / Delete are available only from the floating
-- palette after selecting one of the player's objects.
for _,toolName in ipairs({"MOVE","ROTATE","SCALE +","SCALE -","DELETE"}) do
	local toolButton=actionButtons[toolName]
	if toolButton then
		toolButton.Visible=false
		toolButton.Active=false
		toolButton.Size=UDim2.fromOffset(0,0)
	end
end

actionButtons["SELECT"].MouseButton1Click:Connect(function()
	clearAdvancedToolVisuals()
	clearSelection()
	mode="Select"
	updateStatus("SELECT • click one of your objects")
end)

actionButtons["MOVE"].MouseButton1Click:Connect(function() clearSelection();
	clearAdvancedToolVisuals();selectedObject=nil;mode="Move";updateStatus("MOVE • select an object")
end)
actionButtons["ROTATE"].MouseButton1Click:Connect(function() clearSelection();
	clearAdvancedToolVisuals();selectedObject=nil;mode="Rotate";updateStatus("ROTATE • select an object")
end)
actionButtons["SCALE +"].MouseButton1Click:Connect(function() clearSelection(); clearAdvancedToolVisuals(); selectedObject=nil; mode="Scale+"; updateStatus("SCALE + • click your object") end)
actionButtons["SCALE -"].MouseButton1Click:Connect(function() clearSelection(); clearAdvancedToolVisuals(); selectedObject=nil; mode="Scale-"; updateStatus("SCALE - • click your object") end)
actionButtons["DELETE"].MouseButton1Click:Connect(function() clearSelection(); clearAdvancedToolVisuals(); selectedObject=nil; mode="Delete"; updateStatus("DELETE • click your object") end)
actionButtons["UNDO"].MouseButton1Click:Connect(function()remote:FireServer("Undo")end)
actionButtons["REDO"].MouseButton1Click:Connect(function()remote:FireServer("Redo")end)
actionButtons["SAVE"].MouseButton1Click:Connect(function()remote:FireServer("SaveDraft")end)
actionButtons["LOAD"].MouseButton1Click:Connect(function()remote:FireServer("LoadDraft")end)
actionButtons["VALIDATE"].MouseButton1Click:Connect(function()remote:FireServer("ValidatePublish")end)
actionButtons["TEST"].MouseButton1Click:Connect(function()remote:FireServer("Test")end)

-- EXIT BUILD MODE TRANSITION
-- IMPORTANT: this lives in its OWN ScreenGui.
-- ParkourBuilderUI is disabled during the transition, so the transition
-- cannot be parented to the Builder ScreenGui.
local exitTransitionGui=Instance.new("ScreenGui")
exitTransitionGui.Name="ParkourExitTransitionUI"
exitTransitionGui.ResetOnSpawn=false
exitTransitionGui.IgnoreGuiInset=true
exitTransitionGui.DisplayOrder=500
exitTransitionGui.Enabled=false
exitTransitionGui.Parent=playerGui

local exitOverlay=Instance.new("Frame")
exitOverlay.Name="ExitBuildTransition"
exitOverlay.Size=UDim2.fromScale(1,1)
exitOverlay.BackgroundColor3=Color3.fromRGB(5,14,25)
exitOverlay.BackgroundTransparency=1
exitOverlay.BorderSizePixel=0
exitOverlay.Visible=false
exitOverlay.Active=true
exitOverlay.ZIndex=300
exitOverlay.Parent=exitTransitionGui

local exitIcon=Instance.new("TextLabel")
exitIcon.Size=UDim2.fromOffset(120,90)
exitIcon.Position=UDim2.new(.5,-60,.5,-155)
exitIcon.BackgroundTransparency=1
exitIcon.Text="🚪➜"
exitIcon.Font=Enum.Font.GothamBlack
exitIcon.TextSize=54
exitIcon.TextColor3=Color3.fromRGB(95,205,255)
exitIcon.TextTransparency=1
exitIcon.ZIndex=301
exitIcon.Parent=exitOverlay

local exitTitle=Instance.new("TextLabel")
exitTitle.Size=UDim2.new(1,-60,0,60)
exitTitle.Position=UDim2.new(0,30,.5,-65)
exitTitle.BackgroundTransparency=1
exitTitle.Text="EXITING BUILD MODE..."
exitTitle.Font=Enum.Font.GothamBlack
exitTitle.TextSize=30
exitTitle.TextColor3=Color3.new(1,1,1)
exitTitle.TextTransparency=1
exitTitle.ZIndex=301
exitTitle.Parent=exitOverlay

local exitSub=Instance.new("TextLabel")
exitSub.Size=UDim2.new(1,-60,0,35)
exitSub.Position=UDim2.new(0,30,.5,-5)
exitSub.BackgroundTransparency=1
exitSub.Text="Returning you to the parkour menu"
exitSub.Font=Enum.Font.GothamMedium
exitSub.TextSize=17
exitSub.TextColor3=Color3.fromRGB(165,215,245)
exitSub.TextTransparency=1
exitSub.ZIndex=301
exitSub.Parent=exitOverlay

local progressBack=Instance.new("Frame")
progressBack.Size=UDim2.fromOffset(470,16)
progressBack.Position=UDim2.new(.5,-235,.5,55)
progressBack.BackgroundColor3=Color3.fromRGB(52,75,98)
progressBack.BackgroundTransparency=.15
progressBack.BorderSizePixel=0
progressBack.ZIndex=301
progressBack.Parent=exitOverlay
corner(progressBack,8)

local progressFill=Instance.new("Frame")
progressFill.Size=UDim2.fromScale(0,1)
progressFill.BackgroundColor3=Color3.fromRGB(65,205,255)
progressFill.BorderSizePixel=0
progressFill.ZIndex=302
progressFill.Parent=progressBack
corner(progressFill,8)

local exitStatus=Instance.new("TextLabel")
exitStatus.Size=UDim2.new(1,-60,0,30)
exitStatus.Position=UDim2.new(0,30,.5,92)
exitStatus.BackgroundTransparency=1
exitStatus.Text="Saving your latest changes..."
exitStatus.Font=Enum.Font.GothamMedium
exitStatus.TextSize=14
exitStatus.TextColor3=Color3.fromRGB(155,195,220)
exitStatus.TextTransparency=1
exitStatus.ZIndex=301
exitStatus.Parent=exitOverlay

local tip=Instance.new("TextLabel")
tip.Size=UDim2.fromOffset(340,72)
tip.Position=UDim2.new(0,28,1,-100)
tip.BackgroundColor3=Color3.fromRGB(12,26,41)
tip.BackgroundTransparency=.08
tip.BorderSizePixel=0
tip.Text="💾  AUTO SAVE\nSaving before you leave Build Mode"
tip.TextXAlignment=Enum.TextXAlignment.Left
tip.Font=Enum.Font.GothamBold
tip.TextSize=14
tip.TextColor3=Color3.fromRGB(205,225,240)
tip.TextTransparency=1
tip.ZIndex=301
tip.Parent=exitOverlay
corner(tip,11)
stroke(tip,Color3.fromRGB(55,145,205))

local exiting=false
local function playExitTransition()
	if exiting then return end
	exiting=true

	-- Save the latest draft immediately before leaving Build Mode.
	-- This uses the same server SaveDraft path as Auto Save.
	remote:FireServer("SaveDraft")

	-- Show transition in its independent ScreenGui first.
	exitTransitionGui.Enabled=true
	exitOverlay.Visible=true
	exitOverlay.BackgroundTransparency=1
	exitIcon.TextTransparency=1
	exitTitle.TextTransparency=1
	exitSub.TextTransparency=1
	exitStatus.TextTransparency=1
	tip.TextTransparency=1
	progressFill.Size=UDim2.fromScale(0,1)

	TweenService:Create(exitOverlay,TweenInfo.new(.22),{BackgroundTransparency=.06}):Play()
	TweenService:Create(exitIcon,TweenInfo.new(.22),{TextTransparency=0}):Play()
	TweenService:Create(exitTitle,TweenInfo.new(.22),{TextTransparency=0}):Play()
	TweenService:Create(exitSub,TweenInfo.new(.28),{TextTransparency=0}):Play()
	TweenService:Create(exitStatus,TweenInfo.new(.28),{TextTransparency=0}):Play()
	TweenService:Create(tip,TweenInfo.new(.28),{TextTransparency=0}):Play()

	-- Give the transition one frame to render, then hide Builder behind it.
	game:GetService("RunService").RenderStepped:Wait()
	gui.Enabled=false

	local progress=TweenService:Create(
		progressFill,
		TweenInfo.new(1.15,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
		{Size=UDim2.fromScale(1,1)}
	)
	progress:Play()
	progress.Completed:Wait()

	exitStatus.Text="Returning to Discover server..."

	-- In a reserved Creator server, leaving Build Mode means leaving the
	-- reserved instance completely. The server performs a normal teleport
	-- back to this PlaceId (no reserved access code).
	returnPublicRemote:FireServer("Return")

	-- Keep the transition visible while Roblox begins the teleport.
	-- In Studio the server replies with StudioReturned instead.
	task.wait(8)

	-- Safety fallback if a published teleport fails without a response.
	if exiting then
		exitStatus.Text="Could not return yet. Please try again."
		task.wait(1.2)
		exitOverlay.Visible=false
		exitTransitionGui.Enabled=false
		gui.Enabled=true
		exiting=false
	end
end

-- Return-to-public responses.
returnPublicRemote.OnClientEvent:Connect(function(action,message)
	if action=="StudioReturned" then
		-- Studio simulation: no real server teleport.
		playerGui:SetAttribute("CreatorTransitionActive",false)
		exitStatus.Text="Opening Discover..."
		navigationEvent:Fire("Discover")
		task.wait(.35)

		exitOverlay.Visible=false
		exitTransitionGui.Enabled=false
		exiting=false

	elseif action=="Failed" then
		warn("[RETURN PUBLIC] "..tostring(message or "Teleport failed"))
		exitStatus.Text="Return failed. Please try again."
		task.wait(1)
		exitOverlay.Visible=false
		exitTransitionGui.Enabled=false
		gui.Enabled=true
		exiting=false
	end
end)

-- Return to Discover by leaving the reserved Creator server.
discover.MouseButton1Click:Connect(function()
	if testing then
		updateStatus("⚠ EXIT TEST MODE BEFORE RETURNING TO DISCOVER")
		return
	end
	task.spawn(playExitTransition)
end)

-- CLEAR PLOT CONFIRMATION
local clearModal=Instance.new("Frame")
clearModal.Size=UDim2.fromOffset(410,220)
clearModal.Position=UDim2.new(.5,-205,.5,-110)
clearModal.BackgroundColor3=Color3.fromRGB(27,33,42)
clearModal.BorderSizePixel=0
clearModal.Visible=false
clearModal.ZIndex=80
clearModal.Parent=gui
corner(clearModal,14)
stroke(clearModal,Color3.fromRGB(210,70,80))

local clearTitle=Instance.new("TextLabel")
clearTitle.Size=UDim2.new(1,-30,0,42);clearTitle.Position=UDim2.fromOffset(15,16)
clearTitle.BackgroundTransparency=1;clearTitle.Text="CLEAR YOUR PLOT?"
clearTitle.Font=Enum.Font.GothamBlack;clearTitle.TextSize=20
clearTitle.TextColor3=Color3.new(1,1,1);clearTitle.ZIndex=81;clearTitle.Parent=clearModal

local clearWarning=Instance.new("TextLabel")
clearWarning.Size=UDim2.new(1,-40,0,70);clearWarning.Position=UDim2.fromOffset(20,65)
clearWarning.BackgroundTransparency=1;clearWarning.TextWrapped=true
clearWarning.Text="This removes every editable block from your current plot. Saved and published parkours are not deleted."
clearWarning.Font=Enum.Font.Gotham;clearWarning.TextSize=14
clearWarning.TextColor3=Color3.fromRGB(195,202,212);clearWarning.ZIndex=81;clearWarning.Parent=clearModal

local confirmClear=btn(clearModal,"CLEAR PLOT",175,45)
confirmClear.Position=UDim2.fromOffset(15,155);confirmClear.BackgroundColor3=Color3.fromRGB(180,55,65);confirmClear.ZIndex=81
local cancelClear=btn(clearModal,"CANCEL",175,45)
cancelClear.Position=UDim2.fromOffset(220,155);cancelClear.ZIndex=81

actionButtons["CLEAR"].MouseButton1Click:Connect(function() clearModal.Visible=true end)
cancelClear.MouseButton1Click:Connect(function() clearModal.Visible=false end)
confirmClear.MouseButton1Click:Connect(function()
	confirmClear.Active=false
	confirmClear.Text="CLEARING..."
	remote:FireServer("ClearPlot")
end)

-- Publish modal
local publish=Instance.new("Frame")
publish.Size=UDim2.fromOffset(410,300);publish.Position=UDim2.new(.5,-205,.5,-150)
publish.BackgroundColor3=Color3.fromRGB(27,33,42);publish.BorderSizePixel=0;publish.Visible=false;publish.ZIndex=20;publish.Parent=gui;corner(publish,14)
local function field(y,placeholder)
	local box=Instance.new("TextBox");box.Size=UDim2.new(1,-30,0,42);box.Position=UDim2.fromOffset(15,y)
	box.BackgroundColor3=Color3.fromRGB(43,50,61);box.BorderSizePixel=0;box.PlaceholderText=placeholder;box.Text=""
	box.ClearTextOnFocus=false;box.Font=Enum.Font.Gotham;box.TextSize=14;box.TextColor3=Color3.new(1,1,1);box.ZIndex=21;box.Parent=publish;corner(box,8);return box
end
local pTitle=field(55,"Parkour title");local pDescription=field(107,"Description");local pDifficulty=field(159,"Easy / Medium / Hard / Extreme")
local ph=Instance.new("TextLabel");ph.Size=UDim2.new(1,-30,0,35);ph.Position=UDim2.fromOffset(15,12);ph.BackgroundTransparency=1
ph.Text="PUBLISH PARKOUR";ph.Font=Enum.Font.GothamBlack;ph.TextSize=19;ph.TextColor3=Color3.new(1,1,1);ph.ZIndex=21;ph.Parent=publish
local publishNow=btn(publish,"PUBLISH",175,45);publishNow.Position=UDim2.fromOffset(15,225);publishNow.ZIndex=21
local cancel=btn(publish,"CANCEL",175,45);cancel.Position=UDim2.fromOffset(220,225);cancel.ZIndex=21
cancel.MouseButton1Click:Connect(function()publish.Visible=false end)
actionButtons["PUBLISH"].MouseButton1Click:Connect(function()remote:FireServer("ValidatePublish");publish.Visible=true end)
publishNow.MouseButton1Click:Connect(function()
	remote:FireServer("Publish",{title=pTitle.Text,description=pDescription.Text,difficulty=pDifficulty.Text})
end)

-- PLOT BOUNDS
local buildPlotModel=workspace:WaitForChild("ParkourCreator"):WaitForChild("BuildPlot")

-- BuildPlot is a Model, so calculate one bounding box for the whole plot.
local function getPlotBounds()
	if buildPlotModel:IsA("BasePart") then
		return buildPlotModel.CFrame,buildPlotModel.Size
	end
	return buildPlotModel:GetBoundingBox()
end

local function clampToPlot(position,objectSize)
	local plotCF,plotSize=getPlotBounds()
	local localPos=plotCF:PointToObjectSpace(position)
	local halfX=math.max(0,plotSize.X/2-objectSize.X/2)
	local halfZ=math.max(0,plotSize.Z/2-objectSize.Z/2)

	localPos=Vector3.new(
		math.clamp(localPos.X,-halfX,halfX),
		localPos.Y,
		math.clamp(localPos.Z,-halfZ,halfZ)
	)
	return plotCF:PointToWorldSpace(localPos)
end

-- LIVE PLACEMENT PREVIEW
-- Selecting a build object now shows a transparent "ghost" at the mouse position.
local previewPart=nil
local previewPosition=nil

-- Replicate the OWNER'S placement preview to guests in the same Creator server.
-- The real preview remains local; only lightweight transform/style data is sent.
local lastSharedPreviewSend=0
local SHARED_PREVIEW_RATE=1/12 -- max 12 updates/sec

local function sendSharedPreview(action,data)
	if not isReservedOwner() and not guestCanBuild() then return end
	sharedPreviewRemote:FireServer(action,data)
end

local previewStyles={
	Platform={size=Vector3.new(8,1,8),color=Color3.fromRGB(80,170,235)},
	KillBlock={size=Vector3.new(8,1,8),color=Color3.fromRGB(235,70,80)},
	BouncePad={size=Vector3.new(8,1,8),color=Color3.fromRGB(235,190,55)},
	SpeedPad={size=Vector3.new(8,1,8),color=Color3.fromRGB(65,205,235)},
	Checkpoint={size=Vector3.new(7,1,7),color=Color3.fromRGB(80,220,120)},
	Start={size=Vector3.new(8,1,8),color=Color3.fromRGB(65,225,150)},
	Finish={size=Vector3.new(8,1,8),color=Color3.fromRGB(235,75,95)}
}

-- Guest-side shared preview. Visual only: never collides, queries, saves or edits.
local guestPreview=nil

local function destroyGuestPreview()
	if guestPreview then
		guestPreview:Destroy()
		guestPreview=nil
	end
end

sharedPreviewRemote.OnClientEvent:Connect(function(action,ownerUserId,data)
	-- Owner already has the high-frequency local preview.
	if tonumber(ownerUserId)==player.UserId then return end

	-- Only guests in this Creator server should render the owner's preview.
	if player:GetAttribute("ParkourCreatorGuest")~=true then
		destroyGuestPreview()
		return
	end

	if action=="Hide" then
		destroyGuestPreview()
		return
	end

	if action~="Update" or type(data)~="table" then return end
	if typeof(data.CFrame)~="CFrame" or typeof(data.Size)~="Vector3" then return end

	if not guestPreview then
		guestPreview=Instance.new("Part")
		guestPreview.Name="GuestOwnerPlacementPreview"
		guestPreview.Anchored=true
		guestPreview.CanCollide=false
		guestPreview.CanTouch=false
		guestPreview.CanQuery=false
		guestPreview.CastShadow=false
		guestPreview.Material=Enum.Material.Neon
		guestPreview.Transparency=.62
		guestPreview.Parent=workspace
	end

	guestPreview.Size=data.Size
	guestPreview.CFrame=data.CFrame
	guestPreview.Color=typeof(data.Color)=="Color3" and data.Color or Color3.fromRGB(80,170,235)
	guestPreview:SetAttribute("PreviewOwnerUserId",tonumber(ownerUserId))
	guestPreview:SetAttribute("PreviewType",tostring(data.Type or "Platform"))
end)

local function destroyPreview()
	if previewPart then previewPart:Destroy();previewPart=nil end
	previewPosition=nil
	sendSharedPreview("Hide")
end

local function ensurePreview()
	if previewPart and previewPart.Parent then return previewPart end
	local style=previewStyles[selectedType] or previewStyles.Platform
	local p=Instance.new("Part")
	p.Name="PlacementPreview"
	p.Size=style.size
	p.Color=style.color
	p.Material=Enum.Material.Neon
	p.Transparency=.55
	p.Anchored=true
	p.CanCollide=false
	p.CanTouch=false
	p.CanQuery=false
	p.CastShadow=false
	p.Parent=workspace
	previewPart=p
	return p
end

local function refreshPreviewStyle()
	if not previewPart then return end
	local style=previewStyles[selectedType] or previewStyles.Platform
	previewPart.Size=Vector3.new(
		math.clamp(style.size.X*placementScale.X,4,30),
		math.clamp(style.size.Y*placementScale.Y,1,12),
		math.clamp(style.size.Z*placementScale.Z,4,30)
	)
	previewPart.Color=style.color
end

RunService.RenderStepped:Connect(function()
	if not gui.Enabled or testing or mode~="Place" then
		if previewPart then previewPart.Transparency=1 end
		if os.clock()-lastSharedPreviewSend>=SHARED_PREVIEW_RATE then
			lastSharedPreviewSend=os.clock()
			sendSharedPreview("Hide")
		end
		return
	end

	local hit=raycastMouse()
	if not hit then
		if previewPart then previewPart.Transparency=1 end
		previewPosition=nil
		if os.clock()-lastSharedPreviewSend>=SHARED_PREVIEW_RATE then
			lastSharedPreviewSend=os.clock()
			sendSharedPreview("Hide")
		end
		return
	end

	local p=ensurePreview()
	refreshPreviewStyle()
	p.Transparency=.55

	-- Snap preview to the existing 2-stud server grid.
	local style=previewStyles[selectedType] or previewStyles.Platform
	local x=math.floor(hit.Position.X/2+.5)*2
	local z=math.floor(hit.Position.Z/2+.5)*2
	local currentSize=p.Size
	local y=hit.Position.Y + currentSize.Y/2
	previewPosition=clampToPlot(Vector3.new(x,y,z),currentSize)
	p.CFrame=CFrame.new(previewPosition)*CFrame.Angles(0,math.rad(placementRotationY),0)

	if os.clock()-lastSharedPreviewSend>=SHARED_PREVIEW_RATE then
		lastSharedPreviewSend=os.clock()
		sendSharedPreview("Update",{
			Kind="Place",
			Type=selectedType,
			CFrame=p.CFrame,
			Size=p.Size,
			Color=p.Color,
		})
	end
end)

-- PRE-PLACEMENT TRANSFORM CONTROLS
local placeTransform=Instance.new("Frame")
placeTransform.Name="PlacementTransformControls"
placeTransform.Size=UDim2.fromOffset(445,58)
placeTransform.AnchorPoint=Vector2.new(.5,1)
placeTransform.BackgroundColor3=Color3.fromRGB(10,27,43)
placeTransform.BackgroundTransparency=.04
placeTransform.BorderSizePixel=0
placeTransform.Visible=false
placeTransform.ZIndex=135
placeTransform.Parent=gui
corner(placeTransform,10)
local pts=Instance.new("UIStroke");pts.Color=Color3.fromRGB(65,200,255);pts.Thickness=2;pts.Transparency=.1;pts.Parent=placeTransform
local ptl=Instance.new("UIListLayout");ptl.FillDirection=Enum.FillDirection.Horizontal;ptl.HorizontalAlignment=Enum.HorizontalAlignment.Center;ptl.VerticalAlignment=Enum.VerticalAlignment.Center;ptl.Padding=UDim.new(0,5);ptl.Parent=placeTransform

local function preBtn(text,w)
	local b=btn(placeTransform,text,w or 70,38)
	b.ZIndex=136
	return b
end
local function placementBind(action,fallback)
	local key=playerGui:GetAttribute("ParkourBind_"..action) or keybinds[action] or fallback
	local pretty={One="1",Two="2",Three="3",Four="4",Five="5",Six="6",Seven="7"}
	return pretty[key] or string.upper(tostring(key or "?"))
end

local preLeft=preBtn("ROTATE -1°\n["..placementBind("Rotate","E").."]",82)
local preRight=preBtn("ROTATE +1°\n[SHIFT+"..placementBind("Rotate","E").."]",100)
local preGrow=preBtn("SCALE +\n["..placementBind("Scale","R").."]",82)
local preShrink=preBtn("SCALE -\n["..placementBind("Scale","R").."]",82)
local preReset=preBtn("RESET\n[X]",70)

local function refreshPlacementTransformKeys()
	preLeft.Text="ROTATE -1°\n["..placementBind("Rotate","E").."]"
	preRight.Text="ROTATE +1°\n[SHIFT+"..placementBind("Rotate","E").."]"
	preGrow.Text="SCALE +\n["..placementBind("Scale","R").."]"
	preShrink.Text="SCALE -\n[SHIFT+"..placementBind("Scale","R").."]"
	preReset.Text="RESET\n[X]"
end

for _,action in ipairs({"Rotate","Scale"}) do
	playerGui:GetAttributeChangedSignal("ParkourBind_"..action):Connect(refreshPlacementTransformKeys)
end

-- Keyboard transforms while previewing a NEW object.
-- Tap = one step. Hold = repeated transformation.
local placementHeld={}
local PLACEMENT_HOLD_DELAY=.22
local PLACEMENT_REPEAT_RATE=1/30

local function placementTransform(action)
	if mode~="Place" or testing then return end

	if action=="RotateLeft" then
		placementRotationY-=1
	elseif action=="RotateRight" then
		placementRotationY+=1
	elseif action=="ScaleUp" then
		placementScale=Vector3.new(
			math.min(3,placementScale.X+.25),
			math.min(3,placementScale.Y+.25),
			math.min(3,placementScale.Z+.25)
		)
	elseif action=="ScaleDown" then
		placementScale=Vector3.new(
			math.max(.5,placementScale.X-.25),
			math.max(.5,placementScale.Y-.25),
			math.max(.5,placementScale.Z-.25)
		)
	end
end

local function startPlacementHold(action,keyCode)
	if placementHeld[keyCode] then return end
	placementHeld[keyCode]=true

	-- Immediate first step.
	placementTransform(action)

	task.spawn(function()
		task.wait(PLACEMENT_HOLD_DELAY)
		while placementHeld[keyCode] and mode=="Place" and not testing do
			placementTransform(action)
			task.wait(PLACEMENT_REPEAT_RATE)
		end
	end)
end

UIS.InputBegan:Connect(function(input,processed)
	if processed or testing or mode~="Place" then return end

	local rotateName=placementBind("Rotate","E")
	local scaleName=placementBind("Scale","R")
	local rotateKey=Enum.KeyCode[rotateName]
	local scaleKey=Enum.KeyCode[scaleName]

	if rotateKey and input.KeyCode==rotateKey then
		local shift=UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
		startPlacementHold(shift and "RotateRight" or "RotateLeft",input.KeyCode)
	elseif scaleKey and input.KeyCode==scaleKey then
		local shift=UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
		startPlacementHold(shift and "ScaleDown" or "ScaleUp",input.KeyCode)
	elseif input.KeyCode==Enum.KeyCode.X then
		placementRotationY=0
		placementScale=Vector3.new(1,1,1)
	end
end)

UIS.InputEnded:Connect(function(input)
	placementHeld[input.KeyCode]=nil
end)

-- If placement mode ends while a key is held, cancel all repeat loops.
RunService.RenderStepped:Connect(function()
	if mode~="Place" or testing then
		table.clear(placementHeld)
	end
end)

preLeft.MouseButton1Click:Connect(function() placementRotationY-=1 end)
preRight.MouseButton1Click:Connect(function() placementRotationY+=1 end)
preGrow.MouseButton1Click:Connect(function()
	placementScale=Vector3.new(
		math.min(3,placementScale.X+.25),
		math.min(3,placementScale.Y+.25),
		math.min(3,placementScale.Z+.25)
	)
end)
preShrink.MouseButton1Click:Connect(function()
	placementScale=Vector3.new(
		math.max(.5,placementScale.X-.25),
		math.max(.5,placementScale.Y-.25),
		math.max(.5,placementScale.Z-.25)
	)
end)
preReset.MouseButton1Click:Connect(function()
	placementRotationY=0
	placementScale=Vector3.new(1,1,1)
end)

RunService.RenderStepped:Connect(function()
	if mode=="Place" and previewPart and previewPart.Parent and previewPosition then
		local camera=workspace.CurrentCamera
		if camera then
			local world=previewPart.Position+Vector3.new(0,previewPart.Size.Y/2+3,0)
			local pos,onScreen=camera:WorldToViewportPoint(world)
			-- Floating pre-placement toolbar removed.
			-- Use the permanent bottom HUD / keyboard bindings instead.
			placeTransform.Visible=false
		end
	else
		placeTransform.Visible=false
	end
end)

-- 3D HOVER LABELS FOR PLACED BLOCKS
-- Reuses ONE BillboardGui instead of destroying/recreating it every frame.
-- This prevents flicker/glitching when the mouse crosses edges of the same object.
local hoverBillboard=Instance.new("BillboardGui")
hoverBillboard.Name="BlockHoverLabel"
hoverBillboard.Size=UDim2.fromOffset(160,44)
hoverBillboard.AlwaysOnTop=true
hoverBillboard.MaxDistance=80
hoverBillboard.Enabled=false
hoverBillboard.Parent=gui

local hoverLabel=Instance.new("TextLabel")
hoverLabel.Size=UDim2.fromScale(1,1)
hoverLabel.BackgroundColor3=Color3.fromRGB(15,25,38)
hoverLabel.BackgroundTransparency=.08
hoverLabel.BorderSizePixel=0
hoverLabel.Font=Enum.Font.GothamBlack
hoverLabel.TextSize=14
hoverLabel.TextColor3=Color3.new(1,1,1)
hoverLabel.TextStrokeColor3=Color3.fromRGB(35,145,220)
hoverLabel.TextStrokeTransparency=.55
hoverLabel.Parent=hoverBillboard
local hoverCorner=Instance.new("UICorner")
hoverCorner.CornerRadius=UDim.new(0,9)
hoverCorner.Parent=hoverLabel
local hoverStroke=Instance.new("UIStroke")
hoverStroke.Color=Color3.fromRGB(75,190,245)
hoverStroke.Transparency=.18
hoverStroke.Thickness=1.5
hoverStroke.Parent=hoverLabel

local hoverAdornee=nil
local hoverLostAt=0
local HOVER_GRACE=.08

local function removeHoverLabel(force)
	if not force and hoverAdornee and os.clock()-hoverLostAt<HOVER_GRACE then return end
	hoverBillboard.Enabled=false
	hoverBillboard.Adornee=nil
	hoverAdornee=nil
end

local function getBlockType(part)
	if not part or not part:IsA("BasePart") then return nil end
	if part.Name=="PlacementPreview"
		or part.Name=="MoveDestinationPreview"
		or part.Name=="ClickTarget"
		or part.Name=="Arc"
		or part.Name=="ArrowHead" then
		return nil
	end

	local t=part:GetAttribute("Type")
	if type(t)=="string" and t~="" then return t end

	local known={
		Platform="Platform",
		KillBlock="Kill Block",
		BouncePad="Bounce Pad",
		SpeedPad="Speed Pad",
		Checkpoint="Checkpoint",
		Start="Start",
		Finish="Finish",
		CreatorSpawn="Creator Spawn",
		SpawnPoint="Creator Spawn"
	}
	if known[part.Name] then return known[part.Name] end

	local parent=part.Parent
	if parent and (parent.Name=="CreatorSpawn" or parent.Name=="SpawnPoint") then
		return "Creator Spawn"
	end
	return nil
end

local function showHoverLabel(part,blockType)
	if hoverAdornee~=part then
		hoverAdornee=part
		hoverBillboard.Adornee=part
	end
	hoverBillboard.StudsOffset=Vector3.new(0,part.Size.Y/2+1.8,0)
	hoverLabel.Text=blockType
	hoverBillboard.Enabled=true
end

RunService.RenderStepped:Connect(function()
	-- Hide hover labels globally only during active Move/Rotate gizmos.
	-- In SELECT mode, other objects should still show their names.
	if not gui.Enabled
		or testing
		or mode=="Move"
		or mode=="Rotate"
		or rotateTarget~=nil
		or moveGhost~=nil then
		removeHoverLabel(true)
		return
	end

	local hit=raycastMouse()
	local part=hit and hit.Instance or nil

	-- The selected object already has a highlight + transformation palette,
	-- so suppress only THAT object's normal hover name.
	if selectedObject and part==selectedObject then
		removeHoverLabel(true)
		return
	end

	local blockType=getBlockType(part)

	if part and blockType then
		local owner=part:GetAttribute("Owner")
		local isCreatorSpawn=(blockType=="Creator Spawn")
		if isCreatorSpawn or owner==nil or owner==editableOwnerUserId() then
			hoverLostAt=os.clock()
			showHoverLabel(part,blockType)
			return
		end
	end

	-- Small grace period stops edge-of-part raycast jitter from flashing the label.
	if hoverBillboard.Enabled then
		if hoverLostAt==0 then hoverLostAt=os.clock() end
		if os.clock()-hoverLostAt>=HOVER_GRACE then
			removeHoverLabel(true)
			hoverLostAt=0
		end
	end
end)

-- CENTER-BOTTOM TRANSFORMATION DOCK (SAFE VERSION)
local transformDock=Instance.new("Frame")
transformDock.Name="TransformDock"
transformDock.Size=UDim2.fromOffset(580,120)
transformDock.AnchorPoint=Vector2.new(.5,1)
transformDock.Position=UDim2.new(.5,0,1,-22)
transformDock.BackgroundColor3=Color3.fromRGB(7,22,38)
transformDock.BackgroundTransparency=.04
transformDock.BorderSizePixel=0
transformDock.Visible=false
transformDock.ZIndex=170
transformDock.Parent=gui
corner(transformDock,14)
local ds=Instance.new("UIStroke");ds.Color=Color3.fromRGB(25,170,255);ds.Thickness=2.5;ds.Transparency=.02;ds.Parent=transformDock

local dl=Instance.new("UIListLayout")
dl.FillDirection=Enum.FillDirection.Horizontal
dl.HorizontalAlignment=Enum.HorizontalAlignment.Center
dl.VerticalAlignment=Enum.VerticalAlignment.Center
dl.Padding=UDim.new(0,8)
dl.Parent=transformDock

local function dockButton(name,iconText,keyText,danger)
	local b=Instance.new("TextButton")
	b.Name=name.."Dock"
	b.Size=UDim2.fromOffset(132,96)
	b.BackgroundColor3=danger and Color3.fromRGB(67,24,35) or Color3.fromRGB(12,38,59)
	b.BackgroundTransparency=.02
	b.BorderSizePixel=0
	b.Text=""
	b.AutoButtonColor=true
	b.ZIndex=172
	b.Parent=transformDock
	corner(b,12)

	local st=Instance.new("UIStroke")
	st.Color=danger and Color3.fromRGB(255,52,84) or Color3.fromRGB(25,151,225)
	st.Thickness=1.5
	st.Transparency=.18
	st.Parent=b

	-- Icon area
	local icon=Instance.new("Frame")
	icon.Name="DockIcon"
	icon.Size=UDim2.fromOffset(64,48)
	icon.Position=UDim2.new(.5,-32,0,4)
	icon.BackgroundTransparency=1
	icon.ZIndex=173
	icon.Parent=b

	if name=="DELETE" then
		local image=Instance.new("ImageLabel")
		image.Name="DeleteIconImage"
		image.Size=UDim2.fromOffset(48,48)
		image.AnchorPoint=Vector2.new(.5,.5)
		image.Position=UDim2.fromScale(.5,.5)
		image.BackgroundTransparency=1
		image.Image="rbxassetid://98830002732455"
		image.ScaleType=Enum.ScaleType.Fit
		image.ZIndex=174
		image.Parent=icon
	elseif name=="MOVE" then
		local image=Instance.new("ImageLabel")
		image.Name="MoveIconImage"
		image.Size=UDim2.fromOffset(52,52)
		image.AnchorPoint=Vector2.new(.5,.5)
		image.Position=UDim2.fromScale(.5,.5)
		image.BackgroundTransparency=1
		image.Image="rbxassetid://129619297738123"
		image.ScaleType=Enum.ScaleType.Fit
		image.ZIndex=174
		image.Parent=icon
	elseif name=="ROTATE" then
		local image=Instance.new("ImageLabel")
		image.Name="RotateIconImage"
		image.Size=UDim2.fromOffset(52,52)
		image.AnchorPoint=Vector2.new(.5,.5)
		image.Position=UDim2.fromScale(.5,.5)
		image.BackgroundTransparency=1
		image.Image="rbxassetid://96105510356146"
		image.ScaleType=Enum.ScaleType.Fit
		image.ZIndex=174
		image.Parent=icon
	elseif name=="SCALE" then
		local image=Instance.new("ImageLabel")
		image.Name="ScaleIconImage"
		image.Size=UDim2.fromOffset(52,52)
		image.AnchorPoint=Vector2.new(.5,.5)
		image.Position=UDim2.fromScale(.5,.5)
		image.BackgroundTransparency=1
		image.Image="rbxassetid://111617531686528"
		image.ScaleType=Enum.ScaleType.Fit
		image.ZIndex=174
		image.Parent=icon
	end

	local label=Instance.new("TextLabel")
	label.Name="DockLabel"
	label.Size=UDim2.new(1,-8,0,38)
	label.Position=UDim2.new(0,4,1,-41)
	label.BackgroundTransparency=1
	label.Text=name.."\n["..keyText.."]"
	label.Font=Enum.Font.GothamBlack
	label.TextSize=12
	label.TextColor3=Color3.fromRGB(245,250,255)
	label.TextStrokeTransparency=.78
	label.ZIndex=173
	label.Parent=b

	return b
end

local dockMove=dockButton("MOVE","✥",prettyBinding("Move","G"),false)
local dockRotate=dockButton("ROTATE","⟳",prettyBinding("Rotate","E"),false)
local dockScale=dockButton("SCALE","◆",prettyBinding("Scale","R"),false)
local dockDelete=dockButton("DELETE","▥","DEL",true)

local function refreshDock()
	dockMove.DockLabel.Text="MOVE\n["..prettyBinding("Move","G").."]"
	dockRotate.DockLabel.Text="ROTATE\n["..prettyBinding("Rotate","E").."  SHIFT+"..prettyBinding("Rotate","E").."]"
	dockScale.DockLabel.Text="SCALE\n["..prettyBinding("Scale","R").."  SHIFT+"..prettyBinding("Scale","R").."]"
	dockDelete.DockLabel.Text="DELETE\n["..prettyBinding("Delete","Delete").."]"
end
for _,a in ipairs({"Move","Rotate","Scale","Delete"}) do
	playerGui:GetAttributeChangedSignal("ParkourBind_"..a):Connect(refreshDock)
end

refreshDock()
keybindEvent.Event:Connect(function(action)
	if action=="BindingsChanged" then refreshDock() end
end)

-- Only show the dock AFTER an object is selected.
-- This avoids introducing any new transformation state machine.
RunService.RenderStepped:Connect(function()
	-- Keep the transformation HUD permanently visible in Build Mode.
	transformDock.Visible=gui.Enabled and not testing
	if transformDock.Visible then
		transformDock.BackgroundTransparency=.02
	end

	-- HUD ACTIVE STATE:
	-- White text when an existing object is selected OR a new object is being previewed.
	-- Grey text only when there is nothing currently transformable.
	for _,button in ipairs({dockMove,dockRotate,dockScale,dockDelete}) do
		button.BackgroundTransparency=.02
		if button:FindFirstChild("DockIcon") then button.DockIcon.Visible=true end

		if (mode=="Select" and selectedObject and selectedObject.Parent)
			or (mode=="Place" and previewPart and previewPart.Parent) then
			button.AutoButtonColor=true
			if button:FindFirstChild("DockLabel") then
				button.DockLabel.TextTransparency=0
				button.DockLabel.TextColor3=Color3.new(1,1,1)
			end
		else
			button.AutoButtonColor=false
			if button:FindFirstChild("DockLabel") then
				button.DockLabel.TextTransparency=.35
				button.DockLabel.TextColor3=Color3.fromRGB(165,175,190)
			end
		end
	end
end)

-- Reuse the already-working selected-object transformation callbacks.
dockMove.MouseButton1Click:Connect(function()
	if selectMove and selectedObject and selectedObject.Parent then
		do
			local obj=selectedObject
			hideSelectionPalette()
			clearRotateVisuals()
			mode="Move"
			selectedObject=obj
			makeMoveGhost(obj)
			updateStatus("MOVE • preview destination, click to confirm")
		end
	end
end)
dockRotate.MouseButton1Click:Connect(function()
	if selectRotate and selectedObject and selectedObject.Parent then
		do
			local obj=selectedObject
			hideSelectionPalette()
			clearMoveVisuals()
			mode="Rotate"
			selectedObject=obj
			showRotateControls(obj)
			updateStatus("ROTATE • use the -1° / +1° arrows")
		end
	end
end)
dockScale.MouseButton1Click:Connect(function()
	if selectScaleUp and selectedObject and selectedObject.Parent then
		showScalePreview(selectedObject,1)
	end
end)
dockDelete.MouseButton1Click:Connect(function()
	if selectDelete and selectedObject and selectedObject.Parent then
		do
			remote:FireServer("Delete",selectedObject)
			clearSelection()
			mode="Select"
			updateStatus("SELECT • click one of your objects")
		end
	end
end)

-- SAVE STATUS + STRONG COOLDOWN TIMER
local SAVE_INTERVAL=5
local saveReadyAt=0

local saveNotice=Instance.new("Frame")
saveNotice.Name="SaveNotice"
saveNotice.Size=UDim2.fromOffset(210,58)
saveNotice.Position=UDim2.new(1,-228,1,-78)
saveNotice.BackgroundColor3=Color3.fromRGB(10,27,43)
saveNotice.BackgroundTransparency=.04
saveNotice.BorderSizePixel=0
saveNotice.Visible=false
saveNotice.ZIndex=160
saveNotice.Parent=gui
corner(saveNotice,11)
local sns=Instance.new("UIStroke")
sns.Color=Color3.fromRGB(65,205,255);sns.Thickness=2;sns.Transparency=.08;sns.Parent=saveNotice

local saveNoticeText=Instance.new("TextLabel")
saveNoticeText.Size=UDim2.fromScale(1,1)
saveNoticeText.BackgroundTransparency=1
saveNoticeText.Text="SAVING..."
saveNoticeText.Font=Enum.Font.GothamBlack
saveNoticeText.TextSize=18
saveNoticeText.TextColor3=Color3.fromRGB(200,245,255)
saveNoticeText.TextStrokeColor3=Color3.fromRGB(30,140,220)
saveNoticeText.TextStrokeTransparency=.45
saveNoticeText.ZIndex=161
saveNoticeText.Parent=saveNotice

local saveTimer=Instance.new("TextLabel")
saveTimer.Name="SaveIntervalTimer"
saveTimer.Size=UDim2.fromOffset(190,30)
saveTimer.Position=UDim2.new(1,-208,0,200)
saveTimer.BackgroundColor3=Color3.fromRGB(10,27,43)
saveTimer.BackgroundTransparency=.06
saveTimer.BorderSizePixel=0
saveTimer.Text="SAVE READY"
saveTimer.Font=Enum.Font.GothamBlack
saveTimer.TextSize=14
saveTimer.TextColor3=Color3.fromRGB(125,230,175)
saveTimer.ZIndex=150
saveTimer.Parent=gui
saveTimer.Visible=false -- persistent SAVE READY indicator removed
corner(saveTimer,9)
local sts=Instance.new("UIStroke")
sts.Color=Color3.fromRGB(70,190,240);sts.Thickness=1.5;sts.Transparency=.18;sts.Parent=saveTimer

RunService.RenderStepped:Connect(function()
	if not gui.Enabled then return end
	local remaining=math.max(0,saveReadyAt-os.clock())
	if remaining>0 then
		saveTimer.Text=string.format("SAVE IN %.1fs",remaining)
		saveTimer.TextColor3=Color3.fromRGB(255,205,105)
	else
		saveTimer.Text="SAVE READY"
		saveTimer.TextColor3=Color3.fromRGB(125,230,175)
	end
end)

local function showSavingNotice()
	saveNotice.Visible=true
	saveNoticeText.Text="SAVING..."
	saveNoticeText.TextSize=18
end

local function showSavedNotice(count)
	saveNotice.Visible=true
	saveNoticeText.Text="✓ SAVED"..(count and (" • "..tostring(count).." OBJECTS") or "")
	saveNoticeText.TextSize=14
	task.delay(1.8,function()
		if saveNotice then saveNotice.Visible=false end
	end)
end

-- TEST MODE TIMER HUD
local testTimer=Instance.new("Frame")
testTimer.Name="TestTimer"
testTimer.Size=UDim2.fromOffset(250,70)
testTimer.Position=UDim2.new(.5,-125,0,245)
testTimer.BackgroundColor3=Color3.fromRGB(17,28,41)
testTimer.BackgroundTransparency=.06
testTimer.BorderSizePixel=0
testTimer.Visible=false
testTimer.ZIndex=70
testTimer.Parent=gui
corner(testTimer,12)
stroke(testTimer,Color3.fromRGB(60,205,255))

local testTimerTitle=Instance.new("TextLabel")
testTimerTitle.Size=UDim2.new(1,0,0,22)
testTimerTitle.Position=UDim2.fromOffset(0,7)
testTimerTitle.BackgroundTransparency=1
testTimerTitle.Text="TEST RUN"
testTimerTitle.Font=Enum.Font.GothamBlack
testTimerTitle.TextSize=11
testTimerTitle.TextColor3=Color3.fromRGB(125,205,245)
testTimerTitle.ZIndex=71
testTimerTitle.Parent=testTimer

local testTimerValue=Instance.new("TextLabel")
testTimerValue.Size=UDim2.new(1,0,0,35)
testTimerValue.Position=UDim2.fromOffset(0,27)
testTimerValue.BackgroundTransparency=1
testTimerValue.Text="0.00s"
testTimerValue.Font=Enum.Font.GothamBlack
testTimerValue.TextSize=25
testTimerValue.TextColor3=Color3.new(1,1,1)
testTimerValue.ZIndex=71
testTimerValue.Parent=testTimer

local testTimerStarted=nil
local testTimerConnection=nil

local function startTestTimer()
	testTimerStarted=os.clock()
	testTimer.Visible=true
	testTimerValue.Text="0.00s"
	if testTimerConnection then testTimerConnection:Disconnect() end
	testTimerConnection=RunService.RenderStepped:Connect(function()
		if testing and testTimerStarted then
			testTimerValue.Text=string.format("%.2fs",os.clock()-testTimerStarted)
		end
	end)
end

local function stopTestTimer(finalTime)
	if testTimerConnection then testTimerConnection:Disconnect();testTimerConnection=nil end
	testTimerStarted=nil
	if finalTime then
		testTimerValue.Text=string.format("%.2fs",tonumber(finalTime) or 0)
		task.delay(.75,function()
			if not testing then testTimer.Visible=false end
		end)
	else
		testTimer.Visible=false
	end
end

-- CONFIGURABLE KEYBOARD SHORTCUTS
local typeActions={
	Platform="Platform",KillBlock="KillBlock",BouncePad="BouncePad",
	SpeedPad="SpeedPad",Checkpoint="Checkpoint",Start="Start",Finish="Finish"
}

local function matches(input,action)
	local wanted=Enum.KeyCode[keyName(action)]
	return wanted and input.KeyCode==wanted
end

UIS.InputBegan:Connect(function(input,processed)
	if processed or not gui.Enabled then return end
	if UIS:GetFocusedTextBox() then return end

	-- Deselect / cancel the current transformation.
	-- ESC or right-click returns cleanly to SELECT mode.
	if matches(input,"CancelTransform") then
		-- Cancel any active transform or unplaced object preview and return to Select.
		if mode=="Place" and previewPart and previewPart.Parent then
			destroyPreview()
			previewPosition=nil
			placementRotationY=0
			placementScale=Vector3.new(1,1,1)
			table.clear(placementHeld)
			if placeTransform then placeTransform.Visible=false end
		end
		clearAdvancedToolVisuals()
		clearSelection()
		mode="Select"
		updateStatus("SELECT • transformation cancelled")
		return
	end

	-- WASD are reserved for character movement and must never change builder tools.
	if input.KeyCode==Enum.KeyCode.W
		or input.KeyCode==Enum.KeyCode.A
		or input.KeyCode==Enum.KeyCode.S
		or input.KeyCode==Enum.KeyCode.D then
		return
	end

	-- Transformation shortcuts work on the CURRENTLY SELECTED object.
	-- They do nothing when no object is selected, preserving the select-first policy.
	if matches(input,"Move") then
		if selectedObject and selectedObject.Parent and mode=="Select" then
			do
				local obj=selectedObject
				hideSelectionPalette()
				clearRotateVisuals()
				mode="Move"
				selectedObject=obj
				makeMoveGhost(obj)
				updateStatus("MOVE • preview destination, click to confirm")
			end
		end
		return
	elseif matches(input,"Rotate") then
		if selectedObject and selectedObject.Parent and mode=="Select" then
			do
				local obj=selectedObject
				hideSelectionPalette()
				clearMoveVisuals()
				mode="Rotate"
				selectedObject=obj
				showRotateControls(obj)
				updateStatus("ROTATE • use the -1° / +1° arrows")
			end
		end
		return
	elseif matches(input,"Scale") then
		if selectedObject and selectedObject.Parent and mode=="Select" then
			local shift=UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
			showScalePreview(selectedObject,shift and -1 or 1)
		end
		return
	elseif matches(input,"Test") then remote:FireServer("Test")
	else
		for action,t in pairs(typeActions) do
			if matches(input,action) then
				clearAdvancedToolVisuals()
				selectedObject=nil
				selectedType=t
				mode="Place"
				updateStatus("PLACE - "..t.."\\nClick where you want to place it")
				break
			end
		end
	end

	if matches(input,"ConfirmTransform") then
		-- MOVE: confirm the current destination preview.
		-- moveTarget is declared later in this large script, so do NOT reference
		-- it from this earlier keyboard callback. Read the visible move preview
		-- directly instead.
		if mode=="Move" and selectedObject and selectedObject.Parent then
			local movePreview=workspace:FindFirstChild("MoveDestinationPreview")
			if movePreview and movePreview:IsA("BasePart") then
				remote:FireServer("Move",selectedObject,movePreview.Position)
				selectedObject=nil
				clearMoveVisuals()
				mode="Select"
				updateStatus("SELECT • move confirmed")
				return
			end
		end

		-- PLACE: confirm the current new-object preview.
		if mode=="Place" and previewPosition then
			remote:FireServer("Place",previewPosition,{
				type=selectedType,
				rotationY=placementRotationY,
				scale={placementScale.X,placementScale.Y,placementScale.Z}
			})
			mode="Select"
			selectedObject=nil
			previewPosition=nil
			placementRotationY=0
			placementScale=Vector3.new(1,1,1)
			table.clear(placementHeld)
			destroyPreview()
			if placeTransform then placeTransform.Visible=false end
			updateStatus("SELECT • placement confirmed")
			return
		end
	end

	if matches(input,"Delete") then
		-- If a NEW object is only being previewed, Delete cancels it locally.
		-- Nothing has reached the server yet, so do not fire the normal Delete action.
		if mode=="Place" and previewPart and previewPart.Parent then
			destroyPreview()
			previewPosition=nil
			placementRotationY=0
			placementScale=Vector3.new(1,1,1)
			table.clear(placementHeld)
			if placeTransform then placeTransform.Visible=false end
			selectedObject=nil
			mode="Select"
			updateStatus("SELECT • preview cancelled")
			return
		end

		-- Existing placed object behavior stays unchanged.
		if selectedObject and selectedObject.Parent and mode=="Select" then
			remote:FireServer("Delete",selectedObject)
			clearSelection()
			mode="Select"
			updateStatus("SELECT • click one of your objects")
		end
		return
	elseif UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl) then
		if input.KeyCode==Enum.KeyCode.Z then remote:FireServer("Undo")
		elseif input.KeyCode==Enum.KeyCode.Y then remote:FireServer("Redo") end
	end
end)

-- SCALE PREVIEW
-- Same visual language as ROTATE: shiny floating title, left/right controls,
-- camera-facing presentation, and slow floating animation.
local scaleAnimationConnection=nil
local scaleUiFolder=nil

clearScalePreview=function()
	if scaleGhost then sendSharedPreview("Hide") end
	if scaleAnimationConnection then
		scaleAnimationConnection:Disconnect()
		scaleAnimationConnection=nil
	end
	if scaleGhost then scaleGhost:Destroy() end
	if scaleBillboard then scaleBillboard:Destroy() end
	if scaleUiFolder then scaleUiFolder:Destroy() end
	scaleGhost=nil
	scaleBillboard=nil
	scaleUiFolder=nil
	scaleSource=nil
	scaleDirection=nil
end

local function makeScaleShinyLabel(parent,name,text,width)
	-- Legacy Scale 3D text UI removed.
	return nil,nil,nil
end

showScalePreview=function(source,direction)
	clearScalePreview()
	if not source or not source.Parent then return end

	selectionUiSuspended=true
	selectionGui.Visible=false
	scaleSource=source
	scaleDirection=direction

	local targetSize=source.Size+Vector3.new(direction*2,direction,direction*2)
	targetSize=Vector3.new(
		math.max(1,targetSize.X),
		math.max(.5,targetSize.Y),
		math.max(1,targetSize.Z)
	)

	-- Preview only: no floating SCALE PREVIEW text, size text, APPLY, or CANCEL UI.
	scaleGhost=source:Clone()
	scaleGhost.Name="ScalePreview"
	scaleGhost.Size=targetSize

	local bottomY=source.Position.Y-source.Size.Y/2
	scaleGhost.CFrame=CFrame.new(
		source.Position.X,
		bottomY+targetSize.Y/2,
		source.Position.Z
	)*source.CFrame.Rotation

	scaleGhost.Transparency=.55
	scaleGhost.Material=Enum.Material.Neon
	scaleGhost.Color=Color3.fromRGB(75,205,255)
	scaleGhost.CanCollide=false
	scaleGhost.CanTouch=false
	scaleGhost.CanQuery=false
	scaleGhost.Anchored=true
	scaleGhost.Parent=workspace

	sendSharedPreview("Update",{
		Kind="Scale",
		Type=tostring(source:GetAttribute("Type") or source.Name),
		CFrame=scaleGhost.CFrame,
		Size=scaleGhost.Size,
		Color=scaleGhost.Color,
	})

	-- Apply immediately through the existing server Scale action.
	-- The server remains authoritative and Undo still works.
	remote:FireServer("Scale",source,direction)

	-- Keep the selected real object active, then remove the temporary ghost shortly
	-- after the server has applied the scale.
	task.delay(.12,function()
		clearScalePreview()
		selectionUiSuspended=false
		if selectedObject and selectedObject.Parent then
			selectHighlight.Adornee=selectedObject
			selectHighlight.Enabled=true
		end
	end)
end

-- MOVE DESTINATION PREVIEW + ROTATE ARROWS
local transformState={
	moveGhost=nil,
	moveTarget=nil,
	moveSource=nil,
	moveBillboard=nil,
	rotateGui=nil,
	rotateTarget=nil,
	scaleGhost=nil,
	scaleSource=nil,
	scaleDirection=nil,
	scaleBillboard=nil,
	rotateButtonBusy=false,
	rotateAnimationConnection=nil,
}

clearMoveVisuals=function()
	if transformState.moveGhost then sendSharedPreview("Hide") end
	if transformState.moveGhost then transformState.moveGhost:Destroy() end
	if transformState.moveBillboard then transformState.moveBillboard:Destroy() end
	transformState.moveGhost=nil;transformState.moveBillboard=nil;transformState.moveTarget=nil;transformState.moveSource=nil
end
clearRotateVisuals=function()
	if transformState.rotateGui then sendSharedPreview("Hide") end
	if transformState.rotateAnimationConnection then
		transformState.rotateAnimationConnection:Disconnect()
		transformState.rotateAnimationConnection=nil
	end
	if transformState.rotateTarget and transformState.rotateTarget.Parent then transformState.rotateTarget.LocalTransparencyModifier=0 end
	if transformState.rotateGui then transformState.rotateGui:Destroy() end
	transformState.rotateGui=nil
	transformState.rotateTarget=nil
end
clearAdvancedToolVisuals=function()
	clearMoveVisuals()
	clearRotateVisuals()
	clearScalePreview()
end

makeMoveGhost=function(source)
	clearMoveVisuals();transformState.moveSource=source
	transformState.moveGhost=source:Clone()
	transformState.moveGhost.Name="MoveDestinationPreview"
	transformState.moveGhost.Transparency=.55;transformState.moveGhost.Material=Enum.Material.Neon
	transformState.moveGhost.CanCollide=false;transformState.moveGhost.CanTouch=false;transformState.moveGhost.CanQuery=false
	transformState.moveGhost.Anchored=true;transformState.moveGhost.Parent=workspace

	transformState.moveBillboard=Instance.new("BillboardGui")
	transformState.moveBillboard.Adornee=transformState.moveGhost;transformState.moveBillboard.Size=UDim2.fromOffset(190,54)
	transformState.moveBillboard.StudsOffset=Vector3.new(0,transformState.moveGhost.Size.Y/2+2.2,0)
	transformState.moveBillboard.AlwaysOnTop=true;transformState.moveBillboard.Parent=gui
	local t=Instance.new("TextLabel");t.Name="Text";t.Size=UDim2.fromScale(1,1)
	t.BackgroundColor3=Color3.fromRGB(12,28,44);t.BackgroundTransparency=.08;t.BorderSizePixel=0
	t.Font=Enum.Font.GothamBlack;t.TextSize=13;t.TextColor3=Color3.fromRGB(105,215,255);t.Parent=transformState.moveBillboard
	local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,9);c.Parent=t
end

local function updateMoveGhost()
	if mode~="Move" or not transformState.moveSource or not transformState.moveGhost then return end
	local hit=raycastMouse();if not hit then return end
	local raw=Vector3.new(hit.Position.X,hit.Position.Y+transformState.moveSource.Size.Y/2,hit.Position.Z)
	transformState.moveTarget=clampToPlot(raw,transformState.moveSource.Size)
	transformState.moveGhost.CFrame=CFrame.new(transformState.moveTarget)*transformState.moveSource.CFrame.Rotation

	if os.clock()-lastSharedPreviewSend>=SHARED_PREVIEW_RATE then
		lastSharedPreviewSend=os.clock()
		sendSharedPreview("Update",{
			Kind="Move",
			Type=tostring(transformState.moveSource:GetAttribute("Type") or transformState.moveSource.Name),
			CFrame=transformState.moveGhost.CFrame,
			Size=transformState.moveGhost.Size,
			Color=transformState.moveGhost.Color,
		})
	end

	local t=transformState.moveBillboard and transformState.moveBillboard:FindFirstChild("Text")
	if t then t.Text=string.format("MOVE TO\nX %.0f  Y %.0f  Z %.0f",transformState.moveTarget.X,transformState.moveTarget.Y,transformState.moveTarget.Z) end
end

showRotateControls=function(part)
	clearRotateVisuals()
	if not part or not part.Parent then return end
	transformState.rotateTarget=part
	transformState.rotateGui=part:Clone()
	transformState.rotateGui.Name="RotatePreview"
	transformState.rotateGui.Anchored=true
	transformState.rotateGui.CanCollide=false
	transformState.rotateGui.CanTouch=false
	transformState.rotateGui.CanQuery=false
	transformState.rotateGui.Transparency=.45
	transformState.rotateGui.Material=Enum.Material.Neon
	transformState.rotateGui.CFrame=part.CFrame
	transformState.rotateGui:SetAttribute("PreviewDegrees",0)
	transformState.rotateGui.Parent=workspace
	part.LocalTransparencyModifier=.55

	sendSharedPreview("Update",{
		Kind="Rotate",
		Type=tostring(part:GetAttribute("Type") or part.Name),
		CFrame=transformState.rotateGui.CFrame,
		Size=transformState.rotateGui.Size,
		Color=transformState.rotateGui.Color,
	})
	updateStatus("ROTATE PREVIEW • rotate key ±1° • ENTER apply • ESC cancel")
end

-- Dedicated rotation-preview key listener.
-- Tap = precise 1° step. Hold = rapid continuous preview rotation.
-- Uses attributes on transformState.rotateGui instead of extra top-level state locals.
UIS.InputBegan:Connect(function(input,processed)
	if processed or not gui.Enabled or testing or mode~="Rotate" then return end
	if UIS:GetFocusedTextBox() then return end
	if not transformState.rotateTarget or not transformState.rotateTarget.Parent or not transformState.rotateGui then return end

	if input.KeyCode==Enum.KeyCode[keyName("Rotate")] then
		if transformState.rotateGui:GetAttribute("RotateKeyHeld") then return end

		transformState.rotateGui:SetAttribute("RotateKeyHeld",true)
		transformState.rotateGui:SetAttribute(
			"RotateDirection",
			(UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)) and 1 or -1
		)

		-- Immediate 1° step for a normal tap.
		transformState.rotateGui:SetAttribute(
			"PreviewDegrees",
			(transformState.rotateGui:GetAttribute("PreviewDegrees") or 0)
				+(transformState.rotateGui:GetAttribute("RotateDirection") or -1)
		)
		transformState.rotateGui.CFrame=transformState.rotateTarget.CFrame*CFrame.Angles(
			0,
			math.rad(transformState.rotateGui:GetAttribute("PreviewDegrees") or 0),
			0
		)

		if os.clock()-lastSharedPreviewSend>=SHARED_PREVIEW_RATE then
			lastSharedPreviewSend=os.clock()
			sendSharedPreview("Update",{
				Kind="Rotate",
				Type=tostring(transformState.rotateTarget:GetAttribute("Type") or transformState.rotateTarget.Name),
				CFrame=transformState.rotateGui.CFrame,
				Size=transformState.rotateGui.Size,
				Color=transformState.rotateGui.Color,
			})
		end

		-- After a short hold delay, rotate rapidly until the key is released.
		task.spawn(function()
			task.wait(.22)
			while transformState.rotateGui
				and transformState.rotateGui.Parent
				and transformState.rotateTarget
				and transformState.rotateTarget.Parent
				and mode=="Rotate"
				and transformState.rotateGui:GetAttribute("RotateKeyHeld") do

				transformState.rotateGui:SetAttribute(
					"PreviewDegrees",
					(transformState.rotateGui:GetAttribute("PreviewDegrees") or 0)
						+(transformState.rotateGui:GetAttribute("RotateDirection") or -1)
				)
				transformState.rotateGui.CFrame=transformState.rotateTarget.CFrame*CFrame.Angles(
					0,
					math.rad(transformState.rotateGui:GetAttribute("PreviewDegrees") or 0),
					0
				)

				if os.clock()-lastSharedPreviewSend>=SHARED_PREVIEW_RATE then
					lastSharedPreviewSend=os.clock()
					sendSharedPreview("Update",{
						Kind="Rotate",
						Type=tostring(transformState.rotateTarget:GetAttribute("Type") or transformState.rotateTarget.Name),
						CFrame=transformState.rotateGui.CFrame,
						Size=transformState.rotateGui.Size,
						Color=transformState.rotateGui.Color,
					})
				end

				task.wait(1/30)
			end
		end)

	elseif input.KeyCode==Enum.KeyCode[keyName("ConfirmTransform")] then
		-- Stop hold rotation before committing.
		transformState.rotateGui:SetAttribute("RotateKeyHeld",false)

		-- Server RotateBy accepts only +/-1 per request, so commit the complete
		-- preview angle one degree at a time instead of sending e.g. 37 and
		-- having the server clamp it to +1.
		local previewDegrees=math.round(transformState.rotateGui:GetAttribute("PreviewDegrees") or 0)
		local step=previewDegrees>=0 and 1 or -1
		for _=1,math.abs(previewDegrees) do
			remote:FireServer("RotateBy",transformState.rotateTarget,step)
		end

		clearRotateVisuals()
		clearSelection()
		mode="Select"
		updateStatus("SELECT • click one of your objects")
	end
end)

UIS.InputEnded:Connect(function(input)
	if transformState.rotateGui
		and transformState.rotateGui.Parent
		and input.KeyCode==Enum.KeyCode[keyName("Rotate")] then
		transformState.rotateGui:SetAttribute("RotateKeyHeld",false)
	end
end)


RunService.RenderStepped:Connect(function()
	if mode=="Place" then
		if transformState.moveGhost then clearMoveVisuals() end
		if transformState.rotateGui then clearRotateVisuals() end
		if transformState.scaleGhost then clearScalePreview() end
		if selectHighlight and selectHighlight.Enabled then
			selectHighlight.Adornee=nil
			selectHighlight.Enabled=false
			if selectionGui then selectionGui.Visible=false end
		end
	end
	if mode~="Move" and transformState.moveGhost then
		clearMoveVisuals()
	elseif mode=="Move" then
		updateMoveGhost()
	end
	if mode~="Rotate" and transformState.rotateGui then
		clearRotateVisuals()
	end
end)

RunService.RenderStepped:Connect(function()
	if selectHighlight.Enabled then
		if not selectedObject or not selectedObject.Parent then
			clearSelection()
		end
	end
end)

-- World interaction
UIS.InputBegan:Connect(function(input,processed)
	if processed or not gui.Enabled or testing then return end
	if input.UserInputType~=Enum.UserInputType.MouseButton1 then return end

	local hit=raycastMouse()
	if not hit then return end

	-- Transform modes may only be entered through the selected object's palette.
	if (mode=="Move" or mode=="Rotate" or mode=="Scale+" or mode=="Scale-" or mode=="Delete")
		and not selectedObject then
		mode="Select"
		updateStatus("SELECT • choose an object before transforming")
		return
	end

	if mode=="Select" then
		local o=ownedTarget(hit)
		if o then
			selectObject(o)
		elseif hit and hit.Instance and hit.Instance:IsA("BasePart")
			and hit.Instance:GetAttribute("Owner")==editableOwnerUserId() then
			clearSelection()
			updateStatus("TOO FAR • move closer to select this object")
		else
			clearSelection()
			updateStatus("SELECT • click one of your objects")
		end
	elseif mode=="Place" then
		if previewPosition then
			remote:FireServer("Place",previewPosition,{
				type=selectedType,
				rotationY=placementRotationY,
				scale={placementScale.X,placementScale.Y,placementScale.Z}
			})

			-- One placement per object selection.
			-- Immediately return to SELECT so another click cannot accidentally
			-- place a second copy of the same object.
			mode="Select"
			selectedObject=nil
			previewPosition=nil
			placementRotationY=0
			placementScale=Vector3.new(1,1,1)
			table.clear(placementHeld)
			destroyPreview()
			if placeTransform then placeTransform.Visible=false end
			updateStatus("SELECT • click one of your objects")
		end
	elseif mode=="Move" then
		if not selectedObject then
			selectedObject=ownedTarget(hit)
			if selectedObject then
				makeMoveGhost(selectedObject)
				updateStatus("MOVE • preview destination, click to confirm")
			end
		elseif transformState.moveTarget then
			remote:FireServer("Move",selectedObject,transformState.moveTarget)
			selectedObject=nil;clearMoveVisuals()
			updateStatus("MOVE • select another object")
		end
	elseif mode=="Rotate" then
		local o=ownedTarget(hit)
		if o then
			selectedObject=o
			showRotateControls(o)
			updateStatus("ROTATE • use left/right arrows")
		else
			clearAdvancedToolVisuals()
			clearSelection()
			mode="Select"
			updateStatus("SELECT • click one of your objects")
		end
	elseif mode=="Scale+" then
		local o=ownedTarget(hit);if o then remote:FireServer("Scale",o,1) end
	elseif mode=="Scale-" then
		local o=ownedTarget(hit);if o then remote:FireServer("Scale",o,-1) end
	elseif mode=="Delete" then
		local o=ownedTarget(hit);if o then remote:FireServer("Delete",o) end
	end
end)

remote.OnClientEvent:Connect(function(action,a,b,c)
	if action=="ClearPlotResult" then
		clearModal.Visible=false
		confirmClear.Active=true
		confirmClear.Text="CLEAR PLOT"
		selectedObject=nil
		destroyPreview()
		updateStatus("✓ PLOT CLEARED")
	elseif action=="Notice" then
		updateStatus(tostring(a))
	elseif action=="Saving" then
		updateStatus("SAVING...")
	elseif action=="DraftSaved" then
		updateStatus("✓ SAVED • "..tostring(a).." objects")
	elseif action=="DraftLoaded" then
		updateStatus("✓ LOADED • "..tostring(a).." objects")
	elseif action=="SaveCooldown" then
		updateStatus("WAIT "..string.format("%.1f",tonumber(a) or 0).."s BEFORE SAVING AGAIN")
	elseif action=="ValidationResult" then
		if a then
			updateStatus("✓ READY TO PUBLISH • "..tostring(c).." objects")
		else
			local problems=type(b)=="table" and table.concat(b,", ") or "Validation failed"
			updateStatus("⚠ "..problems)
		end
	elseif action=="PublishResult" then
		if a then
			publish.Visible=false
			updateStatus("✓ PUBLISHED • "..tostring(c or b))
		else
			updateStatus("⚠ "..tostring(b))
		end
	elseif action=="TestMode" then
		testing=a==true
		actionButtons["TEST"].Text=(testing and "EXIT TEST" or "TEST").."\n["..prettyBinding("Test","F").."]"

		-- Discover navigation is locked during an active test run.
		discover.Active=not testing
		discover.AutoButtonColor=not testing
		discover.BackgroundTransparency=testing and .55 or 0
		discover.TextTransparency=testing and .45 or 0
		if testing then
			discover.Text="🔒 RETURN"
		else
			refreshReturnButton()
		end

		if testing then
			startTestTimer()
			updateStatus("TEST MODE • reach FINISH")
		else
			stopTestTimer()
			mode="Select"
			selectedObject=nil
			updateStatus("SELECT • click one of your objects")
		end
	elseif action=="Finished" then
		testing=false
		actionButtons["TEST"].Text="TEST\n["..prettyBinding("Test","F").."]"
		discover.Active=true
		discover.AutoButtonColor=true
		discover.BackgroundTransparency=0
		discover.TextTransparency=0
		refreshReturnButton()
		stopTestTimer(a)
		updateStatus("✓ TEST COMPLETE • "..string.format("%.2fs",tonumber(a) or 0))
	elseif action=="VerificationChanged" then
		if a then updateStatus("✓ VERIFIED • "..string.format("%.2fs",tonumber(b) or 0)) end
	end
end)



-- Every time Build Mode opens, re-read the player's saved configuration.
gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then
		task.spawn(function()
			pullAuthoritativeBindings()
			task.wait()
			refreshObjectButtonKeys()
			task.wait(.15)
			refreshObjectButtonKeys()
		end)
	end
end)

print("✓ ParkourBuilderClient V2.3 strict positive permission UI loaded")

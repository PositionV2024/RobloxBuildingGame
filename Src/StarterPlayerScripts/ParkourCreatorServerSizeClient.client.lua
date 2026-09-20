-- ParkourCreatorServerSizeClient V1.2 - LIVE COUNT + OUTLINED PLAYER ICON
-- REPLACE the existing LocalScript: StarterPlayer > StarterPlayerScripts > ParkourCreatorServerSizeClient
-- Navy/cyan SERVER SIZE UI. Does not enable/disable BuilderUI or change roles/saves.
-- The owner selects TOTAL players, including themselves.
-- Button: SERVER SIZE with admitted players / server-confirmed limit.
-- Slider changes are pending until APPLY succeeds; they do not change the badge.
-- Reuses ParkourCreatorCapacity V1.1; no new RemoteEvents or database writes.
-- Icon uses native UI shapes; no images, asset IDs, or emoji fonts required.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local remote = RS:WaitForChild("ParkourCreatorServerSizeEvent", 15)
if not remote or not remote:IsA("RemoteEvent") then
	warn("[SERVER SIZE UI] Install ParkourCreatorCapacity ModuleScript and both replacement server scripts.")
	return
end

local old = pg:FindFirstChild("ParkourCreatorServerSizeUI")
if old then old:Destroy() end

local COLORS = {
	Navy = Color3.fromRGB(7,25,40),
	Panel = Color3.fromRGB(15,40,59),
	Cyan = Color3.fromRGB(55,195,255),
	Blue = Color3.fromRGB(20,145,225),
	White = Color3.fromRGB(242,249,255),
	Muted = Color3.fromRGB(150,192,216),
	Gray = Color3.fromRGB(55,66,78),
	Error = Color3.fromRGB(255,170,160),
}
local function make(className, properties, parent)
	local object = Instance.new(className)
	for key,value in pairs(properties) do object[key] = value end
	object.Parent = parent
	return object
end
local function rounded(parent, radius)
	make("UICorner", {CornerRadius = UDim.new(0, radius)}, parent)
end
local function text(parent, name, value, size, position, textSize, color)
	return make("TextLabel", {
		Name=name, Text=value, Size=size, Position=position,
		BackgroundTransparency=1, TextColor3=color or COLORS.White,
		Font=Enum.Font.GothamBold, TextSize=textSize,
		TextXAlignment=Enum.TextXAlignment.Left,
	}, parent)
end
local function button(parent, name, caption, size, position, color)
	local object = make("TextButton", {
		Name=name, Text=caption, Size=size, Position=position,
		BorderSizePixel=0, BackgroundColor3=color or COLORS.Blue,
		TextColor3=COLORS.White, Font=Enum.Font.GothamBlack, TextSize=12,
	}, parent)
	rounded(object,9)
	return object
end

local gui = make("ScreenGui", {
	Name="ParkourCreatorServerSizeUI", ResetOnSpawn=false,
	IgnoreGuiInset=false, DisplayOrder=1460, ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
}, pg)
local root = make("Frame", {
	Name="Root", Size=UDim2.fromScale(1,1), BackgroundTransparency=1,
}, gui)
local open = button(root,"OpenServerSize","",UDim2.fromOffset(170,42),UDim2.new(1,-190,0,178))
open.Visible = false
open.AutoButtonColor = true
make("UIStroke", {
	Color=COLORS.Cyan, Thickness=1, Transparency=0.45,
	ApplyStrokeMode=Enum.ApplyStrokeMode.Border,
}, open)

-- Fixed design canvas scales with the ONLINE PLAYERS button it sits beneath.
-- This keeps the icon and both text lines aligned at smaller resolutions.
local openContent = make("Frame", {
	Name="ButtonContent", Size=UDim2.fromOffset(170,42),
	AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5),
	BackgroundTransparency=1, Active=false,
}, open)
local openContentScale = make("UIScale", {Scale=1}, openContent)
local openTitle = text(openContent,"Caption","SERVER SIZE",
	UDim2.fromOffset(110,16),UDim2.fromOffset(49,4),11,COLORS.White)
openTitle.Font=Enum.Font.GothamBlack
openTitle.TextXAlignment=Enum.TextXAlignment.Center
local openCount = text(openContent,"PlayerCount","-- / --",
	UDim2.fromOffset(110,17),UDim2.fromOffset(49,20),14,COLORS.White)
openCount.Font=Enum.Font.GothamBlack
openCount.TextXAlignment=Enum.TextXAlignment.Center

-- Three-person outline, drawn from small rounded strokes and circular heads.
-- Cyan side figures and a brighter front figure match the existing UI theme.
do
	local icon = make("Frame", {
		Name="PlayerLimitIcon", Size=UDim2.fromOffset(32,32),
		Position=UDim2.fromOffset(11,5), BackgroundTransparency=1,
		Active=false,
	}, openContent)
	local sideColor=Color3.fromRGB(170,231,255)

	local function head(name,x,y,diameter,color)
		local circle=make("Frame", {
			Name=name, Size=UDim2.fromOffset(diameter,diameter),
			AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromOffset(x,y),
			BackgroundTransparency=1, BorderSizePixel=0, Active=false,
		}, icon)
		make("UICorner", {CornerRadius=UDim.new(1,0)}, circle)
		make("UIStroke", {
			Color=color, Thickness=1.45, Transparency=0.02,
			ApplyStrokeMode=Enum.ApplyStrokeMode.Border,
		}, circle)
	end

	local function outline(name,points,color)
		for i=1,#points-1 do
			local a,b=points[i],points[i+1]
			local dx,dy=b[1]-a[1],b[2]-a[2]
			local length=math.sqrt(dx*dx+dy*dy)
			local line=make("Frame", {
				Name=name..tostring(i), AnchorPoint=Vector2.new(0.5,0.5),
				Position=UDim2.fromOffset((a[1]+b[1])/2,(a[2]+b[2])/2),
				Size=UDim2.fromOffset(length+0.6,1.45),
				Rotation=math.deg(math.atan2(dy,dx)),
				BackgroundColor3=color, BorderSizePixel=0, Active=false,
			}, icon)
			make("UICorner", {CornerRadius=UDim.new(1,0)}, line)
		end
	end

	head("LeftHead",7,9,5.8,sideColor)
	head("RightHead",25,9,5.8,sideColor)
	outline("LeftShoulder",{{5.5,13.6},{3.3,15},{1.5,18.5},{1,23},{6.5,23}},sideColor)
	outline("RightShoulder",{{26.5,13.6},{28.7,15},{30.5,18.5},{31,23},{25.5,23}},sideColor)
	head("CenterHead",16,7,7.5,COLORS.White)
	outline("CenterShoulders",{
		{13,12.8},{10.2,14.4},{8.5,18},{7.5,26},
		{24.5,26},{23.5,18},{21.8,14.4},{19,12.8},
	},COLORS.White)
end

local function fitOpenButtonContent()
	local size=open.AbsoluteSize
	if size.X>0 and size.Y>0 then
		openContentScale.Scale=math.min(size.X/170,size.Y/42)
	end
end
open:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitOpenButtonContent)
fitOpenButtonContent()

local panel = make("Frame", {
	Name="ServerSizePanel", Size=UDim2.fromOffset(420,414),
	AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5),
	BackgroundColor3=COLORS.Navy, BorderSizePixel=0, Visible=false,
	Active=true, ZIndex=10,
}, root)
rounded(panel,14)
make("UIStroke", {Color=COLORS.Cyan,Thickness=2},panel)
local panelScale = make("UIScale", {Scale=1},panel)
local title = text(panel,"Title","SERVER SIZE",UDim2.new(1,-76,0,30),UDim2.fromOffset(20,14),18,COLORS.Cyan)
title.Font=Enum.Font.GothamBlack
local close = button(panel,"Close","X",UDim2.fromOffset(32,30),UDim2.new(1,-52,0,16),COLORS.Gray)
local subtitle = text(panel,"Subtitle","Manage your Creator server's player limit.",UDim2.new(1,-40,0,22),UDim2.fromOffset(20,48),12,COLORS.Muted)
local occupancy = text(panel,"Occupancy","PLAYERS INSIDE: --",UDim2.new(1,-40,0,24),UDim2.fromOffset(20,83),12,COLORS.White)
local limitTitle = text(panel,"LimitTitle","TOTAL PLAYER LIMIT",UDim2.new(1,-40,0,22),UDim2.fromOffset(20,114),11,COLORS.Muted)

local minus = button(panel,"Decrease","-",UDim2.fromOffset(52,52),UDim2.fromOffset(20,142),COLORS.Panel)
minus.TextSize=26

local value = make("TextLabel", {
	Name="LimitValue", Size=UDim2.new(1,-164,0,52), Position=UDim2.fromOffset(82,142),
	BackgroundColor3=COLORS.Panel, BorderSizePixel=0, Text="--",
	TextColor3=COLORS.White, Font=Enum.Font.GothamBlack, TextSize=28,
	TextXAlignment=Enum.TextXAlignment.Center, TextYAlignment=Enum.TextYAlignment.Center,
},panel)
rounded(value,9)

local plus = button(panel,"Increase","+",UDim2.fromOffset(52,52),UDim2.new(1,-72,0,142),COLORS.Panel)
plus.TextSize=26

-- =========================================================
-- SERVER SIZE SLIDER
-- 1 to 5 total players, including the owner.
-- =========================================================
local sliderTitle = text(
	panel,"SliderTitle","DRAG TO SET LIMIT",
	UDim2.new(1,-40,0,18),UDim2.fromOffset(20,207),10,COLORS.Muted
)

local sliderTrack = make("Frame",{
	Name="SliderTrack",
	Size=UDim2.new(1,-76,0,10),
	Position=UDim2.fromOffset(38,235),
	BackgroundColor3=Color3.fromRGB(44,67,84),
	BorderSizePixel=0,
	Active=true,
	ZIndex=12,
},panel)
rounded(sliderTrack,5)

local sliderFill = make("Frame",{
	Name="SliderFill",
	Size=UDim2.fromScale(0,1),
	BackgroundColor3=COLORS.Cyan,
	BorderSizePixel=0,
	ZIndex=13,
},sliderTrack)
rounded(sliderFill,5)

local sliderKnob = make("TextButton",{
	Name="SliderKnob",
	Size=UDim2.fromOffset(24,24),
	AnchorPoint=Vector2.new(.5,.5),
	Position=UDim2.new(0,0,.5,0),
	BackgroundColor3=COLORS.White,
	BorderSizePixel=0,
	Text="",
	AutoButtonColor=false,
	Active=true,
	ZIndex=15,
},sliderTrack)
rounded(sliderKnob,12)
make("UIStroke",{Color=COLORS.Cyan,Thickness=2},sliderKnob)

local sliderTicks=make("Frame",{
	Name="SliderTicks",
	Size=UDim2.new(1,-60,0,22),
	Position=UDim2.fromOffset(30,251),
	BackgroundTransparency=1,
	ZIndex=11,
},panel)

for n=1,5 do
	local tick=text(
		sliderTicks,
		"Tick"..n,
		tostring(n),
		UDim2.fromOffset(22,20),
		UDim2.new((n-1)/4,-11,0,0),
		10,
		COLORS.Muted
	)
	tick.TextXAlignment=Enum.TextXAlignment.Center
end

local range = text(
	panel,"Range",
	"1-5 players total. You count as one player.",
	UDim2.new(1,-40,0,20),UDim2.fromOffset(20,276),11,COLORS.Muted
)

local message = text(
	panel,"Message","",
	UDim2.new(1,-40,0,46),UDim2.fromOffset(20,302),11,COLORS.Muted
)
message.TextWrapped=true
message.TextYAlignment=Enum.TextYAlignment.Top

local cancel = button(
	panel,"Cancel","CANCEL",
	UDim2.fromOffset(118,40),UDim2.fromOffset(20,356),COLORS.Gray
)
local apply = button(
	panel,"Apply","APPLY",
	UDim2.new(1,-168,0,40),UDim2.fromOffset(148,356),COLORS.Blue
)

-- Separate notice panel: no writes to the invitation button or BuilderUI.
local notice = make("Frame", {
	Name="ServerSizeNotice", Size=UDim2.fromOffset(360,96),
	AnchorPoint=Vector2.new(1,0), Position=UDim2.new(1,390,0,235),
	BackgroundColor3=COLORS.Navy, BorderSizePixel=0, Visible=false, ZIndex=30,
},root)
rounded(notice,13)
make("UIStroke",{Color=COLORS.Cyan,Thickness=2},notice)
local noticeTitle = text(notice,"Title","SERVER SIZE UPDATED",UDim2.new(1,-28,0,25),UDim2.fromOffset(14,10),13,COLORS.Cyan)
local noticeBody = text(notice,"Body","",UDim2.new(1,-28,0,49),UDim2.fromOffset(14,39),12,COLORS.White)
noticeBody.TextWrapped=true
noticeBody.TextYAlignment=Enum.TextYAlignment.Top
local noticeGeneration = 0
local noticeTween = nil
local function showNotice(heading, body)
	noticeGeneration = noticeGeneration + 1
	local generation = noticeGeneration
	if noticeTween then noticeTween:Cancel() end
	noticeTitle.Text=tostring(heading)
	noticeBody.Text=tostring(body)
	notice.Visible=true
	notice.Position=UDim2.new(1,390,0,235)
	noticeTween=TweenService:Create(notice,TweenInfo.new(0.3,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Position=UDim2.new(1,-18,0,235)})
	noticeTween:Play()
	task.delay(4,function()
		if generation~=noticeGeneration or not notice.Parent then return end
		noticeTween=TweenService:Create(notice,TweenInfo.new(0.22,Enum.EasingStyle.Quart,Enum.EasingDirection.In),{Position=UDim2.new(1,390,0,235)})
		noticeTween:Play()
		task.delay(0.23,function()
			if generation==noticeGeneration then notice.Visible=false end
		end)
	end)
end

local state = nil
local selected = nil
local dirty = false
local applying = false
local draggingSlider = false
local HARD_MAX = 5
local requestToken = 0
local sourceButton = nil
local sourceConnections = {}

local function looksLikeOwner()
	local ownerId=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))
	if ownerId then
		return ownerId==player.UserId and workspace:GetAttribute("ParkourCreatorSessionClosing")~=true
	end
	return player:GetAttribute("ParkourCreatorOwner")==true
		and player:GetAttribute("ParkourCreatorGuest")~=true
end

local function updateLayout()
	local size=root.AbsoluteSize
	panelScale.Scale=math.max(0.25,math.min(1,(size.X-28)/420,(size.Y-28)/414))
	if sourceButton and sourceButton.Parent then
		-- Relative AbsolutePosition subtraction handles existing inset/UIScale.
		local p=sourceButton.AbsolutePosition-root.AbsolutePosition
		open.Position=UDim2.fromOffset(p.X,p.Y+sourceButton.AbsoluteSize.Y+8)
		open.Size=UDim2.fromOffset(sourceButton.AbsoluteSize.X,sourceButton.AbsoluteSize.Y)
	end
end

local function refreshButtonCount()
	-- Never use 'selected' here: it is the unsaved slider value.
	-- Capacity pushes State snapshots after admissions, departures and Apply.
	if state and state.available then
		openCount.Text=string.format("%d / %d",state.occupancy,state.limit)
	else
		openCount.Text="-- / --"
	end
end

local function refreshVisibility()
	refreshButtonCount()
	local canShow=looksLikeOwner()
	if state and state.available==false then canShow=false end
	open.Visible=canShow and (not sourceButton or sourceButton.Visible)
	if not canShow then panel.Visible=false end
end

local function render()
	refreshVisibility()
	local ready=state~=nil and state.available==true and selected~=nil
	local adjustable=ready and state.occupancy<=state.maximum
	minus.Active=adjustable and not applying and selected>math.max(1,state.occupancy)
	plus.Active=adjustable and not applying and selected<state.maximum
	apply.Active=adjustable and not applying
	sliderKnob.Active=adjustable and not applying
	sliderKnob.AutoButtonColor=false
	sliderKnob.BackgroundTransparency=(adjustable and not applying) and 0 or 0.4
	if applying or not adjustable then draggingSlider=false end
	for _,b in ipairs({minus,plus,apply}) do
		b.AutoButtonColor=b.Active
		b.BackgroundTransparency=b.Active and 0 or 0.4
	end
	apply.Text=applying and "APPLYING..." or "APPLY"
	if ready then
		value.Text=tostring(selected)
		occupancy.Text=string.format("PLAYERS INSIDE: %d / %d",state.occupancy,state.limit)
		range.Text=string.format("1-%d players total. You count as one player.",state.maximum)

		local shown=math.clamp(selected,1,HARD_MAX)
		local alpha=(shown-1)/(HARD_MAX-1)
		sliderFill.Size=UDim2.fromScale(alpha,1)
		sliderKnob.Position=UDim2.new(alpha,0,.5,0)
	else
		occupancy.Text="LOADING SERVER SIZE..."
	end
end

local function finiteInteger(n)
	return type(n)=="number" and n==n and n~=math.huge
		and n~=-math.huge and n%1==0
end

local function receiveState(data)
	if type(data)~="table" or not finiteInteger(data.limit)
		or not finiteInteger(data.maximum) or not finiteInteger(data.occupancy)
		or data.limit<1 or data.maximum<1 or data.occupancy<0 then
		warn("[SERVER SIZE UI] Ignoring an invalid capacity snapshot.")
		return
	end
	local incomingRevision=finiteInteger(data.revision) and data.revision or nil
	if state and incomingRevision and state.revision
		and incomingRevision<state.revision then
		return
	end
	state={
		available=data.available==true,
		limit=data.limit, occupancy=data.occupancy,
		maximum=math.min(HARD_MAX,data.maximum), revision=incomingRevision,
	}
	if not dirty or selected==nil then selected=state.limit end
	if state.occupancy<=state.maximum then
		selected=math.clamp(selected,math.max(1,state.occupancy),state.maximum)
	else
		-- Display the true occupancy; never silently clamp the badge count.
		selected=state.limit
	end
	render()
end

local function closePanel()
	draggingSlider=false
	panel.Visible=false
	dirty=false
end
close.Activated:Connect(closePanel)
cancel.Activated:Connect(closePanel)

open.Activated:Connect(function()
	if not looksLikeOwner() then return end
	panel.Visible=not panel.Visible
	if not panel.Visible then draggingSlider=false; return end
	dirty=false
	selected=state and state.limit or nil
	message.Text="This setting applies to this session only. Existing guests stay."
	message.TextColor3=COLORS.Muted
	remote:FireServer("Get")
	render()
end)

local function changeBy(amount)
	if applying or not state or not state.available or state.occupancy>state.maximum then return end
	selected=math.clamp((selected or state.limit)+amount,math.max(1,state.occupancy),state.maximum)
	dirty=true
	value.Text=tostring(selected)
	render()
end
minus.Activated:Connect(function() if minus.Active then changeBy(-1) end end)
plus.Activated:Connect(function() if plus.Active then changeBy(1) end end)

local function setSliderFromScreenX(screenX)
	if applying or not panel.Visible or not state or not state.available
		or state.occupancy>state.maximum then return end
	local width=sliderTrack.AbsoluteSize.X
	if width<=0 then return end

	local alpha=math.clamp(
		(screenX-sliderTrack.AbsolutePosition.X)/width,
		0,
		1
	)

	local candidate=math.floor(1+alpha*(HARD_MAX-1)+0.5)
	candidate=math.clamp(candidate,math.max(1,state.occupancy),state.maximum)

	if candidate~=selected then
		selected=candidate
		dirty=true
		render()
	end
end

local function beginSlider(input)
	if not panel.Visible or not state or not state.available or applying
		or state.occupancy>state.maximum then return end
	draggingSlider=true
	setSliderFromScreenX(input.Position.X)
end

sliderTrack.InputBegan:Connect(function(input)
	if input.UserInputType==Enum.UserInputType.MouseButton1
		or input.UserInputType==Enum.UserInputType.Touch then
		beginSlider(input)
	end
end)

sliderKnob.InputBegan:Connect(function(input)
	if input.UserInputType==Enum.UserInputType.MouseButton1
		or input.UserInputType==Enum.UserInputType.Touch then
		beginSlider(input)
	end
end)

UIS.InputChanged:Connect(function(input)
	if not draggingSlider then return end
	if input.UserInputType==Enum.UserInputType.MouseMovement
		or input.UserInputType==Enum.UserInputType.Touch then
		setSliderFromScreenX(input.Position.X)
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.UserInputType==Enum.UserInputType.MouseButton1
		or input.UserInputType==Enum.UserInputType.Touch then
		draggingSlider=false
	end
end)

apply.Activated:Connect(function()
	if applying or not state or not state.available or not selected then return end
	if selected<math.max(1,state.occupancy) or selected>state.maximum then
		message.Text="Choose a size from "..tostring(math.max(1,state.occupancy)).." to "..tostring(state.maximum).."."
		message.TextColor3=COLORS.Error
		return
	end
	applying=true
	requestToken=requestToken+1
	local myToken=requestToken
	remote:FireServer("Apply",selected)
	render()
	task.delay(8,function()
		if applying and requestToken==myToken then
			applying=false
			message.Text="No confirmation received. Reopen this panel to check the current limit."
			message.TextColor3=COLORS.Error
			render()
		end
	end)
end)

remote.OnClientEvent:Connect(function(action,a,b,c)
	if action=="State" then
		receiveState(a)
	elseif action=="Result" then
		applying=false
		requestToken=requestToken+1
		dirty=false
		receiveState(c)
		message.Text=tostring(b or "")
		message.TextColor3=a and COLORS.Cyan or COLORS.Error
		if a then showNotice("SERVER SIZE UPDATED",b) end
		render()
	elseif action=="Notice" then
		showNotice(a,b)
	end
end)

-- Attach visually below the existing ONLINE PLAYERS button without editing it.
local function findOnlineButton()
	local browser=pg:FindFirstChild("ParkourCrossServerBrowser")
	if not browser then return end
	for _,object in ipairs(browser:GetDescendants()) do
		if object:IsA("TextButton") and string.find(object.Text,"ONLINE PLAYERS",1,true) then
			if sourceButton==object then return end
			for _,connection in ipairs(sourceConnections) do connection:Disconnect() end
			table.clear(sourceConnections)
			sourceButton=object
			for _,property in ipairs({"AbsolutePosition","AbsoluteSize","Visible"}) do
				table.insert(sourceConnections,object:GetPropertyChangedSignal(property):Connect(function()
					updateLayout(); refreshVisibility()
				end))
			end
			table.insert(sourceConnections,object.Destroying:Connect(function()
				sourceButton=nil
				open.Position=UDim2.new(1,-190,0,178)
				open.Size=UDim2.fromOffset(170,42)
			end))
			updateLayout(); refreshVisibility()
			return
		end
	end
end

pg.DescendantAdded:Connect(function(object)
	if object:IsA("TextButton") then task.defer(findOnlineButton) end
end)
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout)
root:GetPropertyChangedSignal("AbsolutePosition"):Connect(updateLayout)
local function roleChanged()
	-- Drop a stale "not ready" snapshot when owner identity arrives later.
	if looksLikeOwner() then
		if state and not state.available then state=nil end
		remote:FireServer("Get")
	end
	refreshVisibility()
end
for _,name in ipairs({"ParkourCreatorOwner","ParkourCreatorGuest","ParkourPrivateCreator"}) do
	player:GetAttributeChangedSignal(name):Connect(roleChanged)
end
for _,name in ipairs({"ParkourCreatorOwnerUserId","ParkourCreatorSessionClosing"}) do
	workspace:GetAttributeChangedSignal(name):Connect(roleChanged)
end

-- A rejected arrival may receive its notification before this LocalScript loads.
local lastAdmissionMessage=nil
local function checkAdmissionMessage()
	local reason=player:GetAttribute("ParkourCreatorAdmissionMessage")
	if type(reason)=="string" and reason~=lastAdmissionMessage then
		lastAdmissionMessage=reason
		showNotice("CANNOT JOIN",reason)
	end
end
player:GetAttributeChangedSignal("ParkourCreatorAdmissionMessage"):Connect(checkAdmissionMessage)
findOnlineButton()
updateLayout()
roleChanged()
checkAdmissionMessage()
render()
print("[SERVER SIZE UI] V1.2 live count + outlined player icon loaded")

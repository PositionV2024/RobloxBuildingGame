-- ParkourUpdateLogClient V1
-- NEW LocalScript: StarterPlayer > StarterPlayerScripts > ParkourUpdateLogClient
-- Standalone navy/cyan window. NEVER changes another ScreenGui's Enabled value.
-- No GitHub or Roblox API credentials belong in this LocalScript.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local CONFIG = {
	ButtonOnlyInDiscover = true, -- false also shows it during Creator sessions
	NotifyUnreadOnJoin = true,
	ButtonPosition = UDim2.new(0, 18, 1, -62),
}
local COLOR = {
	Panel = Color3.fromRGB(7,25,40), Card = Color3.fromRGB(12,35,53),
	Blue = Color3.fromRGB(20,145,225), Cyan = Color3.fromRGB(75,210,255),
	White = Color3.fromRGB(240,248,255), Muted = Color3.fromRGB(157,186,207),
	Gray = Color3.fromRGB(42,59,76), Error = Color3.fromRGB(255,184,128),
}

if pg:FindFirstChild("ParkourUpdateLogUI") then
	warn("[UPDATE LOG] Duplicate client ignored. Keep only one ParkourUpdateLogClient.")
	return
end

local function make(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do instance[key] = value end
	instance.Parent = parent
	return instance
end
local function rounded(parent, radius)
	make("UICorner", {CornerRadius = UDim.new(0, radius or 10)}, parent)
end
local function outline(parent, color, thickness)
	return make("UIStroke", {
		Color = color or COLOR.Cyan, Thickness = thickness or 1,
		Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end
local function label(parent, name, value, size, position, fontSize, color)
	return make("TextLabel", {
		Name = name, Text = value, Size = size, Position = position,
		BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextSize = fontSize or 14, TextColor3 = color or COLOR.White,
		TextXAlignment = Enum.TextXAlignment.Left, RichText = false,
	}, parent)
end
local function button(parent, name, value, size, position, background)
	local b = make("TextButton", {
		Name = name, Text = value, Size = size, Position = position,
		BackgroundColor3 = background or COLOR.Blue, BorderSizePixel = 0,
		Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = COLOR.White,
		AutoButtonColor = true,
	}, parent)
	rounded(b, 9)
	return b
end

local gui = make("ScreenGui", {
	Name = "ParkourUpdateLogUI", ResetOnSpawn = false,
	IgnoreGuiInset = false, DisplayOrder = 1750,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, pg)
local open = button(gui, "OpenUpdates", "UPDATES", UDim2.fromOffset(156,40), CONFIG.ButtonPosition)
local badge = label(open, "NewBadge", "NEW", UDim2.fromOffset(38,20), UDim2.new(1,-44,0.5,-10), 10, COLOR.Panel)
badge.BackgroundTransparency = 0
badge.BackgroundColor3 = COLOR.Cyan
badge.TextXAlignment = Enum.TextXAlignment.Center
badge.Font = Enum.Font.GothamBlack
badge.Visible = false
rounded(badge, 6)

local shade = make("TextButton", {
	Name = "ModalShade", Size = UDim2.fromScale(1,1), Text = "",
	BackgroundColor3 = Color3.new(0,0,0), BackgroundTransparency = 0.38,
	BorderSizePixel = 0, AutoButtonColor = false, Visible = false, ZIndex = 10,
}, gui)
local panel = make("Frame", {
	Name = "UpdateWindow", AnchorPoint = Vector2.new(0.5,0.5),
	Position = UDim2.fromScale(0.5,0.5), Size = UDim2.fromOffset(660,520),
	BackgroundColor3 = COLOR.Panel, BorderSizePixel = 0, Visible = false, ZIndex = 11,
}, gui)
rounded(panel, 15)
outline(panel, COLOR.Cyan, 2)
local title = label(panel, "Title", "UPDATE LOG", UDim2.new(1,-90,0,32), UDim2.fromOffset(18,10), 21, COLOR.Cyan)
title.Font = Enum.Font.GothamBlack
local subtitle = label(panel, "Subtitle", "What's new in your parkour world", UDim2.new(1,-36,0,20), UDim2.fromOffset(18,44), 12, COLOR.Muted)
subtitle.TextTruncate = Enum.TextTruncate.AtEnd
local close = button(panel, "Close", "X", UDim2.fromOffset(38,34), UDim2.new(1,-54,0,14), COLOR.Gray)
local status = label(panel, "ServiceStatus", "Loading update history...", UDim2.new(1,-36,0,26), UDim2.fromOffset(18,72), 12, COLOR.Muted)
status.TextTruncate = Enum.TextTruncate.AtEnd

local list = make("ScrollingFrame", {
	Name = "ReleaseHistory", Size = UDim2.new(1,-36,1,-152), Position = UDim2.fromOffset(18,105),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5,
	ScrollBarImageColor3 = COLOR.Cyan, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
}, panel)
make("UIListLayout", {Padding = UDim.new(0,12), SortOrder = Enum.SortOrder.LayoutOrder}, list)
make("UIPadding", {PaddingTop=UDim.new(0,3),PaddingBottom=UDim.new(0,6),PaddingLeft=UDim.new(0,3)}, list)
local footer = label(panel, "Footer", "New notes are checked about every 2 minutes.", UDim2.new(1,-36,0,32), UDim2.new(0,18,1,-42), 11, COLOR.Muted)
footer.TextWrapped = true

local toast = button(gui, "UpdateToast", "", UDim2.fromOffset(310,84), UDim2.new(1,340,1,-112), COLOR.Panel)
toast.AnchorPoint = Vector2.new(1,1)
toast.Visible = false
toast.ZIndex = 20
outline(toast, COLOR.Cyan, 2)
local toastTitle = label(toast, "Heading", "NEW UPDATE", UDim2.new(1,-28,0,24), UDim2.fromOffset(14,10), 13, COLOR.Cyan)
toastTitle.Font = Enum.Font.GothamBlack
local toastBody = label(toast, "Message", "Tap to read the latest changes.", UDim2.new(1,-28,0,36), UDim2.fromOffset(14,35), 12, COLOR.White)
toastBody.TextWrapped = true

local remote = nil
local state = nil
local renderedFingerprint = nil
local pendingRead = nil
local announced = {}
local receivedReadyState = false
local openWindow
local notificationToken = 0
local notificationTween = nil
local watched = {}
local cameraConnection = nil

local transitions = {
	ParkourCreatorTransitionUI = true, ParkourExitTransitionUI = true,
	ParkourGuestReturnTransitionUI = true, ParkourKickReturnTransition = true,
}
local function inTransition()
	if pg:GetAttribute("CreatorTransitionActive") == true then return true end
	for _, child in ipairs(pg:GetChildren()) do
		if child:IsA("ScreenGui") and transitions[child.Name] and child.Enabled then return true end
	end
	return false
end
local function hideToast()
	notificationToken = notificationToken + 1
	if notificationTween then notificationTween:Cancel(); notificationTween = nil end
	toast.Visible = false
end
local function closeWindow()
	panel.Visible = false
	shade.Visible = false
end
local function refreshVisibility()
	local transitioning = inTransition()
	local discover = pg:FindFirstChild("ParkourDiscoverUI")
	local show = not transitioning
	if show and CONFIG.ButtonOnlyInDiscover and discover and discover:IsA("ScreenGui") then
		show = discover.Enabled
		local background = discover:FindFirstChildWhichIsA("Frame")
		if background then show = show and background.Visible end
	end
	open.Visible = show
	if transitioning then closeWindow(); hideToast() end
end
local function responsive()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local size = camera.ViewportSize
	panel.Size = UDim2.fromOffset(math.max(240, math.min(660, size.X-30)), math.max(220, math.min(520, size.Y-80)))
	toast.Size = UDim2.fromOffset(math.max(220, math.min(310,size.X-36)),84)
end
local function hookCamera()
	if cameraConnection then cameraConnection:Disconnect(); cameraConnection=nil end
	if workspace.CurrentCamera then
		cameraConnection = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(responsive)
	end
	responsive()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
hookCamera()

local function watchGui(child)
	if watched[child] then return end
	if child:IsA("ScreenGui") and (child.Name=="ParkourDiscoverUI" or transitions[child.Name]) then
		watched[child] = true
		child:GetPropertyChangedSignal("Enabled"):Connect(refreshVisibility)
		child.ChildAdded:Connect(function(item)
			if item:IsA("Frame") then item:GetPropertyChangedSignal("Visible"):Connect(refreshVisibility) end
			task.defer(refreshVisibility)
		end)
		for _, item in ipairs(child:GetChildren()) do
			if item:IsA("Frame") then item:GetPropertyChangedSignal("Visible"):Connect(refreshVisibility) end
		end
	end
end
for _, child in ipairs(pg:GetChildren()) do watchGui(child) end
pg.ChildAdded:Connect(function(child) watchGui(child); task.defer(refreshVisibility) end)
pg.ChildRemoved:Connect(function(child) watched[child]=nil; task.defer(refreshVisibility) end)
pg:GetAttributeChangedSignal("CreatorTransitionActive"):Connect(refreshVisibility)
refreshVisibility()

local MONTHS = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
local function formatDate(timestamp)
	local ok, date = pcall(function() return DateTime.fromUnixTimestamp(timestamp):ToUniversalTime() end)
	if not ok then return "Release date unavailable" end
	return string.format("%02d %s %04d", date.Day, MONTHS[date.Month] or "", date.Year)
end
local function clearCards()
	for _, item in ipairs(list:GetChildren()) do if item:IsA("Frame") then item:Destroy() end end
end
local function card(entry, order)
	local frame = make("Frame", {
		Name = "ReleaseCard", LayoutOrder = order, Size = UDim2.new(1,-12,0,0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = COLOR.Card, BorderSizePixel = 0,
	}, list)
	rounded(frame, 11)
	outline(frame, order == 1 and COLOR.Cyan or COLOR.Gray, order == 1 and 1.5 or 1)
	make("UIPadding", {
		PaddingTop = UDim.new(0,14), PaddingBottom = UDim.new(0,16),
		PaddingLeft = UDim.new(0,14), PaddingRight = UDim.new(0,14),
	}, frame)
	make("UIListLayout", {Padding = UDim.new(0,8), SortOrder=Enum.SortOrder.LayoutOrder}, frame)
	local meta = label(frame, "ReleaseMeta", entry.version .. "  •  " .. formatDate(entry.publishedAt), UDim2.new(1,0,0,20), UDim2.new(), 11, COLOR.Cyan)
	meta.LayoutOrder=1
	meta.TextTruncate=Enum.TextTruncate.AtEnd
	meta.Font=Enum.Font.GothamBold
	local heading=label(frame,"ReleaseTitle",entry.title,UDim2.new(1,0,0,0),UDim2.new(),18,COLOR.White)
	heading.LayoutOrder=2
	heading.Font=Enum.Font.GothamBlack
	heading.AutomaticSize=Enum.AutomaticSize.Y
	heading.TextWrapped=true
	heading.TextYAlignment=Enum.TextYAlignment.Top
	local body=label(frame,"ReleaseNotes",entry.body,UDim2.new(1,0,0,0),UDim2.new(),14,COLOR.White)
	body.LayoutOrder=3
	body.AutomaticSize=Enum.AutomaticSize.Y
	body.TextWrapped=true
	body.TextYAlignment=Enum.TextYAlignment.Top
	body.LineHeight=1.2
end
local function updateScreen()
	badge.Visible = state ~= nil and state.unread == true
	open.Text = badge.Visible and "UPDATES       " or "UPDATES"
	if not state then return end
	if renderedFingerprint ~= state.fingerprint then
		renderedFingerprint=state.fingerprint
		clearCards()
		for index, entry in ipairs(state.entries) do card(entry,index) end
		list.CanvasPosition=Vector2.zero
	end
	if state.demo then
		status.Text="STUDIO DEMO — no live release or saved data"
		status.TextColor3=COLOR.Error
	elseif state.status=="loading" then
		status.Text="Loading update history..."
		status.TextColor3=COLOR.Muted
	elseif state.status=="unavailable" then
		status.Text="Update history is unavailable. The server will retry."
		status.TextColor3=COLOR.Error
	elseif state.status=="stale" then
		status.Text="Showing saved notes while the server reconnects."
		status.TextColor3=COLOR.Error
	elseif #state.entries==0 then
		status.Text="No update announcements have been published yet."
		status.TextColor3=COLOR.Muted
	else
		status.Text=state.unread and "NEW RELEASE AVAILABLE" or "YOU'RE UP TO DATE"
		status.TextColor3=COLOR.Cyan
	end
end
local function markRead()
	if not remote or not state or not panel.Visible or list.CanvasPosition.Y>12 then return end
	local latest=state.entries[1]
	if not latest or not state.unread or pendingRead==latest.id then return end
	pendingRead=latest.id
	remote:FireServer("Read",latest.id)
	local id=latest.id
	task.delay(3,function() if pendingRead==id then pendingRead=nil end end)
end
local function showToast(entry)
	if inTransition() or panel.Visible then return end
	notificationToken=notificationToken+1
	local myToken=notificationToken
	if notificationTween then notificationTween:Cancel() end
	toastTitle.Text="NEW UPDATE  •  " .. entry.version
	toastTitle.TextTruncate=Enum.TextTruncate.AtEnd
	toastBody.Text=entry.title .. "\nTap to read the changes."
	toast.Position=UDim2.new(1,340,1,-112)
	toast.Visible=true
	notificationTween=TweenService:Create(toast,TweenInfo.new(0.3,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Position=UDim2.new(1,-18,1,-112)})
	notificationTween:Play()
	task.delay(5,function()
		if myToken~=notificationToken then return end
		notificationTween=TweenService:Create(toast,TweenInfo.new(0.22,Enum.EasingStyle.Quart,Enum.EasingDirection.In),{Position=UDim2.new(1,340,1,-112)})
		notificationTween:Play()
		task.delay(0.25,function() if myToken==notificationToken then toast.Visible=false end end)
	end)
end
openWindow=function()
	if inTransition() then return end
	hideToast()
	panel.Visible=true
	shade.Visible=true
	updateScreen()
	list.CanvasPosition=Vector2.zero
	if remote then remote:FireServer("Request") end
	markRead()
end
open.Activated:Connect(function() if panel.Visible then closeWindow() else openWindow() end end)
close.Activated:Connect(closeWindow)
shade.Activated:Connect(closeWindow)
toast.Activated:Connect(openWindow)
list:GetPropertyChangedSignal("CanvasPosition"):Connect(markRead)
UIS.InputBegan:Connect(function(input,processed)
	if not processed and panel.Visible and input.KeyCode==Enum.KeyCode.Escape then closeWindow() end
end)

local function attachRemote(candidate)
	if remote or candidate.Name~="ParkourUpdateLogEvent" or not candidate:IsA("RemoteEvent") then return end
	remote=candidate
	remote.OnClientEvent:Connect(function(action,data)
		if action~="State" or type(data)~="table" or type(data.entries)~="table" or type(data.fingerprint)~="string" then return end
		state=data
		if not state.unread then pendingRead=nil end
		updateScreen()
		if state.seenReady and state.status=="ready" then
			local latest=state.entries[1]
			if latest and state.unread and not announced[latest.id] then
				announced[latest.id]=true
				if receivedReadyState or CONFIG.NotifyUnreadOnJoin then showToast(latest) end
			end
			receivedReadyState=true
		end
		markRead()
	end)
	remote:FireServer("Request")
end
RS.ChildAdded:Connect(attachRemote)
local found=RS:FindFirstChild("ParkourUpdateLogEvent")
if found then attachRemote(found) end
-- Retry only the initial cached-state request in case the service starts late.
task.spawn(function()
	for attempt=1,4 do
		task.wait(3)
		if state then return end
		if remote then remote:FireServer("Request") end
	end
	if not state then
		status.Text="Update-log server not responding. Check Studio Output."
		status.TextColor3=COLOR.Error
	end
end)

print("[UPDATE LOG] Client V1 loaded -- existing game UIs left untouched")

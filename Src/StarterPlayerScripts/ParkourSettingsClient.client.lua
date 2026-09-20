-- MAKE YOUR OWN PARKOUR - SETTINGS / KEY BINDINGS V1
-- StarterPlayer > StarterPlayerScripts > ParkourSettingsClient
-- Adds a SETTINGS button directly to ParkourDiscoverUI and configurable builder keys.
-- V1 stores settings for the current session. Persistent DataStore saving can be added next.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")

local player=Players.LocalPlayer
local pg=player:WaitForChild("PlayerGui")

local event=RS:FindFirstChild("ParkourKeybindEvent") or Instance.new("BindableEvent")
event.Name="ParkourKeybindEvent"
event.Parent=RS
local saveRemote=RS:WaitForChild("ParkourKeybindSaveEvent")
local prefsRemote=RS:WaitForChild("ParkourPlayerSettingsEvent")
local prefsGet=RS:WaitForChild("ParkourPlayerSettingsGet")

local defaults={
	Place="Q",Move="G",Rotate="E",Scale="R",Delete="Delete",CancelTransform="Escape",ConfirmTransform="Return",HideBuildUI="H",
	Platform="One",KillBlock="Two",BouncePad="Three",SpeedPad="Four",
	Checkpoint="Five",Start="Six",Finish="Seven",Test="F"
}
local binds={}
for k,v in pairs(defaults) do binds[k]=v end

local display={
	One="1",Two="2",Three="3",Four="4",Five="5",Six="6",Seven="7",
	Space="SPACE",LeftShift="LSHIFT",RightShift="RSHIFT",Delete="DEL",Escape="ESC",Return="ENTER",KeypadEnter="NUM ENTER"
}
local reservedMovement={W=true,A=true,S=true,D=true}
local function pretty(k)return display[k] or string.upper(k)end

local gui=Instance.new("ScreenGui")
gui.Name="ParkourSettingsUI"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.DisplayOrder=150
gui.Parent=pg

local open=Instance.new("TextButton")
open.Name="SettingsButton"
open.Size=UDim2.fromOffset(125,40)
open.Position=UDim2.new(1,-270,0,20)
open.BackgroundColor3=Color3.fromRGB(48,58,72)
open.BorderSizePixel=0
open.Text="⚙  SETTINGS"
open.Font=Enum.Font.GothamBold
open.TextSize=13
open.TextColor3=Color3.new(1,1,1)
open.Parent=gui
local oc=Instance.new("UICorner");oc.CornerRadius=UDim.new(0,8);oc.Parent=open

local shade=Instance.new("TextButton")
shade.Size=UDim2.fromScale(1,1);shade.BackgroundColor3=Color3.fromRGB(5,9,15)
shade.BackgroundTransparency=.35;shade.BorderSizePixel=0;shade.Text="";shade.Visible=false
shade.AutoButtonColor=false;shade.ZIndex=10;shade.Parent=gui

local panel=Instance.new("Frame")
panel.Size=UDim2.fromOffset(650,590);panel.Position=UDim2.new(.5,-325,.5,-295)
panel.BackgroundColor3=Color3.fromRGB(24,31,41);panel.BorderSizePixel=0;panel.Visible=false
panel.ZIndex=11;panel.Parent=gui
local pc=Instance.new("UICorner");pc.CornerRadius=UDim.new(0,14);pc.Parent=panel

local title=Instance.new("TextLabel")
title.Size=UDim2.new(1,-100,0,55);title.Position=UDim2.fromOffset(22,10);title.BackgroundTransparency=1
title.Text="⚙  SETTINGS";title.TextXAlignment=Enum.TextXAlignment.Left;title.Font=Enum.Font.GothamBlack
title.TextSize=23;title.TextColor3=Color3.new(1,1,1);title.ZIndex=12;title.Parent=panel

local close=Instance.new("TextButton")
close.Size=UDim2.fromOffset(48,40);close.Position=UDim2.new(1,-62,0,16);close.BackgroundColor3=Color3.fromRGB(55,65,78)
close.BorderSizePixel=0;close.Text="×";close.Font=Enum.Font.GothamBlack;close.TextSize=22;close.TextColor3=Color3.new(1,1,1)
close.ZIndex=12;close.Parent=panel

local heading=Instance.new("TextLabel")
heading.Size=UDim2.new(1,-44,0,44);heading.Position=UDim2.fromOffset(22,70);heading.BackgroundTransparency=1
heading.Text="KEY BINDINGS\\nCustomize controls for smoother building";heading.TextXAlignment=Enum.TextXAlignment.Left
heading.Font=Enum.Font.GothamBold;heading.TextSize=15;heading.TextColor3=Color3.fromRGB(185,200,215);heading.ZIndex=12;heading.Parent=panel

local scroll=Instance.new("ScrollingFrame")
scroll.Size=UDim2.new(1,-44,0,390);scroll.Position=UDim2.fromOffset(22,125)
scroll.BackgroundTransparency=1;scroll.BorderSizePixel=0;scroll.ScrollBarThickness=5
scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y;scroll.CanvasSize=UDim2.new();scroll.ZIndex=12;scroll.Parent=panel
local layout=Instance.new("UIListLayout");layout.Padding=UDim.new(0,6);layout.Parent=scroll

local AUTOSAVE_MIN=30
local AUTOSAVE_MAX=300
local AUTOSAVE_DEFAULT=60
local SELECT_RANGE_MIN=15
local SELECT_RANGE_MAX=100
local SELECT_RANGE_DEFAULT=45
local selectRange=math.clamp(
	tonumber(pg:GetAttribute("ParkourSelectRange")) or SELECT_RANGE_DEFAULT,
	SELECT_RANGE_MIN,
	SELECT_RANGE_MAX
)
pg:SetAttribute("ParkourSelectRange",selectRange)

local autoSaveThreshold=tonumber(pg:GetAttribute("ParkourAutoSaveInterval")) or AUTOSAVE_DEFAULT
autoSaveThreshold=math.clamp(math.floor(autoSaveThreshold+.5),AUTOSAVE_MIN,AUTOSAVE_MAX)
pg:SetAttribute("ParkourAutoSaveInterval",autoSaveThreshold)

local labels={
	{"Move","Move mode"},{"Rotate","Rotate mode"},{"Scale","Scale mode"},{"Delete","Delete"},{"CancelTransform","Cancel transform"},{"ConfirmTransform","Confirm transform"},{"HideBuildUI","Hide build UI"},
	{"Platform","Platform"},{"KillBlock","Kill Block"},{"BouncePad","Bounce Pad"},{"SpeedPad","Speed Pad"},
	{"Checkpoint","Checkpoint"},{"Start","Start"},{"Finish","Finish"},{"Test","Test / Exit Test"}
}
local bindingButtons={}
local listening=nil

local function broadcast()
	local copy={}
	for k,v in pairs(binds) do
		copy[k]=v
		-- Persistent session state so Builder can read the current binding
		-- even if it loaded after the Settings client broadcast.
		pg:SetAttribute("ParkourBind_"..k,v)
	end
	event:Fire("BindingsChanged",copy)
end

for _,entry in ipairs(labels) do
	local action,labelText=entry[1],entry[2]
	local row=Instance.new("Frame");row.Size=UDim2.new(1,-8,0,46);row.BackgroundColor3=Color3.fromRGB(35,44,56)
	row.BorderSizePixel=0;row.ZIndex=13;row.Parent=scroll
	local rc=Instance.new("UICorner");rc.CornerRadius=UDim.new(0,8);rc.Parent=row

	local label=Instance.new("TextLabel");label.Size=UDim2.new(1,-155,1,0);label.Position=UDim2.fromOffset(14,0)
	label.BackgroundTransparency=1;label.Text=labelText;label.TextXAlignment=Enum.TextXAlignment.Left
	label.Font=Enum.Font.GothamBold;label.TextSize=14;label.TextColor3=Color3.new(1,1,1);label.ZIndex=14;label.Parent=row

	local b=Instance.new("TextButton");b.Size=UDim2.fromOffset(125,34);b.Position=UDim2.new(1,-136,.5,-17)
	b.BackgroundColor3=Color3.fromRGB(55,112,175);b.BorderSizePixel=0;b.Text=pretty(binds[action])
	b.Font=Enum.Font.GothamBlack;b.TextSize=13;b.TextColor3=Color3.new(1,1,1);b.ZIndex=14;b.Parent=row
	local bc=Instance.new("UICorner");bc.CornerRadius=UDim.new(0,7);bc.Parent=b
	bindingButtons[action]=b
	b.MouseButton1Click:Connect(function()
		if listening and bindingButtons[listening] then bindingButtons[listening].Text=pretty(binds[listening]) end
		listening=action;b.Text="PRESS A KEY..."
	end)
end

local reset=Instance.new("TextButton")
reset.Size=UDim2.fromOffset(190,42);reset.Position=UDim2.new(0,22,0,532);reset.BackgroundColor3=Color3.fromRGB(65,75,90)
reset.BorderSizePixel=0;reset.Text="RESET TO DEFAULT";reset.Font=Enum.Font.GothamBlack;reset.TextSize=13
reset.TextColor3=Color3.new(1,1,1);reset.ZIndex=12;reset.Parent=panel
local resc=Instance.new("UICorner");resc.CornerRadius=UDim.new(0,8);resc.Parent=reset

-- Keybindings now save automatically when Settings closes.
-- Keep a hidden compatibility object because the existing save response code references `save`.
local save=Instance.new("TextButton")
save.Name="HiddenKeybindSave"
save.Size=UDim2.fromOffset(1,1)
save.Position=UDim2.fromOffset(-100,-100)
save.Visible=false
save.Active=false
save.Text=""
save.Parent=panel

local done=Instance.new("TextButton")
done.Size=UDim2.fromOffset(190,42);done.Position=UDim2.new(1,-212,0,532);done.BackgroundColor3=Color3.fromRGB(55,175,110)
done.BorderSizePixel=0;done.Text="DONE";done.Font=Enum.Font.GothamBlack;done.TextSize=13
done.TextColor3=Color3.new(1,1,1);done.ZIndex=12;done.Parent=panel
local dc=Instance.new("UICorner");dc.CornerRadius=UDim.new(0,8);dc.Parent=done

-- AUTO SAVE: one normal row inside the existing scroll list.
local autoRow=Instance.new("Frame")
autoRow.Size=UDim2.new(1,-8,0,46);autoRow.BackgroundColor3=Color3.fromRGB(35,44,56)
autoRow.BorderSizePixel=0;autoRow.ZIndex=13;autoRow.Parent=scroll
local autoCorner=Instance.new("UICorner");autoCorner.CornerRadius=UDim.new(0,8);autoCorner.Parent=autoRow

local autoLabel=Instance.new("TextLabel")
autoLabel.Size=UDim2.new(1,-155,1,0);autoLabel.Position=UDim2.fromOffset(14,0)
autoLabel.BackgroundTransparency=1;autoLabel.Text="Auto save interval";autoLabel.TextXAlignment=Enum.TextXAlignment.Left
autoLabel.Font=Enum.Font.GothamBold;autoLabel.TextSize=14;autoLabel.TextColor3=Color3.new(1,1,1);autoLabel.ZIndex=14;autoLabel.Parent=autoRow

-- Smooth auto-save interval slider: 30 to 300 seconds.
local sliderWrap=Instance.new("Frame")
sliderWrap.Size=UDim2.fromOffset(210,34)
sliderWrap.Position=UDim2.new(1,-221,.5,-17)
sliderWrap.BackgroundTransparency=1
sliderWrap.ZIndex=14
sliderWrap.Parent=autoRow

local sliderTrack=Instance.new("Frame")
sliderTrack.Name="Track"
sliderTrack.Size=UDim2.new(1,-58,0,7)
sliderTrack.Position=UDim2.fromOffset(0,14)
sliderTrack.BackgroundColor3=Color3.fromRGB(58,72,90)
sliderTrack.BorderSizePixel=0
sliderTrack.ZIndex=14
sliderTrack.Parent=sliderWrap
local stc=Instance.new("UICorner");stc.CornerRadius=UDim.new(1,0);stc.Parent=sliderTrack

local sliderFill=Instance.new("Frame")
sliderFill.Name="Fill"
sliderFill.Size=UDim2.fromScale(0,1)
sliderFill.BackgroundColor3=Color3.fromRGB(60,145,225)
sliderFill.BorderSizePixel=0
sliderFill.ZIndex=15
sliderFill.Parent=sliderTrack
local sfc=Instance.new("UICorner");sfc.CornerRadius=UDim.new(1,0);sfc.Parent=sliderFill

local knob=Instance.new("TextButton")
knob.Name="Knob"
knob.Size=UDim2.fromOffset(18,18)
knob.AnchorPoint=Vector2.new(.5,.5)
knob.Position=UDim2.new(0,0,.5,0)
knob.BackgroundColor3=Color3.fromRGB(225,245,255)
knob.BorderSizePixel=0
knob.Text=""
knob.AutoButtonColor=false
knob.ZIndex=16
knob.Parent=sliderTrack
local kc=Instance.new("UICorner");kc.CornerRadius=UDim.new(1,0);kc.Parent=knob
local ks=Instance.new("UIStroke");ks.Color=Color3.fromRGB(65,155,235);ks.Thickness=2;ks.Parent=knob

local autoValue=Instance.new("TextLabel")
autoValue.Size=UDim2.fromOffset(52,34)
autoValue.Position=UDim2.new(1,-52,0,0)
autoValue.BackgroundColor3=Color3.fromRGB(55,112,175)
autoValue.BorderSizePixel=0
autoValue.Font=Enum.Font.GothamBlack
autoValue.TextSize=11
autoValue.TextColor3=Color3.new(1,1,1)
autoValue.ZIndex=14
autoValue.Parent=sliderWrap
local avc=Instance.new("UICorner");avc.CornerRadius=UDim.new(0,7);avc.Parent=autoValue

local draggingSlider=false

local function updateAutoSaveSlider(value)
	value=math.clamp(math.floor(value+.5),AUTOSAVE_MIN,AUTOSAVE_MAX)
	autoSaveThreshold=value
	pg:SetAttribute("ParkourAutoSaveInterval",value)

	local alpha=(value-AUTOSAVE_MIN)/(AUTOSAVE_MAX-AUTOSAVE_MIN)
	sliderFill.Size=UDim2.fromScale(alpha,1)
	knob.Position=UDim2.new(alpha,0,.5,0)
	autoValue.Text=tostring(value).."s"
end

local function sliderFromX(x)
	local left=sliderTrack.AbsolutePosition.X
	local width=math.max(1,sliderTrack.AbsoluteSize.X)
	local alpha=math.clamp((x-left)/width,0,1)

	-- Snap to 5-second increments for smooth but practical adjustment.
	local raw=AUTOSAVE_MIN+alpha*(AUTOSAVE_MAX-AUTOSAVE_MIN)
	local value=math.round(raw/5)*5
	updateAutoSaveSlider(value)
end

knob.MouseButton1Down:Connect(function()
	draggingSlider=true
end)

sliderTrack.InputBegan:Connect(function(input)
	if input.UserInputType==Enum.UserInputType.MouseButton1
		or input.UserInputType==Enum.UserInputType.Touch then
		draggingSlider=true
		sliderFromX(input.Position.X)
	end
end)

UIS.InputChanged:Connect(function(input)
	if not draggingSlider then return end
	if input.UserInputType==Enum.UserInputType.MouseMovement
		or input.UserInputType==Enum.UserInputType.Touch then
		sliderFromX(input.Position.X)
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.UserInputType==Enum.UserInputType.MouseButton1
		or input.UserInputType==Enum.UserInputType.Touch then
		draggingSlider=false
	end
end)

updateAutoSaveSlider(autoSaveThreshold)

-- SELECT RANGE SLIDER
local rangeRow=Instance.new("Frame")
rangeRow.Size=UDim2.new(1,-8,0,46)
rangeRow.BackgroundColor3=Color3.fromRGB(35,44,56)
rangeRow.BorderSizePixel=0
rangeRow.ZIndex=13
rangeRow.Parent=scroll
local rrc=Instance.new("UICorner");rrc.CornerRadius=UDim.new(0,8);rrc.Parent=rangeRow

local rangeLabel=Instance.new("TextLabel")
rangeLabel.Size=UDim2.new(1,-250,1,0)
rangeLabel.Position=UDim2.fromOffset(14,0)
rangeLabel.BackgroundTransparency=1
rangeLabel.Text="Select range"
rangeLabel.TextXAlignment=Enum.TextXAlignment.Left
rangeLabel.Font=Enum.Font.GothamBold
rangeLabel.TextSize=14
rangeLabel.TextColor3=Color3.new(1,1,1)
rangeLabel.ZIndex=14
rangeLabel.Parent=rangeRow

local rangeWrap=Instance.new("Frame")
rangeWrap.Size=UDim2.fromOffset(210,34)
rangeWrap.Position=UDim2.new(1,-221,.5,-17)
rangeWrap.BackgroundTransparency=1
rangeWrap.ZIndex=14
rangeWrap.Parent=rangeRow

local rangeTrack=Instance.new("Frame")
rangeTrack.Size=UDim2.new(1,-58,0,7)
rangeTrack.Position=UDim2.fromOffset(0,14)
rangeTrack.BackgroundColor3=Color3.fromRGB(58,72,90)
rangeTrack.BorderSizePixel=0
rangeTrack.ZIndex=14
rangeTrack.Parent=rangeWrap
local rtc=Instance.new("UICorner");rtc.CornerRadius=UDim.new(1,0);rtc.Parent=rangeTrack

local rangeFill=Instance.new("Frame")
rangeFill.Size=UDim2.fromScale(0,1)
rangeFill.BackgroundColor3=Color3.fromRGB(60,145,225)
rangeFill.BorderSizePixel=0
rangeFill.ZIndex=15
rangeFill.Parent=rangeTrack
local rfc=Instance.new("UICorner");rfc.CornerRadius=UDim.new(1,0);rfc.Parent=rangeFill

local rangeKnob=Instance.new("TextButton")
rangeKnob.Size=UDim2.fromOffset(18,18)
rangeKnob.AnchorPoint=Vector2.new(.5,.5)
rangeKnob.Position=UDim2.new(0,0,.5,0)
rangeKnob.BackgroundColor3=Color3.fromRGB(225,245,255)
rangeKnob.BorderSizePixel=0
rangeKnob.Text=""
rangeKnob.AutoButtonColor=false
rangeKnob.ZIndex=16
rangeKnob.Parent=rangeTrack
local rkc=Instance.new("UICorner");rkc.CornerRadius=UDim.new(1,0);rkc.Parent=rangeKnob
local rks=Instance.new("UIStroke");rks.Color=Color3.fromRGB(65,155,235);rks.Thickness=2;rks.Parent=rangeKnob

local rangeValue=Instance.new("TextLabel")
rangeValue.Size=UDim2.fromOffset(52,34)
rangeValue.Position=UDim2.new(1,-52,0,0)
rangeValue.BackgroundColor3=Color3.fromRGB(55,112,175)
rangeValue.BorderSizePixel=0
rangeValue.Font=Enum.Font.GothamBlack
rangeValue.TextSize=11
rangeValue.TextColor3=Color3.new(1,1,1)
rangeValue.ZIndex=14
rangeValue.Parent=rangeWrap
local rvc=Instance.new("UICorner");rvc.CornerRadius=UDim.new(0,7);rvc.Parent=rangeValue

local draggingRange=false

local function updateSelectRange(value)
	value=math.clamp(math.round(value),SELECT_RANGE_MIN,SELECT_RANGE_MAX)
	selectRange=value
	pg:SetAttribute("ParkourSelectRange",value)
	local alpha=(value-SELECT_RANGE_MIN)/(SELECT_RANGE_MAX-SELECT_RANGE_MIN)
	rangeFill.Size=UDim2.fromScale(alpha,1)
	rangeKnob.Position=UDim2.new(alpha,0,.5,0)
	rangeValue.Text=tostring(value).." st"
end

local function rangeFromX(x)
	local alpha=math.clamp((x-rangeTrack.AbsolutePosition.X)/math.max(1,rangeTrack.AbsoluteSize.X),0,1)
	-- 5-stud steps.
	updateSelectRange(math.round((SELECT_RANGE_MIN+alpha*(SELECT_RANGE_MAX-SELECT_RANGE_MIN))/5)*5)
end

rangeKnob.MouseButton1Down:Connect(function() draggingRange=true end)
rangeTrack.InputBegan:Connect(function(input)
	if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
		draggingRange=true
		rangeFromX(input.Position.X)
	end
end)
UIS.InputChanged:Connect(function(input)
	if draggingRange and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
		rangeFromX(input.Position.X)
	end
end)
UIS.InputEnded:Connect(function(input)
	if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
		draggingRange=false
	end
end)
updateSelectRange(selectRange)

-- Load persistent player preferences after both sliders exist.
task.spawn(function()
	local ok,data=pcall(function()
		return prefsGet:InvokeServer()
	end)
	if ok and type(data)=="table" then
		if data.AutoSaveInterval~=nil then updateAutoSaveSlider(data.AutoSaveInterval) end
		if data.SelectRange~=nil then updateSelectRange(data.SelectRange) end
	end
end)

UIS.InputBegan:Connect(function(input,processed)
	if not listening then return end
	if input.UserInputType~=Enum.UserInputType.Keyboard then return end
	if input.KeyCode==Enum.KeyCode.Unknown then return end
	local action=listening
	local newKey=input.KeyCode.Name

	-- Keep Roblox movement controls separate from editor shortcuts.
	if reservedMovement[newKey] then
		bindingButtons[action].Text="RESERVED"
		task.delay(1,function()
			if bindingButtons[action] then bindingButtons[action].Text=pretty(binds[action]) end
		end)
		listening=nil
		return
	end

	-- Every configurable Builder action must use a unique key.
	-- If another action already owns this key, reject the change and keep
	-- the current binding unchanged.
	for otherAction,otherKey in pairs(binds) do
		if otherAction~=action and otherKey==newKey then
			listening=nil
			bindingButtons[action].Text="USED BY "..string.upper(otherAction)
			bindingButtons[action].BackgroundColor3=Color3.fromRGB(165,65,75)

			task.delay(1.2,function()
				if bindingButtons[action] then
					bindingButtons[action].Text=pretty(binds[action])
					bindingButtons[action].BackgroundColor3=Color3.fromRGB(55,112,175)
				end
			end)
			return
		end
	end

	listening=nil
	binds[action]=newKey
	bindingButtons[action].Text=pretty(binds[action])
	broadcast()
end)

reset.MouseButton1Click:Connect(function()
	for k,v in pairs(defaults) do binds[k]=v end
	autoSaveThreshold=AUTOSAVE_DEFAULT
	pg:SetAttribute("ParkourAutoSaveInterval",autoSaveThreshold)
	updateAutoSaveSlider(autoSaveThreshold)
	updateSelectRange(SELECT_RANGE_DEFAULT)
	for k,b in pairs(bindingButtons) do b.Text=pretty(binds[k]) end
	listening=nil;broadcast()
end)

local saveBusy=false
local SAVE_COOLDOWN=3

saveRemote.OnClientEvent:Connect(function(action,data)
	if action=="Loaded" and type(data)=="table" then
		for k,v in pairs(data) do
			if defaults[k] and type(v)=="string" and Enum.KeyCode[v] then binds[k]=v end
		end
		-- Older versions used W for Move, which conflicts with walking.
		if reservedMovement[binds.Move] then binds.Move="G" end
		for k,b in pairs(bindingButtons) do b.Text=pretty(binds[k]) end
		broadcast()
	elseif action=="Saved" then
		save.Text="✓ SAVED"
		task.delay(SAVE_COOLDOWN,function()
			saveBusy=false
			save.Active=true
			save.AutoButtonColor=true
			save.BackgroundTransparency=0
			save.Text="SAVE KEY BINDINGS"
		end)
	elseif action=="SaveError" then
		save.Text="SAVE FAILED"
		task.delay(1.5,function()
			saveBusy=false
			save.Active=true
			save.AutoButtonColor=true
			save.BackgroundTransparency=0
			save.Text="SAVE KEY BINDINGS"
		end)
	end
end)

saveRemote:FireServer("Load")

local settingsDirty=true
local closingSaveBusy=false

local function saveSettingsOnExit()
	if closingSaveBusy then return end
	closingSaveBusy=true

	-- Keybindings + current slider value are committed when leaving Settings.
	broadcast()
	pg:SetAttribute("ParkourAutoSaveInterval",autoSaveThreshold)
	pg:SetAttribute("ParkourSelectRange",selectRange)
	saveRemote:FireServer("Save",binds)
	prefsRemote:FireServer("Save",{
		AutoSaveInterval=autoSaveThreshold,
		SelectRange=selectRange
	})

	-- Prevent rapid close/open cycles from spamming the remote.
	task.delay(1,function()
		closingSaveBusy=false
	end)
end

local function showSettings(on)
	local wasOpen=panel.Visible
	if wasOpen and not on then
		saveSettingsOnExit()
	end
	panel.Visible=on
	shade.Visible=on
end
open.MouseButton1Click:Connect(function()showSettings(true)end)
close.MouseButton1Click:Connect(function()showSettings(false)end)
done.MouseButton1Click:Connect(function()showSettings(false)end)

-- Settings button should only appear while Discover UI is enabled.
game:GetService("RunService").RenderStepped:Connect(function()
	local d=pg:FindFirstChild("ParkourDiscoverUI")
	local discoverVisible=false

	if d and d.Enabled then
		-- Discover ScreenGui stays alive during other modes, so also require
		-- its main full-screen content to actually be visible.
		for _,obj in ipairs(d:GetChildren()) do
			if obj:IsA("Frame")
				and obj.Visible
				and obj.Size.X.Scale>=0.9
				and obj.Size.Y.Scale>=0.9 then
				discoverVisible=true
				break
			end
		end
	end

	open.Visible=discoverVisible

	-- Never leave the Settings modal floating over Builder/Test/Play mode.
	if not discoverVisible and panel.Visible then
		showSettings(false)
	end
end)

task.defer(broadcast)
print("✓ Parkour Settings / Key Bindings V1 loaded")

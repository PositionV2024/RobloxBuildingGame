-- MAKE YOUR OWN PARKOUR - CINEMATIC MENU V3
-- REPLACE ParkourMenuController with this ONE LocalScript.
-- StarterPlayer > StarterPlayerScripts > ParkourMenuController
--
-- This version builds the complete menu scene LOCALLY at runtime.
-- No Command Bar scene, MenuCamera, landmarks, or saved attributes required.

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Lighting=game:GetService("Lighting")

local player=Players.LocalPlayer
local pg=player:WaitForChild("PlayerGui")
local camera=workspace.CurrentCamera

-- Remove any old client-visible menu scene and rebuild cleanly.
local old=workspace:FindFirstChild("ParkourMenuScene")
if old then old:Destroy() end

local scene=Instance.new("Model")
scene.Name="ParkourMenuScene"
scene.Parent=workspace

local O=Vector3.new(0,700,-1200)

local function part(name,size,pos,color,material,parent)
	local p=Instance.new("Part")
	p.Name=name
	p.Size=size
	p.Position=pos
	p.Anchored=true
	p.CanCollide=false
	p.CanTouch=false
	p.CanQuery=false
	p.Color=color
	p.Material=material or Enum.Material.SmoothPlastic
	p.TopSurface=Enum.SurfaceType.Smooth
	p.BottomSurface=Enum.SurfaceType.Smooth
	p.Parent=parent or scene
	return p
end

local function glowPlatform(name,pos,size,glow)
	local m=Instance.new("Model");m.Name=name;m.Parent=scene
	local p=part("Platform",size,pos,Color3.fromRGB(68,74,84),Enum.Material.Slate,m)
	part("Glow",Vector3.new(size.X+.5,.45,size.Z+.5),pos+Vector3.new(0,size.Y/2+.12,0),glow,Enum.Material.Neon,m)
	part("Top",Vector3.new(size.X,1,size.Z),pos+Vector3.new(0,size.Y/2+.55,0),Color3.fromRGB(84,91,100),Enum.Material.Slate,m)
	return m
end

local function island(name,pos,size)
	local m=Instance.new("Model");m.Name=name;m.Parent=scene
	part("Rock",size,pos,Color3.fromRGB(60,65,72),Enum.Material.Rock,m)
	part("LowerRock",Vector3.new(size.X*.65,size.Y*.7,size.Z*.65),
		pos-Vector3.new(0,size.Y*.72,0),Color3.fromRGB(50,54,61),Enum.Material.Rock,m)
	part("Grass",Vector3.new(size.X+1,2,size.Z+1),
		pos+Vector3.new(0,size.Y/2+1,0),Color3.fromRGB(67,125,72),Enum.Material.Grass,m)
	return m
end

local function sign(text,pos,color)
	local p=part(text.."Sign",Vector3.new(36,15,2),pos,Color3.fromRGB(34,39,47),Enum.Material.Slate)
	local gui=Instance.new("SurfaceGui");gui.Face=Enum.NormalId.Front;gui.Parent=p
	local t=Instance.new("TextLabel");t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1
	t.Text=text;t.TextScaled=true;t.Font=Enum.Font.GothamBlack;t.TextColor3=color;t.Parent=gui
	local light=Instance.new("PointLight");light.Color=color;light.Range=25;light.Brightness=2;light.Parent=p
	return p
end

-- START foreground
island("StartIsland",O+Vector3.new(-100,0,70),Vector3.new(68,18,58))
glowPlatform("StartPad",O+Vector3.new(-100,12,70),Vector3.new(46,3,34),Color3.fromRGB(30,150,255))
sign("START",O+Vector3.new(-116,27,48),Color3.fromRGB(35,165,255))

-- Central tower
island("TowerIsland",O+Vector3.new(5,2,-5),Vector3.new(46,24,44))
for y=18,114,16 do
	part("TowerSection",Vector3.new(20,15,20),O+Vector3.new(5,y,-5),
		Color3.fromRGB(72,76,84),Enum.Material.Slate)
	if y%32==18 then
		part("TowerGlow",Vector3.new(24,.55,24),O+Vector3.new(5,y+8,-5),
			Color3.fromRGB(35,145,255),Enum.Material.Neon)
	end
end

-- Main route
local route={
	{-65,22,48,"blue"},{-40,31,32,"yellow"},{-15,39,18,"red"},
	{28,43,0,"blue"},{50,51,-10,"yellow"},{73,58,-22,"red"},
	{96,65,-34,"blue"}
}
local colors={
	blue=Color3.fromRGB(30,155,255),
	yellow=Color3.fromRGB(255,190,45),
	red=Color3.fromRGB(255,60,80)
}
for i,d in ipairs(route) do
	glowPlatform("Course_"..i,O+Vector3.new(d[1],d[2],d[3]),Vector3.new(16,3,16),colors[d[4]])
end

-- Hanging obstacles
for i=1,6 do
	part("Obstacle_"..i,Vector3.new(5,24,10),
		O+Vector3.new(-20+i*20,58+(i%2)*10,-42+(i%3)*12),
		Color3.fromRGB(78,83,92),Enum.Material.Slate)
end

-- Finish
island("FinishIsland",O+Vector3.new(130,22,-60),Vector3.new(54,24,48))
sign("FINISH",O+Vector3.new(130,49,-48),Color3.fromRGB(255,55,80))

-- Distant islands
for i=1,7 do
	island("BackgroundIsland_"..i,
		O+Vector3.new(-145+i*42,40+(i%3)*18,-105-(i%2)*48),
		Vector3.new(25+(i%3)*7,16+(i%2)*6,25+(i%3)*7))
end

-- Atmosphere / sky lighting
Lighting.ClockTime=17.25
Lighting.Brightness=2.5
Lighting.EnvironmentDiffuseScale=.7
Lighting.EnvironmentSpecularScale=.7

local atmosphere=Lighting:FindFirstChild("ParkourMenuAtmosphere")
if not atmosphere then
	atmosphere=Instance.new("Atmosphere")
	atmosphere.Name="ParkourMenuAtmosphere"
	atmosphere.Parent=Lighting
end
atmosphere.Density=.22
atmosphere.Haze=1.2
atmosphere.Glare=.12
atmosphere.Color=Color3.fromRGB(205,220,255)
atmosphere.Decay=Color3.fromRGB(255,188,145)

-- Exact camera composition relative to the scene WE JUST BUILT.
local cameraCF=CFrame.lookAt(
	O+Vector3.new(-175,95,185),
	O+Vector3.new(5,45,-5)
)


-- ===== V4 VISUAL UPGRADE: closer to the cinematic concept =====
local function decoPart(name,size,pos,color,material,transparency)
	local p=Instance.new("Part")
	p.Name=name;p.Size=size;p.Position=pos;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
	p.Color=color;p.Material=material or Enum.Material.SmoothPlastic;p.Transparency=transparency or 0;p.Parent=scene
	return p
end

local function addTree(pos,scale)
	decoPart("TreeTrunk",Vector3.new(3,11,3)*scale,pos+Vector3.new(0,5.5*scale,0),Color3.fromRGB(90,58,36),Enum.Material.Wood)
	for _,off in ipairs({Vector3.new(0,13,0),Vector3.new(5,11,1),Vector3.new(-5,11,0),Vector3.new(2,15,3)}) do
		local l=decoPart("TreeLeaves",Vector3.new(10,8,10)*scale,pos+off*scale,Color3.fromRGB(48,112,57),Enum.Material.Grass)
		l.Shape=Enum.PartType.Ball
	end
end

local function addLantern(pos)
	decoPart("LanternPost",Vector3.new(1,7,1),pos+Vector3.new(0,3.5,0),Color3.fromRGB(65,48,35),Enum.Material.Wood)
	local lamp=decoPart("Lantern",Vector3.new(2.5,3,2.5),pos+Vector3.new(0,7.5,0),Color3.fromRGB(255,170,55),Enum.Material.Neon)
	local light=Instance.new("PointLight");light.Color=Color3.fromRGB(255,165,60);light.Range=24;light.Brightness=2.5;light.Parent=lamp
end

-- Trees and warm lanterns on hero islands.
addTree(O+Vector3.new(-150,15,100),1.0)
addTree(O+Vector3.new(150,42,-80),.9)
addTree(O+Vector3.new(-55,74,-125),.7)
addTree(O+Vector3.new(105,69,-155),.7)
addLantern(O+Vector3.new(-154,15,105))
addLantern(O+Vector3.new(-96,15,103))
addLantern(O+Vector3.new(122,42,-49))
addLantern(O+Vector3.new(168,42,-49))

-- Waterfalls on central and finish islands.
for i,data in ipairs({
	{O+Vector3.new(18,-18,19),10,62},
	{O+Vector3.new(151,-2,-40),12,75},
	{O+Vector3.new(-55,38,-103),8,48}
	}) do
	local w=decoPart("Waterfall_"..i,Vector3.new(data[2],data[3],1),data[1],Color3.fromRGB(105,190,255),Enum.Material.Glass,.28)
	local light=Instance.new("PointLight");light.Color=Color3.fromRGB(100,180,255);light.Range=16;light.Brightness=.7;light.Parent=w
end

-- Cloud sea.
for i=1,22 do
	local x=-250+(i*37)%500
	local z=-60-((i*59)%230)
	local y=-28+(i%4)*9
	local cloud=decoPart("Cloud_"..i,Vector3.new(42+(i%3)*16,15+(i%2)*7,30+(i%4)*7),
		O+Vector3.new(x,y,z),Color3.fromRGB(235,240,255),Enum.Material.SmoothPlastic,.62)
	cloud.Shape=Enum.PartType.Ball
end

-- Extra route pieces to make the scene denser like the concept.
local extraColors={Color3.fromRGB(30,155,255),Color3.fromRGB(255,188,45),Color3.fromRGB(255,60,80)}
for i=1,10 do
	local ang=i*.72
	local pos=O+Vector3.new(-25+i*18,72+(i%3)*8,-75-math.sin(ang)*30)
	local p=decoPart("ShowcasePlatform_"..i,Vector3.new(12,3,12),pos,Color3.fromRGB(72,76,84),Enum.Material.Slate)
	local glow=decoPart("ShowcaseGlow_"..i,Vector3.new(12.5,.4,12.5),pos+Vector3.new(0,1.7,0),extraColors[(i-1)%3+1],Enum.Material.Neon)
end

-- Better post-processing.
local bloom=Lighting:FindFirstChild("ParkourMenuBloom") or Instance.new("BloomEffect")
bloom.Name="ParkourMenuBloom";bloom.Intensity=.75;bloom.Size=28;bloom.Threshold=1.1;bloom.Parent=Lighting
local cc=Lighting:FindFirstChild("ParkourMenuColor") or Instance.new("ColorCorrectionEffect")
cc.Name="ParkourMenuColor";cc.Brightness=.035;cc.Contrast=.10;cc.Saturation=.15;cc.TintColor=Color3.fromRGB(255,235,220);cc.Parent=Lighting
Lighting.ClockTime=17.35
Lighting.Brightness=3
Lighting.Ambient=Color3.fromRGB(105,112,130)
Lighting.OutdoorAmbient=Color3.fromRGB(125,130,145)

local active=false
local hidden={}
local oldWalk,oldJump=16,50

local function discoverOpen()
	local gui=pg:FindFirstChild("ParkourDiscoverUI")
	if not gui or not gui.Enabled then return false end
	for _,f in ipairs(gui:GetChildren()) do
		if f:IsA("Frame") and f.Visible
			and f.AbsoluteSize.X>camera.ViewportSize.X*.8
			and f.AbsoluteSize.Y>camera.ViewportSize.Y*.8 then
			return true
		end
	end
	return false
end

local function hideCharacter()
	local char=player.Character
	if not char then return end
	local hum=char:FindFirstChildOfClass("Humanoid")
	if hum then
		oldWalk=hum.WalkSpeed;oldJump=hum.JumpPower
		hum.WalkSpeed=0;hum.JumpPower=0;hum.AutoRotate=false
	end
	hidden={}
	for _,o in ipairs(char:GetDescendants()) do
		if o:IsA("BasePart") then
			hidden[o]=o.LocalTransparencyModifier
			o.LocalTransparencyModifier=1
		end
	end
end

local function restore()
	local char=player.Character
	local hum=char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed=oldWalk;hum.JumpPower=oldJump;hum.AutoRotate=true
	end
	for p,v in pairs(hidden) do if p and p.Parent then p.LocalTransparencyModifier=v end end
	hidden={}
	camera.CameraType=Enum.CameraType.Custom
	if hum then camera.CameraSubject=hum end
end

RunService:BindToRenderStep("ParkourCinematicMenuV3",Enum.RenderPriority.Camera.Value+50,function()
	local open=discoverOpen()
	if open and not active then active=true;hideCharacter()
	elseif not open and active then active=false;restore() end

	if active then
		camera.CameraType=Enum.CameraType.Scriptable

		-- CINEMATIC SHOWCASE ORBIT V3.4
		-- 36-second lap with smooth acceleration/deceleration around
		-- important views rather than a constant mechanical spin.
		local LAP_TIME=36
		local raw=(os.clock()%LAP_TIME)/LAP_TIME

		-- Smooth periodic time warp. This makes the camera linger around
		-- the front/side showcase angles and glide through transitions.
		local phase=raw*math.pi*2
		local angle=phase - math.sin(phase*2)*0.11

		local focus=O+Vector3.new(5,45,-5)

		-- Wide elliptical path.
		local radiusX=205
		local radiusZ=180

		-- Gentle crane motion: high around tower views, lower near START/FINISH.
		local height=
			91
			+math.sin(angle*2-.6)*11
			+math.sin(angle*3+.8)*3

		local orbitPos=focus+Vector3.new(
			math.cos(angle)*radiusX,
			height,
			math.sin(angle)*radiusZ
		)

		-- The aim point subtly travels across the course instead of
		-- staring rigidly at one exact point.
		local lookAt=focus+Vector3.new(
			math.sin(angle*.5)*13,
			5+math.sin(angle*2)*5,
			math.cos(angle*.5)*7
		)

		-- Tiny cinematic bank during sweeping turns.
		local baseLook=CFrame.lookAt(orbitPos,lookAt)
		local roll=math.rad(math.sin(angle)*1.2)

		camera.CFrame=baseLook*CFrame.Angles(0,0,roll)
		camera.Focus=CFrame.new(lookAt)

		-- Slight FOV breathing gives wide establishing views and tighter hero shots.
		camera.FieldOfView=68+math.sin(angle*2-.4)*3
	end
end)

print("✓ CINEMATIC MENU V4 — CINEMATIC SKY REALM")
print("StartIsland parts:",#scene.StartIsland:GetChildren())
print("TowerIsland parts:",#scene.TowerIsland:GetChildren())
print("FinishIsland parts:",#scene.FinishIsland:GetChildren())

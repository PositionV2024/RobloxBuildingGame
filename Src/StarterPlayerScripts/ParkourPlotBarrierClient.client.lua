-- ParkourPlotBarrierClient V6.4 - INTEGRATED COLOR SWATCHES
-- Full replacement for ParkourPlotBarrierClient V6.3.
-- Keeps DEFAULT / PULSE_WAVE, animated style cards and the existing remote.
-- Color swatches use the SAME COLOR_PRESETS as the actual barrier.
-- Selecting a swatch only updates pending settings + the miniature previews.
-- APPLY still sends the same Save payload to ParkourBarrierSettingsServer V4.
-- No new DataStore, UI-state table, image asset or ModuleScript is required.
-- Put this LocalScript in:
-- StarterPlayer > StarterPlayerScripts
--
-- Uses your EXISTING marker setup:
-- Workspace
-- └── ParkourCreator
--     └── BarrierMarkers
--         ├── Front
--         ├── Back
--         ├── Left
--         └── Right
--
-- IMPORTANT:
-- The X size of each marker controls that wall's LENGTH.
-- Move / rotate / resize the marker and the barrier follows LIVE.
--
-- This client does not change ParkourBuilderClient or plot/draft saves.
-- Barrier persistence remains server-side through ParkourBarrierSettingsEvent.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local barrierSettingsRemote = RS:WaitForChild("ParkourBarrierSettingsEvent")

local function canEditBarrier()
	-- Prefer the server-authoritative owner UserId stored on Workspace.
	local ownerUserId=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))
	if ownerUserId and ownerUserId==player.UserId then
		return true
	end

	-- Attribute fallback for the short replication window during arrival.
	if player:GetAttribute("ParkourCreatorOwner")==true then
		return true
	end

	-- Keep Studio CREATE simulation working.
	if RunService:IsStudio()
		and player:GetAttribute("ParkourPrivateCreator")==true then
		return true
	end

	return false
end
local playerGui = player:WaitForChild("PlayerGui")

local creator = workspace:WaitForChild("ParkourCreator")
local markersFolder = creator:WaitForChild("BarrierMarkers")

local MARKER_NAMES = {"Front","Back","Left","Right"}

-- =========================================================
-- EASY SETTINGS - CHANGE ONLY THESE
-- =========================================================
local CONFIG = {
	Style = "DEFAULT",         -- DEFAULT / PULSE_WAVE
	WaveAmplitude = 1.8,       -- Pulse Wave height
	Arrows = true,             -- true / false
	Facing = "RIGHT",          -- "LEFT" / "RIGHT"
	Move = "RIGHT",            -- "UP" / "DOWN" / "LEFT" / "RIGHT"
	Speed = 5,                 -- arrow movement speed
	Spacing = 8,               -- horizontal spacing between arrow groups
	TrailCount = 4,            -- extra arrows behind main arrow
	TrailGap = 1.35,           -- distance between trailing arrows
	Glow = 0.25,               -- 0 = very soft, 1 = original bright neon
	ClickRange = 35,            -- max studs from character to barrier
}

-- Internal visual values. Normally you do not need to change these.
local WALL_HEIGHT, PANEL_THICKNESS = 8, .28
local RAIL_HEIGHT, RAIL_DEPTH = .28, .55
local POST_WIDTH, POST_EXTRA_HEIGHT = 1.6, 2.4
local CHEVRON_WIDTH, CHEVRON_HEIGHT = 2.7, .42
local COLOR_PRESETS = {
	BLUE={Color3.fromRGB(30,105,155),Color3.fromRGB(70,165,185),Color3.fromRGB(150,205,215),Color3.fromRGB(45,120,165)},
	CYAN={Color3.fromRGB(25,125,145),Color3.fromRGB(65,185,195),Color3.fromRGB(155,220,220),Color3.fromRGB(35,140,155)},
	GREEN={Color3.fromRGB(35,120,75),Color3.fromRGB(80,175,115),Color3.fromRGB(165,215,180),Color3.fromRGB(45,135,85)},
	PURPLE={Color3.fromRGB(90,55,145),Color3.fromRGB(145,105,185),Color3.fromRGB(205,175,220),Color3.fromRGB(105,70,155)},
	PINK={Color3.fromRGB(145,65,110),Color3.fromRGB(185,105,145),Color3.fromRGB(225,180,205),Color3.fromRGB(155,75,120)},
	RED={Color3.fromRGB(145,55,55),Color3.fromRGB(185,95,90),Color3.fromRGB(225,175,165),Color3.fromRGB(155,65,60)},
	ORANGE={Color3.fromRGB(150,85,35),Color3.fromRGB(190,125,70),Color3.fromRGB(225,190,150),Color3.fromRGB(160,95,45)},
	GOLD={Color3.fromRGB(145,115,35),Color3.fromRGB(185,155,75),Color3.fromRGB(225,210,155),Color3.fromRGB(155,125,45)},
	WHITE={Color3.fromRGB(120,130,140),Color3.fromRGB(175,185,190),Color3.fromRGB(220,225,225),Color3.fromRGB(135,145,150)},
}
local currentColor="BLUE"
local selectedColors=COLOR_PRESETS[currentColor]
local PANEL_COLOR,RAIL_COLOR,HOT_COLOR,POST_COLOR=table.unpack(selectedColors)
local ARROW_TRAVEL_HEIGHT = WALL_HEIGHT - 1.5
-- Arrow facing is read live from CONFIG.Facing in the animation loop.

-- =========================================================
-- CLEAN OLD VERSION
-- =========================================================
local old = workspace:FindFirstChild("LocalParkourPlotBarrier")
if old then old:Destroy() end

local root = Instance.new("Folder")
root.Name = "LocalParkourPlotBarrier"
root.Parent = workspace

local walls = {}

local barrierHighlight=Instance.new("Highlight")
barrierHighlight.Name="BarrierHoverHighlight"
barrierHighlight.Adornee=root
barrierHighlight.DepthMode=Enum.HighlightDepthMode.Occluded
barrierHighlight.FillColor=Color3.fromRGB(120,205,235)
barrierHighlight.FillTransparency=.88
barrierHighlight.OutlineColor=Color3.fromRGB(200,240,255)
barrierHighlight.OutlineTransparency=.15
barrierHighlight.Enabled=false
barrierHighlight.Parent=root

-- =========================================================
-- HELPERS
-- =========================================================
local function makePart(name,parent,color,material,transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p:SetAttribute("ParkourBarrier",true)
	p.CastShadow = false
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.Parent = parent
	return p
end

local function addLight(part,brightness,range)
	local light = Instance.new("PointLight")
	light.Color = RAIL_COLOR
	light:SetAttribute("BaseBrightness",brightness)
	light:SetAttribute("BaseRange",range)
	light.Brightness = brightness * CONFIG.Glow
	light.Range = range * (.45 + .55*CONFIG.Glow)
	light.Shadows = false
	light.Parent = part
	return light
end

local function addSparkEmitter(part)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "EnergySparks"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, HOT_COLOR),
		ColorSequenceKeypoint.new(1, RAIL_COLOR)
	})
	emitter.LightEmission = .35 * CONFIG.Glow
	emitter.Rate = math.max(1,math.floor(3*CONFIG.Glow))
	emitter.Lifetime = NumberRange.new(.35,.8)
	emitter.Speed = NumberRange.new(.5,2.2)
	emitter.SpreadAngle = Vector2.new(35,35)
	emitter.Rotation = NumberRange.new(0,360)
	emitter.RotSpeed = NumberRange.new(-90,90)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0,.18),
		NumberSequenceKeypoint.new(.5,.08),
		NumberSequenceKeypoint.new(1,0)
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,.15),
		NumberSequenceKeypoint.new(1,1)
	})
	emitter.Parent = part
	return emitter
end

-- =========================================================
-- WALL CREATION
-- =========================================================
local function createWall(name,marker)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = root

	local panel = makePart(
		"EnergyPanel",
		folder,
		PANEL_COLOR,
		Enum.Material.ForceField,
		.42
	)

	local topRail = makePart(
		"TopRail",
		folder,
		RAIL_COLOR,
		Enum.Material.Neon,
		.22
	)

	local bottomRail = makePart(
		"BottomRail",
		folder,
		RAIL_COLOR,
		Enum.Material.Neon,
		.22
	)

	-- Inner luminous strips make the rails look layered/thicker.
	local topCore = makePart(
		"TopRailCore",
		folder,
		HOT_COLOR,
		Enum.Material.Neon,
		.28
	)

	local bottomCore = makePart(
		"BottomRailCore",
		folder,
		HOT_COLOR,
		Enum.Material.Neon,
		.28
	)

	addLight(topRail,1.15,11)
	addLight(bottomRail,.7,8)

	walls[name] = {
		marker = marker,
		folder = folder,
		panel = panel,
		topRail = topRail,
		bottomRail = bottomRail,
		topCore = topCore,
		bottomCore = bottomCore,
		chevrons = {},
		waveBands = {},
		lastLength = -1,
		lastWaveLength = -1,
		activeStyle = nil,
		phase = math.random()*math.pi*2
	}
end

local function clearChevrons(data)
	for _,item in ipairs(data.chevrons) do
		if item.left then item.left:Destroy() end
		if item.right then item.right:Destroy() end
		for _,trail in ipairs(item.trails or {}) do
			if trail.left then trail.left:Destroy() end
			if trail.right then trail.right:Destroy() end
		end
	end
	table.clear(data.chevrons)
end

local function rebuildChevrons(data,length)
	clearChevrons(data)
	data.lastLength=length

	if not CONFIG.Arrows then
		return
	end

	local count = math.max(2,math.floor(length/CONFIG.Spacing))

	for i=1,count do
		local left = makePart(
			"ChevronLeft_"..i,
			data.folder,
			HOT_COLOR,
			Enum.Material.Neon,
			.04
		)

		local right = makePart(
			"ChevronRight_"..i,
			data.folder,
			HOT_COLOR,
			Enum.Material.Neon,
			.04
		)

		left.Size = Vector3.new(CHEVRON_WIDTH,CHEVRON_HEIGHT,.12)
		right.Size = Vector3.new(CHEVRON_WIDTH,CHEVRON_HEIGHT,.12)

		local trails={}
		for trailIndex=1,CONFIG.TrailCount do
			local trailLeft=makePart(
				"ChevronTrailLeft_"..i.."_"..trailIndex,
				data.folder,
				HOT_COLOR,
				Enum.Material.Neon,
				.08
			)

			local trailRight=makePart(
				"ChevronTrailRight_"..i.."_"..trailIndex,
				data.folder,
				HOT_COLOR,
				Enum.Material.Neon,
				.08
			)

			trailLeft.Size=Vector3.new(CHEVRON_WIDTH,CHEVRON_HEIGHT,.12)
			trailRight.Size=Vector3.new(CHEVRON_WIDTH,CHEVRON_HEIGHT,.12)

			table.insert(trails,{
				left=trailLeft,
				right=trailRight,
				trailIndex=trailIndex
			})
		end

		table.insert(data.chevrons,{
			left=left,
			right=right,
			trails=trails,
			index=i,
			count=count,
			phase=i*.85
		})
	end

end

-- =========================================================
-- PULSE WAVE STYLE
-- Smooth local neon segments approximate flowing sine waves.
-- =========================================================
local WAVE_SAMPLES=30
local WAVE_THICKNESS=.14

local function clearWaves(data)
	for _,band in ipairs(data.waveBands or {}) do
		for _,segment in ipairs(band) do
			if segment then segment:Destroy() end
		end
	end
	data.waveBands={}
	data.lastWaveLength=-1
end

local function rebuildWaves(data,length)
	clearWaves(data)

	local bandCount=math.clamp(math.max(1,CONFIG.TrailCount),1,5)
	for bandIndex=1,bandCount do
		local band={}
		for sample=1,WAVE_SAMPLES-1 do
			local segment=makePart(
				"PulseWave_"..bandIndex.."_"..sample,
				data.folder,
				HOT_COLOR,
				Enum.Material.Neon,
				.12
			)
			segment.CanQuery=false
			segment:SetAttribute("PulseWave",true)
			table.insert(band,segment)
		end
		table.insert(data.waveBands,band)
	end

	data.lastWaveLength=length
end

local function setSegmentBetween(segment,p1,p2,wallNormal)
	local delta=p2-p1
	local distance=delta.Magnitude
	if distance<=.001 then
		segment.Transparency=1
		return
	end

	local right=delta.Unit
	local back=wallNormal.Unit
	local up=back:Cross(right)
	if up.Magnitude<=.001 then up=Vector3.yAxis else up=up.Unit end

	segment.Size=Vector3.new(distance+.08,WAVE_THICKNESS,.10)
	segment.CFrame=CFrame.fromMatrix((p1+p2)/2,right,up,back)
end

local function updatePulseWaves(data,length,cf,t)
	if math.abs(length-data.lastWaveLength)>.02
		or #data.waveBands~=math.clamp(math.max(1,CONFIG.TrailCount),1,5) then
		rebuildWaves(data,length)
	end

	local direction=string.upper(CONFIG.Move)
	local vertical=(direction=="UP" or direction=="DOWN")
	local sign=(direction=="LEFT" or direction=="DOWN") and -1 or 1
	local phase=-t*CONFIG.Speed*.85*sign
	local bandCount=#data.waveBands
	local amplitude=math.clamp(CONFIG.WaveAmplitude,.5,3)
	local maxY=WALL_HEIGHT/2-.45
	local maxX=math.max(.5,length/2-.45)

	for bandIndex,band in ipairs(data.waveBands) do
		local bandOffset=(bandIndex-(bandCount+1)/2)*.72

		for sample,segment in ipairs(band) do
			local a0=(sample-1)/(WAVE_SAMPLES-1)
			local a1=sample/(WAVE_SAMPLES-1)
			local p0Local,p1Local

			if vertical then
				local y0=-WALL_HEIGHT/2+a0*WALL_HEIGHT
				local y1=-WALL_HEIGHT/2+a1*WALL_HEIGHT
				local x0=math.clamp(
					bandOffset+math.sin(y0*.82+phase+bandIndex*.42)*amplitude,
					-maxX,maxX
				)
				local x1=math.clamp(
					bandOffset+math.sin(y1*.82+phase+bandIndex*.42)*amplitude,
					-maxX,maxX
				)
				p0Local=Vector3.new(x0,y0,-PANEL_THICKNESS*.70)
				p1Local=Vector3.new(x1,y1,-PANEL_THICKNESS*.70)
			else
				local x0=-length/2+a0*length
				local x1=-length/2+a1*length
				local y0=math.clamp(
					bandOffset+math.sin(x0*.55+phase+bandIndex*.42)*amplitude,
					-maxY,maxY
				)
				local y1=math.clamp(
					bandOffset+math.sin(x1*.55+phase+bandIndex*.42)*amplitude,
					-maxY,maxY
				)
				p0Local=Vector3.new(x0,y0,-PANEL_THICKNESS*.70)
				p1Local=Vector3.new(x1,y1,-PANEL_THICKNESS*.70)
			end

			local p0=cf:PointToWorldSpace(p0Local)
			local p1=cf:PointToWorldSpace(p1Local)
			setSegmentBetween(segment,p0,p1,cf.ZVector)

			local glow=math.clamp(CONFIG.Glow,0,1)
			local distanceFromLead=(bandIndex-1)/math.max(1,bandCount-1)
			segment.Transparency=math.clamp(.48-(glow*.40)+distanceFromLead*.18,0,1)
			segment.Color=HOT_COLOR
		end
	end
end

-- =========================================================
-- BUILD FOUR SIDES
-- =========================================================
for _,name in ipairs(MARKER_NAMES) do
	local marker = markersFolder:WaitForChild(name)

	if not marker:IsA("BasePart") then
		error("BarrierMarkers."..name.." must be a BasePart")
	end

	createWall(name,marker)
end

-- =========================================================
-- CORNER POSTS
-- Posts are derived from wall endpoints, but merged when
-- Front/Back/Left/Right meet at the same corner.
-- =========================================================
local cornerFolder = Instance.new("Folder")
cornerFolder.Name = "CornerPosts"
cornerFolder.Parent = root

local cornerPosts = {}

local function cornerKey(v)
	return string.format(
		"%d_%d_%d",
		math.round(v.X*4),
		math.round(v.Y*4),
		math.round(v.Z*4)
	)
end

local function createPost(position,index)
	local holder = Instance.new("Folder")
	holder.Name = "Post_"..index
	holder.Parent = cornerFolder

	local post = makePart(
		"Post",
		holder,
		POST_COLOR,
		Enum.Material.Neon,
		.03
	)

	post.Size = Vector3.new(
		POST_WIDTH,
		WALL_HEIGHT+POST_EXTRA_HEIGHT,
		POST_WIDTH
	)
	post.CFrame = CFrame.new(position)

	local core = makePart(
		"Core",
		holder,
		HOT_COLOR,
		Enum.Material.Neon,
		.08
	)
	core.Size = Vector3.new(
		POST_WIDTH*.34,
		WALL_HEIGHT+POST_EXTRA_HEIGHT+.2,
		POST_WIDTH*.34
	)
	core.CFrame = post.CFrame

	local cap = makePart(
		"Cap",
		holder,
		HOT_COLOR,
		Enum.Material.Neon,
		.01
	)
	cap.Size = Vector3.new(POST_WIDTH*1.35,.35,POST_WIDTH*1.35)
	cap.CFrame = post.CFrame*CFrame.new(
		0,
		(WALL_HEIGHT+POST_EXTRA_HEIGHT)/2+.18,
		0
	)

	local light = addLight(post,2.2,16)
	addSparkEmitter(cap)

	return {
		holder=holder,
		post=post,
		core=core,
		cap=cap,
		light=light,
		phase=index*1.15
	}
end

local function rebuildPosts()
	for _,p in pairs(cornerPosts) do
		if p.holder then p.holder:Destroy() end
	end
	table.clear(cornerPosts)

	local seen = {}
	local index = 0

	for _,name in ipairs(MARKER_NAMES) do
		local marker = markersFolder:FindFirstChild(name)

		if marker and marker:IsA("BasePart") then
			local half = marker.Size.X/2

			for _,x in ipairs({-half,half}) do
				local endpoint =
					marker.CFrame:PointToWorldSpace(Vector3.new(x,0,0))

				local key = cornerKey(endpoint)

				if not seen[key] then
					seen[key] = true
					index += 1
					cornerPosts[key] = createPost(endpoint,index)
				end
			end
		end
	end
end

rebuildPosts()

-- =========================================================
-- LIVE UPDATE
-- =========================================================
local started = os.clock()
local lastPostRefresh = 0

RunService.RenderStepped:Connect(function()
	if not root.Parent then return end

	local t = os.clock()-started
	local markerChanged = false

	for _,name in ipairs(MARKER_NAMES) do
		local data = walls[name]
		local marker = data.marker

		if marker and marker.Parent then
			local length = math.max(1,marker.Size.X)
			local cf = marker.CFrame

			if data.activeStyle~=CONFIG.Style then
				clearChevrons(data)
				clearWaves(data)
				data.lastLength=-1
				data.lastWaveLength=-1
				data.activeStyle=CONFIG.Style
			end

			if CONFIG.Style=="DEFAULT" then
				if math.abs(length-data.lastLength)>.02 then
					rebuildChevrons(data,length)
					markerChanged=true
				end
			elseif CONFIG.Style=="PULSE_WAVE" then
				updatePulseWaves(data,length,cf,t)
			end

			-- Energy glass panel.
			data.panel.Size =
				Vector3.new(length,WALL_HEIGHT,PANEL_THICKNESS)
			data.panel.CFrame = cf

			-- Thick glowing top/bottom rails.
			data.topRail.Size =
				Vector3.new(length+.3,RAIL_HEIGHT,RAIL_DEPTH)
			data.topRail.CFrame =
				cf*CFrame.new(0,WALL_HEIGHT/2,0)

			data.bottomRail.Size =
				Vector3.new(length+.3,RAIL_HEIGHT,RAIL_DEPTH)
			data.bottomRail.CFrame =
				cf*CFrame.new(0,-WALL_HEIGHT/2,0)

			data.topCore.Size =
				Vector3.new(length+.35,.08,.18)
			data.topCore.CFrame =
				cf*CFrame.new(0,WALL_HEIGHT/2+.03,-.05)

			data.bottomCore.Size =
				Vector3.new(length+.35,.08,.18)
			data.bottomCore.CFrame =
				cf*CFrame.new(0,-WALL_HEIGHT/2+.03,-.05)

			-- Large animated chevrons (DEFAULT style only).
			if CONFIG.Style=="DEFAULT" then
				for _,item in ipairs(data.chevrons) do
					local x =
						-length/2+
						(item.index/(item.count+1))*length

					-- Move each chevron pair UP the energy wall continuously.
					-- item.phase spaces the arrows so they do not all rise together.
					local moveDirection=string.upper(CONFIG.Move)
					local vertical=(moveDirection=="UP" or moveDirection=="DOWN")
					local travelDistance=vertical and ARROW_TRAVEL_HEIGHT or math.max(1,length-3)
					local moveSign=(moveDirection=="DOWN" or moveDirection=="LEFT") and -1 or 1
					local phaseOffset=(item.index-1)*(travelDistance/math.max(1,item.count))
					local travelPos=-travelDistance/2
						+((t*CONFIG.Speed*moveSign+phaseOffset)%travelDistance)

					local movingX=vertical and x or travelPos
					local movingY=vertical and travelPos or 0

					local facingName=string.upper(CONFIG.Facing)

					-- The base chevron geometry points RIGHT.
					-- Rotate the entire chevron for the other three directions.
					local facingRotation=0
					if facingName=="LEFT" then
						facingRotation=math.rad(180)
					elseif facingName=="UP" then
						facingRotation=math.rad(90)
					elseif facingName=="DOWN" then
						facingRotation=math.rad(-90)
					end

					-- Keep the base > geometry identical for every direction.
					-- Only facingRotation changes its final orientation.
					local facing=1

					-- Explicitly mirror the chevron shape.
					-- RIGHT: upper/lower strokes form >
					-- LEFT:  upper/lower strokes form <
					-- Build a complete RIGHT-facing chevron around one pivot,
					-- then rotate the whole shape. Rotating only each stroke caused
					-- UP/DOWN to become a vertical zig-zag.
					local arrowPivot =
						cf
						*CFrame.new(movingX,movingY,-PANEL_THICKNESS)
						*CFrame.Angles(0,0,facingRotation)

					item.left.CFrame =
						arrowPivot
						*CFrame.new(-.72,-.72,0)
						*CFrame.Angles(0,0,math.rad(48))

					item.right.CFrame =
						arrowPivot
						*CFrame.new(-.72,.72,0)
						*CFrame.Angles(0,0,math.rad(-48))

					local arrowGlow=math.clamp(CONFIG.Glow,0,1)
					local mainArrowTransparency=.72-(arrowGlow*.68)
					item.left.Transparency=mainArrowTransparency
					item.right.Transparency=mainArrowTransparency

					-- Multiple trailing arrow rows follow behind the main arrow.
					for _,trail in ipairs(item.trails or {}) do
						local trailPos=-travelDistance/2
							+((t*CONFIG.Speed*moveSign+phaseOffset
								-(CONFIG.TrailGap*trail.trailIndex)*moveSign)
								%travelDistance)

						local trailX=vertical and x or trailPos
						local trailY=vertical and trailPos or 0

						local trailPivot =
							cf
							*CFrame.new(trailX,trailY,-PANEL_THICKNESS-.02)
							*CFrame.Angles(0,0,facingRotation)

						trail.left.CFrame =
							trailPivot
							*CFrame.new(-.72,-.72,0)
							*CFrame.Angles(0,0,math.rad(48))

						trail.right.CFrame =
							trailPivot
							*CFrame.new(-.72,.72,0)
							*CFrame.Angles(0,0,math.rad(-48))

						local trailNormalized=
							(trailPos+travelDistance/2)/travelDistance
						local trailEdgeFade=
							math.min(
								trailNormalized/.15,
								(1-trailNormalized)/.15,
								1
							)

						-- Farther trailing arrows are slightly dimmer.
						local baseFade=math.min(.28,.05*trail.trailIndex)
						local trailTr=
							(.72-(math.clamp(CONFIG.Glow,0,1)*.52))
							+baseFade+(1-trailEdgeFade)*.30

						trail.left.Transparency=math.clamp(trailTr,0,1)
						trail.right.Transparency=math.clamp(trailTr,0,1)
					end
				end
			end

			-- Force-field breathing effect.
			local pulse =
				(math.sin(t*2.1+data.phase)+1)/2

			-- Glow is applied HERE every frame so RenderStepped cannot overwrite it.
			-- 0 = muted/subtle barrier, 1 = strongest visual glow.
			local glow=math.clamp(CONFIG.Glow,0,1)
			if CONFIG.Style=="PULSE_WAVE" then
				data.panel.Transparency=math.clamp(.82-(glow*.22)+pulse*.04,0,1)
			else
				data.panel.Transparency=math.clamp(.68-(glow*.30)+pulse*(.08+.09*glow),0,1)
			end
			data.topRail.Transparency=math.clamp(.58-(glow*.40)+pulse*(.05+.07*glow),0,1)
			data.bottomRail.Transparency=data.topRail.Transparency
			data.topCore.Transparency=math.clamp(.72-(glow*.50)+pulse*.05,0,1)
			data.bottomCore.Transparency=data.topCore.Transparency
		end
	end

	-- Refresh corner locations a few times per second.
	-- This lets the posts follow when markers are moved/resized.
	if t-lastPostRefresh>.2 then
		rebuildPosts()
		lastPostRefresh=t
	end

	-- Strong pillar pulse + vertical energy feel.
	for _,data in pairs(cornerPosts) do
		if data.post and data.post.Parent then
			local pulse =
				(math.sin(t*3.2+data.phase)+1)/2

			local glow=math.clamp(CONFIG.Glow,0,1)
			data.post.Transparency=math.clamp(.58-(glow*.50)+pulse*.08,0,1)
			data.core.Transparency=math.clamp(.68-(glow*.60)+pulse*.08,0,1)
			data.cap.Transparency=math.clamp(.62-(glow*.58)+pulse*.06,0,1)
			local baseBrightness=data.light:GetAttribute("BaseBrightness") or 2.2
			local baseRange=data.light:GetAttribute("BaseRange") or 16
			data.light.Brightness=baseBrightness*glow*(.75+pulse*.25)
			data.light.Range=baseRange*(.45+.55*glow)
		end
	end
end)


-- =========================================================
-- SAVED BARRIER SETTINGS
-- =========================================================
local function applyBarrierSettings(data)
	if type(data)~="table" then return end

	local style=tostring(data.Style or "DEFAULT"):upper()
	if style=="DEFAULT" or style=="PULSE_WAVE" then CONFIG.Style=style end
	if type(data.WaveAmplitude)=="number" then
		CONFIG.WaveAmplitude=math.clamp(data.WaveAmplitude,.5,3)
	end

	if type(data.Color)=="string" and COLOR_PRESETS[string.upper(data.Color)] then
		currentColor=string.upper(data.Color)
	end
	if type(data.Glow)=="number" then CONFIG.Glow=math.clamp(data.Glow,0,1) end
	if type(data.Speed)=="number" then CONFIG.Speed=math.clamp(data.Speed,1,15) end
	if type(data.Spacing)=="number" then CONFIG.Spacing=math.clamp(math.round(data.Spacing),4,20) end
	if type(data.TrailCount)=="number" then CONFIG.TrailCount=math.clamp(math.round(data.TrailCount),0,8) end

	local move=tostring(data.Direction or ""):upper()
	if move=="UP" or move=="DOWN" or move=="LEFT" or move=="RIGHT" then
		CONFIG.Move=move
	end

	local facing=tostring(data.Facing or ""):upper()
	if facing=="UP" or facing=="DOWN" or facing=="LEFT" or facing=="RIGHT" then
		CONFIG.Facing=facing
	end

	-- Force active style geometry to rebuild after loading.
	for _,wall in pairs(walls) do
		wall.lastLength=-1
		wall.lastWaveLength=-1
		wall.activeStyle=nil
	end
end

-- =========================================================
-- BARRIER COLOR & SETTINGS UI
-- Uses the existing pending settings and server-side barrier persistence.
-- =========================================================

local DEFAULTS={
	Style="DEFAULT",
	WaveAmplitude=1.8,
	Glow=.25,
	Speed=5,
	Spacing=8,
	TrailCount=4,
	Direction="RIGHT",
	Facing="RIGHT",
	Color="BLUE",
}

local pending={
	Style=CONFIG.Style,
	WaveAmplitude=CONFIG.WaveAmplitude,
	Glow=CONFIG.Glow,
	Speed=CONFIG.Speed,
	Spacing=CONFIG.Spacing,
	TrailCount=CONFIG.TrailCount,
	Direction=CONFIG.Move,
	Facing=CONFIG.Facing,
	Color=currentColor,
}

local function recolorBarrier(name)
	local colors=COLOR_PRESETS[name]
	if not colors then return end

	currentColor=name
	PANEL_COLOR,RAIL_COLOR,HOT_COLOR,POST_COLOR=table.unpack(colors)

	for _,obj in ipairs(root:GetDescendants()) do
		if obj:IsA("BasePart") then
			if obj.Name=="EnergyPanel" then
				obj.Color=PANEL_COLOR
			elseif obj.Name=="TopRail" or obj.Name=="BottomRail" then
				obj.Color=RAIL_COLOR
			elseif obj.Name=="Post" then
				obj.Color=POST_COLOR
			else
				obj.Color=HOT_COLOR
			end
		elseif obj:IsA("PointLight") then
			obj.Color=RAIL_COLOR
		elseif obj:IsA("ParticleEmitter") then
			obj.Color=ColorSequence.new({
				ColorSequenceKeypoint.new(0,HOT_COLOR),
				ColorSequenceKeypoint.new(1,RAIL_COLOR)
			})
		end
	end
end

local gui=Instance.new("ScreenGui")
gui.Name="ParkourBarrierSettingsUI"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.DisplayOrder=1200
gui.Parent=playerGui

local modal=Instance.new("Frame")
modal.Name="Modal"
modal.AnchorPoint=Vector2.new(.5,.5)
modal.Position=UDim2.fromScale(.5,.5)
modal.Size=UDim2.fromOffset(560,720)
modal.BackgroundColor3=Color3.fromRGB(7,25,40)
modal.BorderSizePixel=0
modal.Visible=false
modal.Parent=gui

local mc=Instance.new("UICorner");mc.CornerRadius=UDim.new(0,18);mc.Parent=modal

-- Keep the modal compact on smaller resolutions.
local modalScale=Instance.new("UIScale")
modalScale.Name="ResponsiveScale"
modalScale.Parent=modal
local function updateModalScale()
	local cam=workspace.CurrentCamera
	if not cam then return end
	local v=cam.ViewportSize
	modalScale.Scale=math.min(1,(v.X-30)/560,(v.Y-30)/720)
end
updateModalScale()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateModalScale)
RunService.RenderStepped:Connect(updateModalScale)
local ms=Instance.new("UIStroke");ms.Color=Color3.fromRGB(35,175,245);ms.Thickness=3;ms.Transparency=.08;ms.Parent=modal

local title=Instance.new("TextLabel")
title.Size=UDim2.new(1,-80,0,46)
title.Position=UDim2.fromOffset(20,8)
title.BackgroundTransparency=1
title.Text="BARRIER COLOR & SETTINGS"
title.TextXAlignment=Enum.TextXAlignment.Left
title.Font=Enum.Font.GothamBlack
title.TextSize=19
title.TextColor3=Color3.new(1,1,1)
title.Parent=modal

local close=Instance.new("TextButton")
close.Size=UDim2.fromOffset(40,36)
close.Position=UDim2.new(1,-52,0,10)
close.BackgroundColor3=Color3.fromRGB(40,56,72)
close.BorderSizePixel=0
close.Text="X"
close.Font=Enum.Font.GothamBlack
close.TextSize=15
close.TextColor3=Color3.new(1,1,1)
close.Parent=modal
local xc=Instance.new("UICorner");xc.CornerRadius=UDim.new(0,10);xc.Parent=close

-- =========================================================
-- BARRIER STYLE
-- =========================================================
local styleTitle=Instance.new("TextLabel")
styleTitle.Size=UDim2.new(1,-44,0,26)
styleTitle.Position=UDim2.fromOffset(22,56)
styleTitle.BackgroundTransparency=1
styleTitle.Text="BARRIER STYLE"
styleTitle.TextXAlignment=Enum.TextXAlignment.Left
styleTitle.Font=Enum.Font.GothamBlack
styleTitle.TextSize=14
styleTitle.TextColor3=Color3.fromRGB(130,220,255)
styleTitle.Parent=modal

local styleFrame=Instance.new("Frame")
styleFrame.Size=UDim2.new(1,-44,0,86)
styleFrame.Position=UDim2.fromOffset(22,84)
styleFrame.BackgroundTransparency=1
styleFrame.Parent=modal

local styleButtons={}
local refreshAll
local stylePreviewAnimators={}

RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled or not modal.Visible then return end
	local t=os.clock()
	for _,anim in ipairs(stylePreviewAnimators) do
		local ok,err=pcall(anim,t,dt)
		if not ok then
			warn("[BARRIER STYLE PREVIEW] "..tostring(err))
		end
	end
end)

local function makePreviewBase(parent)
	local box=Instance.new("Frame")
	box.Size=UDim2.new(1,0,1,0)
	box.BackgroundColor3=Color3.fromRGB(10,32,48)
	box.BackgroundTransparency=.16
	box.BorderSizePixel=0
	box.ClipsDescendants=true
	box.Parent=parent
	local bc=Instance.new("UICorner");bc.CornerRadius=UDim.new(0,8);bc.Parent=box
	local bs=Instance.new("UIStroke");bs.Color=Color3.fromRGB(32,84,118);bs.Transparency=.28;bs.Thickness=1;bs.Parent=box

	local topGlow=Instance.new("Frame")
	topGlow:SetAttribute("BarrierPreviewColorSlot",2)
	topGlow.Size=UDim2.new(1,-10,0,2)
	topGlow.Position=UDim2.fromOffset(5,5)
	topGlow.BackgroundColor3=Color3.fromRGB(70,200,255)
	topGlow.BackgroundTransparency=.28
	topGlow.BorderSizePixel=0
	topGlow.Parent=box

	local bottomGlow=topGlow:Clone()
	bottomGlow.Position=UDim2.new(0,5,1,-7)
	bottomGlow.Parent=box

	local softCenter=Instance.new("Frame")
	softCenter:SetAttribute("BarrierPreviewColorSlot",1)
	softCenter.Size=UDim2.new(1,-18,0,18)
	softCenter.Position=UDim2.new(0,9,.5,-9)
	softCenter.BackgroundColor3=Color3.fromRGB(28,65,88)
	softCenter.BackgroundTransparency=.72
	softCenter.BorderSizePixel=0
	softCenter.Parent=box
	local scc=Instance.new("UICorner");scc.CornerRadius=UDim.new(1,0);scc.Parent=softCenter

	return box
end

local function buildDefaultPreview(parent)
	local box=makePreviewBase(parent)

	local railGlow=Instance.new("Frame")
	railGlow:SetAttribute("BarrierPreviewColorSlot",3)
	railGlow.Size=UDim2.new(1,-24,0,10)
	railGlow.Position=UDim2.fromOffset(12,9)
	railGlow.BackgroundColor3=Color3.fromRGB(235,245,255)
	railGlow.BackgroundTransparency=.88
	railGlow.BorderSizePixel=0
	railGlow.Parent=box
	local rgc=Instance.new("UICorner");rgc.CornerRadius=UDim.new(1,0);rgc.Parent=railGlow

	local rail=Instance.new("Frame")
	rail:SetAttribute("BarrierPreviewColorSlot",3)
	rail.Size=UDim2.new(1,-24,0,4)
	rail.Position=UDim2.fromOffset(12,12)
	rail.BackgroundColor3=Color3.fromRGB(242,248,255)
	rail.BackgroundTransparency=.18
	rail.BorderSizePixel=0
	rail.Parent=box
	local rc=Instance.new("UICorner");rc.CornerRadius=UDim.new(1,0);rc.Parent=rail

	local lane=Instance.new("Frame")
	lane.Size=UDim2.new(1,-26,0,18)
	lane.Position=UDim2.fromOffset(13,5)
	lane.BackgroundTransparency=1
	lane.ClipsDescendants=true
	lane.Parent=box

	local arrows={}
	for i=1,7 do
		local chev=Instance.new("TextLabel")
		chev:SetAttribute("BarrierPreviewColorSlot",3)
		chev.Size=UDim2.fromOffset(12,16)
		chev.BackgroundTransparency=1
		chev.Text=">"
		chev.Font=Enum.Font.GothamBlack
		chev.TextSize=16
		chev.TextColor3=Color3.fromRGB(248,250,255)
		chev.TextStrokeTransparency=.75
		chev.Parent=lane
		table.insert(arrows,chev)
	end

	table.insert(stylePreviewAnimators,function(t)
		if not lane.Parent then return end
		local width=math.max(lane.AbsoluteSize.X,1)
		for i,chev in ipairs(arrows) do
			local x=((i-1)*18 + t*30)%(width+18)-10
			chev.Position=UDim2.fromOffset(x,1)
		end
	end)
end

local function buildPulseWavePreview(parent)
	local box=makePreviewBase(parent)

	local railGlow=Instance.new("Frame")
	railGlow:SetAttribute("BarrierPreviewColorSlot",3)
	railGlow.Size=UDim2.new(1,-24,0,12)
	railGlow.Position=UDim2.fromOffset(12,8)
	railGlow.BackgroundColor3=Color3.fromRGB(82,232,255)
	railGlow.BackgroundTransparency=.9
	railGlow.BorderSizePixel=0
	railGlow.Parent=box
	local rgc=Instance.new("UICorner");rgc.CornerRadius=UDim.new(1,0);rgc.Parent=railGlow

	local rail=Instance.new("Frame")
	rail:SetAttribute("BarrierPreviewColorSlot",3)
	rail.Size=UDim2.new(1,-24,0,3)
	rail.Position=UDim2.fromOffset(12,13)
	rail.BackgroundColor3=Color3.fromRGB(108,236,255)
	rail.BackgroundTransparency=.22
	rail.BorderSizePixel=0
	rail.Parent=box
	local rc=Instance.new("UICorner");rc.CornerRadius=UDim.new(1,0);rc.Parent=rail

	local lane=Instance.new("Frame")
	lane.Size=UDim2.new(1,-26,0,22)
	lane.Position=UDim2.fromOffset(13,3)
	lane.BackgroundTransparency=1
	lane.ClipsDescendants=true
	lane.Parent=box

	local pulses={}
	for i=1,5 do
		local glow=Instance.new("Frame")
		glow:SetAttribute("BarrierPreviewColorSlot",2)
		glow.BorderSizePixel=0
		glow.BackgroundColor3=Color3.fromRGB(110,240,255)
		glow.BackgroundTransparency=.82
		glow.Parent=lane
		local gc=Instance.new("UICorner");gc.CornerRadius=UDim.new(1,0);gc.Parent=glow

		local band=Instance.new("Frame")
		band:SetAttribute("BarrierPreviewColorSlot",3)
		band.BorderSizePixel=0
		band.BackgroundColor3=Color3.fromRGB(168,248,255)
		band.BackgroundTransparency=.06
		band.Parent=lane
		local bc=Instance.new("UICorner");bc.CornerRadius=UDim.new(1,0);bc.Parent=band

		table.insert(pulses,{glow=glow,band=band,phase=(i-1)*.75,offset=(i-1)*.17})
	end

	table.insert(stylePreviewAnimators,function(t)
		if not lane.Parent then return end
		local width=math.max(lane.AbsoluteSize.X,1)
		for _,pulse in ipairs(pulses) do
			local progress=(pulse.offset + t*.22)%1
			local x=math.floor(progress*(width-16))
			local wave=.5+.5*math.sin(t*5 + pulse.phase)
			local h=8 + wave*10
			pulse.glow.Size=UDim2.fromOffset(14,h+6)
			pulse.glow.Position=UDim2.fromOffset(x-1,math.floor(11-(h+6)/2))
			pulse.glow.BackgroundTransparency=.9-(wave*.18)
			pulse.band.Size=UDim2.fromOffset(8,h)
			pulse.band.Position=UDim2.fromOffset(x+2,math.floor(11-h/2))
		end
	end)
end

local function makeStyleCard(name,label,description,x,previewBuilder)
	local b=Instance.new("TextButton")
	b.Name=name
	b.Size=UDim2.new(.5,-5,1,0)
	b.Position=UDim2.new(x,x==0 and 0 or 5,0,0)
	b.AutoButtonColor=false
	b.BackgroundColor3=Color3.fromRGB(13,42,62)
	b.BorderSizePixel=0
	b.Text=""
	b.Parent=styleFrame
	local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,10);c.Parent=b

	local st=Instance.new("UIStroke")
	st.Name="SelectedStroke"
	st.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
	st.Color=Color3.fromRGB(40,190,255)
	st.Thickness=2.5
	st.Enabled=false
	st.Parent=b

	local preview=Instance.new("Frame")
	preview.Size=UDim2.new(1,-16,0,28)
	preview.Position=UDim2.fromOffset(8,7)
	preview.BackgroundTransparency=1
	preview.Parent=b
	previewBuilder(preview)

	local titleLabel=Instance.new("TextLabel")
	titleLabel.Size=UDim2.new(1,-16,0,18)
	titleLabel.Position=UDim2.fromOffset(8,41)
	titleLabel.BackgroundTransparency=1
	titleLabel.Text=label
	titleLabel.TextXAlignment=Enum.TextXAlignment.Left
	titleLabel.Font=Enum.Font.GothamBlack
	titleLabel.TextSize=11
	titleLabel.TextColor3=Color3.new(1,1,1)
	titleLabel.Parent=b

	local desc=Instance.new("TextLabel")
	desc.Size=UDim2.new(1,-16,0,16)
	desc.Position=UDim2.fromOffset(8,60)
	desc.BackgroundTransparency=1
	desc.Text=description
	desc.TextXAlignment=Enum.TextXAlignment.Left
	desc.Font=Enum.Font.Gotham
	desc.TextSize=9
	desc.TextColor3=Color3.fromRGB(155,180,198)
	desc.Parent=b

	styleButtons[name]=b
	b.Activated:Connect(function()
		pending.Style=name
		refreshAll()
	end)
end

makeStyleCard("DEFAULT","DEFAULT","Classic arrow barrier",0,buildDefaultPreview)
makeStyleCard("PULSE_WAVE","PULSE WAVE","Flowing energy effect",.5,buildPulseWavePreview)

local function refreshStyleSelection()
	for name,b in pairs(styleButtons) do
		local selected=(pending.Style==name)
		b.BackgroundColor3=selected and Color3.fromRGB(15,60,86) or Color3.fromRGB(13,42,62)
		local st=b:FindFirstChild("SelectedStroke")
		if st then st.Enabled=selected end

		-- Tint the miniature samples to the currently chosen barrier preset.
		-- The world barrier is NOT recolored until APPLY is pressed.
		local colors=COLOR_PRESETS[pending.Color] or COLOR_PRESETS.BLUE
		for _,detail in ipairs(b:GetDescendants()) do
			local slot=detail:GetAttribute("BarrierPreviewColorSlot")
			local color=slot and colors[slot]
			if color then
				if detail:IsA("TextLabel") then
					detail.TextColor3=color
				elseif detail:IsA("Frame") then
					detail.BackgroundColor3=color
				end
			end
		end
	end
end

local colorTitle=Instance.new("TextLabel")
colorTitle.Size=UDim2.new(1,-44,0,28)
colorTitle.Position=UDim2.fromOffset(22,180)
colorTitle.BackgroundTransparency=1
colorTitle.Text="BARRIER COLOR"
colorTitle.TextXAlignment=Enum.TextXAlignment.Left
colorTitle.Font=Enum.Font.GothamBlack
colorTitle.TextSize=15
colorTitle.TextColor3=Color3.fromRGB(130,220,255)
colorTitle.Parent=modal

-- =========================================================
-- COLOR SWATCHES
-- Image-like glossy cards built with Frames + UIGradient: no text labels
-- and no external image uploads. COLOR_PRESETS remains the single palette.
-- =========================================================
local colorFrame=Instance.new("Frame")
colorFrame.Name="BarrierColorSwatches"
colorFrame.Size=UDim2.new(1,-44,0,116)
colorFrame.Position=UDim2.fromOffset(22,210)
colorFrame.BackgroundTransparency=1
colorFrame.ClipsDescendants=false
colorFrame.Parent=modal

local colorGrid=Instance.new("UIGridLayout")
colorGrid.CellSize=UDim2.new(1/5,-8,0,48)
colorGrid.CellPadding=UDim2.fromOffset(10,10)
colorGrid.FillDirection=Enum.FillDirection.Horizontal
colorGrid.FillDirectionMaxCells=5
colorGrid.SortOrder=Enum.SortOrder.LayoutOrder
colorGrid.HorizontalAlignment=Enum.HorizontalAlignment.Left
colorGrid.VerticalAlignment=Enum.VerticalAlignment.Top
colorGrid.Parent=colorFrame

local colorButtons={}
local colorOrder={"BLUE","CYAN","GOLD","GREEN","ORANGE","PINK","PURPLE","RED","WHITE"}

local function refreshColorSelection()
	for name,b in pairs(colorButtons) do
		local selected=(name==pending.Color)
		local hovered=b:GetAttribute("SwatchHovered")==true
		b:SetAttribute("IsSelected",selected)

		local outline=b:FindFirstChild("SelectedOutline")
		if outline then outline.Visible=selected end
		local glow=b:FindFirstChild("SelectedGlow")
		if glow then glow.Visible=selected end
		local mark=b:FindFirstChild("SelectedMark")
		if mark then mark.Visible=selected end

		local border=b:FindFirstChild("SwatchBorder")
		if border then
			border.Transparency=(selected or hovered) and .04 or .28
		end
		local inset=b:FindFirstChild("Inset")
		local inner=inset and inset:FindFirstChild("InnerBorder")
		if inner then
			inner.Transparency=selected and .05 or (hovered and .30 or .58)
		end
	end
end

for order,name in ipairs(colorOrder) do
	local colors=COLOR_PRESETS[name]
	local b=Instance.new("TextButton")
	b.Name=name
	b.LayoutOrder=order
	b.AutoButtonColor=false
	b.Active=true
	b.Selectable=true
	b.BackgroundColor3=Color3.new(1,1,1)
	b.BorderSizePixel=0
	b.Text="" -- Color is the picture, not a printed word.
	b.ClipsDescendants=false
	b.ZIndex=3
	b:SetAttribute("BarrierColorName",name)
	b:SetAttribute("SwatchHovered",false)
	b.Parent=colorFrame

	local corner=Instance.new("UICorner")
	corner.CornerRadius=UDim.new(0,10)
	corner.Parent=b

	-- Glossy color sample from the actual barrier's hot/rail/panel colors.
	-- No changes to the real COLOR_PRESETS or saved color names.
	local gradient=Instance.new("UIGradient")
	gradient.Name="SwatchGradient"
	gradient.Rotation=90
	gradient.Color=ColorSequence.new({
		ColorSequenceKeypoint.new(0,colors[3]),
		ColorSequenceKeypoint.new(.22,colors[2]:Lerp(colors[3],.30)),
		ColorSequenceKeypoint.new(.60,colors[2]),
		ColorSequenceKeypoint.new(1,colors[1]),
	})
	gradient.Parent=b

	local border=Instance.new("UIStroke")
	border.Name="SwatchBorder"
	border.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
	border.Color=colors[3]
	border.Thickness=1.5
	border.Transparency=.28
	border.Parent=b

	local inset=Instance.new("Frame")
	inset.Name="Inset"
	inset.Size=UDim2.new(1,-6,1,-6)
	inset.Position=UDim2.fromOffset(3,3)
	inset.BackgroundTransparency=1
	inset.BorderSizePixel=0
	inset.Active=false
	inset.ZIndex=4
	inset.Parent=b
	local insetCorner=Instance.new("UICorner")
	insetCorner.CornerRadius=UDim.new(0,7)
	insetCorner.Parent=inset
	local innerBorder=Instance.new("UIStroke")
	innerBorder.Name="InnerBorder"
	innerBorder.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
	innerBorder.Color=Color3.new(1,1,1)
	innerBorder.Thickness=1
	innerBorder.Transparency=.58
	innerBorder.Parent=inset

	local sheen=Instance.new("Frame")
	sheen.Name="Gloss"
	sheen.Size=UDim2.new(1,-12,.42,0)
	sheen.Position=UDim2.fromOffset(6,5)
	sheen.BackgroundColor3=Color3.new(1,1,1)
	sheen.BackgroundTransparency=.64
	sheen.BorderSizePixel=0
	sheen.Active=false
	sheen.ZIndex=4
	sheen.Parent=b
	local sheenCorner=Instance.new("UICorner")
	sheenCorner.CornerRadius=UDim.new(0,6)
	sheenCorner.Parent=sheen
	local sheenGradient=Instance.new("UIGradient")
	sheenGradient.Rotation=90
	sheenGradient.Transparency=NumberSequence.new({
		NumberSequenceKeypoint.new(0,.12),
		NumberSequenceKeypoint.new(1,1),
	})
	sheenGradient.Parent=sheen

	-- Soft cyan halo outside the swatch. It never changes grid cell size.
	local halo=Instance.new("Frame")
	halo.Name="SelectedGlow"
	halo.Size=UDim2.new(1,4,1,4)
	halo.Position=UDim2.fromOffset(-2,-2)
	halo.BackgroundTransparency=1
	halo.BorderSizePixel=0
	halo.Active=false
	halo.Visible=false
	halo.ZIndex=4
	halo.Parent=b
	local haloCorner=Instance.new("UICorner")
	haloCorner.CornerRadius=UDim.new(0,12)
	haloCorner.Parent=halo
	local haloStroke=Instance.new("UIStroke")
	haloStroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
	haloStroke.Color=Color3.fromRGB(35,195,255)
	haloStroke.Thickness=7
	haloStroke.Transparency=.80
	haloStroke.Parent=halo

	local outline=Instance.new("Frame")
	outline.Name="SelectedOutline"
	outline.Size=UDim2.new(1,4,1,4)
	outline.Position=UDim2.fromOffset(-2,-2)
	outline.BackgroundTransparency=1
	outline.BorderSizePixel=0
	outline.Active=false
	outline.Visible=false
	outline.ZIndex=5
	outline.Parent=b
	local outlineCorner=Instance.new("UICorner")
	outlineCorner.CornerRadius=UDim.new(0,12)
	outlineCorner.Parent=outline
	local outlineStroke=Instance.new("UIStroke")
	outlineStroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
	outlineStroke.Color=Color3.fromRGB(45,210,255)
	outlineStroke.Thickness=2.5
	outlineStroke.Transparency=0
	outlineStroke.Parent=outline

	-- Small graphic check. Built from shapes to avoid unsupported glyphs.
	local mark=Instance.new("Frame")
	mark.Name="SelectedMark"
	mark.Size=UDim2.fromOffset(16,16)
	mark.Position=UDim2.new(1,-22,0,6)
	mark.BackgroundColor3=Color3.fromRGB(7,25,40)
	mark.BackgroundTransparency=.06
	mark.BorderSizePixel=0
	mark.Active=false
	mark.Visible=false
	mark.ZIndex=6
	mark.Parent=b
	local markCorner=Instance.new("UICorner")
	markCorner.CornerRadius=UDim.new(1,0)
	markCorner.Parent=mark

	local short=Instance.new("Frame")
	short.AnchorPoint=Vector2.new(.5,.5)
	short.Position=UDim2.fromOffset(5.5,8.5)
	short.Size=UDim2.fromOffset(5,2)
	short.Rotation=45
	short.BackgroundColor3=Color3.new(1,1,1)
	short.BorderSizePixel=0
	short.Active=false
	short.ZIndex=7
	short.Parent=mark
	local long=Instance.new("Frame")
	long.AnchorPoint=Vector2.new(.5,.5)
	long.Position=UDim2.fromOffset(9.5,7)
	long.Size=UDim2.fromOffset(8,2)
	long.Rotation=-45
	long.BackgroundColor3=Color3.new(1,1,1)
	long.BorderSizePixel=0
	long.Active=false
	long.ZIndex=7
	long.Parent=mark

	colorButtons[name]=b

	local function setHovered(hovered)
		b:SetAttribute("SwatchHovered",hovered)
		refreshColorSelection()
	end
	b.MouseEnter:Connect(function() setHovered(true) end)
	b.MouseLeave:Connect(function() setHovered(false) end)
	b.SelectionGained:Connect(function() setHovered(true) end)
	b.SelectionLost:Connect(function() setHovered(false) end)

	b.Activated:Connect(function()
		pending.Color=name
		refreshColorSelection()
		refreshStyleSelection()
	end)
end

local settingsTitle=Instance.new("TextLabel")
settingsTitle.Size=UDim2.new(1,-44,0,28)
settingsTitle.Position=UDim2.fromOffset(22,334)
settingsTitle.BackgroundTransparency=1
settingsTitle.Text="BARRIER SETTINGS"
settingsTitle.TextXAlignment=Enum.TextXAlignment.Left
settingsTitle.Font=Enum.Font.GothamBlack
settingsTitle.TextSize=15
settingsTitle.TextColor3=Color3.fromRGB(130,220,255)
settingsTitle.Parent=modal

-- Scroll only the adjustment options; title/colors/footer remain fixed.
local settingsScroll=Instance.new("ScrollingFrame")
settingsScroll.Name="SettingsScroll"
settingsScroll.Size=UDim2.new(1,-44,0,280)
settingsScroll.Position=UDim2.fromOffset(22,366)
settingsScroll.BackgroundTransparency=1
settingsScroll.BorderSizePixel=0
settingsScroll.ScrollBarThickness=7
settingsScroll.ScrollBarImageColor3=Color3.fromRGB(55,190,245)
settingsScroll.CanvasSize=UDim2.fromOffset(0,386)
settingsScroll.ScrollingDirection=Enum.ScrollingDirection.Y
settingsScroll.Parent=modal

local function makeAdjustRow(y,label,description,key,minValue,maxValue,step,formatValue)
	local row=Instance.new("Frame")
	row.Size=UDim2.new(1,-10,0,58)
	row.Position=UDim2.fromOffset(0,y)
	row.BackgroundColor3=Color3.fromRGB(9,31,49)
	row.BackgroundTransparency=.12
	row.BorderSizePixel=0
	row.Parent=settingsScroll
	local rc=Instance.new("UICorner");rc.CornerRadius=UDim.new(0,10);rc.Parent=row

	local labelText=Instance.new("TextLabel")
	labelText.Size=UDim2.fromOffset(170,22)
	labelText.Position=UDim2.fromOffset(14,7)
	labelText.BackgroundTransparency=1
	labelText.Text=label
	labelText.TextXAlignment=Enum.TextXAlignment.Left
	labelText.Font=Enum.Font.GothamBlack
	labelText.TextSize=13
	labelText.TextColor3=Color3.new(1,1,1)
	labelText.Parent=row

	local desc=Instance.new("TextLabel")
	desc.Size=UDim2.fromOffset(210,20)
	desc.Position=UDim2.fromOffset(14,30)
	desc.BackgroundTransparency=1
	desc.Text=description
	desc.TextXAlignment=Enum.TextXAlignment.Left
	desc.Font=Enum.Font.Gotham
	desc.TextSize=10
	desc.TextColor3=Color3.fromRGB(155,180,198)
	desc.Parent=row

	local minus=Instance.new("TextButton")
	minus.Size=UDim2.fromOffset(38,38)
	minus.Position=UDim2.new(1,-196,.5,-19)
	minus.BackgroundColor3=Color3.fromRGB(31,66,91)
	minus.BorderSizePixel=0
	minus.Text="−"
	minus.Font=Enum.Font.GothamBlack
	minus.TextSize=22
	minus.TextColor3=Color3.fromRGB(115,220,255)
	minus.Parent=row
	local mic=Instance.new("UICorner");mic.CornerRadius=UDim.new(0,8);mic.Parent=minus

	local value=Instance.new("TextLabel")
	value.Size=UDim2.fromOffset(86,38)
	value.Position=UDim2.new(1,-150,.5,-19)
	value.BackgroundColor3=Color3.fromRGB(24,45,62)
	value.BorderSizePixel=0
	value.Font=Enum.Font.GothamBlack
	value.TextSize=14
	value.TextColor3=Color3.new(1,1,1)
	value.Parent=row
	local vc=Instance.new("UICorner");vc.CornerRadius=UDim.new(0,8);vc.Parent=value

	local plus=Instance.new("TextButton")
	plus.Size=UDim2.fromOffset(38,38)
	plus.Position=UDim2.new(1,-52,.5,-19)
	plus.BackgroundColor3=Color3.fromRGB(31,66,91)
	plus.BorderSizePixel=0
	plus.Text="+"
	plus.Font=Enum.Font.GothamBlack
	plus.TextSize=20
	plus.TextColor3=Color3.fromRGB(115,220,255)
	plus.Parent=row
	local plc=Instance.new("UICorner");plc.CornerRadius=UDim.new(0,8);plc.Parent=plus

	local function update()
		value.Text=formatValue(pending[key])
	end
	update()

	minus.Activated:Connect(function()
		pending[key]=math.clamp(pending[key]-step,minValue,maxValue)
		if key=="TrailCount" or key=="Spacing" then pending[key]=math.round(pending[key]) end
		update()
	end)

	plus.Activated:Connect(function()
		pending[key]=math.clamp(pending[key]+step,minValue,maxValue)
		if key=="TrailCount" or key=="Spacing" then pending[key]=math.round(pending[key]) end
		update()
	end)

	return update,row,labelText,desc
end

local updateGlow,glowRow,glowLabel,glowDesc=makeAdjustRow(0,"GLOW INTENSITY","How bright the barrier glows","Glow",0,1,.05,function(v)return string.format("%.2f",v)end)
local updateSpeed,speedRow,speedLabel,speedDesc=makeAdjustRow(62,"ARROW SPEED","Speed of moving arrows","Speed",1,15,1,function(v)return tostring(math.round(v))end)
local updateSpacing,spacingRow,spacingLabel,spacingDesc=makeAdjustRow(124,"ARROW SPACING","Distance between arrow groups","Spacing",4,20,1,function(v)return tostring(math.round(v))end)
local updateTrails,trailsRow,trailsLabel,trailsDesc=makeAdjustRow(186,"TRAIL COUNT","Extra arrows behind the main arrow","TrailCount",0,8,1,function(v)return tostring(math.round(v))end)
local updateWaveAmplitude,waveAmplitudeRow,waveAmplitudeLabel,waveAmplitudeDesc=makeAdjustRow(124,"WAVE AMPLITUDE","Height of the wave effect","WaveAmplitude",.5,3,.25,function(v)return string.format("%.2f",v)end)

-- ARROW DIRECTION row
local directionRow=Instance.new("Frame")
directionRow.Size=UDim2.new(1,-10,0,58)
directionRow.Position=UDim2.fromOffset(0,248)
directionRow.BackgroundColor3=Color3.fromRGB(9,31,49)
directionRow.BackgroundTransparency=.12
directionRow.BorderSizePixel=0
directionRow.Parent=settingsScroll
local drc=Instance.new("UICorner");drc.CornerRadius=UDim.new(0,10);drc.Parent=directionRow

local directionLabel=Instance.new("TextLabel")
directionLabel.Size=UDim2.fromOffset(170,22)
directionLabel.Position=UDim2.fromOffset(14,7)
directionLabel.BackgroundTransparency=1
directionLabel.Text="ARROW DIRECTION"
directionLabel.TextXAlignment=Enum.TextXAlignment.Left
directionLabel.Font=Enum.Font.GothamBlack
directionLabel.TextSize=13
directionLabel.TextColor3=Color3.new(1,1,1)
directionLabel.Parent=directionRow

local directionDesc=Instance.new("TextLabel")
directionDesc.Size=UDim2.fromOffset(190,20)
directionDesc.Position=UDim2.fromOffset(14,30)
directionDesc.BackgroundTransparency=1
directionDesc.Text="Direction of moving arrows"
directionDesc.TextXAlignment=Enum.TextXAlignment.Left
directionDesc.Font=Enum.Font.Gotham
directionDesc.TextSize=10
directionDesc.TextColor3=Color3.fromRGB(155,180,198)
directionDesc.Parent=directionRow

local directionButtons={}
local directionInfo={
	{"RIGHT","→"},
	{"LEFT","←"},
	{"UP","↑"},
	{"DOWN","↓"},
}

local function refreshDirectionSelection()
	for name,b in pairs(directionButtons) do
		local selected=(pending.Direction==name)
		b.BackgroundColor3=selected and Color3.fromRGB(20,155,245) or Color3.fromRGB(24,45,62)
		local stroke=b:FindFirstChild("SelectedStroke")
		if stroke then stroke.Enabled=selected end
	end
end

for i,info in ipairs(directionInfo) do
	local name,symbol=info[1],info[2]
	local b=Instance.new("TextButton")
	b.Name=name
	b.Size=UDim2.fromOffset(48,38)
	b.Position=UDim2.new(1,-218+(i-1)*52,.5,-19)
	b.BackgroundColor3=Color3.fromRGB(24,45,62)
	b.BorderSizePixel=0
	b.Text=symbol
	b.Font=Enum.Font.GothamBlack
	b.TextSize=23
	b.TextColor3=Color3.new(1,1,1)
	b.Parent=directionRow
	local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,8);c.Parent=b
	local st=Instance.new("UIStroke");st.Name="SelectedStroke";st.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;st.Color=Color3.fromRGB(160,235,255);st.Thickness=2;st.Enabled=false;st.Parent=b
	directionButtons[name]=b
	b.Activated:Connect(function()
		pending.Direction=name
		refreshDirectionSelection()
	end)
end

-- ARROW FACING row
local facingRow=Instance.new("Frame")
facingRow.Size=UDim2.new(1,-10,0,58)
facingRow.Position=UDim2.fromOffset(0,310)
facingRow.BackgroundColor3=Color3.fromRGB(9,31,49)
facingRow.BackgroundTransparency=.12
facingRow.BorderSizePixel=0
facingRow.Parent=settingsScroll
local frc=Instance.new("UICorner");frc.CornerRadius=UDim.new(0,10);frc.Parent=facingRow

local facingLabel=Instance.new("TextLabel")
facingLabel.Size=UDim2.fromOffset(170,22)
facingLabel.Position=UDim2.fromOffset(14,7)
facingLabel.BackgroundTransparency=1
facingLabel.Text="ARROW FACING"
facingLabel.TextXAlignment=Enum.TextXAlignment.Left
facingLabel.Font=Enum.Font.GothamBlack
facingLabel.TextSize=13
facingLabel.TextColor3=Color3.new(1,1,1)
facingLabel.Parent=facingRow

local facingDesc=Instance.new("TextLabel")
facingDesc.Size=UDim2.fromOffset(190,20)
facingDesc.Position=UDim2.fromOffset(14,30)
facingDesc.BackgroundTransparency=1
facingDesc.Text="Which way the arrows face"
facingDesc.TextXAlignment=Enum.TextXAlignment.Left
facingDesc.Font=Enum.Font.Gotham
facingDesc.TextSize=10
facingDesc.TextColor3=Color3.fromRGB(155,180,198)
facingDesc.Parent=facingRow

local facingButtons={}
local function refreshFacingSelection()
	for name,b in pairs(facingButtons) do
		local selected=(pending.Facing==name)
		b.BackgroundColor3=selected and Color3.fromRGB(20,155,245) or Color3.fromRGB(24,45,62)
		local stroke=b:FindFirstChild("SelectedStroke")
		if stroke then stroke.Enabled=selected end
	end
end

for i,info in ipairs({
	{"RIGHT","→"},
	{"LEFT","←"},
	{"UP","↑"},
	{"DOWN","↓"},
	}) do
	local name,symbol=info[1],info[2]
	local b=Instance.new("TextButton")
	b.Name=name
	b.Size=UDim2.fromOffset(48,38)
	b.Position=UDim2.new(1,-218+(i-1)*52,.5,-19)
	b.BackgroundColor3=Color3.fromRGB(24,45,62)
	b.BorderSizePixel=0
	b.Text=symbol
	b.Font=Enum.Font.GothamBlack
	b.TextSize=22
	b.TextColor3=Color3.new(1,1,1)
	b.Parent=facingRow
	local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,8);c.Parent=b
	local st=Instance.new("UIStroke");st.Name="SelectedStroke";st.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;st.Color=Color3.fromRGB(160,235,255);st.Thickness=2;st.Enabled=false;st.Parent=b
	facingButtons[name]=b
	b.Activated:Connect(function()
		pending.Facing=name
		refreshFacingSelection()
	end)
end

local reset=Instance.new("TextButton")
reset.Size=UDim2.fromOffset(190,40)
reset.Position=UDim2.fromOffset(22,690)
reset.AnchorPoint=Vector2.new(0,1)
reset.BackgroundColor3=Color3.fromRGB(38,55,71)
reset.BorderSizePixel=0
reset.Text="RESET DEFAULT"
reset.Font=Enum.Font.GothamBlack
reset.TextSize=12
reset.TextColor3=Color3.new(1,1,1)
reset.Parent=modal
local resc=Instance.new("UICorner");resc.CornerRadius=UDim.new(0,9);resc.Parent=reset

local apply=Instance.new("TextButton")
apply.Size=UDim2.fromOffset(160,40)
apply.Position=UDim2.new(1,-182,0,690)
apply.AnchorPoint=Vector2.new(0,1)
apply.BackgroundColor3=Color3.fromRGB(20,155,245)
apply.BorderSizePixel=0
apply.Text="APPLY"
apply.Font=Enum.Font.GothamBlack
apply.TextSize=13
apply.TextColor3=Color3.new(1,1,1)
apply.Parent=modal
local apc=Instance.new("UICorner");apc.CornerRadius=UDim.new(0,9);apc.Parent=apply

local function refreshStyleUI()
	local pulse=pending.Style=="PULSE_WAVE"
	if pulse and pending.TrailCount<1 then
		pending.TrailCount=1
		updateTrails()
	end

	speedLabel.Text=pulse and "WAVE SPEED" or "ARROW SPEED"
	speedDesc.Text=pulse and "How fast the pulse wave moves" or "Speed of moving arrows"

	trailsLabel.Text=pulse and "WAVE BANDS" or "TRAIL COUNT"
	trailsDesc.Text=pulse and "Number of flowing energy bands" or "Extra arrows behind the main arrow"

	directionLabel.Text=pulse and "WAVE DIRECTION" or "ARROW DIRECTION"
	directionDesc.Text=pulse and "Direction the wave flows" or "Direction of moving arrows"

	spacingRow.Visible=not pulse
	facingRow.Visible=not pulse
	waveAmplitudeRow.Visible=pulse
end

refreshAll=function()
	updateGlow()
	updateSpeed()
	updateSpacing()
	updateTrails()
	updateWaveAmplitude()
	refreshStyleSelection()
	refreshStyleUI()
	refreshColorSelection()
	refreshDirectionSelection()
	refreshFacingSelection()
end

reset.Activated:Connect(function()
	for k,v in pairs(DEFAULTS) do pending[k]=v end
	refreshAll()
end)

apply.Activated:Connect(function()
	local oldStyle=CONFIG.Style
	local oldSpacing=CONFIG.Spacing
	local oldTrails=CONFIG.TrailCount

	CONFIG.Style=pending.Style
	CONFIG.WaveAmplitude=pending.WaveAmplitude
	CONFIG.Glow=pending.Glow
	CONFIG.Speed=pending.Speed
	CONFIG.Spacing=pending.Spacing
	CONFIG.TrailCount=pending.TrailCount
	CONFIG.Move=pending.Direction
	CONFIG.Facing=pending.Facing
	CONFIG.Color=pending.Color

	recolorBarrier(pending.Color)

	-- Save barrier customization separately from plot drafts and keybinds.
	barrierSettingsRemote:FireServer("Save",{
		Style=CONFIG.Style,
		WaveAmplitude=CONFIG.WaveAmplitude,
		Color=CONFIG.Color,
		Glow=CONFIG.Glow,
		Speed=CONFIG.Speed,
		Spacing=CONFIG.Spacing,
		TrailCount=CONFIG.TrailCount,
		Direction=CONFIG.Move,
		Facing=CONFIG.Facing,
	})

	-- Style/spacing/trail changes rebuild the relevant motion geometry.
	if oldStyle~=CONFIG.Style or oldSpacing~=CONFIG.Spacing or oldTrails~=CONFIG.TrailCount then
		for _,data in pairs(walls) do
			data.lastLength=-1
			data.lastWaveLength=-1
			data.activeStyle=nil
		end
	end

	-- Apply glow from fixed base values (never multiply the previous result).
	for _,obj in ipairs(root:GetDescendants()) do
		if obj:IsA("PointLight") then
			local baseBrightness=obj:GetAttribute("BaseBrightness") or 1
			local baseRange=obj:GetAttribute("BaseRange") or 10
			obj.Brightness=baseBrightness*CONFIG.Glow
			obj.Range=baseRange*(.45+.55*CONFIG.Glow)
		elseif obj:IsA("ParticleEmitter") then
			obj.LightEmission=.1+.65*CONFIG.Glow
			obj.Rate=CONFIG.Glow<=.02 and 0 or math.max(1,math.floor(2+8*CONFIG.Glow))
		end
	end

	modal.Visible=false
end)

close.Activated:Connect(function()
	-- Cancel unapplied edits by restoring pending values from live CONFIG.
	pending.Style=CONFIG.Style
	pending.WaveAmplitude=CONFIG.WaveAmplitude
	pending.Glow=CONFIG.Glow
	pending.Speed=CONFIG.Speed
	pending.Spacing=CONFIG.Spacing
	pending.TrailCount=CONFIG.TrailCount
	pending.Direction=CONFIG.Move
	pending.Facing=CONFIG.Facing
	pending.Color=currentColor
	refreshAll()
	modal.Visible=false
end)

barrierSettingsRemote.OnClientEvent:Connect(function(action,data)
	if action~="Loaded" and action~="SessionUpdated" then return end
	if type(data)~="table" then return end

	applyBarrierSettings(data)
	recolorBarrier(currentColor)

	pending.Style=CONFIG.Style
	pending.WaveAmplitude=CONFIG.WaveAmplitude
	pending.Glow=CONFIG.Glow
	pending.Speed=CONFIG.Speed
	pending.Spacing=CONFIG.Spacing
	pending.TrailCount=CONFIG.TrailCount
	pending.Direction=CONFIG.Move
	pending.Facing=CONFIG.Facing
	pending.Color=currentColor
	refreshAll()

	if action=="Loaded" then
		print("✓ Saved barrier settings loaded")
	else
		print("✓ Creator barrier changes synced")
	end
end)

-- Always ask the server to resolve our role.
-- The server decides authoritatively whether this player is the owner or guest.
barrierSettingsRemote:FireServer("Load")

refreshAll()

-- Dedicated barrier-only raycast.
local camera=workspace.CurrentCamera
local function getBarrierUnderMouse()
	camera=workspace.CurrentCamera
	if not camera then return nil end

	local mousePos=UIS:GetMouseLocation()
	local ray=camera:ViewportPointToRay(mousePos.X,mousePos.Y)

	local params=RaycastParams.new()
	params.FilterType=Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances={root}
	params.IgnoreWater=true

	local result=workspace:Raycast(ray.Origin,ray.Direction*2000,params)
	if not result or not result.Instance then return nil end
	if result.Instance:GetAttribute("ParkourBarrier")~=true then return nil end

	local character=player.Character
	local hrp=character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	if (hrp.Position-result.Position).Magnitude>CONFIG.ClickRange then
		return nil
	end

	return result.Instance
end

-- Hover before clicking.
RunService.RenderStepped:Connect(function()
	barrierHighlight.Enabled=(not modal.Visible) and getBarrierUnderMouse()~=nil
end)

UIS.InputBegan:Connect(function(input,processed)
	if processed or UIS:GetFocusedTextBox() then return end
	if input.UserInputType==Enum.UserInputType.MouseButton1 then
		if not canEditBarrier() then return end
		if getBarrierUnderMouse() then
			pending.Style=CONFIG.Style
			pending.WaveAmplitude=CONFIG.WaveAmplitude
			pending.Glow=CONFIG.Glow
			pending.Speed=CONFIG.Speed
			pending.Spacing=CONFIG.Spacing
			pending.TrailCount=CONFIG.TrailCount
			pending.Direction=CONFIG.Move
			pending.Facing=CONFIG.Facing
			pending.Color=currentColor
			refreshAll()
			modal.Visible=true
		end
	end
end)

print("✓ ParkourPlotBarrierClient V6.4 integrated swatches + live color previews loaded")

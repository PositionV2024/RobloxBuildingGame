-- ParkourCreatorRoleRingClient V2.1 - BOLD SURFACE LETTERING
-- REPLACE StarterPlayer > StarterPlayerScripts > ParkourCreatorRoleRingClient.
-- Keep ONE enabled copy. Do not leave the V1 BillboardGui script running.
--
-- Visual only. This script READS the existing server-set role attributes.
-- It never grants permissions, changes Builder UI, or saves objects.
-- Every client draws the rings for all nearby players in its Creator session.
--
-- Keeps V2's circular band, role detection, and slow rotation.
-- Replaces clipped copies of a whole word with ONE complete letter per surface.
-- Each letter has a measured canvas and a fixed bold font size (no auto-shrink).
-- The long COLLABORATOR title repeats twice so its letters can stay large.
-- No BillboardGuis, point lights, global bloom, or changes to build permissions.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local localPlayer = Players.LocalPlayer

-- =========================================================
-- APPEARANCE
-- =========================================================
local CONFIG = {
	Radius = 2.5,                  -- Studs from torso center; V1 used 3.25.
	BandHeight = 0.85,             -- Slightly taller to give the lettering room.
	VerticalOffset = -0.35,         -- Relative to UpperTorso / R6 Torso.
	RotationSpeed = 15,            -- Degrees/second; one revolution in 30s.
	Segments = 64,                 -- Smooth band geometry; independent of letters.
	TextRepeats = 4,

	PanelThickness = 0.024,
	PanelColor = Color3.fromRGB(7, 21, 33),
	PanelTransparency = 0.24,      -- More solid backing for readable bright text.
	RailThickness = 0.035,
	RailTransparency = 0.48,       -- Rails are quieter than the role lettering.
	TextBrightness = 1.3,         -- SurfaceGui brightness; no additional lights.
	TextHeightScale = 0.96,        -- Letter surface height / band height.
	TextWhiteMix = 0.25,           -- Lighter gold/cyan/white letter faces.
	TextOutlineThickness = 1.8,    -- Fixed canvas pixels, not animated.
	TextOutlineColor = Color3.fromRGB(2, 8, 15),
	TextSurfaceLift = 0.045,       -- Physical offset in studs beyond the dark band.
	TitleGap = 0.22,               -- Minimum gap between complete repeated titles.
	ShowIcons = true,              -- Asset-free crown / tools / eye outlines.

	MaxDistance = 100,              -- Distance from this client's camera.
	DistanceHysteresis = 8,        -- Avoid rebuilding repeatedly at the boundary.
	HideOwnInFirstPerson = true,
	RefreshInterval = 0.20,        -- Retry streamed-in characters / distance checks.
	Debug = false,
}

local STYLES = {
	Owner = {Text = "OWNER", Color = Color3.fromRGB(255, 202, 73), Icon = "Crown"},
	Collaborator = {Text = "COLLABORATOR", Color = Color3.fromRGB(70, 199, 255), Icon = "Tools", Repeats = 2},
	Viewer = {Text = "VIEWER", Color = Color3.fromRGB(235, 244, 255), Icon = "Eye"},
}

assert(CONFIG.Radius > 0 and CONFIG.BandHeight > 0, "Role ring dimensions must be positive")
assert(CONFIG.TextRepeats >= 1 and CONFIG.TextRepeats % 1 == 0, "TextRepeats must be a positive integer")
assert(CONFIG.Segments >= 16 and CONFIG.Segments % 1 == 0,
	"Segments must be an integer of at least 16")
assert(CONFIG.TextHeightScale > 0 and CONFIG.TextHeightScale <= 1,
	"TextHeightScale must be greater than zero and at most 1")

local TAU = math.pi * 2
local STEP = TAU / CONFIG.Segments
local CHORD = 2 * CONFIG.Radius * math.sin(STEP / 2)
local TEXT_RADIUS = CONFIG.Radius + CONFIG.PanelThickness / 2 + CONFIG.TextSurfaceLift
local FONT = Enum.Font.GothamBlack
local FONT_SIZE = 100
local GLYPH_PADDING = 8
local MIN_CANVAS_HEIGHT = 112
local CONTAINER_NAME = "ParkourRoleRingsLocal_V2_1"

-- Remove this effect's old visuals only. Still replace the old LocalScript.
for _, name in ipairs({"ParkourRoleRingsLocal_V2", CONTAINER_NAME}) do
	local oldContainer = workspace:FindFirstChild(name)
	if oldContainer then oldContainer:Destroy() end
end
for _, child in ipairs(workspace:GetChildren()) do
	if child:IsA("Model") and child.Name:match("^ParkourRoleRing_%-?%d+$") then
		child:Destroy()
	end
end

local container = Instance.new("Folder")
container.Name = CONTAINER_NAME
container.Archivable = false
container.Parent = workspace

local states = {}
local connections = {}
local running = true

-- =========================================================
-- EXISTING SESSION / PERMISSION ATTRIBUTES (READ ONLY)
-- =========================================================
local function sessionOwnerId()
	local id = tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))
	if id and id ~= 0 then return id end
	return nil
end

local function inCreatorSession()
	return workspace:GetAttribute("ParkourPrivateCreatorServer") == true
		or sessionOwnerId() ~= nil
end

local function getRole(player)
	local ownerId = sessionOwnerId()
	local guest = player:GetAttribute("ParkourCreatorGuest") == true
	local sessionRole = player:GetAttribute("ParkourCreatorRole")
	local permissionRole = player:GetAttribute("ParkourGuestPermissionRole")

	-- When an owner ID exists, it takes precedence over stale role flags.
	if ownerId then
		if player.UserId == ownerId then return "Owner" end
	elseif not guest and (
		player:GetAttribute("ParkourCreatorOwner") == true or sessionRole == "Owner"
		) then
		return "Owner"
	end

	local participant = guest or (
		player:GetAttribute("ParkourPrivateCreator") == true
			and (sessionRole == "Viewer" or sessionRole == "Collaborator"
				or permissionRole == "Viewer" or permissionRole == "Collaborator")
	)
	if not participant then return nil end

	if permissionRole == "Collaborator"
		and player:GetAttribute("ParkourCanCollaborate") == true then
		return "Collaborator"
	end
	return "Viewer" -- No permission also displays Viewer; never Owner.
end

local function findTorso(character)
	if not character then return nil end
	for _, name in ipairs({"UpperTorso", "Torso", "HumanoidRootPart"}) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then return part end
	end
	return nil
end

local function ringCenter(torso)
	return torso.Position + Vector3.new(0, CONFIG.VerticalOffset, 0)
end

local function poseAt(center, player, timestamp)
	-- World-upright: running animations do not tilt the band into a spiky shape.
	-- Server time makes rotation phases approximately consistent across clients.
	local phase = (timestamp * CONFIG.RotationSpeed + math.abs(player.UserId) % 360) % 360
	return CFrame.new(center) * CFrame.Angles(0, math.rad(phase), 0)
end

-- =========================================================
-- GEOMETRY AND BOLD, INDIVIDUALLY SIZED SURFACE LETTERS
-- =========================================================
local function visualPart(parent, name, size, cf, color, material, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Archivable = false
	part.Parent = parent
	return part
end

-- These small icons use ordinary UI geometry, not emoji fonts or asset IDs.
local function drawIcon(parent, icon, ox, oy, size, color)
	local thickness = math.max(2, size * 0.075)
	local function line(x1, y1, x2, y2)
		local dx, dy = (x2 - x1) * size, (y2 - y1) * size
		local frame = Instance.new("Frame")
		frame.Name = "IconStroke"
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromOffset(ox + (x1 + x2) * size / 2, oy + (y1 + y2) * size / 2)
		frame.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), thickness)
		frame.Rotation = math.deg(math.atan2(dy, dx))
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = color
		frame.Parent = parent
	end
	local function path(points)
		for i = 1, #points - 1 do
			line(points[i][1], points[i][2], points[i + 1][1], points[i + 1][2])
		end
	end

	if icon == "Crown" then
		path({{0.14, 0.75}, {0.04, 0.25}, {0.30, 0.48}, {0.50, 0.06},
			{0.70, 0.48}, {0.96, 0.25}, {0.86, 0.75}, {0.14, 0.75}})
		line(0.17, 0.91, 0.83, 0.91)
	elseif icon == "Tools" then
		-- Crossed tool shafts with open jaws.
		line(0.17, 0.86, 0.77, 0.26)
		path({{0.58, 0.06}, {0.56, 0.24}, {0.76, 0.44}, {0.94, 0.42}})
		line(0.83, 0.86, 0.23, 0.26)
		path({{0.42, 0.06}, {0.44, 0.24}, {0.24, 0.44}, {0.06, 0.42}})
	else
		path({{0.03, 0.50}, {0.23, 0.24}, {0.50, 0.12}, {0.77, 0.24},
			{0.97, 0.50}, {0.77, 0.76}, {0.50, 0.88}, {0.23, 0.76}, {0.03, 0.50}})
		local pupil = Instance.new("Frame")
		pupil.Name = "EyePupil"
		pupil.AnchorPoint = Vector2.new(0.5, 0.5)
		pupil.Position = UDim2.fromOffset(ox + size / 2, oy + size / 2)
		pupil.Size = UDim2.fromOffset(size * 0.29, size * 0.29)
		pupil.BackgroundColor3 = color
		pupil.BorderSizePixel = 0
		pupil.Parent = parent
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = pupil
	end
end

-- Font measurement is cached: it does not run every animation frame.
local measuredGlyphs = {}
local titleLayouts = {}
local warnedFontMeasure = false

local function measureGlyph(character)
	if measuredGlyphs[character] then return measuredGlyphs[character] end

	local ok, bounds = pcall(function()
		return TextService:GetTextSize(character, FONT_SIZE, FONT, Vector2.new(2048, 2048))
	end)
	if not ok or bounds.X <= 0 or bounds.Y <= 0 then
		-- Keep the effect usable if measuring the font fails. These widths
		-- are deliberately generous so a letter is not clipped to a sliver.
		if not warnedFontMeasure then
			warnedFontMeasure = true
			warn("[ROLE RING V2.1] Font measurement unavailable; using fallback widths")
		end
		local factor = (character == "W" or character == "M") and 1.05 or 0.82
		bounds = Vector2.new(FONT_SIZE * factor, FONT_SIZE)
	end
	local measured = {
		character = character,
		width = math.ceil(bounds.X) + GLYPH_PADDING,
		height = math.ceil(bounds.Y),
	}
	measuredGlyphs[character] = measured
	return measured
end

local function getTitleLayout(style)
	if titleLayouts[style.Text] then return titleLayouts[style.Text] end

	local glyphs = {}
	local totalPixels = 0
	local canvasHeight = MIN_CANVAS_HEIGHT
	-- These role labels contain ASCII capital letters only.
	for i = 1, #style.Text do
		local measured = measureGlyph(style.Text:sub(i, i))
		table.insert(glyphs, measured)
		totalPixels = totalPixels + measured.width
		canvasHeight = math.max(canvasHeight, measured.height + 12)
	end

	local repeats = style.Repeats or CONFIG.TextRepeats
	local cycleArc = TAU * TEXT_RADIUS / repeats
	local availableArc = math.max(0.2, cycleArc - CONFIG.TitleGap)
	local desiredHeight = CONFIG.BandHeight * CONFIG.TextHeightScale
	local studPerPixel = desiredHeight / canvasHeight
	local iconSize = CONFIG.ShowIcons and CONFIG.BandHeight * 0.52 or 0
	local iconGap = CONFIG.ShowIcons and CONFIG.BandHeight * 0.15 or 0
	local desiredWidth = totalPixels * studPerPixel + iconSize + iconGap
	local fit = math.min(1, availableArc / desiredWidth)

	local layout = {
		glyphs = glyphs,
		canvasHeight = canvasHeight,
		studPerPixel = studPerPixel * fit,
		surfaceHeight = desiredHeight * fit,
		iconSize = iconSize * fit,
		iconGap = iconGap * fit,
		width = desiredWidth * fit,
		repeats = repeats,
		cycleArc = cycleArc,
	}
	titleLayouts[style.Text] = layout
	return layout
end

local function tangentFrame(angle, radius)
	local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
	-- Clockwise tangent: +X is the Back face's left-to-right text direction.
	local tangent = Vector3.new(math.sin(angle), 0, -math.cos(angle))
	return CFrame.fromMatrix(outward * radius, tangent, Vector3.yAxis, outward)
end

local function makeLetterSurface(parent, name, angle, arcWidth, height, pixelWidth, pixelHeight)
	local width = 2 * TEXT_RADIUS * math.sin(arcWidth / (2 * TEXT_RADIUS))
	local carrier = visualPart(parent, name, Vector3.new(width, height, 0.01),
		tangentFrame(angle, TEXT_RADIUS), CONFIG.PanelColor, Enum.Material.SmoothPlastic, 1)

	local surface = Instance.new("SurfaceGui")
	surface.Name = "RoleLetterSurface"
	surface.Adornee = carrier
	surface.Face = Enum.NormalId.Back
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = Vector2.new(pixelWidth, pixelHeight)
	surface.ClipsDescendants = true
	surface.AlwaysOnTop = false -- Do not show the rear lettering through the avatar.
	surface.LightInfluence = 0
	surface.Brightness = CONFIG.TextBrightness
	surface.MaxDistance = CONFIG.MaxDistance + CONFIG.DistanceHysteresis + TEXT_RADIUS
	surface.Active = false
	surface.Parent = carrier
	return surface
end

local function addBoldTitles(model, style)
	local layout = getTitleLayout(style)
	local textColor = style.Color:Lerp(Color3.new(1, 1, 1), CONFIG.TextWhiteMix)

	for repeatIndex = 0, layout.repeats - 1 do
		-- Centre each title in its own arc. Advance clockwise so the letters
		-- read in their normal order from the outside of the band.
		local middleAngle = -repeatIndex * TAU / layout.repeats
		local startAngle = middleAngle + layout.width / (2 * TEXT_RADIUS)
		local cursor = 0

		if CONFIG.ShowIcons then
			local angle = startAngle - (layout.iconSize / 2) / TEXT_RADIUS
			local surface = makeLetterSurface(model, "RoleIcon_" .. repeatIndex,
				angle, layout.iconSize, layout.iconSize, 112, 112)
			drawIcon(surface, style.Icon, 9, 9, 94, textColor)
			cursor = layout.iconSize + layout.iconGap
		end

		for index, glyph in ipairs(layout.glyphs) do
			local advance = glyph.width * layout.studPerPixel
			local angle = startAngle - (cursor + advance / 2) / TEXT_RADIUS
			local surface = makeLetterSurface(model,
				"Glyph_" .. repeatIndex .. "_" .. index .. "_" .. glyph.character,
				angle, advance, layout.surfaceHeight, glyph.width, layout.canvasHeight)

			local label = Instance.new("TextLabel")
			label.Name = "BoldRoleLetter"
			label.Size = UDim2.fromScale(1, 1)
			label.Position = UDim2.fromScale(0, 0)
			label.BackgroundTransparency = 1
			label.Text = glyph.character
			label.Font = FONT
			label.TextScaled = false
			label.TextSize = FONT_SIZE
			label.TextWrapped = false
			label.RichText = false
			label.AutoLocalize = false
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.TextYAlignment = Enum.TextYAlignment.Center
			label.TextColor3 = textColor
			label.TextTransparency = 0
			label.TextStrokeTransparency = 1 -- Use the single UIStroke below.
			label.Parent = surface

			local outline = Instance.new("UIStroke")
			outline.Name = "TextContrastOutline"
			outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			outline.Color = CONFIG.TextOutlineColor
			outline.Thickness = CONFIG.TextOutlineThickness
			outline.Transparency = 0.12
			outline.Parent = label

			cursor = cursor + advance
		end
	end
end

local function createBand(player, role, center, timestamp)
	local style = STYLES[role]
	local model = Instance.new("Model")
	model.Name = "Role_" .. tostring(player.UserId)
	model.Archivable = false

	-- Explicit center pivot; avoids a bounding-box-based rotating offset.
	local pivot = visualPart(model, "CenterPivot", Vector3.new(0.05, 0.05, 0.05),
		CFrame.new(), CONFIG.PanelColor, Enum.Material.SmoothPlastic, 1)
	model.PrimaryPart = pivot

	for i = 1, CONFIG.Segments do
		local angleA = -(i - 1) * STEP
		local angleB = -i * STEP
		local a = Vector3.new(math.cos(angleA) * CONFIG.Radius, 0, math.sin(angleA) * CONFIG.Radius)
		local b = Vector3.new(math.cos(angleB) * CONFIG.Radius, 0, math.sin(angleB) * CONFIG.Radius)
		local midpoint = (a + b) / 2
		local tangent = (b - a).Unit
		local outward = tangent:Cross(Vector3.yAxis)
		local facetCF = CFrame.fromMatrix(midpoint, tangent, Vector3.yAxis, outward)

		local panel = visualPart(model, "BandFacet_" .. i,
			Vector3.new(CHORD, CONFIG.BandHeight, CONFIG.PanelThickness), facetCF,
			CONFIG.PanelColor, Enum.Material.SmoothPlastic, CONFIG.PanelTransparency)
		for _, sign in ipairs({-1, 1}) do
			-- Crucial fix: rail LENGTH is along the SAME TANGENT as the band.
			-- Endpoints meet around the circumference instead of pointing outwards.
			visualPart(model, sign == 1 and "UpperRail" or "LowerRail",
				Vector3.new(CHORD + 0.008, CONFIG.RailThickness, CONFIG.RailThickness),
				facetCF * CFrame.new(0, sign * CONFIG.BandHeight / 2, CONFIG.PanelThickness / 2),
				style.Color, Enum.Material.Neon, CONFIG.RailTransparency)
		end
	end

	addBoldTitles(model, style)
	model:PivotTo(poseAt(center, player, timestamp))
	model.Parent = container -- Never put visual parts inside PlacedObjects.
	return model
end

-- =========================================================
-- LIFECYCLE: ROLE CHANGES / RESPAWN / DISTANCE
-- =========================================================
local function clearBand(state)
	local model = state.model
	state.model = nil
	state.torso = nil
	state.character = nil
	state.role = nil
	if model then model:Destroy() end
end

local function reconcile(player, state, camera, timestamp)
	if not inCreatorSession() or player.Parent ~= Players then
		clearBand(state)
		return
	end

	local role = getRole(player)
	local character = player.Character
	local torso = findTorso(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not role or not torso or not humanoid or humanoid.Health <= 0 then
		clearBand(state)
		return
	end

	if not camera then return end
	local center = ringCenter(torso)
	local limit = CONFIG.MaxDistance + (state.model and CONFIG.DistanceHysteresis or 0)
	if (camera.CFrame.Position - center).Magnitude > limit then
		clearBand(state)
		return
	end

	if CONFIG.HideOwnInFirstPerson and player == localPlayer then
		local head = character:FindFirstChild("Head")
		if head and head:IsA("BasePart") and (camera.CFrame.Position - head.Position).Magnitude < 1.15 then
			clearBand(state)
			return
		end
	end

	if state.model and state.model.Parent == container
		and state.role == role and state.torso == torso and state.character == character then
		return
	end

	clearBand(state)
	state.model = createBand(player, role, center, timestamp)
	state.torso = torso
	state.character = character
	state.role = role
	if CONFIG.Debug then
		print("[ROLE RING V2.1] " .. player.Name .. " -> " .. role)
	end
end

local function watchPlayer(player)
	if states[player] then return end
	local state = {dirty = true, connections = {}}
	states[player] = state

	table.insert(state.connections, player.CharacterAdded:Connect(function()
		clearBand(state)
		state.dirty = true
	end))
	table.insert(state.connections, player.CharacterRemoving:Connect(function()
		clearBand(state)
		state.dirty = true
	end))

	for _, attribute in ipairs({
		"ParkourPrivateCreator", "ParkourCreatorOwner", "ParkourCreatorGuest",
		"ParkourCreatorRole", "ParkourGuestPermissionRole", "ParkourCanCollaborate",
		}) do
		table.insert(state.connections, player:GetAttributeChangedSignal(attribute):Connect(function()
			state.dirty = true
		end))
	end
end

local function unwatchPlayer(player)
	local state = states[player]
	if not state then return end
	for _, connection in ipairs(state.connections) do connection:Disconnect() end
	clearBand(state)
	states[player] = nil
end

local function dirtyAll()
	for _, state in pairs(states) do state.dirty = true end
end

table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
table.insert(connections, Players.PlayerRemoving:Connect(unwatchPlayer))
table.insert(connections, workspace:GetAttributeChangedSignal("ParkourPrivateCreatorServer"):Connect(dirtyAll))
table.insert(connections, workspace:GetAttributeChangedSignal("ParkourCreatorOwnerUserId"):Connect(dirtyAll))
table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(dirtyAll))
for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end

-- ONE frame connection for the whole effect; no timer per letter/label.
local nextRefresh = 0
table.insert(connections, RunService.RenderStepped:Connect(function()
	if not running then return end
	local now = os.clock()
	local refreshAll = now >= nextRefresh
	if refreshAll then nextRefresh = now + CONFIG.RefreshInterval end
	local camera = workspace.CurrentCamera
	local timestamp = workspace:GetServerTimeNow()

	for player, state in pairs(states) do
		if state.dirty or refreshAll then
			state.dirty = false
			reconcile(player, state, camera, timestamp)
		end
		if state.model and state.model.Parent == container then
			if state.torso and state.character == player.Character
				and state.torso:IsDescendantOf(state.character) then
				-- Move one complete rigid visual model, not a radial collection of billboards.
				state.model:PivotTo(poseAt(ringCenter(state.torso), player, timestamp))
			else
				clearBand(state)
				state.dirty = true
			end
		end
	end
end))

local function shutdown(destroyContainer)
	if not running then return end
	running = false
	for _, connection in ipairs(connections) do connection:Disconnect() end
	for player in pairs(states) do unwatchPlayer(player) end
	if destroyContainer and container.Parent then container:Destroy() end
end

table.insert(connections, script.Destroying:Connect(function() shutdown(true) end))
table.insert(connections, container.Destroying:Connect(function() shutdown(false) end))

print("[ROLE RING V2.1] Bold surface letters loaded | no clipped word slices | no billboards")

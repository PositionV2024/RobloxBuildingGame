-- PARKOUR MENU CAMERA NAVIGATION BRIDGE
-- StarterPlayer > StarterPlayerScripts > ParkourMenuNavigationBridge
-- Restores the existing cinematic menu camera when Builder -> Discover is pressed.

local RS=game:GetService("ReplicatedStorage")
local navigationEvent=RS:WaitForChild("ParkourNavigationEvent")
local camera=workspace.CurrentCamera

local function restoreMenuCamera()
	local scene=workspace:FindFirstChild("ParkourMenuScene")
	if not scene then
		warn("[MENU BRIDGE] ParkourMenuScene missing")
		return
	end

	-- Your cinematic setup previously saved camera data as attributes.
	local cf=scene:GetAttribute("SavedMenuCameraCFrame")
	if typeof(cf)~="CFrame" then
		cf=scene:GetAttribute("MenuCameraCFrame")
	end

	-- Also support an actual camera/part marker if one exists.
	if typeof(cf)~="CFrame" then
		local marker=scene:FindFirstChild("MenuCamera",true)
		if marker then
			if marker:IsA("Camera") or marker:IsA("BasePart") then cf=marker.CFrame end
		end
	end

	if typeof(cf)=="CFrame" then
		camera.CameraType=Enum.CameraType.Scriptable
		camera.CFrame=cf
	else
		-- ParkourMenuController can still take over on the next frame.
		warn("[MENU BRIDGE] Saved menu camera CFrame not found; requesting cinematic state only")
	end
end

navigationEvent.Event:Connect(function(destination)
	if destination=="MenuCamera" then
		restoreMenuCamera()
	end
end)

print("✓ Parkour Menu Navigation Bridge loaded")

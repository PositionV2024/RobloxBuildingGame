-- MAKE YOUR OWN PARKOUR - TASK 25 EDITOR POLISH
-- Create StarterPlayer > StarterPlayerScripts > ParkourEditorPolish
-- Cosmetic layer only; does not replace ParkourBuilderClient.

local Players=game:GetService("Players")
local TweenService=game:GetService("TweenService")
local player=Players.LocalPlayer
local pg=player:WaitForChild("PlayerGui")

local function polish(gui)
	for _,o in ipairs(gui:GetDescendants()) do
		if o:IsA("TextButton") then
			if not o:FindFirstChildOfClass("UIStroke") then
				local s=Instance.new("UIStroke")
				s.Color=Color3.fromRGB(88,98,112)
				s.Transparency=.65
				s.Parent=o
			end
			o.MouseEnter:Connect(function()
				TweenService:Create(o,TweenInfo.new(.1),{BackgroundTransparency=.08}):Play()
			end)
			o.MouseLeave:Connect(function()
				TweenService:Create(o,TweenInfo.new(.1),{BackgroundTransparency=0}):Play()
			end)
		elseif o:IsA("Frame") and o.BackgroundTransparency<1 and not o:FindFirstChildOfClass("UIStroke") then
			local s=Instance.new("UIStroke")
			s.Color=Color3.fromRGB(75,85,98)
			s.Transparency=.75
			s.Parent=o
		end
	end
end

local editor=pg:WaitForChild("ParkourBuilderUI",10)
if editor then
	polish(editor)
	editor.DescendantAdded:Connect(function()
		task.defer(function()polish(editor)end)
	end)
end

print("Task 25 Editor polish loaded")

--============================================================
-- MAKE YOUR OWN PARKOUR - MENU UI SKIN
-- Create StarterPlayer > StarterPlayerScripts > ParkourMenuSkin
--
-- Cosmetic upgrade for your CURRENT ParkourDiscoverUI.
-- Does not replace Discover/Search/Details/Play logic.
--============================================================

local Players=game:GetService("Players")
local TweenService=game:GetService("TweenService")

local player=Players.LocalPlayer
local pg=player:WaitForChild("PlayerGui")
local gui=pg:WaitForChild("ParkourDiscoverUI",15)
if not gui then return end

local function styleButton(b)
	if not b:IsA("TextButton") then return end
	local corner=b:FindFirstChildOfClass("UICorner")
	if not corner then
		corner=Instance.new("UICorner")
		corner.CornerRadius=UDim.new(0,10)
		corner.Parent=b
	end

	if not b:FindFirstChildOfClass("UIStroke") then
		local s=Instance.new("UIStroke")
		s.Color=Color3.fromRGB(70,145,235)
		s.Transparency=.72
		s.Parent=b
	end

	local original=b.BackgroundColor3
	b.MouseEnter:Connect(function()
		TweenService:Create(b,TweenInfo.new(.12),{
			BackgroundColor3=original:Lerp(Color3.fromRGB(45,135,255),.22)
		}):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b,TweenInfo.new(.12),{
			BackgroundColor3=original
		}):Play()
	end)
end

local function style()
	for _,o in ipairs(gui:GetDescendants()) do
		if o:IsA("TextButton") then
			styleButton(o)
		elseif o:IsA("TextBox") then
			o.BackgroundColor3=Color3.fromRGB(25,38,55)
			o.BackgroundTransparency=.18
			local c=o:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
			c.CornerRadius=UDim.new(0,12);c.Parent=o
			if not o:FindFirstChildOfClass("UIStroke") then
				local s=Instance.new("UIStroke")
				s.Color=Color3.fromRGB(50,145,255)
				s.Transparency=.45
				s.Parent=o
			end
		end
	end
end

style()
gui.DescendantAdded:Connect(function()
	task.defer(style)
end)

print("✓ Cinematic menu UI skin loaded")

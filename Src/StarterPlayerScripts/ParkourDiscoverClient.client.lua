-- MAKE YOUR OWN PARKOUR - TASK 16 MAIN MENU / DISCOVER CLIENT
-- Create StarterPlayer > StarterPlayerScripts > ParkourDiscoverClient
--
-- M toggles Discover.
-- Browse NEW, MOST PLAYED, MOST LIKED, or MY CREATIONS.
-- PLAY is intentionally disabled until Task 18 (Community Play System).

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local Lighting=game:GetService("Lighting")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")

local player=Players.LocalPlayer
local remote=RS:WaitForChild("ParkourDiscoverEvent")
local detailsRemote=RS:WaitForChild("ParkourDetailsEvent")
local communityRemote=RS:WaitForChild("ParkourCommunityEvent")
local socialRemote=RS:WaitForChild("ParkourSocialEvent")
local leaderboardRemote=RS:WaitForChild("ParkourLeaderboardEvent")
local profileRemote=RS:WaitForChild("ParkourCreatorProfileEvent")
local searchRemote=RS:WaitForChild("ParkourSearchEvent")
local deleteRemote=RS:WaitForChild("ParkourDeleteEvent")
local creatorModeRemote=RS:WaitForChild("ParkourCreatorModeEvent")
-- Reserved-server CREATE flow.
local createPrivateRemote=RS:WaitForChild("ParkourCreatePrivateServer")
local navigationEvent=RS:FindFirstChild("ParkourNavigationEvent") or Instance.new("BindableEvent")
navigationEvent.Name="ParkourNavigationEvent"
navigationEvent.Parent=RS
local currentCreatorUserId=nil
local currentCreatorName=nil
local currentParkourId=nil
local request -- forward declaration for navigation callbacks
local communityPlaying=false
local playerGui=player:WaitForChild("PlayerGui")

local function setEditorVisible(visible)
	local editor=playerGui:FindFirstChild("ParkourBuilderUI")
	if editor then editor.Enabled=visible end
end

local gui=Instance.new("ScreenGui")
gui.Name="ParkourDiscoverUI"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=true
gui.Parent=playerGui

-- DUPLICATE DISCOVER UI GUARD
local function removeDuplicateDiscoverUIs()
	for _,other in ipairs(playerGui:GetChildren()) do
		if other:IsA("ScreenGui") and other.Name=="ParkourDiscoverUI" and other~=gui then
			warn("[UI GUARD] Removing duplicate ParkourDiscoverUI:",other:GetFullName())
			other:Destroy()
		end
	end
end

task.defer(removeDuplicateDiscoverUIs)


local overlay=Instance.new("Frame")
overlay.Size=UDim2.fromScale(1,1)
overlay.BackgroundColor3=Color3.fromRGB(18,22,28)
overlay.BackgroundTransparency=.42
overlay.BorderSizePixel=0
overlay.Parent=gui

local header=Instance.new("Frame")
header.Size=UDim2.new(1,0,0,76)
header.BackgroundColor3=Color3.fromRGB(27,32,40)
header.BorderSizePixel=0
header.Parent=overlay

local title=Instance.new("TextLabel")
title.Size=UDim2.fromOffset(420,48)
title.Position=UDim2.fromOffset(150,14)
title.BackgroundTransparency=1
title.Text="MAKE YOUR OWN PARKOUR\nDiscover • Create • Challenge"
title.TextXAlignment=Enum.TextXAlignment.Left
title.Font=Enum.Font.GothamBlack
title.TextSize=21
title.TextColor3=Color3.new(1,1,1)
title.Parent=header

local close=Instance.new("TextButton")
close.Size=UDim2.fromOffset(110,42)
close.Position=UDim2.new(1,-130,0,20)
close.BackgroundColor3=Color3.fromRGB(58,65,76)
close.BorderSizePixel=0
close.Text="CREATE"
close.Font=Enum.Font.GothamBold
close.TextSize=14
close.TextColor3=Color3.new(1,1,1)
close.Parent=header

local searchBox=Instance.new("TextBox")
searchBox.Size=UDim2.new(1,-190,0,42)
searchBox.Position=UDim2.fromOffset(28,92)
searchBox.BackgroundColor3=Color3.fromRGB(43,50,60)
searchBox.BorderSizePixel=0
searchBox.PlaceholderText="Search parkours, creators, or exact Parkour ID..."
searchBox.PlaceholderColor3=Color3.fromRGB(155,164,174)
searchBox.Text=""
searchBox.ClearTextOnFocus=false
searchBox.Font=Enum.Font.Gotham
searchBox.TextSize=16
searchBox.TextColor3=Color3.new(1,1,1)
searchBox.Parent=overlay
local searchCorner=Instance.new("UICorner")
searchCorner.CornerRadius=UDim.new(0,9)
searchCorner.Parent=searchBox

local searchButton=Instance.new("TextButton")
searchButton.Size=UDim2.fromOffset(120,42)
searchButton.Position=UDim2.new(1,-148,0,92)
searchButton.BackgroundColor3=Color3.fromRGB(70,130,205)
searchButton.BorderSizePixel=0
searchButton.Text="SEARCH"
searchButton.Font=Enum.Font.GothamBlack
searchButton.TextSize=14
searchButton.TextColor3=Color3.new(1,1,1)
searchButton.Parent=overlay
local searchButtonCorner=Instance.new("UICorner")
searchButtonCorner.CornerRadius=UDim.new(0,9)
searchButtonCorner.Parent=searchButton

local tabs=Instance.new("Frame")
tabs.Size=UDim2.new(1,-40,0,52)
tabs.Position=UDim2.fromOffset(28,145)
tabs.BackgroundTransparency=1
tabs.Parent=overlay

local tabLayout=Instance.new("UIListLayout")
tabLayout.FillDirection=Enum.FillDirection.Horizontal
tabLayout.Padding=UDim.new(0,8)
tabLayout.Parent=tabs

local function button(parent,text,w)
	local b=Instance.new("TextButton")
	b.Size=UDim2.fromOffset(w or 130,42)
	b.BackgroundColor3=Color3.fromRGB(53,61,72)
	b.BorderSizePixel=0
	b.Text=text
	b.Font=Enum.Font.GothamBold
	b.TextSize=14
	b.TextColor3=Color3.new(1,1,1)
	b.Parent=parent
	local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,8);c.Parent=b
	return b
end

local newTab=button(tabs,"NEW",105)
local playedTab=button(tabs,"MOST PLAYED",135)
local likedTab=button(tabs,"MOST LIKED",130)
local mineTab=button(tabs,"MY CREATIONS",145)

local heading=Instance.new("TextLabel")
heading.Size=UDim2.new(1,-50,0,42)
heading.Position=UDim2.fromOffset(28,202)
heading.BackgroundTransparency=1
heading.Text="NEW PARKOURS"
heading.TextXAlignment=Enum.TextXAlignment.Left
heading.Font=Enum.Font.GothamBlack
heading.TextSize=20
heading.TextColor3=Color3.fromRGB(225,230,235)
heading.Parent=overlay

local scroll=Instance.new("ScrollingFrame")
scroll.Size=UDim2.new(1,-50,1,-264)
scroll.Position=UDim2.fromOffset(25,247)
scroll.BackgroundTransparency=1
scroll.BorderSizePixel=0
scroll.ScrollBarThickness=7
scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
scroll.CanvasSize=UDim2.new()
scroll.Parent=overlay

local grid=Instance.new("UIGridLayout")
grid.CellSize=UDim2.fromOffset(280,190)
grid.CellPadding=UDim2.fromOffset(14,14)
grid.Parent=scroll

local loading=Instance.new("TextLabel")
loading.Size=UDim2.fromOffset(300,50)
loading.Position=UDim2.new(.5,-150,.5,-25)
loading.BackgroundTransparency=1
loading.Text="◌  LOADING PARKOURS..."
loading.Font=Enum.Font.GothamBold
loading.TextSize=16
loading.TextColor3=Color3.fromRGB(170,178,188)
loading.Parent=overlay

local function clearCards()
	for _,o in ipairs(scroll:GetChildren()) do
		if o:IsA("Frame") then o:Destroy() end
	end
end

local function performSearch()
	local q=searchBox.Text
	q=q:match("^%s*(.-)%s*$") or ""
	if #q<2 then
		heading.Text="TYPE AT LEAST 2 CHARACTERS"
		return
	end
	loading.Visible=true
	loading.Text="⌕  SEARCHING..."
	clearCards()
	heading.Text='SEARCH RESULTS FOR "'..q..'"'
	searchRemote:FireServer("Search",q)
end

searchButton.MouseButton1Click:Connect(performSearch)
searchBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then performSearch() end
end)

local difficultyColor={
	Easy=Color3.fromRGB(90,205,120),
	Medium=Color3.fromRGB(235,195,70),
	Hard=Color3.fromRGB(235,125,70),
	Extreme=Color3.fromRGB(220,75,95)
}


-- TASK 17: Parkour details page.
local detailsPanel=Instance.new("Frame")
detailsPanel.Size=UDim2.new(1,-70,1,-125)
detailsPanel.Position=UDim2.fromOffset(35,100)
detailsPanel.BackgroundColor3=Color3.fromRGB(25,30,38)
detailsPanel.BackgroundTransparency=.06
detailsPanel.BorderSizePixel=0
detailsPanel.Visible=false
detailsPanel.ZIndex=20
detailsPanel.Parent=overlay
local dc=Instance.new("UICorner");dc.CornerRadius=UDim.new(0,14);dc.Parent=detailsPanel

local back=button(detailsPanel,"← BACK",105)
back.Position=UDim2.fromOffset(18,18)
back.ZIndex=21

local detailsTitle=Instance.new("TextLabel")
detailsTitle.Size=UDim2.new(1,-180,0,48)
detailsTitle.Position=UDim2.fromOffset(140,16)
detailsTitle.BackgroundTransparency=1
detailsTitle.Text="PARKOUR"
detailsTitle.TextXAlignment=Enum.TextXAlignment.Left
detailsTitle.Font=Enum.Font.GothamBlack
detailsTitle.TextSize=26
detailsTitle.TextColor3=Color3.new(1,1,1)
detailsTitle.ZIndex=21
detailsTitle.Parent=detailsPanel

local hero=Instance.new("Frame")
hero.Size=UDim2.new(.46,-25,0,255)
hero.Position=UDim2.fromOffset(20,82)
hero.BackgroundColor3=Color3.fromRGB(57,67,80)
hero.BorderSizePixel=0
hero.ZIndex=21
hero.Parent=detailsPanel
local heroCorner=Instance.new("UICorner");heroCorner.CornerRadius=UDim.new(0,12);heroCorner.Parent=hero
local heroIcon=Instance.new("TextLabel")
heroIcon.Size=UDim2.fromScale(1,1);heroIcon.BackgroundTransparency=1;heroIcon.Text="🏃";heroIcon.TextSize=72;heroIcon.ZIndex=22;heroIcon.Parent=hero

local info=Instance.new("Frame")
info.Size=UDim2.new(.54,-35,0,300)
info.Position=UDim2.new(.46,15,0,82)
info.BackgroundTransparency=1
info.ZIndex=21
info.Parent=detailsPanel

local creator=Instance.new("TextLabel")
creator.Size=UDim2.new(1,0,0,30);creator.BackgroundTransparency=1;creator.TextXAlignment=Enum.TextXAlignment.Left
creator.Font=Enum.Font.GothamBold;
creator.TextSize=16;creator.TextColor3=Color3.fromRGB(185,192,201);creator.ZIndex=22;creator.Parent=info

local creatorOpen=Instance.new("TextButton")
creatorOpen.Size=UDim2.new(1,0,0,34)
creatorOpen.Position=UDim2.fromOffset(0,0)
creatorOpen.BackgroundTransparency=1
creatorOpen.Text=""
creatorOpen.ZIndex=23
creatorOpen.Parent=info


local difficulty=Instance.new("TextLabel")
difficulty.Size=UDim2.fromOffset(150,32);difficulty.Position=UDim2.fromOffset(0,40);difficulty.BorderSizePixel=0
difficulty.Font=Enum.Font.GothamBlack;difficulty.TextSize=14;difficulty.TextColor3=Color3.new(1,1,1);difficulty.ZIndex=22;difficulty.Parent=info
local diffCorner=Instance.new("UICorner");diffCorner.CornerRadius=UDim.new(0,8);diffCorner.Parent=difficulty

local stats=Instance.new("TextLabel")
stats.Size=UDim2.new(1,0,0,34);stats.Position=UDim2.fromOffset(0,84);stats.BackgroundTransparency=1
stats.TextXAlignment=Enum.TextXAlignment.Left;stats.Font=Enum.Font.GothamBold;stats.TextSize=15
stats.TextColor3=Color3.fromRGB(210,215,221);stats.ZIndex=22;stats.Parent=info

local verified=Instance.new("TextLabel")
verified.Size=UDim2.new(1,0,0,28);verified.Position=UDim2.fromOffset(0,120);verified.BackgroundTransparency=1
verified.TextXAlignment=Enum.TextXAlignment.Left;verified.Font=Enum.Font.Gotham;verified.TextSize=14
verified.TextColor3=Color3.fromRGB(145,210,175);verified.ZIndex=22;verified.Parent=info

local published=Instance.new("TextLabel")
published.Size=UDim2.new(1,0,0,28)
published.Position=UDim2.fromOffset(0,148)
published.BackgroundTransparency=1
published.TextXAlignment=Enum.TextXAlignment.Left
published.Font=Enum.Font.Gotham
published.TextSize=14
published.TextColor3=Color3.fromRGB(160,170,182)
published.ZIndex=22
published.Parent=info

local description=Instance.new("TextLabel")
description.Size=UDim2.new(1,0,0,90);description.Position=UDim2.fromOffset(0,180);description.BackgroundTransparency=1
description.TextWrapped=true;description.TextXAlignment=Enum.TextXAlignment.Left;description.TextYAlignment=Enum.TextYAlignment.Top
description.Font=Enum.Font.Gotham;description.TextSize=15;description.TextColor3=Color3.fromRGB(190,196,204);description.ZIndex=22;description.Parent=info

local leaderboardButton=button(detailsPanel,"🏆 TIMES",115)
leaderboardButton.Position=UDim2.new(1,-135,0,18)
leaderboardButton.ZIndex=21

local leaderboardPanel=Instance.new("Frame")
leaderboardPanel.Size=UDim2.fromOffset(430,420)
leaderboardPanel.Position=UDim2.new(.5,-215,.5,-210)
leaderboardPanel.BackgroundColor3=Color3.fromRGB(25,30,38)
leaderboardPanel.BackgroundTransparency=.06
leaderboardPanel.BorderSizePixel=0
leaderboardPanel.Visible=false
leaderboardPanel.ZIndex=50
leaderboardPanel.Parent=overlay
local lbc=Instance.new("UICorner");lbc.CornerRadius=UDim.new(0,14);lbc.Parent=leaderboardPanel

local leaderboardTitle=Instance.new("TextLabel")
leaderboardTitle.Size=UDim2.new(1,-80,0,50);leaderboardTitle.Position=UDim2.fromOffset(18,12)
leaderboardTitle.BackgroundTransparency=1;leaderboardTitle.Text="🏆 FASTEST TIMES"
leaderboardTitle.TextXAlignment=Enum.TextXAlignment.Left;leaderboardTitle.Font=Enum.Font.GothamBlack
leaderboardTitle.TextSize=20;leaderboardTitle.TextColor3=Color3.new(1,1,1);leaderboardTitle.ZIndex=51;leaderboardTitle.Parent=leaderboardPanel

local leaderboardClose=Instance.new("TextButton")
leaderboardClose.Size=UDim2.fromOffset(45,40);leaderboardClose.Position=UDim2.new(1,-58,0,14)
leaderboardClose.BackgroundColor3=Color3.fromRGB(60,67,78);leaderboardClose.BorderSizePixel=0
leaderboardClose.Text="×";leaderboardClose.Font=Enum.Font.GothamBlack;leaderboardClose.TextSize=22
leaderboardClose.TextColor3=Color3.new(1,1,1);leaderboardClose.ZIndex=51;leaderboardClose.Parent=leaderboardPanel

local leaderboardRows=Instance.new("Frame")
leaderboardRows.Size=UDim2.new(1,-36,1,-82);leaderboardRows.Position=UDim2.fromOffset(18,68)
leaderboardRows.BackgroundTransparency=1;leaderboardRows.ZIndex=51;leaderboardRows.Parent=leaderboardPanel
local leaderboardLayout=Instance.new("UIListLayout")
leaderboardLayout.Padding=UDim.new(0,5);leaderboardLayout.Parent=leaderboardRows

local function showBoard(entries)
	for _,o in ipairs(leaderboardRows:GetChildren()) do
		if o:IsA("TextLabel") then o:Destroy() end
	end

	if type(entries)~="table" or #entries==0 then
		local empty=Instance.new("TextLabel")
		empty.Size=UDim2.new(1,0,0,45);empty.BackgroundTransparency=1
		empty.Text="No completion times yet. Be the first!"
		empty.Font=Enum.Font.GothamBold;empty.TextSize=15;empty.TextColor3=Color3.fromRGB(170,178,188)
		empty.ZIndex=52;empty.Parent=leaderboardRows
		return
	end

	for rank,e in ipairs(entries) do
		local row=Instance.new("TextLabel")
		row.Size=UDim2.new(1,0,0,30)
		row.BackgroundColor3=rank==1 and Color3.fromRGB(92,76,38) or Color3.fromRGB(43,49,59)
		row.BackgroundTransparency=.12
		row.BorderSizePixel=0
		row.TextXAlignment=Enum.TextXAlignment.Left
		row.Text="  #"..rank.."   "..tostring(e.name).."                         "..string.format("%.2fs",tonumber(e.time) or 0)
		row.Font=rank<=3 and Enum.Font.GothamBlack or Enum.Font.GothamBold
		row.TextSize=14
		row.TextColor3=Color3.new(1,1,1)
		row.ZIndex=52
		row.Parent=leaderboardRows
	end
end

leaderboardClose.MouseButton1Click:Connect(function()
	leaderboardPanel.Visible=false
	detailsPanel.Visible=true
	local blocker=gui:FindFirstChild("ModalBlocker")
	if blocker then blocker.Visible=false end
	local blur=Lighting:FindFirstChild("ParkourPopupBlur")
	if blur then blur.Size=0 end
	local blur=Lighting:FindFirstChild("ParkourPopupBlur")
	if blur then blur.Enabled=false end
end)

leaderboardButton.MouseButton1Click:Connect(function()
	if currentParkourId then
		local blocker=gui:FindFirstChild("ModalBlocker")
		if blocker then blocker.Visible=true end
		local blur=Lighting:FindFirstChild("ParkourPopupBlur")
		if blur then blur.Enabled=true end
		local blur=Lighting:FindFirstChild("ParkourPopupBlur")
		if blur then blur.Size=7 end
		detailsPanel.Visible=false
		leaderboardPanel.Visible=true
		showBoard({})
		leaderboardRemote:FireServer("Get",currentParkourId)
	end
end)

local likeButton=button(detailsPanel,"♡ LIKE",125)
likeButton.Position=UDim2.new(0,20,1,-62)
likeButton.ZIndex=21

local dislikeButton=button(detailsPanel,"♢ DISLIKE",125)
dislikeButton.Position=UDim2.new(0,155,1,-62)
dislikeButton.ZIndex=21

local favoriteButton=button(detailsPanel,"☆ FAVORITE",145)
favoriteButton.Position=UDim2.new(0,290,1,-62)
favoriteButton.ZIndex=21

local likedCurrent=false
local dislikedCurrent=false
local favoritedCurrent=false

local deleteCreation=button(detailsPanel,"DELETE CREATION",155)
deleteCreation.Position=UDim2.new(1,-365,1,-62)
deleteCreation.BackgroundColor3=Color3.fromRGB(170,58,65)
deleteCreation.Visible=false
deleteCreation.ZIndex=21

local deleteModal=Instance.new("Frame")
deleteModal.Size=UDim2.fromOffset(420,220)
deleteModal.Position=UDim2.new(.5,-210,.5,-110)
deleteModal.BackgroundColor3=Color3.fromRGB(28,33,41)
deleteModal.BorderSizePixel=0
deleteModal.Visible=false
deleteModal.ZIndex=90
deleteModal.Parent=overlay
local dmc=Instance.new("UICorner");dmc.CornerRadius=UDim.new(0,14);dmc.Parent=deleteModal

local deleteTitle=Instance.new("TextLabel")
deleteTitle.Size=UDim2.new(1,-30,0,45);deleteTitle.Position=UDim2.fromOffset(15,15)
deleteTitle.BackgroundTransparency=1;deleteTitle.Text="DELETE THIS PARKOUR?"
deleteTitle.Font=Enum.Font.GothamBlack;deleteTitle.TextSize=20;deleteTitle.TextColor3=Color3.new(1,1,1)
deleteTitle.ZIndex=91;deleteTitle.Parent=deleteModal

local deleteWarning=Instance.new("TextLabel")
deleteWarning.Size=UDim2.new(1,-40,0,75);deleteWarning.Position=UDim2.fromOffset(20,62)
deleteWarning.BackgroundTransparency=1;deleteWarning.TextWrapped=true
deleteWarning.Text="This permanently removes the creation from Discover and prevents players from playing it."
deleteWarning.Font=Enum.Font.Gotham;deleteWarning.TextSize=15;deleteWarning.TextColor3=Color3.fromRGB(190,196,204)
deleteWarning.ZIndex=91;deleteWarning.Parent=deleteModal

local confirmDelete=button(deleteModal,"DELETE",175)
confirmDelete.Position=UDim2.fromOffset(20,155)
confirmDelete.BackgroundColor3=Color3.fromRGB(190,55,65)
confirmDelete.ZIndex=91

local cancelDelete=button(deleteModal,"CANCEL",175)
cancelDelete.Position=UDim2.fromOffset(225,155)
cancelDelete.ZIndex=91

cancelDelete.MouseButton1Click:Connect(function()
	deleteModal.Visible=false
	setPopupBlur(false)
end)

deleteCreation.MouseButton1Click:Connect(function()
	if currentParkourId then deleteModal.Visible=true;setPopupBlur(true) end
end)

confirmDelete.MouseButton1Click:Connect(function()
	if not currentParkourId then return end
	confirmDelete.Active=false
	confirmDelete.BackgroundTransparency=.5
	deleteRemote:FireServer("Delete",currentParkourId)
end)

local visitorsLabel=Instance.new("TextLabel")
visitorsLabel.Size=UDim2.fromOffset(245,18)
visitorsLabel.Position=UDim2.new(1,-655,1,-58)
visitorsLabel.BackgroundTransparency=1
visitorsLabel.Text="RECENT VISITORS"
visitorsLabel.TextXAlignment=Enum.TextXAlignment.Right
visitorsLabel.Font=Enum.Font.GothamBlack
visitorsLabel.TextSize=12
visitorsLabel.TextColor3=Color3.fromRGB(155,165,178)
visitorsLabel.ZIndex=21
visitorsLabel.Parent=detailsPanel

local visitorsRow=Instance.new("Frame")
visitorsRow.Size=UDim2.fromOffset(245,36)
visitorsRow.Position=UDim2.new(1,-655,1,-38)
visitorsRow.BackgroundTransparency=1
visitorsRow.ZIndex=21
visitorsRow.Parent=detailsPanel
local visitorsLayout=Instance.new("UIListLayout")
visitorsLayout.FillDirection=Enum.FillDirection.Horizontal
visitorsLayout.HorizontalAlignment=Enum.HorizontalAlignment.Right
visitorsLayout.Padding=UDim.new(0,8)
visitorsLayout.Parent=visitorsRow

local openProfile -- forward declaration for clickable visitor avatars

local function clearVisitors()
	for _,o in ipairs(visitorsRow:GetChildren()) do
		if o:IsA("ImageButton") then o:Destroy() end
	end
end

local function showRecentVisitors(list)
	clearVisitors()
	if type(list)~="table" or #list==0 then
		visitorsLabel.Text="RECENT VISITORS • NONE YET"
		return
	end
	visitorsLabel.Text="RECENT VISITORS"
	for i,v in ipairs(list) do
		if i>6 then break end
		local img=Instance.new("ImageButton")
		img.Size=UDim2.fromOffset(34,34)
		img.BackgroundColor3=Color3.fromRGB(52,60,72)
		img.BorderSizePixel=0
		img.AutoButtonColor=true
		img.ZIndex=22
		img.Parent=visitorsRow
		local c=Instance.new("UICorner");c.CornerRadius=UDim.new(1,0);c.Parent=img
		task.spawn(function()
			local ok,url=pcall(function()
				return Players:GetUserThumbnailAsync(tonumber(v.userId) or 0,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size100x100)
			end)
			if ok and img.Parent then img.Image=url end
		end)
		img.MouseButton1Click:Connect(function()
			if tonumber(v.userId) then
				openProfile(tonumber(v.userId),tostring(v.name or "Unknown"))
			end
		end)
	end
end

local playDetails=button(detailsPanel,"PLAY",170)
playDetails.Position=UDim2.new(1,-190,1,-62)
playDetails.BackgroundColor3=Color3.fromRGB(65,180,115)
playDetails.BackgroundTransparency=0
playDetails.ZIndex=21

local idLabel=Instance.new("TextLabel")
idLabel.Size=UDim2.new(1,-230,0,30);idLabel.Position=UDim2.new(0,20,1,-55);idLabel.BackgroundTransparency=1
idLabel.TextXAlignment=Enum.TextXAlignment.Left;idLabel.Font=Enum.Font.Code;idLabel.TextSize=12
idLabel.TextColor3=Color3.fromRGB(130,138,148);idLabel.ZIndex=21;idLabel.Parent=detailsPanel

local detailColors={
	Easy=Color3.fromRGB(70,170,95),
	Medium=Color3.fromRGB(185,145,55),
	Hard=Color3.fromRGB(190,95,55),
	Extreme=Color3.fromRGB(175,60,80)
}

local function publicationText(timestamp)
	timestamp=tonumber(timestamp) or 0
	if timestamp<=0 then return "Published date unavailable" end

	local now=os.time()
	local age=math.max(0,now-timestamp)
	local days=math.floor(age/86400)

	local date=os.date("%d %b %Y",timestamp)
	local ago

	if days==0 then
		local hours=math.floor(age/3600)
		if hours<=0 then
			local mins=math.max(1,math.floor(age/60))
			ago=mins==1 and "1 minute ago" or mins.." minutes ago"
		else
			ago=hours==1 and "1 hour ago" or hours.." hours ago"
		end
	elseif days==1 then
		ago="1 day ago"
	else
		ago=days.." days ago"
	end

	return "Published "..date.."  •  "..ago
end

local function openDetails(id)
	detailsPanel.Visible=true
	detailsTitle.Text="LOADING..."
	creator.Text=""
	difficulty.Text=""
	stats.Text=""
	verified.Text=""
	published.Text=""
	description.Text=""
	idLabel.Text=""
	detailsRemote:FireServer("GetDetails",id)
end

back.MouseButton1Click:Connect(function()
	detailsPanel.Visible=false
end)


-- TASK 21: Creator profile panel.
local profilePanel=Instance.new("Frame")
profilePanel.Size=UDim2.new(1,-70,1,-125)
profilePanel.Position=UDim2.fromOffset(35,100)
profilePanel.BackgroundColor3=Color3.fromRGB(25,30,38)
profilePanel.BackgroundTransparency=0
profilePanel.BorderSizePixel=0
profilePanel.Visible=false
profilePanel.ZIndex=50
profilePanel.Parent=overlay
local prc=Instance.new("UICorner");prc.CornerRadius=UDim.new(0,14);prc.Parent=profilePanel

local profileBack=button(profilePanel,"← BACK",105)
profileBack.Position=UDim2.fromOffset(18,18)
profileBack.ZIndex=51

local avatar=Instance.new("ImageLabel")
avatar.Size=UDim2.fromOffset(110,110)
avatar.Position=UDim2.fromOffset(28,82)
avatar.BackgroundColor3=Color3.fromRGB(55,64,76)
avatar.BorderSizePixel=0
avatar.Image=""
avatar.ZIndex=51
avatar.Parent=profilePanel
local avc=Instance.new("UICorner");avc.CornerRadius=UDim.new(1,0);avc.Parent=avatar

local profileName=Instance.new("TextLabel")
profileName.Size=UDim2.new(1,-190,0,48)
profileName.Position=UDim2.fromOffset(160,82)
profileName.BackgroundTransparency=1
profileName.Text="@CREATOR"
profileName.TextXAlignment=Enum.TextXAlignment.Left
profileName.Font=Enum.Font.GothamBlack
profileName.TextSize=26
profileName.TextColor3=Color3.new(1,1,1)
profileName.ZIndex=51
profileName.Parent=profilePanel

local profileStats=Instance.new("TextLabel")
profileStats.Size=UDim2.new(1,-190,0,60)
profileStats.Position=UDim2.fromOffset(160,130)
profileStats.BackgroundTransparency=1
profileStats.TextXAlignment=Enum.TextXAlignment.Left
profileStats.TextYAlignment=Enum.TextYAlignment.Top
profileStats.Font=Enum.Font.GothamBold
profileStats.TextSize=15
profileStats.TextColor3=Color3.fromRGB(185,192,201)
profileStats.ZIndex=51
profileStats.Parent=profilePanel

local creationsTitle=Instance.new("TextLabel")
creationsTitle.Size=UDim2.new(1,-50,0,36)
creationsTitle.Position=UDim2.fromOffset(28,215)
creationsTitle.BackgroundTransparency=1
creationsTitle.Text="PUBLISHED PARKOURS"
creationsTitle.TextXAlignment=Enum.TextXAlignment.Left
creationsTitle.Font=Enum.Font.GothamBlack
creationsTitle.TextSize=18
creationsTitle.TextColor3=Color3.new(1,1,1)
creationsTitle.ZIndex=51
creationsTitle.Parent=profilePanel

local profileScroll=Instance.new("ScrollingFrame")
profileScroll.Size=UDim2.new(1,-56,1,-275)
profileScroll.Position=UDim2.fromOffset(28,255)
profileScroll.BackgroundTransparency=1
profileScroll.BorderSizePixel=0
profileScroll.ScrollBarThickness=6
profileScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
profileScroll.CanvasSize=UDim2.new()
profileScroll.ZIndex=51
profileScroll.Parent=profilePanel

local profileList=Instance.new("UIListLayout")
profileList.Padding=UDim.new(0,7)
profileList.Parent=profileScroll

local function clearProfileCourses()
	for _,o in ipairs(profileScroll:GetChildren()) do
		if o:IsA("TextButton") then o:Destroy() end
	end
end

openProfile=function(userId,name)
	profilePanel.Visible=true
	profileName.Text="LOADING..."
	profileStats.Text=""
	clearProfileCourses()
	profileRemote:FireServer("GetProfile",userId,name)
end

profileBack.MouseButton1Click:Connect(function()
	profilePanel.Visible=false
	detailsPanel.Visible=true
	local blocker=gui:FindFirstChild("ModalBlocker")
	if blocker then blocker.Visible=false end
	local blur=Lighting:FindFirstChild("ParkourPopupBlur")
	if blur then blur.Size=0 end
	local blur=Lighting:FindFirstChild("ParkourPopupBlur")
	if blur then blur.Enabled=false end
end)

creatorOpen.MouseButton1Click:Connect(function()
	if currentCreatorUserId then
		openProfile(currentCreatorUserId,currentCreatorName)
	end
end)

profileRemote.OnClientEvent:Connect(function(action,data)
	if action~="Profile" or type(data)~="table" then return end

	profileName.Text="@"..tostring(data.name)
	profileStats.Text=
		tostring(data.creationCount or 0).." creations     ▶ "..tostring(data.totalPlays or 0).." plays\n"
		.."♥ "..tostring(data.totalLikes or 0).." likes     ◆ "..tostring(data.totalDislikes or 0).." dislikes"

	-- Roblox headshot thumbnail.
	local ok,image=pcall(function()
		return Players:GetUserThumbnailAsync(
			tonumber(data.userId) or 0,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size150x150
		)
	end)
	if ok then avatar.Image=image end

	clearProfileCourses()

	if type(data.courses)~="table" or #data.courses==0 then
		local empty=Instance.new("TextButton")
		empty.Size=UDim2.new(1,-8,0,45)
		empty.BackgroundColor3=Color3.fromRGB(42,48,58)
		empty.Text="No published parkours"
		empty.Font=Enum.Font.GothamBold
		empty.TextSize=14
		empty.TextColor3=Color3.fromRGB(165,172,181)
		empty.AutoButtonColor=false
		empty.ZIndex=52
		empty.Parent=profileScroll
		return
	end

	for _,course in ipairs(data.courses) do
		local row=Instance.new("TextButton")
		row.Size=UDim2.new(1,-8,0,54)
		row.BackgroundColor3=Color3.fromRGB(42,48,58)
		row.BorderSizePixel=0
		row.TextXAlignment=Enum.TextXAlignment.Left
		row.Text="  "..tostring(course.title)
			.."     ["..tostring(course.difficulty).."]"
			.."     ▶ "..tostring(course.plays or 0)
			.."     ♥ "..tostring(course.likes or 0)
		row.Font=Enum.Font.GothamBold
		row.TextSize=14
		row.TextColor3=Color3.new(1,1,1)
		row.ZIndex=52
		row.Parent=profileScroll
		local rc=Instance.new("UICorner");rc.CornerRadius=UDim.new(0,8);rc.Parent=row

		row.MouseButton1Click:Connect(function()
			profilePanel.Visible=false
			openDetails(tostring(course.id))
		end)
	end
end)

deleteRemote.OnClientEvent:Connect(function(action,success,message)
	if action~="DeleteResult" then return end
	confirmDelete.Active=true
	confirmDelete.BackgroundTransparency=0

	if success then
		deleteModal.Visible=false
		local blocker=gui:FindFirstChild("ModalBlocker")
		if blocker then blocker.Visible=false end
		local blur=Lighting:FindFirstChild("ParkourPopupBlur")
		if blur then blur.Size=0 end
		local blur=Lighting:FindFirstChild("ParkourPopupBlur")
		if blur then blur.Enabled=false end
		detailsPanel.Visible=false
		currentParkourId=nil
		status.Text="✓ CREATION DELETED"
		task.delay(2.5,function()
			if status then update() end
		end)
		remote:FireServer("Discover","New")
	else
		deleteWarning.Text=tostring(message or "Delete failed.")
		deleteWarning.TextColor3=Color3.fromRGB(255,130,130)
	end
end)

detailsRemote.OnClientEvent:Connect(function(action,data)
	if action=="DetailsError" then
		detailsTitle.Text="COULD NOT LOAD"
		description.Text=tostring(data)
		return
	end
	if action~="Details" or type(data)~="table" then return end

	detailsTitle.Text=tostring(data.title)
	creator.Text="Created by  @"..tostring(data.creatorName).."   ›"
	currentCreatorUserId=tonumber(data.creatorUserId)
	currentCreatorName=tostring(data.creatorName)
	deleteCreation.Visible=(currentCreatorUserId==player.UserId)
	if deleteCreation.Visible then
		visitorsLabel.Position=UDim2.new(1,-655,1,-58)
		visitorsRow.Position=UDim2.new(1,-655,1,-38)
	else
		visitorsLabel.Position=UDim2.new(1,-485,1,-58)
		visitorsRow.Position=UDim2.new(1,-485,1,-38)
	end
	difficulty.Text=string.upper(tostring(data.difficulty))
	difficulty.BackgroundColor3=detailColors[data.difficulty] or Color3.fromRGB(80,90,105)
	stats.Text="▶ "..tostring(data.plays or 0).." plays     👥 "..tostring(data.visitorCount or 0).." visitors     ♥ "..tostring(data.likes or 0).." likes     ▣ "..tostring(data.objectCount or 0).." objects"

	if type(data.verifiedTime)=="number" then
		verified.Text="✓ Creator verified in "..string.format("%.2f",data.verifiedTime).."s"
	else
		verified.Text="✓ Creator verified"
	end

	published.Text=publicationText(data.publishedAt)
	showRecentVisitors(data.recentVisitors)
	description.Text=tostring(data.description or "No description.")
	idLabel.Text="Parkour ID: "..tostring(data.id)
	currentParkourId=tostring(data.id)
	likedCurrent=false
	dislikedCurrent=false
	favoritedCurrent=false
	likeButton.Text="♡ LIKE"
	dislikeButton.Text="♢ DISLIKE"
	favoriteButton.Text="☆ FAVORITE"
	socialRemote:FireServer("GetState",currentParkourId)
end)

local function card(data)
	local f=Instance.new("Frame")
	f.BackgroundColor3=Color3.fromRGB(34,40,49)
	f.BorderSizePixel=0
	f.Parent=scroll
	local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,12);corner.Parent=f
	local border=Instance.new("UIStroke");border.Color=Color3.fromRGB(72,82,96);border.Transparency=.55;border.Parent=f

	-- Placeholder thumbnail until thumbnail generation is added later.
	local thumb=Instance.new("Frame")
	thumb.Size=UDim2.new(1,-16,0,82)
	thumb.Position=UDim2.fromOffset(8,8)
	thumb.BackgroundColor3=Color3.fromRGB(62,72,86)
	thumb.BorderSizePixel=0
	thumb.Parent=f
	local tc=Instance.new("UICorner");tc.CornerRadius=UDim.new(0,8);tc.Parent=thumb

	local icon=Instance.new("TextLabel")
	icon.Size=UDim2.fromScale(1,1);icon.BackgroundTransparency=1
	icon.Text="🏃\n"..string.upper(tostring(data.difficulty or "MEDIUM"));icon.TextSize=22;icon.Font=Enum.Font.GothamBlack;icon.TextColor3=Color3.fromRGB(225,230,235);icon.Parent=thumb

	local name=Instance.new("TextLabel")
	name.Size=UDim2.new(1,-16,0,28);name.Position=UDim2.fromOffset(8,94)
	name.BackgroundTransparency=1;name.Text=tostring(data.title or "Untitled")
	name.TextXAlignment=Enum.TextXAlignment.Left;name.TextTruncate=Enum.TextTruncate.AtEnd
	name.Font=Enum.Font.GothamBlack;name.TextSize=16;name.TextColor3=Color3.new(1,1,1);name.Parent=f

	local creator=Instance.new("TextLabel")
	creator.Size=UDim2.new(1,-16,0,20);creator.Position=UDim2.fromOffset(8,122)
	creator.BackgroundTransparency=1;creator.Text="by "..tostring(data.creatorName or "Unknown")
	creator.TextXAlignment=Enum.TextXAlignment.Left;creator.Font=Enum.Font.Gotham
	creator.TextSize=13;creator.TextColor3=Color3.fromRGB(170,178,188);creator.Parent=f

	local stats=Instance.new("TextLabel")
	stats.Size=UDim2.new(1,-105,0,28);stats.Position=UDim2.fromOffset(8,150)
	stats.BackgroundTransparency=1
	stats.Text="▶ "..tostring(data.plays or 0).."   ♥ "..tostring(data.likes or 0).."   "..tostring(data.difficulty or "Medium")
	stats.TextXAlignment=Enum.TextXAlignment.Left;stats.Font=Enum.Font.GothamBold;stats.TextSize=12
	stats.TextColor3=difficultyColor[data.difficulty] or Color3.new(1,1,1);stats.Parent=f

	local open=Instance.new("TextButton")
	open.Name="OpenDetails"
	open.Size=UDim2.new(1,-16,1,-48)
	open.Position=UDim2.fromOffset(8,8)
	open.BackgroundTransparency=1
	open.Text=""
	open.ZIndex=5
	open.Parent=f
	open.MouseButton1Click:Connect(function()
		openDetails(tostring(data.id))
	end)

	local play=Instance.new("TextButton")
	play.Size=UDim2.fromOffset(88,32);play.Position=UDim2.new(1,-96,1,-40)
	play.ZIndex=6
	play.BackgroundColor3=Color3.fromRGB(70,82,95);play.BackgroundTransparency=.35
	play.BorderSizePixel=0;play.Text="PLAY";play.Font=Enum.Font.GothamBold
	play.TextSize=12;play.TextColor3=Color3.new(1,1,1);play.BackgroundColor3=Color3.fromRGB(65,180,115);play.BackgroundTransparency=0;play.Parent=f
	play.MouseButton1Click:Connect(function()
		communityRemote:FireServer("Play",tostring(data.id))
	end)
	local pc=Instance.new("UICorner");pc.CornerRadius=UDim.new(0,7);pc.Parent=play
end


local playHUD=Instance.new("Frame")
playHUD.Size=UDim2.fromOffset(600,82)
playHUD.Position=UDim2.new(.5,-300,0,18)
playHUD.BackgroundColor3=Color3.fromRGB(28,33,41)
playHUD.BackgroundTransparency=.08
playHUD.BorderSizePixel=0
playHUD.Visible=false
playHUD.Parent=gui
local phc=Instance.new("UICorner");phc.CornerRadius=UDim.new(0,10);phc.Parent=playHUD

local playName=Instance.new("TextLabel")
playName.Size=UDim2.new(1,-330,1,0);playName.Position=UDim2.fromOffset(14,0);playName.BackgroundTransparency=1
playName.Text="PARKOUR";playName.TextXAlignment=Enum.TextXAlignment.Left;playName.Font=Enum.Font.GothamBlack
playName.TextSize=16;playName.TextColor3=Color3.new(1,1,1);playName.Parent=playHUD

local liveTime=Instance.new("TextLabel")
liveTime.Size=UDim2.fromOffset(120,54)
liveTime.Position=UDim2.new(1,-318,.5,-27)
liveTime.BackgroundColor3=Color3.fromRGB(38,45,55)
liveTime.BorderSizePixel=0
liveTime.Text="TIME\\n0.00s"
liveTime.Font=Enum.Font.GothamBlack
liveTime.TextSize=14
liveTime.TextColor3=Color3.fromRGB(105,225,165)
liveTime.Parent=playHUD
local ltc=Instance.new("UICorner");ltc.CornerRadius=UDim.new(0,9);ltc.Parent=liveTime

local restartPlay=Instance.new("TextButton")
restartPlay.Size=UDim2.fromOffset(92,42)
restartPlay.Position=UDim2.new(1,-190,.5,-21)
restartPlay.BackgroundColor3=Color3.fromRGB(65,115,190)
restartPlay.BorderSizePixel=0
restartPlay.Text="RESTART"
restartPlay.Font=Enum.Font.GothamBold
restartPlay.TextSize=13
restartPlay.TextColor3=Color3.new(1,1,1)
restartPlay.Parent=playHUD
local rpc=Instance.new("UICorner");rpc.CornerRadius=UDim.new(0,8);rpc.Parent=restartPlay

local exitPlay=Instance.new("TextButton")
exitPlay.Size=UDim2.fromOffset(86,42);exitPlay.Position=UDim2.new(1,-96,.5,-21);exitPlay.BackgroundColor3=Color3.fromRGB(170,65,70)
exitPlay.BorderSizePixel=0;exitPlay.Text="EXIT";exitPlay.Font=Enum.Font.GothamBold;exitPlay.TextSize=14;exitPlay.TextColor3=Color3.new(1,1,1);exitPlay.Parent=playHUD

local playStartTime=nil
local liveTimerConnection=nil
local request -- forward declaration; defined below
local function beginCommunityPlay(title,creator)
	communityPlaying=true
	overlay.Visible=false
	detailsPanel.Visible=false
	setEditorVisible(false)
	playHUD.Visible=true
	playName.Text=tostring(title).."\\nCreated by @"..tostring(creator)
	playStartTime=os.clock()
	liveTime.Text="TIME\\n0.00s"

	if liveTimerConnection then liveTimerConnection:Disconnect() end
	liveTimerConnection=game:GetService("RunService").RenderStepped:Connect(function()
		if playStartTime and playHUD.Visible then
			liveTime.Text="TIME\\n"..string.format("%.2fs",os.clock()-playStartTime)
		end
	end)
end

restartPlay.MouseButton1Click:Connect(function()
	communityRemote:FireServer("Restart")
end)

exitPlay.MouseButton1Click:Connect(function()
	communityRemote:FireServer("Exit")
end)

likeButton.MouseButton1Click:Connect(function()
	if currentParkourId then
		likeButton.BackgroundTransparency=.45
		socialRemote:FireServer("ToggleLike",currentParkourId)
	end
end)

dislikeButton.MouseButton1Click:Connect(function()
	if currentParkourId then
		dislikeButton.BackgroundTransparency=.45
		socialRemote:FireServer("ToggleDislike",currentParkourId)
	end
end)

favoriteButton.MouseButton1Click:Connect(function()
	if currentParkourId then
		favoriteButton.BackgroundTransparency=.45
		socialRemote:FireServer("ToggleFavorite",currentParkourId)
	end
end)

socialRemote.OnClientEvent:Connect(function(action,id,a,b,c,d)
	if tostring(id)~=tostring(currentParkourId) then return end

	if action=="SocialState"then
		likedCurrent=a==true
		dislikedCurrent=b==true
		favoritedCurrent=c==true
		likeButton.Text=likedCurrent and "♥ LIKED" or "♡ LIKE"
		dislikeButton.Text=dislikedCurrent and "◆ DISLIKED" or "♢ DISLIKE"
		favoriteButton.Text=favoritedCurrent and "★ FAVORITED" or "☆ FAVORITE"

	elseif action=="LikeChanged"then
		likedCurrent=a==true
		likeButton.Text=likedCurrent and "♥ LIKED" or "♡ LIKE"
		likeButton.BackgroundTransparency=0
		if c==true then
			dislikedCurrent=false
			dislikeButton.Text="♢ DISLIKE"
		end
		stats.Text=stats.Text:gsub("♥ %d+ likes","♥ "..tostring(b or 0).." likes")

	elseif action=="DislikeChanged"then
		dislikedCurrent=a==true
		dislikeButton.Text=dislikedCurrent and "◆ DISLIKED" or "♢ DISLIKE"
		dislikeButton.BackgroundTransparency=0
		if c==true then
			likedCurrent=false
			likeButton.Text="♡ LIKE"
			stats.Text=stats.Text:gsub("♥ %d+ likes","♥ "..tostring(d or 0).." likes")
		end

	elseif action=="FavoriteChanged"then
		favoritedCurrent=a==true
		favoriteButton.Text=favoritedCurrent and "★ FAVORITED" or "☆ FAVORITE"
		favoriteButton.BackgroundTransparency=0

	elseif action=="SocialError"then
		likeButton.BackgroundTransparency=0
		dislikeButton.BackgroundTransparency=0
		favoriteButton.BackgroundTransparency=0
	end
end)

playDetails.MouseButton1Click:Connect(function()
	if currentParkourId then communityRemote:FireServer("Play",currentParkourId) end
end)

leaderboardRemote.OnClientEvent:Connect(function(action,id,value)
	if action=="SubmitVerified" and type(id)=="string" and type(value)=="number" then
		leaderboardRemote:FireServer("Submit",id,value)
	end
end)

leaderboardRemote.OnClientEvent:Connect(function(action,id,entries)
	if action=="Leaderboard" then
		if tostring(id)==tostring(currentParkourId) then
			showBoard(entries)
		end
	elseif action=="LeaderboardError" then
		if tostring(id)==tostring(currentParkourId) then
			showBoard({})
		end
	end
end)


-- Polished course-completion summary popup.
local completeOverlay=Instance.new("Frame")
completeOverlay.Size=UDim2.fromScale(1,1);completeOverlay.BackgroundColor3=Color3.fromRGB(8,12,18)
completeOverlay.BackgroundTransparency=.38;completeOverlay.BorderSizePixel=0;completeOverlay.Visible=false;completeOverlay.ZIndex=110;
completeOverlay.Parent=gui

-- Shared popup blur. Reuse this helper for any modal/popup.
local popupBlur=Lighting:FindFirstChild("ParkourPopupBlur")
if not popupBlur then
	popupBlur=Instance.new("BlurEffect")
	popupBlur.Name="ParkourPopupBlur"
	local blur=Lighting:FindFirstChild("ParkourPopupBlur")
	if blur then blur.Size=0 end
	local blur=Lighting:FindFirstChild("ParkourPopupBlur")
	if blur then blur.Enabled=false end
	popupBlur.Parent=Lighting
end

local function setPopupBlur(enabled)
	popupBlur.Enabled=enabled
	popupBlur.Size=enabled and 7 or 0
end

local completeCard=Instance.new("Frame")
completeCard.Size=UDim2.fromOffset(460,340);completeCard.Position=UDim2.new(.5,-230,.5,-170)
completeCard.BackgroundColor3=Color3.fromRGB(28,34,43);completeCard.BorderSizePixel=0;completeCard.ZIndex=111;completeCard.Parent=completeOverlay
local ccc=Instance.new("UICorner");ccc.CornerRadius=UDim.new(0,18);ccc.Parent=completeCard
local ccs=Instance.new("UIStroke");ccs.Color=Color3.fromRGB(75,205,145);ccs.Transparency=.3;ccs.Thickness=2;ccs.Parent=completeCard
local trophy=Instance.new("TextLabel")
trophy.Size=UDim2.new(1,0,0,68);trophy.Position=UDim2.fromOffset(0,18);trophy.BackgroundTransparency=1;trophy.Text="🏆";trophy.TextSize=48;trophy.ZIndex=112;trophy.Parent=completeCard
local congrats=Instance.new("TextLabel")
congrats.Size=UDim2.new(1,-30,0,42);congrats.Position=UDim2.fromOffset(15,84);congrats.BackgroundTransparency=1
congrats.Text="CONGRATULATIONS!";congrats.Font=Enum.Font.GothamBlack;congrats.TextSize=25;congrats.TextColor3=Color3.fromRGB(105,230,155);congrats.ZIndex=112;congrats.Parent=completeCard
local completedName=Instance.new("TextLabel")
completedName.Size=UDim2.new(1,-40,0,30);completedName.Position=UDim2.fromOffset(20,128);completedName.BackgroundTransparency=1
completedName.Font=Enum.Font.GothamBold;completedName.TextSize=15;completedName.TextColor3=Color3.fromRGB(195,202,211);completedName.ZIndex=112;completedName.Parent=completeCard
local resultTime=Instance.new("TextLabel")
resultTime.Size=UDim2.new(1,-40,0,76);resultTime.Position=UDim2.fromOffset(20,166);resultTime.BackgroundColor3=Color3.fromRGB(38,46,57)
resultTime.BorderSizePixel=0;resultTime.Font=Enum.Font.GothamBlack;resultTime.TextSize=21;resultTime.TextColor3=Color3.new(1,1,1);resultTime.ZIndex=112;resultTime.Parent=completeCard
local rtc=Instance.new("UICorner");rtc.CornerRadius=UDim.new(0,12);rtc.Parent=resultTime
local exitResult=Instance.new("TextButton")
exitResult.Size=UDim2.fromOffset(300,52);exitResult.Position=UDim2.new(.5,-150,0,268);exitResult.BackgroundColor3=Color3.fromRGB(65,73,85)
exitResult.BorderSizePixel=0;exitResult.Text="EXIT TO DISCOVER";exitResult.Font=Enum.Font.GothamBlack;exitResult.TextSize=14;exitResult.TextColor3=Color3.new(1,1,1);exitResult.ZIndex=112;exitResult.Parent=completeCard
exitResult.MouseButton1Click:Connect(function()completeOverlay.Visible=false;setPopupBlur(false);communityRemote:FireServer("Exit")end)

communityRemote.OnClientEvent:Connect(function(action,a,b)
	if action=="PlayStarted"then
		beginCommunityPlay(a,b)
	elseif action=="Restarted"then
		playStartTime=os.clock()
		liveTime.Text="TIME\\n0.00s"
		if liveTimerConnection then liveTimerConnection:Disconnect() end
		liveTimerConnection=game:GetService("RunService").RenderStepped:Connect(function()
			if playStartTime and playHUD.Visible then
				liveTime.Text="TIME\\n"..string.format("%.2fs",os.clock()-playStartTime)
			end
		end)
	elseif action=="Finished"then
		local finishTime=tonumber(a) or 0
		local courseName=tostring(b or "Parkour")
		if liveTimerConnection then liveTimerConnection:Disconnect();liveTimerConnection=nil end
		liveTime.Text="FINAL TIME\\n"..string.format("%.2fs",finishTime)
		playName.Text="✓ COMPLETE  "..string.format("%.2fs",finishTime).."\\n"..courseName
		completedName.Text="You completed \""..courseName.."\"!"
		resultTime.Text="YOUR TIME\\n"..string.format("%.2f seconds",finishTime)
		completeOverlay.Visible=true
		setPopupBlur(true)
	elseif action=="PlayError"then
		detailsTitle.Text="PLAY ERROR"
		description.Text=tostring(a)
	elseif action=="Exited"then
		if liveTimerConnection then liveTimerConnection:Disconnect();liveTimerConnection=nil end
		playStartTime=nil
		communityPlaying=false
		playHUD.Visible=false
		overlay.Visible=true
		setEditorVisible(false)
		request("New")
	end
end)

request=function(mode)
	loading.Visible=true
	clearCards()
	heading.Text=string.upper(mode=="New" and "NEW PARKOURS" or mode)
	if mode=="My Creations" then
		remote:FireServer("MyCreations")
	else
		remote:FireServer("Discover",mode)
	end
end

newTab.MouseButton1Click:Connect(function()request("New")end)
playedTab.MouseButton1Click:Connect(function()request("MostPlayed")end)
likedTab.MouseButton1Click:Connect(function()request("MostLiked")end)
mineTab.MouseButton1Click:Connect(function()request("My Creations")end)

-- CREATE navigation is handled exclusively by the polished transition below.
-- Do not directly enable Builder here, otherwise it bypasses the transition.
close.MouseButton1Click:Connect(function()
	UIS.MouseIconEnabled=true
end)

-- No keyboard shortcut for opening/closing Discover.
-- Navigation is handled only through visible UI buttons.

searchRemote.OnClientEvent:Connect(function(action,results,query)
	if action~="SearchResults" then return end
	loading.Visible=false
	clearCards()

	if type(results)~="table" or #results==0 then
		loading.Visible=true
		loading.Text='NO RESULTS FOR "'..tostring(query)..'"'
		heading.Text="SEARCH"
		return
	end

	loading.Text="◌  LOADING PARKOURS..."
	heading.Text='SEARCH RESULTS FOR "'..tostring(query)..'"'
	for _,data in ipairs(results) do
		card(data)
	end
end)

remote.OnClientEvent:Connect(function(action,results,mode)
	if action~="DiscoverResults" then return end
	loading.Visible=false
	clearCards()
	if type(results)~="table" or #results==0 then
		loading.Visible=true
		loading.Text="NO PARKOURS FOUND YET"
		return
	end
	loading.Text="◌  LOADING PARKOURS..."
	for _,data in ipairs(results) do card(data) end
	heading.Text=string.upper(tostring(mode or "DISCOVER"))
end)


-- CENTRAL BLUR STATE V3
-- Main Discover browser = soft blur 4
-- Modal popup = stronger blur 7
-- Playing/building = no blur
RunService.RenderStepped:Connect(function()
	local blur=Lighting:FindFirstChild("ParkourPopupBlur")
	if not blur then return end

	local modalOpen =
		(profilePanel and profilePanel.Visible)
		or (leaderboardPanel and leaderboardPanel.Visible)
		or (deleteModal and deleteModal.Visible)
		or (completeOverlay and completeOverlay.Visible)

	local discoverOpen = overlay and overlay.Visible and not communityPlaying

	if modalOpen then
		blur.Enabled=true
		blur.Size=7
	elseif discoverOpen then
		blur.Enabled=true
		blur.Size=4
	else
		blur.Size=0
		blur.Enabled=false
	end
end)

-- Creator spawn reset hook
if create then
	create.MouseButton1Click:Connect(function()
		creatorModeRemote:FireServer("EnterCreator")
	end)
end

-- CREATOR SPAWN V2
-- Explicitly bind the existing CREATE button to the server-side plot reset.
if create then
	create.MouseButton1Click:Connect(function()
		creatorModeRemote:FireServer("EnterCreator")
	end)
end


-- CREATOR TELEPORT TRANSITION V7 - POLISHED
-- Independent ScreenGui, matching the Exit Build Mode transition style.
local creatorTransitionGui=Instance.new("ScreenGui")
creatorTransitionGui.Name="ParkourCreatorTransitionUI"
creatorTransitionGui.ResetOnSpawn=false
creatorTransitionGui.IgnoreGuiInset=true
creatorTransitionGui.DisplayOrder=500
creatorTransitionGui.Enabled=false
creatorTransitionGui.Parent=playerGui

local teleportOverlay=Instance.new("Frame")
teleportOverlay.Name="CreatorTeleportOverlay"
teleportOverlay.Size=UDim2.fromScale(1,1)
teleportOverlay.BackgroundColor3=Color3.fromRGB(5,14,25)
teleportOverlay.BackgroundTransparency=1
teleportOverlay.BorderSizePixel=0
teleportOverlay.Active=true
teleportOverlay.ZIndex=300
teleportOverlay.Parent=creatorTransitionGui

local teleportIcon=Instance.new("TextLabel")
teleportIcon.Size=UDim2.fromOffset(150,100)
teleportIcon.Position=UDim2.new(.5,-75,.5,-190)
teleportIcon.BackgroundTransparency=1
teleportIcon.Text="◉  ➜"
teleportIcon.Font=Enum.Font.GothamBlack
teleportIcon.TextSize=52
teleportIcon.TextColor3=Color3.fromRGB(75,205,255)
teleportIcon.TextTransparency=1
teleportIcon.ZIndex=301
teleportIcon.Parent=teleportOverlay

local teleportTitle=Instance.new("TextLabel")
teleportTitle.Size=UDim2.new(1,-60,0,62)
teleportTitle.Position=UDim2.new(0,30,.5,-82)
teleportTitle.BackgroundTransparency=1
teleportTitle.Text="TELEPORTING YOU TO CREATOR..."
teleportTitle.Font=Enum.Font.GothamBlack
teleportTitle.TextSize=30
teleportTitle.TextColor3=Color3.new(1,1,1)
teleportTitle.TextTransparency=1
teleportTitle.ZIndex=301
teleportTitle.Parent=teleportOverlay

local teleportSub=Instance.new("TextLabel")
teleportSub.Size=UDim2.new(1,-60,0,34)
teleportSub.Position=UDim2.new(0,30,.5,-18)
teleportSub.BackgroundTransparency=1
teleportSub.Text="Preparing your build plot"
teleportSub.Font=Enum.Font.GothamMedium
teleportSub.TextSize=17
teleportSub.TextColor3=Color3.fromRGB(165,215,245)
teleportSub.TextTransparency=1
teleportSub.ZIndex=301
teleportSub.Parent=teleportOverlay

local creatorProgressBack=Instance.new("Frame")
creatorProgressBack.Size=UDim2.fromOffset(470,16)
creatorProgressBack.Position=UDim2.new(.5,-235,.5,43)
creatorProgressBack.BackgroundColor3=Color3.fromRGB(52,75,98)
creatorProgressBack.BackgroundTransparency=.15
creatorProgressBack.BorderSizePixel=0
creatorProgressBack.ZIndex=301
creatorProgressBack.Parent=teleportOverlay
local cpbc=Instance.new("UICorner");cpbc.CornerRadius=UDim.new(1,0);cpbc.Parent=creatorProgressBack

local creatorProgress=Instance.new("Frame")
creatorProgress.Size=UDim2.fromScale(0,1)
creatorProgress.BackgroundColor3=Color3.fromRGB(65,205,255)
creatorProgress.BorderSizePixel=0
creatorProgress.ZIndex=302
creatorProgress.Parent=creatorProgressBack
local cpc=Instance.new("UICorner");cpc.CornerRadius=UDim.new(1,0);cpc.Parent=creatorProgress

local dots=Instance.new("TextLabel")
dots.Size=UDim2.new(1,-60,0,30)
dots.Position=UDim2.new(0,30,.5,78)
dots.BackgroundTransparency=1
dots.Text="●   ●   ●"
dots.Font=Enum.Font.GothamBlack
dots.TextSize=17
dots.TextColor3=Color3.fromRGB(70,125,165)
dots.TextTransparency=1
dots.ZIndex=301
dots.Parent=teleportOverlay

local creatorStatus=Instance.new("TextLabel")
creatorStatus.Size=UDim2.new(1,-60,0,30)
creatorStatus.Position=UDim2.new(0,30,.5,112)
creatorStatus.BackgroundTransparency=1
creatorStatus.Text="Loading your environment..."
creatorStatus.Font=Enum.Font.GothamMedium
creatorStatus.TextSize=14
creatorStatus.TextColor3=Color3.fromRGB(155,195,220)
creatorStatus.TextTransparency=1
creatorStatus.ZIndex=301
creatorStatus.Parent=teleportOverlay

local creatorTip=Instance.new("TextLabel")
creatorTip.Size=UDim2.fromOffset(340,72)
creatorTip.Position=UDim2.new(0,28,1,-100)
creatorTip.BackgroundColor3=Color3.fromRGB(12,26,41)
creatorTip.BackgroundTransparency=.08
creatorTip.BorderSizePixel=0
creatorTip.Text="💡  TIP\nYour builds are saved automatically!"
creatorTip.TextXAlignment=Enum.TextXAlignment.Left
creatorTip.Font=Enum.Font.GothamBold
creatorTip.TextSize=14
creatorTip.TextColor3=Color3.fromRGB(205,225,240)
creatorTip.TextTransparency=1
creatorTip.ZIndex=301
creatorTip.Parent=teleportOverlay
local ctpc=Instance.new("UICorner");ctpc.CornerRadius=UDim.new(0,11);ctpc.Parent=creatorTip
local ctps=Instance.new("UIStroke");ctps.Color=Color3.fromRGB(55,145,205);ctps.Transparency=.35;ctps.Parent=creatorTip

local creatorTransitionRunning=false
local function showCreatorTransition()
	if creatorTransitionRunning then return end
	creatorTransitionRunning=true
	playerGui:SetAttribute("CreatorTransitionActive",true)

	-- Hide both application UIs before rendering transition.
	setEditorVisible(false)
	overlay.Visible=false
	detailsPanel.Visible=false
	profilePanel.Visible=false
	leaderboardPanel.Visible=false

	creatorTransitionGui.Enabled=true
	teleportOverlay.BackgroundTransparency=1
	teleportIcon.TextTransparency=1
	teleportTitle.TextTransparency=1
	teleportSub.TextTransparency=1
	dots.TextTransparency=1
	creatorStatus.TextTransparency=1
	creatorTip.TextTransparency=1
	creatorProgress.Size=UDim2.fromScale(0,1)

	TweenService:Create(teleportOverlay,TweenInfo.new(.22),{BackgroundTransparency=.06}):Play()
	TweenService:Create(teleportIcon,TweenInfo.new(.22),{TextTransparency=0}):Play()
	TweenService:Create(teleportTitle,TweenInfo.new(.22),{TextTransparency=0}):Play()
	TweenService:Create(teleportSub,TweenInfo.new(.28),{TextTransparency=0}):Play()
	TweenService:Create(dots,TweenInfo.new(.28),{TextTransparency=0}):Play()
	TweenService:Create(creatorStatus,TweenInfo.new(.28),{TextTransparency=0}):Play()
	TweenService:Create(creatorTip,TweenInfo.new(.28),{TextTransparency=0}):Play()

	local progressTween=TweenService:Create(
		creatorProgress,
		TweenInfo.new(1.15,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
		{Size=UDim2.fromScale(1,1)}
	)
	progressTween:Play()

	task.wait(.65)
	dots.Text="●   ○   ○"
	creatorStatus.Text="Reserving your private creator server..."

	progressTween.Completed:Wait()
	dots.Text="●   ●   ○"
	creatorStatus.Text="Opening your private build server..."

	-- Ask the server to reserve a fresh server of this same Place and
	-- teleport ONLY this player. The transition stays visible until Roblox
	-- begins the teleport.
	createPrivateRemote:FireServer("Create")

	-- Do NOT enable Builder locally here. The destination reserved server
	-- will identify the Creator session from TeleportData.
end

-- If Roblox cannot reserve/teleport, restore Discover instead of leaving
-- the player stuck on the transition screen.
createPrivateRemote.OnClientEvent:Connect(function(action,message)
	-- STUDIO ONLY: ParkourCreatorTeleportServer skips the real teleport and
	-- reports that the simulated private Creator server is ready.
	if action=="StudioCreatorReady" then
		dots.Text="●   ●   ●"
		creatorStatus.Text="Creator server ready!"

		-- Briefly show success, then remove the teleport overlay.
		task.wait(.2)
		creatorTransitionGui.Enabled=false
		playerGui:SetAttribute("CreatorTransitionActive",false)

		-- The server already set ParkourPrivateCreator=true.
		-- ParkourCreatorArrivalClient will request EnterCreator.
		-- Reveal the existing Builder UI after that request has had time to run.
		task.wait(.25)
		setEditorVisible(true)

		creatorTransitionRunning=false
		print("[CREATE STUDIO] Simulated Creator transition completed")
		return
	end

	if action~="Failed" then return end

	warn("[CREATE PRIVATE] "..tostring(message or "Teleport failed"))
	creatorTransitionRunning=false
	playerGui:SetAttribute("CreatorTransitionActive",false)
	creatorTransitionGui.Enabled=false
	overlay.Visible=true
	setEditorVisible(false)

	-- Allow the CREATE button to be pressed again.
	close.Active=true
end)

-- CREATE BUTTON - DIRECT BINDING V7.2
-- `close` is the actual CREATE button defined in the header.
-- Bind it directly instead of searching the GUI tree.
close.MouseButton1Click:Connect(function()
	if creatorTransitionRunning then return end
	print("[CREATE V7.2] CREATE clicked -> polished creator transition")
	task.spawn(showCreatorTransition)
end)

-- RETURN TO DISCOVER BUTTON
local returnDiscover=Instance.new("TextButton")
returnDiscover.Name="ReturnToDiscover"
returnDiscover.Size=UDim2.fromOffset(170,42)
returnDiscover.Position=UDim2.new(0,22,0,78)
returnDiscover.BackgroundColor3=Color3.fromRGB(39,48,60)
returnDiscover.BorderSizePixel=0
returnDiscover.Text="← DISCOVER"
returnDiscover.Font=Enum.Font.GothamBlack
returnDiscover.TextSize=14
returnDiscover.TextColor3=Color3.new(1,1,1)
returnDiscover.Visible=false
returnDiscover.ZIndex=80
returnDiscover.Parent=gui
local rdc=Instance.new("UICorner");rdc.CornerRadius=UDim.new(0,10);rdc.Parent=returnDiscover
local rds=Instance.new("UIStroke");rds.Color=Color3.fromRGB(70,145,235);rds.Transparency=.55;rds.Parent=returnDiscover

returnDiscover.MouseButton1Click:Connect(function()
	removeDuplicateDiscoverUIs()
	creatorModeRemote:FireServer("LeaveCreator")

	-- Restore normal Discover top-level UI.
	for _,obj in ipairs(gui:GetChildren()) do
		if obj~=teleportOverlay and obj:IsA("GuiObject") then
			obj.Visible=true
		end
	end
	overlay.Visible=true
	detailsPanel.Visible=false
	profilePanel.Visible=false
	leaderboardPanel.Visible=false

	-- Hide editor and restore Discover.
	setEditorVisible(false)
	overlay.Visible=true
	detailsPanel.Visible=false
	profilePanel.Visible=false
	leaderboardPanel.Visible=false
	returnDiscover.Visible=false

	-- Refresh New creations when returning.
	if request then request("New") end
end)

-- Show this only while the builder/editor is active.
game:GetService("RunService").RenderStepped:Connect(function()
	local editorVisible=false
	local pg=player:FindFirstChild("PlayerGui")
	if pg then
		for _,g in ipairs(pg:GetChildren()) do
			if g:IsA("ScreenGui") and g~=gui and g.Enabled then
				local buildText=g:FindFirstChild("BuildMode",true)
				if buildText and buildText:IsA("GuiObject") and buildText.Visible then
					editorVisible=true
					break
				end
			end
		end
	end
	-- Do not infer Builder mode merely because Discover is hidden:
	-- Discover is also hidden during the teleport transition.
	if playerGui:GetAttribute("CreatorTransitionActive")==true then
		editorVisible=false
	end
	returnDiscover.Visible=editorVisible
end)

-- Unified navigation back to Discover.
navigationEvent.Event:Connect(function(destination)
	if destination~="Discover" then return end

	playerGui:SetAttribute("CreatorTransitionActive",false)
	creatorModeRemote:FireServer("LeaveCreator")

	setEditorVisible(false)
	gui.Enabled=true
	overlay.Visible=true
	detailsPanel.Visible=false
	profilePanel.Visible=false
	leaderboardPanel.Visible=false
	playHUD.Visible=false
	communityPlaying=false

	if request then request("New") end

	-- Tell cinematic menu controller to restore its saved menu camera.
	navigationEvent:Fire("MenuCamera")
end)

-- STARTUP ROLE GUARD
-- Give ParkourCreatorArrivalServer time to set the player's server role.
task.wait(.5)

local startupOwnerId=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))
local startupIsOwner=
	(startupOwnerId~=nil and startupOwnerId==player.UserId)
	or player:GetAttribute("ParkourCreatorOwner")==true
	or player:GetAttribute("ParkourCreatorRole")=="Owner"

local startupIsGuest=player:GetAttribute("ParkourCreatorGuest")==true

if startupIsOwner then

	-- Actual reserved-server owner.
	gui.Enabled=false
	overlay.Visible=false
	detailsPanel.Visible=false
	profilePanel.Visible=false
	leaderboardPanel.Visible=false
	playHUD.Visible=false
	setEditorVisible(true)

	print("[DISCOVER] Reserved Creator owner detected -> Builder visible")

elseif startupIsGuest then

	-- GUEST joined an owner's Creator server.
	-- Viewer/no permission starts with Builder hidden.
	-- Only an explicitly granted Collaborator sees the Builder.
	gui.Enabled=false
	overlay.Visible=false

	local startupCanBuild=
		player:GetAttribute("ParkourGuestPermissionRole")=="Collaborator"
		and player:GetAttribute("ParkourCanCollaborate")==true

	setEditorVisible(startupCanBuild)

	print("[DISCOVER] Creator guest detected -> Builder permission = "..tostring(startupCanBuild))

else
	-- Normal/public server join.
	gui.Enabled=true
	setEditorVisible(false)
	overlay.Visible=true
	request("New")
end



-- If the server role arrives slightly later than startup, immediately suppress
-- Discover for Creator owners/guests.
local function refreshCreatorServerRole()
	if player:GetAttribute("ParkourPrivateCreator")==true
		or player:GetAttribute("ParkourCreatorOwner")==true
		or player:GetAttribute("ParkourCreatorGuest")==true then
		overlay.Visible=false
		detailsPanel.Visible=false
		profilePanel.Visible=false
		leaderboardPanel.Visible=false
		playHUD.Visible=false
		gui.Enabled=false
	end
end

player:GetAttributeChangedSignal("ParkourPrivateCreator"):Connect(refreshCreatorServerRole)
player:GetAttributeChangedSignal("ParkourCreatorOwner"):Connect(refreshCreatorServerRole)
player:GetAttributeChangedSignal("ParkourCreatorGuest"):Connect(refreshCreatorServerRole)

print("✓ ParkourDiscoverClient V1.5 strict guest permission startup loaded")

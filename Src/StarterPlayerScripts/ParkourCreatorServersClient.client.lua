-- ParkourCreatorServersClient V1
-- NEW LocalScript: StarterPlayer > StarterPlayerScripts > ParkourCreatorServersClient
-- Adds a Creator Servers tab to the existing Discover UI and owns ONLY this feature's UI.
-- Does NOT write BuilderUI.Enabled, DiscoverUI.Enabled, permissions, or save data.
-- All names/counts/decisions come from the server. Tiny parkour tiles are DECORATIVE,
-- not screenshots or stored project titles. No external icon/image asset uploads required.

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local TweenService=game:GetService("TweenService")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer
local pg=player:WaitForChild("PlayerGui")
local remote=RS:WaitForChild("ParkourCreatorServersEvent",30)
if not remote or not remote:IsA("RemoteEvent") then
	warn("[CREATOR BROWSER UI] Missing ParkourCreatorServersEvent. Install the server Script and Rules ModuleScript first.")
	return
end
if pg:FindFirstChild("ParkourCreatorServersUI") then
	warn("[CREATOR BROWSER UI] Duplicate client detected. Keep one enabled copy.")
	return
end
local C={
	BG=Color3.fromRGB(4,19,34), Panel=Color3.fromRGB(8,32,51), Raised=Color3.fromRGB(13,46,69),
	Cyan=Color3.fromRGB(20,207,255), Blue=Color3.fromRGB(0,137,246), White=Color3.fromRGB(237,249,255),
	Muted=Color3.fromRGB(155,194,224), Border=Color3.fromRGB(35,107,151),
	Green=Color3.fromRGB(0,235,146), Red=Color3.fromRGB(255,104,125), Gray=Color3.fromRGB(47,69,92),
}
local function make(class,props,parent)
	local o=Instance.new(class)
	for k,v in pairs(props) do o[k]=v end
	o.Parent=parent
	return o
end
local function round(o,r) return make("UICorner",{CornerRadius=UDim.new(0,r or 10)},o) end
local function stroke(o,color,thickness,transparency)
	return make("UIStroke",{Color=color or C.Border,Thickness=thickness or 1,
		Transparency=transparency or 0,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},o)
end
local function gradient(o,top,bottom)
	return make("UIGradient",{Rotation=90,Color=ColorSequence.new(top,bottom)},o)
end
local function label(parent,text,size,position,width,height,color,font)
	return make("TextLabel",{
		BackgroundTransparency=1,Text=text,TextSize=size,Position=position,
		Size=UDim2.fromOffset(width,height),Font=font or Enum.Font.GothamBold,
		TextColor3=color or C.White,TextXAlignment=Enum.TextXAlignment.Left,
		TextYAlignment=Enum.TextYAlignment.Center,TextTruncate=Enum.TextTruncate.AtEnd,
		ZIndex=parent.ZIndex+1,
	},parent)
end
local function button(parent,text,position,size,bright)
	local b=make("TextButton",{Text=text,Position=position,Size=size,
		BackgroundColor3=bright and C.Blue or C.Raised,BorderSizePixel=0,
		AutoButtonColor=false,TextColor3=C.White,Font=Enum.Font.GothamBlack,TextSize=12,
		ZIndex=parent.ZIndex+1},parent)
	round(b,9)
	local s=stroke(b,bright and C.Cyan or C.Border,bright and 2 or 1)
	if bright then gradient(b,Color3.fromRGB(0,170,255),Color3.fromRGB(0,102,220)) end
	b.MouseEnter:Connect(function() if b.Active then s.Transparency=0; s.Thickness=2 end end)
	b.MouseLeave:Connect(function() s.Thickness=bright and 2 or 1 end)
	return b
end
local function line(parent,x,y,w,h,rotation,color)
	local l=make("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(x,y),
		Size=UDim2.fromOffset(w,h),Rotation=rotation,BackgroundColor3=color or C.Cyan,
		BorderSizePixel=0,ZIndex=parent.ZIndex+1},parent)
	round(l,2)
	return l
end
local function closeButton(parent,position)
	local b=button(parent,"",position,UDim2.fromOffset(42,42),false)
	line(b,21,21,23,3,45,C.Muted); line(b,21,21,23,3,-45,C.Muted)
	return b
end
local function groupIcon(parent,position,scale,color)
	local f=make("Frame",{Size=UDim2.fromOffset(64,54),Position=position,
		BackgroundTransparency=1,ZIndex=parent.ZIndex+1},parent)
	make("UIScale",{Scale=scale or 1},f)
	for _,s in ipairs({{6,8,16,18,22,29},{42,8,16,18,22,29},{20,2,24,24,31,32}}) do
		local head=make("Frame",{Size=UDim2.fromOffset(s[3],s[3]),Position=UDim2.fromOffset(s[1],s[2]),
			BackgroundColor3=color or C.Cyan,BorderSizePixel=0,ZIndex=f.ZIndex+1},f)
		round(head,s[3]/2)
		local body=make("Frame",{Size=UDim2.fromOffset(s[5],s[4]),Position=UDim2.fromOffset(s[1]-(s[5]-s[3])/2,s[6]),
			BackgroundColor3=color or C.Cyan,BorderSizePixel=0,ZIndex=f.ZIndex+1},f)
		round(body,8)
	end
	return f
end
local function searchIcon(parent,position)
	local f=make("Frame",{Position=position,Size=UDim2.fromOffset(28,28),BackgroundTransparency=1,ZIndex=parent.ZIndex+1},parent)
	local circle=make("Frame",{Size=UDim2.fromOffset(15,15),Position=UDim2.fromOffset(2,2),
		BackgroundTransparency=1,ZIndex=f.ZIndex+1},f)
	round(circle,10); stroke(circle,C.Muted,2)
	line(f,20,20,13,2,45,C.Muted)
end
local function outlinedPanel(parent,name,size,position)
	local p=make("Frame",{Name=name,Size=size,Position=position,AnchorPoint=Vector2.new(.5,.5),
		BackgroundColor3=C.BG,BorderSizePixel=0,Active=true,ZIndex=parent.ZIndex+1},parent)
	round(p,18); stroke(p,C.Cyan,2)
	gradient(p,Color3.fromRGB(7,30,49),Color3.fromRGB(3,17,32))
	-- Layered low-opacity borders approximate a neon halo without editing Lighting.
	for i=1,3 do
		local g=make("Frame",{Size=UDim2.new(1,4*i,1,4*i),Position=UDim2.fromOffset(-2*i,-2*i),
			BackgroundTransparency=1,ZIndex=p.ZIndex},p)
		round(g,18+2*i); stroke(g,C.Cyan,2,0.75+i*0.065)
	end
	return p
end

local screen=make("ScreenGui",{Name="ParkourCreatorServersUI",ResetOnSpawn=false,
	IgnoreGuiInset=true,DisplayOrder=1700,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},pg)
local root=make("Frame",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ZIndex=1},screen)
local shade=make("TextButton",{Name="BrowserShade",Size=UDim2.fromScale(1,1),Text="",
	BackgroundColor3=Color3.fromRGB(0,7,17),BackgroundTransparency=.35,
	BorderSizePixel=0,AutoButtonColor=false,Visible=false,ZIndex=10},root)
local panel=outlinedPanel(shade,"CreatorServersPanel",UDim2.fromOffset(980,666),UDim2.fromScale(.5,.5))
local panelScale=make("UIScale",{Scale=1},panel)
local headerIcon=groupIcon(panel,UDim2.fromOffset(29,27),.95)
local heading=label(panel,"CREATOR SERVERS",34,UDim2.fromOffset(113,27),500,45)
heading.Font=Enum.Font.GothamBlack
local live=label(panel,"LIVE NOW",13,UDim2.fromOffset(630,33),93,29,C.Green,Enum.Font.GothamBlack)
local liveDot=make("Frame",{Size=UDim2.fromOffset(13,13),Position=UDim2.fromOffset(609,41),
	BackgroundColor3=C.Green,BorderSizePixel=0,ZIndex=panel.ZIndex+2},panel)
round(liveDot,8)
label(panel,"Browse active Creator sessions and request to join.",15,UDim2.fromOffset(114,72),755,24,C.Muted)
local close=closeButton(panel,UDim2.new(1,-68,0,26))

local searchBack=make("Frame",{Size=UDim2.new(1,-303,0,49),Position=UDim2.fromOffset(28,118),
	BackgroundColor3=C.BG,BorderSizePixel=0,ZIndex=panel.ZIndex+1},panel)
round(searchBack,11); stroke(searchBack,C.Cyan,1)
searchIcon(searchBack,UDim2.fromOffset(14,11))
local search=make("TextBox",{Name="CreatorSearch",Size=UDim2.new(1,-65,1,0),Position=UDim2.fromOffset(55,0),
	BackgroundTransparency=1,Text="",PlaceholderText="Search creators...",PlaceholderColor3=C.Muted,
	TextColor3=C.White,TextSize=15,Font=Enum.Font.Gotham,ClearTextOnFocus=false,
	TextXAlignment=Enum.TextXAlignment.Left,ZIndex=searchBack.ZIndex+1},searchBack)
local filterButton=button(panel,"ALL CREATORS",UDim2.new(1,-260,0,118),UDim2.fromOffset(232,49),false)
line(filterButton,209,24,11,2,45,C.Muted); line(filterButton,216,24,11,2,-45,C.Muted)
local filterMenu=make("Frame",{Position=UDim2.new(1,-260,0,173),Size=UDim2.fromOffset(232,134),
	BackgroundColor3=C.BG,BorderSizePixel=0,Visible=false,ZIndex=45},panel)
round(filterMenu,10); stroke(filterMenu,C.Cyan,1)
local filterNames={"ALL CREATORS","SPACE AVAILABLE","FULL SERVERS"}
local filterOptions={}
for i,name in ipairs(filterNames) do
	local b=button(filterMenu,name,UDim2.fromOffset(7,7+(i-1)*40),UDim2.fromOffset(218,36),false)
	filterOptions[i]=b
end
local list=make("ScrollingFrame",{Name="ServerList",Position=UDim2.fromOffset(28,188),
	Size=UDim2.new(1,-56,1,-273),BackgroundTransparency=1,BorderSizePixel=0,
	ScrollBarThickness=5,ScrollBarImageColor3=C.Cyan,CanvasSize=UDim2.new(),
	AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollingDirection=Enum.ScrollingDirection.Y,
	ZIndex=panel.ZIndex+1},panel)
make("UIPadding",{PaddingRight=UDim.new(0,7),PaddingBottom=UDim.new(0,3),PaddingTop=UDim.new(0,3)},list)
make("UIListLayout",{Padding=UDim.new(0,9),SortOrder=Enum.SortOrder.LayoutOrder},list)
local empty=label(panel,"Loading Creator servers...",16,UDim2.fromOffset(60,310),860,76,C.Muted)
empty.TextWrapped=true; empty.TextXAlignment=Enum.TextXAlignment.Center
local bottomLine=make("Frame",{Position=UDim2.new(0,28,1,-73),Size=UDim2.new(1,-56,0,1),
	BackgroundColor3=C.Border,BorderSizePixel=0,ZIndex=panel.ZIndex+1},panel)
local footer=label(panel,"Requests are sent to the Creator for approval.",12,UDim2.new(0,31,1,-60),590,36,C.Muted)
local more=button(panel,"LOAD MORE",UDim2.new(1,-258,1,-60),UDim2.fromOffset(110,35),false)
local refresh=button(panel,"REFRESH",UDim2.new(1,-136,1,-60),UDim2.fromOffset(108,35),false)
more.Visible=false

-- Pending request banner lives outside the browser so closing it does not lose the request.
local pendingBanner=make("Frame",{Name="PendingJoinRequest",AnchorPoint=Vector2.new(.5,1),
	Position=UDim2.new(.5,0,1,-24),Size=UDim2.fromOffset(530,55),
	BackgroundColor3=C.BG,BorderSizePixel=0,Visible=false,ZIndex=80},root)
round(pendingBanner,12); stroke(pendingBanner,C.Cyan,1.5)
local pendingScale=make("UIScale",{Scale=1},pendingBanner)
local pendingLabel=label(pendingBanner,"Waiting for Creator...",12,UDim2.fromOffset(15,6),385,42,C.White)
pendingLabel.TextWrapped=true
local cancelRequest=button(pendingBanner,"CANCEL",UDim2.new(1,-119,0,10),UDim2.fromOffset(105,35),false)

-- Owner request inbox; separated from invitation UI and from the Discover panel.
local ownerOpen=button(root,"JOIN REQUESTS",UDim2.new(1,-190,0,222),UDim2.fromOffset(170,42),true)
ownerOpen.Visible=false
local ownerShade=make("Frame",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false,ZIndex=100},root)
local ownerPanel=outlinedPanel(ownerShade,"JoinRequestInbox",UDim2.fromOffset(440,334),UDim2.new(1,-240,.5,0))
local ownerScale=make("UIScale",{Scale=1},ownerPanel)
label(ownerPanel,"JOIN REQUESTS",20,UDim2.fromOffset(22,18),315,33,C.White,Enum.Font.GothamBlack)
local ownerClose=closeButton(ownerPanel,UDim2.new(1,-58,0,13))
local pause=button(ownerPanel,"REQUESTS OPEN",UDim2.fromOffset(22,60),UDim2.fromOffset(181,32),false)
local queueLabel=label(ownerPanel,"0 WAITING",11,UDim2.fromOffset(236,61),175,30,C.Muted)
queueLabel.TextXAlignment=Enum.TextXAlignment.Right
local requesterAvatar=make("ImageLabel",{Size=UDim2.fromOffset(60,60),Position=UDim2.fromOffset(23,113),
	BackgroundColor3=C.Raised,Image="",BorderSizePixel=0,ZIndex=ownerPanel.ZIndex+2},ownerPanel)
round(requesterAvatar,30); stroke(requesterAvatar,C.Cyan,2)
local requesterName=label(ownerPanel,"No pending requests",17,UDim2.fromOffset(96,111),320,29,C.White)
local requesterUser=label(ownerPanel,"Players in Discover can request to join.",12,UDim2.fromOffset(96,143),320,27,C.Muted)
local ownerDescription=label(ownerPanel,"Approved guests join as Viewers. Build access stays separate.",12,
	UDim2.fromOffset(24,187),392,40,C.Muted)
ownerDescription.TextWrapped=true
local ownerTrack=make("Frame",{Size=UDim2.fromOffset(335,5),Position=UDim2.fromOffset(24,244),
	BackgroundColor3=C.Gray,BorderSizePixel=0,ZIndex=ownerPanel.ZIndex+2},ownerPanel)
round(ownerTrack,3)
local ownerProgress=make("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=C.Cyan,
	BorderSizePixel=0,ZIndex=ownerTrack.ZIndex+1},ownerTrack)
round(ownerProgress,3)
local remainingLabel=label(ownerPanel,"--s",12,UDim2.fromOffset(368,234),46,25,C.Muted)
remainingLabel.TextXAlignment=Enum.TextXAlignment.Right
local accept=button(ownerPanel,"APPROVE",UDim2.fromOffset(24,273),UDim2.fromOffset(189,40),true)
local decline=button(ownerPanel,"DECLINE",UDim2.fromOffset(225,273),UDim2.fromOffset(189,40),false)

-- Small queued toasts; no old delayed tween can hide a newer toast.
local toast=make("Frame",{Name="JoinRequestToast",AnchorPoint=Vector2.new(1,0),
	Position=UDim2.new(1,440,0,278),Size=UDim2.fromOffset(395,82),
	BackgroundColor3=C.BG,BorderSizePixel=0,Visible=false,ZIndex=150},root)
round(toast,12); stroke(toast,C.Cyan,1.5)
local toastScale=make("UIScale",{Scale=1},toast)
local toastTitle=label(toast,"JOIN REQUEST",14,UDim2.fromOffset(15,10),365,23,C.Cyan,Enum.Font.GothamBlack)
local toastText=label(toast,"",12,UDim2.fromOffset(15,36),365,37,C.Muted)
toastText.TextWrapped=true
local toastQueue,toastRunning={},false
local function notify(title,text)
	if #toastQueue>=5 then table.remove(toastQueue,1) end
	table.insert(toastQueue,{title=title,text=text})
	if toastRunning then return end
	toastRunning=true
	task.spawn(function()
		while #toastQueue>0 and screen.Parent do
			local item=table.remove(toastQueue,1)
			toastTitle.Text=item.title; toastText.Text=item.text
			toast.Visible=true; toast.Position=UDim2.new(1,440,0,278)
			local incoming=TweenService:Create(toast,TweenInfo.new(.25,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),
				{Position=UDim2.new(1,-20,0,278)})
			incoming:Play(); incoming.Completed:Wait(); task.wait(3.4)
			local outgoingTween=TweenService:Create(toast,TweenInfo.new(.2),{Position=UDim2.new(1,440,0,278)})
			outgoingTween:Play(); outgoingTween.Completed:Wait(); toast.Visible=false
		end
		toastRunning=false
	end)
end

-- Teleport transition belongs only to a server-approved join request.
local transferGui=make("ScreenGui",{Name="ParkourCreatorRequestTransition",ResetOnSpawn=false,
	IgnoreGuiInset=true,DisplayOrder=6000,Enabled=false},pg)
local transferBG=make("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=C.BG,BorderSizePixel=0,ZIndex=1},transferGui)
local transferTitle=label(transferBG,"JOINING CREATOR SERVER",26,UDim2.new(.5,-280,.5,-38),560,50,C.White,Enum.Font.GothamBlack)
transferTitle.TextXAlignment=Enum.TextXAlignment.Center; transferTitle.TextScaled=true
make("UITextSizeConstraint",{MinTextSize=16,MaxTextSize=26},transferTitle)
transferTitle.Size=UDim2.new(.85,0,0,50); transferTitle.AnchorPoint=Vector2.new(.5,0); transferTitle.Position=UDim2.new(.5,0,.5,-38)
local transferText=label(transferBG,"Your request was approved. Joining as a Viewer...",15,UDim2.new(.5,-270,.5,19),540,50,C.Muted)
transferText.TextWrapped=true; transferText.TextXAlignment=Enum.TextXAlignment.Center
transferText.Size=UDim2.new(.85,0,0,50); transferText.AnchorPoint=Vector2.new(.5,0); transferText.Position=UDim2.new(.5,0,.5,19)
local transferId=nil
local function showTransfer(packet)
	transferId=packet.id; transferGui.Enabled=true
	transferText.Text="@"..tostring(packet.ownerUsername or "Creator").." approved your request. Joining as a Viewer..."
	-- Do not change the global custom-teleport GUI used by other features.
end
local function hideTransfer(id)
	if id and transferId~=id then return end
	transferId=nil; transferGui.Enabled=false
end

local function isOwner()
	local owner=tonumber(workspace:GetAttribute("ParkourCreatorOwnerUserId"))
	if owner then return owner==player.UserId and workspace:GetAttribute("ParkourCreatorOwnerPresent")~=false end
	return player:GetAttribute("ParkourCreatorOwner")==true
end
local function inCreator()
	return player:GetAttribute("ParkourPrivateCreator")==true or player:GetAttribute("ParkourCreatorGuest")==true
		or player:GetAttribute("ParkourCreatorOwner")==true
end
local thumbnails={}
local function setAvatar(image,id)
	image:SetAttribute("RequestedUserId",id)
	if thumbnails[id] then image.Image=thumbnails[id]; return end
	if type(id)~="number" or id<1 then return end
	task.spawn(function()
		local ok,url=pcall(function()
			return Players:GetUserThumbnailAsync(id,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size150x150)
		end)
		if ok and type(url)=="string" then
			thumbnails[id]=url
			if image.Parent and image:GetAttribute("RequestedUserId")==id then image.Image=url end
		end
	end)
end
local function decorativeTile(parent,position)
	local viewport=make("ViewportFrame",{Name="DecorativeParkourTile",Size=UDim2.fromOffset(61,61),Position=position,
		BackgroundColor3=C.BG,BorderSizePixel=0,Ambient=Color3.fromRGB(180,195,215),
		LightColor=Color3.fromRGB(200,230,255),LightDirection=Vector3.new(-1,-1,-1),
		ZIndex=parent.ZIndex+1},parent)
	round(viewport,7); stroke(viewport,C.Border,1)
	local camera=make("Camera",{CFrame=CFrame.lookAt(Vector3.new(10,9,12),Vector3.new(0,1,0)),FieldOfView=40},viewport)
	viewport.CurrentCamera=camera
	local model=make("Model",{Name="IllustrationNotActualPlot"},viewport)
	for i=1,5 do
		local y=(i-1)*.55
		local part=make("Part",{Anchored=true,Size=Vector3.new(2,.5,2),
			CFrame=CFrame.new((i-3)*1.8,y,math.sin(i)*2),Color=C.Raised,
			Material=Enum.Material.SmoothPlastic},model)
		make("Part",{Anchored=true,Size=Vector3.new(2,.09,2),CFrame=part.CFrame*CFrame.new(0,.29,0),
			Color=C.Cyan,Material=Enum.Material.SmoothPlastic},model)
	end
	return viewport
end

local servers,serverOrder,rowViews={}, {}, {}
local currentFilter=1
local requestDuration=30
local outgoingRequest,sendingSession=nil,nil
local sequences,lastResponse,hasMore,loading=0,0,false,false
local requestRevisions={}
local loadedExtraPages=false
local rowsRendered=0
local function isTerminal(s)
	return s=="Declined" or s=="Expired" or s=="Cancelled" or s=="OwnerLeft" or s=="Closed"
		or s=="Full" or s=="Failed" or s=="Arrived"
end
local render,requestBrowse
local function createRow(id)
	local row=make("Frame",{Name="Server_"..id,Size=UDim2.new(1,0,0,88),BackgroundColor3=C.Panel,
		BorderSizePixel=0,ZIndex=list.ZIndex+1},list)
	round(row,12); stroke(row,C.Border,1); gradient(row,Color3.fromRGB(11,41,65),Color3.fromRGB(5,24,41))
	local avatar=make("ImageLabel",{Size=UDim2.fromOffset(62,62),Position=UDim2.fromOffset(17,12),
		BackgroundColor3=C.BG,BorderSizePixel=0,Image="",ZIndex=row.ZIndex+1},row)
	round(avatar,31); stroke(avatar,C.Cyan,2)
	local online=make("Frame",{Size=UDim2.fromOffset(14,14),Position=UDim2.fromOffset(67,61),
		BackgroundColor3=C.Green,BorderSizePixel=0,ZIndex=row.ZIndex+2},row)
	round(online,7); stroke(online,C.Panel,2)
	local name=label(row,"",17,UDim2.fromOffset(96,18),154,25,C.White)
	local handle=label(row,"",12,UDim2.fromOffset(96,45),154,22,C.Muted)
	local badge=make("Frame",{Size=UDim2.fromOffset(118,32),Position=UDim2.fromOffset(259,27),
		BackgroundColor3=Color3.fromRGB(0,46,37),BorderSizePixel=0,ZIndex=row.ZIndex+1},row)
	round(badge,7); local badgeStroke=stroke(badge,C.Green,1.5)
	local badgeText=label(badge,"IN CREATOR",11,UDim2.fromScale(0,0),118,32,C.Green,Enum.Font.GothamBlack)
	badgeText.TextXAlignment=Enum.TextXAlignment.Center
	groupIcon(row,UDim2.fromOffset(392,28),.36,C.Muted)
	local count=label(row,"-- / --",19,UDim2.fromOffset(422,20),83,28,C.White,Enum.Font.GothamBlack)
	label(row,"In server",10,UDim2.fromOffset(422,48),81,20,C.Muted)
	decorativeTile(row,UDim2.fromOffset(508,13))
	label(row,"Creator session",12,UDim2.fromOffset(580,20),151,23,C.White)
	label(row,"Preview illustration",10,UDim2.fromOffset(580,47),151,22,C.Muted)
	local join=button(row,"REQUEST TO JOIN",UDim2.new(1,-185,0,21),UDim2.fromOffset(172,46),true)
	local view={row=row,name=name,handle=handle,count=count,badge=badgeText,badgeStroke=badgeStroke,join=join,avatar=avatar}
	join.Activated:Connect(function()
		local d=servers[id]
		if not d or outgoingRequest or sendingSession or not join.Active then return end
		sendingSession=id; render()
		remote:FireServer("Request",{sessionId=id})
		task.delay(12,function()
			if sendingSession==id and not outgoingRequest then
				sendingSession=nil; render()
				notify("REQUEST NOT CONFIRMED","No confirmation received. Please retry shortly.")
				remote:FireServer("Sync")
			end
		end)
	end)
	return view
end
render=function()
	local query=search.Text:lower():gsub("^%s+",""):gsub("%s+$","")
	local visibleCount=0
	for index,id in ipairs(serverOrder) do
		local d=servers[id]
		local view=rowViews[id]
		if not view then view=createRow(id); rowViews[id]=view end
		view.row.LayoutOrder=index
		local matches=query=="" or d.username:lower():find(query,1,true) or d.displayName:lower():find(query,1,true)
		local full=d.count>=d.limit
		local matchesFilter=currentFilter==1 or (currentFilter==2 and not full and d.ready and d.accepting)
			or (currentFilter==3 and full)
		view.row.Visible=matches~=nil and matches~=false and matchesFilter
		if view.row.Visible then visibleCount=visibleCount+1 end
		view.name.Text=d.displayName; view.handle.Text="@"..d.username
		view.count.Text=string.format("%d/%d",d.count,d.limit)
		if view.avatar:GetAttribute("RequestedUserId")~=d.ownerUserId then setAvatar(view.avatar,d.ownerUserId) end
		local color=C.Green
		local status="IN CREATOR"
		if not d.ready then status="UNAVAILABLE"; color=C.Muted
		elseif not d.accepting then status="PAUSED"; color=C.Muted
		elseif full then status="FULL"; color=C.Red end
		view.badge.Text=status; view.badge.TextColor3=color; view.badgeStroke.Color=color
		local busyForThis=outgoingRequest and outgoingRequest.sessionId==id
		if sendingSession==id then view.join.Text="SENDING..."
		elseif busyForThis then view.join.Text=outgoingRequest.state=="Transferring" and "JOINING..." or "REQUESTED"
		elseif not d.ready then view.join.Text="UNAVAILABLE"
		elseif not d.accepting then view.join.Text="REQUESTS PAUSED"
		elseif full then view.join.Text="FULL"
		else view.join.Text="REQUEST TO JOIN" end
		view.join.Active=not outgoingRequest and not sendingSession and d.ready and d.accepting and not full
		view.join.TextTransparency=view.join.Active and 0 or .28
		view.join.BackgroundTransparency=view.join.Active and 0 or .5
		view.join:FindFirstChildOfClass("UIStroke").Transparency=view.join.Active and 0 or .6
	end
	rowsRendered=visibleCount
	empty.Visible=visibleCount==0
	if visibleCount==0 and not loading then
		empty.Text=(query~="" or currentFilter~=1) and "No loaded servers match these filters. Try another search or LOAD MORE."
			or "No active Creator servers yet. A Creator must be online in a server running this update."
	end
	more.Visible=hasMore; more.Active=hasMore and not loading
	refresh.Active=not loading; refresh.Text=loading and "LOADING..." or "REFRESH"
end
requestBrowse=function(morePages)
	if loading or inCreator() then return end
	sequences=sequences+1; local seq=sequences
	loading=true
	if not next(servers) then empty.Text="Loading Creator servers..."; empty.Visible=true end
	render()
	remote:FireServer("Browse",{sequence=seq,more=morePages==true})
	task.delay(12,function()
		if loading and sequences==seq and lastResponse<seq then
			loading=false; render(); empty.Visible=rowsRendered==0
			if rowsRendered==0 then empty.Text="No response from the server. Check the server Script, then press REFRESH." end
			notify("LISTINGS UNAVAILABLE","The browser did not receive a response. Please try again.")
		end
	end)
end
local function closeBrowser()
	shade.Visible=false; filterMenu.Visible=false
end
local function openBrowser()
	if inCreator() then return end
	shade.Visible=true; panel.Position=UDim2.new(.5,0,.5,10)
	TweenService:Create(panel,TweenInfo.new(.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
		{Position=UDim2.fromScale(.5,.5)}):Play()
	requestBrowse(false)
end
close.Activated:Connect(closeBrowser)
shade.Activated:Connect(function()
	local mouse=UIS:GetMouseLocation()
	local pos,size=panel.AbsolutePosition,panel.AbsoluteSize
	if mouse.X<pos.X or mouse.X>pos.X+size.X or mouse.Y<pos.Y or mouse.Y>pos.Y+size.Y then closeBrowser() end
end)
filterButton.Activated:Connect(function() filterMenu.Visible=not filterMenu.Visible end)
for i,b in ipairs(filterOptions) do
	b.Activated:Connect(function()
		currentFilter=i; filterButton.Text=filterNames[i]; filterMenu.Visible=false; render()
	end)
end
search:GetPropertyChangedSignal("Text"):Connect(render)
refresh.Activated:Connect(function() requestBrowse(false) end)
more.Activated:Connect(function() if hasMore then requestBrowse(true) end end)
cancelRequest.Activated:Connect(function()
	if outgoingRequest and outgoingRequest.state=="Pending" then
		remote:FireServer("Cancel",{id=outgoingRequest.id})
	end
end)

local inbox,inboxOpen,lastInboxIds,decisionBusy={},true,{},nil
local function refreshOwnerPanel()
	local r=inbox[1]
	ownerOpen.Text="JOIN REQUESTS  ("..#inbox..")"
	queueLabel.Text=tostring(#inbox).." WAITING"
	pause.Text=inboxOpen and "REQUESTS OPEN" or "REQUESTS PAUSED"
	pause.TextColor3=inboxOpen and C.Green or C.Muted
	requesterAvatar.Visible=r~=nil
	ownerTrack.Visible=r~=nil; remainingLabel.Visible=r~=nil
	accept.Visible=r~=nil; decline.Visible=r~=nil
	if r then
		requesterName.Text=r.displayName; requesterUser.Text="@"..r.username
		setAvatar(requesterAvatar,r.requesterUserId)
		ownerDescription.Text="Wants to join your Creator server. Approval gives VIEWER access only."
	else
		requesterName.Text="No pending requests"
		requesterUser.Text="Players can request from Discover."
		ownerDescription.Text=inboxOpen and "Requests are open. New requests will appear here."
			or "Join requests are paused. Direct invitations are unchanged."
	end
end
ownerOpen.Activated:Connect(function()
	ownerShade.Visible=not ownerShade.Visible
	if ownerShade.Visible then remote:FireServer("Sync"); refreshOwnerPanel() end
end)
ownerClose.Activated:Connect(function() ownerShade.Visible=false end)
pause.Activated:Connect(function() if isOwner() then remote:FireServer("SetOpen",{open=not inboxOpen}) end end)
local function respond(approve)
	local r=inbox[1]
	if not r or decisionBusy or not isOwner() then return end
	decisionBusy=r.id
	remote:FireServer("Respond",{id=r.id,requesterUserId=r.requesterUserId,approve=approve})
	task.delay(8,function()
		if decisionBusy==r.id then
			decisionBusy=nil
			notify("RESPONSE NOT CONFIRMED","Please check the request and try again.")
			remote:FireServer("Sync")
		end
	end)
end
accept.Activated:Connect(function() if accept.Active then respond(true) end end)
decline.Activated:Connect(function() if decline.Active then respond(false) end end)

-- Add the new tab to the verified Discover tab row; do not replace DiscoverClient.
local discoverGui,attachedTab,tabRow=nil,nil,nil
local fallback=button(root,"CREATOR SERVERS",UDim2.new(0,22,1,-72),UDim2.fromOffset(178,43),true)
fallback.Visible=false
fallback.Activated:Connect(openBrowser)
local function findTabRow(g)
	for _,o in ipairs(g:GetDescendants()) do
		if o:IsA("TextButton") and o~=attachedTab then
			local text=o.Text:upper():gsub("%s+"," ")
			if text=="MY CREATIONS" or text=="MY CREATORS" then return o.Parent end
		end
	end
	return nil
end
local function discoverVisible()
	if inCreator() then return false end
	if pg:GetAttribute("CreatorTransitionActive")==true then return false end
	local g=pg:FindFirstChild("ParkourDiscoverUI")
	if not g or not g:IsA("ScreenGui") or not g.Enabled then return false end
	local row=tabRow
	if row and row.Parent then
		local p=row
		while p and p~=g do
			if p:IsA("GuiObject") and not p.Visible then return false end
			p=p.Parent
		end
	end
	return true
end
local function attachTab()
	local g=pg:FindFirstChild("ParkourDiscoverUI")
	if not g or not g:IsA("ScreenGui") then return end
	discoverGui=g
	if attachedTab and attachedTab:IsDescendantOf(g) then return end
	local row=findTabRow(g)
	if not row or not row:IsA("GuiObject") then return end
	tabRow=row
	attachedTab=button(row,"CREATOR SERVERS",UDim2.new(),UDim2.fromOffset(175,42),true)
	attachedTab.Name="CreatorServersTab"
	attachedTab.LayoutOrder=1000
	local layout=row:FindFirstChildOfClass("UIListLayout")
	if layout then layout.SortOrder=Enum.SortOrder.LayoutOrder end
	attachedTab.Activated:Connect(openBrowser)
end
local function refreshContext()
	attachTab()
	local visible=discoverVisible()
	local fits=false
	if attachedTab and tabRow and tabRow.Parent then
		local total=0
		local layout=tabRow:FindFirstChildOfClass("UIListLayout")
		for _,child in ipairs(tabRow:GetChildren()) do
			if child:IsA("GuiObject") and child~=attachedTab and child.Visible then
				total=total+child.AbsoluteSize.X+(layout and layout.Padding.Offset or 8)
			end
		end
		fits=tabRow.AbsoluteSize.X>=total+attachedTab.AbsoluteSize.X
		attachedTab.Visible=visible and fits
	end
	fallback.Visible=visible and not fits
	ownerOpen.Visible=isOwner()
	local sizeGui=pg:FindFirstChild("ParkourCreatorServerSizeUI")
	local sizeButton=sizeGui and sizeGui:FindFirstChild("OpenServerSize",true)
	if sizeButton and sizeButton:IsA("GuiObject") and sizeButton.Visible then
		local p=sizeButton.AbsolutePosition
		ownerOpen.Size=UDim2.fromOffset(sizeButton.AbsoluteSize.X,sizeButton.AbsoluteSize.Y)
		ownerOpen.Position=UDim2.fromOffset(p.X,p.Y+sizeButton.AbsoluteSize.Y+8)
	end
	if not visible then closeBrowser() end
	if not isOwner() then ownerShade.Visible=false end
	if inCreator() and not transferId then pendingBanner.Visible=false end
end

local function updateSizes()
	local camera=workspace.CurrentCamera
	if not camera then return end
	local v=camera.ViewportSize
	panelScale.Scale=math.min(1,(v.X-30)/980,(v.Y-40)/666)
	ownerScale.Scale=math.min(1,(v.X-30)/440,(v.Y-40)/334)
	ownerPanel.Position=v.X<650 and UDim2.fromScale(.5,.5) or UDim2.new(1,-240,.5,0)
	pendingScale.Scale=math.min(1,(v.X-24)/530)
	toastScale.Scale=math.min(1,(v.X-30)/395)
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateSizes)

remote.OnClientEvent:Connect(function(action,data)
	if type(data)~="table" then return end
	if action=="Directory" then
		if data.sequence~=sequences then return end
		lastResponse=data.sequence; loading=false
		if data.error then
			render()
			if rowsRendered==0 then empty.Text=data.message or "Could not load Creator servers."; empty.Visible=true end
			footer.Text=data.message or "Listings unavailable. Press REFRESH."
			return
		end
		if not data.append then
			local newIds={}
			for _,d in ipairs(data.rows or {}) do newIds[d.sessionId]=true end
			for id,view in pairs(rowViews) do
				if not newIds[id] then view.row:Destroy(); rowViews[id]=nil end
			end
			servers={}; serverOrder={}; loadedExtraPages=false
		else loadedExtraPages=true end
		for _,d in ipairs(data.rows or {}) do
			if type(d.sessionId)=="string" and type(d.username)=="string"
				and type(d.count)=="number" and type(d.limit)=="number" then
				if not servers[d.sessionId] then table.insert(serverOrder,d.sessionId) end
				servers[d.sessionId]=d
			end
		end
		hasMore=data.hasMore==true
		footer.Text=data.studio and "STUDIO: local simulated sessions only. Published servers show real cross-server listings."
			or (loadedExtraPages and "More servers loaded. REFRESH reloads the first page with current counts."
				or "Requests need Creator approval. Joining does not grant build permission.")
		render()
		if data.message and rowsRendered==0 then empty.Text=data.message end
	elseif action=="RequestStatus" then
		if type(data.id)~="string" then return end
		local revision=tonumber(data.revision) or 0
		if revision<=(requestRevisions[data.id] or 0) then return end
		requestRevisions[data.id]=revision
		sendingSession=nil
		local terminal=isTerminal(data.state)
		if terminal then
			if outgoingRequest and outgoingRequest.id==data.id then outgoingRequest=nil end
			hideTransfer(data.id)
			pendingBanner.Visible=false
			notify(data.state=="Arrived" and "WELCOME TO CREATOR" or "JOIN REQUEST",data.message or data.state)
		else
			outgoingRequest=data
			pendingBanner.Visible=data.state=="Pending"
			pendingLabel.Text="Waiting for @"..tostring(data.ownerUsername or "Creator").." to approve your request."
			cancelRequest.Active=data.state=="Pending"
			if data.state=="Pending" then notify("REQUEST SENT",data.message or "Waiting for owner approval.") end
			if data.state=="Transferring" then closeBrowser(); showTransfer(data) end
		end
		render()
	elseif action=="Inbox" then
		inbox=data.rows or {}; inboxOpen=data.requestsOpen~=false
		local new=false; local ids={}
		for _,r in ipairs(inbox) do
			ids[r.id]=true
			if not lastInboxIds[r.id] then new=true end
		end
		lastInboxIds=ids
		if decisionBusy and not ids[decisionBusy] then decisionBusy=nil end
		if new and isOwner() then ownerShade.Visible=true end
		refreshOwnerPanel()
	elseif action=="Decision" then
		if decisionBusy==data.id then decisionBusy=nil end
		if data.ok then
			for i=#inbox,1,-1 do
				if inbox[i].id==data.id then table.remove(inbox,i) end
			end
			refreshOwnerPanel()
		end
		notify(data.ok and "REQUEST UPDATED" or "REQUEST UNAVAILABLE",data.message or "Request updated.")
	elseif action=="Error" then
		sendingSession=nil; render(); notify("CREATOR SERVERS",data.message or "The request failed.")
	elseif action=="Hello" then
		if type(data.requestSeconds)=="number" and data.requestSeconds>0 then requestDuration=data.requestSeconds end
		refreshContext()
	elseif action=="StudioJoined" then
		hideTransfer(); closeBrowser(); outgoingRequest=nil; pendingBanner.Visible=false
	end
end)

local accumulated=0
RunService.RenderStepped:Connect(function(dt)
	accumulated=accumulated+dt
	if accumulated<.1 then return end
	accumulated=0
	updateSizes()
	local r=inbox[1]
	if ownerShade.Visible and r then
		local remaining=math.max(0,r.expiresAt-workspace:GetServerTimeNow())
		ownerProgress.Size=UDim2.fromScale(math.clamp(remaining/requestDuration,0,1),1)
		remainingLabel.Text=remaining>0 and tostring(math.ceil(remaining)).."s" or "0s"
		local enabled=remaining>0 and decisionBusy==nil and isOwner()
		accept.Active=enabled; decline.Active=enabled
		accept.Text=decisionBusy==r.id and "SENDING..." or "APPROVE"
		accept.TextTransparency=enabled and 0 or .35
		decline.TextTransparency=enabled and 0 or .35
	end
end)
UIS.InputBegan:Connect(function(input,processed)
	if processed or UIS:GetFocusedTextBox() then return end
	if input.KeyCode==Enum.KeyCode.Escape then closeBrowser(); ownerShade.Visible=false end
end)
for _,a in ipairs({"ParkourCreatorOwner","ParkourCreatorGuest","ParkourPrivateCreator","ParkourCreatorRole"}) do
	player:GetAttributeChangedSignal(a):Connect(function() task.defer(refreshContext) end)
end
for _,a in ipairs({"ParkourCreatorOwnerUserId","ParkourCreatorOwnerPresent"}) do
	workspace:GetAttributeChangedSignal(a):Connect(function() task.defer(refreshContext) end)
end
pg:GetAttributeChangedSignal("CreatorTransitionActive"):Connect(refreshContext)
-- Hooking the existing tab row is retried without changing unrelated ScreenGuis.
task.spawn(function()
	while screen.Parent do refreshContext(); task.wait(1) end
end)
task.spawn(function()
	while screen.Parent do
		task.wait(12)
		if shade.Visible and not loading and not loadedExtraPages then requestBrowse(false) end
	end
end)
updateSizes(); refreshContext(); render()
remote:FireServer("Ready")
-- If owner attributes arrived after Ready, ask for the pending inbox once more.
task.delay(3,function() if screen.Parent then remote:FireServer("Sync") end end)
print("[CREATOR BROWSER UI] V1 loaded. Creator Servers tab + approval inbox ready.")

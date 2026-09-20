-- ParkourCrossServerPlayerBrowserClient V2 - TIMED INVITES
-- LocalScript in StarterPlayer > StarterPlayerScripts
-- Replaces the existing ParkourCrossServerPlayerBrowserClient.
--
-- Adds:
--   ACCEPT (10) -> ACCEPT (1) -> EXPIRED
--   Owner sees INVITED (10) -> INVITED (1)
--   Same player cannot be invited again during active invitation
--   Other players can still be invited normally

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local TweenService=game:GetService("TweenService")
local RunService=game:GetService("RunService")

local player=Players.LocalPlayer
local dir=RS:WaitForChild("ParkourOnlineDirectoryEvent")
local invite=RS:WaitForChild("ParkourCreatorInviteEvent")
local kickGuestRemote=RS:WaitForChild("ParkourCreatorKickGuestEvent")
local ownerLeftRemote=RS:WaitForChild("ParkourCreatorOwnerLeftEvent")
local sessionActivityRemote=RS:WaitForChild("ParkourCreatorSessionActivityEvent")
local permissionRemote=RS:WaitForChild("ParkourCreatorGuestPermissionEvent")
local pg=player:WaitForChild("PlayerGui")

local INVITE_SECONDS=10
local playerButtons={} -- [userId] = current visible button
local playerNames={} -- [userId] = username for confirmed invite toasts
local inviteLocked={} -- [userId] = true while invitation is active
local lastInviteAttemptUserId=nil

-- SAME SERVER is determined directly from Players, not MemoryStore/directory flags.
local function isPlayerInThisServer(userId)
	userId=tonumber(userId)
	if not userId or userId==player.UserId then return false end
	return Players:GetPlayerByUserId(userId)~=nil
end
local directoryRenderBusy=false
local pendingDirectory=nil
local lastDirectorySignature=nil

local gui=Instance.new("ScreenGui")
gui.Name="ParkourCrossServerBrowser"
gui.ResetOnSpawn=false
gui.DisplayOrder=1450
gui.Parent=pg

local open=Instance.new("TextButton")
open.Size=UDim2.fromOffset(170,42)
open.Position=UDim2.new(1,-190,0,126)
open.Text="🌐 ONLINE PLAYERS"
open.Font=Enum.Font.GothamBlack
open.TextSize=11
open.TextColor3=Color3.new(1,1,1)
open.BackgroundColor3=Color3.fromRGB(15,115,190)
open.BorderSizePixel=0
open.Visible=false
open.Parent=gui
Instance.new("UICorner",open).CornerRadius=UDim.new(0,9)

local frame=Instance.new("Frame")
frame.AnchorPoint=Vector2.new(.5,.5)
frame.Position=UDim2.fromScale(.5,.5)
frame.Size=UDim2.fromOffset(480,480)
frame.BackgroundColor3=Color3.fromRGB(7,25,40)
frame.BorderSizePixel=0
frame.Visible=false
frame.Parent=gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,14)

local title=Instance.new("TextLabel")
title.Size=UDim2.new(1,-120,0,50)
title.Position=UDim2.fromOffset(18,8)
title.BackgroundTransparency=1
title.Text="ONLINE PLAYERS"
title.TextXAlignment=Enum.TextXAlignment.Left
title.Font=Enum.Font.GothamBlack
title.TextSize=18
title.TextColor3=Color3.new(1,1,1)
title.Parent=frame

local refresh=Instance.new("TextButton")
refresh.Size=UDim2.fromOffset(82,34)
refresh.Position=UDim2.new(1,-100,0,14)
refresh.Text="REFRESH"
refresh.Font=Enum.Font.GothamBlack
refresh.TextSize=9
refresh.TextColor3=Color3.new(1,1,1)
refresh.BackgroundColor3=Color3.fromRGB(25,100,145)
refresh.BorderSizePixel=0
refresh.Parent=frame

local list=Instance.new("ScrollingFrame")
list.Size=UDim2.new(1,-36,1,-78)
list.Position=UDim2.fromOffset(18,60)
list.BackgroundColor3=Color3.fromRGB(9,31,49)
list.BorderSizePixel=0
list.AutomaticCanvasSize=Enum.AutomaticSize.Y
list.CanvasSize=UDim2.new()
list.ScrollBarThickness=6
list.Parent=frame

local lay=Instance.new("UIListLayout")
lay.Padding=UDim.new(0,7)
lay.Parent=list

local function request()
	dir:FireServer("Request")
end

local function clear()
	table.clear(playerButtons)
	table.clear(playerNames)
	for _,x in ipairs(list:GetChildren()) do
		if x:IsA("Frame") then x:Destroy() end
	end
end

local function directorySignature(data)
	local pieces={}
	for _,d in ipairs(data or {}) do
		table.insert(pieces,table.concat({
			tostring(d.userId),
			tostring(d.username),
			tostring(d.displayName),
			tostring(d.isSelf==true),
		},"|"))
	end
	table.sort(pieces)
	return table.concat(pieces,";")
end

local function renderDirectory(data)
	local signature=directorySignature(data)

	-- Do not destroy/recreate all player rows if nothing actually changed.
	if signature==lastDirectorySignature then
		return
	end
	lastDirectorySignature=signature

	clear()

	for _,d in ipairs(data) do
		local row=Instance.new("Frame")
		row.Size=UDim2.new(1,-8,0,58)
		row.BackgroundColor3=Color3.fromRGB(19,43,61)
		row.BorderSizePixel=0
		row.Parent=list

		local name=Instance.new("TextLabel")
		name.Size=UDim2.new(1,-130,0,30)
		name.Position=UDim2.fromOffset(12,3)
		name.BackgroundTransparency=1
		name.Text=tostring(d.displayName).."  @"..tostring(d.username)
		name.TextXAlignment=Enum.TextXAlignment.Left
		name.Font=Enum.Font.GothamBold
		name.TextSize=12
		name.TextColor3=Color3.new(1,1,1)
		name.Parent=row

		local status=Instance.new("TextLabel")
		status.Name="PlayerStatus"
		status.Size=UDim2.new(1,-130,0,18)
		status.Position=UDim2.fromOffset(12,31)
		status.BackgroundTransparency=1
		status.Text="●  "..tostring(d.status or "IN LOBBY")
		status.TextXAlignment=Enum.TextXAlignment.Left
		status.Font=Enum.Font.GothamBold
		status.TextSize=9
		status.TextColor3=(d.status=="IN CREATOR SERVER")
			and Color3.fromRGB(90,220,255)
			or Color3.fromRGB(130,205,165)
		status.Parent=row

		local userId=tonumber(d.userId)
		if userId then
			playerNames[userId]=tostring(d.username or d.displayName or ("User"..userId))
		end
		local isSelf=d.isSelf==true or userId==player.UserId
		local isSameServer=isPlayerInThisServer(userId)

		local b=Instance.new("TextButton")
		b.Size=UDim2.fromOffset(100,36)
		b.Position=UDim2.new(1,-110,.5,-18)
		b.Font=Enum.Font.GothamBlack
		b.TextSize=10
		b.BorderSizePixel=0
		b.Parent=row

		if isSelf then
			b.Text="YOU"
			b.TextColor3=Color3.fromRGB(170,185,195)
			b.BackgroundColor3=Color3.fromRGB(48,61,72)
			b.Active=false
			b.AutoButtonColor=false

		elseif isSameServer then
			-- Guest has already arrived in this Creator server.
			-- The status label already says IN CREATOR SERVER, so the old
			-- SAME SERVER button is redundant. Keep only KICK.
			b.Visible=false
			b.Active=false
			b.AutoButtonColor=false

			local manage=Instance.new("TextButton")
			manage.Name="ManageGuest"
			manage.Size=UDim2.fromOffset(76,36)
			manage.Position=UDim2.new(1,-174,.5,-18)
			manage.Text="MANAGE"
			manage.Font=Enum.Font.GothamBlack
			manage.TextSize=9
			manage.TextColor3=Color3.new(1,1,1)
			manage.BackgroundColor3=Color3.fromRGB(25,120,175)
			manage.BorderSizePixel=0
			manage.Parent=row
			local mc=Instance.new("UICorner")
			mc.CornerRadius=UDim.new(0,8)
			mc.Parent=manage

			manage.Activated:Connect(function()
				permissionRemote:FireServer("RequestRole",userId)
				gui:SetAttribute("PendingManageGuestUserId",userId)
				gui:SetAttribute("PendingManageGuestName",tostring(d.username))
			end)

			local kick=Instance.new("TextButton")
			kick.Name="KickGuest"
			kick.Size=UDim2.fromOffset(72,36)
			kick.Position=UDim2.new(1,-82,.5,-18)
			kick.Text="KICK"
			kick.Font=Enum.Font.GothamBlack
			kick.TextSize=10
			kick.TextColor3=Color3.new(1,1,1)
			kick.BackgroundColor3=Color3.fromRGB(185,55,65)
			kick.BorderSizePixel=0
			kick.Parent=row
			local kc=Instance.new("UICorner")
			kc.CornerRadius=UDim.new(0,8)
			kc.Parent=kick

			local kickBusy=false
			kick.Activated:Connect(function()
				if kickBusy then return end
				if not isPlayerInThisServer(userId) then return end
				kickBusy=true
				kick.Active=false
				kick.Text="..."

				kickGuestRemote:FireServer(userId)

				task.delay(1,function()
					if kick.Parent then
						kickBusy=false
						kick.Active=true
						kick.Text="KICK"
					end
				end)
			end)

		else
			playerButtons[userId]=b
			b.Text="INVITE"
			b.TextColor3=Color3.new(1,1,1)
			b.BackgroundColor3=Color3.fromRGB(20,145,225)
			b.Active=true
			b.AutoButtonColor=true

			local clickBusy=false

			local function refreshInviteEnabled()
				local locked=inviteLocked[userId]==true
				b.Active=not locked
				b.AutoButtonColor=not locked

				if locked then
					b.Text="INVITED"
					b.TextColor3=Color3.fromRGB(170,190,200)
					b.BackgroundColor3=Color3.fromRGB(48,61,72)
				else
					b.Text="INVITE"
					b.TextColor3=Color3.new(1,1,1)
					b.BackgroundColor3=Color3.fromRGB(20,145,225)
				end
			end

			refreshInviteEnabled()

			b.Activated:Connect(function()
				if clickBusy or inviteLocked[userId] then return end
				clickBusy=true

				-- Lock immediately to prevent duplicate clicks while waiting
				-- for the server confirmation.
				inviteLocked[userId]=true
				lastInviteAttemptUserId=userId
				refreshInviteEnabled()

				invite:FireServer("Invite",userId)

				task.delay(.5,function()
					clickBusy=false
				end)
			end)

			b:SetAttribute("InviteUserId",userId)
		end
	end
end

local function queueDirectoryRender(data)
	pendingDirectory=data
	if directoryRenderBusy then return end
	directoryRenderBusy=true

	task.defer(function()
		-- Coalesce directory responses arriving close together.
		task.wait(.08)
		local newest=pendingDirectory
		pendingDirectory=nil
		if type(newest)=="table" then
			renderDirectory(newest)
		end
		directoryRenderBusy=false

		-- If another response arrived during rendering, process the newest one.
		if pendingDirectory then
			queueDirectoryRender(pendingDirectory)
		end
	end)
end

dir.OnClientEvent:Connect(function(action,data)
	if action~="Directory" then return end
	if type(data)~="table" then return end
	queueDirectoryRender(data)
end)

-- OLD DIRECTORY HANDLER REMOVED BELOW
-- Local server membership is authoritative for SAME SERVER.
-- Invalidate the cached directory signature so the row is rebuilt immediately.
local function refreshForLocalMembership()
	lastDirectorySignature=nil
	if frame.Visible then
		request()
	end
end

Players.PlayerAdded:Connect(function(joined)
	if joined~=player then
		task.defer(refreshForLocalMembership)
	end
end)

Players.PlayerRemoving:Connect(function(leaving)
	if leaving~=player then
		task.defer(refreshForLocalMembership)
	end
end)

open.Activated:Connect(function()
	frame.Visible=not frame.Visible
	if frame.Visible then request() end
end)

refresh.Activated:Connect(request)

local function setInviteLocked(userId,locked)
	userId=tonumber(userId)
	if not userId then return end

	inviteLocked[userId]=locked==true

	local b=playerButtons[userId]
	if not b or not b.Parent then return end

	if locked then
		b.Text="INVITED"
		b.TextColor3=Color3.fromRGB(170,190,200)
		b.BackgroundColor3=Color3.fromRGB(48,61,72)
		b.Active=false
		b.AutoButtonColor=false
	else
		b.Text="INVITE"
		b.TextColor3=Color3.new(1,1,1)
		b.BackgroundColor3=Color3.fromRGB(20,145,225)
		b.Active=true
		b.AutoButtonColor=true
	end
end

-- =========================================================
-- STRONG CONFIRMED INVITATION TOASTS
-- Separate from the static INVITE buttons so button text never flickers.
-- =========================================================
local toastHolder=Instance.new("Frame")
toastHolder.Name="InviteToastHolder"
toastHolder.AnchorPoint=Vector2.new(1,0)
toastHolder.Position=UDim2.new(1,-18,0,330)
toastHolder.Size=UDim2.fromOffset(390,300)
toastHolder.BackgroundTransparency=1
toastHolder.Parent=gui

local toastLayout=Instance.new("UIListLayout")
toastLayout.Padding=UDim.new(0,10)
toastLayout.HorizontalAlignment=Enum.HorizontalAlignment.Right
toastLayout.SortOrder=Enum.SortOrder.LayoutOrder
toastLayout.Parent=toastHolder

local toastOrder=0

local function showStatusToast(headingText,bodyText,symbol)
	toastOrder+=1

	local slot=Instance.new("Frame")
	slot.Name="InviteToastSlot"
	slot.Size=UDim2.fromOffset(390,82)
	slot.BackgroundTransparency=1
	slot.LayoutOrder=-toastOrder
	slot.ClipsDescendants=false
	slot.Parent=toastHolder

	local toast=Instance.new("Frame")
	toast.Name="InviteSentToast"
	toast.Size=UDim2.fromOffset(360,82)
	toast.AnchorPoint=Vector2.new(1,0)
	toast.Position=UDim2.new(1,400,0,0)
	toast.BackgroundColor3=Color3.fromRGB(5,28,45)
	toast.BorderSizePixel=0
	toast.Parent=slot

	local tc=Instance.new("UICorner")
	tc.CornerRadius=UDim.new(0,13)
	tc.Parent=toast

	local stroke=Instance.new("UIStroke")
	stroke.Color=Color3.fromRGB(40,205,255)
	stroke.Thickness=2.5
	stroke.Transparency=.05
	stroke.Parent=toast

	local accent=Instance.new("Frame")
	accent.Size=UDim2.fromOffset(6,58)
	accent.Position=UDim2.fromOffset(10,12)
	accent.BackgroundColor3=Color3.fromRGB(40,205,255)
	accent.BorderSizePixel=0
	accent.Parent=toast
	local acc=Instance.new("UICorner");acc.CornerRadius=UDim.new(1,0);acc.Parent=accent

	local check=Instance.new("TextLabel")
	check.Size=UDim2.fromOffset(42,42)
	check.Position=UDim2.fromOffset(27,20)
	check.BackgroundTransparency=1
	check.Text=tostring(symbol or "✓")
	check.Font=Enum.Font.GothamBlack
	check.TextSize=30
	check.TextColor3=Color3.fromRGB(80,230,255)
	check.Parent=toast

	local heading=Instance.new("TextLabel")
	heading.Size=UDim2.new(1,-85,0,27)
	heading.Position=UDim2.fromOffset(76,14)
	heading.BackgroundTransparency=1
	heading.Text=tostring(headingText)
	heading.TextXAlignment=Enum.TextXAlignment.Left
	heading.Font=Enum.Font.GothamBlack
	heading.TextSize=15
	heading.TextColor3=Color3.new(1,1,1)
	heading.Parent=toast

	local body=Instance.new("TextLabel")
	body.Size=UDim2.new(1,-85,0,25)
	body.Position=UDim2.fromOffset(76,42)
	body.BackgroundTransparency=1
	body.Text=tostring(bodyText)
	body.TextXAlignment=Enum.TextXAlignment.Left
	body.Font=Enum.Font.GothamMedium
	body.TextSize=13
	body.TextColor3=Color3.fromRGB(155,215,240)
	body.Parent=toast

	-- Match the guest invitation popup: slide in from beyond the right edge.
	TweenService:Create(
		toast,
		TweenInfo.new(.3,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),
		{Position=UDim2.new(1,0,0,0)}
	):Play()

	task.delay(2.7,function()
		if not toast.Parent then return end

		-- Slide back out to the right, just like the invitation popup.
		local slideOut=TweenService:Create(
			toast,
			TweenInfo.new(.2,Enum.EasingStyle.Quart,Enum.EasingDirection.In),
			{Position=UDim2.new(1,400,0,0)}
		)
		slideOut:Play()
		slideOut.Completed:Wait()

		if slot.Parent then
			slot:Destroy()
		end
	end)
end

-- =========================================================
-- GUEST PERMISSION MANAGEMENT
-- =========================================================
local permissionPanel=Instance.new("Frame")
permissionPanel.Name="GuestPermissionPanel"
permissionPanel.AnchorPoint=Vector2.new(.5,.5)
permissionPanel.Position=UDim2.fromScale(.5,.5)
permissionPanel.Size=UDim2.fromOffset(390,310)
permissionPanel.BackgroundColor3=Color3.fromRGB(7,25,40)
permissionPanel.BorderSizePixel=0
permissionPanel.Visible=false
permissionPanel.ZIndex=200
permissionPanel.Parent=gui
Instance.new("UICorner",permissionPanel).CornerRadius=UDim.new(0,14)

local ppStroke=Instance.new("UIStroke")
ppStroke.Color=Color3.fromRGB(55,195,255)
ppStroke.Thickness=2
ppStroke.Parent=permissionPanel

local ppTitle=Instance.new("TextLabel")
ppTitle.Size=UDim2.new(1,-30,0,36)
ppTitle.Position=UDim2.fromOffset(15,12)
ppTitle.BackgroundTransparency=1
ppTitle.Text="GUEST PERMISSIONS"
ppTitle.TextXAlignment=Enum.TextXAlignment.Left
ppTitle.Font=Enum.Font.GothamBlack
ppTitle.TextSize=16
ppTitle.TextColor3=Color3.fromRGB(110,220,255)
ppTitle.ZIndex=201
ppTitle.Parent=permissionPanel

local ppGuest=Instance.new("TextLabel")
ppGuest.Size=UDim2.new(1,-30,0,28)
ppGuest.Position=UDim2.fromOffset(15,48)
ppGuest.BackgroundTransparency=1
ppGuest.Text="@guest"
ppGuest.TextXAlignment=Enum.TextXAlignment.Left
ppGuest.Font=Enum.Font.GothamBold
ppGuest.TextSize=13
ppGuest.TextColor3=Color3.new(1,1,1)
ppGuest.ZIndex=201
ppGuest.Parent=permissionPanel

local ppCurrent=Instance.new("TextLabel")
ppCurrent.Size=UDim2.new(1,-30,0,24)
ppCurrent.Position=UDim2.fromOffset(15,78)
ppCurrent.BackgroundTransparency=1
ppCurrent.Text="CURRENT: NO PERMISSION"
ppCurrent.TextXAlignment=Enum.TextXAlignment.Left
ppCurrent.Font=Enum.Font.GothamBold
ppCurrent.TextSize=10
ppCurrent.TextColor3=Color3.fromRGB(155,215,240)
ppCurrent.ZIndex=201
ppCurrent.Parent=permissionPanel

local function roleButton(text,y,description)
	local b=Instance.new("TextButton")
	b.Size=UDim2.new(1,-30,0,54)
	b.Position=UDim2.fromOffset(15,y)
	b.BackgroundColor3=Color3.fromRGB(20,58,82)
	b.BorderSizePixel=0
	b.Text=""
	b.ZIndex=201
	b.Parent=permissionPanel
	Instance.new("UICorner",b).CornerRadius=UDim.new(0,9)

	local t=Instance.new("TextLabel")
	t.Size=UDim2.new(1,-20,0,22)
	t.Position=UDim2.fromOffset(10,6)
	t.BackgroundTransparency=1
	t.Text=text
	t.TextXAlignment=Enum.TextXAlignment.Left
	t.Font=Enum.Font.GothamBlack
	t.TextSize=12
	t.TextColor3=Color3.new(1,1,1)
	t.ZIndex=202
	t.Parent=b

	local d=Instance.new("TextLabel")
	d.Size=UDim2.new(1,-20,0,18)
	d.Position=UDim2.fromOffset(10,29)
	d.BackgroundTransparency=1
	d.Text=description
	d.TextXAlignment=Enum.TextXAlignment.Left
	d.Font=Enum.Font.Gotham
	d.TextSize=10
	d.TextColor3=Color3.fromRGB(155,195,215)
	d.ZIndex=202
	d.Parent=b
	return b
end

local viewer=roleButton("VIEWER",108,"Can explore and watch. Cannot edit the parkour.")
local collaborator=roleButton("COLLABORATOR",168,"Can build and modify the owner's parkour.")

local closePermission=Instance.new("TextButton")
closePermission.Size=UDim2.new(1,-30,0,38)
closePermission.Position=UDim2.fromOffset(15,244)
closePermission.BackgroundColor3=Color3.fromRGB(25,120,175)
closePermission.BorderSizePixel=0
closePermission.Text="CLOSE"
closePermission.Font=Enum.Font.GothamBlack
closePermission.TextSize=9
closePermission.TextColor3=Color3.new(1,1,1)
closePermission.ZIndex=201
closePermission.Parent=permissionPanel
Instance.new("UICorner",closePermission).CornerRadius=UDim.new(0,8)

local managedGuestUserId=nil

viewer.Activated:Connect(function()
	if managedGuestUserId then
		permissionRemote:FireServer("SetRole",managedGuestUserId,"Viewer")
	end
end)

collaborator.Activated:Connect(function()
	if managedGuestUserId then
		permissionRemote:FireServer("SetRole",managedGuestUserId,"Collaborator")
	end
end)



closePermission.Activated:Connect(function()
	permissionPanel.Visible=false
	managedGuestUserId=nil
end)

permissionRemote.OnClientEvent:Connect(function(action,a,b,c)
	if action=="RoleState" then
		managedGuestUserId=tonumber(a)
		local role=b
		local username=gui:GetAttribute("PendingManageGuestName") or "guest"
		ppGuest.Text="@"..tostring(username)
		ppCurrent.Text="CURRENT: "..(role and string.upper(tostring(role)) or "NO PERMISSION")
		permissionPanel.Visible=true

	elseif action=="PermissionChanged" then
		local userId=tonumber(a)
		local role=b
		local username=tostring(c or "guest")
		if managedGuestUserId==userId then
			ppCurrent.Text="CURRENT: "..(role and string.upper(tostring(role)) or "NO PERMISSION")
		end
		showStatusToast(
			"PERMISSION UPDATED",
			role and ("@"..username.." is now "..string.upper(role)..".")
				or ("Permissions removed from @"..username.."."),
			"✓"
		)

	elseif action=="YourRoleChanged" then
		local role=a

		-- Direct server-confirmed UI update for THIS guest only.
		-- This avoids relying on LocalScript startup order or attribute
		-- replication timing. The owner never receives YourRoleChanged.
		local builder=pg:FindFirstChild("ParkourBuilderUI")
		if builder and builder:IsA("ScreenGui") then
			builder.Enabled=(role=="Collaborator")
		end

		-- Also publish a local PlayerGui state so a BuilderUI created a
		-- fraction later can recover the intended permission state.
		pg:SetAttribute("ParkourLocalCanBuild",role=="Collaborator")

		showStatusToast(
			"ROLE UPDATED",
			role and ("Your role is now "..string.upper(tostring(role))..".")
				or "Your Creator permissions were removed.",
			"✓"
		)

	elseif action=="PermissionFailed" then
		showStatusToast("PERMISSION FAILED",tostring(a or "Could not update permission."),"!")
	end
end)

-- Small guest join/leave notifications.
sessionActivityRemote.OnClientEvent:Connect(function(action,userId,username,displayName)
	local shownName=tostring(displayName or username or "Player")
	local handle=tostring(username or shownName)

	if action=="GuestJoined" then
		showStatusToast(
			"PLAYER JOINED",
			shownName.."  @"..handle.." joined your Creator server.",
			"+"
		)
	elseif action=="GuestLeft" then
		showStatusToast(
			"PLAYER LEFT",
			shownName.."  @"..handle.." left your Creator server.",
			"−"
		)
	end
end)

-- Reserved Creator owner-left notification.
ownerLeftRemote.OnClientEvent:Connect(function(ownerUserId,ownerName)
	showStatusToast(
		"OWNER LEFT",
		"@"..tostring(ownerName or "Creator").." has left the Creator server.",
		"!"
	)
end)

-- =========================================================
-- INCOMING CREATOR INVITATION
-- =========================================================
local incoming=Instance.new("Frame")
incoming.Name="IncomingInvite"
incoming.Size=UDim2.fromOffset(420,210)
incoming.AnchorPoint=Vector2.new(1,0)
incoming.Position=UDim2.new(1,400,0,135)
incoming.BackgroundColor3=Color3.fromRGB(7,25,40)
incoming.BorderSizePixel=0
incoming.ZIndex=20
incoming.Visible=false
incoming.ClipsDescendants=false
incoming.Parent=gui

local ic=Instance.new("UICorner")
ic.CornerRadius=UDim.new(0,14)
ic.Parent=incoming

local ist=Instance.new("UIStroke")
ist.Color=Color3.fromRGB(55,195,255)
ist.Thickness=2
ist.Parent=incoming

local inviteTitle=Instance.new("TextLabel")
inviteTitle.Size=UDim2.new(1,-28,0,32)
inviteTitle.Position=UDim2.fromOffset(14,10)
inviteTitle.BackgroundTransparency=1
inviteTitle.Text="CREATOR INVITATION"
inviteTitle.TextXAlignment=Enum.TextXAlignment.Left
inviteTitle.Font=Enum.Font.GothamBlack
inviteTitle.TextSize=14
inviteTitle.TextColor3=Color3.fromRGB(110,220,255)
inviteTitle.ZIndex=22
inviteTitle.Parent=incoming

local inviteBody=Instance.new("TextLabel")
inviteBody.Size=UDim2.new(1,-28,0,45)
inviteBody.Position=UDim2.fromOffset(14,43)
inviteBody.BackgroundTransparency=1
inviteBody.TextWrapped=true
inviteBody.TextXAlignment=Enum.TextXAlignment.Left
inviteBody.TextYAlignment=Enum.TextYAlignment.Top
inviteBody.Font=Enum.Font.Gotham
inviteBody.TextSize=12
inviteBody.TextColor3=Color3.new(1,1,1)
inviteBody.ZIndex=22
inviteBody.Parent=incoming

local accept=Instance.new("TextButton")
accept.Size=UDim2.new(.5,-20,0,42)
accept.Position=UDim2.fromOffset(14,150)
accept.BackgroundColor3=Color3.fromRGB(20,155,225)
accept.BorderSizePixel=0
accept.Text="ACCEPT"
accept.Font=Enum.Font.GothamBlack
accept.TextSize=12
accept.TextColor3=Color3.new(1,1,1)
accept.ZIndex=22
accept.Parent=incoming

local ac=Instance.new("UICorner")
ac.CornerRadius=UDim.new(0,9)
ac.Parent=accept

local decline=Instance.new("TextButton")
decline.Size=UDim2.new(.5,-20,0,42)
decline.Position=UDim2.new(.5,6,0,150)
decline.BackgroundColor3=Color3.fromRGB(55,66,78)
decline.BorderSizePixel=0
decline.Text="DECLINE"
decline.Font=Enum.Font.GothamBlack
decline.TextSize=12
decline.TextColor3=Color3.new(1,1,1)
decline.ZIndex=22
decline.Parent=incoming

local dc=Instance.new("UICorner")
dc.CornerRadius=UDim.new(0,9)
dc.Parent=decline

-- Invitation lifetime progress slider (visual only).
local timeLabel=Instance.new("TextLabel")
timeLabel.Name="InviteTimeLabel"
timeLabel.Size=UDim2.fromOffset(165,18)
timeLabel.Position=UDim2.fromOffset(14,100)
timeLabel.BackgroundTransparency=1
timeLabel.Text="TIME TO RESPOND"
timeLabel.TextXAlignment=Enum.TextXAlignment.Left
timeLabel.Font=Enum.Font.GothamBold
timeLabel.TextSize=10
timeLabel.TextColor3=Color3.fromRGB(125,205,240)
timeLabel.ZIndex=22
timeLabel.Parent=incoming

local secondsLabel=Instance.new("TextLabel")
secondsLabel.Name="InviteSeconds"
secondsLabel.Size=UDim2.fromOffset(48,21)
secondsLabel.Position=UDim2.new(1,-62,0,97)
secondsLabel.BackgroundTransparency=1
secondsLabel.Text="10s"
secondsLabel.TextXAlignment=Enum.TextXAlignment.Right
secondsLabel.Font=Enum.Font.GothamBold
secondsLabel.TextSize=14
secondsLabel.TextColor3=Color3.new(1,1,1)
secondsLabel.ZIndex=22
secondsLabel.Parent=incoming

local inviteProgressBack=Instance.new("Frame")
inviteProgressBack.Name="InviteTimeBack"
inviteProgressBack.Size=UDim2.new(1,-28,0,8)
inviteProgressBack.Position=UDim2.fromOffset(14,126)
inviteProgressBack.BackgroundColor3=Color3.fromRGB(55,78,98)
inviteProgressBack.BorderSizePixel=0
inviteProgressBack.ClipsDescendants=true
inviteProgressBack.ZIndex=22
inviteProgressBack.Parent=incoming
local ipbc=Instance.new("UICorner");ipbc.CornerRadius=UDim.new(1,0);ipbc.Parent=inviteProgressBack

local inviteProgress=Instance.new("Frame")
inviteProgress.Name="InviteTimeRemaining"
inviteProgress.Size=UDim2.fromScale(1,1)
inviteProgress.BackgroundColor3=Color3.fromRGB(30,195,245)
inviteProgress.BorderSizePixel=0
inviteProgress.ZIndex=23
inviteProgress.Parent=inviteProgressBack
local ipc=Instance.new("UICorner");ipc.CornerRadius=UDim.new(1,0);ipc.Parent=inviteProgress

local pendingOwner=nil
local incomingToken=0
local inviteProgressTween=nil
local inviteCountdownConnection=nil

local function hideIncoming()
	incomingToken+=1
	if inviteProgressTween then
		inviteProgressTween:Cancel()
		inviteProgressTween=nil
	end
	if inviteCountdownConnection then
		inviteCountdownConnection:Disconnect()
		inviteCountdownConnection=nil
	end
	pendingOwner=nil

	TweenService:Create(
		incoming,
		TweenInfo.new(.2),
		{Position=UDim2.new(1,400,0,135)}
	):Play()

	task.delay(.21,function()
		if not pendingOwner then
			incoming.Visible=false
		end
	end)

	accept.Active=true
	accept.AutoButtonColor=true
	accept.BackgroundTransparency=0
	accept.Text="ACCEPT"
	decline.Active=true
	decline.AutoButtonColor=true
	decline.BackgroundTransparency=0
end

local function showIncoming(ownerUserId,ownerName,serverExpiresAt)
	incomingToken+=1
	pendingOwner=tonumber(ownerUserId)

	if inviteProgressTween then
		inviteProgressTween:Cancel()
	end

	-- Server timestamp drives the display; server remains authoritative.
	local expiresAt=tonumber(serverExpiresAt) or (os.time()+INVITE_SECONDS)
	local remaining=math.clamp(expiresAt-os.time(),0,INVITE_SECONDS)

	inviteProgress.Size=UDim2.fromScale(math.clamp(remaining/INVITE_SECONDS,0,1),1)
	secondsLabel.Text=tostring(math.max(0,math.ceil(remaining))).."s"

	inviteProgressTween=TweenService:Create(
		inviteProgress,
		TweenInfo.new(remaining,Enum.EasingStyle.Linear),
		{Size=UDim2.fromScale(0,1)}
	)
	inviteProgressTween:Play()

	if inviteCountdownConnection then inviteCountdownConnection:Disconnect() end
	inviteCountdownConnection=RunService.Heartbeat:Connect(function()
		if pendingOwner~=tonumber(ownerUserId) then return end

		local secondsLeft=math.max(0,expiresAt-os.time())
		secondsLabel.Text=tostring(math.max(0,math.ceil(secondsLeft))).."s"

		-- Lock interaction during the final 1.5 seconds.
		-- The server still remains authoritative for actual expiration.
		local canRespond=secondsLeft>1.5

		accept.Active=canRespond
		accept.AutoButtonColor=canRespond
		decline.Active=canRespond
		decline.AutoButtonColor=canRespond

		if canRespond then
			accept.BackgroundTransparency=0
			decline.BackgroundTransparency=0
		else
			-- Slightly faded so it is obvious both buttons are disabled.
			accept.BackgroundTransparency=.35
			decline.BackgroundTransparency=.35
		end
	end)

	-- When the visual time bar reaches zero, close the invitation immediately.
	-- The server still validates/removes the invitation authoritatively.
	local thisOwner=pendingOwner
	local thisToken=incomingToken

	inviteProgressTween.Completed:Connect(function(playbackState)
		-- Ignore Cancelled tweens (Accept/Decline/new invitation).
		if playbackState~=Enum.PlaybackState.Completed then return end
		if incomingToken~=thisToken then return end
		if pendingOwner~=thisOwner then return end

		-- The progress bar is VISUAL ONLY.
		-- Do NOT FireServer("Expire") here. ParkourCreatorInviteServer V4.3
		-- already owns the 10-second expiry and sends exactly one Expired result
		-- to the Creator.
		accept.Active=false
		accept.AutoButtonColor=false
		decline.Active=false
		decline.AutoButtonColor=false

		hideIncoming()
	end)

	inviteBody.Text=
		"@"..tostring(ownerName)..
		" has invited you to join their server."

	incoming.Visible=true
	incoming.Position=UDim2.new(1,400,0,135)
	accept.Active=true
	accept.AutoButtonColor=true
	accept.BackgroundTransparency=0
	accept.Text="ACCEPT"
	decline.Active=true
	decline.AutoButtonColor=true
	decline.BackgroundTransparency=0

	TweenService:Create(
		incoming,
		TweenInfo.new(.3,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),
		{Position=UDim2.new(1,-18,0,135)}
	):Play()

end

accept.Activated:Connect(function()
	if not pendingOwner then return end

	local owner=pendingOwner
	incomingToken+=1

	accept.Active=false
	accept.AutoButtonColor=false
	accept.Text="JOINING..."

	invite:FireServer("Accept",owner)
end)

decline.Activated:Connect(function()
	if pendingOwner then
		invite:FireServer("Decline",pendingOwner)
	end
	hideIncoming()
end)

invite.OnClientEvent:Connect(function(action,a,b,c)
	if action=="InviteReceived" then
		showIncoming(a,b,c)

	elseif action=="InviteSent" then
		-- Server confirms that this player's invitation is now active.
		local userId=tonumber(a)
		if userId then
			if lastInviteAttemptUserId==userId then
				lastInviteAttemptUserId=nil
			end
			setInviteLocked(userId,true)
			local username=playerNames[userId] or ("User"..userId)
			showStatusToast("INVITATION SENT","Sent to @"..username,"✓")
		end

	elseif action=="InviteReleased" then
		local userId=tonumber(a)
		if userId then
			setInviteLocked(userId,false)
		end

	elseif action=="InviteResult" then
		local userId=tonumber(a)
		local result=tostring(b or "")
		local username=userId and (playerNames[userId] or ("User"..userId)) or "Player"

		-- Decline / timeout / accept all end the active invitation.
		if userId then
			setInviteLocked(userId,false)
		end

		if result=="Accepted" then
			showStatusToast(
				"INVITATION ACCEPTED",
				"@"..username.." accepted your invitation.",
				"✓"
			)
		elseif result=="Rejected" then
			showStatusToast(
				"INVITATION DECLINED",
				"@"..username.." declined your invitation.",
				"×"
			)
		elseif result=="Expired" then
			showStatusToast(
				"INVITATION TIMED OUT",
				"@"..username.." did not respond. Try inviting them again.",
				"!"
			)
		end

	elseif action=="InviteExpired" then
		local ownerUserId=tonumber(a)
		if pendingOwner and ownerUserId==pendingOwner then
			hideIncoming()
		end

	elseif action=="InviteFailed" then
		-- If the Creator's send failed, undo the immediate local lock.
		if lastInviteAttemptUserId then
			setInviteLocked(lastInviteAttemptUserId,false)
			lastInviteAttemptUserId=nil
		end

		-- Keep the Creator's INVITE button unchanged.
		-- Recipient can retry ACCEPT only while their popup is still present.
		if pendingOwner then
			accept.Active=true
			accept.AutoButtonColor=true
			accept.Text="ACCEPT"
		end

	elseif action=="StudioInviteAccepted" then
		hideIncoming()
	end
end)

RunService.RenderStepped:Connect(function()
	open.Visible=
		player:GetAttribute("ParkourPrivateCreator")==true
		and (player:GetAttribute("ParkourCreatorRole") or "Owner")=="Owner"
end)

print("✓ ParkourCrossServerPlayerBrowserClient V5.6 permission window without remove button loaded")

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local UIS=game:GetService("UserInputService")
local VIM=game:GetService("VirtualInputManager")
local GuiService=game:GetService("GuiService")
local Workspace=game:GetService("Workspace")

local LP=Players.LocalPlayer
local PG=LP:WaitForChild("PlayerGui")
local Camera=Workspace.CurrentCamera

local AUTO_FIRE=false
local HOLD_FIRE=false
local TEAM_CHECK=true
local WALL_CHECK=true
local DRAG_MODE=false
local PULL_AIM=false

local FIRE_DELAY=0.15
local MAX_DISTANCE=500
local SPREAD_MULTIPLIER=0.45

local MEMORY_TIME=10
local REACQUIRE_HOLD=0.30

local TRANSPARENCY_LIMIT=0.90
local TRANSPARENT_RATIO=0.75

local NEAR_DISTANCE=15
local MID_DISTANCE=100
local FAR_DISTANCE=220
local NEAR_RATIO=1.85
local MID_RATIO=1.95
local FAR_RATIO=1.15
local MIN_SPREAD_PX=0.8
local MAX_SPREAD_PX=50

local CLOSE_SPREAD_END=40
local CLOSE_SPREAD_BONUS=0.40

local FAR_FORCE_START=60
local FAR_FORCE_END=220
local FAR_MIN_START=1.2
local FAR_MIN_END=7.5

local LEAD_TIME=0.020
local VELOCITY_SMOOTH=0.35
local MAX_LEAD_PX=22
local MOTION_FULL=700

local PULL_SPEED=16
local PULL_MAX_STEP_DEG=7
local PULL_FIRE_RADIUS=15

local Whitelist={}
local Blacklist={}

local CurrentPlayer=nil
local CurrentPart=nil
local CurrentDistance=0
local CurrentWorld=nil
local CurrentMode=nil

local ManualPlayer=nil
local LastAutoPlayer=nil
local LastAutoPosition=nil
local Memories={}
local MemorySerial=0
local Reacquire={Player=nil,Until=0}
local Motion={Player=nil,Pos=nil,Time=nil,Velocity=Vector2.zero}

local lastFire=0
local touchId=5000
local RENDER_NAME="UniversalTPS"

pcall(function() RunService:UnbindFromRenderStep(RENDER_NAME) end)
for _,n in ipairs({"UniversalTPSUI","UniversalTPSOverlay"}) do
	local o=PG:FindFirstChild(n)
	if o then o:Destroy() end
end
local oh=Workspace:FindFirstChild("UniversalTPSTargetHighlight")
if oh then oh:Destroy() end

local Gui=Instance.new("ScreenGui")
Gui.Name="UniversalTPSUI"
Gui.ResetOnSpawn=false
Gui.Parent=PG

local Overlay=Instance.new("ScreenGui")
Overlay.Name="UniversalTPSOverlay"
Overlay.ResetOnSpawn=false
Overlay.IgnoreGuiInset=true
Overlay.DisplayOrder=999
Overlay.Parent=PG

pcall(function()
	Overlay.ScreenInsets=Enum.ScreenInsets.None
	Overlay.ClipToDeviceSafeArea=false
end)

local function corner(o,r)
	local c=Instance.new("UICorner")
	c.CornerRadius=UDim.new(0,r)
	c.Parent=o
end

local function stroke(o,t)
	local s=Instance.new("UIStroke")
	s.Thickness=t or 1
	s.Parent=o
end

local function button(parent,text,pos,size)
	local b=Instance.new("TextButton")
	b.Size=size
	b.Position=pos
	b.BackgroundColor3=Color3.fromRGB(60,60,70)
	b.BorderSizePixel=0
	b.Text=text
	b.TextColor3=Color3.new(1,1,1)
	b.Font=Enum.Font.GothamBold
	b.TextSize=12
	b.Active=true
	b.Parent=parent
	corner(b,7)
	return b
end

local Main=Instance.new("Frame")
Main.Size=UDim2.fromOffset(280,420)
Main.Position=UDim2.new(0.04,0,0.12,0)
Main.BackgroundColor3=Color3.fromRGB(25,25,30)
Main.BorderSizePixel=0
Main.Active=true
Main.Parent=Gui
corner(Main,12)
stroke(Main,2)

local Title=Instance.new("TextLabel")
Title.Size=UDim2.new(1,-40,0,40)
Title.Position=UDim2.fromOffset(10,0)
Title.BackgroundTransparency=1
Title.Text="Universal TPS"
Title.TextColor3=Color3.new(1,1,1)
Title.Font=Enum.Font.GothamBold
Title.TextSize=16
Title.TextXAlignment=Enum.TextXAlignment.Left
Title.Active=true
Title.Parent=Main

local Close=button(Main,"X",UDim2.new(1,-36,0,5),UDim2.fromOffset(30,30))
local AutoBtn=button(Main,"자동사격: OFF",UDim2.fromOffset(10,45),UDim2.new(1,-20,0,36))
local TeamBtn=button(Main,"팀: ON",UDim2.fromOffset(10,87),UDim2.new(0.31,-3,0,30))
local WallBtn=button(Main,"월: ON",UDim2.new(0.34,0,0,87),UDim2.new(0.31,-3,0,30))
local DragBtn=button(Main,"드래그: OFF",UDim2.new(0.67,0,0,87),UDim2.new(0.31,-3,0,30))
local PullBtn=button(Main,"끌어치기: OFF",UDim2.fromOffset(10,123),UDim2.new(1,-20,0,30))

local function inputRow(label,y,default)
	local l=Instance.new("TextLabel")
	l.Size=UDim2.new(0.45,0,0,27)
	l.Position=UDim2.fromOffset(12,y)
	l.BackgroundTransparency=1
	l.Text=label
	l.TextColor3=Color3.new(0.9,0.9,0.9)
	l.Font=Enum.Font.Gotham
	l.TextSize=12
	l.TextXAlignment=Enum.TextXAlignment.Left
	l.Parent=Main

	local x=Instance.new("TextBox")
	x.Size=UDim2.new(0.45,0,0,26)
	x.Position=UDim2.new(0.52,0,0,y)
	x.BackgroundColor3=Color3.fromRGB(45,45,55)
	x.BorderSizePixel=0
	x.Text=tostring(default)
	x.TextColor3=Color3.new(1,1,1)
	x.Font=Enum.Font.Gotham
	x.TextSize=12
	x.ClearTextOnFocus=false
	x.Parent=Main
	corner(x,6)
	return x
end

local DelayBox=inputRow("발사 간격",162,FIRE_DELAY)
local DistanceBox=inputRow("최대 거리",194,MAX_DISTANCE)
local SpreadBox=inputRow("퍼짐 배율",226,SPREAD_MULTIPLIER)

local Status=Instance.new("TextLabel")
Status.Size=UDim2.new(1,-20,0,145)
Status.Position=UDim2.fromOffset(10,264)
Status.BackgroundColor3=Color3.fromRGB(15,15,20)
Status.BorderSizePixel=0
Status.Text="대상 탐색 중"
Status.TextColor3=Color3.fromRGB(210,210,215)
Status.Font=Enum.Font.Gotham
Status.TextSize=10
Status.TextWrapped=true
Status.TextXAlignment=Enum.TextXAlignment.Left
Status.TextYAlignment=Enum.TextYAlignment.Top
Status.Parent=Main
corner(Status,7)

local List=Instance.new("Frame")
List.Size=UDim2.fromOffset(230,250)
List.Position=UDim2.new(0.04,290,0.12,0)
List.BackgroundColor3=Color3.fromRGB(25,25,30)
List.BorderSizePixel=0
List.Active=true
List.Parent=Gui
corner(List,12)
stroke(List,2)

local ListTitle=Instance.new("TextLabel")
ListTitle.Size=UDim2.new(1,0,0,38)
ListTitle.BackgroundTransparency=1
ListTitle.Text="타겟 필터"
ListTitle.TextColor3=Color3.new(1,1,1)
ListTitle.Font=Enum.Font.GothamBold
ListTitle.TextSize=15
ListTitle.Active=true
ListTitle.Parent=List

local NameBox=Instance.new("TextBox")
NameBox.Size=UDim2.new(1,-20,0,32)
NameBox.Position=UDim2.fromOffset(10,40)
NameBox.BackgroundColor3=Color3.fromRGB(45,45,55)
NameBox.BorderSizePixel=0
NameBox.PlaceholderText="플레이어 이름"
NameBox.Text=""
NameBox.TextColor3=Color3.new(1,1,1)
NameBox.Font=Enum.Font.Gotham
NameBox.TextSize=12
NameBox.ClearTextOnFocus=false
NameBox.Parent=List
corner(NameBox,6)

local WhiteBtn=button(List,"화이트",UDim2.fromOffset(10,78),UDim2.new(0.5,-15,0,28))
local BlackBtn=button(List,"블랙",UDim2.new(0.5,5,0,78),UDim2.new(0.5,-15,0,28))
local RemoveBtn=button(List,"제거",UDim2.fromOffset(10,112),UDim2.new(1,-20,0,28))

local ListText=Instance.new("TextLabel")
ListText.Size=UDim2.new(1,-20,0,95)
ListText.Position=UDim2.fromOffset(10,146)
ListText.BackgroundColor3=Color3.fromRGB(15,15,20)
ListText.BorderSizePixel=0
ListText.Text=""
ListText.TextColor3=Color3.new(0.85,0.85,0.85)
ListText.Font=Enum.Font.Gotham
ListText.TextSize=10
ListText.TextWrapped=true
ListText.TextXAlignment=Enum.TextXAlignment.Left
ListText.TextYAlignment=Enum.TextYAlignment.Top
ListText.Parent=List
corner(ListText,6)

local FireBtn=button(Gui,"FIRE",UDim2.new(0.80,-37,0.66,-37),UDim2.fromOffset(75,75))
FireBtn.Name="MobileFireBtn"
FireBtn.BackgroundColor3=Color3.fromRGB(220,50,50)
FireBtn.TextSize=16
local fc=FireBtn:FindFirstChildOfClass("UICorner")
if fc then fc.CornerRadius=UDim.new(1,0) end
stroke(FireBtn,3)

local LockBtn=button(Gui,"🎯",UDim2.new(0.80,-105,0.66,-25),UDim2.fromOffset(52,52))
LockBtn.Name="KillLockBtn"
LockBtn.TextSize=25
corner(LockBtn,13)
stroke(LockBtn,2)

local Aim=Instance.new("Frame")
Aim.Size=UDim2.fromOffset(18,18)
Aim.AnchorPoint=Vector2.new(0.5,0.5)
Aim.BackgroundColor3=Color3.fromRGB(40,255,100)
Aim.BorderSizePixel=0
Aim.Visible=false
Aim.ZIndex=100
Aim.Parent=Overlay
corner(Aim,9)

local Center=Instance.new("Frame")
Center.Size=UDim2.fromOffset(10,10)
Center.AnchorPoint=Vector2.new(0.5,0.5)
Center.BackgroundColor3=Color3.fromRGB(255,210,45)
Center.BorderSizePixel=0
Center.Visible=false
Center.ZIndex=101
Center.Parent=Overlay
corner(Center,5)

local Highlight=Instance.new("Highlight")
Highlight.Name="UniversalTPSTargetHighlight"
Highlight.Enabled=false
Highlight.DepthMode=Enum.HighlightDepthMode.Occluded
Highlight.FillTransparency=0.82
Highlight.OutlineTransparency=0
Highlight.Parent=Workspace

local function draggable(frame,handle)
	handle=handle or frame
	local dragging=false
	local startPos
	local startInput
	local active

	handle.InputBegan:Connect(function(i)
		if i.UserInputType~=Enum.UserInputType.Touch and i.UserInputType~=Enum.UserInputType.MouseButton1 then return end
		if (frame==FireBtn or frame==LockBtn) and not DRAG_MODE then return end
		dragging=true
		active=i
		startInput=Vector2.new(i.Position.X,i.Position.Y)
		startPos=frame.Position
	end)

	UIS.InputChanged:Connect(function(i)
		if not dragging then return end
		if i~=active and i.UserInputType~=Enum.UserInputType.Touch and i.UserInputType~=Enum.UserInputType.MouseMovement then return end
		local p=Vector2.new(i.Position.X,i.Position.Y)
		local d=p-startInput
		frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
	end)

	UIS.InputEnded:Connect(function(i)
		if i==active then
			dragging=false
			active=nil
		end
	end)
end

draggable(Main,Title)
draggable(List,ListTitle)
draggable(FireBtn)
draggable(LockBtn)

local function resetMotion()
	Motion.Player=nil
	Motion.Pos=nil
	Motion.Time=nil
	Motion.Velocity=Vector2.zero
end

local function alive(p)
	local c=p and p.Character
	local h=c and c:FindFirstChildOfClass("Humanoid")
	return h and h.Health>0
end

local function transparent(p)
	local c=p and p.Character
	if not c then return true end

	local total=0
	local inv=0

	for _,v in ipairs(c:GetChildren()) do
		if v:IsA("BasePart") and v.Name~="HumanoidRootPart" then
			total+=1
			local t=1-(1-math.clamp(v.Transparency,0,1))*(1-math.clamp(v.LocalTransparencyModifier,0,1))
			if t>=TRANSPARENCY_LIMIT then inv+=1 end
		end
	end

	return total>0 and inv/total>=TRANSPARENT_RATIO
end

local function eligible(p)
	if not p or p==LP then return false end
	if Whitelist[p.Name] then return false end
	if TEAM_CHECK and LP.Team~=nil and p.Team==LP.Team then return false end
	if not alive(p) then return false end
	if transparent(p) then return false end
	return true
end

local function aimPart(c)
	return c and (
		c:FindFirstChild("UpperTorso")
		or c:FindFirstChild("Torso")
		or c:FindFirstChild("HumanoidRootPart")
		or c:FindFirstChild("Head")
	)
end

local function origin()
	local c=LP.Character
	local r=c and c:FindFirstChild("HumanoidRootPart")
	return r and r.Position or nil
end

local function viewport(world)
	Camera=Workspace.CurrentCamera
	if not Camera then return nil,false end
	local p,v=Camera:WorldToViewportPoint(world)
	if p.Z<=0 then return nil,false end
	return Vector2.new(p.X,p.Y),v
end

local function screen(world)
	Camera=Workspace.CurrentCamera
	if not Camera then return nil,false end
	local p,v=Camera:WorldToScreenPoint(world)
	if p.Z<=0 then return nil,false end
	return Vector2.new(p.X,p.Y),v
end

local function onScreen(world)
	Camera=Workspace.CurrentCamera
	if not Camera then return false end
	local p,v=Camera:WorldToViewportPoint(world)
	return v and p.Z>0 and p.X>=0 and p.Y>=0 and p.X<=Camera.ViewportSize.X and p.Y<=Camera.ViewportSize.Y
end

local function los(player,part)
	if not WALL_CHECK then return true end
	Camera=Workspace.CurrentCamera
	if not Camera or not player or not player.Character or not part then return false end

	local dir=part.Position-Camera.CFrame.Position
	if dir.Magnitude<0.01 then return true end

	local rp=RaycastParams.new()
	rp.FilterType=Enum.RaycastFilterType.Exclude
	rp.IgnoreWater=true
	rp.FilterDescendantsInstances=LP.Character and {LP.Character} or {}

	local hit=Workspace:Raycast(Camera.CFrame.Position,dir,rp)
	return not hit or (hit.Instance and hit.Instance:IsDescendantOf(player.Character))
end

local function visible(player,part)
	return eligible(player) and part and onScreen(part.Position) and los(player,part)
end

local function remember(player,pos)
	if not player or not pos or not eligible(player) then return end
	MemorySerial+=1
	Memories[player]={Position=pos,Expires=os.clock()+MEMORY_TIME,Serial=MemorySerial}
end

local function clearManual()
	ManualPlayer=nil
	LockBtn.BackgroundColor3=Color3.fromRGB(60,60,70)
end

local function cleanupMemory()
	local now=os.clock()
	for p,m in pairs(Memories) do
		if not eligible(p) or m.Expires<=now then
			Memories[p]=nil
			if Reacquire.Player==p then
				Reacquire.Player=nil
				Reacquire.Until=0
			end
		end
	end
	if ManualPlayer and not eligible(ManualPlayer) then clearManual() end
end

local function data(player,part,org,pos,mode,vis)
	return {
		Player=player,
		Character=player.Character,
		Part=part,
		Distance=(pos-org).Magnitude,
		Position=pos,
		Mode=mode,
		Visible=vis
	}
end

local function updateLastAuto()
	if not LastAutoPlayer then return end
	local p=LastAutoPlayer
	if not eligible(p) then
		LastAutoPlayer=nil
		LastAutoPosition=nil
		return
	end
	local part=aimPart(p.Character)
	if not part then
		LastAutoPlayer=nil
		LastAutoPosition=nil
		return
	end
	if visible(p,part) then
		LastAutoPosition=part.Position
	else
		if LastAutoPosition then remember(p,LastAutoPosition) end
		LastAutoPlayer=nil
		LastAutoPosition=nil
	end
end

local function bestVisible(org)
	Camera=Workspace.CurrentCamera
	if not Camera then return nil end
	local center=Camera.ViewportSize*0.5
	local normal,black=nil,nil
	local ns,bs=math.huge,math.huge

	for _,p in ipairs(Players:GetPlayers()) do
		if eligible(p) then
			local part=aimPart(p.Character)
			if part then
				local dist=(part.Position-org).Magnitude
				if dist<=MAX_DISTANCE and visible(p,part) then
					local vp=viewport(part.Position)
					if vp then
						local score=(vp-center).Magnitude
						local d=data(p,part,org,part.Position,"NORMAL",true)
						if Blacklist[p.Name] then
							if score<bs then bs=score black=d end
						elseif score<ns then
							ns=score normal=d
						end
					end
				end
			end
		end
	end

	return black or normal
end

local function reacquired(org)
	if not Reacquire.Player then return nil end
	if os.clock()>Reacquire.Until then
		Reacquire.Player=nil
		return nil
	end

	local p=Reacquire.Player
	if not eligible(p) then Reacquire.Player=nil return nil end
	local part=aimPart(p.Character)
	if not part or not visible(p,part) or (part.Position-org).Magnitude>MAX_DISTANCE then
		Reacquire.Player=nil
		return nil
	end
	return data(p,part,org,part.Position,"REACQUIRE",true)
end

local function reappeared(org)
	cleanupMemory()
	local best=nil
	local serial=-1

	for p,m in pairs(Memories) do
		if eligible(p) then
			local part=aimPart(p.Character)
			if part and (part.Position-org).Magnitude<=MAX_DISTANCE and visible(p,part) and m.Serial>serial then
				best=data(p,part,org,part.Position,"REAPPEAR",true)
				serial=m.Serial
			end
		end
	end

	if best then
		Memories[best.Player]=nil
		Reacquire.Player=best.Player
		Reacquire.Until=os.clock()+REACQUIRE_HOLD
	end

	return best
end

local function latestMemory(org)
	local bp,bm=nil,nil
	local serial=-1
	for p,m in pairs(Memories) do
		if eligible(p) and m.Serial>serial and (m.Position-org).Magnitude<=MAX_DISTANCE then
			bp,bm,serial=p,m,m.Serial
		end
	end
	if not bp then return nil end
	local part=aimPart(bp.Character)
	return part and data(bp,part,org,bm.Position,"LAST",false) or nil
end

local function manualTarget(org)
	if not ManualPlayer then return nil end
	local p=ManualPlayer
	local part=eligible(p) and aimPart(p.Character) or nil
	if not part or not visible(p,part) or (part.Position-org).Magnitude>MAX_DISTANCE then
		clearManual()
		return nil
	end
	return data(p,part,org,part.Position,"MANUAL",true)
end

local function currentTarget(org)
	if ManualPlayer then
		local m=manualTarget(org)
		if m then return m end
	end

	updateLastAuto()
	cleanupMemory()

	local r=reacquired(org)
	if r then
		LastAutoPlayer=r.Player
		LastAutoPosition=r.Position
		return r
	end

	local rr=reappeared(org)
	if rr then
		LastAutoPlayer=rr.Player
		LastAutoPosition=rr.Position
		return rr
	end

	local n=bestVisible(org)
	if n then
		LastAutoPlayer=n.Player
		LastAutoPosition=n.Position
		return n
	end

	LastAutoPlayer=nil
	LastAutoPosition=nil
	return latestMemory(org)
end

local function updateHighlight(d)
	if not d or not d.Character or transparent(d.Player) then
		Highlight.Enabled=false
		Highlight.Adornee=nil
		return
	end

	Highlight.Enabled=true
	Highlight.Adornee=d.Character

	if d.Mode=="MANUAL" then
		Highlight.FillColor=Color3.fromRGB(255,40,40)
		Highlight.OutlineColor=Color3.fromRGB(255,220,220)
	elseif d.Mode=="LAST" then
		Highlight.FillColor=Color3.fromRGB(255,170,35)
		Highlight.OutlineColor=Color3.fromRGB(255,220,130)
	elseif d.Mode=="REAPPEAR" or d.Mode=="REACQUIRE" then
		Highlight.FillColor=Color3.fromRGB(50,180,255)
		Highlight.OutlineColor=Color3.fromRGB(210,240,255)
	else
		Highlight.FillColor=Color3.fromRGB(40,255,100)
		Highlight.OutlineColor=Color3.new(1,1,1)
	end
end

local function updateVelocity(p,pos)
	local now=os.clock()
	if Motion.Player~=p then
		Motion.Player=p
		Motion.Pos=pos
		Motion.Time=now
		Motion.Velocity=Vector2.zero
		return
	end
	if Motion.Pos and Motion.Time then
		local dt=now-Motion.Time
		if dt>0.001 and dt<0.1 then
			local v=(pos-Motion.Pos)/dt
			if v.Magnitude>4500 then v=v.Unit*4500 end
			Motion.Velocity=Motion.Velocity:Lerp(v,VELOCITY_SMOOTH)
		end
	end
	Motion.Pos=pos
	Motion.Time=now
end

local function lead()
	local l=Motion.Velocity*LEAD_TIME
	if l.Magnitude>MAX_LEAD_PX then l=l.Unit*MAX_LEAD_PX end
	return l
end

local function gaussian()
	local u1=math.max(math.random(),0.000001)
	local u2=math.random()
	return math.sqrt(-2*math.log(u1))*math.cos(2*math.pi*u2)
end

local function screenRadius(character)
	Camera=Workspace.CurrentCamera
	if not Camera or not character then return 4 end
	local ok,cf,size=pcall(function()
		local a,b=character:GetBoundingBox()
		return a,b
	end)
	if not ok then return 4 end

	local c=Camera:WorldToScreenPoint(cf.Position)
	if c.Z<=0 then return 4 end

	local hp=Camera:WorldToScreenPoint(cf.Position+Camera.CFrame.RightVector*math.max(size.X,size.Z)*0.5)
	local vp=Camera:WorldToScreenPoint(cf.Position+Camera.CFrame.UpVector*size.Y*0.5)

	return math.max(1.5,math.min(math.abs(hp.X-c.X),math.abs(vp.Y-c.Y)))
end

local function spread(character,distance)
	if SPREAD_MULTIPLIER<=0 then return 0 end

	local ratio
	if distance<=MID_DISTANCE then
		local t=math.clamp((distance-NEAR_DISTANCE)/math.max(1,MID_DISTANCE-NEAR_DISTANCE),0,1)^0.8
		ratio=NEAR_RATIO+(MID_RATIO-NEAR_RATIO)*t
	else
		local t=math.clamp((distance-MID_DISTANCE)/math.max(1,FAR_DISTANCE-MID_DISTANCE),0,1)^0.8
		ratio=MID_RATIO+(FAR_RATIO-MID_RATIO)*t
	end

	local sigma=screenRadius(character)*ratio

	local closeT=1-math.clamp(distance/CLOSE_SPREAD_END,0,1)
	sigma=sigma*(1+CLOSE_SPREAD_BONUS*closeT)

	local ft=math.clamp((distance-FAR_FORCE_START)/math.max(1,FAR_FORCE_END-FAR_FORCE_START),0,1)
	local forced=FAR_MIN_START+(FAR_MIN_END-FAR_MIN_START)*ft
	sigma=math.max(sigma,forced)

	sigma=sigma*SPREAD_MULTIPLIER

	return math.clamp(
		sigma,
		MIN_SPREAD_PX*SPREAD_MULTIPLIER,
		MAX_SPREAD_PX*SPREAD_MULTIPLIER
	)
end

local CoordinateState={
	ScreenOffset=Vector2.zero,
	ViewportOffset=Vector2.zero
}

local function refreshCoordinateOffsets()
	local screenOffset=nil
	local viewportOffset=nil

	local okNone,noneRect=pcall(function()
		return GuiService:GetInsetArea(Enum.ScreenInsets.None)
	end)

	if okNone and typeof(noneRect)=="Rect" then
		screenOffset=Vector2.new(
			-noneRect.Min.X,
			-noneRect.Min.Y
		)

		local okDevice,deviceRect=pcall(function()
			return GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets)
		end)

		if okDevice and typeof(deviceRect)=="Rect" then
			viewportOffset=Vector2.new(
				deviceRect.Min.X-noneRect.Min.X,
				deviceRect.Min.Y-noneRect.Min.Y
			)
		end
	end

	if not screenOffset then
		local fallback=Vector2.zero

		pcall(function()
			local tl=select(1,GuiService:GetGuiInset())
			if typeof(tl)=="Vector2" then
				fallback=tl
			end
		end)

		screenOffset=fallback
	end

	if not viewportOffset then
		viewportOffset=screenOffset
	end

	CoordinateState.ScreenOffset=screenOffset
	CoordinateState.ViewportOffset=viewportOffset
end

local function screenToFull(p)
	local o=CoordinateState.ScreenOffset
	return Vector2.new(
		p.X+o.X,
		p.Y+o.Y
	)
end

local function viewportToFull(p)
	local o=CoordinateState.ViewportOffset
	return Vector2.new(
		p.X+o.X,
		p.Y+o.Y
	)
end

local function toVIM(p)
	return screenToFull(p)
end

local function viewportToVIM(p)
	return viewportToFull(p)
end

local function fireAt(point,character,distance)
	local s=spread(character,distance)
	local p=Vector2.new(point.X+gaussian()*s,point.Y+gaussian()*s)
	touchId+=1
	if touchId>2000000000 then touchId=5000 end
	local x=math.floor(p.X+0.5)
	local y=math.floor(p.Y+0.5)
	local id=touchId

	local ok=pcall(function()
		VIM:SendTouchEvent(id,Enum.UserInputState.Begin.Value,x,y)
		task.delay(0.018,function()
			pcall(function()
				VIM:SendTouchEvent(id,Enum.UserInputState.End.Value,x,y)
			end)
		end)
	end)
	return ok
end

local function rotateTo(world,dt)
	Camera=Workspace.CurrentCamera
	if not Camera then return end

	local pos=Camera.CFrame.Position
	local delta=world-pos
	if delta.Magnitude<0.001 then return end

	local a=Camera.CFrame.LookVector.Unit
	local b=delta.Unit
	local angle=math.acos(math.clamp(a:Dot(b),-1,1))
	if angle<0.0001 then return end

	local step=math.min(angle,math.rad(PULL_MAX_STEP_DEG),PULL_SPEED*math.max(dt,0))
	local look=a:Lerp(b,math.clamp(step/angle,0,1))
	if look.Magnitude<0.001 then return end

	Camera.CFrame=CFrame.lookAt(pos,pos+look.Unit,Vector3.yAxis)
end

local function playerFromText(t)
	t=string.lower(t or "")
	if t=="" then return nil end
	for _,p in ipairs(Players:GetPlayers()) do
		if string.lower(p.Name):sub(1,#t)==t or string.lower(p.DisplayName):sub(1,#t)==t then
			return p
		end
	end
end

local function refreshList()
	local w,b="화이트\n","블랙\n"
	local wc,bc=0,0
	for n in pairs(Whitelist) do w..=n.."\n" wc+=1 end
	for n in pairs(Blacklist) do b..=n.."\n" bc+=1 end
	if wc==0 then w..="없음\n" end
	if bc==0 then b..="없음\n" end
	ListText.Text=w.."\n"..b
end
refreshList()

WhiteBtn.MouseButton1Click:Connect(function()
	local p=playerFromText(NameBox.Text)
	if not p then return end
	Whitelist[p.Name]=true
	Blacklist[p.Name]=nil
	Memories[p]=nil
	if ManualPlayer==p then clearManual() end
	NameBox.Text=""
	refreshList()
end)

BlackBtn.MouseButton1Click:Connect(function()
	local p=playerFromText(NameBox.Text)
	if not p then return end
	Blacklist[p.Name]=true
	Whitelist[p.Name]=nil
	NameBox.Text=""
	refreshList()
end)

RemoveBtn.MouseButton1Click:Connect(function()
	local p=playerFromText(NameBox.Text)
	if not p then return end
	Whitelist[p.Name]=nil
	Blacklist[p.Name]=nil
	NameBox.Text=""
	refreshList()
end)

AutoBtn.MouseButton1Click:Connect(function()
	AUTO_FIRE=not AUTO_FIRE
	AutoBtn.Text=AUTO_FIRE and "자동사격: ON" or "자동사격: OFF"
end)

TeamBtn.MouseButton1Click:Connect(function()
	TEAM_CHECK=not TEAM_CHECK
	TeamBtn.Text=TEAM_CHECK and "팀: ON" or "팀: OFF"
end)

WallBtn.MouseButton1Click:Connect(function()
	WALL_CHECK=not WALL_CHECK
	WallBtn.Text=WALL_CHECK and "월: ON" or "월: OFF"
end)

DragBtn.MouseButton1Click:Connect(function()
	DRAG_MODE=not DRAG_MODE
	if DRAG_MODE then HOLD_FIRE=false end
	DragBtn.Text=DRAG_MODE and "드래그: ON" or "드래그: OFF"
end)

PullBtn.MouseButton1Click:Connect(function()
	PULL_AIM=not PULL_AIM
	PullBtn.Text=PULL_AIM and "끌어치기: ON" or "끌어치기: OFF"
	Center.Visible=PULL_AIM
	resetMotion()
end)

LockBtn.MouseButton1Click:Connect(function()
	if DRAG_MODE then return end
	if ManualPlayer then
		clearManual()
		return
	end
	if CurrentPlayer and CurrentPart and visible(CurrentPlayer,CurrentPart) then
		ManualPlayer=CurrentPlayer
		Reacquire.Player=nil
		LastAutoPlayer=nil
		LastAutoPosition=nil
		LockBtn.BackgroundColor3=Color3.fromRGB(215,45,45)
	end
end)

DelayBox.FocusLost:Connect(function()
	FIRE_DELAY=math.max(0.01,tonumber(DelayBox.Text) or FIRE_DELAY)
	DelayBox.Text=tostring(FIRE_DELAY)
end)

DistanceBox.FocusLost:Connect(function()
	MAX_DISTANCE=math.max(1,tonumber(DistanceBox.Text) or MAX_DISTANCE)
	DistanceBox.Text=tostring(MAX_DISTANCE)
end)

SpreadBox.FocusLost:Connect(function()
	SPREAD_MULTIPLIER=math.clamp(tonumber(SpreadBox.Text) or SPREAD_MULTIPLIER,0,3)
	SpreadBox.Text=tostring(SPREAD_MULTIPLIER)
end)

FireBtn.InputBegan:Connect(function(i)
	if DRAG_MODE then return end
	if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then
		HOLD_FIRE=true
	end
end)

FireBtn.InputEnded:Connect(function(i)
	if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then
		HOLD_FIRE=false
	end
end)

Close.MouseButton1Click:Connect(function()
	AUTO_FIRE=false
	HOLD_FIRE=false
	pcall(function() RunService:UnbindFromRenderStep(RENDER_NAME) end)
	Highlight:Destroy()
	Overlay:Destroy()
	Gui:Destroy()
end)

RunService:BindToRenderStep(RENDER_NAME,Enum.RenderPriority.Camera.Value+2,function(dt)
	Camera=Workspace.CurrentCamera
	if not Camera or not Gui.Parent then return end

	cleanupMemory()
	refreshCoordinateOffsets()

	local center=Camera.ViewportSize*0.5
	local centerFull=viewportToFull(center)
	Center.Position=UDim2.fromOffset(centerFull.X,centerFull.Y)
	Center.Visible=PULL_AIM

	local org=origin()
	if not org then
		Highlight.Enabled=false
		Aim.Visible=false
		resetMotion()
		return
	end

	local d=currentTarget(org)
	if not d then
		CurrentPlayer=nil
		CurrentPart=nil
		CurrentWorld=nil
		CurrentMode=nil
		Highlight.Enabled=false
		Aim.Visible=false
		Status.Text="화면 안 타겟 없음"
		resetMotion()
		return
	end

	CurrentPlayer=d.Player
	CurrentPart=d.Part
	CurrentDistance=d.Distance
	CurrentWorld=d.Position
	CurrentMode=d.Mode

	updateHighlight(d)

	local sp,on=screen(CurrentWorld)
	if sp and on then
		local overlayPoint=screenToFull(sp)
		Aim.Visible=true
		Aim.Position=UDim2.fromOffset(overlayPoint.X,overlayPoint.Y)
	else
		Aim.Visible=false
	end

	if d.Visible and sp then updateVelocity(CurrentPlayer,sp) else resetMotion() end

	if PULL_AIM then
		rotateTo(CurrentWorld,dt)
	end

	local mode=CurrentMode
	if mode=="NORMAL" then mode="중앙 최근접"
	elseif mode=="MANUAL" then mode="🎯 수동고정"
	elseif mode=="LAST" then mode="마지막 위치"
	elseif mode=="REAPPEAR" or mode=="REACQUIRE" then mode="재등장 우선"
	end

	Status.Text=string.format(
		"타겟: %s | %.1f\n모드: %s\n월체크: %s | 실제보임: %s\n퍼짐: %.2fpx | 배율 %.2f\n투명 관전자 제외: ON\n끌어치기: %s",
		CurrentPlayer.Name,
		CurrentDistance,
		mode,
		WALL_CHECK and "ON" or "OFF",
		d.Visible and "YES" or "NO",
		spread(CurrentPlayer.Character,CurrentDistance),
		SPREAD_MULTIPLIER,
		PULL_AIM and "ON" or "OFF"
	)

	if not (AUTO_FIRE or HOLD_FIRE) then return end
	if transparent(CurrentPlayer) then return end
	if os.clock()-lastFire<FIRE_DELAY then return end

	local final,ons=screen(CurrentWorld)
	if not final or not ons then return end

	local point
	if PULL_AIM then
		local vp=viewport(CurrentWorld)
		if not vp or (vp-center).Magnitude>PULL_FIRE_RADIUS then return end
		point=viewportToVIM(center)
	else
		local predicted=final
		if d.Visible then predicted+=lead() end
		point=toVIM(predicted)
	end

	if fireAt(point,CurrentPlayer.Character,CurrentDistance) then
		lastFire=os.clock()
	end
end)

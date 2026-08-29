local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = Workspace.CurrentCamera

local FireEvent = ReplicatedStorage:WaitForChild("발사S")

local AUTO_FIRE = false

local PROJECTILE_SPEED = 750
local FIRE_DELAY = 0.15
local MAX_DISTANCE = 500
local GUN2A_SPREAD = 1.5

local GUN2A_PROJECTILE_SPEED = 350
local NETWORK_LEAD = 0.08

local TEAM_CHECK = true
local WALL_CHECK = true
local SAFE_ZONE_CHECK = true
local SAFE_ZONE_VISIBLE = false

local INPUT_LEAD_TIME = 0.020
local VELOCITY_SMOOTH = 0.35
local MAX_LEAD_PX = 22

local NEAR_DISTANCE = 15
local FAR_DISTANCE = 200
local NEAR_SPREAD_RATIO = 0.40
local FAR_SPREAD_RATIO = 1.15
local MIN_SPREAD_PX = 0.65
local MAX_SPREAD_PX = 16
local FAR_FORCE_START = 60
local FAR_FORCE_END = 220
local FAR_MIN_SPREAD_START = 1.2
local FAR_MIN_SPREAD_END = 7.5
local MOTION_SPEED_FULL = 700
local MOTION_SPREAD_REDUCTION = 0.45

local Whitelist = {}
local Blacklist = {}

local lastFireTime = 0

local CurrentTargetPlayer = nil
local CurrentTargetCharacter = nil
local CurrentTargetPart = nil
local CurrentTargetDistance = nil
local CurrentScreenDistance = nil

local TargetHighlight = nil

local TouchHolding = false
local HoldTouchId = nil
local LastTouchPosition = nil
local HoldSpreadOffset = Vector2.zero
local LastSpreadUpdate = 0
local NextTouchId = 5000

local Motion = {
	Player = nil,
	LastPosition = nil,
	LastTime = nil,
	Velocity = Vector2.zero
}

local LOCAL_SAFE_ZONES = {
	{ Center = Vector3.new(70.0, 70.5, 125.3), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(65.3, 65.3, 136.9), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(62.9, 65.3, 117.9), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(64.2, 65.3, 95.6), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(80.0, 65.3, 84.1), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(64.9, 65.2, 68.9), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(64.3, 65.2, 52.4), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(44.2, 65.2, 51.0), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(19.4, 65.2, 52.7), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(42.2, 65.2, 78.6), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(15.1, 65.2, 79.6), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(-8.1, 65.2, 77.9), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(-12.0, 65.2, 84.3), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(-10.0, 65.2, 64.5), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(-15.7, 65.2, 44.4), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(4.4, 63.4, 41.3), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(39.2, 65.2, 89.4), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(14.9, 65.2, 85.6), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(-19.7, 34.6, 107.1), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(20.1, 32.0, 98.7), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(65.7, 3.6, 153.4), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(64.4, 3.6, 156.6), Size = Vector3.new(30.0, 10.0, 30.0) },
	{ Center = Vector3.new(60.4, 3.6, 152.4), Size = Vector3.new(30.0, 10.0, 30.0) },
}

local oldGui = PlayerGui:FindFirstChild("CyborgAutoFireUI")
if oldGui then
	oldGui:Destroy()
end

for _, object in ipairs(Workspace:GetChildren()) do
	if object:IsA("BasePart") and object.Name == "VisualSafeZonePart" then
		object:Destroy()
	end
end

for _, object in ipairs(Workspace:GetDescendants()) do
	if object:IsA("Highlight") and object.Name == "CyborgTargetHighlight" then
		object:Destroy()
	end
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CyborgAutoFireUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = false
ScreenGui.Parent = PlayerGui

local InsetProbe = Instance.new("Frame")
InsetProbe.Size = UDim2.fromOffset(1, 1)
InsetProbe.Position = UDim2.fromOffset(0, 0)
InsetProbe.BackgroundTransparency = 1
InsetProbe.BorderSizePixel = 0
InsetProbe.Active = false
InsetProbe.Parent = ScreenGui

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.fromOffset(270, 370)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -185)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(70, 150, 255)
MainStroke.Thickness = 2
MainStroke.Parent = MainFrame

local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 42)
TitleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
TitleBar.BorderSizePixel = 0
TitleBar.Active = true
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 12)
TitleCorner.Parent = TitleBar

local TitleFix = Instance.new("Frame")
TitleFix.Size = UDim2.new(1, 0, 0, 12)
TitleFix.Position = UDim2.new(0, 0, 1, -12)
TitleFix.BackgroundColor3 = TitleBar.BackgroundColor3
TitleFix.BorderSizePixel = 0
TitleFix.Parent = TitleBar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -50, 1, 0)
Title.Position = UDim2.fromOffset(14, 0)
Title.BackgroundTransparency = 1
Title.Text = "사이보그 예측 자동사격"
Title.TextColor3 = Color3.fromRGB(240, 240, 245)
Title.TextSize = 17
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TitleBar

local CloseButton = Instance.new("TextButton")
CloseButton.Size = UDim2.fromOffset(34, 30)
CloseButton.Position = UDim2.new(1, -39, 0, 6)
CloseButton.BackgroundColor3 = Color3.fromRGB(180, 55, 55)
CloseButton.Text = "X"
CloseButton.TextColor3 = Color3.new(1, 1, 1)
CloseButton.TextSize = 15
CloseButton.Font = Enum.Font.GothamBold
CloseButton.Parent = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 7)
CloseCorner.Parent = CloseButton

local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(1, -24, 0, 42)
ToggleButton.Position = UDim2.fromOffset(12, 50)
ToggleButton.BackgroundColor3 = Color3.fromRGB(165, 55, 55)
ToggleButton.Text = "자동사격: 꺼짐"
ToggleButton.TextColor3 = Color3.new(1, 1, 1)
ToggleButton.TextSize = 16
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.Parent = MainFrame

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 10)
ToggleCorner.Parent = ToggleButton

local VisibleButton = Instance.new("TextButton")
VisibleButton.Size = UDim2.new(1, -24, 0, 32)
VisibleButton.Position = UDim2.fromOffset(12, 98)
VisibleButton.BackgroundColor3 = Color3.fromRGB(85, 85, 95)
VisibleButton.Text = "세이프존 보기: 꺼짐"
VisibleButton.TextColor3 = Color3.new(1, 1, 1)
VisibleButton.TextSize = 13
VisibleButton.Font = Enum.Font.GothamBold
VisibleButton.Parent = MainFrame

local VisibleCorner = Instance.new("UICorner")
VisibleCorner.CornerRadius = UDim.new(0, 8)
VisibleCorner.Parent = VisibleButton

local function createInput(labelText, defaultText, yPosition, parentFrame)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.45, 0, 0, 32)
	label.Position = UDim2.fromOffset(14, yPosition)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(220, 220, 225)
	label.TextSize = 13
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parentFrame

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0.45, 0, 0, 28)
	box.Position = UDim2.new(0.52, 0, 0, yPosition + 2)
	box.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	box.Text = defaultText
	box.PlaceholderText = defaultText
	box.TextColor3 = Color3.new(1, 1, 1)
	box.TextSize = 13
	box.Font = Enum.Font.Gotham
	box.ClearTextOnFocus = false
	box.Parent = parentFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = box

	return box
end

local SpeedBox = createInput("탄속", tostring(PROJECTILE_SPEED), 136, MainFrame)
local DelayBox = createInput("발사 간격", tostring(FIRE_DELAY), 170, MainFrame)
local DistanceBox = createInput("최대 거리", tostring(MAX_DISTANCE), 204, MainFrame)
local SpreadBox = createInput("Gun2-A 퍼짐 배율", tostring(GUN2A_SPREAD), 238, MainFrame)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -24, 0, 38)
StatusLabel.Position = UDim2.fromOffset(12, 280)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "대상 탐색 중"
StatusLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
StatusLabel.TextSize = 13
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextWrapped = true
StatusLabel.Parent = MainFrame

local ListFrame = Instance.new("Frame")
ListFrame.Name = "ListFrame"
ListFrame.Size = UDim2.fromOffset(240, 370)
ListFrame.Position = UDim2.new(0.5, 20, 0.5, -185)
ListFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
ListFrame.BorderSizePixel = 0
ListFrame.Active = true
ListFrame.Parent = ScreenGui

local ListCorner = Instance.new("UICorner")
ListCorner.CornerRadius = UDim.new(0, 12)
ListCorner.Parent = ListFrame

local ListStroke = Instance.new("UIStroke")
ListStroke.Color = Color3.fromRGB(180, 70, 255)
ListStroke.Thickness = 2
ListStroke.Parent = ListFrame

local ListTitleBar = Instance.new("Frame")
ListTitleBar.Size = UDim2.new(1, 0, 0, 42)
ListTitleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
ListTitleBar.BorderSizePixel = 0
ListTitleBar.Active = true
ListTitleBar.Parent = ListFrame

local ListTitleCorner = Instance.new("UICorner")
ListTitleCorner.CornerRadius = UDim.new(0, 12)
ListTitleCorner.Parent = ListTitleBar

local ListTitleFix = Instance.new("Frame")
ListTitleFix.Size = UDim2.new(1, 0, 0, 12)
ListTitleFix.Position = UDim2.new(0, 0, 1, -12)
ListTitleFix.BackgroundColor3 = ListTitleBar.BackgroundColor3
ListTitleFix.BorderSizePixel = 0
ListTitleFix.Parent = ListTitleBar

local ListTitle = Instance.new("TextLabel")
ListTitle.Size = UDim2.new(1, -20, 1, 0)
ListTitle.Position = UDim2.fromOffset(14, 0)
ListTitle.BackgroundTransparency = 1
ListTitle.Text = "타겟 필터 설정"
ListTitle.TextColor3 = Color3.fromRGB(240, 240, 245)
ListTitle.TextSize = 16
ListTitle.Font = Enum.Font.GothamBold
ListTitle.TextXAlignment = Enum.TextXAlignment.Left
ListTitle.Parent = ListTitleBar

local NameInput = Instance.new("TextBox")
NameInput.Size = UDim2.new(1, -24, 0, 34)
NameInput.Position = UDim2.fromOffset(12, 50)
NameInput.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
NameInput.Text = ""
NameInput.PlaceholderText = "플레이어 이름 입력..."
NameInput.TextColor3 = Color3.new(1, 1, 1)
NameInput.TextSize = 13
NameInput.Font = Enum.Font.Gotham
NameInput.ClearTextOnFocus = false
NameInput.Parent = ListFrame

local NameInputCorner = Instance.new("UICorner")
NameInputCorner.CornerRadius = UDim.new(0, 8)
NameInputCorner.Parent = NameInput

local AddWhiteBtn = Instance.new("TextButton")
AddWhiteBtn.Size = UDim2.new(0.5, -14, 0, 32)
AddWhiteBtn.Position = UDim2.fromOffset(12, 90)
AddWhiteBtn.BackgroundColor3 = Color3.fromRGB(45, 120, 60)
AddWhiteBtn.Text = "🟢 화이트"
AddWhiteBtn.TextColor3 = Color3.new(1, 1, 1)
AddWhiteBtn.TextSize = 13
AddWhiteBtn.Font = Enum.Font.GothamBold
AddWhiteBtn.Parent = ListFrame

local AddWhiteCorner = Instance.new("UICorner")
AddWhiteCorner.CornerRadius = UDim.new(0, 6)
AddWhiteCorner.Parent = AddWhiteBtn

local AddBlackBtn = Instance.new("TextButton")
AddBlackBtn.Size = UDim2.new(0.5, -14, 0, 32)
AddBlackBtn.Position = UDim2.new(0.5, 2, 0, 90)
AddBlackBtn.BackgroundColor3 = Color3.fromRGB(165, 55, 55)
AddBlackBtn.Text = "🔴 블랙"
AddBlackBtn.TextColor3 = Color3.new(1, 1, 1)
AddBlackBtn.TextSize = 13
AddBlackBtn.Font = Enum.Font.GothamBold
AddBlackBtn.Parent = ListFrame

local AddBlackCorner = Instance.new("UICorner")
AddBlackCorner.CornerRadius = UDim.new(0, 6)
AddBlackCorner.Parent = AddBlackBtn

local RemoveBtn = Instance.new("TextButton")
RemoveBtn.Size = UDim2.new(1, -24, 0, 30)
RemoveBtn.Position = UDim2.fromOffset(12, 126)
RemoveBtn.BackgroundColor3 = Color3.fromRGB(85, 85, 95)
RemoveBtn.Text = "⚪ 타겟 해제/제거"
RemoveBtn.TextColor3 = Color3.new(1, 1, 1)
RemoveBtn.TextSize = 13
RemoveBtn.Font = Enum.Font.GothamBold
RemoveBtn.Parent = ListFrame

local RemoveCorner = Instance.new("UICorner")
RemoveCorner.CornerRadius = UDim.new(0, 6)
RemoveCorner.Parent = RemoveBtn

local ListDisplay = Instance.new("TextLabel")
ListDisplay.Size = UDim2.new(1, -24, 0, 196)
ListDisplay.Position = UDim2.fromOffset(12, 164)
ListDisplay.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
ListDisplay.Text = "🟢 화이트리스트 (제외)\n없음\n\n🔴 블랙리스트 (최우선)\n없음"
ListDisplay.TextColor3 = Color3.fromRGB(200, 200, 210)
ListDisplay.TextSize = 12
ListDisplay.Font = Enum.Font.Gotham
ListDisplay.TextXAlignment = Enum.TextXAlignment.Left
ListDisplay.TextYAlignment = Enum.TextYAlignment.Top
ListDisplay.TextWrapped = true
ListDisplay.Parent = ListFrame

local ListDisplayCorner = Instance.new("UICorner")
ListDisplayCorner.CornerRadius = UDim.new(0, 6)
ListDisplayCorner.Parent = ListDisplay

local UIPadding = Instance.new("UIPadding")
UIPadding.PaddingTop = UDim.new(0, 6)
UIPadding.PaddingBottom = UDim.new(0, 6)
UIPadding.PaddingLeft = UDim.new(0, 6)
UIPadding.PaddingRight = UDim.new(0, 6)
UIPadding.Parent = ListDisplay

local function getFullPlayerName(text)
	if text == "" then return nil end

	local lowerText = string.lower(text)

	for _, player in ipairs(Players:GetPlayers()) do
		if string.lower(player.Name):sub(1, #lowerText) == lowerText
			or string.lower(player.DisplayName):sub(1, #lowerText) == lowerText then
			return player.Name
		end
	end

	return text
end

local function updateListUI()
	local whiteText = "🟢 화이트리스트 (제외)\n"
	local whiteCount = 0

	for name in pairs(Whitelist) do
		whiteText = whiteText .. "- " .. name .. "\n"
		whiteCount += 1
	end

	if whiteCount == 0 then
		whiteText = whiteText .. "없음\n"
	end

	local blackText = "\n🔴 블랙리스트 (최우선)\n"
	local blackCount = 0

	for name in pairs(Blacklist) do
		blackText = blackText .. "- " .. name .. "\n"
		blackCount += 1
	end

	if blackCount == 0 then
		blackText = blackText .. "없음\n"
	end

	ListDisplay.Text = whiteText .. blackText
end

AddWhiteBtn.MouseButton1Click:Connect(function()
	local name = getFullPlayerName(NameInput.Text)

	if name then
		Whitelist[name] = true
		Blacklist[name] = nil
		NameInput.Text = ""
		updateListUI()
	end
end)

AddBlackBtn.MouseButton1Click:Connect(function()
	local name = getFullPlayerName(NameInput.Text)

	if name then
		Blacklist[name] = true
		Whitelist[name] = nil
		NameInput.Text = ""
		updateListUI()
	end
end)

RemoveBtn.MouseButton1Click:Connect(function()
	local name = getFullPlayerName(NameInput.Text)

	if name then
		Whitelist[name] = nil
		Blacklist[name] = nil
		NameInput.Text = ""
		updateListUI()
	end
end)

local function makeDraggable(frame, titleBar)
	local dragging = false
	local dragInput = nil
	local dragStart = nil
	local startPosition = nil

	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then

			dragging = true
			dragStart = input.Position
			startPosition = frame.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	titleBar.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and input == dragInput then
			local delta = input.Position - dragStart

			frame.Position = UDim2.new(
				startPosition.X.Scale,
				startPosition.X.Offset + delta.X,
				startPosition.Y.Scale,
				startPosition.Y.Offset + delta.Y
			)
		end
	end)
end

makeDraggable(MainFrame, TitleBar)
makeDraggable(ListFrame, ListTitleBar)

local function createVisualSafeZones()
	for _, zone in ipairs(LOCAL_SAFE_ZONES) do
		local part = Instance.new("Part")
		part.Name = "VisualSafeZonePart"
		part.Size = zone.Size
		part.CFrame = CFrame.new(zone.Center)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Color = Color3.fromRGB(85, 255, 120)
		part.Material = Enum.Material.ForceField
		part.Parent = Workspace
	end
end

createVisualSafeZones()

VisibleButton.MouseButton1Click:Connect(function()
	SAFE_ZONE_VISIBLE = not SAFE_ZONE_VISIBLE

	if SAFE_ZONE_VISIBLE then
		VisibleButton.Text = "세이프존 보기: 켜짐"
		VisibleButton.BackgroundColor3 = Color3.fromRGB(45, 120, 60)
	else
		VisibleButton.Text = "세이프존 보기: 꺼짐"
		VisibleButton.BackgroundColor3 = Color3.fromRGB(85, 85, 95)
	end

	for _, object in ipairs(Workspace:GetChildren()) do
		if object:IsA("BasePart") and object.Name == "VisualSafeZonePart" then
			object.Transparency = SAFE_ZONE_VISIBLE and 0.8 or 1
		end
	end
end)

local function isInSafeZone(character)
	if not SAFE_ZONE_CHECK then return false end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end

	local position = rootPart.Position

	for _, zone in ipairs(LOCAL_SAFE_ZONES) do
		local minX = zone.Center.X - zone.Size.X / 2
		local maxX = zone.Center.X + zone.Size.X / 2
		local minY = zone.Center.Y - zone.Size.Y / 2
		local maxY = zone.Center.Y + zone.Size.Y / 2
		local minZ = zone.Center.Z - zone.Size.Z / 2
		local maxZ = zone.Center.Z + zone.Size.Z / 2

		if position.X >= minX and position.X <= maxX
			and position.Y >= minY and position.Y <= maxY
			and position.Z >= minZ and position.Z <= maxZ then
			return true
		end
	end

	return false
end

local function teamNameContains(player, keyword)
	local team = player.Team
	if not team then return false end
	return string.find(team.Name, keyword, 1, true) ~= nil
end

local function getCharacterInfo(player)
	local character = player.Character
	if not character then return nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return nil
	end

	return character, humanoid, rootPart
end

local function getFireOrigin()
	local character = LocalPlayer.Character
	if not character then return nil end

	local tool = character:FindFirstChildOfClass("Tool")

	if tool then
		local muzzle = tool:FindFirstChild("Muzzle", true)

		if muzzle then
			if muzzle:IsA("Attachment") then
				return muzzle.WorldPosition
			end

			if muzzle:IsA("BasePart") then
				return muzzle.Position
			end
		end
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if rootPart then
		return rootPart.Position
	end

	return nil
end

local function canSeeTarget(origin, targetPart, targetCharacter)
	if not WALL_CHECK then
		return true
	end

	local filterList = {}

	if LocalPlayer.Character then
		table.insert(filterList, LocalPlayer.Character)
	end

	for _, object in ipairs(Workspace:GetChildren()) do
		if object.Name == "VisualSafeZonePart" then
			table.insert(filterList, object)
		end
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = filterList
	rayParams.IgnoreWater = true

	local direction = targetPart.Position - origin
	local result = Workspace:Raycast(origin, direction, rayParams)

	if not result then
		return true
	end

	return result.Instance:IsDescendantOf(targetCharacter)
end

local function getScreenCenter()
	Camera = Workspace.CurrentCamera

	if not Camera then
		return Vector2.zero
	end

	return Vector2.new(
		Camera.ViewportSize.X / 2,
		Camera.ViewportSize.Y / 2
	)
end

local function getBestTarget(origin)
	Camera = Workspace.CurrentCamera

	if not Camera then
		return nil
	end

	if LocalPlayer.Character and isInSafeZone(LocalPlayer.Character) then
		return nil
	end

	local screenCenter = getScreenCenter()
	local blacklistTarget = nil
	local priorityTarget = nil
	local normalTarget = nil

	local blacklistScreenDistance = math.huge
	local priorityScreenDistance = math.huge
	local normalScreenDistance = math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		if player == LocalPlayer then
			continue
		end

		if Whitelist[player.Name] then
			continue
		end

		local isBlacklisted = Blacklist[player.Name] ~= nil

		if not isBlacklisted then
			if teamNameContains(player, "무직") then
				continue
			end

			if TEAM_CHECK
				and LocalPlayer.Team ~= nil
				and player.Team == LocalPlayer.Team then
				continue
			end
		end

		local character, humanoid, rootPart = getCharacterInfo(player)

		if not character or not humanoid or not rootPart then
			continue
		end

		if isInSafeZone(character) then
			continue
		end

		local aimPart = rootPart
		local worldDistance = (aimPart.Position - origin).Magnitude

		if worldDistance > MAX_DISTANCE then
			continue
		end

		if not canSeeTarget(origin, aimPart, character) then
			continue
		end

		local screenPosition, onScreen = Camera:WorldToViewportPoint(aimPart.Position)

		if not onScreen or screenPosition.Z <= 0 then
			continue
		end

		local screenPoint = Vector2.new(screenPosition.X, screenPosition.Y)
		local screenDistance = (screenPoint - screenCenter).Magnitude

		local targetData = {
			Player = player,
			Character = character,
			Part = aimPart,
			WorldDistance = worldDistance,
			ScreenDistance = screenDistance,
			Humanoid = humanoid
		}

		if isBlacklisted then
			if screenDistance < blacklistScreenDistance then
				blacklistScreenDistance = screenDistance
				blacklistTarget = targetData
			end
		elseif teamNameContains(player, "보안") then
			if screenDistance < priorityScreenDistance then
				priorityScreenDistance = screenDistance
				priorityTarget = targetData
			end
		else
			if screenDistance < normalScreenDistance then
				normalScreenDistance = screenDistance
				normalTarget = targetData
			end
		end
	end

	if blacklistTarget then
		return blacklistTarget
	end

	if priorityTarget then
		return priorityTarget
	end

	return normalTarget
end

local function clearTargetHighlight()
	if TargetHighlight then
		TargetHighlight:Destroy()
		TargetHighlight = nil
	end

	CurrentTargetPlayer = nil
	CurrentTargetCharacter = nil
	CurrentTargetPart = nil
	CurrentTargetDistance = nil
	CurrentScreenDistance = nil
end

local function setTargetHighlight(targetData)
	if not targetData or not targetData.Character then
		clearTargetHighlight()
		return
	end

	if TargetHighlight and TargetHighlight.Adornee == targetData.Character then
		return
	end

	if TargetHighlight then
		TargetHighlight:Destroy()
		TargetHighlight = nil
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "CyborgTargetHighlight"
	highlight.Adornee = targetData.Character
	highlight.FillColor = Color3.fromRGB(255, 55, 90)
	highlight.FillTransparency = 0.45
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = targetData.Character

	TargetHighlight = highlight
end

local function calculatePredictedPosition(origin, targetPart, humanoid, targetPlayer, currentSpeed, toolName)
	local targetPosition = targetPart.Position
	local targetVelocity = targetPart.AssemblyLinearVelocity

	local relativePosition = targetPosition - origin
	local distance = relativePosition.Magnitude

	local speedSquared = currentSpeed * currentSpeed
	local velocitySquared = targetVelocity:Dot(targetVelocity)

	local a = velocitySquared - speedSquared
	local b = 2 * relativePosition:Dot(targetVelocity)
	local c = relativePosition:Dot(relativePosition)

	local travelTime = nil

	if math.abs(a) < 0.001 then
		if math.abs(b) > 0.001 then
			local linearTime = -c / b

			if linearTime > 0 then
				travelTime = linearTime
			end
		end
	else
		local discriminant = b * b - 4 * a * c

		if discriminant >= 0 then
			local squareRoot = math.sqrt(discriminant)
			local t1 = (-b - squareRoot) / (2 * a)
			local t2 = (-b + squareRoot) / (2 * a)

			if t1 > 0 and t2 > 0 then
				travelTime = math.min(t1, t2)
			elseif t1 > 0 then
				travelTime = t1
			elseif t2 > 0 then
				travelTime = t2
			end
		end
	end

	if not travelTime then
		travelTime = distance / currentSpeed
	end

	travelTime = travelTime + NETWORK_LEAD
	travelTime = math.clamp(travelTime, 0, 3)

	local predictedPos = targetPosition + targetVelocity * travelTime

	if humanoid and humanoid.FloorMaterial == Enum.Material.Air then
		local gravity = Vector3.new(0, -Workspace.Gravity, 0)
		predictedPos = predictedPos + 0.5 * gravity * (travelTime * travelTime)
	end

	if toolName == "Gun2-A" then
		predictedPos = predictedPos + Vector3.new(0, 1, 0)
	elseif toolName == "GunSNIPE" and targetPlayer and teamNameContains(targetPlayer, "보안") then
		predictedPos = predictedPos - Vector3.new(0, 1.8, 0)
	elseif targetPlayer and teamNameContains(targetPlayer, "보안") then
		predictedPos = predictedPos - Vector3.new(0, 1.8, 0)
	end

	return predictedPos
end

local function getGuiInset()
	local result = Vector2.zero

	pcall(function()
		local topLeft = select(1, GuiService:GetGuiInset())

		if typeof(topLeft) == "Vector2" then
			result = topLeft
		end
	end)

	return result
end

local function getSafeAreaInset()
	local result = Vector2.zero
	local absolute = InsetProbe.AbsolutePosition

	if typeof(absolute) == "Vector2" then
		result = Vector2.new(
			math.max(0, absolute.X),
			math.max(0, absolute.Y)
		)
	end

	pcall(function()
		local fullRect = GuiService:GetInsetArea(Enum.ScreenInsets.None)
		local safeRect = GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets)

		if fullRect and safeRect then
			local delta = safeRect.Min - fullRect.Min

			result = Vector2.new(
				math.max(result.X, delta.X),
				math.max(result.Y, delta.Y)
			)
		end
	end)

	return result
end

local function getInputInset()
	local gui = getGuiInset()
	local safe = getSafeAreaInset()

	return Vector2.new(
		math.max(gui.X, safe.X),
		math.max(gui.Y, safe.Y)
	)
end

local function getVimFromScreen(screenPosition)
	local inset = getInputInset()

	return Vector2.new(
		screenPosition.X + inset.X,
		screenPosition.Y + inset.Y
	)
end

local function getScreenFromWorld(worldPosition)
	local camera = Workspace.CurrentCamera

	if not camera then
		return nil, false
	end

	local point, visible = camera:WorldToScreenPoint(worldPosition)

	if point.Z <= 0 then
		return nil, false
	end

	return Vector2.new(point.X, point.Y), visible
end

local function resetMotion()
	Motion.Player = nil
	Motion.LastPosition = nil
	Motion.LastTime = nil
	Motion.Velocity = Vector2.zero
end

local function updateScreenVelocity(player, screenPosition)
	local now = os.clock()

	if Motion.Player ~= player then
		Motion.Player = player
		Motion.LastPosition = screenPosition
		Motion.LastTime = now
		Motion.Velocity = Vector2.zero
		return
	end

	if not Motion.LastPosition or not Motion.LastTime then
		Motion.LastPosition = screenPosition
		Motion.LastTime = now
		return
	end

	local dt = now - Motion.LastTime

	if dt > 0.001 and dt < 0.1 then
		local velocity = (screenPosition - Motion.LastPosition) / dt

		if velocity.Magnitude > 4500 then
			velocity = velocity.Unit * 4500
		end

		Motion.Velocity = Motion.Velocity:Lerp(
			velocity,
			VELOCITY_SMOOTH
		)
	end

	Motion.LastPosition = screenPosition
	Motion.LastTime = now
end

local function getLeadOffset()
	local lead = Motion.Velocity * INPUT_LEAD_TIME

	if lead.Magnitude > MAX_LEAD_PX then
		lead = lead.Unit * MAX_LEAD_PX
	end

	return lead
end

local function randomGaussian()
	local u1 = math.max(math.random(), 0.000001)
	local u2 = math.random()

	return math.sqrt(-2 * math.log(u1))
		* math.cos(2 * math.pi * u2)
end

local function getScreenRadius(character)
	local camera = Workspace.CurrentCamera

	if not camera or not character then
		return 4
	end

	local ok, cf, size = pcall(function()
		local c, s = character:GetBoundingBox()
		return c, s
	end)

	if not ok then
		return 4
	end

	local center = cf.Position
	local centerScreen = camera:WorldToScreenPoint(center)

	if centerScreen.Z <= 0 then
		return 4
	end

	local horizontal =
		center
		+ camera.CFrame.RightVector
		* math.max(size.X, size.Z)
		* 0.5

	local vertical =
		center
		+ camera.CFrame.UpVector
		* size.Y
		* 0.5

	local hp = camera:WorldToScreenPoint(horizontal)
	local vp = camera:WorldToScreenPoint(vertical)

	local rx = math.abs(hp.X - centerScreen.X)
	local ry = math.abs(vp.Y - centerScreen.Y)

	return math.max(
		1.5,
		math.min(rx, ry)
	)
end

local function getGun2ASpread(character, distance)
	if GUN2A_SPREAD <= 0 then
		return 0
	end

	local radius = getScreenRadius(character)
	local denominator = FAR_DISTANCE - NEAR_DISTANCE
	local t = 0

	if denominator > 0 then
		t = math.clamp(
			(distance - NEAR_DISTANCE) / denominator,
			0,
			1
		)
	end

	t = t ^ 0.65

	local ratio =
		NEAR_SPREAD_RATIO
		+ (FAR_SPREAD_RATIO - NEAR_SPREAD_RATIO)
		* t

	local sizeSpread = radius * ratio
	local farDenominator = FAR_FORCE_END - FAR_FORCE_START
	local farT = 0

	if farDenominator > 0 then
		farT = math.clamp(
			(distance - FAR_FORCE_START) / farDenominator,
			0,
			1
		)
	end

	local forced =
		FAR_MIN_SPREAD_START
		+ (FAR_MIN_SPREAD_END - FAR_MIN_SPREAD_START)
		* farT

	local sigma = math.max(sizeSpread, forced)

	local motionT = math.clamp(
		Motion.Velocity.Magnitude / MOTION_SPEED_FULL,
		0,
		1
	)

	local motionMultiplier =
		1 - MOTION_SPREAD_REDUCTION * motionT

	sigma =
		sigma
		* motionMultiplier
		* GUN2A_SPREAD

	return math.clamp(
		sigma,
		MIN_SPREAD_PX * GUN2A_SPREAD,
		MAX_SPREAD_PX * GUN2A_SPREAD
	)
end

local function generateTouchId()
	NextTouchId += 1

	if NextTouchId > 2000000000 then
		NextTouchId = 5000
	end

	return NextTouchId
end

local function beginHoldTouch(point)
	local x = math.floor(point.X + 0.5)
	local y = math.floor(point.Y + 0.5)

	HoldTouchId = generateTouchId()

	local ok = pcall(function()
		VirtualInputManager:SendTouchEvent(
			HoldTouchId,
			Enum.UserInputState.Begin.Value,
			x,
			y
		)
	end)

	if ok then
		TouchHolding = true
		LastTouchPosition = Vector2.new(x, y)
	end

	return ok
end

local function updateHoldTouch(point)
	if not TouchHolding then
		return beginHoldTouch(point)
	end

	local x = math.floor(point.X + 0.5)
	local y = math.floor(point.Y + 0.5)

	if LastTouchPosition
		and math.abs(LastTouchPosition.X - x) < 1
		and math.abs(LastTouchPosition.Y - y) < 1 then
		return true
	end

	local ok = pcall(function()
		VirtualInputManager:SendTouchEvent(
			HoldTouchId,
			Enum.UserInputState.Change.Value,
			x,
			y
		)
	end)

	if ok then
		LastTouchPosition = Vector2.new(x, y)
	end

	return ok
end

local function endHoldTouch()
	if not TouchHolding then
		HoldTouchId = nil
		LastTouchPosition = nil
		HoldSpreadOffset = Vector2.zero
		resetMotion()
		return
	end

	local point = LastTouchPosition or Vector2.zero
	local id = HoldTouchId

	pcall(function()
		VirtualInputManager:SendTouchEvent(
			id,
			Enum.UserInputState.End.Value,
			math.floor(point.X + 0.5),
			math.floor(point.Y + 0.5)
		)
	end)

	TouchHolding = false
	HoldTouchId = nil
	LastTouchPosition = nil
	HoldSpreadOffset = Vector2.zero
	resetMotion()
end

local function updateSettings()
	local newSpeed = tonumber(SpeedBox.Text)
	local newDelay = tonumber(DelayBox.Text)
	local newDistance = tonumber(DistanceBox.Text)
	local newSpread = tonumber(SpreadBox.Text)

	if newSpeed and newSpeed > 0 then
		PROJECTILE_SPEED = newSpeed
	else
		SpeedBox.Text = tostring(PROJECTILE_SPEED)
	end

	if newDelay and newDelay >= 0.03 then
		FIRE_DELAY = newDelay
	else
		DelayBox.Text = tostring(FIRE_DELAY)
	end

	if newDistance and newDistance > 0 then
		MAX_DISTANCE = newDistance
	else
		DistanceBox.Text = tostring(MAX_DISTANCE)
	end

	if newSpread and newSpread >= 0 then
		GUN2A_SPREAD = newSpread
	else
		SpreadBox.Text = tostring(GUN2A_SPREAD)
	end
end

SpeedBox.FocusLost:Connect(updateSettings)
DelayBox.FocusLost:Connect(updateSettings)
DistanceBox.FocusLost:Connect(updateSettings)
SpreadBox.FocusLost:Connect(updateSettings)

ToggleButton.MouseButton1Click:Connect(function()
	updateSettings()
	AUTO_FIRE = not AUTO_FIRE

	if AUTO_FIRE then
		ToggleButton.Text = "자동사격: 켜짐"
		ToggleButton.BackgroundColor3 = Color3.fromRGB(45, 165, 90)
	else
		ToggleButton.Text = "자동사격: 꺼짐"
		ToggleButton.BackgroundColor3 = Color3.fromRGB(165, 55, 55)
		endHoldTouch()
	end
end)

CloseButton.MouseButton1Click:Connect(function()
	AUTO_FIRE = false
	endHoldTouch()
	clearTargetHighlight()

	for _, object in ipairs(Workspace:GetChildren()) do
		if object.Name == "VisualSafeZonePart" then
			object:Destroy()
		end
	end

	ScreenGui:Destroy()
end)

RunService.RenderStepped:Connect(function()
	if not ScreenGui.Parent then
		endHoldTouch()
		return
	end

	local origin = getFireOrigin()

	if LocalPlayer.Character and isInSafeZone(LocalPlayer.Character) then
		StatusLabel.Text = "🛡️ 안전구역 내부 - 사격 중지"
		endHoldTouch()
		clearTargetHighlight()
		return
	end

	if not origin then
		StatusLabel.Text = "캐릭터 또는 발사 위치 없음"
		endHoldTouch()
		clearTargetHighlight()
		return
	end

	local targetData = getBestTarget(origin)

	if not targetData then
		StatusLabel.Text =
			AUTO_FIRE
			and "자동사격 켜짐 | 대상 없음"
			or "자동사격 꺼짐 | 대상 없음"

		endHoldTouch()
		clearTargetHighlight()
		return
	end

	CurrentTargetPlayer = targetData.Player
	CurrentTargetCharacter = targetData.Character
	CurrentTargetPart = targetData.Part
	CurrentTargetDistance = targetData.WorldDistance
	CurrentScreenDistance = targetData.ScreenDistance

	setTargetHighlight(targetData)

	local targetStatus = ""

	if Blacklist[targetData.Player.Name] then
		targetStatus = " [블랙리스트]"
	elseif teamNameContains(targetData.Player, "보안") then
		targetStatus = " [보안-조준보정]"
	end

	local character = LocalPlayer.Character
	local tool = character and character:FindFirstChildOfClass("Tool")

	if tool and tool.Name == "Gun2-A" then
		targetStatus = targetStatus .. " [터치홀드]"
	end

	StatusLabel.Text = string.format(
		"%s | 대상: %s | %.1f studs%s",
		AUTO_FIRE and "사격 켜짐" or "사격 꺼짐",
		targetData.Player.Name,
		targetData.WorldDistance,
		targetStatus
	)

	if not AUTO_FIRE then
		endHoldTouch()
		return
	end

	if not character or not tool or tool.Name ~= "Gun2-A" then
		endHoldTouch()
		return
	end

	if isInSafeZone(character) then
		endHoldTouch()
		return
	end

	if CurrentTargetCharacter and isInSafeZone(CurrentTargetCharacter) then
		endHoldTouch()
		return
	end

	if not CurrentTargetPart or not CurrentTargetPart.Parent then
		endHoldTouch()
		return
	end

	local humanoid =
		CurrentTargetCharacter
		and CurrentTargetCharacter:FindFirstChildOfClass("Humanoid")

	local predictedPosition =
		calculatePredictedPosition(
			origin,
			CurrentTargetPart,
			humanoid,
			CurrentTargetPlayer,
			GUN2A_PROJECTILE_SPEED,
			tool.Name
		)

	local screenPosition, onScreen =
		getScreenFromWorld(predictedPosition)

	if not screenPosition or not onScreen then
		endHoldTouch()
		return
	end

	updateScreenVelocity(
		CurrentTargetPlayer,
		screenPosition
	)

	local predictedScreen =
		screenPosition + getLeadOffset()

	local now = os.clock()

	if now - LastSpreadUpdate >= FIRE_DELAY then
		local sigma =
			getGun2ASpread(
				CurrentTargetPlayer.Character,
				CurrentTargetDistance
			)

		HoldSpreadOffset = Vector2.new(
			randomGaussian() * sigma,
			randomGaussian() * sigma
		)

		LastSpreadUpdate = now
	end

	local touchPoint =
		getVimFromScreen(
			predictedScreen + HoldSpreadOffset
		)

	updateHoldTouch(touchPoint)
end)

RunService.Heartbeat:Connect(function()
	if not AUTO_FIRE then
		return
	end

	if not CurrentTargetPart or not CurrentTargetPart.Parent then
		return
	end

	if os.clock() - lastFireTime < FIRE_DELAY then
		return
	end

	local character = LocalPlayer.Character

	if not character then
		return
	end

	local tool = character:FindFirstChildOfClass("Tool")

	if not tool then
		return
	end

	if tool.Name == "Gun2-A" then
		return
	end

	if isInSafeZone(character) then
		return
	end

	if CurrentTargetCharacter and isInSafeZone(CurrentTargetCharacter) then
		return
	end

	local origin = getFireOrigin()

	if not origin then
		return
	end

	local humanoid =
		CurrentTargetCharacter
		and CurrentTargetCharacter:FindFirstChildOfClass("Humanoid")

	if tool.Name == "GunSNIPE" then
		local activeSpeed = 1000

		local predictedPosition =
			calculatePredictedPosition(
				origin,
				CurrentTargetPart,
				humanoid,
				CurrentTargetPlayer,
				activeSpeed,
				tool.Name
			)

		FireEvent:FireServer(predictedPosition)
		lastFireTime = os.clock()
	else
		local activeSpeed = PROJECTILE_SPEED

		local predictedPosition =
			calculatePredictedPosition(
				origin,
				CurrentTargetPart,
				humanoid,
				CurrentTargetPlayer,
				activeSpeed,
				tool.Name
			)

		FireEvent:FireServer(predictedPosition)
		lastFireTime = os.clock()
	end
end)

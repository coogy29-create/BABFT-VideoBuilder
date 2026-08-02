local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local Player = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local BlocksFolder = Workspace:WaitForChild("Blocks"):WaitForChild(Player.Name)

local JSON_URL = "https://raw.githubusercontent.com/coogy29-create/BABFT-VideoBuilder/refs/heads/main/badapple_64x64_3fps.json"

local WIDTH = 64
local HEIGHT = 64
local FPS = 3
local MAX_DELAY_COUNT = 500
local DELAYS_PER_FRAME = 2
local MAX_FRAME_COUNT = math.floor(MAX_DELAY_COUNT / DELAYS_PER_FRAME)

local DISPLAY_ID = 4100
local DELAY_ID = 551

local DISPLAY_SPACING_X = 2
local DISPLAY_SPACING_Y = 2

local DELAY_VERTICAL_SPACING = 2.15
local DELAY_SIDE_OFFSET = WIDTH * DISPLAY_SPACING_X + 8

local BUILD_PAUSE = 0
local CONNECT_PAUSE = 0.005
local BATCH_PAUSE = 0.01

local DISPLAY_PARALLEL_BATCH = 16
local DISPLAY_BATCH_TIMEOUT = 5
local DISPLAY_MATCH_DISTANCE = 3

local ZONE_OFFSET = Vector3.new(
	53.565689086914,
	18,
	345.50686645508
)

local WHITE = Color3.new(
	0.97254902124405,
	0.97254902124405,
	0.97254902124405
)

local BLACK = Color3.new(
	0.066666670143604,
	0.066666670143604,
	0.066666670143604
)

local oldGui = CoreGui:FindFirstChild("BABFTBadAppleBuilder")
if oldGui then
	oldGui:Destroy()
end

local CancelRequested = false
local Running = false
local Selecting = false
local SelectedWorldCFrame = nil
local Marker = nil

local Generated = {
	Displays = {},
	DisplayList = {},
	Frames = {},
	Button = nil,
	BaseCFrame = nil,
	Video = nil
}

local function getCharacter()
	return Player.Character or Player.CharacterAdded:Wait()
end

local function findTool(name)
	local character = getCharacter()
	local backpack = Player:WaitForChild("Backpack")

	return backpack:FindFirstChild(name)
		or character:FindFirstChild(name)
end

local function findCharacterTool(name)
	local character = getCharacter()
	local backpack = Player:WaitForChild("Backpack")

	local tool = character:FindFirstChild(name)

	if not tool then
		local backpackTool = backpack:FindFirstChild(name)

		if backpackTool then
			backpackTool.Parent = character
			task.wait(0.2)
			tool = character:FindFirstChild(name)
		end
	end

	return tool
end

local function worldToZoneCFrame(worldCFrame)
	return CFrame.new(worldCFrame.Position + ZONE_OFFSET)
		* worldCFrame.Rotation
end

local function snapshotChildren()
	local snapshot = {}

	for _, object in ipairs(BlocksFolder:GetChildren()) do
		snapshot[object] = true
	end

	return snapshot
end

local function findNewBlock(before, expectedName)
	local fallback = nil

	for _, object in ipairs(BlocksFolder:GetChildren()) do
		if not before[object] then
			fallback = fallback or object

			if object.Name == expectedName then
				return object
			end
		end
	end

	return fallback
end

local function getObjectPosition(object)
	if object:IsA("Model") then
		return object:GetPivot().Position
	elseif object:IsA("BasePart") then
		return object.Position
	end

	return nil
end

local function collectNewBlocks(before, expectedName)
	local blocks = {}

	for _, object in ipairs(BlocksFolder:GetChildren()) do
		if not before[object] and object.Name == expectedName then
			table.insert(blocks, object)
		end
	end

	return blocks
end

local function installDisplayBatch(buildRF, requests)
	local zone = Workspace:FindFirstChild("WhiteZone")

	if not zone then
		return nil, "workspace.WhiteZone을 찾지 못했습니다."
	end

	local before = snapshotChildren()
	local finished = 0
	local callErrors = {}

	for requestIndex, request in ipairs(requests) do
		task.spawn(function()
			local ok, result = pcall(function()
				return buildRF:InvokeServer(
					"DisplayBlock",
					DISPLAY_ID,
					zone,
					worldToZoneCFrame(request.CFrame),
					true,
					request.CFrame,
					false
				)
			end)

			if not ok then
				callErrors[requestIndex] = tostring(result)
			end

			finished += 1
		end)
	end

	local callDeadline = os.clock() + DISPLAY_BATCH_TIMEOUT

	while finished < #requests and os.clock() < callDeadline do
		if CancelRequested then
			return nil, "사용자가 중단했습니다."
		end

		task.wait(0.005)
	end

	if finished < #requests then
		return nil, "병렬 설치 리모트 응답 시간 초과"
	end

	local created = {}
	local createDeadline = os.clock() + DISPLAY_BATCH_TIMEOUT

	repeat
		if CancelRequested then
			return nil, "사용자가 중단했습니다."
		end

		created = collectNewBlocks(before, "DisplayBlock")

		if #created >= #requests then
			break
		end

		task.wait(0.005)
	until os.clock() >= createDeadline

	local remainingObjects = {}

	for _, object in ipairs(created) do
		table.insert(remainingObjects, object)
	end

	local matched = {}
	local missing = {}

	for requestIndex, request in ipairs(requests) do
		local bestObject = nil
		local bestObjectIndex = nil
		local bestDistance = math.huge

		for objectIndex, object in ipairs(remainingObjects) do
			local position = getObjectPosition(object)

			if position then
				local distance = (position - request.CFrame.Position).Magnitude

				if distance < bestDistance then
					bestDistance = distance
					bestObject = object
					bestObjectIndex = objectIndex
				end
			end
		end

		if bestObject and bestDistance <= DISPLAY_MATCH_DISTANCE then
			matched[requestIndex] = bestObject
			table.remove(remainingObjects, bestObjectIndex)
		else
			table.insert(missing, requestIndex)
		end
	end

	-- 누락된 요청만 안정적인 순차 방식으로 한 번 재시도
	for _, requestIndex in ipairs(missing) do
		if CancelRequested then
			return nil, "사용자가 중단했습니다."
		end

		local request = requests[requestIndex]
		local display, errorMessage = installBlock(
			buildRF,
			"DisplayBlock",
			DISPLAY_ID,
			request.CFrame,
			4
		)

		if not display then
			local remoteError = callErrors[requestIndex]

			return nil,
				"병렬 누락 재시도 실패: "
				.. tostring(errorMessage)
				.. (remoteError and ("\n리모트: " .. remoteError) or "")
		end

		matched[requestIndex] = display
	end

	return matched
end

local function installBlock(buildRF, blockType, blockId, worldCFrame, timeout)
	local zone = Workspace:FindFirstChild("WhiteZone")

	if not zone then
		return nil, "workspace.WhiteZone을 찾지 못했습니다."
	end

	local before = snapshotChildren()

	local ok, result = pcall(function()
		return buildRF:InvokeServer(
			blockType,
			blockId,
			zone,
			worldToZoneCFrame(worldCFrame),
			true,
			worldCFrame,
			false
		)
	end)

	if not ok then
		return nil, tostring(result)
	end

	local deadline = os.clock() + (timeout or 8)
	local created = nil

	repeat
		if CancelRequested then
			return nil, "사용자가 중단했습니다."
		end

		created = findNewBlock(before, blockType)

		if created then
			break
		end

		task.wait(0.005)
	until os.clock() >= deadline

	if not created then
		return nil, blockType .. " 생성 확인 시간 초과"
	end

	return created
end

local function waitForChild(parent, name, timeout)
	local existing = parent and parent:FindFirstChild(name)

	if existing then
		return existing
	end

	local deadline = os.clock() + (timeout or 5)

	while parent and parent.Parent and os.clock() < deadline do
		local child = parent:FindFirstChild(name)

		if child then
			return child
		end

		task.wait(0.005)
	end

	return nil
end

local function invokePaint(paintRF, entries)
	if #entries == 0 then
		return true
	end

	local ok, result = pcall(function()
		return paintRF:InvokeServer(entries)
	end)

	return ok, result
end

local function paintInBatches(paintRF, entries, batchSize)
	local size = batchSize or 100
	local index = 1

	while index <= #entries do
		if CancelRequested then
			return false, "사용자가 중단했습니다."
		end

		local batch = {}
		local last = math.min(index + size - 1, #entries)

		for i = index, last do
			table.insert(batch, entries[i])
		end

		local ok, result = invokePaint(paintRF, batch)

		if not ok then
			return false, result
		end

		index = last + 1
		task.wait(BATCH_PAUSE)
	end

	return true
end

local function setDelayTime(propertyRF, delays, value)
	local ok, result = pcall(function()
		return propertyRF:InvokeServer(
			"Delay time",
			delays,
			tostring(value)
		)
	end)

	return ok, result
end

local function setDelayTimesInBatches(propertyRF, groups)
	for _, group in ipairs(groups) do
		if CancelRequested then
			return false, "사용자가 중단했습니다."
		end

		local ok, result = setDelayTime(
			propertyRF,
			group.Delays,
			group.Value
		)

		if not ok then
			return false, result
		end

		task.wait(BATCH_PAUSE)
	end

	return true
end

local function bindValues(bindRF, sourceBlock, targets)
	if not sourceBlock then
		return false, "연결 원본 블록이 없습니다."
	end

	if #targets == 0 then
		return true, nil, 0
	end

	local ok, result = pcall(function()
		return bindRF:InvokeServer(
			{
				Activate = targets
			},
			sourceBlock,
			{},
			false,
			true
		)
	end)

	if not ok then
		return false, tostring(result), 0
	end

	return true, result, #targets
end

local function getObjectPosition(object)
	if object:IsA("Model") then
		return object:GetPivot().Position
	elseif object:IsA("BasePart") then
		return object.Position
	end

	return nil
end

local function findNearestButton(position)
	local nearest = nil
	local nearestDistance = math.huge

	for _, object in ipairs(BlocksFolder:GetChildren()) do
		if object.Name == "Button" then
			local objectPosition = getObjectPosition(object)

			if objectPosition then
				local distance = (objectPosition - position).Magnitude

				if distance < nearestDistance then
					nearestDistance = distance
					nearest = object
				end
			end
		end
	end

	return nearest, nearestDistance
end

local function frameDelayValue(frameIndex)
	if frameIndex == 1 then
		return "0.01"
	end

	local patternIndex = (frameIndex - 2) % 3

	if patternIndex == 2 then
		return "0.34"
	end

	return "0.33"
end

local function decodeFrame(frame)
	local whiteTargets = {}
	local blackTargets = {}

	for y = 1, HEIGHT do
		local row = frame[y]

		if type(row) ~= "string" or #row < WIDTH then
			return nil, nil, "잘못된 프레임 행: " .. tostring(y)
		end

		for x = 1, WIDTH do
			local display = Generated.Displays[y][x]
			local bindFire = display and display:FindFirstChild("BindFire")

			if not bindFire then
				return nil, nil, string.format(
					"Display BindFire 없음: (%d, %d)",
					x,
					y
				)
			end

			if row:sub(x, x) == "1" then
				table.insert(whiteTargets, bindFire)
			else
				table.insert(blackTargets, bindFire)
			end
		end
	end

	return whiteTargets, blackTargets
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "BABFTBadAppleBuilder"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false
Gui.Parent = CoreGui

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(330, 350)
Main.Position = UDim2.new(0.5, -165, 0.5, -175)
Main.BackgroundColor3 = Color3.fromRGB(27, 29, 35)
Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = Gui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 15)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(70, 75, 90)
MainStroke.Thickness = 1
MainStroke.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -55, 0, 42)
Title.Position = UDim2.fromOffset(15, 4)
Title.BackgroundTransparency = 1
Title.Text = "BABFT Bad Apple Builder V1.0 PARALLEL"
Title.TextColor3 = Color3.fromRGB(245, 245, 250)
Title.TextSize = 17
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local Close = Instance.new("TextButton")
Close.Size = UDim2.fromOffset(34, 34)
Close.Position = UDim2.new(1, -42, 0, 7)
Close.BackgroundColor3 = Color3.fromRGB(48, 51, 61)
Close.BorderSizePixel = 0
Close.Text = "×"
Close.TextColor3 = Color3.new(1, 1, 1)
Close.TextSize = 23
Close.Font = Enum.Font.GothamBold
Close.Parent = Main

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 10)
CloseCorner.Parent = Close

local Info = Instance.new("TextLabel")
Info.Size = UDim2.new(1, -30, 0, 58)
Info.Position = UDim2.fromOffset(15, 48)
Info.BackgroundColor3 = Color3.fromRGB(36, 39, 47)
Info.BorderSizePixel = 0
Info.Text = "64×64 / 3FPS / 250프레임 · PARALLEL\nDisplay 16개씩 동시 설치 · 누락만 재시도"
Info.TextColor3 = Color3.fromRGB(205, 209, 220)
Info.TextSize = 13
Info.TextWrapped = true
Info.Font = Enum.Font.Gotham
Info.Parent = Main

local InfoCorner = Instance.new("UICorner")
InfoCorner.CornerRadius = UDim.new(0, 10)
InfoCorner.Parent = Info

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -30, 0, 96)
Status.Position = UDim2.fromOffset(15, 116)
Status.BackgroundColor3 = Color3.fromRGB(39, 42, 51)
Status.BorderSizePixel = 0
Status.Text = "먼저 위치 선택을 누르고\n64×64 화면의 좌하단 위치를 누르세요."
Status.TextColor3 = Color3.fromRGB(225, 227, 235)
Status.TextSize = 14
Status.TextWrapped = true
Status.Font = Enum.Font.Gotham
Status.Parent = Main

local StatusCorner = Instance.new("UICorner")
StatusCorner.CornerRadius = UDim.new(0, 10)
StatusCorner.Parent = Status

local SelectButton = Instance.new("TextButton")
SelectButton.Size = UDim2.new(1, -30, 0, 44)
SelectButton.Position = UDim2.fromOffset(15, 224)
SelectButton.BackgroundColor3 = Color3.fromRGB(56, 105, 190)
SelectButton.BorderSizePixel = 0
SelectButton.Text = "위치 선택"
SelectButton.TextColor3 = Color3.new(1, 1, 1)
SelectButton.TextSize = 15
SelectButton.Font = Enum.Font.GothamBold
SelectButton.Parent = Main

local SelectCorner = Instance.new("UICorner")
SelectCorner.CornerRadius = UDim.new(0, 10)
SelectCorner.Parent = SelectButton

local StartButton = Instance.new("TextButton")
StartButton.Size = UDim2.new(0.64, -20, 0, 48)
StartButton.Position = UDim2.fromOffset(15, 282)
StartButton.BackgroundColor3 = Color3.fromRGB(60, 65, 75)
StartButton.BorderSizePixel = 0
StartButton.Text = "생성 시작"
StartButton.TextColor3 = Color3.fromRGB(155, 158, 168)
StartButton.TextSize = 15
StartButton.Font = Enum.Font.GothamBold
StartButton.AutoButtonColor = false
StartButton.Parent = Main

local StartCorner = Instance.new("UICorner")
StartCorner.CornerRadius = UDim.new(0, 10)
StartCorner.Parent = StartButton

local StopButton = Instance.new("TextButton")
StopButton.Size = UDim2.new(0.36, -10, 0, 48)
StopButton.Position = UDim2.new(0.64, 5, 0, 282)
StopButton.BackgroundColor3 = Color3.fromRGB(166, 65, 65)
StopButton.BorderSizePixel = 0
StopButton.Text = "중단"
StopButton.TextColor3 = Color3.new(1, 1, 1)
StopButton.TextSize = 15
StopButton.Font = Enum.Font.GothamBold
StopButton.Parent = Main

local StopCorner = Instance.new("UICorner")
StopCorner.CornerRadius = UDim.new(0, 10)
StopCorner.Parent = StopButton

local dragging = false
local dragInput = nil
local dragStart = nil
local startPos = nil

Title.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = Main.Position
	end
end)

Title.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and input == dragInput then
		local delta = input.Position - dragStart

		Main.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

local function setStatus(text)
	Status.Text = text
end

local function setStartEnabled(enabled)
	StartButton.AutoButtonColor = enabled

	if enabled then
		StartButton.BackgroundColor3 = Color3.fromRGB(46, 170, 104)
		StartButton.TextColor3 = Color3.new(1, 1, 1)
	else
		StartButton.BackgroundColor3 = Color3.fromRGB(60, 65, 75)
		StartButton.TextColor3 = Color3.fromRGB(155, 158, 168)
	end
end

local function createMarker(cframe)
	if Marker then
		Marker:Destroy()
	end

	Marker = Instance.new("Part")
	Marker.Name = "BABFTBadAppleSelectionMarker"
	Marker.Anchored = true
	Marker.CanCollide = false
	Marker.CanQuery = false
	Marker.CanTouch = false
	Marker.Material = Enum.Material.Neon
	Marker.Color = Color3.fromRGB(0, 230, 255)
	Marker.Transparency = 0.55
	Marker.Size = Vector3.new(
		(WIDTH - 1) * DISPLAY_SPACING_X + 2,
		(HEIGHT - 1) * DISPLAY_SPACING_Y + 2,
		0.2
	)
	Marker.CFrame = cframe * CFrame.new(
		(WIDTH - 1) * DISPLAY_SPACING_X / 2,
		(HEIGHT - 1) * DISPLAY_SPACING_Y / 2,
		0
	)
	Marker.Parent = Workspace
end

local function choosePosition(screenPosition)
	local ray = Camera:ViewportPointToRay(
		screenPosition.X,
		screenPosition.Y
	)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local excluded = {}

	if Player.Character then
		table.insert(excluded, Player.Character)
	end

	if Marker then
		table.insert(excluded, Marker)
	end

	params.FilterDescendantsInstances = excluded

	local result = Workspace:Raycast(
		ray.Origin,
		ray.Direction * 3000,
		params
	)

	if not result then
		setStatus("위치 감지 실패\n바닥이나 벽을 다시 누르세요.")
		return
	end

	local position = result.Position + result.Normal

	position = Vector3.new(
		math.round(position.X),
		math.round(position.Y * 10) / 10,
		math.round(position.Z)
	)

	local right = Camera.CFrame.RightVector
	right = Vector3.new(right.X, 0, right.Z)

	if right.Magnitude < 0.1 then
		right = Vector3.new(1, 0, 0)
	else
		right = right.Unit
	end

	local up = Vector3.new(0, 1, 0)
	local back = right:Cross(up)

	if back.Magnitude < 0.1 then
		back = Vector3.new(0, 0, 1)
	else
		back = back.Unit
	end

	SelectedWorldCFrame = CFrame.fromMatrix(
		position,
		right,
		up,
		back
	)

	Generated.BaseCFrame = SelectedWorldCFrame
	Selecting = false

	createMarker(SelectedWorldCFrame)
	setStartEnabled(true)

	setStatus(string.format(
		"위치 선택 완료\nX %.1f / Y %.1f / Z %.1f",
		position.X,
		position.Y,
		position.Z
	))

	SelectButton.Text = "위치 다시 선택"
end

SelectButton.MouseButton1Click:Connect(function()
	if Running then
		return
	end

	Selecting = true
	setStatus("창 밖에서 64×64 화면 좌하단 위치를 누르세요.")
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not Selecting or Running then
		return
	end

	if input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1 then
		choosePosition(input.Position)
	end
end)

StopButton.MouseButton1Click:Connect(function()
	if Running then
		CancelRequested = true
		setStatus("중단 요청됨\n현재 작업이 끝나는 즉시 멈춥니다.")
	end
end)

local function fail(message)
	setStatus(message)
	Running = false
	setStartEnabled(SelectedWorldCFrame ~= nil)
	StartButton.Text = "다시 시작"
end

local function loadVideo()
	setStatus("Bad Apple JSON 다운로드 중...")

	local ok, raw = pcall(function()
		return game:HttpGet(
			JSON_URL .. "?t=" .. tostring(os.time())
		)
	end)

	if not ok then
		return nil, "JSON 다운로드 실패: " .. tostring(raw)
	end

	setStatus(string.format(
		"JSON 다운로드 완료\n%.2f MB · 해석 중...",
		#raw / 1024 / 1024
	))

	local decodeOk, video = pcall(function()
		return HttpService:JSONDecode(raw)
	end)

	if not decodeOk then
		return nil, "JSON 해석 실패: " .. tostring(video)
	end

	if tonumber(video.width) ~= WIDTH
		or tonumber(video.height) ~= HEIGHT then
		return nil, string.format(
			"JSON 해상도 불일치: %sx%s",
			tostring(video.width),
			tostring(video.height)
		)
	end

	if type(video.frames) ~= "table" then
		return nil, "JSON frames 배열이 없습니다."
	end

	local usableFrames = math.min(
		#video.frames,
		MAX_FRAME_COUNT
	)

	if usableFrames < 1 then
		return nil, "사용 가능한 프레임이 없습니다."
	end

	video.UsableFrameCount = usableFrames

	return video
end

local function buildAll()
	if Running or not SelectedWorldCFrame then
		return
	end

	Running = true
	CancelRequested = false
	setStartEnabled(false)
	StartButton.Text = "생성 중..."

	Generated = {
		Displays = {},
		DisplayList = {},
		Frames = {},
		Button = nil,
		BaseCFrame = SelectedWorldCFrame,
		Video = nil
	}

	local video, videoError = loadVideo()

	if not video then
		return fail(videoError)
	end

	Generated.Video = video

	local character = getCharacter()
	local backpack = Player:WaitForChild("Backpack")

	local BuildingTool = findTool("BuildingTool")
	local PaintingTool = findTool("PaintingTool")
	local BindTool = findCharacterTool("BindTool")
	local PropertiesTool = findTool("PropertiesTool")

	if not BuildingTool then
		return fail("BuildingTool을 찾지 못했습니다.")
	end

	if not PaintingTool then
		return fail("PaintingTool을 찾지 못했습니다.")
	end

	if not BindTool then
		return fail("Character.BindTool을 찾지 못했습니다.")
	end

	if not PropertiesTool then
		return fail("PropertiesTool을 찾지 못했습니다.")
	end

	local BuildRF = BuildingTool:WaitForChild("RF")
	local PaintRF = PaintingTool:WaitForChild("RF")
	local BindRF = BindTool:WaitForChild("RF")
	local PropertyRF = PropertiesTool:WaitForChild("SetPropertieRF")

	local totalDisplays = WIDTH * HEIGHT

	for y = 1, HEIGHT do
		Generated.Displays[y] = {}
	end

	local requests = {}

	for y = 1, HEIGHT do
		for x = 1, WIDTH do
			local index = (y - 1) * WIDTH + x
			local worldCFrame = SelectedWorldCFrame * CFrame.new(
				(x - 1) * DISPLAY_SPACING_X,
				(HEIGHT - y) * DISPLAY_SPACING_Y,
				0
			)

			table.insert(requests, {
				Index = index,
				X = x,
				Y = y,
				CFrame = worldCFrame
			})
		end
	end

	for batchStart = 1, #requests, DISPLAY_PARALLEL_BATCH do
		if CancelRequested then
			return fail("Display 생성 중 중단됨")
		end

		local batch = {}
		local batchEnd = math.min(
			batchStart + DISPLAY_PARALLEL_BATCH - 1,
			#requests
		)

		for index = batchStart, batchEnd do
			table.insert(batch, requests[index])
		end

		setStatus(string.format(
			"Display 병렬 생성 중\n%d ~ %d / %d (%.1f%%)\n동시 요청: %d개",
			batchStart,
			batchEnd,
			totalDisplays,
			batchEnd / totalDisplays * 100,
			#batch
		))

		local matched, batchError = installDisplayBatch(
			BuildRF,
			batch
		)

		if not matched then
			return fail(
				"Display 병렬 생성 실패\n"
				.. tostring(batchError)
				.. string.format(
					"\n범위: %d ~ %d / %d",
					batchStart,
					batchEnd,
					totalDisplays
				)
			)
		end

		for localIndex, request in ipairs(batch) do
			local display = matched[localIndex]

			if not display then
				return fail(
					string.format(
						"Display 좌표 매칭 실패\n전체 번호 %d",
						request.Index
					)
				)
			end

			local bindFire = waitForChild(
				display,
				"BindFire",
				3
			)

			if not bindFire then
				return fail(
					string.format(
						"Display BindFire 준비 실패\n%d / %d",
						request.Index,
						totalDisplays
					)
				)
			end

			Generated.Displays[request.Y][request.X] = display
			table.insert(Generated.DisplayList, display)
		end

		task.wait()
	end

	local frameCount = video.UsableFrameCount
	local totalDelays = frameCount * 2

	local delayBase = SelectedWorldCFrame * CFrame.new(
		DELAY_SIDE_OFFSET,
		0,
		0
	)

	local paintEntries = {}
	local timeGroups = {
		["0.01"] = {},
		["0.33"] = {},
		["0.34"] = {}
	}

	for frameIndex = 1, frameCount do
		if CancelRequested then
			return fail("Delay 생성 중 중단됨")
		end

		local whiteIndex = (frameIndex - 1) * 2 + 1
		local blackIndex = whiteIndex + 1

		setStatus(string.format(
			"Delay 수직 적층 중\n%d / %d (프레임 %d / %d)",
			whiteIndex - 1,
			totalDelays,
			frameIndex,
			frameCount
		))

		local whiteWorldCFrame = delayBase * CFrame.new(
			0,
			(whiteIndex - 1) * DELAY_VERTICAL_SPACING,
			0
		)

		local whiteDelay, whiteError = installBlock(
			BuildRF,
			"Delay",
			DELAY_ID,
			whiteWorldCFrame,
			3
		)

		if not whiteDelay then
			return fail(
				"흰색 Delay 생성 실패\n"
				.. tostring(whiteError)
				.. string.format("\n프레임 %d", frameIndex)
			)
		end

		setStatus(string.format(
			"Delay 수직 적층 중\n%d / %d (프레임 %d / %d)",
			whiteIndex,
			totalDelays,
			frameIndex,
			frameCount
		))

		local blackWorldCFrame = delayBase * CFrame.new(
			0,
			(blackIndex - 1) * DELAY_VERTICAL_SPACING,
			0
		)

		local blackDelay, blackError = installBlock(
			BuildRF,
			"Delay",
			DELAY_ID,
			blackWorldCFrame,
			3
		)

		if not blackDelay then
			return fail(
				"검은색 Delay 생성 실패\n"
				.. tostring(blackError)
				.. string.format("\n프레임 %d", frameIndex)
			)
		end

		local whiteActivate = waitForChild(
			whiteDelay,
			"BindActivate",
			5
		)

		local blackActivate = waitForChild(
			blackDelay,
			"BindActivate",
			5
		)

		if not whiteActivate or not blackActivate then
			return fail(
				"Delay BindActivate 준비 실패\n프레임 "
				.. tostring(frameIndex)
			)
		end

		Generated.Frames[frameIndex] = {
			White = whiteDelay,
			Black = blackDelay,
			WhiteActivate = whiteActivate,
			BlackActivate = blackActivate
		}

		table.insert(paintEntries, {
			whiteDelay,
			WHITE
		})

		table.insert(paintEntries, {
			blackDelay,
			BLACK
		})

		local delayValue = frameDelayValue(frameIndex)

		table.insert(
			timeGroups[delayValue],
			whiteDelay
		)

		table.insert(
			timeGroups[delayValue],
			blackDelay
		)

		if BUILD_PAUSE > 0 then
			task.wait(BUILD_PAUSE)
		elseif frameIndex % 20 == 0 then
			task.wait()
		end
	end

	setStatus("Delay 500개 색상 일괄 설정 중...")

	local paintOk, paintResult = paintInBatches(
		PaintRF,
		paintEntries,
		100
	)

	if not paintOk then
		return fail(
			"Delay 색칠 실패\n"
			.. tostring(paintResult)
		)
	end

	setStatus("3FPS Delay 시간 일괄 설정 중...")

	local delayGroups = {}

	for _, value in ipairs({
		"0.01",
		"0.33",
		"0.34"
	}) do
		local list = timeGroups[value]

		if #list > 0 then
			table.insert(delayGroups, {
				Value = value,
				Delays = list
			})
		end
	end

	local timeOk, timeResult = setDelayTimesInBatches(
		PropertyRF,
		delayGroups
	)

	if not timeOk then
		return fail(
			"Delay 시간 설정 실패\n"
			.. tostring(timeResult)
		)
	end

	for frameIndex = 1, frameCount do
		if CancelRequested then
			return fail("Display 연결 중 중단됨")
		end

		setStatus(string.format(
			"프레임 Display 연결 중\n%d / %d (%.1f%%)",
			frameIndex,
			frameCount,
			frameIndex / frameCount * 100
		))

		local frame = video.frames[frameIndex]

		local whiteTargets, blackTargets, decodeError =
			decodeFrame(frame)

		if not whiteTargets then
			return fail(
				"프레임 해석 실패\n"
				.. tostring(decodeError)
				.. "\n프레임 "
				.. tostring(frameIndex)
			)
		end

		local frameBlocks = Generated.Frames[frameIndex]

		local whiteOk, whiteResult = bindValues(
			BindRF,
			frameBlocks.White,
			whiteTargets
		)

		if not whiteOk then
			return fail(
				"흰색 Display 연결 실패\n프레임 "
				.. tostring(frameIndex)
				.. "\n"
				.. tostring(whiteResult)
			)
		end

		local blackOk, blackResult = bindValues(
			BindRF,
			frameBlocks.Black,
			blackTargets
		)

		if not blackOk then
			return fail(
				"검은색 Display 연결 실패\n프레임 "
				.. tostring(frameIndex)
				.. "\n"
				.. tostring(blackResult)
			)
		end

		if CONNECT_PAUSE > 0 then
			task.wait(CONNECT_PAUSE)
		elseif frameIndex % 10 == 0 then
			task.wait()
		end
	end

	for frameIndex = 1, frameCount - 1 do
		if CancelRequested then
			return fail("Delay 체인 연결 중 중단됨")
		end

		setStatus(string.format(
			"Delay 체인 연결 중\n%d / %d",
			frameIndex,
			frameCount - 1
		))

		local currentFrame = Generated.Frames[frameIndex]
		local nextFrame = Generated.Frames[frameIndex + 1]

		local chainOk, chainResult = bindValues(
			BindRF,
			currentFrame.White,
			{
				nextFrame.WhiteActivate,
				nextFrame.BlackActivate
			}
		)

		if not chainOk then
			return fail(
				"Delay 체인 연결 실패\n프레임 "
				.. tostring(frameIndex)
				.. " → "
				.. tostring(frameIndex + 1)
				.. "\n"
				.. tostring(chainResult)
			)
		end

		if CONNECT_PAUSE > 0 then
			task.wait(CONNECT_PAUSE)
		elseif frameIndex % 10 == 0 then
			task.wait()
		end
	end

	setStatus("가장 가까운 시작 버튼 탐색 중...")

	local button, buttonDistance = findNearestButton(
		SelectedWorldCFrame.Position
	)

	if button then
		local firstFrame = Generated.Frames[1]

		local buttonOk, buttonResult = bindValues(
			BindRF,
			button,
			{
				firstFrame.WhiteActivate,
				firstFrame.BlackActivate
			}
		)

		if not buttonOk then
			return fail(
				"시작 버튼 연결 실패\n"
				.. tostring(buttonResult)
			)
		end

		Generated.Button = button
	end

	if Marker then
		Marker:Destroy()
		Marker = nil
	end

	getgenv().BABFTBadAppleBuilder = Generated

	Running = false
	StartButton.Text = "완료"
	StartButton.BackgroundColor3 = Color3.fromRGB(46, 170, 104)
	StartButton.TextColor3 = Color3.new(1, 1, 1)

	if Generated.Button then
		setStatus(string.format(
			"전체 생성 완료\n250프레임 · Delay 500개 · 버튼 연결 완료\n버튼 거리 %.1f",
			buttonDistance or 0
		))
	else
		setStatus(
			"전체 생성 완료\n250프레임 · Delay 500개\nButton이 없어 첫 Delay 2개를 수동 연결하세요."
		)
	end

	print("BABFT Bad Apple Builder 생성 완료")
	print("프레임:", frameCount)
	print("Display:", #Generated.DisplayList)
	print("Delay:", frameCount * 2)
	print("재생 길이:", frameCount / FPS, "초")
	print("시작 버튼:", Generated.Button)
end

StartButton.MouseButton1Click:Connect(function()
	if not SelectedWorldCFrame then
		setStatus("먼저 위치를 선택하세요.")
		return
	end

	task.spawn(buildAll)
end)

Close.MouseButton1Click:Connect(function()
	if Running then
		CancelRequested = true
	end

	Selecting = false

	if Marker then
		Marker:Destroy()
	end

	Gui:Destroy()
end)

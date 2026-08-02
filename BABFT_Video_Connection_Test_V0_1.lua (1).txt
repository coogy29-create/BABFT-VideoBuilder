local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local Player = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local BlocksFolder = Workspace:WaitForChild("Blocks"):WaitForChild(Player.Name)

local WIDTH = 8
local HEIGHT = 8
local DISPLAY_ID = 68
local DELAY_ID = 551
local DISPLAY_SPACING_X = 2
local DISPLAY_SPACING_Y = 2
local DELAY_SPACING = 3
local ZONE_OFFSET = Vector3.new(53.565689086914, 18, 345.50686645508)
local WHITE = Color3.new(0.97254902124405, 0.97254902124405, 0.97254902124405)
local BLACK = Color3.new(0.066666670143604, 0.066666670143604, 0.066666670143604)

local oldGui = CoreGui:FindFirstChild("BABFTVideoConnectionTest")
if oldGui then oldGui:Destroy() end

local function getCharacter()
    return Player.Character or Player.CharacterAdded:Wait()
end

local function findTool(name)
    local character = getCharacter()
    local backpack = Player:WaitForChild("Backpack")
    return backpack:FindFirstChild(name) or character:FindFirstChild(name)
end

local function snapshotChildren()
    local t = {}
    for _, v in ipairs(BlocksFolder:GetChildren()) do t[v] = true end
    return t
end

local function waitForNewBlock(before, expectedName, timeout)
    local deadline = os.clock() + (timeout or 5)
    repeat
        for _, v in ipairs(BlocksFolder:GetChildren()) do
            if not before[v] and (not expectedName or v.Name == expectedName) then
                return v
            end
        end
        task.wait(0.03)
    until os.clock() >= deadline
    for _, v in ipairs(BlocksFolder:GetChildren()) do
        if not before[v] then return v end
    end
end

local function worldToZoneCFrame(worldCFrame)
    return CFrame.new(worldCFrame.Position + ZONE_OFFSET) * worldCFrame.Rotation
end

local function installBlock(buildRF, blockType, blockId, worldCFrame)
    local zone = Workspace:FindFirstChild("WhiteZone")
    if not zone then return nil, "workspace.WhiteZone 없음" end
    local before = snapshotChildren()
    local ok, err = pcall(function()
        buildRF:InvokeServer(
            blockType,
            blockId,
            zone,
            worldToZoneCFrame(worldCFrame),
            true,
            worldCFrame,
            false
        )
    end)
    if not ok then return nil, tostring(err) end
    local created = waitForNewBlock(before, blockType, 5) or waitForNewBlock(before, nil, 1)
    if not created then return nil, blockType .. " 생성 확인 실패" end
    return created
end

local function paintBlocks(paintRF, entries)
    return pcall(function() paintRF:InvokeServer(entries) end)
end

local function setDelayTime(propertyRF, delays, value)
    return pcall(function()
        propertyRF:InvokeServer("Delay time", delays, tostring(value))
    end)
end

local function bindDisplays(bindRF, delayBlock, displayBlocks)
    local targets = {}
    for _, display in ipairs(displayBlocks) do
        local bindFire = display and display:FindFirstChild("BindFire")
        if bindFire then table.insert(targets, bindFire) end
    end
    if #targets == 0 then return false, "BindFire 대상 없음", 0 end
    local ok, err = pcall(function()
        bindRF:InvokeServer({Activate = targets}, delayBlock, {}, false, true)
    end)
    return ok, err, #targets
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "BABFTVideoConnectionTest"
Gui.ResetOnSpawn = false
Gui.Parent = CoreGui

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(310, 260)
Main.Position = UDim2.new(0.5, -155, 0.5, -130)
Main.BackgroundColor3 = Color3.fromRGB(27, 29, 35)
Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = Gui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 15)

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(70, 75, 90)
Stroke.Thickness = 1
Stroke.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -55, 0, 42)
Title.Position = UDim2.fromOffset(15, 4)
Title.BackgroundTransparency = 1
Title.Text = "BABFT 연결 테스트 V0.1"
Title.TextColor3 = Color3.fromRGB(245, 245, 250)
Title.TextSize = 18
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local Close = Instance.new("TextButton")
Close.Size = UDim2.fromOffset(34, 34)
Close.Position = UDim2.new(1, -42, 0, 7)
Close.BackgroundColor3 = Color3.fromRGB(48, 51, 61)
Close.BorderSizePixel = 0
Close.Text = "×"
Close.TextColor3 = Color3.new(1,1,1)
Close.TextSize = 23
Close.Font = Enum.Font.GothamBold
Close.Parent = Main
Instance.new("UICorner", Close).CornerRadius = UDim.new(0, 10)

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -30, 0, 78)
Status.Position = UDim2.fromOffset(15, 50)
Status.BackgroundColor3 = Color3.fromRGB(39, 42, 51)
Status.BorderSizePixel = 0
Status.Text = "위치 선택을 누른 뒤\n8×8 화면의 좌하단 위치를 누르세요."
Status.TextColor3 = Color3.fromRGB(220, 223, 232)
Status.TextSize = 14
Status.TextWrapped = true
Status.Font = Enum.Font.Gotham
Status.Parent = Main
Instance.new("UICorner", Status).CornerRadius = UDim.new(0, 10)

local SelectButton = Instance.new("TextButton")
SelectButton.Size = UDim2.new(1, -30, 0, 48)
SelectButton.Position = UDim2.fromOffset(15, 142)
SelectButton.BackgroundColor3 = Color3.fromRGB(56, 105, 190)
SelectButton.BorderSizePixel = 0
SelectButton.Text = "위치 선택"
SelectButton.TextColor3 = Color3.new(1,1,1)
SelectButton.TextSize = 16
SelectButton.Font = Enum.Font.GothamBold
SelectButton.Parent = Main
Instance.new("UICorner", SelectButton).CornerRadius = UDim.new(0, 11)

local StartButton = Instance.new("TextButton")
StartButton.Size = UDim2.new(1, -30, 0, 48)
StartButton.Position = UDim2.fromOffset(15, 199)
StartButton.BackgroundColor3 = Color3.fromRGB(60, 65, 75)
StartButton.BorderSizePixel = 0
StartButton.Text = "생성 시작"
StartButton.TextColor3 = Color3.fromRGB(155, 158, 168)
StartButton.TextSize = 16
StartButton.Font = Enum.Font.GothamBold
StartButton.AutoButtonColor = false
StartButton.Parent = Main
Instance.new("UICorner", StartButton).CornerRadius = UDim.new(0, 11)

local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
Title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
    end
end)
Title.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        local d = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

local Selecting = false
local Running = false
local SelectedWorldCFrame
local Marker

local function setStatus(text) Status.Text = text end
local function setStartEnabled(enabled)
    StartButton.AutoButtonColor = enabled
    if enabled then
        StartButton.BackgroundColor3 = Color3.fromRGB(46, 170, 104)
        StartButton.TextColor3 = Color3.new(1,1,1)
    else
        StartButton.BackgroundColor3 = Color3.fromRGB(60, 65, 75)
        StartButton.TextColor3 = Color3.fromRGB(155, 158, 168)
    end
end

local function createMarker(cframe)
    if Marker then Marker:Destroy() end
    Marker = Instance.new("Part")
    Marker.Name = "BABFTVideoSelectionMarker"
    Marker.Anchored = true
    Marker.CanCollide = false
    Marker.CanQuery = false
    Marker.CanTouch = false
    Marker.Material = Enum.Material.Neon
    Marker.Color = Color3.fromRGB(0, 230, 255)
    Marker.Transparency = 0.35
    Marker.Size = Vector3.new((WIDTH-1)*DISPLAY_SPACING_X+2, (HEIGHT-1)*DISPLAY_SPACING_Y+2, 0.2)
    Marker.CFrame = cframe * CFrame.new((WIDTH-1)*DISPLAY_SPACING_X/2, (HEIGHT-1)*DISPLAY_SPACING_Y/2, 0)
    Marker.Parent = Workspace
end

local function choosePosition(screenPosition)
    local ray = Camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local exclude = {}
    if Player.Character then table.insert(exclude, Player.Character) end
    if Marker then table.insert(exclude, Marker) end
    params.FilterDescendantsInstances = exclude
    local result = Workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
    if not result then
        setStatus("위치 감지 실패\n바닥이나 벽을 다시 누르세요.")
        return
    end

    local position = result.Position + result.Normal
    position = Vector3.new(math.round(position.X), math.round(position.Y*10)/10, math.round(position.Z))

    local right = Camera.CFrame.RightVector
    right = Vector3.new(right.X, 0, right.Z)
    right = right.Magnitude < 0.1 and Vector3.new(1,0,0) or right.Unit
    local up = Vector3.new(0,1,0)
    local back = right:Cross(up)
    back = back.Magnitude < 0.1 and Vector3.new(0,0,1) or back.Unit

    SelectedWorldCFrame = CFrame.fromMatrix(position, right, up, back)
    Selecting = false
    createMarker(SelectedWorldCFrame)
    setStartEnabled(true)
    setStatus(string.format("위치 선택 완료\nX %.1f / Y %.1f / Z %.1f", position.X, position.Y, position.Z))
    SelectButton.Text = "위치 다시 선택"
end

SelectButton.MouseButton1Click:Connect(function()
    if Running then return end
    Selecting = true
    setStatus("창 밖에서 화면 좌하단 위치를 누르세요.")
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed or not Selecting or Running then return end
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        choosePosition(input.Position)
    end
end)

local function fail(message)
    setStatus(message)
    Running = false
    StartButton.Text = "실패"
end

local function buildTest()
    if Running or not SelectedWorldCFrame then return end
    Running = true
    setStartEnabled(false)
    StartButton.Text = "생성 중..."

    local BuildingTool = findTool("BuildingTool")
    local PaintingTool = findTool("PaintingTool")
    local BindTool = findTool("BindTool")
    local PropertiesTool = findTool("PropertiesTool")
    if not BuildingTool then return fail("BuildingTool을 찾지 못했습니다.") end
    if not PaintingTool then return fail("PaintingTool을 찾지 못했습니다.") end
    if not BindTool then return fail("BindTool을 찾지 못했습니다.") end
    if not PropertiesTool then return fail("PropertiesTool을 찾지 못했습니다.") end

    local BuildRF = BuildingTool:WaitForChild("RF")
    local PaintRF = PaintingTool:WaitForChild("RF")
    local BindRF = BindTool:WaitForChild("RF")
    local PropertyRF = PropertiesTool:WaitForChild("SetPropertieRF")

    local Displays = {}
    local displayList = {}
    local total = WIDTH * HEIGHT

    for y = 1, HEIGHT do
        Displays[y] = {}
        for x = 1, WIDTH do
            local index = (y-1)*WIDTH + x
            setStatus(string.format("DisplayBlock 생성 중\n%d / %d", index, total))
            local worldCFrame = SelectedWorldCFrame * CFrame.new((x-1)*DISPLAY_SPACING_X, (HEIGHT-y)*DISPLAY_SPACING_Y, 0)
            local display, err = installBlock(BuildRF, "DisplayBlock", DISPLAY_ID, worldCFrame)
            if not display then return fail("Display 생성 실패\n" .. tostring(err)) end
            Displays[y][x] = display
            table.insert(displayList, display)
            task.wait(0.06)
        end
    end

    local delayBase = SelectedWorldCFrame * CFrame.new(WIDTH*DISPLAY_SPACING_X + 5, 0, 0)
    setStatus("흰색 Delay 생성 중")
    local whiteDelay, err1 = installBlock(BuildRF, "Delay", DELAY_ID, delayBase)
    if not whiteDelay then return fail("흰색 Delay 생성 실패\n" .. tostring(err1)) end

    setStatus("검은색 Delay 생성 중")
    local blackDelay, err2 = installBlock(BuildRF, "Delay", DELAY_ID, delayBase * CFrame.new(0, 0, -DELAY_SPACING))
    if not blackDelay then return fail("검은색 Delay 생성 실패\n" .. tostring(err2)) end

    setStatus("Delay 색상 설정 중")
    local paintOk, paintErr = paintBlocks(PaintRF, {{whiteDelay, WHITE}, {blackDelay, BLACK}})
    if not paintOk then return fail("색칠 실패\n" .. tostring(paintErr)) end

    setStatus("Delay 시간 0.33초 설정 중")
    local propOk, propErr = setDelayTime(PropertyRF, {whiteDelay, blackDelay}, "0.33")
    if not propOk then return fail("Delay 시간 설정 실패\n" .. tostring(propErr)) end

    local whiteDisplays, blackDisplays = {}, {}
    for y = 1, HEIGHT do
        for x = 1, WIDTH do
            if (x+y)%2 == 0 then
                table.insert(whiteDisplays, Displays[y][x])
            else
                table.insert(blackDisplays, Displays[y][x])
            end
        end
    end

    setStatus("흰색 Display 32개 연결 중")
    local wOk, wErr, wCount = bindDisplays(BindRF, whiteDelay, whiteDisplays)
    if not wOk then return fail("흰색 연결 실패\n" .. tostring(wErr)) end

    setStatus("검은색 Display 32개 연결 중")
    local bOk, bErr, bCount = bindDisplays(BindRF, blackDelay, blackDisplays)
    if not bOk then return fail("검은색 연결 실패\n" .. tostring(bErr)) end

    getgenv().BABFTVideoConnectionTest = {
        Displays = Displays,
        DisplayList = displayList,
        WhiteDelay = whiteDelay,
        BlackDelay = blackDelay,
        WhiteDisplays = whiteDisplays,
        BlackDisplays = blackDisplays,
        BaseCFrame = SelectedWorldCFrame
    }

    if Marker then Marker:Destroy() Marker = nil end
    setStatus(string.format("생성 및 연결 완료\nDisplay %d | 흰색 %d | 검은색 %d", #displayList, wCount or 0, bCount or 0))
    StartButton.Text = "완료"
    StartButton.BackgroundColor3 = Color3.fromRGB(46, 170, 104)
    StartButton.TextColor3 = Color3.new(1,1,1)
    Running = false

    print("BABFT 연결 테스트 완료")
    print("흰색 Delay:", whiteDelay:GetFullName())
    print("검은색 Delay:", blackDelay:GetFullName())
    print("두 Delay를 각각 작동시켜 체크무늬가 출력되는지 확인하세요.")
end

StartButton.MouseButton1Click:Connect(function()
    if not SelectedWorldCFrame then
        setStatus("먼저 위치를 선택하세요.")
        return
    end
    task.spawn(buildTest)
end)

Close.MouseButton1Click:Connect(function()
    Selecting = false
    if Marker then Marker:Destroy() end
    Gui:Destroy()
end)

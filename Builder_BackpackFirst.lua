local Players = game:GetService("Players")

local Context = getgenv().BABFT_CALCULATOR
local Config = Context.Config
local Utils = Context.Modules.Utils
local Inventory = Context.Modules.Inventory
local WhiteZone = Context.Modules.WhiteZone

local Builder = {}

local LocalPlayer = Players.LocalPlayer

Builder.CurrentName = "UNKNOWN"
Builder.PlaceIndex = 0
Builder.LastInvokeDebug = ""

local function copyText(text)
	if setclipboard then
		setclipboard(text)
	elseif toclipboard then
		toclipboard(text)
	end
end

local function getBuildingRemote()
	local backpack = LocalPlayer:WaitForChild("Backpack")

	local tool = backpack:FindFirstChild(
		Config.Tools.BuildingTool
	)

	if tool then
		local remote = tool:FindFirstChild("RF")

		if remote then
			return remote
		end
	end

	local character = LocalPlayer.Character

	if character then
		tool = character:FindFirstChild(
			Config.Tools.BuildingTool
		)

		if tool then
			local remote = tool:FindFirstChild("RF")

			if remote then
				return remote
			end
		end
	end

	error("BuildingTool.RF를 찾을 수 없습니다.")
end

local function resolveInventoryValue(blockType)
	if Inventory and Inventory.Get then
		return Inventory.Get(blockType)
	end

	local value = Config.Inventory[blockType]

	assert(
		type(value) == "number" and value > 0,
		"보유량 값 오류: " .. tostring(blockType)
	)

	return value
end

local function getObjectPosition(object)
	if not object then
		return nil
	end

	if object:IsA("BasePart") then
		return object.Position
	end

	if object:IsA("Model") then
		local success, pivot = pcall(function()
			return object:GetPivot()
		end)

		if success then
			return pivot.Position
		end
	end

	local part = object:FindFirstChildWhichIsA(
		"BasePart",
		true
	)

	return part and part.Position or nil
end

local function takeSnapshot(folder)
	local snapshot = {}

	for _, object in ipairs(folder:GetChildren()) do
		snapshot[object] = true
	end

	return snapshot
end

local function collectNewObjects(folder, snapshot)
	local objects = {}

	for _, object in ipairs(folder:GetChildren()) do
		if not snapshot[object] then
			objects[#objects + 1] = object
		end
	end

	return objects
end

local function chooseCreatedObject(
	objects,
	blockName,
	targetPosition
)
	local nearestMatching = nil
	local nearestMatchingDistance = math.huge

	local nearestAny = nil
	local nearestAnyDistance = math.huge

	for _, object in ipairs(objects) do
		if object and object.Parent then
			local position = getObjectPosition(object)

			if object.Name == blockName then
				if position then
					local distance =
						(position - targetPosition).Magnitude

					if distance < nearestMatchingDistance then
						nearestMatching = object
						nearestMatchingDistance = distance
					end
				elseif not nearestMatching then
					nearestMatching = object
				end
			end

			if position then
				local distance =
					(position - targetPosition).Magnitude

				if distance < nearestAnyDistance then
					nearestAny = object
					nearestAnyDistance = distance
				end
			elseif not nearestAny then
				nearestAny = object
			end
		end
	end

	return nearestMatching or nearestAny
end

local function formatInvokeResult(result)
	if typeof(result) == "Instance" then
		return result:GetFullName()
	end

	if type(result) == "table" then
		local parts = {}

		for key, value in pairs(result) do
			parts[#parts + 1] =
				tostring(key)
				.. "="
				.. tostring(value)
		end

		return "{"
			.. table.concat(parts, ", ")
			.. "}"
	end

	return tostring(result)
end

local function createInvokeDebug(
	blockName,
	inventoryValue,
	zone,
	zoneCFrame,
	worldCFrame,
	invokeSuccess,
	invokeResult,
	beforeCount
)
	local resultText = formatInvokeResult(
		invokeResult
	)

	return table.concat({
		"[BABFT InvokeServer 결과]",
		"순서: " .. tostring(Builder.PlaceIndex),
		"등록 이름: " .. tostring(Builder.CurrentName),
		"블록 종류: " .. tostring(blockName),
		"보유량 인자: " .. tostring(inventoryValue),
		"WhiteZone: " .. tostring(zone),
		"성공: " .. tostring(invokeSuccess),
		"반환 타입: " .. typeof(invokeResult),
		"반환값: " .. resultText,
		"설치 전 개수: " .. tostring(beforeCount),

		string.format(
			"World 좌표: %.3f, %.3f, %.3f",
			worldCFrame.Position.X,
			worldCFrame.Position.Y,
			worldCFrame.Position.Z
		),

		string.format(
			"Zone 좌표: %.3f, %.3f, %.3f",
			zoneCFrame.Position.X,
			zoneCFrame.Position.Y,
			zoneCFrame.Position.Z
		)
	}, "\n")
end

local function buildDiagnostic(
	folder,
	blockName,
	worldCFrame,
	beforeCount,
	afterCount,
	addedObjects,
	invokeDebug
)
	local lines = {
		"[BABFT Builder 진단]",
		"순서: " .. tostring(Builder.PlaceIndex),
		"등록 이름: " .. tostring(Builder.CurrentName),
		"블록 종류: " .. tostring(blockName),
		"설치 전 개수: " .. tostring(beforeCount),
		"설치 후 개수: " .. tostring(afterCount),

		string.format(
			"요청 좌표: %.2f, %.2f, %.2f",
			worldCFrame.Position.X,
			worldCFrame.Position.Y,
			worldCFrame.Position.Z
		),

		"ChildAdded 감지 수: "
			.. tostring(#addedObjects),

		"",
		invokeDebug,
		"",
		"ChildAdded 목록:"
	}

	for index, object in ipairs(addedObjects) do
		local fullName = "삭제됨"

		if object and object.Parent then
			fullName = object:GetFullName()
		end

		lines[#lines + 1] = string.format(
			"%d. %s | %s",
			index,
			object and object.Name or "nil",
			fullName
		)
	end

	lines[#lines + 1] = ""
	lines[#lines + 1] =
		"현재 플레이어 블록 목록:"

	for index, object in ipairs(folder:GetChildren()) do
		lines[#lines + 1] = string.format(
			"%d. %s | %s",
			index,
			object.Name,
			object:GetFullName()
		)
	end

	return table.concat(lines, "\n")
end

function Builder.PlaceBlock(blockType, worldCFrame)
	assert(
		typeof(worldCFrame) == "CFrame",
		"worldCFrame은 CFrame이어야 합니다."
	)

	if Utils.IsCancelled() then
		return nil, "사용자가 중단했습니다."
	end

	Builder.PlaceIndex += 1

	local folder = Utils.GetBlocksFolder()

	local blockName =
		Config.BlockNames[blockType]
		or blockType

	local snapshot = takeSnapshot(folder)
	local beforeCount = #folder:GetChildren()
	local addedObjects = {}

	local childConnection =
		folder.ChildAdded:Connect(function(object)
			addedObjects[#addedObjects + 1] =
				object

		end)

	local remote = getBuildingRemote()

	local inventoryValue =
		resolveInventoryValue(blockType)

	local zone =
		WhiteZone
		and WhiteZone.Get
		and WhiteZone.Get()
		or Utils.GetWhiteZone()

	assert(
		zone,
		"WhiteZone을 찾을 수 없습니다."
	)

	local zoneCFrame =
		WhiteZone
		and WhiteZone.WorldToZone
		and WhiteZone.WorldToZone(worldCFrame)
		or Utils.WorldToZoneCFrame(worldCFrame)

	local invokeSuccess, invokeResult =
		pcall(function()
			return remote:InvokeServer(
				blockName,
				inventoryValue,
				zone,
				zoneCFrame,
				true,
				worldCFrame,
				false
			)
		end)

	local invokeDebug = createInvokeDebug(
		blockName,
		inventoryValue,
		zone,
		zoneCFrame,
		worldCFrame,
		invokeSuccess,
		invokeResult,
		beforeCount
	)

	Builder.LastInvokeDebug = invokeDebug

	if not invokeSuccess then
		copyText(invokeDebug)
		warn(invokeDebug)
		childConnection:Disconnect()

		local errorText =
			invokeDebug
			.. "\n\n블록 설치 리모트 호출 실패"

		copyText(errorText)

		return nil, errorText
	end

	if typeof(invokeResult) == "Instance"
		and invokeResult.Parent
		and not snapshot[invokeResult] then

		childConnection:Disconnect()

		Context.Statistics.BlocksPlaced += 1

		return invokeResult
	end

	local created = nil

	local deadline =
		os.clock()
		+ (Config.InstallTimeout or 7)

	repeat
		if Utils.IsCancelled() then
			childConnection:Disconnect()

			return nil,
				"사용자가 중단했습니다."
		end

		local candidates = {}

		for _, object in ipairs(addedObjects) do
			if object
				and object.Parent
				and not snapshot[object] then

				candidates[#candidates + 1] =
					object
			end
		end

		local currentNewObjects =
			collectNewObjects(
				folder,
				snapshot
			)

		for _, object in ipairs(currentNewObjects) do
			if not table.find(
				candidates,
				object
			) then

				candidates[#candidates + 1] =
					object
			end
		end

		created = chooseCreatedObject(
			candidates,
			blockName,
			worldCFrame.Position
		)

		if created then
			break
		end

		task.wait(0.02)
	until os.clock() >= deadline

	childConnection:Disconnect()

	if not created then
		local afterCount =
			#folder:GetChildren()

		local diagnostic = buildDiagnostic(
			folder,
			blockName,
			worldCFrame,
			beforeCount,
			afterCount,
			addedObjects,
			invokeDebug
		)

		copyText(diagnostic)
		warn(diagnostic)

		return nil,
			"생성된 블록을 찾지 못했습니다: "
			.. blockName
			.. "\n진단 결과를 클립보드에 복사했습니다."
	end

	Context.Statistics.BlocksPlaced += 1

	return created
end

function Builder.PlaceNamedBlock(
	name,
	blockType,
	worldCFrame
)
	assert(
		type(name) == "string"
			and name ~= "",
		"등록 이름이 필요합니다."
	)

	Builder.CurrentName = name

	local object, errorMessage =
		Builder.PlaceBlock(
			blockType,
			worldCFrame
		)

	if not object then
		error(errorMessage)
	end

	Context:RegisterObject(
		name,
		object
	)

	return object
end

function Builder.PlaceMany(list)
	assert(
		type(list) == "table",
		"설치 목록은 테이블이어야 합니다."
	)

	local created = {}
	local total = #list

	for index, data in ipairs(list) do
		if Utils.IsCancelled() then
			break
		end

		local cframe =
			data.CFrame
			or (
				typeof(data.Position)
					== "Vector3"
				and CFrame.new(data.Position)
			)

		assert(
			typeof(cframe) == "CFrame",
			"CFrame 누락: "
				.. tostring(data.Name)
		)

		Utils.SetTask(
			"블록 설치: "
				.. tostring(data.Name),
			total > 0
				and index / total
				or 1
		)

		local object =
			Builder.PlaceNamedBlock(
				data.Name,
				data.Type,
				cframe
			)

		created[#created + 1] =
			object

		if data.GateType then
			Context:QueueProperty({
				Type = data.GateType,
				Gate = object
			})
		end

		if data.Color then
			Context:QueuePaint({
				Object = object,
				Color = data.Color
			})
		end

		task.wait(
			Config.PlaceDelay or 0
		)
	end

	return created
end

function Builder.Find(name)
	return Context:GetObject(name)
end

function Builder.Exists(name)
	local object =
		Context:GetObject(name)

	return object ~= nil
		and object.Parent ~= nil
end

function Builder.Require(name)
	local object =
		Context:GetObject(name)

	assert(
		object and object.Parent,
		"등록된 블록 없음: "
			.. tostring(name)
	)

	return object
end

function Builder.Unregister(name)
	local object =
		Context.NamedObjects[name]

	Context.NamedObjects[name] = nil

	return object
end

function Builder.ClearRegistry()
	table.clear(
		Context.NamedObjects
	)
end

Context.Modules.Builder = Builder

return Builder

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local camera = Workspace.CurrentCamera

-- CONFIGURATION -----------------------------------------
local SPEED_BASE = 25  
local SPEED_BOOST = 100 
local SPEED_GMODE = 200 
local SPEED_WARP = 1000 
local MAX_IDLE_SPEED = 40
local ACCEL_SPEED = 0.06 

local FOV_NORMAL = 70
local FOV_MAX = 120 -- Expanded for high-speed effect
local ROTATION_RESPONSIVENESS = 15 
local BANK_ANGLE = 35 
local PITCH_ANGLE = 15 

-- ASSET IDS (Replace with your IDs)
local ANIM_IDLE_ID = "rbxassetid://93326430026112" 
local ANIM_FLY_ID = "rbxassetid://93681287985936"  
local ANIM_DESCEND_ID = "rbxassetid://78487249533001" 
local ANIM_ASCEND_ID = "rbxassetid://114871503457855" -- <--- ADD YOUR ID HERE
local ANIM_LAND_ID = "rbxassetid://112472797825991" 
local BOOM_SOUND_ID = "rbxassetid://9120769331" 
local WIND_SOUND_ID = "rbxassetid://93035214379043" 

local SHIRT_ID = "rbxassetid://86956423395949" -- <--- ADD YOUR ID HERE
local PANTS_ID = "rbxassetid://130491833787584" -- <--- ADD YOUR ID HERE

-- KEYS
local TOGGLE_KEY = Enum.KeyCode.H
local BOOST_KEY = Enum.KeyCode.Space
local G_KEY = Enum.KeyCode.C         
local WARP_KEY = Enum.KeyCode.V      
local DOWN_KEY = Enum.KeyCode.Q
local UP_KEY = Enum.KeyCode.E
local FREELOOK_KEY = Enum.KeyCode.RightAlt 
----------------------------------------------------------

local isFlying = false
local isBoosting = false
local isLanding = false 
local isFreeLooking = false 
local currentSpeed = 0 
local currentBank = 0 

local loadedIdleAnim, loadedFlyAnim, loadedLandAnim, loadedDescendAnim, loadedAscendAnim
local boomSound, windSound
local speedGui, speedLabel, idleSpeedBox

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- Appearance Function
local function updateAppearance()
	local shirt = character:FindFirstChildOfClass("Shirt") or Instance.new("Shirt", character)
	local pants = character:FindFirstChildOfClass("Pants") or Instance.new("Pants", character)

	shirt.ShirtTemplate = SHIRT_ID
	shirt.Color3 = Color3.fromRGB(255, 255, 255) -- Set to White

	pants.PantsTemplate = PANTS_ID
	pants.Color3 = Color3.fromRGB(255, 255, 255) -- Set to White
end

local function setupUI()
	local existing = player.PlayerGui:FindFirstChild("FlyStats")
	if existing then existing:Destroy() end

	speedGui = Instance.new("ScreenGui")
	speedGui.Name = "FlyStats"
	speedGui.ResetOnSpawn = false
	speedGui.Enabled = false

	speedLabel = Instance.new("TextLabel")
	speedLabel.Size = UDim2.new(0, 250, 0, 50)
	speedLabel.Position = UDim2.new(0.5, -125, 0.85, 0)
	speedLabel.BackgroundTransparency = 1
	speedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	speedLabel.Font = Enum.Font.GothamBold
	speedLabel.TextSize = 22
	speedLabel.Parent = speedGui

	local controlFrame = Instance.new("Frame")
	controlFrame.Size = UDim2.new(0, 120, 0, 60)
	controlFrame.Position = UDim2.new(0, 20, 0.5, -30)
	controlFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	controlFrame.BackgroundTransparency = 0.5
	controlFrame.Parent = speedGui
	Instance.new("UICorner", controlFrame)

	idleSpeedBox = Instance.new("TextBox")
	idleSpeedBox.Size = UDim2.new(0.8, 0, 0, 25)
	idleSpeedBox.Position = UDim2.new(0.1, 0, 0.45, 0)
	idleSpeedBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	idleSpeedBox.TextColor3 = Color3.fromRGB(0, 255, 150)
	idleSpeedBox.Text = tostring(SPEED_BASE)
	idleSpeedBox.Font = Enum.Font.GothamBold
	idleSpeedBox.Parent = controlFrame

	idleSpeedBox.FocusLost:Connect(function()
		local val = tonumber(idleSpeedBox.Text)
		if val then SPEED_BASE = math.clamp(val, 0, MAX_IDLE_SPEED) end
		idleSpeedBox.Text = tostring(SPEED_BASE)
	end)

	speedGui.Parent = player:WaitForChild("PlayerGui")
end

local function setupAssets()
	local animator = humanoid:FindFirstChild("Animator") or humanoid:WaitForChild("Animator")

	local function load(id, prio)
		local a = Instance.new("Animation")
		a.AnimationId = id
		local track = animator:LoadAnimation(a)
		track.Priority = prio
		return track
	end

	loadedIdleAnim = load(ANIM_IDLE_ID, Enum.AnimationPriority.Action)
	loadedFlyAnim = load(ANIM_FLY_ID, Enum.AnimationPriority.Action)
	loadedDescendAnim = load(ANIM_DESCEND_ID, Enum.AnimationPriority.Action2)
	loadedAscendAnim = load(ANIM_ASCEND_ID, Enum.AnimationPriority.Action2)
	loadedLandAnim = load(ANIM_LAND_ID, Enum.AnimationPriority.Action4)

	boomSound = Instance.new("Sound", rootPart)
	boomSound.SoundId = BOOM_SOUND_ID
	boomSound.Volume = 0.5

	windSound = Instance.new("Sound", rootPart)
	windSound.SoundId = WIND_SOUND_ID
	windSound.Looped = true
	windSound.Volume = 0
end

setupAssets()
setupUI()

local function toggleFlight(forceOff)
	if forceOff then isFlying = false else isFlying = not isFlying end
	speedGui.Enabled = isFlying
	isFreeLooking = false 
	rayParams.FilterDescendantsInstances = {character}

	if isFlying then
		updateAppearance()
		humanoid.PlatformStand = true
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		windSound:Play()

		local attachment = Instance.new("Attachment", rootPart)
		attachment.Name = "FlyAttachment"

		local lv = Instance.new("LinearVelocity", rootPart)
		lv.Name = "FlyVelocity"
		lv.Attachment0 = attachment
		lv.MaxForce = 9999999

		local ao = Instance.new("AlignOrientation", rootPart)
		ao.Name = "FlyGyro"
		ao.Attachment0 = attachment
		ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
		ao.Responsiveness = ROTATION_RESPONSIVENESS
		ao.MaxTorque = 9999999

		loadedIdleAnim:Play(0.3)
	else
		windSound:Stop()
		camera.FieldOfView = FOV_NORMAL -- Reset FOV on land
		if rootPart:FindFirstChild("FlyVelocity") then rootPart.FlyVelocity:Destroy() end
		if rootPart:FindFirstChild("FlyGyro") then rootPart.FlyGyro:Destroy() end
		if rootPart:FindFirstChild("FlyAttachment") then rootPart.FlyAttachment:Destroy() end

		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		loadedIdleAnim:Stop()
		loadedFlyAnim:Stop()
		loadedDescendAnim:Stop()
		loadedAscendAnim:Stop()
		rootPart.CFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, math.rad(rootPart.Orientation.Y), 0)
	end
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == TOGGLE_KEY then toggleFlight() end

	if input.KeyCode == FREELOOK_KEY and isFlying then
		isFreeLooking = not isFreeLooking
	end

	if input.KeyCode == BOOST_KEY and isFlying then 
		isBoosting = true 
		boomSound:Play()
	end
	if input.KeyCode == G_KEY and isFlying and isBoosting then
		boomSound:Play()
	end
	if input.KeyCode == WARP_KEY and isFlying and isBoosting then
		boomSound:Play()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == BOOST_KEY then isBoosting = false end
end)

RunService.RenderStepped:Connect(function(dt)
	if not isFlying or isLanding then return end

	local lv = rootPart:FindFirstChild("FlyVelocity")
	local ao = rootPart:FindFirstChild("FlyGyro")
	if not lv or not ao then return end

	local moveVector = Vector3.zero
	local camCFrame = camera.CFrame
	local targetBank = 0

	-- Movement Inputs
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector += camCFrame.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector -= camCFrame.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector -= camCFrame.RightVector targetBank += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector += camCFrame.RightVector targetBank -= 1 end
	if UserInputService:IsKeyDown(UP_KEY) then moveVector += Vector3.new(0, 1, 0) end
	if UserInputService:IsKeyDown(DOWN_KEY) then moveVector += Vector3.new(0, -1, 0) end -- FIXED: Now moves Down

	local isMoving = moveVector.Magnitude > 0
	local isAscending = UserInputService:IsKeyDown(UP_KEY)
	local isDescending = UserInputService:IsKeyDown(DOWN_KEY)
	local isGMode = isBoosting and UserInputService:IsKeyDown(G_KEY)
	local isWarping = isBoosting and UserInputService:IsKeyDown(WARP_KEY)

	-- Speed Logic
	local targetSpeed = 0
	if isMoving then
		if isBoosting then
			if isWarping then targetSpeed = SPEED_WARP
			elseif isGMode then targetSpeed = SPEED_GMODE
			else targetSpeed = SPEED_BOOST end -- Handles Space + E at 100 Speed
		else
			targetSpeed = SPEED_BASE
		end
		moveVector = moveVector.Unit
	end

	currentSpeed = currentSpeed + (targetSpeed - currentSpeed) * ACCEL_SPEED
	currentBank = currentBank + (targetBank - currentBank) * 0.1 

	lv.VectorVelocity = moveVector * currentSpeed

	-- FOV CHANGE LOGIC (Based on Speed)
	local fovPercent = math.clamp(currentSpeed / SPEED_WARP, 0, 1)
	camera.FieldOfView = FOV_NORMAL + ((FOV_MAX - FOV_NORMAL) * fovPercent)

	-- ROTATION LOGIC
	local bankAngle = math.rad(currentBank * BANK_ANGLE)
	local pitchAngle = math.rad(-(currentSpeed / SPEED_WARP) * PITCH_ANGLE)

	if isFreeLooking then
		if isMoving then
			local targetRotation = CFrame.lookAt(rootPart.Position, rootPart.Position + moveVector)
			ao.CFrame = targetRotation * CFrame.Angles(pitchAngle, 0, bankAngle)
		else
			ao.CFrame = ao.CFrame:Lerp(CFrame.new(rootPart.Position) * rootPart.CFrame.Rotation * CFrame.Angles(pitchAngle, 0, bankAngle), 0.1)
		end
	else
		local targetRotation = CFrame.lookAt(rootPart.Position, rootPart.Position + camCFrame.LookVector)
		ao.CFrame = targetRotation * CFrame.Angles(pitchAngle, 0, bankAngle)
	end

	-- Landing check
	local groundRay = workspace:Raycast(rootPart.Position, Vector3.new(0, -8, 0), rayParams)
	if groundRay and isGMode then
		isLanding = true
		toggleFlight(true) 
		loadedLandAnim:Play()
		task.delay(3, function() 
			loadedLandAnim:Stop(0.5) 
			isLanding = false 
		end)
		return
	end

	-- Animation Controller
	if isAscending and isBoosting then
		if not loadedAscendAnim.IsPlaying then
			loadedIdleAnim:Stop(0.2)
			loadedFlyAnim:Stop(0.2)
			loadedDescendAnim:Stop(0.2)
			loadedAscendAnim:Play(0.2)
		end
	elseif isDescending and not isBoosting then
		if not loadedDescendAnim.IsPlaying then
			loadedIdleAnim:Stop(0.2)
			loadedFlyAnim:Stop(0.2)
			loadedAscendAnim:Stop(0.2)
			loadedDescendAnim:Play(0.2)
		end
	else
		if loadedDescendAnim.IsPlaying then loadedDescendAnim:Stop(0.2) end
		if loadedAscendAnim.IsPlaying then loadedAscendAnim:Stop(0.2) end
		if isMoving and isBoosting then
			if not loadedFlyAnim.IsPlaying then loadedIdleAnim:Stop(0.4) loadedFlyAnim:Play(0.4) end
		else
			if not loadedIdleAnim.IsPlaying then loadedFlyAnim:Stop(0.4) loadedIdleAnim:Play(0.4) end
		end
	end

	-- HUD Updates
	local status = isFreeLooking and "[FREE LOOK] " or ""
	speedLabel.Text = status .. "SPD: " .. math.floor(currentSpeed)
	speedLabel.TextColor3 = isFreeLooking and Color3.fromRGB(150, 200, 255) or Color3.fromRGB(255, 255, 255)
end)

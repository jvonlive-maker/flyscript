--[[
    OMNI-FLIGHT CONTROLLER (Ultimate Version - No Auto-Land)
    Style: Heavy Physics, Impactful, High-Speed
    Author: Gemini
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

-- References
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local camera = Workspace.CurrentCamera

-- CONFIGURATION
local SETTINGS = {
	SPEED = {
		BASE = 0, 
		HOVER = 25,
		BOOST = 150,
		GMODE = 300,
		WARP = 1200,
		ACCEL = 5,     -- Units per second acceleration
		DECEL = 6,     -- Drag when stopping
	},
	FOV = {
		NORMAL = 70,
		MAX = 130,
	},
	PHYSICS = {
		ROTATION_SPEED = 20, 
		BANK_MAX = 50,       
		PITCH_MAX = 5,      
	},
	IDS = {
		IDLE = "rbxassetid://93326430026112", 
		FLY = "rbxassetid://101291673584393",
		DESCEND = "rbxassetid://93326430026112",
		ASCEND = "rbxassetid://93326430026112",
		-- Audio
		BOOM = "rbxassetid://9120769331",
		WIND = "rbxassetid://93035214379043",
		-- Apparel
		SHIRT = "rbxassetid://86956423395949",
		PANTS = "rbxassetid://130491833787584"
	},
	KEYS = {
		TOGGLE = Enum.KeyCode.H,
		BOOST = Enum.KeyCode.Space,
		GMODE = Enum.KeyCode.C,
		WARP = Enum.KeyCode.V,
		DOWN = Enum.KeyCode.Q,
		UP = Enum.KeyCode.E,
		FREELOOK = Enum.KeyCode.RightAlt
	}
}

-- STATE VARIABLES
local flightState = {
	Active = false,
	Boosting = false,
	FreeLook = false,
	CurrentSpeed = 0,
	TargetSpeed = 0,
	CurrentBank = 0,
	CurrentPitch = 0,
	MoveVector = Vector3.zero
}

local tracks = {}
local sounds = {}

-- HELPER FUNCTIONS
local function safeLoadAnimation(animator, id, name, priority)
	if not id or id == "" then return nil end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local success, track = pcall(function() return animator:LoadAnimation(animation) end)
	if success and track then
		if priority then track.Priority = priority end
		return track
	end
	return nil
end

local function setupAssets()
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	tracks.Idle = safeLoadAnimation(animator, SETTINGS.IDS.IDLE, "Idle", Enum.AnimationPriority.Idle)
	tracks.Fly = safeLoadAnimation(animator, SETTINGS.IDS.FLY, "Fly", Enum.AnimationPriority.Movement)
	tracks.Descend = safeLoadAnimation(animator, SETTINGS.IDS.DESCEND, "Descend", Enum.AnimationPriority.Action)
	tracks.Ascend = safeLoadAnimation(animator, SETTINGS.IDS.ASCEND, "Ascend", Enum.AnimationPriority.Action)

	if SETTINGS.IDS.BOOM ~= "" then
		sounds.Boom = Instance.new("Sound", rootPart)
		sounds.Boom.SoundId = SETTINGS.IDS.BOOM
		sounds.Boom.Volume = 0.8
	end
	if SETTINGS.IDS.WIND ~= "" then
		sounds.Wind = Instance.new("Sound", rootPart)
		sounds.Wind.SoundId = SETTINGS.IDS.WIND
		sounds.Wind.Looped = true
		sounds.Wind.Volume = 0
	end
end

local function updateAppearance()
	if SETTINGS.IDS.SHIRT ~= "" then
		local shirt = character:FindFirstChildOfClass("Shirt") or Instance.new("Shirt", character)
		shirt.ShirtTemplate = SETTINGS.IDS.SHIRT
	end
	if SETTINGS.IDS.PANTS ~= "" then
		local pants = character:FindFirstChildOfClass("Pants") or Instance.new("Pants", character)
		pants.PantsTemplate = SETTINGS.IDS.PANTS
	end
end

local function playExclusive(trackName, fadeTime)
	for name, track in pairs(tracks) do
		if name == trackName then
			if not track.IsPlaying then track:Play(fadeTime) end
		else
			if track.IsPlaying then track:Stop(fadeTime) end
		end
	end
end

local function stopAllTracks(fadeTime)
	for _, track in pairs(tracks) do
		if track.IsPlaying then track:Stop(fadeTime) end
	end
end

-- UI SETUP
local gui, mainFrame, speedLabel, speedBarBackground, speedBarFill

local function setupUI()
	local existing = player.PlayerGui:FindFirstChild("FlightHUD")
	if existing then existing:Destroy() end

	gui = Instance.new("ScreenGui")
	gui.Name = "FlightHUD"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = player.PlayerGui

	-- Container for all UI elements
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(0, 350, 0, 100)
	container.Position = UDim2.new(0.5, -175, 0.85, 0)
	container.BackgroundTransparency = 1
	container.Parent = gui

	-- Speed Number (Main Display)
	speedLabel = Instance.new("TextLabel")
	speedLabel.Name = "SpeedLabel"
	speedLabel.Size = UDim2.new(1, 0, 0, 40)
	speedLabel.Position = UDim2.new(0, 0, 0, 0)
	speedLabel.BackgroundTransparency = 1
	speedLabel.Font = Enum.Font.GothamBlack -- Thicker font for "Heavy" feel
	speedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	speedLabel.TextSize = 32
	speedLabel.Text = "000"
	speedLabel.Parent = container

	local speedSub = Instance.new("TextLabel", speedLabel)
	speedSub.Text = "VELOCITY"
	speedSub.Size = UDim2.new(1, 0, 0, 15)
	speedSub.Position = UDim2.new(0, 0, 1, -5)
	speedSub.BackgroundTransparency = 1
	speedSub.Font = Enum.Font.GothamBold
	speedSub.TextSize = 10
	speedSub.TextColor3 = Color3.fromRGB(200, 200, 200)

	-- Speed Bar Background
	speedBarBackground = Instance.new("Frame")
	speedBarBackground.Name = "BarBG"
	speedBarBackground.Size = UDim2.new(0.8, 0, 0, 4)
	speedBarBackground.Position = UDim2.new(0.1, 0, 0.8, 0)
	speedBarBackground.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	speedBarBackground.BackgroundTransparency = 0.8
	speedBarBackground.BorderSizePixel = 0
	speedBarBackground.Parent = container

	-- Speed Bar Fill
	speedBarFill = Instance.new("Frame")
	speedBarFill.Name = "BarFill"
	speedBarFill.Size = UDim2.new(0, 0, 1, 0) 
	speedBarFill.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
	speedBarFill.BorderSizePixel = 0
	speedBarFill.Parent = speedBarBackground

	-- Add Glow effect to fill
	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.Position = UDim2.new(0, -15, 0, -15)
	glow.Size = UDim2.new(1, 30, 1, 30)
	glow.Image = "rbxassetid://4996891965" -- Neon glow texture
	glow.ImageColor3 = Color3.fromRGB(0, 200, 255)
	glow.ImageTransparency = 0.5
	glow.Parent = speedBarFill

	-- Round the corners
	Instance.new("UICorner", speedBarBackground).CornerRadius = UDim.new(1, 0)
	Instance.new("UICorner", speedBarFill).CornerRadius = UDim.new(1, 0)
end
local function shakeCamera(intensity)
	local startTime = tick()
	local duration = 0.5
	task.spawn(function()
		while tick() - startTime < duration do
			local offset = Vector3.new(math.random()-0.5, math.random()-0.5, math.random()-0.5) * intensity
			camera.CFrame = camera.CFrame * CFrame.new(offset)
			RunService.RenderStepped:Wait()
		end
	end)
end

local function toggleFlight(forceOff)
	flightState.Active = forceOff and false or not flightState.Active
	gui.Enabled = flightState.Active

	if flightState.Active then
		updateAppearance()
		humanoid.PlatformStand = true
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		if sounds.Wind then sounds.Wind:Play() end

		local att = Instance.new("Attachment", rootPart)
		att.Name = "FlightAtt"

		local vel = Instance.new("LinearVelocity", rootPart)
		vel.Name = "FlightVel"
		vel.Attachment0 = att
		vel.MaxForce = math.huge
		vel.VectorVelocity = Vector3.zero 

		local gyro = Instance.new("AlignOrientation", rootPart)
		gyro.Name = "FlightGyro"
		gyro.Attachment0 = att
		gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
		gyro.Responsiveness = SETTINGS.PHYSICS.ROTATION_SPEED
		gyro.MaxTorque = math.huge

		playExclusive("Idle", 0.5)
		if sounds.Boom then sounds.Boom:Play() end
	else
		if sounds.Wind then sounds.Wind:Stop() end
		camera.FieldOfView = SETTINGS.FOV.NORMAL
		if rootPart:FindFirstChild("FlightVel") then rootPart.FlightVel:Destroy() end
		if rootPart:FindFirstChild("FlightGyro") then rootPart.FlightGyro:Destroy() end
		if rootPart:FindFirstChild("FlightAtt") then rootPart.FlightAtt:Destroy() end
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		stopAllTracks(0.2)
	end
end

-- INPUT
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == SETTINGS.KEYS.TOGGLE then
		toggleFlight()
	elseif input.KeyCode == SETTINGS.KEYS.BOOST and flightState.Active then
		flightState.Boosting = true
		if sounds.Boom then sounds.Boom:Play() end
		shakeCamera(0.5)
	elseif input.KeyCode == SETTINGS.KEYS.FREELOOK and flightState.Active then
		flightState.FreeLook = not flightState.FreeLook
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == SETTINGS.KEYS.BOOST then
		flightState.Boosting = false
	end
end)

-- PHYSICS LOOP
RunService.RenderStepped:Connect(function(dt)
	if not flightState.Active then return end

	local vel = rootPart:FindFirstChild("FlightVel")
	local gyro = rootPart:FindFirstChild("FlightGyro")
	if not vel or not gyro then return end

	-- Movement
	local rawInput = Vector3.zero
	local camCF = camera.CFrame
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then rawInput += camCF.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then rawInput -= camCF.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then rawInput -= camCF.RightVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then rawInput += camCF.RightVector end
	if UserInputService:IsKeyDown(SETTINGS.KEYS.UP) then rawInput += Vector3.new(0, 1, 0) end
	if UserInputService:IsKeyDown(SETTINGS.KEYS.DOWN) then rawInput += Vector3.new(0, -1, 0) end

	local isInputting = rawInput.Magnitude > 0
	if isInputting then rawInput = rawInput.Unit end

	-- Speed Calc
	local targetMax = 0
	if isInputting then
		if flightState.Boosting then
			if UserInputService:IsKeyDown(SETTINGS.KEYS.WARP) then targetMax = SETTINGS.SPEED.WARP
			elseif UserInputService:IsKeyDown(SETTINGS.KEYS.GMODE) then targetMax = SETTINGS.SPEED.GMODE
			else targetMax = SETTINGS.SPEED.BOOST end
		else
			targetMax = SETTINGS.SPEED.HOVER
		end
	end

	flightState.CurrentSpeed = math.lerp(flightState.CurrentSpeed, targetMax, 2 * dt)
	if isInputting then flightState.MoveVector = rawInput end
	vel.VectorVelocity = flightState.MoveVector * flightState.CurrentSpeed

	-- Visuals
	local speedRatio = math.clamp(flightState.CurrentSpeed / SETTINGS.SPEED.WARP, 0, 1)
	camera.FieldOfView = math.lerp(camera.FieldOfView, SETTINGS.FOV.NORMAL + ((SETTINGS.FOV.MAX - SETTINGS.FOV.NORMAL) * speedRatio), 5 * dt)
	if sounds.Wind then
		sounds.Wind.Volume = math.clamp(speedRatio * 3, 0, 2)
		sounds.Wind.PlaybackSpeed = 0.5 + (speedRatio * 1.5)
	end

	-- Rotation/Banking
	local targetBank = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then targetBank = 1 elseif UserInputService:IsKeyDown(Enum.KeyCode.D) then targetBank = -1 end
	flightState.CurrentBank = math.lerp(flightState.CurrentBank, targetBank * SETTINGS.PHYSICS.BANK_MAX, 4 * dt)

	local targetPitch = (isInputting and flightState.CurrentSpeed > 50) and (-SETTINGS.PHYSICS.PITCH_MAX * speedRatio) or 0
	flightState.CurrentPitch = math.lerp(flightState.CurrentPitch, targetPitch, 4 * dt)

	local lookDir = flightState.FreeLook and flightState.MoveVector or camCF.LookVector
	if lookDir.Magnitude < 0.01 then lookDir = rootPart.CFrame.LookVector end
	gyro.CFrame = CFrame.lookAt(Vector3.zero, lookDir) * CFrame.Angles(math.rad(flightState.CurrentPitch), 0, math.rad(flightState.CurrentBank))

	-- Animation Logic
	if UserInputService:IsKeyDown(SETTINGS.KEYS.UP) then playExclusive("Ascend", 0.2)
	elseif UserInputService:IsKeyDown(SETTINGS.KEYS.DOWN) then playExclusive("Descend", 0.2)
	elseif isInputting and flightState.CurrentSpeed > 60 then playExclusive("Fly", 0.3)
	else playExclusive("Idle", 0.3) end

	-- Updated UI Logic
	local displaySpeed = math.floor(flightState.CurrentSpeed)
	speedLabel.Text = tostring(displaySpeed)

	-- Calculate percentage based on Warp speed
	local speedPercent = math.clamp(flightState.CurrentSpeed / SETTINGS.SPEED.WARP, 0, 1)

	-- Animate the bar width smoothly
	speedBarFill:TweenSize(UDim2.new(speedPercent, 0, 1, 0), "Out", "Quad", 0.1, true)

	-- Visual Feedback: Change colors as you get faster
	if flightState.CurrentSpeed > SETTINGS.SPEED.GMODE then
		-- "Heat" color for high speeds
		local heatColor = Color3.fromRGB(255, 100, 0)
		speedBarFill.BackgroundColor3 = heatColor
		speedBarFill.Glow.ImageColor3 = heatColor
		speedLabel.TextColor3 = heatColor

		-- UI Shake at extreme speeds
		speedLabel.Position = UDim2.new(0, math.random(-2, 2), 0, math.random(-2, 2))
	elseif flightState.CurrentSpeed > SETTINGS.SPEED.BOOST then
		-- "Boost" color
		local boostColor = Color3.fromRGB(0, 255, 200)
		speedBarFill.BackgroundColor3 = boostColor
		speedBarFill.Glow.ImageColor3 = boostColor
		speedLabel.TextColor3 = Color3.new(1, 1, 1)
		speedLabel.Position = UDim2.new(0, 0, 0, 0)
	else
		-- Normal Flight
		speedBarFill.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
		speedBarFill.Glow.ImageColor3 = Color3.fromRGB(0, 180, 255)
		speedLabel.TextColor3 = Color3.new(1, 1, 1)
		speedLabel.Position = UDim2.new(0, 0, 0, 0)
	end
end)

setupAssets()
setupUI()

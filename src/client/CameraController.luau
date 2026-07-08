local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraController = {}
CameraController.__index = CameraController

local CAMERA_DISTANCE = 16
local CAMERA_HEIGHT = 4
local MIN_PITCH = math.rad(-60)
local MAX_PITCH = math.rad(40)
local MOUSE_SENSITIVITY = 0.0035
-- Calibrated for touchscreen — value from the targeting-upgrades branch
-- where this camera feel was tuned and tested.
local TOUCH_SENSITIVITY = 0.0055

function CameraController.new()
	local self = setmetatable({}, CameraController)
	self.player = Players.LocalPlayer
	self.camera = workspace.CurrentCamera
	self.yaw = 0
	self.pitch = math.rad(-15)
	self.mouseLook = false
	self.suspended = false
	self.activeTouch = nil
	self.lastTouchPos = nil
	self.connections = {}
	return self
end

-- AbilityCaster calls this with `true` while a drag-aim is in flight so the
-- camera doesn't rotate at the same time the player is steering an ability
-- indicator. Released back to false on aimEnd.
function CameraController:setSuspended(suspended)
	self.suspended = suspended
end

function CameraController:isMouseLook()
	return self.mouseLook
end

function CameraController:getYaw()
	return self.yaw
end

function CameraController:_setMouseLook(enabled)
	self.mouseLook = enabled
	if enabled then
		-- LockCurrentPosition (not LockCenter): pin the cursor where it already
		-- is while still reporting movement deltas. LockCenter under a Scriptable
		-- camera teleports the cursor to a screen corner when released — which is
		-- why the cursor jumped to the bottom-right after rotating.
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		UserInputService.MouseIconEnabled = false
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

function CameraController:start()
	self.camera.CameraType = Enum.CameraType.Scriptable

	table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:_setMouseLook(true)
		end
	end))

	table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:_setMouseLook(false)
		end
	end))

	table.insert(self.connections, UserInputService.InputChanged:Connect(function(input, processed)
		if processed or self.suspended then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement and self.mouseLook then
			self.yaw = self.yaw - input.Delta.X * MOUSE_SENSITIVITY
			self.pitch = math.clamp(self.pitch - input.Delta.Y * MOUSE_SENSITIVITY, MIN_PITCH, MAX_PITCH)
		end
	end))

	-- Tablet / mobile touch-look. Tracks a single specific touch (the first
	-- finger that touches outside the joystick zone) and rotates the camera
	-- by that finger's per-frame translation. This is the same approach the
	-- targeting-upgrades branch shipped — feels right because we ignore
	-- subsequent touches and only act on a deliberate single-finger drag.
	table.insert(self.connections, UserInputService.TouchStarted:Connect(function(input, processed)
		if processed or self.suspended then
			return
		end
		-- Bottom-left quadrant is reserved for the dynamic joystick — touches
		-- starting there move the character, not the camera.
		local viewport = workspace.CurrentCamera.ViewportSize
		if input.Position.X < viewport.X * 0.45 and input.Position.Y > viewport.Y * 0.45 then
			return
		end
		if not self.activeTouch then
			self.activeTouch = input
			self.lastTouchPos = input.Position
		end
	end))

	table.insert(self.connections, UserInputService.TouchMoved:Connect(function(input)
		if input == self.activeTouch and not self.suspended then
			local currentPos = input.Position
			if self.lastTouchPos then
				local delta = currentPos - self.lastTouchPos
				self.yaw = self.yaw - delta.X * TOUCH_SENSITIVITY
				self.pitch = math.clamp(self.pitch - delta.Y * TOUCH_SENSITIVITY, MIN_PITCH, MAX_PITCH)
			end
			self.lastTouchPos = currentPos
		end
	end))

	table.insert(self.connections, UserInputService.TouchEnded:Connect(function(input)
		if input == self.activeTouch then
			self.activeTouch = nil
			self.lastTouchPos = nil
		end
	end))

	table.insert(self.connections, RunService.RenderStepped:Connect(function()
		self:_update()
	end))
end

function CameraController:_update()
	-- Keep ownership of the camera. Roblox flips CameraType back to Custom on
	-- respawn, which wakes the default camera up again — then BOTH it and this
	-- controller rotate on right-click (the "insanely fast" double-spin) and
	-- fight over the mouse lock (cursor flicking to a corner on release).
	-- Re-asserting Scriptable each frame keeps the default camera suppressed.
	if self.camera.CameraType ~= Enum.CameraType.Scriptable then
		self.camera.CameraType = Enum.CameraType.Scriptable
	end

	local character = self.player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local pivot = root.Position + Vector3.new(0, CAMERA_HEIGHT, 0)
	local look = CFrame.fromOrientation(self.pitch, self.yaw, 0)
	local back = look:VectorToWorldSpace(Vector3.new(0, 0, CAMERA_DISTANCE))
	local cameraPos = pivot + back
	self.camera.CFrame = CFrame.lookAt(cameraPos, pivot)
end

-- Horizontal unit-vector the camera is facing (W direction).
function CameraController:getCameraForward()
	local cf = CFrame.fromOrientation(0, self.yaw, 0)
	return cf:VectorToWorldSpace(Vector3.new(0, 0, -1))
end

-- Ray from camera center forward, intersected with the y=groundY plane.
function CameraController:getGroundTarget(groundY)
	groundY = groundY or 0
	local origin = self.camera.CFrame.Position
	local forward = self.camera.CFrame.LookVector
	if math.abs(forward.Y) < 0.001 then
		return origin + forward * 60
	end
	local t = (groundY - origin.Y) / forward.Y
	if t < 0 then
		return origin + forward * 60
	end
	return origin + forward * t
end

function CameraController:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
	self.camera.CameraType = Enum.CameraType.Custom
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
end

return CameraController

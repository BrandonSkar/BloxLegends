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
-- TouchPan delta is pixel-scale rather than mouse-delta scale. Tuned lower
-- than the previous attempt — a single thumb-flick yields ~45° of yaw, which
-- is sane for orientation tweaks without overshooting.
local TOUCH_SENSITIVITY = 0.006

function CameraController.new()
	local self = setmetatable({}, CameraController)
	self.player = Players.LocalPlayer
	self.camera = workspace.CurrentCamera
	self.yaw = 0
	self.pitch = math.rad(-15)
	self.mouseLook = false
	self.suspended = false
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
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
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

	-- Touch: single-finger drag rotates the camera. We skip the gesture if:
	--   • `processed` is set (Roblox engine is already using the gesture for
	--     the default joystick / a GUI element with Active=true);
	--   • `self.suspended` is true (drag-aim on an ability slot is in flight
	--     and rotating the camera would fight the indicator placement);
	--   • more than one touch is on the screen (two-finger gestures are
	--     reserved for zooming/UI; rotating the camera at the same time
	--     felt chaotic — this is the "crazy" behavior we had earlier).
	table.insert(self.connections, UserInputService.TouchPan:Connect(function(positions, delta, _velocity, _state, processed)
		if processed or self.suspended then
			return
		end
		if #positions > 1 then
			return
		end
		self.yaw = self.yaw - delta.X * TOUCH_SENSITIVITY
		self.pitch = math.clamp(self.pitch - delta.Y * TOUCH_SENSITIVITY, MIN_PITCH, MAX_PITCH)
	end))

	table.insert(self.connections, RunService.RenderStepped:Connect(function()
		self:_update()
	end))
end

function CameraController:_update()
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

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MovementController = {}
MovementController.__index = MovementController

function MovementController.new(cameraController)
	local self = setmetatable({}, MovementController)
	self.player = Players.LocalPlayer
	self.camera = cameraController
	self.held = { W = false, A = false, S = false, D = false }
	self.connections = {}
	return self
end

local KEY_MAP = {
	[Enum.KeyCode.W] = "W",
	[Enum.KeyCode.A] = "A",
	[Enum.KeyCode.S] = "S",
	[Enum.KeyCode.D] = "D",
}

function MovementController:start()
	table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local k = KEY_MAP[input.KeyCode]
		if k then
			self.held[k] = true
		end
	end))

	table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
		local k = KEY_MAP[input.KeyCode]
		if k then
			self.held[k] = false
		end
	end))

	table.insert(self.connections, RunService.RenderStepped:Connect(function()
		self:_tick()
	end))
end

function MovementController:_tick()
	local character = self.player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	local forwardAxis = 0
	local rightAxis = 0
	if self.held.W then
		forwardAxis = forwardAxis - 1
	end
	if self.held.S then
		forwardAxis = forwardAxis + 1
	end
	if self.held.D then
		rightAxis = rightAxis + 1
	end
	if self.held.A then
		rightAxis = rightAxis - 1
	end

	if forwardAxis == 0 and rightAxis == 0 then
		humanoid:Move(Vector3.zero, false)
		return
	end

	-- Rotate (right, _, forward) by camera yaw so W is always camera-forward.
	local yaw = self.camera:getYaw()
	local local3 = Vector3.new(rightAxis, 0, forwardAxis)
	local world = CFrame.fromOrientation(0, yaw, 0):VectorToWorldSpace(local3)
	local moveDir = Vector3.new(world.X, 0, world.Z)
	if moveDir.Magnitude < 0.01 then
		humanoid:Move(Vector3.zero, false)
		return
	end
	moveDir = moveDir.Unit

	humanoid:Move(moveDir, false)
	-- Face the direction of motion ONLY when humanoid auto-rotate is off
	-- (in-match). In the lobby AutoRotate is true and we let the engine handle it.
	if not humanoid.AutoRotate then
		root.CFrame = CFrame.new(root.Position, root.Position + moveDir)
	end
end

function MovementController:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
end

return MovementController

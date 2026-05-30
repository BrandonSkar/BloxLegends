-- Toggles minion HP-bar BillboardGuis on/off based on distance from the local
-- player, so the screen isn't full of HP bars 200 studs away. Runs on Heartbeat
-- and just enables/disables the existing GUIs the server already attached.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HPBarVisibility = {}
HPBarVisibility.__index = HPBarVisibility

-- Minion HP bars only show within this many studs of the local player.
local MINION_BAR_DISTANCE = 60

function HPBarVisibility.new()
	local self = setmetatable({}, HPBarVisibility)
	self.localPlayer = Players.LocalPlayer
	self.connections = {}
	return self
end

function HPBarVisibility:_tick()
	local char = self.localPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local origin = root.Position
	local bin = Workspace:FindFirstChild("Minions")
	if not bin then
		return
	end
	for _, model in ipairs(bin:GetChildren()) do
		local minionRoot = model:FindFirstChild("HumanoidRootPart")
		local head = model:FindFirstChild("Head")
		local bar = head and head:FindFirstChild("HPBar")
		if minionRoot and bar then
			local dist = (minionRoot.Position - origin).Magnitude
			local want = dist <= MINION_BAR_DISTANCE
			if bar.Enabled ~= want then
				bar.Enabled = want
			end
		end
	end
end

function HPBarVisibility:start()
	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function()
			self:_tick()
		end)
	)
end

function HPBarVisibility:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
end

return HPBarVisibility

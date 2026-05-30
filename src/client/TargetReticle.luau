-- A floating "target locked" reticle above the local player's auto-attack target.
-- Pulses while the target is locked. Attaches to the target's body so it tracks
-- naturally as the target moves. Hooked off TargetingController:onChanged.

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local TargetReticle = {}
TargetReticle.__index = TargetReticle

function TargetReticle.new()
	local self = setmetatable({}, TargetReticle)
	self.currentGui = nil
	return self
end

local function findAdornee(target)
	if not target then
		return nil
	end
	if target.type == "player" then
		local p = Players:GetPlayerByUserId(target.id)
		local char = p and p.Character
		local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
		return head
	elseif target.type == "minion" then
		local bin = workspace:FindFirstChild("Minions")
		if bin then
			for _, model in ipairs(bin:GetChildren()) do
				if model:GetAttribute("MinionId") == target.id then
					return model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
				end
			end
		end
	elseif target.type == "tower" then
		for _, inst in ipairs(workspace:GetDescendants()) do
			if inst:IsA("BasePart") and inst:GetAttribute("TowerId") == target.id then
				return inst
			end
		end
	end
	return nil
end

function TargetReticle:setTarget(target)
	if self.currentGui then
		self.currentGui:Destroy()
		self.currentGui = nil
	end
	local adornee = findAdornee(target)
	if not adornee then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "TargetReticle"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(72, 72)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = adornee

	-- A transparent circular Frame with a colored UIStroke. Pulsing the
	-- stroke thickness + transparency gives a "locked on" look without
	-- needing any image assets.
	local ring = Instance.new("Frame")
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(255, 70, 70)
	stroke.Thickness = 3
	stroke.Transparency = 0.1
	stroke.Parent = ring

	-- Pulse forever (until reticle is replaced).
	local pulseInfo = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(stroke, pulseInfo, {
		Thickness = 6,
		Transparency = 0.5,
	}):Play()
	TweenService:Create(ring, pulseInfo, {
		Size = UDim2.fromScale(1.1, 1.1),
	}):Play()

	self.currentGui = gui
end

return TargetReticle

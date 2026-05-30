-- Hides enemy champions standing inside a bush from this client's view.
-- A bush is any BasePart with the Attribute `IsBush = true` placed in Workspace.
-- Visibility rule (League-style):
--   - I see an enemy if they are NOT in any bush, OR they are in the same bush I'm in.
--   - I see my own bush as semi-transparent so I can see out.
--   - Allies are always visible.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BushController = {}
BushController.__index = BushController

-- How transparent the bush looks to the player standing inside it.
local INSIDE_ALPHA = 0.7

function BushController.new()
	local self = setmetatable({}, BushController)
	self.localPlayer = Players.LocalPlayer
	self.bushes = {} -- list of { part = BasePart, originalTransparency = number }
	self.hiddenPlayers = {} -- userId -> true while currently hidden
	self.connections = {}
	return self
end

local function pointInBushXZ(pos, bushPart)
	-- Check XZ containment in the bush's local frame so rotated bushes work.
	-- We allow a generous Y tolerance so the HRP's height above the floor
	-- (~3 studs) doesn't kick the player out of a low bush.
	local localPos = bushPart.CFrame:PointToObjectSpace(pos)
	local hs = bushPart.Size / 2
	if math.abs(localPos.X) > hs.X then
		return false
	end
	if math.abs(localPos.Z) > hs.Z then
		return false
	end
	if math.abs(localPos.Y) > hs.Y + 6 then
		return false
	end
	return true
end

local function registerBush(self, part)
	for _, existing in ipairs(self.bushes) do
		if existing.part == part then
			return
		end
	end
	table.insert(self.bushes, {
		part = part,
		originalTransparency = part.Transparency,
	})
end

function BushController:_collectExistingBushes()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("BasePart") and inst:GetAttribute("IsBush") then
			registerBush(self, inst)
		end
	end
end

function BushController:_findBushAt(pos)
	if not pos then
		return nil
	end
	for _, b in ipairs(self.bushes) do
		if b.part.Parent and pointInBushXZ(pos, b.part) then
			return b
		end
	end
	return nil
end

local function getTeam(char)
	return char and char:GetAttribute("Team")
end

local function setCharacterHiddenLocally(player, hidden)
	local char = player.Character
	if not char then
		return
	end
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then
			p.LocalTransparencyModifier = hidden and 1 or 0
		elseif p:IsA("BillboardGui") or p:IsA("SurfaceGui") then
			-- Name tag and any other UI attached to the character also need
			-- to go away — BaseParts going transparent doesn't hide adornee GUIs.
			p.Enabled = not hidden
		end
	end
end

function BushController:_tick()
	local localChar = self.localPlayer.Character
	local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")
	local localTeam = getTeam(localChar)
	local localBush = localRoot and self:_findBushAt(localRoot.Position)

	-- Per-other-player visibility. An enemy is hidden if either:
	--   (a) they have the `Invisible` character attribute set (Smoke Bomb-style ability), or
	--   (b) they are inside a bush that I'm not also standing in.
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= self.localPlayer then
			local oChar = other.Character
			local oRoot = oChar and oChar:FindFirstChild("HumanoidRootPart")
			local shouldHide = false
			if oRoot then
				local oTeam = getTeam(oChar)
				if localTeam and oTeam and oTeam ~= localTeam then
					if oChar:GetAttribute("Invisible") then
						shouldHide = true
					else
						local otherBush = self:_findBushAt(oRoot.Position)
						if otherBush and otherBush ~= localBush then
							shouldHide = true
						end
					end
				end
			end
			local wasHidden = self.hiddenPlayers[other.UserId] or false
			if wasHidden ~= shouldHide then
				self.hiddenPlayers[other.UserId] = shouldHide or nil
				setCharacterHiddenLocally(other, shouldHide)
			end
		end
	end

	-- Bush visuals: only the bush I'm in gets the semi-transparent look,
	-- everything else stays at its original transparency.
	for _, b in ipairs(self.bushes) do
		if b.part.Parent then
			local desired = (b == localBush) and INSIDE_ALPHA or b.originalTransparency
			if b.part.Transparency ~= desired then
				b.part.Transparency = desired
			end
		end
	end
end

function BushController:start()
	self:_collectExistingBushes()
	-- Pick up bushes spawned after the match starts.
	table.insert(
		self.connections,
		Workspace.DescendantAdded:Connect(function(inst)
			if inst:IsA("BasePart") and inst:GetAttribute("IsBush") then
				registerBush(self, inst)
			end
		end)
	)
	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function()
			self:_tick()
		end)
	)
end

function BushController:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
end

return BushController

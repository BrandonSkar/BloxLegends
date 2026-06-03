-- Single source of truth for layout decisions across every ScreenGui. Each UI
-- module reads device class + scale from here instead of hard-coding pixel
-- sizes. Re-evaluates live whenever the viewport changes (window resize,
-- Studio device emulator preset switch, mobile orientation change).
--
-- Device class is picked by viewport width + touch capability:
--   phone   — narrow viewport OR touch + small screen
--   tablet  — touch + mid-sized viewport
--   desktop — everything else (mouse + keyboard or large screen)
--
-- Scale is computed relative to a design width of 1280px. We clamp so phones
-- don't get crushed (min 0.55) and 4K monitors don't get cartoonish (max 1.4).

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Responsive = {}

local DESIGN_WIDTH = 1280
local SCALE_MIN = 0.55
local SCALE_MAX = 1.4

-- Width breakpoints (in raw pixels, before scale). Below PHONE_MAX is phone,
-- below TABLET_MAX is tablet if touch, else desktop.
local PHONE_MAX = 700
local TABLET_MAX = 1100

local state = {
	deviceClass = "desktop", -- "phone" | "tablet" | "desktop"
	scale = 1.0,
	viewportSize = Vector2.new(1280, 720),
	topInset = 36,
	listeners = {},
}

local function computeDeviceClass(viewport)
	local touch = UserInputService.TouchEnabled
	local w = viewport.X
	if w <= PHONE_MAX then
		return "phone"
	end
	if touch and w <= TABLET_MAX then
		return "tablet"
	end
	if touch and w <= 1366 then
		-- Touch-first big tablet (iPad Pro 13") — treat as tablet, not desktop.
		return "tablet"
	end
	return "desktop"
end

local function computeScale(viewport)
	local raw = viewport.X / DESIGN_WIDTH
	return math.clamp(raw, SCALE_MIN, SCALE_MAX)
end

local function computeTopInset()
	-- GuiService:GetGuiInset() returns the topbar push in pixels. We pad an
	-- extra 8px so UI never visually touches the topbar.
	local inset = GuiService:GetGuiInset()
	return inset.Y + 8
end

local function fireListeners()
	-- Iterate a snapshot so listeners can unsubscribe during the callback.
	local snap = {}
	for _, fn in ipairs(state.listeners) do
		table.insert(snap, fn)
	end
	for _, fn in ipairs(snap) do
		local ok, err = pcall(fn, state.deviceClass, state.scale)
		if not ok then
			warn("[Responsive] listener error: " .. tostring(err))
		end
	end
end

local function recompute()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	-- Roblox sometimes hands back (1, 1) for one frame at startup. Ignore it —
	-- it would briefly classify the device as "phone" and reflow everything,
	-- causing a visible layout flicker.
	if viewport.X < 50 or viewport.Y < 50 then
		return
	end
	local nextClass = computeDeviceClass(viewport)
	local nextScale = computeScale(viewport)
	local nextInset = computeTopInset()
	local changed = nextClass ~= state.deviceClass
		or math.abs(nextScale - state.scale) > 0.001
		or math.abs(nextInset - state.topInset) > 0.5
	state.deviceClass = nextClass
	state.scale = nextScale
	state.viewportSize = viewport
	state.topInset = nextInset
	if changed then
		fireListeners()
	end
end

-- Public API ----------------------------------------------------------------

function Responsive.getDeviceClass()
	return state.deviceClass
end

function Responsive.isPhone()
	return state.deviceClass == "phone"
end

function Responsive.isTablet()
	return state.deviceClass == "tablet"
end

function Responsive.isDesktop()
	return state.deviceClass == "desktop"
end

function Responsive.isTouch()
	return state.deviceClass == "phone" or state.deviceClass == "tablet"
end

function Responsive.scale()
	return state.scale
end

function Responsive.viewportSize()
	return state.viewportSize
end

function Responsive.topInset()
	return state.topInset
end

-- Convenience: scale a pixel value to current device scale. Used everywhere
-- a UDim2.fromOffset(x, y) appears in legacy code so we can keep the visual
-- proportions while rescaling for the actual viewport.
function Responsive.px(value)
	return math.floor(value * state.scale + 0.5)
end

-- Subscribe to layout changes. Returns an unsubscribe function. Listener
-- fires once immediately so the caller can apply the initial layout
-- without duplicating the recompute logic.
function Responsive.onChanged(fn)
	table.insert(state.listeners, fn)
	pcall(fn, state.deviceClass, state.scale)
	return function()
		for i, existing in ipairs(state.listeners) do
			if existing == fn then
				table.remove(state.listeners, i)
				return
			end
		end
	end
end

-- One-time start: hook camera viewport changes so layout reflows when the
-- Studio device emulator switches presets or the player rotates a phone.
local started = false
function Responsive.start()
	if started then
		return
	end
	started = true
	recompute()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(recompute)
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local cam = Workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(recompute)
		end
		recompute()
	end)
	-- Topbar inset can change when chat is enabled/disabled or in immersive mode.
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(recompute)
end

return Responsive

-- SoundFX — tiny fire-and-forget sound layer. Uses only rbxasset:// sounds
-- that ship with the Roblox client, so nothing needs uploading or moderation
-- and there are no failing asset loads. Pitch/volume variation makes a small
-- set of built-ins cover the whole game vocabulary.

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local SoundFX = {}

local DEFS = {
	-- UI / economy
	click = { id = "rbxasset://sounds/button.wav", volume = 0.5 },
	buy = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, pitch = 1.6 },
	deny = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, pitch = 0.55 },
	ping = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5 },
	-- Combat
	kill = { id = "rbxasset://sounds/bass.wav", volume = 0.9, pitch = 1.3 },
	death = { id = "rbxasset://sounds/uuhhh.mp3", volume = 0.8 },
	castRanged = { id = "rbxasset://sounds/swoosh.wav", volume = 0.3, pitch = 1.15 },
	castMelee = { id = "rbxasset://sounds/swordslash.wav", volume = 0.25 },
	ability = { id = "rbxasset://sounds/swoosh.wav", volume = 0.45, pitch = 0.9 },
	-- Progression / objectives
	levelup = { id = "rbxasset://sounds/flashbulb.wav", volume = 0.7, pitch = 1.1 },
	towerDown = { id = "rbxasset://sounds/collide.wav", volume = 0.8, pitch = 0.7 },
	objective = { id = "rbxasset://sounds/bass.wav", volume = 0.9, pitch = 0.8 },
	announce = { id = "rbxasset://sounds/snap.mp3", volume = 0.55 },
	recall = { id = "rbxasset://sounds/short spring sound.wav", volume = 0.6 },
}

-- Play a named one-shot. opts can override { pitch, volume }.
function SoundFX.play(name, opts)
	local def = DEFS[name]
	if not def then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = (opts and opts.volume) or def.volume or 0.5
	sound.PlaybackSpeed = (opts and opts.pitch) or def.pitch or 1
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 6)
end

-- Short ping melody — used for victory (ascending) / defeat (descending).
function SoundFX.jingle(pitches, interval)
	task.spawn(function()
		for _, pitch in ipairs(pitches) do
			SoundFX.play("ping", { pitch = pitch, volume = 0.6 })
			task.wait(interval or 0.18)
		end
	end)
end

function SoundFX.victory()
	SoundFX.jingle({ 1.0, 1.26, 1.5, 2.0 })
end

function SoundFX.defeat()
	SoundFX.jingle({ 1.0, 0.84, 0.7, 0.5 }, 0.24)
end

return SoundFX

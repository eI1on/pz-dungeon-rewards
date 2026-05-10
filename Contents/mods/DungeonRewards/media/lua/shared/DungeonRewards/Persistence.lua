local JSON = require("ElyonLib/FileUtils/JSON")
local FileUtils = require("ElyonLib/FileUtils/FileUtils")
local DungeonRewards = require("DungeonRewards/Shared")

local Persistence = {}
local Shared = DungeonRewards.Shared

local function readJsonQuiet(filePath)
	local content = FileUtils.readFile(filePath, DungeonRewards.FILE_MOD_ID, { createIfNull = true })
	if type(content) ~= "string" then
		return nil
	end
	if content:gsub("%s+", "") == "" then
		return nil
	end

	local data = JSON.parse(content)
	if type(data) == "table" then
		return data
	end
	return nil
end

local function writeJsonQuiet(filePath, data)
	return FileUtils.writeJson(filePath, data, DungeonRewards.FILE_MOD_ID, { createIfNull = true })
end

local function path(fileName)
	return DungeonRewards.DATA_DIR .. "/" .. fileName
end

local function normalizeContainers(containers)
	local out = {}
	containers = type(containers) == "table" and containers or {}
	for key, entry in pairs(containers) do
		local container = Shared.NormalizeContainer(entry)
		if container.key == "" then
			container.key = tostring(key)
		end
		out[container.key] = container
	end
	return out
end

function Persistence.loadPresets()
	local data = readJsonQuiet(path("presets.json"))
	if type(data) == "table" and type(data.presets) == "table" then
		return Shared.NormalizePresets(data.presets)
	end
	if type(data) == "table" and data[1] ~= nil then
		return Shared.NormalizePresets(data)
	end
	return Shared.GetDefaultPresets()
end

function Persistence.savePresets(presets)
	local data = {
		version = DungeonRewards.DATA_VERSION,
		presets = Shared.NormalizePresets(presets),
	}
	return writeJsonQuiet(path("presets.json"), data), data.presets
end

function Persistence.loadContainers()
	local data = readJsonQuiet(path("containers.json"))
	if type(data) == "table" and type(data.containers) == "table" then
		return normalizeContainers(data.containers)
	end
	return normalizeContainers(data)
end

function Persistence.saveContainers(containers)
	local data = {
		version = DungeonRewards.DATA_VERSION,
		containers = normalizeContainers(containers),
	}
	return writeJsonQuiet(path("containers.json"), data), data.containers
end

function Persistence.loadWorld()
	local presets = Persistence.loadPresets()
	local containers = Persistence.loadContainers()
	Persistence.savePresets(presets)
	Persistence.saveContainers(containers)
	return {
		version = DungeonRewards.DATA_VERSION,
		presets = presets,
		containers = containers,
	}
end

function Persistence.saveWorld(world)
	world = type(world) == "table" and world or {}
	local presetOk, presets = Persistence.savePresets(world.presets)
	local containerOk, containers = Persistence.saveContainers(world.containers)
	return presetOk and containerOk,
		{
			version = DungeonRewards.DATA_VERSION,
			presets = presets,
			containers = containers,
		}
end

function Persistence.newPlayerRollStore()
	return {
		version = DungeonRewards.DATA_VERSION,
		players = {},
		containers = {},
	}
end

function Persistence.loadPlayerRollStore()
	local store = readJsonQuiet(path("player_rolls.json"))
	if type(store) ~= "table" then
		store = Persistence.newPlayerRollStore()
	end
	store.version = DungeonRewards.DATA_VERSION
	store.players = type(store.players) == "table" and store.players or {}
	store.containers = type(store.containers) == "table" and store.containers or {}
	Persistence.savePlayerRollStore(store)
	return store
end

function Persistence.savePlayerRollStore(store)
	store = type(store) == "table" and store or Persistence.newPlayerRollStore()
	store.version = DungeonRewards.DATA_VERSION
	store.players = type(store.players) == "table" and store.players or {}
	store.containers = type(store.containers) == "table" and store.containers or {}
	return writeJsonQuiet(path("player_rolls.json"), store)
end

function Persistence.loadPresetImportFile()
	local data = readJsonQuiet(DungeonRewards.CONFIG_FILE)
	if type(data) == "table" and type(data.presets) == "table" then
		return Shared.NormalizePresets(data.presets), true
	end
	if type(data) == "table" and data[1] ~= nil then
		return Shared.NormalizePresets(data), true
	end
	return Shared.GetDefaultPresets(), false
end

function Persistence.savePresetExportFile(presets)
	local normalized = Shared.NormalizePresets(presets)
	return writeJsonQuiet(DungeonRewards.CONFIG_FILE, {
		version = DungeonRewards.DATA_VERSION,
		presets = normalized,
	}),
		normalized
end

return Persistence

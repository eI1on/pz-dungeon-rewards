local Globals = require("ElyonLib/Core/Globals")
local FileUtils = require("ElyonLib/FileUtils/FileUtils")
local ItemUtils = require("ElyonLib/ItemUtils/ItemUtils")
local JSON = require("ElyonLib/FileUtils/JSON")
local MathUtils = require("ElyonLib/MathUtils/MathUtils")
local TableUtils = require("ElyonLib/TableUtils/TableUtils")
local TextUtils = require("ElyonLib/TextUtils/TextUtils")

local DungeonRewards = {}

DungeonRewards.Shared = {}
DungeonRewards.MODULE = "DungeonRewards"
DungeonRewards.VERSION = "0.1.0"
DungeonRewards.DATA_SCHEMA_VERSION = 2
DungeonRewards.CONFIG_FILE = "DungeonRewardsPresets.json"
DungeonRewards.PLAYER_STORE_FILE = "DungeonRewardsPlayerClaims.json"
DungeonRewards.FILE_MOD_ID = "Dungeon Rewards"
DungeonRewards.ClientSnapshot = nil
DungeonRewards.ActiveContainer = nil

DungeonRewards.Custom = DungeonRewards.Custom or {
    handlers = {},
    definitions = {},
}

DungeonRewards.DefaultPresets = {
    {
        id = "starter_cache",
        name = "Starter Cache",
        description = "A small dungeon chest with survival supplies.",
        enabled = true,
        rollCount = 3,
        allowDuplicates = false,
        consumeOncePerPlayer = true,
        rewards = {
            {
                id = "water",
                type = "item",
                weight = 40,
                title = "Clean Water",
                item = "Base.WaterBottleFull",
                count = 1,
            },
            {
                id = "food",
                type = "item",
                weight = 35,
                title = "Canned Food",
                item = "Base.TinnedSoup",
                count = 2,
            },
            {
                id = "maintenance_xp",
                type = "xp",
                weight = 20,
                title = "Maintenance Practice",
                perk = "Maintenance",
                amount = 50,
            },
            {
                id = "lucky_trait",
                type = "trait",
                weight = 5,
                title = "Lucky Break",
                trait = "Lucky",
                mode = "add",
            },
        },
    },
}

local Shared = DungeonRewards.Shared
local copyValue = TableUtils.deepCopy
local parseNumber = MathUtils.parseNumber
local trim = TextUtils.trim

local function getObjectIndex(object)
    if not object or not object.getSquare then
        return 0
    end
    if object.getObjectIndex then
        local index = tonumber(object:getObjectIndex())
        if index then
            return index
        end
    end
    local square = object:getSquare()
    local objects = square and square:getObjects()
    if objects then
        for i = 0, objects:size() - 1 do
            if objects:get(i) == object then
                return i
            end
        end
    end
    return 0
end

local function getObjectSpriteName(object)
    if object and object.getSprite and object:getSprite() and object:getSprite().getName then
        return object:getSprite():getName() or ""
    end
    return ""
end

function Shared.GetLocalPlayer()
    return getPlayer() or getSpecificPlayer(0)
end

function Shared.GetPlayerUsername(player)
    if player and player.getUsername then
        local username = player:getUsername()
        if username and username ~= "" then
            return username
        end
    end
    return nil
end

function Shared.GetPlayerKey(player)
    if not player then
        return nil
    end

    local username = Shared.GetPlayerUsername(player)
    if username then
        return username
    end

    if player.getOnlineID then
        local onlineId = tonumber(player:getOnlineID())
        if onlineId and onlineId >= 0 then
            return "online-" .. tostring(onlineId)
        end
    end

    if player.getPlayerNum then
        return "player-" .. tostring(player:getPlayerNum())
    end

    return tostring(player)
end

function Shared.PlayerHasAdminAccess(player)
    if Globals.isSingleplayer then
        return true
    end
    if player and player.getAccessLevel then
        local access = tostring(player:getAccessLevel() or "")
        return access == "Admin"
    end
    if isAdmin and isAdmin() then
        return true
    end
    if getAccessLevel then
        local access = tostring(getAccessLevel() or "")
        return access == "Admin"
    end
    return false
end

function Shared.GenerateID(prefix)
    local randomValue = type(ZombRand) == "function" and ZombRand(100000, 999999) or math.random(100000, 999999)
    return tostring(prefix or "id") .. "_" .. tostring(os.time()) .. "_" .. tostring(randomValue)
end

function Shared.NowTimestampString()
    return tostring(math.floor(tonumber(os.time()) or 0))
end

function Shared.NormalizeTimestamp(value)
    local numberValue = tonumber(value)
    if numberValue then
        return tostring(math.floor(numberValue))
    end
    local text = trim(value)
    if text ~= "" then
        return text
    end
    return Shared.NowTimestampString()
end

function Shared.GetContainerKeyFromObject(object)
    if not object or not object.getSquare then
        return nil
    end
    local square = object:getSquare()
    if not square then
        return nil
    end
    return string.format("%d:%d:%d:%d", square:getX(), square:getY(), square:getZ(), getObjectIndex(object))
end

function Shared.GetContainerDescriptor(object)
    if not object or not object.getSquare then
        return nil
    end
    local square = object:getSquare()
    if not square then
        return nil
    end
    local container = object.getContainer and object:getContainer() or nil
    return {
        key = Shared.GetContainerKeyFromObject(object),
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        objectIndex = getObjectIndex(object),
        spriteName = getObjectSpriteName(object),
        containerType = container and container:getType() or "",
        name = container and container:getType() or getObjectSpriteName(object),
    }
end

function Shared.FindContainerObjectByKey(key)
    if not key then
        return nil
    end
    local x, y, z, index = tostring(key):match("^(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+)$")
    x, y, z, index = tonumber(x), tonumber(y), tonumber(z), tonumber(index)
    if not x or not y or not z or not index or not getCell then
        return nil
    end
    local square = getCell():getGridSquare(x, y, z)
    local objects = square and square:getObjects()
    if not objects or index < 0 or index >= objects:size() then
        return nil
    end
    local object = objects:get(index)
    if object and object.getContainer and object:getContainer() then
        return object
    end
    return nil
end

function Shared.NormalizeReward(entry, index)
    entry = type(entry) == "table" and entry or {}
    local rewardType = trim(entry.type)
    if rewardType == "" then
        if trim(entry.item or entry.fullType) ~= "" then
            rewardType = "item"
        elseif trim(entry.perk or entry.skill) ~= "" then
            rewardType = "xp"
        elseif trim(entry.trait) ~= "" then
            rewardType = "trait"
        elseif trim(entry.handler) ~= "" then
            rewardType = "custom"
        else
            rewardType = "custom"
        end
    end

    local id = trim(entry.id)
    if id == "" then
        id = rewardType .. "_" .. tostring(index or 1)
    end

    local out = copyValue(entry)
    out.id = id
    out.type = rewardType
    out.weight = parseNumber(entry.weight, 1, 0, 100000) or 1
    out.title = trim(entry.title)
    out.description = trim(entry.description)

    if rewardType == "item" then
        out.item = trim(entry.item or entry.typeName or entry.fullType or entry.fullName)
        out.count = math.floor(parseNumber(entry.count or entry.amount, 1, 1, 999) or 1)
        if out.title == "" then
            out.title = ItemUtils.getDisplayName(out.item)
        end
    elseif rewardType == "xp" then
        out.perk = trim(entry.perk or entry.skill)
        out.amount = parseNumber(entry.amount or entry.xp, 0, -100000, 100000) or 0
        if out.title == "" then
            out.title = tostring(out.perk) .. " XP"
        end
    elseif rewardType == "trait" then
        out.trait = trim(entry.trait)
        out.mode = trim(entry.mode)
        if out.mode ~= "remove" then
            out.mode = "add"
        end
        if out.title == "" then
            out.title = (out.mode == "remove" and "Remove " or "Trait ") .. out.trait
        end
    elseif rewardType == "custom" then
        out.handler = trim(entry.handler or entry.id)
        if out.title == "" then
            out.title = Shared.GetCustomRewardDisplayName(out)
        end
    end

    return out
end

function Shared.NormalizePreset(preset, index)
    preset = type(preset) == "table" and preset or {}
    local id = trim(preset.id)
    if id == "" then
        id = Shared.GenerateID("preset")
    end

    local rewards = {}
    local inputRewards = type(preset.rewards) == "table" and preset.rewards or {}
    for i = 1, #inputRewards do
        local reward = Shared.NormalizeReward(inputRewards[i], i)
        if reward.weight > 0 then
            rewards[#rewards + 1] = reward
        end
    end

    return {
        id = id,
        name = trim(preset.name) ~= "" and trim(preset.name) or ("Preset " .. tostring(index or 1)),
        description = trim(preset.description),
        enabled = preset.enabled ~= false,
        rollCount = math.floor(parseNumber(preset.rollCount, 1, 1, 200) or 1),
        allowDuplicates = preset.allowDuplicates == true,
        consumeOncePerPlayer = preset.consumeOncePerPlayer ~= false,
        rewards = rewards,
    }
end

function Shared.NormalizePresets(presets)
    local out = {}
    presets = type(presets) == "table" and presets or DungeonRewards.DefaultPresets
    for i = 1, #presets do
        out[#out + 1] = Shared.NormalizePreset(presets[i], i)
    end
    if #out == 0 then
        return Shared.NormalizePresets(DungeonRewards.DefaultPresets)
    end
    return out
end

function Shared.NormalizeContainer(entry)
    entry = type(entry) == "table" and entry or {}
    local key = trim(entry.key)
    return {
        key = key,
        x = math.floor(parseNumber(entry.x, 0) or 0),
        y = math.floor(parseNumber(entry.y, 0) or 0),
        z = math.floor(parseNumber(entry.z, 0) or 0),
        objectIndex = math.floor(parseNumber(entry.objectIndex, 0) or 0),
        spriteName = trim(entry.spriteName),
        containerType = trim(entry.containerType),
        name = trim(entry.name) ~= "" and trim(entry.name) or key,
        presetId = trim(entry.presetId),
        enabled = entry.enabled ~= false,
        createdBy = trim(entry.createdBy),
        createdAt = Shared.NormalizeTimestamp(entry.createdAt),
        updatedAt = Shared.NormalizeTimestamp(entry.updatedAt),
    }
end

function Shared.GetDefaultPresets()
    return Shared.NormalizePresets(copyValue(DungeonRewards.DefaultPresets))
end

function Shared.LoadPresetsFromFile()
    local content = FileUtils.readFile(DungeonRewards.CONFIG_FILE, DungeonRewards.FILE_MOD_ID, { createIfNull = true })
    local data = nil
    if type(content) == "string" and content:gsub("%s+", "") ~= "" then
        local ok, parsed = pcall(JSON.parse, content)
        if ok then
            data = parsed
        end
    end
    if type(data) == "table" then
        if type(data.presets) == "table" then
            return Shared.NormalizePresets(data.presets), true
        end
        return Shared.NormalizePresets(data), true
    end
    return Shared.GetDefaultPresets(), false
end

function Shared.SavePresetsToFile(presets)
    local normalized = Shared.NormalizePresets(presets)
    return FileUtils.writeJson(DungeonRewards.CONFIG_FILE, { presets = normalized }, DungeonRewards.FILE_MOD_ID,
        { createIfNull = true }), normalized
end

function Shared.ResetModData(data)
    data = data or {}
    local keys = {}
    for key, _ in pairs(data) do
        keys[#keys + 1] = key
    end
    for i = 1, #keys do
        data[keys[i]] = nil
    end
    data.version = DungeonRewards.VERSION
    data.schemaVersion = DungeonRewards.DATA_SCHEMA_VERSION
    data.presets = Shared.GetDefaultPresets()
    data.containers = {}
    return data
end

function Shared.GetModData()
    local data = ModData.getOrCreate(DungeonRewards.MODULE)
    if data.schemaVersion ~= DungeonRewards.DATA_SCHEMA_VERSION then
        if type(data.presets) ~= "table" and type(data.containers) ~= "table" then
            return Shared.ResetModData(data)
        end
        data.version = DungeonRewards.VERSION
        data.schemaVersion = DungeonRewards.DATA_SCHEMA_VERSION
        data.players = nil
    end
    data.version = DungeonRewards.VERSION
    data.schemaVersion = DungeonRewards.DATA_SCHEMA_VERSION
    data.presets = Shared.NormalizePresets(data.presets)
    data.containers = type(data.containers) == "table" and data.containers or {}
    local containers = {}
    for key, entry in pairs(data.containers) do
        local container = Shared.NormalizeContainer(entry)
        if container.key == "" then
            container.key = tostring(key)
        end
        containers[container.key] = container
    end
    data.containers = containers
    data.players = nil
    return data
end

function Shared.FindPreset(data, presetId)
    if not data or not presetId then
        return nil
    end
    for i = 1, #(data.presets or {}) do
        if data.presets[i].id == presetId then
            return data.presets[i], i
        end
    end
    return nil, nil
end

function Shared.GetRewardSummary(reward)
    reward = Shared.NormalizeReward(reward or {}, 1)
    if reward.type == "item" then
        return string.format("%dx %s", reward.count or 1, ItemUtils.getDisplayName(reward.item))
    elseif reward.type == "xp" then
        return string.format("%s XP +%s", reward.perk or "Skill", tostring(reward.amount or 0))
    elseif reward.type == "trait" then
        return string.format("%s trait: %s", reward.mode == "remove" and "Remove" or "Add", reward.trait or "?")
    elseif reward.type == "custom" then
        return "Custom: " .. Shared.GetCustomRewardDisplayName(reward)
    end
    return reward.title or "Reward"
end

function Shared.GetPresetWeightTotal(preset)
    local total = 0
    for i = 1, #(preset and preset.rewards or {}) do
        total = total + math.max(0, tonumber(preset.rewards[i].weight) or 0)
    end
    return total
end

function Shared.RollRewards(preset)
    preset = Shared.NormalizePreset(preset)
    local rewards = copyValue(preset.rewards)
    local rolls = {}
    local count = math.min(preset.rollCount or 1, preset.allowDuplicates and (preset.rollCount or 1) or #rewards)

    for rollIndex = 1, count do
        local total = 0
        for i = 1, #rewards do
            total = total + math.max(0, tonumber(rewards[i].weight) or 0)
        end
        if total <= 0 then
            break
        end

        local pick = type(ZombRand) == "function" and (ZombRand(0, math.floor(total * 10000)) / 10000) or
            (math.random() * total)
        local cursor = 0
        local selectedIndex = 1
        for i = 1, #rewards do
            cursor = cursor + math.max(0, tonumber(rewards[i].weight) or 0)
            if pick <= cursor then
                selectedIndex = i
                break
            end
        end

        rolls[#rolls + 1] = copyValue(rewards[selectedIndex])
        if not preset.allowDuplicates then
            table.remove(rewards, selectedIndex)
        end
    end

    return rolls
end

function Shared.RegisterCustomReward(handlerId, fn, definition)
    handlerId = trim(handlerId)
    if handlerId == "" or type(fn) ~= "function" then
        return false
    end
    definition = type(definition) == "table" and definition or {}
    DungeonRewards.Custom.handlers[handlerId] = fn
    DungeonRewards.Custom.definitions[handlerId] = {
        handler = handlerId,
        displayName = trim(definition.displayName),
        icon = trim(definition.icon),
        iconText = trim(definition.iconText),
    }
    return true
end

function Shared.GetCustomRewardHandler(handlerId)
    return DungeonRewards.Custom.handlers[tostring(handlerId or "")]
end

function Shared.GetCustomRewardDisplayName(reward)
    reward = type(reward) == "table" and reward or {}
    local displayName = trim(reward.displayName)
    if displayName ~= "" then
        return displayName
    end
    local definition = DungeonRewards.Custom.definitions[trim(reward.handler)]
    if definition and trim(definition.displayName) ~= "" then
        return trim(definition.displayName)
    end
    return trim(reward.handler) ~= "" and trim(reward.handler) or "Custom Reward"
end

function Shared.ExecuteCommand(command, args)
    args = args or {}
    if Globals.isClient and not Globals.isServer then
        sendClientCommand(DungeonRewards.MODULE, command, args)
        return true
    end

    local serverModule = require("DungeonRewards/Server")
    if not serverModule or not serverModule.Server or not serverModule.Server.ServerCommands then
        return false
    end
    local handler = serverModule.Server.ServerCommands[command]
    if type(handler) ~= "function" then
        return false
    end
    handler(Shared.GetLocalPlayer(), args)
    return true
end

return DungeonRewards

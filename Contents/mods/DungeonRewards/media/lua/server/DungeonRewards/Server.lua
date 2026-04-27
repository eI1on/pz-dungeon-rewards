local Globals = require("ElyonLib/Core/Globals")
local FileUtils = require("ElyonLib/FileUtils/FileUtils")
local JSON = require("ElyonLib/FileUtils/JSON")
local Logger = require("DungeonRewards/Logger")
local DungeonRewards = require("DungeonRewards/Shared")

DungeonRewards.Server = DungeonRewards.Server or {}
DungeonRewards.Server.ServerCommands = DungeonRewards.Server.ServerCommands or {}

local Server = DungeonRewards.Server
local Shared = DungeonRewards.Shared
local PLAYER_STORE_SCHEMA = 1

Server.PendingRolls = Server.PendingRolls or {}

local function newPlayerStore()
    return {
        version = DungeonRewards.VERSION,
        schemaVersion = PLAYER_STORE_SCHEMA,
        players = {},
    }
end

local function callClientHandler(command, args)
    if DungeonRewards.Client and DungeonRewards.Client.ClientCommands and DungeonRewards.Client.ClientCommands[command] then
        DungeonRewards.Client.ClientCommands[command](args or {})
    end
end

local function sendToPlayer(player, command, args)
    if Globals.isServer then
        sendServerCommand(player, DungeonRewards.MODULE, command, args or {})
    else
        callClientHandler(command, args or {})
    end
end

local function sendCommandResult(player, message, level)
    sendToPlayer(player, "CommandResult", {
        message = tostring(message or ""),
        level = level or "info",
    })
end

local function pushSnapshotToAll(message, level)
    if Globals.isServer and getOnlinePlayers then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do
            Server.PushSnapshotToPlayer(players:get(i), message, level)
        end
        return
    end
    Server.PushSnapshotToPlayer(Shared.GetLocalPlayer(), message, level)
end

function Server.LoadPlayerStore(force)
    if Server.PlayerStore and not force then
        return Server.PlayerStore
    end

    local content = FileUtils.readFile(DungeonRewards.PLAYER_STORE_FILE, DungeonRewards.FILE_MOD_ID,
        { createIfNull = true })
    local store = nil
    if type(content) == "string" and content:gsub("%s+", "") ~= "" then
        local ok, parsed = pcall(JSON.parse, content)
        if ok and type(parsed) == "table" then
            store = parsed
        else
            Logger:warning("Dungeon Rewards player claim store was invalid; rebuilding %s",
                tostring(DungeonRewards.PLAYER_STORE_FILE))
        end
    end
    if type(store) ~= "table" or store.schemaVersion ~= PLAYER_STORE_SCHEMA then
        store = newPlayerStore()
    end
    store.version = DungeonRewards.VERSION
    store.schemaVersion = PLAYER_STORE_SCHEMA
    store.players = type(store.players) == "table" and store.players or {}
    Server.PlayerStore = store
    Server.SavePlayerStore()
    return store
end

function Server.SavePlayerStore()
    if not Server.PlayerStore then
        return true
    end
    return FileUtils.writeJson(DungeonRewards.PLAYER_STORE_FILE, Server.PlayerStore, DungeonRewards.FILE_MOD_ID,
        { createIfNull = true })
end

local function getPlayerClaimState(store, playerId)
    store.players[playerId] = type(store.players[playerId]) == "table" and store.players[playerId] or {}
    local state = store.players[playerId]
    state.containers = type(state.containers) == "table" and state.containers or {}
    return state
end

local function isContainerClaimed(store, playerId, containerKey)
    local state = getPlayerClaimState(store, playerId)
    return state.containers[containerKey] ~= nil
end

local function markContainerClaimed(store, playerId, containerKey)
    local state = getPlayerClaimState(store, playerId)
    state.containers[containerKey] = Shared.NowTimestampString()
end

local function clearContainerClaims(store, containerKey)
    local count = 0
    for _, state in pairs(store.players or {}) do
        if type(state) == "table" and type(state.containers) == "table" and state.containers[containerKey] ~= nil then
            state.containers[containerKey] = nil
            count = count + 1
        end
    end
    return count
end

local function getPendingRoll(playerId, containerKey)
    local playerRolls = Server.PendingRolls[playerId]
    return playerRolls and playerRolls[containerKey] or nil
end

local function setPendingRoll(playerId, containerKey, rewards)
    Server.PendingRolls[playerId] = type(Server.PendingRolls[playerId]) == "table" and Server.PendingRolls[playerId] or {}
    Server.PendingRolls[playerId][containerKey] = {
        rolledRewards = rewards,
        rolledAt = Shared.NowTimestampString(),
    }
    return Server.PendingRolls[playerId][containerKey]
end

local function clearPendingRoll(playerId, containerKey)
    if Server.PendingRolls[playerId] then
        Server.PendingRolls[playerId][containerKey] = nil
    end
end

local function clearPendingForContainer(containerKey)
    for playerId, playerRolls in pairs(Server.PendingRolls or {}) do
        if type(playerRolls) == "table" then
            playerRolls[containerKey] = nil
            if not next(playerRolls) then
                Server.PendingRolls[playerId] = nil
            end
        end
    end
end

function Server.BuildSnapshot(player, message, level)
    local data = Shared.GetModData()
    local containers = {}
    for key, entry in pairs(data.containers or {}) do
        containers[#containers + 1] = Shared.NormalizeContainer(entry)
    end
    table.sort(containers, function(a, b)
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)

    return {
        version = DungeonRewards.VERSION,
        schemaVersion = DungeonRewards.DATA_SCHEMA_VERSION,
        isAdmin = Shared.PlayerHasAdminAccess(player),
        presets = data.presets or {},
        containers = containers,
        message = message,
        level = level or "info",
    }
end

function Server.PushSnapshotToPlayer(player, message, level)
    if not player then
        return nil
    end
    local snapshot = Server.BuildSnapshot(player, message, level)
    sendToPlayer(player, "LoadSnapshot", snapshot)
    return snapshot
end

local function findPerk(perkName)
    perkName = tostring(perkName or "")
    if perkName == "" then
        return nil
    end
    if Perks and Perks[perkName] then
        return Perks[perkName]
    end
    if Perks and Perks.FromString then
        local perk = Perks.FromString(perkName)
        if perk and PerkFactory.getPerk(perk) then
            return perk
        end
    end
    return nil
end

local function grantItemReward(player, reward, summaries, errors)
    local itemType = tostring(reward.item or reward.fullType or "")
    local count = math.floor(tonumber(reward.count) or 1)
    if itemType == "" or count <= 0 then
        errors[#errors + 1] = "Invalid item reward"
        return
    end

    local scriptItem = ScriptManager.instance:getItem(itemType)
    if not scriptItem then
        errors[#errors + 1] = "Missing item " .. itemType
        return
    end

    if Globals.isServer then
        player:sendObjectChange("addItemOfType", { type = itemType, count = count })
    else
        for i = 1, count do
            player:getInventory():AddItem(itemType)
        end
    end
    summaries[#summaries + 1] = string.format("%dx %s", count, scriptItem:getDisplayName())
end

local function grantXpReward(player, reward, summaries, errors)
    local perk = findPerk(reward.perk)
    local amount = tonumber(reward.amount) or 0
    if not perk or amount == 0 then
        errors[#errors + 1] = "Invalid XP reward " .. tostring(reward.perk)
        return
    end
    player:getXp():AddXP(perk, amount)
    local perkInfo = PerkFactory.getPerk(perk)
    summaries[#summaries + 1] = string.format("%s XP +%s", perkInfo and perkInfo:getName() or tostring(reward.perk),
        tostring(amount))
end

local function grantTraitReward(player, reward, summaries, errors)
    local traitType = tostring(reward.trait or "")
    if traitType == "" or not player or not player.getTraits then
        errors[#errors + 1] = "Invalid trait reward"
        return
    end
    local trait = TraitFactory and TraitFactory.getTrait(traitType) or nil
    if not trait then
        errors[#errors + 1] = "Missing trait " .. traitType
        return
    end

    if reward.mode == "remove" then
        if player:getTraits():contains(traitType) then
            player:getTraits():remove(traitType)
            SyncXp(player)
        end
        summaries[#summaries + 1] = "Removed trait " .. trait:getLabel()
        return
    end

    if not player:getTraits():contains(traitType) then
        player:getTraits():add(traitType)
        SyncXp(player)
    end
    summaries[#summaries + 1] = "Trait " .. trait:getLabel()
end

local function grantCustomReward(player, reward, context, summaries, errors)
    local handler = Shared.GetCustomRewardHandler(reward.handler)
    if type(handler) ~= "function" then
        errors[#errors + 1] = "Missing custom handler " .. tostring(reward.handler)
        return
    end
    local success, summary = handler(player, reward, context)
    if success == false then
        errors[#errors + 1] = tostring(summary or "Custom reward failed")
        return
    end
    summaries[#summaries + 1] = tostring(summary or Shared.GetCustomRewardDisplayName(reward))
end

function Server.GrantRewards(player, rewards, context)
    local summaries = {}
    local errors = {}
    for i = 1, #(rewards or {}) do
        local reward = Shared.NormalizeReward(rewards[i], i)
        if reward.type == "item" then
            grantItemReward(player, reward, summaries, errors)
        elseif reward.type == "xp" then
            grantXpReward(player, reward, summaries, errors)
        elseif reward.type == "trait" then
            grantTraitReward(player, reward, summaries, errors)
        elseif reward.type == "custom" then
            grantCustomReward(player, reward, context, summaries, errors)
        end
    end
    return {
        summaries = summaries,
        errors = errors,
        successCount = #summaries,
        errorCount = #errors,
    }
end

local function summarizeGrant(grant)
    if grant.successCount > 0 then
        return "Received: " .. table.concat(grant.summaries, ", "), "info"
    end
    if grant.errorCount > 0 then
        return "Reward claimed, but delivery had issues: " .. table.concat(grant.errors, ", "), "warning"
    end
    return "Reward claimed.", "info"
end

function Server.ServerCommands.RequestSnapshot(player, args)
    Server.PushSnapshotToPlayer(player)
end

function Server.ServerCommands.SavePreset(player, args)
    if not Shared.PlayerHasAdminAccess(player) then
        sendCommandResult(player, "Dungeon Rewards presets are admin-only.", "error")
        return
    end

    local data = Shared.GetModData()
    local preset = Shared.NormalizePreset(args and args.preset or {})
    local _, index = Shared.FindPreset(data, preset.id)
    if index then
        data.presets[index] = preset
    else
        data.presets[#data.presets + 1] = preset
    end
    Logger:info("%s saved Dungeon Rewards preset %s", tostring(Shared.GetPlayerKey(player)), tostring(preset.id))
    pushSnapshotToAll("Preset saved.", "info")
end

function Server.ServerCommands.DeletePreset(player, args)
    if not Shared.PlayerHasAdminAccess(player) then
        sendCommandResult(player, "Dungeon Rewards presets are admin-only.", "error")
        return
    end

    local data = Shared.GetModData()
    local presetId = tostring(args and args.presetId or "")
    local _, index = Shared.FindPreset(data, presetId)
    if not index then
        sendCommandResult(player, "Preset not found.", "error")
        return
    end
    table.remove(data.presets, index)
    for _, container in pairs(data.containers or {}) do
        if container.presetId == presetId then
            container.presetId = ""
        end
    end
    pushSnapshotToAll("Preset deleted.", "info")
end

function Server.ServerCommands.ImportPresets(player, args)
    if not Shared.PlayerHasAdminAccess(player) then
        sendCommandResult(player, "Dungeon Rewards presets are admin-only.", "error")
        return
    end
    local data = Shared.GetModData()
    data.presets = Shared.NormalizePresets(args and args.presets or {})
    pushSnapshotToAll("Presets imported.", "info")
end

function Server.ServerCommands.ResetPresets(player, args)
    if not Shared.PlayerHasAdminAccess(player) then
        sendCommandResult(player, "Dungeon Rewards presets are admin-only.", "error")
        return
    end
    local data = Shared.GetModData()
    data.presets = Shared.GetDefaultPresets()
    pushSnapshotToAll("Presets reset.", "info")
end

function Server.ServerCommands.RegisterContainer(player, args)
    if not Shared.PlayerHasAdminAccess(player) then
        sendCommandResult(player, "Dungeon Rewards containers are admin-only.", "error")
        return
    end

    local descriptor = Shared.NormalizeContainer(args and args.container or {})
    if descriptor.key == "" then
        sendCommandResult(player, "Container key was missing.", "error")
        return
    end

    local data = Shared.GetModData()
    local existing = data.containers[descriptor.key] or {}
    descriptor.presetId = tostring(args and args.presetId or existing.presetId or descriptor.presetId or "")
    descriptor.createdAt = Shared.NormalizeTimestamp(existing.createdAt)
    descriptor.createdBy = existing.createdBy or Shared.GetPlayerKey(player) or "Admin"
    descriptor.updatedAt = Shared.NowTimestampString()
    data.containers[descriptor.key] = descriptor
    pushSnapshotToAll("Container registered.", "info")
end

function Server.ServerCommands.AssignContainerPreset(player, args)
    if not Shared.PlayerHasAdminAccess(player) then
        sendCommandResult(player, "Dungeon Rewards containers are admin-only.", "error")
        return
    end
    local data = Shared.GetModData()
    local key = tostring(args and args.containerKey or "")
    local container = data.containers[key]
    if not container then
        sendCommandResult(player, "Container not found.", "error")
        return
    end
    local presetId = tostring(args and args.presetId or "")
    if presetId ~= "" and not Shared.FindPreset(data, presetId) then
        sendCommandResult(player, "Preset not found.", "error")
        return
    end
    container.presetId = presetId
    container.enabled = not args or args.enabled ~= false
    container.updatedAt = Shared.NowTimestampString()
    pushSnapshotToAll("Container updated.", "info")
end

function Server.ServerCommands.DeleteContainer(player, args)
    if not Shared.PlayerHasAdminAccess(player) then
        sendCommandResult(player, "Dungeon Rewards containers are admin-only.", "error")
        return
    end
    local data = Shared.GetModData()
    data.containers[tostring(args and args.containerKey or "")] = nil
    pushSnapshotToAll("Container removed.", "info")
end

function Server.ServerCommands.ResetContainerClaims(player, args)
    if not Shared.PlayerHasAdminAccess(player) then
        sendCommandResult(player, "Dungeon Rewards containers are admin-only.", "error")
        return
    end

    local key = tostring(args and args.containerKey or "")
    if key == "" then
        sendCommandResult(player, "Container key was missing.", "error")
        return
    end

    local data = Shared.GetModData()
    if not data.containers[key] then
        sendCommandResult(player, "Container not found.", "error")
        return
    end

    local store = Server.LoadPlayerStore()
    local count = clearContainerClaims(store, key)
    clearPendingForContainer(key)
    Server.SavePlayerStore()
    pushSnapshotToAll(string.format("Container reuse enabled. Cleared %d player claim(s).", count), "info")
end

function Server.ServerCommands.RequestContainerRoll(player, args)
    if not player then
        return
    end
    local data = Shared.GetModData()
    local key = tostring(args and args.containerKey or "")
    local container = data.containers[key]
    if not container or container.enabled == false then
        sendCommandResult(player, "This is not an active Dungeon Rewards container.", "error")
        return
    end

    local preset = Shared.FindPreset(data, container.presetId)
    if not preset or preset.enabled == false or #(preset.rewards or {}) == 0 then
        sendCommandResult(player, "This container has no active preset.", "error")
        return
    end

    local playerId = Shared.GetPlayerKey(player)
    local store = Server.LoadPlayerStore()
    if preset.consumeOncePerPlayer and isContainerClaimed(store, playerId, key) then
        sendToPlayer(player, "LoadContainerRoll", {
            container = container,
            preset = preset,
            claimed = true,
            rolledRewards = {},
            message = "You already claimed this container.",
            level = "warning",
        })
        return
    end

    local pending = getPendingRoll(playerId, key)
    if not pending or args.reroll == true then
        pending = setPendingRoll(playerId, key, Shared.RollRewards(preset))
    end

    sendToPlayer(player, "LoadContainerRoll", {
        container = container,
        preset = preset,
        claimed = false,
        rolledRewards = pending.rolledRewards,
        playerId = playerId,
    })
end

function Server.ServerCommands.ClaimContainerRewards(player, args)
    if not player then
        return
    end
    local data = Shared.GetModData()
    local key = tostring(args and args.containerKey or "")
    local container = data.containers[key]
    if not container or container.enabled == false then
        sendCommandResult(player, "This is not an active Dungeon Rewards container.", "error")
        return
    end
    local preset = Shared.FindPreset(data, container.presetId)
    if not preset then
        sendCommandResult(player, "This container has no active preset.", "error")
        return
    end

    local playerId = Shared.GetPlayerKey(player)
    local store = Server.LoadPlayerStore()
    if preset.consumeOncePerPlayer and isContainerClaimed(store, playerId, key) then
        sendCommandResult(player, "You already claimed this container.", "warning")
        return
    end

    local pending = getPendingRoll(playerId, key)
    local rolledRewards = pending and pending.rolledRewards or Shared.RollRewards(preset)

    local grant = Server.GrantRewards(player, rolledRewards, {
        type = "dungeon-container",
        containerKey = key,
        presetId = preset.id,
        playerId = playerId,
    })
    markContainerClaimed(store, playerId, key)
    Server.SavePlayerStore()
    clearPendingRoll(playerId, key)

    local message, level = summarizeGrant(grant)
    Logger:info("%s claimed Dungeon Rewards container %s preset %s", tostring(playerId), tostring(key),
        tostring(preset.id))
    sendToPlayer(player, "ContainerClaimed", {
        containerKey = key,
        message = message,
        level = level,
    })
    Server.PushSnapshotToPlayer(player, message, level)
end

function Server.onClientCommand(module, command, player, args)
    if module ~= DungeonRewards.MODULE then
        return
    end
    local handler = Server.ServerCommands[command]
    if type(handler) == "function" then
        handler(player, args or {})
    end
end

Events.OnClientCommand.Add(Server.onClientCommand)

Events.OnInitGlobalModData.Add(function()
    local data = Shared.GetModData()
    if not data.presets or #data.presets == 0 then
        data.presets = Shared.GetDefaultPresets()
    end
end)

return DungeonRewards

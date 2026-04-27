require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"

local Logger = require("DungeonRewards/Logger")
local DungeonRewards = require("DungeonRewards/Shared")
local AdminPanel = require("DungeonRewards/DungeonRewardsAdminPanel")
local PlayerPanel = require("DungeonRewards/DungeonRewardsPlayerPanel")

DungeonRewards.Client = DungeonRewards.Client or {}
DungeonRewards.Client.ClientCommands = DungeonRewards.Client.ClientCommands or {}

local Client = DungeonRewards.Client
local Shared = DungeonRewards.Shared

local function findContainerObject(worldobjects)
    for i = 1, #(worldobjects or {}) do
        local object = worldobjects[i]
        if object and object.getContainer and object:getContainer() then
            return object
        end
    end
    return nil
end

local function findContainerInSnapshot(key)
    local snapshot = DungeonRewards.ClientSnapshot or {}
    for i = 1, #(snapshot.containers or {}) do
        if snapshot.containers[i].key == key then
            return snapshot.containers[i]
        end
    end
    return nil
end

function Client.ClientCommands.LoadSnapshot(args)
    DungeonRewards.ClientSnapshot = args or {}
    if AdminPanel.instance then
        AdminPanel.instance:onSnapshotReceived(DungeonRewards.ClientSnapshot)
    end
end

function Client.ClientCommands.CommandResult(args)
    args = args or {}
    if AdminPanel.instance then
        AdminPanel.instance:setStatus(args.message or "", args.level or "info")
    end
    if PlayerPanel.instance then
        PlayerPanel.instance:setStatus(args.message or "", args.level or "info")
    end
    local player = getPlayer()
    if player and player.setHaloNote and args.message and args.message ~= "" then
        player:setHaloNote(args.message, 255, 255, 255, 500)
    end
end

function Client.ClientCommands.LoadContainerRoll(args)
    if PlayerPanel.instance then
        PlayerPanel.instance:loadPayload(args or {})
    end
end

function Client.ClientCommands.ContainerClaimed(args)
    args = args or {}
    if PlayerPanel.instance then
        PlayerPanel.instance.payload = PlayerPanel.instance.payload or {}
        PlayerPanel.instance.payload.claimed = true
        PlayerPanel.instance:setStatus(args.message or getText("IGUI_DRewards_StatusClaimed"), args.level or "info")
    end
    local player = getPlayer()
    if player and player.setHaloNote and args.message then
        player:setHaloNote(args.message, 255, 255, 255, 500)
    end
end

function Client.onServerCommand(module, command, args)
    if module ~= DungeonRewards.MODULE then
        return
    end
    local handler = Client.ClientCommands[command]
    if type(handler) == "function" then
        handler(args or {})
    end
end

Events.OnServerCommand.Add(Client.onServerCommand)

local function openPlayerPanel(worldobjects, playerNum, object)
    local playerObj = getSpecificPlayer(playerNum) or getPlayer()
    local key = Shared.GetContainerKeyFromObject(object)
    if key then
        PlayerPanel.openPanel(playerObj, key)
    end
end

local function registerContainer(worldobjects, playerNum, object)
    local playerObj = getSpecificPlayer(playerNum) or getPlayer()
    local descriptor = Shared.GetContainerDescriptor(object)
    if not descriptor then
        return
    end
    DungeonRewards.ActiveContainer = descriptor.key
    Shared.ExecuteCommand("RegisterContainer", { container = descriptor })
    AdminPanel.openPanel(playerObj)
end

function Client.onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    local object = findContainerObject(worldobjects)
    if not object then
        return
    end

    local key = Shared.GetContainerKeyFromObject(object)
    local container = key and findContainerInSnapshot(key) or nil
    local playerObj = getSpecificPlayer(playerNum) or getPlayer()
    local isAdmin = Shared.PlayerHasAdminAccess(playerObj)

    if container and container.enabled ~= false and container.presetId and container.presetId ~= "" then
        if test then
            ISWorldObjectContextMenu.setTest()
            return true
        end
        context:addOption(getText("ContextMenu_DRewards_Open"), worldobjects, openPlayerPanel, playerNum, object)
    end

    if isAdmin then
        if test then
            ISWorldObjectContextMenu.setTest()
            return true
        end
        local optionText = container and getText("ContextMenu_DRewards_Manage") or getText("ContextMenu_DRewards_Register")
        context:addOption(optionText, worldobjects, registerContainer, playerNum, object)
    end
end

Events.OnFillWorldObjectContextMenu.Add(Client.onFillWorldObjectContextMenu)

local requestReady = false
local function requestInitialSnapshot()
    if not requestReady then
        requestReady = true
        return
    end
    Events.OnTick.Remove(requestInitialSnapshot)
    if not Shared.ExecuteCommand("RequestSnapshot", { reason = "game-start" }) then
        Logger:warning("Failed to request Dungeon Rewards snapshot.")
    end
end

Events.OnTick.Add(requestInitialSnapshot)

return DungeonRewards

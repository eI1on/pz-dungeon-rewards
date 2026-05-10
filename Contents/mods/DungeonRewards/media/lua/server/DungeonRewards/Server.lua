local Globals = require("ElyonLib/Core/Globals")
local GrantUtils = require("ElyonLib/Rewards/GrantUtils")
local Logger = require("DungeonRewards/Logger")
local DungeonRewards = require("DungeonRewards/Shared")
local Persistence = require("DungeonRewards/Persistence")
local RollService = require("DungeonRewards/RollService")

DungeonRewards.Server = DungeonRewards.Server or {}
DungeonRewards.Server.ServerCommands = DungeonRewards.Server.ServerCommands or {}

local Server = DungeonRewards.Server
local Shared = DungeonRewards.Shared

Server.World = Server.World or nil

local function getWorld()
	if not Server.World then
		Server.World = Persistence.loadWorld()
	end
	return Server.World
end

local function saveWorld()
	local ok, world = Persistence.saveWorld(getWorld())
	Server.World = world
	return ok
end

local function callClientHandler(command, args)
	if
		DungeonRewards.Client
		and DungeonRewards.Client.ClientCommands
		and DungeonRewards.Client.ClientCommands[command]
	then
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

function Server.BuildSnapshot(player, message, level)
	local world = getWorld()
	local containers = {}
	for _, entry in pairs(world.containers or {}) do
		containers[#containers + 1] = Shared.NormalizeContainer(entry)
	end
	table.sort(containers, function(a, b)
		return tostring(a.name):lower() < tostring(b.name):lower()
	end)

	return {
		version = DungeonRewards.VERSION,
		dataVersion = DungeonRewards.DATA_VERSION,
		isAdmin = Shared.PlayerHasAdminAccess(player),
		presets = world.presets or {},
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

local function grantItemReward(player, reward, summaries, errors)
	GrantUtils.grantItem(player, tostring(reward.item or reward.fullType or ""), reward.count, summaries, errors)
end

local function grantXpReward(player, reward, summaries, errors)
	GrantUtils.grantXp(player, reward.perk, reward.amount, summaries, errors)
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

	local world = getWorld()
	local preset = Shared.NormalizePreset(args and args.preset or {})
	local _, index = Shared.FindPreset(world, preset.id)
	if index then
		world.presets[index] = preset
	else
		world.presets[#world.presets + 1] = preset
	end
	saveWorld()
	Logger:info("%s saved Dungeon Rewards preset %s", tostring(Shared.GetPlayerKey(player)), tostring(preset.id))
	pushSnapshotToAll("Preset saved.", "info")
end

function Server.ServerCommands.DeletePreset(player, args)
	if not Shared.PlayerHasAdminAccess(player) then
		sendCommandResult(player, "Dungeon Rewards presets are admin-only.", "error")
		return
	end

	local world = getWorld()
	local presetId = tostring(args and args.presetId or "")
	local _, index = Shared.FindPreset(world, presetId)
	if not index then
		sendCommandResult(player, "Preset not found.", "error")
		return
	end
	table.remove(world.presets, index)
	for _, container in pairs(world.containers or {}) do
		if container.presetId == presetId then
			container.presetId = ""
		end
	end
	saveWorld()
	pushSnapshotToAll("Preset deleted.", "info")
end

function Server.ServerCommands.ImportPresets(player, args)
	if not Shared.PlayerHasAdminAccess(player) then
		sendCommandResult(player, "Dungeon Rewards presets are admin-only.", "error")
		return
	end
	local world = getWorld()
	world.presets = Shared.NormalizePresets(args and args.presets or {})
	saveWorld()
	pushSnapshotToAll("Presets imported.", "info")
end

function Server.ServerCommands.ResetPresets(player, args)
	if not Shared.PlayerHasAdminAccess(player) then
		sendCommandResult(player, "Dungeon Rewards presets are admin-only.", "error")
		return
	end
	local world = getWorld()
	world.presets = Shared.GetDefaultPresets()
	saveWorld()
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

	local world = getWorld()
	local existing = world.containers[descriptor.key] or {}
	descriptor.presetId = tostring(args and args.presetId or existing.presetId or descriptor.presetId or "")
	descriptor.createdAt = Shared.NormalizeTimestamp(existing.createdAt)
	descriptor.createdBy = existing.createdBy or Shared.GetPlayerKey(player) or "Admin"
	descriptor.updatedAt = Shared.NowTimestampString()
	world.containers[descriptor.key] = descriptor
	saveWorld()
	pushSnapshotToAll("Container registered.", "info")
end

function Server.ServerCommands.AssignContainerPreset(player, args)
	if not Shared.PlayerHasAdminAccess(player) then
		sendCommandResult(player, "Dungeon Rewards containers are admin-only.", "error")
		return
	end
	local world = getWorld()
	local key = tostring(args and args.containerKey or "")
	local container = world.containers[key]
	if not container then
		sendCommandResult(player, "Container not found.", "error")
		return
	end
	local presetId = tostring(args and args.presetId or "")
	if presetId ~= "" and not Shared.FindPreset(world, presetId) then
		sendCommandResult(player, "Preset not found.", "error")
		return
	end
	container.presetId = presetId
	container.enabled = not args or args.enabled ~= false
	container.updatedAt = Shared.NowTimestampString()
	saveWorld()
	pushSnapshotToAll("Container updated.", "info")
end

function Server.ServerCommands.DeleteContainer(player, args)
	if not Shared.PlayerHasAdminAccess(player) then
		sendCommandResult(player, "Dungeon Rewards containers are admin-only.", "error")
		return
	end
	local world = getWorld()
	world.containers[tostring(args and args.containerKey or "")] = nil
	saveWorld()
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
	if not getWorld().containers[key] then
		sendCommandResult(player, "Container not found.", "error")
		return
	end

	local count = RollService.resetContainer(key)
	pushSnapshotToAll(string.format("Container reuse enabled. Cleared %d player claim(s).", count), "info")
end

function Server.ServerCommands.RequestContainerRoll(player, args)
	if not player then
		return
	end
	local world = getWorld()
	local key = tostring(args and args.containerKey or "")
	local container = world.containers[key]
	if not container or container.enabled == false then
		sendCommandResult(player, "This is not an active Dungeon Rewards container.", "error")
		return
	end

	local preset = Shared.FindPreset(world, container.presetId)
	if not preset or preset.enabled == false or #(preset.rewards or {}) == 0 then
		sendCommandResult(player, "This container has no active preset.", "error")
		return
	end

	local playerId = Shared.GetPlayerKey(player)
	if preset.consumeOncePerPlayer and RollService.isClaimed(playerId, key) then
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

	local pending = RollService.getOrCreatePending(playerId, key, preset)
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
	local world = getWorld()
	local key = tostring(args and args.containerKey or "")
	local container = world.containers[key]
	if not container or container.enabled == false then
		sendCommandResult(player, "This is not an active Dungeon Rewards container.", "error")
		return
	end
	local preset = Shared.FindPreset(world, container.presetId)
	if not preset then
		sendCommandResult(player, "This container has no active preset.", "error")
		return
	end

	local playerId = Shared.GetPlayerKey(player)
	if preset.consumeOncePerPlayer and RollService.isClaimed(playerId, key) then
		sendCommandResult(player, "You already claimed this container.", "warning")
		return
	end

	local pending = RollService.getOrCreatePending(playerId, key, preset)
	local grant = Server.GrantRewards(player, pending.rolledRewards, {
		type = "dungeon-container",
		containerKey = key,
		presetId = preset.id,
		playerId = playerId,
	})
	RollService.markClaimed(playerId, key, pending)

	local message, level = summarizeGrant(grant)
	Logger:info(
		"%s claimed Dungeon Rewards container %s preset %s",
		tostring(playerId),
		tostring(key),
		tostring(preset.id)
	)
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

return DungeonRewards

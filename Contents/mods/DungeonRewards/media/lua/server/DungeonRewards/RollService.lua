local DungeonRewards = require("DungeonRewards/Shared")
local Persistence = require("DungeonRewards/Persistence")

local RollService = {}
local Shared = DungeonRewards.Shared

local ROLL_ATTEMPTS = 12
local RECENT_SIGNATURE_LIMIT = 40

RollService.MemoryPendingRolls = RollService.MemoryPendingRolls or {}
RollService.Store = nil

local function getStore()
	if not RollService.Store then
		RollService.Store = Persistence.loadPlayerRollStore()
	end
	return RollService.Store
end

local function saveStore()
	return Persistence.savePlayerRollStore(getStore())
end

local function getPlayerState(store, playerId)
	store.players[playerId] = type(store.players[playerId]) == "table" and store.players[playerId] or {}
	local state = store.players[playerId]
	state.claimed = type(state.claimed) == "table" and state.claimed or {}
	state.pendingRolls = type(state.pendingRolls) == "table" and state.pendingRolls or {}
	return state
end

local function getContainerState(store, containerKey)
	store.containers[containerKey] = type(store.containers[containerKey]) == "table" and store.containers[containerKey]
		or {}
	local state = store.containers[containerKey]
	state.recentSignatures = type(state.recentSignatures) == "table" and state.recentSignatures or {}
	return state
end

local function getRewardSignature(rewards)
	local parts = {}
	for i = 1, #(rewards or {}) do
		local reward = Shared.NormalizeReward(rewards[i], i)
		local target = reward.item or reward.perk or reward.trait or reward.handler or reward.id or ""
		parts[#parts + 1] = string.format(
			"%s:%s:%s:%s:%s",
			tostring(reward.type or ""),
			tostring(target),
			tostring(reward.count or reward.amount or ""),
			tostring(reward.mode or ""),
			tostring(reward.weight or "")
		)
	end
	table.sort(parts)
	return table.concat(parts, "|")
end

local function addRecentSignature(store, containerKey, signature)
	if not signature or signature == "" then
		return
	end
	local state = getContainerState(store, containerKey)
	local recent = state.recentSignatures
	for i = #recent, 1, -1 do
		if recent[i] == signature then
			table.remove(recent, i)
		end
	end
	recent[#recent + 1] = signature
	while #recent > RECENT_SIGNATURE_LIMIT do
		table.remove(recent, 1)
	end
end

local function buildAvoidSignatures(store, containerKey, playerId)
	local avoid = {}
	local containerState = getContainerState(store, containerKey)
	for i = 1, #(containerState.recentSignatures or {}) do
		avoid[containerState.recentSignatures[i]] = true
	end
	for otherPlayerId, state in pairs(store.players or {}) do
		if otherPlayerId ~= playerId and type(state) == "table" and type(state.pendingRolls) == "table" then
			local pending = state.pendingRolls[containerKey]
			if type(pending) == "table" and pending.signature then
				avoid[pending.signature] = true
			end
		end
	end
	return avoid
end

local function rollForPlayer(preset, store, containerKey, playerId)
	local avoid = buildAvoidSignatures(store, containerKey, playerId)
	local bestRewards = nil
	local bestSignature = nil
	for _ = 1, ROLL_ATTEMPTS do
		local rewards = Shared.RollRewards(preset)
		local signature = getRewardSignature(rewards)
		bestRewards = rewards
		bestSignature = signature
		if not avoid[signature] then
			return rewards, signature
		end
	end
	return bestRewards or Shared.RollRewards(preset), bestSignature or ""
end

function RollService.isClaimed(playerId, containerKey)
	return getPlayerState(getStore(), playerId).claimed[containerKey] ~= nil
end

function RollService.getPending(playerId, containerKey, presetId)
	local memory = RollService.MemoryPendingRolls[playerId]
	local pending = memory and memory[containerKey] or nil
	if type(pending) == "table" and tostring(pending.presetId or "") == tostring(presetId or "") then
		return pending
	end

	local state = getPlayerState(getStore(), playerId)
	pending = state.pendingRolls[containerKey]
	if type(pending) ~= "table" then
		return nil
	end
	if tostring(pending.presetId or "") ~= tostring(presetId or "") then
		state.pendingRolls[containerKey] = nil
		saveStore()
		return nil
	end
	if type(pending.rolledRewards) ~= "table" or #pending.rolledRewards == 0 then
		state.pendingRolls[containerKey] = nil
		saveStore()
		return nil
	end
	return pending
end

function RollService.getOrCreatePending(playerId, containerKey, preset)
	local pending = RollService.getPending(playerId, containerKey, preset.id)
	if pending then
		return pending
	end

	local store = getStore()
	local rewards, signature = rollForPlayer(preset, store, containerKey, playerId)
	pending = {
		presetId = tostring(preset.id or ""),
		rolledRewards = rewards,
		signature = signature or getRewardSignature(rewards),
		rolledAt = Shared.NowTimestampString(),
	}

	local state = getPlayerState(store, playerId)
	state.pendingRolls[containerKey] = pending
	RollService.MemoryPendingRolls[playerId] = type(RollService.MemoryPendingRolls[playerId]) == "table"
			and RollService.MemoryPendingRolls[playerId]
		or {}
	RollService.MemoryPendingRolls[playerId][containerKey] = pending
	saveStore()
	return pending
end

function RollService.markClaimed(playerId, containerKey, pending)
	local store = getStore()
	local state = getPlayerState(store, playerId)
	state.claimed[containerKey] = Shared.NowTimestampString()
	state.pendingRolls[containerKey] = nil
	if RollService.MemoryPendingRolls[playerId] then
		RollService.MemoryPendingRolls[playerId][containerKey] = nil
	end
	addRecentSignature(
		store,
		containerKey,
		pending and pending.signature or getRewardSignature(pending and pending.rolledRewards)
	)
	saveStore()
end

function RollService.resetContainer(containerKey)
	local store = getStore()
	local count = 0
	for playerId, state in pairs(store.players or {}) do
		if type(state) == "table" then
			if type(state.claimed) == "table" and state.claimed[containerKey] ~= nil then
				state.claimed[containerKey] = nil
				count = count + 1
			end
			if type(state.pendingRolls) == "table" then
				state.pendingRolls[containerKey] = nil
			end
		end
		if RollService.MemoryPendingRolls[playerId] then
			RollService.MemoryPendingRolls[playerId][containerKey] = nil
		end
	end
	store.containers[containerKey] = nil
	saveStore()
	return count
end

return RollService

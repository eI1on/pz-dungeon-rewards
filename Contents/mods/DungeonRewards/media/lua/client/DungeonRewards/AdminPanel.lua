require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISTickBox"

local DungeonRewards = require("DungeonRewards/Shared")
local ColorUtils = require("ElyonLib/ColorUtils/ColorUtils")
local MathUtils = require("ElyonLib/MathUtils/MathUtils")
local TextUtils = require("ElyonLib/TextUtils/TextUtils")
local UIUtils = require("ElyonLib/UI/Utils/UIUtils")
local Theme = require("ElyonLib/UI/Theme/Theme")

local AdminPanel = ISCollapsableWindow:derive("DungeonRewardsAdminPanel")
AdminPanel.instance = nil

local Shared = DungeonRewards.Shared
local copyColor = ColorUtils.copy
local parseNumber = MathUtils.parseNumber
local trim = TextUtils.trim
local trimToWidth = TextUtils.trimToWidth
local getEntryText = UIUtils.getEntryText
local setBounds = UIUtils.setBounds
local setEntryText = UIUtils.setEntryText

local FONT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)

local C = {
    SIZE = {
        W = 850, H = 600, MIN_W = 850, MIN_H = 600,
    },
    LAYOUT = {
        PAD = 12, GAP = 8, TOP = 34,
    },
    CTRL = {
        BUTTON_H = 24, FIELD_H = 22,
    },
    LIST = {
        ROW        = 38,
        REWARD_ROW = 44,
        SCROLL_W   = 18,
    },
    ANIM = {
        NOTICE_TICKS = 300,
    },
    COLORS = Theme.standardColors(),
}

local REWARD_TYPES = {
    { label = getText("IGUI_DRewards_RewardType_Item"),   data = "item" },
    { label = getText("IGUI_DRewards_RewardType_XP"),     data = "xp" },
    { label = getText("IGUI_DRewards_RewardType_Trait"),  data = "trait" },
    { label = getText("IGUI_DRewards_RewardType_Custom"), data = "custom" },
}

local function applyButtonStyle(button, variant)
    Theme.applyButtonStyle(button, variant)
end

local function addButton(panel, x, y, w, text, internal, variant)
    local button = ISButton:new(x, y, w, C.CTRL.BUTTON_H, text, panel, AdminPanel.onClick)
    button.internal = internal
    button:initialise()
    button:instantiate()
    applyButtonStyle(button, variant)
    panel:addChild(button)
    return button
end

local function addEntry(panel, x, y, w, h, multiline)
    local entry = ISTextEntryBox:new("", x, y, w, h)
    entry:initialise()
    entry:instantiate()
    if multiline then
        entry:setMultipleLine(true)
        entry:setMaxLines(1000)
    end
    Theme.applyFieldStyle(entry)
    panel:addChild(entry)
    return entry
end

local function styleList(list)
    Theme.applyListStyle(list)
    list.drawBorder = true
end

local function rewardTargetText(reward)
    reward = reward or {}
    if reward.type == "item" then
        return tostring(reward.item or "")
    elseif reward.type == "xp" then
        return tostring(reward.perk or "")
    elseif reward.type == "trait" then
        return tostring(reward.trait or "")
    elseif reward.type == "custom" then
        return tostring(reward.handler or "")
    end
    return ""
end

local function rewardValueText(reward)
    reward = reward or {}
    if reward.type == "item" then
        return "x" .. tostring(reward.count or 1)
    elseif reward.type == "xp" then
        return "+" .. tostring(reward.amount or 0)
    elseif reward.type == "trait" then
        return tostring(reward.mode or "add")
    end
    return ""
end

local function copyRewards(rewards)
    local out = {}
    for i = 1, #(rewards or {}) do
        out[#out + 1] = Shared.NormalizeReward(rewards[i], i)
    end
    return out
end

function AdminPanel:new(x, y, width, height, playerObj)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    setmetatable(o, self)
    self.__index           = self
    o.playerObj            = playerObj or getPlayer()
    o.snapshot             = DungeonRewards.ClientSnapshot or {}
    o.selectedPresetId     = nil
    o.selectedContainerKey = DungeonRewards.ActiveContainer
    o.selectedRewardIndex  = 1
    o.workingRewards       = {}
    o.loadingReward        = false
    o.statusMessage        = getText("IGUI_DRewards_StatusWaiting")
    o.statusLevel          = "info"
    o.statusTicks          = C.ANIM.NOTICE_TICKS
    o.backgroundColor      = Theme.copy(Theme.colors.background)
    o.borderColor          = Theme.copy(Theme.colors.border)
    o.title                = getText("IGUI_DRewards_AdminTitle")
    o.minimumWidth         = C.SIZE.MIN_W
    o.minimumHeight        = C.SIZE.MIN_H
    return o
end

function AdminPanel:initialise()
    ISCollapsableWindow.initialise(self)
end

function AdminPanel:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:setResizable(true)

    self.presetsList = ISScrollingListBox:new(0, 0, 100, 100)
    self.presetsList:initialise()
    self.presetsList:instantiate()
    self.presetsList.itemheight = C.LIST.ROW
    self.presetsList.parentPanel = self
    self.presetsList.doDrawItem = AdminPanel.drawPresetItem
    self.presetsList.onMouseDown = AdminPanel.onPresetMouseDown
    styleList(self.presetsList)
    self:addChild(self.presetsList)

    self.containersList = ISScrollingListBox:new(0, 0, 100, 100)
    self.containersList:initialise()
    self.containersList:instantiate()
    self.containersList.itemheight = C.LIST.ROW
    self.containersList.parentPanel = self
    self.containersList.doDrawItem = AdminPanel.drawContainerItem
    self.containersList.onMouseDown = AdminPanel.onContainerMouseDown
    styleList(self.containersList)
    self:addChild(self.containersList)

    self.refreshBtn = addButton(self, 0, 0, 88, getText("IGUI_DRewards_Refresh"), "REFRESH")
    self.importBtn = addButton(self, 0, 0, 80, getText("IGUI_DRewards_Import"), "IMPORT")
    self.exportBtn = addButton(self, 0, 0, 80, getText("IGUI_DRewards_Export"), "EXPORT")
    self.resetBtn = addButton(self, 0, 0, 104, getText("IGUI_DRewards_Reset"), "RESET", "danger")

    self.presetIdEntry = addEntry(self, 0, 0, 100, C.CTRL.FIELD_H)
    self.presetNameEntry = addEntry(self, 0, 0, 100, C.CTRL.FIELD_H)
    self.rollCountEntry = addEntry(self, 0, 0, 44, C.CTRL.FIELD_H)
    self.descriptionEntry = addEntry(self, 0, 0, 100, 42, true)
    self.enabledTick = ISTickBox:new(0, 0, 84, C.CTRL.FIELD_H, "", self, AdminPanel.onTickChanged)
    self.enabledTick:initialise()
    self.enabledTick:addOption(getText("IGUI_DRewards_Enabled"))
    self:addChild(self.enabledTick)
    self.duplicatesTick = ISTickBox:new(0, 0, 124, C.CTRL.FIELD_H, "", self, AdminPanel.onTickChanged)
    self.duplicatesTick:initialise()
    self.duplicatesTick:addOption(getText("IGUI_DRewards_AllowDuplicates"))
    self:addChild(self.duplicatesTick)
    self.onceTick = ISTickBox:new(0, 0, 138, C.CTRL.FIELD_H, "", self, AdminPanel.onTickChanged)
    self.onceTick:initialise()
    self.onceTick:addOption(getText("IGUI_DRewards_OncePerPlayer"))
    self:addChild(self.onceTick)

    self.newPresetBtn = addButton(self, 0, 0, 92, getText("IGUI_DRewards_NewPreset"), "NEW_PRESET")
    self.savePresetBtn = addButton(self, 0, 0, 104, getText("IGUI_DRewards_SavePreset"), "SAVE_PRESET", "primary")
    self.deletePresetBtn = addButton(self, 0, 0, 104, getText("IGUI_DRewards_DeletePreset"), "DELETE_PRESET", "danger")

    self.rewardsList = ISScrollingListBox:new(0, 0, 100, 100)
    self.rewardsList:initialise()
    self.rewardsList:instantiate()
    self.rewardsList.itemheight = C.LIST.REWARD_ROW
    self.rewardsList.parentPanel = self
    self.rewardsList.doDrawItem = AdminPanel.drawRewardItem
    self.rewardsList.onMouseDown = AdminPanel.onRewardMouseDown
    styleList(self.rewardsList)
    self:addChild(self.rewardsList)

    self.addRewardBtn = addButton(self, 0, 0, 84, getText("IGUI_DRewards_AddReward"), "ADD_REWARD")
    self.applyRewardBtn = addButton(self, 0, 0, 90, getText("IGUI_DRewards_ApplyReward"), "APPLY_REWARD", "primary")
    self.deleteRewardBtn = addButton(self, 0, 0, 94, getText("IGUI_DRewards_DeleteReward"), "DELETE_REWARD", "danger")
    self.autoWeightBtn = addButton(self, 0, 0, 118, getText("IGUI_DRewards_AutoWeights"), "AUTO_WEIGHTS")

    self.rewardTypeCombo = ISComboBox:new(0, 0, 100, C.CTRL.FIELD_H, self, AdminPanel.onRewardTypeChanged)
    self.rewardTypeCombo:initialise()
    self:addChild(self.rewardTypeCombo)
    for i = 1, #REWARD_TYPES do
        self.rewardTypeCombo:addOptionWithData(REWARD_TYPES[i].label, REWARD_TYPES[i].data)
    end

    self.rewardTitleEntry = addEntry(self, 0, 0, 100, C.CTRL.FIELD_H)
    self.rewardTargetEntry = addEntry(self, 0, 0, 100, C.CTRL.FIELD_H)
    self.rewardCountEntry = addEntry(self, 0, 0, 56, C.CTRL.FIELD_H)
    self.rewardWeightEntry = addEntry(self, 0, 0, 56, C.CTRL.FIELD_H)
    self.weightMinusBtn = addButton(self, 0, 0, 26, "-", "WEIGHT_MINUS")
    self.weightPlusBtn = addButton(self, 0, 0, 26, "+", "WEIGHT_PLUS")
    self.rewardModeCombo = ISComboBox:new(0, 0, 84, C.CTRL.FIELD_H, self, AdminPanel.onRewardTypeChanged)
    self.rewardModeCombo:initialise()
    self.rewardModeCombo:addOptionWithData("add", "add")
    self.rewardModeCombo:addOptionWithData("remove", "remove")
    self:addChild(self.rewardModeCombo)

    self.assignCombo = ISComboBox:new(0, 0, 100, C.CTRL.FIELD_H, self, AdminPanel.onPresetComboChanged)
    self.assignCombo:initialise()
    self:addChild(self.assignCombo)
    self.assignBtn = addButton(self, 0, 0, 96, getText("IGUI_DRewards_Assign"), "ASSIGN", "primary")
    self.removeContainerBtn = addButton(self, 0, 0, 130, getText("IGUI_DRewards_RemoveContainer"), "REMOVE_CONTAINER",
        "danger")
    self.resetClaimsBtn = addButton(self, 0, 0, 122, getText("IGUI_DRewards_ResetClaims"), "RESET_CLAIMS")
end

function AdminPanel:layoutChildren()
    if self.isCollapsed then
        return
    end

    local pad = C.LAYOUT.PAD
    local leftW = math.max(270, math.min(310, math.floor(self.width * 0.31)))
    local contentX = pad + leftW + C.LAYOUT.GAP
    local contentW = self.width - contentX - pad
    local bottomY = self.height - pad - FONT_SMALL - 8
    local y = C.LAYOUT.TOP

    setBounds(self.refreshBtn, pad, y, 88, C.CTRL.BUTTON_H)
    setBounds(self.importBtn, pad + 96, y, 78, C.CTRL.BUTTON_H)
    setBounds(self.exportBtn, pad + 182, y, 78, C.CTRL.BUTTON_H)
    setBounds(self.resetBtn, pad, y + C.CTRL.BUTTON_H + C.LAYOUT.GAP, leftW, C.CTRL.BUTTON_H)

    local listTop = self.resetBtn:getY() + C.CTRL.BUTTON_H + 28
    local listGap = 32
    local containerToolsH = C.CTRL.FIELD_H + C.LAYOUT.GAP + C.CTRL.BUTTON_H + 48
    local listH = math.floor((bottomY - listTop - listGap - C.CTRL.BUTTON_H - C.LAYOUT.GAP - containerToolsH) * 0.50)
    listH = math.max(150, listH)
    setBounds(self.presetsList, pad, listTop, leftW, listH)
    local containersY = listTop + listH + listGap
    local containersH = math.max(130, bottomY - containersY - C.CTRL.BUTTON_H - C.LAYOUT.GAP - containerToolsH)
    setBounds(self.containersList, pad, containersY, leftW, containersH)

    local assignY = self.containersList:getY() + self.containersList:getHeight() + 28
    setBounds(self.assignCombo, pad, assignY, leftW, C.CTRL.FIELD_H)
    local smallButtonW = math.floor((leftW - C.LAYOUT.GAP) / 2)
    setBounds(self.assignBtn, pad, assignY + C.CTRL.FIELD_H + C.LAYOUT.GAP, smallButtonW, C.CTRL.BUTTON_H)
    setBounds(self.resetClaimsBtn, pad + smallButtonW + C.LAYOUT.GAP, assignY + C.CTRL.FIELD_H + C.LAYOUT.GAP,
        leftW - smallButtonW -
        C.LAYOUT.GAP, C.CTRL.BUTTON_H)
    setBounds(self.removeContainerBtn, pad, assignY + C.CTRL.FIELD_H + C.LAYOUT.GAP + C.CTRL.BUTTON_H + C.LAYOUT.GAP,
        leftW,
        C.CTRL.BUTTON_H)

    local presetY = C.LAYOUT.TOP + 28
    local smallW = math.max(112, math.floor((contentW - C.LAYOUT.GAP * 3) * 0.22))
    local nameW = math.max(190, contentW - smallW - 78 - C.LAYOUT.GAP * 2)
    setBounds(self.presetIdEntry, contentX, presetY + 18, smallW, C.CTRL.FIELD_H)
    setBounds(self.presetNameEntry, contentX + smallW + C.LAYOUT.GAP, presetY + 18, nameW, C.CTRL.FIELD_H)
    setBounds(self.rollCountEntry, contentX + smallW + nameW + C.LAYOUT.GAP * 2, presetY + 18, 58, C.CTRL.FIELD_H)
    local ticksY = presetY + 48
    setBounds(self.enabledTick, contentX, ticksY, 100, C.CTRL.FIELD_H)
    setBounds(self.duplicatesTick, contentX + 112, ticksY, 124, C.CTRL.FIELD_H)
    setBounds(self.onceTick, contentX + 248, ticksY, math.min(150, contentW - 248), C.CTRL.FIELD_H)
    setBounds(self.descriptionEntry, contentX, presetY + 88, contentW, 42)
    setBounds(self.newPresetBtn, contentX, presetY + 140, 92, C.CTRL.BUTTON_H)
    setBounds(self.savePresetBtn, contentX + 100, presetY + 140, 106, C.CTRL.BUTTON_H)
    setBounds(self.deletePresetBtn, contentX + 214, presetY + 140, 112, C.CTRL.BUTTON_H)

    local rewardTop = presetY + 198
    local rewardListW = math.max(300, math.floor(contentW * 0.48))
    local rewardH = math.max(220, bottomY - rewardTop - 76)
    setBounds(self.rewardsList, contentX, rewardTop, rewardListW, rewardH)
    setBounds(self.addRewardBtn, contentX, rewardTop + rewardH + C.LAYOUT.GAP, 84, C.CTRL.BUTTON_H)
    setBounds(self.applyRewardBtn, contentX + 92, rewardTop + rewardH + C.LAYOUT.GAP, 92, C.CTRL.BUTTON_H)
    setBounds(self.deleteRewardBtn, contentX + 192, rewardTop + rewardH + C.LAYOUT.GAP, 100, C.CTRL.BUTTON_H)
    setBounds(self.autoWeightBtn, contentX + 300, rewardTop + rewardH + C.LAYOUT.GAP, 122, C.CTRL.BUTTON_H)

    local editorX = contentX + rewardListW + C.LAYOUT.GAP
    local editorW = contentW - rewardListW - C.LAYOUT.GAP
    local fieldY = rewardTop + 20
    local typeW = math.min(112, math.max(86, math.floor(editorW * 0.38)))
    setBounds(self.rewardTypeCombo, editorX, fieldY, typeW, C.CTRL.FIELD_H)
    setBounds(self.rewardTitleEntry, editorX + typeW + C.LAYOUT.GAP, fieldY, math.max(92, editorW - typeW - C.LAYOUT.GAP),
        C.CTRL.FIELD_H)
    fieldY = fieldY + 52
    setBounds(self.rewardTargetEntry, editorX, fieldY, editorW, C.CTRL.FIELD_H)
    fieldY = fieldY + 52
    setBounds(self.rewardCountEntry, editorX, fieldY, 72, C.CTRL.FIELD_H)
    setBounds(self.rewardModeCombo, editorX + 80, fieldY, 82, C.CTRL.FIELD_H)
    if editorW >= 316 then
        setBounds(self.rewardWeightEntry, editorX + 174, fieldY, 68, C.CTRL.FIELD_H)
        setBounds(self.weightMinusBtn, editorX + 250, fieldY, 26, C.CTRL.BUTTON_H)
        setBounds(self.weightPlusBtn, editorX + 282, fieldY, 26, C.CTRL.BUTTON_H)
    else
        setBounds(self.rewardWeightEntry, editorX, fieldY + 48, 68, C.CTRL.FIELD_H)
        setBounds(self.weightMinusBtn, editorX + 76, fieldY + 48, 26, C.CTRL.BUTTON_H)
        setBounds(self.weightPlusBtn, editorX + 108, fieldY + 48, 26, C.CTRL.BUTTON_H)
    end
end

function AdminPanel:setStatus(message, level)
    self.statusMessage = tostring(message or "")
    self.statusLevel = level or "info"
    self.statusTicks = self.statusMessage ~= "" and C.ANIM.NOTICE_TICKS or 0
end

function AdminPanel:onSnapshotReceived(snapshot)
    self.snapshot = snapshot or {}
    if self.snapshot.message then
        self:setStatus(self.snapshot.message, self.snapshot.level)
    end
    self:populateLists()
end

function AdminPanel:getSelectedPreset()
    for i = 1, #(self.snapshot.presets or {}) do
        if self.snapshot.presets[i].id == self.selectedPresetId then
            return self.snapshot.presets[i]
        end
    end
    return (self.snapshot.presets or {})[1]
end

function AdminPanel:getSelectedContainer()
    for i = 1, #(self.snapshot.containers or {}) do
        if self.snapshot.containers[i].key == self.selectedContainerKey then
            return self.snapshot.containers[i]
        end
    end
    return nil
end

function AdminPanel:populateLists()
    self.presetsList:clear()
    for i = 1, #(self.snapshot.presets or {}) do
        local preset = self.snapshot.presets[i]
        self.presetsList:addItem(preset.name, preset)
        if not self.selectedPresetId then
            self.selectedPresetId = preset.id
        end
    end

    self.containersList:clear()
    for i = 1, #(self.snapshot.containers or {}) do
        self.containersList:addItem(self.snapshot.containers[i].name, self.snapshot.containers[i])
    end

    self.assignCombo:clear()
    for i = 1, #(self.snapshot.presets or {}) do
        local preset = self.snapshot.presets[i]
        self.assignCombo:addOptionWithData(preset.name, preset.id)
    end

    self:loadPresetIntoEditor(self:getSelectedPreset())
    self:updateAssignCombo()
end

function AdminPanel:populateRewardsList()
    self.rewardsList:clear()
    for i = 1, #self.workingRewards do
        local reward = self.workingRewards[i]
        self.rewardsList:addItem(reward.title or reward.id or tostring(i), reward)
    end
    self.selectedRewardIndex = math.max(1, math.min(self.selectedRewardIndex or 1, #self.workingRewards))
    self.rewardsList.selected = self.selectedRewardIndex
end

function AdminPanel:loadPresetIntoEditor(preset)
    preset = preset or Shared.NormalizePreset({})
    self.selectedPresetId = preset.id
    self.selectedRewardIndex = 1
    self.workingRewards = copyRewards(preset.rewards)
    setEntryText(self.presetIdEntry, preset.id)
    setEntryText(self.presetNameEntry, preset.name)
    setEntryText(self.rollCountEntry, tostring(preset.rollCount or 1))
    setEntryText(self.descriptionEntry, preset.description or "")
    self.enabledTick:setSelected(1, preset.enabled ~= false)
    self.duplicatesTick:setSelected(1, preset.allowDuplicates == true)
    self.onceTick:setSelected(1, preset.consumeOncePerPlayer ~= false)
    self:populateRewardsList()
    self:loadRewardIntoEditor(self.workingRewards[self.selectedRewardIndex])
end

function AdminPanel:selectRewardType(rewardType)
    for i = 1, #self.rewardTypeCombo.options do
        if self.rewardTypeCombo:getOptionData(i) == rewardType then
            self.rewardTypeCombo.selected = i
            return
        end
    end
    self.rewardTypeCombo.selected = 1
end

function AdminPanel:loadRewardIntoEditor(reward)
    reward = reward or
        Shared.NormalizeReward({ type = "item", item = "Base.WaterBottleFull", count = 1, weight = 10 }, 1)
    self.loadingReward = true
    self:selectRewardType(reward.type)
    setEntryText(self.rewardTitleEntry, reward.title or "")
    setEntryText(self.rewardTargetEntry, rewardTargetText(reward))
    setEntryText(self.rewardCountEntry, tostring(reward.count or reward.amount or 1))
    setEntryText(self.rewardWeightEntry, tostring(reward.weight or 10))
    self.rewardModeCombo:selectData(reward.mode or "add")
    self.loadingReward = false
end

function AdminPanel:getRewardType()
    return self.rewardTypeCombo:getOptionData(self.rewardTypeCombo.selected) or "item"
end

function AdminPanel:buildRewardFromEditor()
    local rewardType = self:getRewardType()
    local target = trim(getEntryText(self.rewardTargetEntry))
    local amount = parseNumber(getEntryText(self.rewardCountEntry), 1, -100000, 100000) or 1
    local reward = {
        id = self.workingRewards[self.selectedRewardIndex] and self.workingRewards[self.selectedRewardIndex].id or
            Shared.GenerateID("reward"),
        type = rewardType,
        title = trim(getEntryText(self.rewardTitleEntry)),
        weight = parseNumber(getEntryText(self.rewardWeightEntry), 10, 0, 100000) or 10,
    }
    if rewardType == "item" then
        reward.item = target
        reward.count = math.floor(parseNumber(amount, 1, 1, 999) or 1)
        if target == "" then
            return nil, getText("IGUI_DRewards_ErrorMissingItem")
        end
        if ScriptManager and ScriptManager.instance and not ScriptManager.instance:getItem(target) then
            return nil, getText("IGUI_DRewards_ErrorInvalidItem") .. " " .. target
        end
    elseif rewardType == "xp" then
        reward.perk = target
        reward.amount = amount
        if target == "" or amount == 0 then
            return nil, getText("IGUI_DRewards_ErrorInvalidAmount")
        end
    elseif rewardType == "trait" then
        reward.trait = target
        reward.mode = self.rewardModeCombo:getOptionData(self.rewardModeCombo.selected) or "add"
        if target == "" then
            return nil, getText("IGUI_DRewards_ErrorMissingTrait")
        end
    elseif rewardType == "custom" then
        reward.handler = target
        if target == "" then
            return nil, getText("IGUI_DRewards_ErrorMissingHandler")
        end
    end
    return Shared.NormalizeReward(reward, self.selectedRewardIndex)
end

function AdminPanel:buildPresetFromEditor()
    return Shared.NormalizePreset({
        id = trim(getEntryText(self.presetIdEntry)),
        name = trim(getEntryText(self.presetNameEntry)),
        description = getEntryText(self.descriptionEntry),
        enabled = self.enabledTick:isSelected(1),
        allowDuplicates = self.duplicatesTick:isSelected(1),
        consumeOncePerPlayer = self.onceTick:isSelected(1),
        rollCount = math.floor(parseNumber(getEntryText(self.rollCountEntry), 1, 1, 200) or 1),
        rewards = self.workingRewards,
    })
end

function AdminPanel:updateAssignCombo()
    local container = self:getSelectedContainer()
    if not container then
        return
    end
    for i = 1, #self.assignCombo.options do
        if self.assignCombo:getOptionData(i) == container.presetId then
            self.assignCombo.selected = i
            return
        end
    end
end

function AdminPanel:exportPresets()
    local success = Shared.SavePresetsToFile(self.snapshot.presets or {})
    self:setStatus(success and getText("IGUI_DRewards_StatusExported") or getText("IGUI_DRewards_StatusExportFailed"),
        success and "info" or "error")
end

function AdminPanel:importPresets()
    local presets = Shared.LoadPresetsFromFile()
    if type(presets) ~= "table" then
        self:setStatus(getText("IGUI_DRewards_StatusImportFailed"), "error")
        return
    end
    Shared.ExecuteCommand("ImportPresets", { presets = presets })
end

function AdminPanel:autoWeights()
    for i = 1, #self.workingRewards do
        self.workingRewards[i].weight = 10
    end
    self:populateRewardsList()
    self:loadRewardIntoEditor(self.workingRewards[self.selectedRewardIndex])
end

function AdminPanel:changeWeight(delta)
    local weight = math.floor(parseNumber(getEntryText(self.rewardWeightEntry), 10, 0, 100000) or 10)
    weight = math.max(0, weight + delta)
    setEntryText(self.rewardWeightEntry, tostring(weight))
end

function AdminPanel:onClick(button)
    local action = button.internal
    if action == "REFRESH" then
        Shared.ExecuteCommand("RequestSnapshot", {})
    elseif action == "SAVE_PRESET" then
        local reward, err = self:buildRewardFromEditor()
        if reward and self.workingRewards[self.selectedRewardIndex] then
            self.workingRewards[self.selectedRewardIndex] = reward
        elseif err and #self.workingRewards > 0 then
            self:setStatus(err, "error")
            return
        end
        Shared.ExecuteCommand("SavePreset", { preset = self:buildPresetFromEditor() })
    elseif action == "NEW_PRESET" then
        self:loadPresetIntoEditor(Shared.NormalizePreset({ id = Shared.GenerateID("preset"), name = "New Preset" }))
    elseif action == "DELETE_PRESET" then
        Shared.ExecuteCommand("DeletePreset", { presetId = self.selectedPresetId })
    elseif action == "IMPORT" then
        self:importPresets()
    elseif action == "EXPORT" then
        self:exportPresets()
    elseif action == "RESET" then
        Shared.ExecuteCommand("ResetPresets", {})
    elseif action == "ADD_REWARD" then
        self.workingRewards[#self.workingRewards + 1] = Shared.NormalizeReward({
            type = "item",
            weight = 10,
            item = "Base.WaterBottleFull",
            count = 1
        }, #self.workingRewards + 1)
        self.selectedRewardIndex = #self.workingRewards
        self:populateRewardsList()
        self:loadRewardIntoEditor(self.workingRewards[self.selectedRewardIndex])
    elseif action == "APPLY_REWARD" then
        local reward, err = self:buildRewardFromEditor()
        if not reward then
            self:setStatus(err or getText("IGUI_DRewards_ErrorRewardInvalid"), "error")
            return
        end
        self.workingRewards[self.selectedRewardIndex] = reward
        self:populateRewardsList()
        self:setStatus(getText("IGUI_DRewards_StatusRewardApplied"), "info")
    elseif action == "DELETE_REWARD" then
        if self.workingRewards[self.selectedRewardIndex] then
            table.remove(self.workingRewards, self.selectedRewardIndex)
            self.selectedRewardIndex = math.max(1, math.min(self.selectedRewardIndex, #self.workingRewards))
            self:populateRewardsList()
            self:loadRewardIntoEditor(self.workingRewards[self.selectedRewardIndex])
        end
    elseif action == "AUTO_WEIGHTS" then
        self:autoWeights()
    elseif action == "WEIGHT_MINUS" then
        self:changeWeight(-1)
    elseif action == "WEIGHT_PLUS" then
        self:changeWeight(1)
    elseif action == "ASSIGN" then
        local container = self:getSelectedContainer()
        if container then
            Shared.ExecuteCommand("AssignContainerPreset", {
                containerKey = container.key,
                presetId = self.assignCombo:getOptionData(self.assignCombo.selected),
                enabled = true,
            })
        end
    elseif action == "REMOVE_CONTAINER" then
        local container = self:getSelectedContainer()
        if container then
            Shared.ExecuteCommand("DeleteContainer", { containerKey = container.key })
        end
    elseif action == "RESET_CLAIMS" then
        local container = self:getSelectedContainer()
        if container then
            Shared.ExecuteCommand("ResetContainerClaims", { containerKey = container.key })
        end
    end
end

function AdminPanel.onTickChanged(target, index, selected)
end

function AdminPanel.onPresetComboChanged(target, combo)
end

function AdminPanel.onRewardTypeChanged(target, combo)
    if target and target.rewardModeCombo then
        local rewardType = target:getRewardType()
        target.rewardModeCombo:setVisible(rewardType == "trait")
        if not target.loadingReward and combo == target.rewardTypeCombo then
            setEntryText(target.rewardTitleEntry, "")
            setEntryText(target.rewardTargetEntry, "")
            setEntryText(target.rewardCountEntry, rewardType == "xp" and "50" or "1")
            setEntryText(target.rewardWeightEntry, "10")
            target.rewardModeCombo:selectData("add")
        end
    end
end

function AdminPanel.onPresetMouseDown(list, x, y)
    local row = list:rowAt(x, y)
    if row < 1 or row > #list.items then
        return true
    end
    list.selected = row
    local panel = list.parentPanel
    panel:loadPresetIntoEditor(list.items[row].item)
    return true
end

function AdminPanel.onContainerMouseDown(list, x, y)
    local row = list:rowAt(x, y)
    if row < 1 or row > #list.items then
        return true
    end
    list.selected = row
    local panel = list.parentPanel
    panel.selectedContainerKey = list.items[row].item.key
    panel:updateAssignCombo()
    return true
end

function AdminPanel.onRewardMouseDown(list, x, y)
    local row = list:rowAt(x, y)
    if row < 1 or row > #list.items then
        return true
    end
    local panel = list.parentPanel
    local current, err = panel:buildRewardFromEditor()
    if current and panel.workingRewards[panel.selectedRewardIndex] then
        panel.workingRewards[panel.selectedRewardIndex] = current
    elseif err then
        panel:setStatus(err, "warning")
    end
    list.selected = row
    panel.selectedRewardIndex = row
    panel:loadRewardIntoEditor(panel.workingRewards[row])
    return true
end

function AdminPanel.drawPresetItem(list, y, item, alt)
    local preset = item.item
    local selected = list.selected == item.index or (list.parentPanel and list.parentPanel.selectedPresetId == preset.id)
    local bg = selected and C.COLORS.SELECTED or (alt and C.COLORS.ALT or C.COLORS.FIELD)
    local total = Shared.GetPresetWeightTotal(preset)
    local contentW = list:getWidth() - C.LIST.SCROLL_W
    list:drawRect(0, y, list:getWidth(), list.itemheight - 1, bg.a, bg.r, bg.g, bg.b)
    list:drawText(trimToWidth(UIFont.Small, preset.name, contentW - 12), 8, y + 4, C.COLORS.TEXT.r,
        C.COLORS.TEXT.g, C.COLORS.TEXT.b, 1, UIFont.Small)
    list:drawText(trimToWidth(UIFont.Small,
        string.format("%d rolls | %d rewards | %d weight", preset.rollCount or 1, #(preset.rewards or {}), total),
        contentW - 12), 8, y + 21, C.COLORS.MUTED.r, C.COLORS.MUTED.g, C.COLORS.MUTED.b, 1, UIFont.Small)
    return y + list.itemheight
end

function AdminPanel.drawContainerItem(list, y, item, alt)
    local container = item.item
    local selected = list.selected == item.index or
        (list.parentPanel and list.parentPanel.selectedContainerKey == container.key)
    local bg = selected and C.COLORS.SELECTED or (alt and C.COLORS.ALT or C.COLORS.FIELD)
    local contentW = list:getWidth() - C.LIST.SCROLL_W
    list:drawRect(0, y, list:getWidth(), list.itemheight - 1, bg.a, bg.r, bg.g, bg.b)
    list:drawText(trimToWidth(UIFont.Small, container.name or container.key, contentW - 12), 8, y + 4,
        C.COLORS.TEXT.r, C.COLORS.TEXT.g, C.COLORS.TEXT.b, 1, UIFont.Small)
    list:drawText(trimToWidth(UIFont.Small,
            string.format("%d,%d,%d | %s", container.x or 0, container.y or 0, container.z or 0,
                container.presetId ~= "" and container.presetId or "No preset"), contentW - 12), 8, y + 21,
        C.COLORS.MUTED.r, C.COLORS.MUTED.g, C.COLORS.MUTED.b, 1, UIFont.Small)
    return y + list.itemheight
end

function AdminPanel.drawRewardItem(list, y, item, alt)
    local panel = list.parentPanel
    local reward = item.item
    local selected = list.selected == item.index or (panel and panel.selectedRewardIndex == item.index)
    local bg = selected and C.COLORS.SELECTED or (alt and C.COLORS.ALT or C.COLORS.FIELD)
    local total = Shared.GetPresetWeightTotal({ rewards = panel and panel.workingRewards or {} })
    local pct = total > 0 and math.floor(((reward.weight or 0) / total) * 100 + 0.5) or 0
    local fullW = list:getWidth()
    local w = fullW - C.LIST.SCROLL_W
    list:drawRect(0, y, fullW, list.itemheight - 1, bg.a, bg.r, bg.g, bg.b)
    list:drawText(trimToWidth(UIFont.Small,
        string.format("%s | %s", tostring(reward.type or "?"):upper(), reward.title or Shared.GetRewardSummary(reward)),
        w - 94), 8, y + 4, C.COLORS.TEXT.r, C.COLORS.TEXT.g, C.COLORS.TEXT.b, 1, UIFont.Small)
    list:drawText(trimToWidth(UIFont.Small, rewardTargetText(reward) .. " " .. rewardValueText(reward), w - 110), 8,
        y + 23, C.COLORS.MUTED.r, C.COLORS.MUTED.g, C.COLORS.MUTED.b, 1, UIFont.Small)
    list:drawTextRight(string.format("w%s %d%%", tostring(reward.weight or 0), pct), w - 8, y + 13, C.COLORS.GOLD.r,
        C.COLORS.GOLD.g, C.COLORS.GOLD.b, 1, UIFont.Small)
    return y + list.itemheight
end

function AdminPanel:drawLabel(text, x, y, w)
    self:drawText(trimToWidth(UIFont.Small, text, w or 200), x, y, C.COLORS.MUTED.r, C.COLORS.MUTED.g, C.COLORS.MUTED.b,
        1, UIFont.Small)
end

function AdminPanel:drawSectionTitle(text, x, y, w)
    local T = Theme.colors
    self:drawText(text, x, y, T.text.r, T.text.g, T.text.b, 1, UIFont.Medium)
    self:drawRect(x, y + FONT_MEDIUM + 3, w, 1, T.borderLight.a, T.borderLight.r, T.borderLight.g, T.borderLight.b)
end

function AdminPanel:drawLabels()
    self:drawSectionTitle(getText("IGUI_DRewards_Presets"), self.presetsList:getX(), self.presetsList:getY() -
        FONT_MEDIUM - 8, self.presetsList:getWidth())
    self:drawSectionTitle(getText("IGUI_DRewards_Containers"), self.containersList:getX(), self.containersList:getY() -
        FONT_MEDIUM - 8, self.containersList:getWidth())
    local selectedContainer = self:getSelectedContainer()
    local selectedText = selectedContainer and
        string.format("%s %d,%d,%d", getText("IGUI_DRewards_SelectedContainer"), selectedContainer.x or 0,
            selectedContainer.y or 0, selectedContainer.z or 0) or
        getText("IGUI_DRewards_NoContainerSelected")
    self:drawLabel(selectedText, self.assignCombo:getX(), self.assignCombo:getY() - FONT_SMALL - 4,
        self.assignCombo:getWidth())
    self:drawSectionTitle(getText("IGUI_DRewards_PresetEditor"), self.presetIdEntry:getX(), C.LAYOUT.TOP,
        self.width - self.presetIdEntry:getX() - C.LAYOUT.PAD)
    self:drawLabel(getText("IGUI_DRewards_PresetId"), self.presetIdEntry:getX(), self.presetIdEntry:getY() - FONT_SMALL -
        4, self.presetIdEntry:getWidth())
    self:drawLabel(getText("IGUI_DRewards_PresetName"), self.presetNameEntry:getX(),
        self.presetNameEntry:getY() - FONT_SMALL - 4, self.presetNameEntry:getWidth())
    self:drawLabel(getText("IGUI_DRewards_Rolls"), self.rollCountEntry:getX(), self.rollCountEntry:getY() - FONT_SMALL -
        4, self.rollCountEntry:getWidth())
    self:drawLabel(getText("IGUI_DRewards_Description"), self.descriptionEntry:getX(),
        self.descriptionEntry:getY() - FONT_SMALL - 4, self.descriptionEntry:getWidth())
    self:drawSectionTitle(getText("IGUI_DRewards_Rewards"), self.rewardsList:getX(),
        self.rewardsList:getY() - FONT_MEDIUM - 8, self.rewardsList:getWidth())
    self:drawSectionTitle(getText("IGUI_DRewards_RewardEditor"), self.rewardTypeCombo:getX(),
        self.rewardsList:getY() - FONT_MEDIUM - 8, self.width - self.rewardTypeCombo:getX() - C.LAYOUT.PAD)
    self:drawLabel(getText("IGUI_DRewards_RewardType"), self.rewardTypeCombo:getX(),
        self.rewardTypeCombo:getY() - FONT_SMALL - 4, self.rewardTypeCombo:getWidth())
    self:drawLabel(getText("IGUI_DRewards_RewardTitle"), self.rewardTitleEntry:getX(),
        self.rewardTitleEntry:getY() - FONT_SMALL - 4, self.rewardTitleEntry:getWidth())
    local targetLabel = getText("IGUI_DRewards_TargetItem")
    local rewardType = self:getRewardType()
    if rewardType == "xp" then
        targetLabel = getText("IGUI_DRewards_TargetPerk")
    elseif rewardType == "trait" then
        targetLabel = getText("IGUI_DRewards_TargetTrait")
    elseif rewardType == "custom" then
        targetLabel = getText("IGUI_DRewards_TargetHandler")
    end
    self:drawLabel(targetLabel, self.rewardTargetEntry:getX(), self.rewardTargetEntry:getY() - FONT_SMALL - 4,
        self.rewardTargetEntry:getWidth())
    self:drawLabel(rewardType == "xp" and getText("IGUI_DRewards_Amount") or getText("IGUI_DRewards_Count"),
        self.rewardCountEntry:getX(), self.rewardCountEntry:getY() - FONT_SMALL - 4, self.rewardCountEntry:getWidth())
    self:drawLabel(getText("IGUI_DRewards_Weight"), self.rewardWeightEntry:getX(),
        self.rewardWeightEntry:getY() - FONT_SMALL - 4, self.rewardWeightEntry:getWidth())
end

function AdminPanel:prerender()
    self:layoutChildren()
    ISCollapsableWindow.prerender(self)
    if not self.isCollapsed then
        self:drawLabels()
        self.rewardModeCombo:setVisible(self:getRewardType() == "trait")
    end
end

function AdminPanel:update()
    ISCollapsableWindow.update(self)
    if (self.statusTicks or 0) > 0 then
        self.statusTicks = self.statusTicks - 1
        if self.statusTicks <= 0 then
            self.statusMessage = ""
        end
    end
end

function AdminPanel:render()
    ISCollapsableWindow.render(self)
    if not self.statusMessage or self.statusMessage == "" then
        return
    end
    local T       = Theme.colors
    local color   = self.statusLevel == "error" and T.danger or
        (self.statusLevel == "warning" and T.warning or T.success)
    local footerY = self.height - C.LAYOUT.PAD - FONT_SMALL
    self:drawRect(C.LAYOUT.PAD - 2, footerY - 2, self.width - C.LAYOUT.PAD * 2 + 4, FONT_SMALL + 6, 0.0,
        T.background.r, T.background.g, T.background.b)
    self:drawText(trimToWidth(UIFont.Small, self.statusMessage or "", self.width - C.LAYOUT.PAD * 2), C.LAYOUT.PAD,
        footerY,
        color.r, color.g, color.b, 1, UIFont.Small)
end

function AdminPanel:close()
    self:setVisible(false)
    self:removeFromUIManager()
    AdminPanel.instance = nil
end

function AdminPanel.openPanel(playerObj)
    if AdminPanel.instance then
        AdminPanel.instance:bringToTop()
        Shared.ExecuteCommand("RequestSnapshot", {})
        return AdminPanel.instance
    end
    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()
    local width = math.min(C.SIZE.W, screenWidth - 40)
    local height = math.min(C.SIZE.H, screenHeight - 40)
    local panel = AdminPanel:new(math.max(20, (screenWidth - width) / 2), math.max(20, (screenHeight - height) / 2),
        width, height, playerObj)
    panel:initialise()
    panel:addToUIManager()
    AdminPanel.instance = panel
    Shared.ExecuteCommand("RequestSnapshot", {})
    return panel
end

local MenuDock = require("ElyonLib/UI/MenuDock/MenuDock")
MenuDock.registerButton({
    id = "dungeon_rewards",
    title = getText("IGUI_DRewards_AdminTitle"),
    icon = "media/ui/DungeonRewards/ui_icon_dungeon_rewards.png",
    minimumAccessLevel = "Admin",
    allowSinglePlayer = true,
    onClick = function(playerNum, entry)
        AdminPanel.openPanel(getSpecificPlayer(playerNum))
    end,
})

return AdminPanel

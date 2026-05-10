require("ISUI/ISCollapsableWindow")
require("ISUI/ISButton")

local DungeonRewards = require("DungeonRewards/Shared")
local ColorUtils = require("ElyonLib/ColorUtils/ColorUtils")
local ItemUtils = require("ElyonLib/ItemUtils/ItemUtils")
local TextUtils = require("ElyonLib/TextUtils/TextUtils")
local UIUtils = require("ElyonLib/UI/Utils/UIUtils")
local Theme = require("ElyonLib/UI/Theme/Theme")

local PlayerPanel = ISCollapsableWindow:derive("DungeonRewardsPlayerPanel")
PlayerPanel.instance = nil

local Shared = DungeonRewards.Shared
local copyColor = ColorUtils.copy
local trimToWidth = TextUtils.trimToWidth
local drawWrappedText = UIUtils.drawWrappedText

local FONT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)

local C = {
	SIZE = {
		W = 650,
		H = 500,
		MIN_W = 650,
		MIN_H = 500,
	},
	LAYOUT = {
		PAD = 15,
		GAP = 10,
		TOP = 35,
	},
	CTRL = {
		BUTTON_H = 25,
	},
	GRID = {
		CARD_MIN_W = 130,
		CARD_H = 150,
		PAD = 15,
		SCROLLBAR_W = 20,
	},
	ANIM = {
		NOTICE_TICKS = 300,
		SPIN_FRAMES = 20,
	},
	COLORS = Theme.standardColors(),
}

local function buttonStyle(button, primary)
	Theme.applyButtonStyle(button, primary and "primary" or nil)
end

local function addButton(panel, x, y, w, text, internal, primary)
	local button = ISButton:new(x, y, w, C.CTRL.BUTTON_H, text, panel, PlayerPanel.onClick)
	button.internal = internal
	button:initialise()
	button:instantiate()
	buttonStyle(button, primary)
	panel:addChild(button)
	return button
end

local function getRewardTexture(reward)
	if reward.type == "item" then
		return ItemUtils.getTexture(reward.item)
	end
	if reward.type == "trait" then
		return getTexture("media/ui/Traits/trait_" .. tostring(reward.trait or ""):lower() .. ".png")
	end
	return nil
end

function PlayerPanel:new(x, y, width, height, playerObj)
	local o = ISCollapsableWindow.new(self, x, y, width, height)
	setmetatable(o, self)
	self.__index = self
	o.playerObj = playerObj or getPlayer()
	o.payload = nil
	o.revealed = {}
	o.cardScroll = 0
	o.revealRunning = false
	o.revealIndex = 0
	o.revealFrame = 0
	o.spinPreview = {}
	o.gridRect = {
		x = C.LAYOUT.PAD,
		y = C.LAYOUT.TOP + C.CTRL.BUTTON_H + 92,
		w = width - C.LAYOUT.PAD * 2,
		h = height - 170,
	}
	o.scrollDragging = false
	o.statusMessage = getText("IGUI_DRewards_StatusWaiting")
	o.statusLevel = "info"
	o.statusTicks = C.ANIM.NOTICE_TICKS
	o.backgroundColor = Theme.copy(Theme.colors.background)
	o.borderColor = Theme.copy(Theme.colors.border)
	o.title = getText("IGUI_DRewards_Title")
	o.minimumWidth = C.SIZE.MIN_W
	o.minimumHeight = C.SIZE.MIN_H
	return o
end

function PlayerPanel:initialise()
	ISCollapsableWindow.initialise(self)
end

function PlayerPanel:createChildren()
	ISCollapsableWindow.createChildren(self)
	self:setResizable(true)
	self.revealBtn =
		addButton(self, C.LAYOUT.PAD, C.LAYOUT.TOP, 120, getText("IGUI_DRewards_RevealNext"), "REVEAL", true)
	self.claimBtn =
		addButton(self, C.LAYOUT.PAD + 130, C.LAYOUT.TOP, 120, getText("IGUI_DRewards_Claim"), "CLAIM", true)
	self.closeBtn = addButton(self, C.LAYOUT.PAD + 250, C.LAYOUT.TOP, 80, getText("IGUI_DRewards_Close"), "CLOSE")
end

function PlayerPanel:layoutChildren()
	if self.isCollapsed then
		return
	end
	self.revealBtn:setX(C.LAYOUT.PAD)
	self.revealBtn:setY(C.LAYOUT.TOP)
	self.revealBtn:setWidth(math.min(128, math.max(112, math.floor(self.width * 0.18))))
	self.claimBtn:setX(self.revealBtn:getRight() + C.LAYOUT.GAP)
	self.claimBtn:setY(C.LAYOUT.TOP)
	self.claimBtn:setWidth(112)
	self.closeBtn:setX(self.claimBtn:getRight() + C.LAYOUT.GAP)
	self.closeBtn:setY(C.LAYOUT.TOP)
	self.closeBtn:setWidth(82)
	local gridY = C.LAYOUT.TOP + C.CTRL.BUTTON_H + 88
	self.gridRect = {
		x = C.LAYOUT.PAD,
		y = gridY,
		w = math.max(100, self.width - C.LAYOUT.PAD * 2),
		h = math.max(90, self.height - gridY - C.LAYOUT.PAD - FONT_SMALL - 14),
	}
	self.cardScroll = math.max(0, math.min(self.cardScroll or 0, self:getMaxCardScroll()))
end

function PlayerPanel:setStatus(message, level)
	self.statusMessage = tostring(message or "")
	self.statusLevel = level or "info"
	self.statusTicks = self.statusMessage ~= "" and C.ANIM.NOTICE_TICKS or 0
end

function PlayerPanel:loadPayload(payload)
	self.payload = payload or {}
	self.revealed = {}
	self.cardScroll = 0
	self.revealRunning = false
	self.revealIndex = 0
	self.revealFrame = 0
	self.spinPreview = {}
	if self.payload.claimed then
		for i = 1, #(self.payload.rolledRewards or {}) do
			self.revealed[i] = true
		end
	end
	self:setStatus(self.payload.message or getText("IGUI_DRewards_StatusReady"), self.payload.level or "info")
end

function PlayerPanel:getGridMetrics()
	local rect = self.gridRect or { w = self.width - (C.LAYOUT.PAD * 2) }
	local contentW = math.max(80, rect.w - C.GRID.PAD * 2 - C.GRID.SCROLLBAR_W - C.LAYOUT.GAP)
	local columns = contentW >= 600 and 4 or 3
	columns = math.max(
		1,
		math.min(columns, math.max(1, math.floor((contentW + C.LAYOUT.GAP) / (C.GRID.CARD_MIN_W + C.LAYOUT.GAP))))
	)
	local cardW = math.floor((contentW - ((columns - 1) * C.LAYOUT.GAP)) / columns)
	return columns, cardW
end

function PlayerPanel:getCardAt(x, y)
	local rewards = self.payload and self.payload.rolledRewards or {}
	local columns, cardW = self:getGridMetrics()
	local rect = self.gridRect or { x = C.LAYOUT.PAD, y = C.LAYOUT.TOP + C.CTRL.BUTTON_H + 88 }
	local startX = rect.x + C.GRID.PAD
	local startY = rect.y + C.GRID.PAD - (self.cardScroll or 0)
	for i = 1, #rewards do
		local col = (i - 1) % columns
		local row = math.floor((i - 1) / columns)
		local cardX = startX + col * (cardW + C.LAYOUT.GAP)
		local cardY = startY + row * (C.GRID.CARD_H + C.LAYOUT.GAP)
		if x >= cardX and x <= cardX + cardW and y >= cardY and y <= cardY + C.GRID.CARD_H then
			return i
		end
	end
	return nil
end

function PlayerPanel:getMaxCardScroll()
	local rewards = self.payload and self.payload.rolledRewards or {}
	local columns = self:getGridMetrics()
	local rows = math.ceil(#rewards / columns)
	local gridH = rows * C.GRID.CARD_H + math.max(0, rows - 1) * C.LAYOUT.GAP + C.GRID.PAD * 2
	local rect = self.gridRect or {}
	local visibleH = rect.h or (self.height - (C.LAYOUT.TOP + C.CTRL.BUTTON_H + 88) - 42)
	return math.max(0, gridH - visibleH)
end

function PlayerPanel:onMouseWheel(del)
	local direction = del > 0 and 1 or -1
	self.cardScroll = math.max(0, math.min(self:getMaxCardScroll(), (self.cardScroll or 0) + direction * 48))
	return true
end

function PlayerPanel:getScrollTrackRect()
	local rect = self.gridRect
	if not rect then
		return nil
	end
	return {
		x = rect.x + rect.w - C.GRID.SCROLLBAR_W - 4,
		y = rect.y + 6,
		w = C.GRID.SCROLLBAR_W,
		h = math.max(1, rect.h - 12),
	}
end

function PlayerPanel:getScrollThumbRect()
	local track = self:getScrollTrackRect()
	if not track then
		return nil
	end
	local maxScroll = self:getMaxCardScroll()
	local thumbH = maxScroll > 0
			and math.max(34, math.floor((self.gridRect.h / (self.gridRect.h + maxScroll)) * track.h))
		or track.h
	local thumbY = maxScroll > 0 and (track.y + math.floor(((self.cardScroll or 0) / maxScroll) * (track.h - thumbH)))
		or track.y
	return {
		x = track.x,
		y = thumbY,
		w = track.w,
		h = thumbH,
	}
end

function PlayerPanel:setScrollFromMouse(y)
	local track = self:getScrollTrackRect()
	local thumb = self:getScrollThumbRect()
	local maxScroll = self:getMaxCardScroll()
	if not track or not thumb or maxScroll <= 0 then
		return
	end
	local usableH = math.max(1, track.h - thumb.h)
	local relative = math.max(0, math.min(usableH, y - track.y - thumb.h / 2))
	self.cardScroll = math.floor((relative / usableH) * maxScroll)
end

function PlayerPanel:scrollToCard(index)
	local rewards = self.payload and self.payload.rolledRewards or {}
	if not index or index < 1 or index > #rewards then
		return
	end
	local columns = self:getGridMetrics()
	local row = math.floor((index - 1) / columns)
	local cardTop = C.GRID.PAD + row * (C.GRID.CARD_H + C.LAYOUT.GAP)
	local visibleH = ((self.gridRect and self.gridRect.h) or (self.height - (C.LAYOUT.TOP + C.CTRL.BUTTON_H + 88) - 42))
		- C.GRID.PAD
	if cardTop < (self.cardScroll or 0) then
		self.cardScroll = cardTop
	elseif cardTop + C.GRID.CARD_H > (self.cardScroll or 0) + visibleH then
		self.cardScroll = math.min(self:getMaxCardScroll(), cardTop + C.GRID.CARD_H - visibleH)
	end
end

function PlayerPanel:startReveal()
	local rewards = self.payload and self.payload.rolledRewards or {}
	if #rewards == 0 or self.payload.claimed or self:allRevealed() then
		return
	end
	self.revealRunning = true
	self.revealIndex = 1
	self.revealFrame = 0
	self:setStatus(getText("IGUI_DRewards_StatusRevealing"), "info")
	getSoundManager():playUISound("UIToggleComboBox")
end

function PlayerPanel:allRevealed()
	local rewards = self.payload and self.payload.rolledRewards or {}
	if #rewards == 0 then
		return false
	end
	for i = 1, #rewards do
		if not self.revealed[i] then
			return false
		end
	end
	return true
end

function PlayerPanel:onMouseDown(x, y)
	if self:getMaxCardScroll() <= 0 then
		return ISCollapsableWindow.onMouseDown(self, x, y)
	end
	local thumb = self:getScrollThumbRect()
	local track = self:getScrollTrackRect()
	if thumb and x >= thumb.x and x <= thumb.x + thumb.w and y >= thumb.y and y <= thumb.y + thumb.h then
		self.scrollDragging = true
		return true
	end
	if track and x >= track.x and x <= track.x + track.w and y >= track.y and y <= track.y + track.h then
		self:setScrollFromMouse(y)
		self.scrollDragging = true
		return true
	end
	return ISCollapsableWindow.onMouseDown(self, x, y)
end

function PlayerPanel:onMouseMove(dx, dy)
	if self.scrollDragging then
		self:setScrollFromMouse(self:getMouseY())
		return true
	end
	if ISCollapsableWindow.onMouseMove then
		return ISCollapsableWindow.onMouseMove(self, dx, dy)
	end
	return false
end

function PlayerPanel:onMouseMoveOutside(dx, dy)
	if self.scrollDragging then
		self:setScrollFromMouse(self:getMouseY())
		return true
	end
	if ISCollapsableWindow.onMouseMoveOutside then
		return ISCollapsableWindow.onMouseMoveOutside(self, dx, dy)
	end
	return false
end

function PlayerPanel:onMouseUp(x, y)
	self.scrollDragging = false
	if ISCollapsableWindow.onMouseUp then
		return ISCollapsableWindow.onMouseUp(self, x, y)
	end
	return false
end

function PlayerPanel:onMouseUpOutside(x, y)
	self.scrollDragging = false
	if ISCollapsableWindow.onMouseUpOutside then
		return ISCollapsableWindow.onMouseUpOutside(self, x, y)
	end
	return false
end

function PlayerPanel:onClick(button)
	if button.internal == "REVEAL" then
		self:startReveal()
	elseif button.internal == "CLAIM" then
		if self.payload and self.payload.container and self:allRevealed() and not self.payload.claimed then
			self:setStatus(getText("IGUI_DRewards_StatusClaiming"), "info")
			Shared.ExecuteCommand("ClaimContainerRewards", { containerKey = self.payload.container.key })
		end
	elseif button.internal == "CLOSE" then
		self:close()
	end
end

function PlayerPanel:update()
	ISCollapsableWindow.update(self)
	if (self.statusTicks or 0) > 0 then
		self.statusTicks = self.statusTicks - 1
		if self.statusTicks <= 0 then
			self.statusMessage = ""
		end
	end
	local rewards = self.payload and self.payload.rolledRewards or {}
	if self.revealRunning then
		self:scrollToCard(self.revealIndex)
		self.revealFrame = (self.revealFrame or 0) + 1
		if #rewards > 0 then
			local previewIndex = 1 + ((self.revealFrame * 3 + self.revealIndex) % #rewards)
			self.spinPreview[self.revealIndex] = rewards[previewIndex]
		end
		if self.revealFrame >= C.ANIM.SPIN_FRAMES then
			self.revealed[self.revealIndex] = true
			self.spinPreview[self.revealIndex] = nil
			getSoundManager():playUISound("UISelectListItem")
			self.revealIndex = self.revealIndex + 1
			self.revealFrame = 0
			if self.revealIndex > #rewards then
				self.revealRunning = false
				self:setStatus(getText("IGUI_DRewards_StatusRevealed"), "info")
			end
		end
	end
	if self.claimBtn then
		self.claimBtn:setEnable(self.payload and not self.payload.claimed and self:allRevealed())
	end
	if self.revealBtn then
		self.revealBtn:setEnable(
			self.payload and not self.payload.claimed and not self.revealRunning and not self:allRevealed()
		)
	end
end

function PlayerPanel:drawCard(x, y, w, reward, index)
	local T = Theme.colors
	local revealed = self.revealed[index] == true
	local spinning = self.revealRunning and self.revealIndex == index
	local visibleReward = (spinning and self.spinPreview[index]) or reward
	local mouseOver = self:getMouseX() >= x
		and self:getMouseX() <= x + w
		and self:getMouseY() >= y
		and self:getMouseY() <= y + C.GRID.CARD_H
	local bg = mouseOver and C.COLORS.CARD_HOVER or C.COLORS.CARD
	self:drawRect(x + 2, y + 3, w, C.GRID.CARD_H, T.shadow.a, T.shadow.r, T.shadow.g, T.shadow.b)
	self:drawRect(x, y, w, C.GRID.CARD_H, bg.a, bg.r, bg.g, bg.b)
	self:drawRectBorder(x, y, w, C.GRID.CARD_H, T.border.a, T.border.r, T.border.g, T.border.b)

	if not revealed and not spinning then
		self:drawTextCentre(
			"?",
			x + w / 2,
			y + 34,
			C.COLORS.GOLD.r,
			C.COLORS.GOLD.g,
			C.COLORS.GOLD.b,
			1,
			UIFont.Massive
		)
		self:drawTextCentre(
			getText("IGUI_DRewards_Hidden"),
			x + w / 2,
			y + 104,
			C.COLORS.MUTED.r,
			C.COLORS.MUTED.g,
			C.COLORS.MUTED.b,
			1,
			UIFont.Small
		)
		return
	end

	local texture = getRewardTexture(visibleReward)
	if texture then
		self:drawTextureScaled(texture, x + (w / 2) - 20, y + 24, 40, 40, 1, 1, 1, 1)
	else
		local label = visibleReward.type == "xp" and "XP" or (visibleReward.type == "trait" and "TR" or "FX")
		self:drawTextCentre(
			label,
			x + w / 2,
			y + 34,
			C.COLORS.GOLD.r,
			C.COLORS.GOLD.g,
			C.COLORS.GOLD.b,
			1,
			UIFont.Medium
		)
	end
	self:drawTextCentre(
		trimToWidth(UIFont.Small, visibleReward.title or Shared.GetRewardSummary(visibleReward), w - 14),
		x + w / 2,
		y + 78,
		C.COLORS.TEXT.r,
		C.COLORS.TEXT.g,
		C.COLORS.TEXT.b,
		1,
		UIFont.Small
	)
	drawWrappedText(
		self,
		spinning and "..." or Shared.GetRewardSummary(visibleReward),
		x + 8,
		y + 100,
		w - 16,
		C.COLORS.MUTED,
		UIFont.Small,
		2
	)
end

function PlayerPanel:drawScrollBar(rect)
	local T = Theme.colors
	local track = self:getScrollTrackRect()
	local thumb = self:getScrollThumbRect()
	if not track then
		return
	end

	self:drawRect(
		track.x,
		track.y,
		track.w,
		track.h,
		T.scrollTrack.a,
		T.scrollTrack.r,
		T.scrollTrack.g,
		T.scrollTrack.b
	)
	self:drawRectBorder(track.x, track.y, track.w, track.h, 0.85, T.border.r, T.border.g, T.border.b)
	if thumb then
		local active = self:getMaxCardScroll() > 0
		local alpha = active and 0.95 or 0.38
		self:drawRect(thumb.x + 3, thumb.y + 3, thumb.w - 6, thumb.h - 6, alpha, T.border.r, T.border.g, T.border.b)
		self:drawRectBorder(thumb.x + 3, thumb.y + 3, thumb.w - 6, thumb.h - 6, alpha, T.gold.r, T.gold.g, T.gold.b)
	end
end

function PlayerPanel:prerender()
	self:layoutChildren()
	ISCollapsableWindow.prerender(self)
	if self.isCollapsed then
		return
	end

	local payload = self.payload or {}
	local preset = payload.preset or {}
	local y = C.LAYOUT.TOP + C.CTRL.BUTTON_H + 12
	self:drawRect(
		C.LAYOUT.PAD,
		y - 5,
		self.width - C.LAYOUT.PAD * 2,
		60,
		0.45,
		C.COLORS.PANEL.r,
		C.COLORS.PANEL.g,
		C.COLORS.PANEL.b
	)
	self:drawText(
		trimToWidth(UIFont.Medium, preset.name or getText("IGUI_DRewards_Title"), self.width - C.LAYOUT.PAD * 2),
		C.LAYOUT.PAD + 8,
		y,
		C.COLORS.TEXT.r,
		C.COLORS.TEXT.g,
		C.COLORS.TEXT.b,
		1,
		UIFont.Medium
	)
	y = y + FONT_MEDIUM + 4
	self:drawText(
		trimToWidth(UIFont.Small, preset.description or "", self.width - C.LAYOUT.PAD * 2 - 16),
		C.LAYOUT.PAD + 8,
		y,
		C.COLORS.MUTED.r,
		C.COLORS.MUTED.g,
		C.COLORS.MUTED.b,
		1,
		UIFont.Small
	)

	local rewards = payload.rolledRewards or {}
	local columns, cardW = self:getGridMetrics()
	local rect = self.gridRect
		or {
			x = C.LAYOUT.PAD,
			y = C.LAYOUT.TOP + C.CTRL.BUTTON_H + 88,
			w = self.width - C.LAYOUT.PAD * 2,
			h = self.height - C.LAYOUT.TOP - C.CTRL.BUTTON_H - 130,
		}
	self:drawRect(rect.x, rect.y, rect.w, rect.h, 0.28, C.COLORS.PANEL.r, C.COLORS.PANEL.g, C.COLORS.PANEL.b)
	self:drawRectBorder(rect.x, rect.y, rect.w, rect.h, 0.65, C.COLORS.BORDER.r, C.COLORS.BORDER.g, C.COLORS.BORDER.b)
	local startX = rect.x + C.GRID.PAD
	local startY = rect.y + C.GRID.PAD - (self.cardScroll or 0)
	self:setStencilRect(rect.x, rect.y, rect.w, rect.h)
	for i = 1, #rewards do
		local col = (i - 1) % columns
		local row = math.floor((i - 1) / columns)
		local cardY = startY + row * (C.GRID.CARD_H + C.LAYOUT.GAP)
		if cardY + C.GRID.CARD_H >= rect.y and cardY <= rect.y + rect.h then
			self:drawCard(startX + col * (cardW + C.LAYOUT.GAP), cardY, cardW, rewards[i], i)
		end
	end
	self:drawScrollBar(rect)
	self:clearStencilRect()
end

function PlayerPanel:render()
	ISCollapsableWindow.render(self)
	if not self.statusMessage or self.statusMessage == "" then
		return
	end
	local T = Theme.colors
	local color = T.textMuted
	if self.statusLevel == "error" then
		color = T.danger
	elseif self.statusLevel == "warning" then
		color = T.warning
	elseif self.statusLevel == "info" then
		color = T.success
	end
	local footerY = self.height - C.LAYOUT.PAD - FONT_SMALL - 4
	self:drawRect(
		C.LAYOUT.PAD - 2,
		footerY - 2,
		self.width - C.LAYOUT.PAD * 2 + 4,
		FONT_SMALL + 6,
		0.0,
		T.background.r,
		T.background.g,
		T.background.b
	)
	self:drawText(
		trimToWidth(UIFont.Small, self.statusMessage or "", self.width - C.LAYOUT.PAD * 2),
		C.LAYOUT.PAD,
		footerY,
		color.r,
		color.g,
		color.b,
		1,
		UIFont.Small
	)
end

function PlayerPanel:close()
	self:setVisible(false)
	self:removeFromUIManager()
	PlayerPanel.instance = nil
end

function PlayerPanel.openPanel(playerObj, containerKey)
	if PlayerPanel.instance then
		PlayerPanel.instance:bringToTop()
		Shared.ExecuteCommand("RequestContainerRoll", { containerKey = containerKey })
		return PlayerPanel.instance
	end

	local screenWidth = getCore():getScreenWidth()
	local screenHeight = getCore():getScreenHeight()
	local width = math.min(C.SIZE.W, screenWidth - 40)
	local height = math.min(C.SIZE.H, screenHeight - 40)
	local panel = PlayerPanel:new(
		math.max(20, (screenWidth - width) / 2),
		math.max(20, (screenHeight - height) / 2),
		width,
		height,
		playerObj
	)
	panel:initialise()
	panel:addToUIManager()
	PlayerPanel.instance = panel
	Shared.ExecuteCommand("RequestContainerRoll", { containerKey = containerKey })
	return panel
end

return PlayerPanel

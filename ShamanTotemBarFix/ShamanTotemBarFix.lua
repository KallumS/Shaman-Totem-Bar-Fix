-- Shaman Totem Bar Fix
-- A stand-alone copy of the Shaman multi-cast totem bar (Call of the Elements /
-- Ancestors / Spirits) that keeps working while Blizzard's GamePad UI is on.
--
-- It does not touch Blizzard's MultiCastActionBarFrame. It builds its own
-- secure buttons on the same server-side multi-cast action slots, so totems
-- chosen here are exactly what the Call spells drop, whichever UI you use.

local ADDON_NAME = ...
local PREFIX = "|cff0070ddShaman Totem Bar Fix|r: "

---------------------------------------------------------------------------
-- Constants (mirrors Blizzard_ActionBar/Shared/MultiCastActionBarFrame.lua)
---------------------------------------------------------------------------
local FIRE  = FIRE_TOTEM_SLOT  or 1
local EARTH = EARTH_TOTEM_SLOT or 2
local WATER = WATER_TOTEM_SLOT or 3
local AIR   = AIR_TOTEM_SLOT   or 4

local SLOT_ORDER     = SHAMAN_TOTEM_PRIORITIES or { EARTH, FIRE, WATER, AIR }
local NUM_PAGES      = 3
local SLOTS_PER_PAGE = 4
local SUMMON_SPELLS  = TOTEM_MULTI_CAST_SUMMON_SPELLS or { 66842, 66843, 66844 }
local RECALL_SPELL   = (TOTEM_MULTI_CAST_RECALL_SPELLS and TOTEM_MULTI_CAST_RECALL_SPELLS[1]) or 36936

local SLOT_NAMES = { [FIRE] = "Fire", [EARTH] = "Earth", [WATER] = "Water", [AIR] = "Air" }

local TEX         = "Interface\\Buttons\\UI-TotemBar"
local BUTTON_SIZE = 30
local GAP         = 8
local EDGE        = 3
local ARROW_W, ARROW_H = 28, 18
local FLY_BUTTON  = 24
local FLY_FIRST   = 4
local FLY_SPACING = 2

local function tc(l, r, t, b) return { l / 128, r / 128, t / 256, b / 256 } end

local EMPTY_TC = {
	[EARTH] = tc(66, 96, 3, 33),   [FIRE] = tc(67, 97, 100, 130),
	[WATER] = tc(39, 69, 209, 239), [AIR] = tc(66, 96, 36, 66),
}
local OVERLAY_TC = {
	[EARTH] = tc(1, 35, 172, 206),  [FIRE] = tc(36, 70, 172, 206),
	[WATER] = tc(1, 35, 207, 240),  [AIR] = tc(36, 70, 137, 171),
}
local ARROW_UP_TC = {
	summon  = tc(99, 127, 84, 102),
	[EARTH] = tc(99, 127, 160, 178), [FIRE] = tc(99, 127, 122, 140),
	[WATER] = tc(99, 127, 199, 217), [AIR] = tc(99, 127, 237, 255),
}
local ARROW_DOWN_TC = {
	summon  = tc(99, 127, 65, 83),
	[EARTH] = tc(99, 127, 141, 159), [FIRE] = tc(99, 127, 103, 121),
	[WATER] = tc(99, 127, 180, 198), [AIR] = tc(99, 127, 218, 236),
}
local FLY_TOP_TC = {
	summon  = tc(33, 65, 1, 23),
	[EARTH] = tc(0, 32, 46, 68),  [FIRE] = tc(33, 65, 46, 68),
	[WATER] = tc(0, 32, 1, 23),   [AIR] = tc(0, 32, 91, 113),
}
local FLY_MID_TC = {
	summon  = tc(33, 65, 23, 43),
	[EARTH] = tc(0, 32, 68, 88),  [FIRE] = tc(33, 65, 68, 88),
	[WATER] = tc(0, 32, 23, 43),  [AIR] = tc(0, 32, 113, 133),
}
local ARROW_HIGHLIGHT_TC = { 0.5625, 0.71875, 0.34375, 0.3828125 }
local CLOSE_HIGHLIGHT_TC = { 0.5625, 0.71875, 0.26953125, 0.30859375 }

local DEFAULTS = {
	page   = 1,
	mode   = "auto",   -- auto: only while GamePad UI is on | always | hidden
	scale  = 1,
	locked = true,
	point  = nil,
}

local db
local pendingUpdate = false

---------------------------------------------------------------------------
-- API helpers (guarded so a renamed API degrades instead of erroring)
---------------------------------------------------------------------------
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end

local function IsKnown(spellID)
	if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
		local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
		return C_SpellBook.IsSpellInSpellBook(spellID, bank, false) and true or false
	end
	if IsPlayerSpell then return IsPlayerSpell(spellID) end
	return IsSpellKnown and IsSpellKnown(spellID) or false
end

local function SpellTexture(spellID)
	if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spellID) end
	return GetSpellTexture and GetSpellTexture(spellID)
end

local function SpellName(spellID)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
	return GetSpellInfo and (GetSpellInfo(spellID))
end

local function ActionTexture(action)
	if C_ActionBar and C_ActionBar.GetActionTexture then return C_ActionBar.GetActionTexture(action) end
	return GetActionTexture and GetActionTexture(action)
end

local function TotemSpells(slot)
	if not GetMultiCastTotemSpells then return {} end
	return { GetMultiCastTotemSpells(slot) }
end

-- Same maths Blizzard uses: button id (pageOffset + slot) shifted onto the
-- multi-cast action bar page (SecureActionButtonMixin:CalculateAction).
local function ActionID(page, slot)
	local barIndex = C_ActionBar and C_ActionBar.GetMultiCastBarIndex and C_ActionBar.GetMultiCastBarIndex()
	if not barIndex or barIndex < 1 then barIndex = 12 end
	return (page - 1) * SLOTS_PER_PAGE + slot + (barIndex - 1) * (NUM_ACTIONBAR_BUTTONS or 12)
end

local function IsGamepadUI()
	if C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle
		and Enum and Enum.InputDeviceInterfaceType then
		return C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad
	end
	-- Fallback: show whenever Blizzard's own bar is not visible.
	return not (MultiCastActionBarFrame and MultiCastActionBarFrame:IsVisible())
end

local function SetCooldown(cooldown, info)
	-- pcall: cooldown values may be restricted ("secret") in combat on newer clients.
	local ok = pcall(function()
		if info and info.isEnabled and info.duration and info.duration > 0 then
			cooldown:SetCooldown(info.startTime, info.duration, info.modRate)
		else
			cooldown:Clear()
		end
	end)
	if not ok then pcall(cooldown.Clear, cooldown) end
end

local function SetTex(texture, coords)
	texture:SetTexture(TEX)
	texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
end

local function ShowSpellTooltip(owner, spellID)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if spellID and spellID > 0 then
		GameTooltip:SetSpellByID(spellID)
	else
		GameTooltip:SetText(MULTI_CAST_TOOLTIP_NO_TOTEM or "No Totem", 1, 1, 1)
	end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local bar        -- outer holder: shown/hidden by our own logic
local inner      -- hidden automatically in vehicles / override bars
local mover
local summonButton, recallButton, pageArrow
local slotButtons = {}   -- [slot] = button
local flyout
local flyButtons = {}

local UpdateAll, UpdateVisuals, ToggleFlyout, HideFlyout

local function NewSecureButton(name, parent, size)
	local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	b:SetSize(size, size)
	b:SetAttribute("useOnKeyDown", false)
	b:RegisterForClicks("AnyUp")

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)

	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hl:SetBlendMode("ADD")
	hl:SetAllPoints()

	local pushed = b:CreateTexture(nil, "OVERLAY")
	pushed:SetColorTexture(0, 0, 0, 0.35)
	pushed:SetAllPoints()
	b:SetPushedTexture(pushed)
	return b
end

local function NewArrow(parent, key, onClick)
	local a = CreateFrame("Button", nil, parent)
	a:SetSize(ARROW_W, ARROW_H)
	a:SetPoint("BOTTOM", parent, "TOP", 0, 0)
	a:SetNormalTexture(TEX)
	a.tex = a:GetNormalTexture()
	a.key = key
	a.tex:SetTexCoord(unpack(ARROW_UP_TC[key]))
	local hl = a:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture(TEX)
	hl:SetBlendMode("ADD")
	hl:SetSize(20, 11)
	hl:SetPoint("CENTER")
	hl:SetTexCoord(unpack(ARROW_HIGHLIGHT_TC))
	a:SetScript("OnClick", onClick)
	return a
end

local function SpellButtonOnEnter(self) ShowSpellTooltip(self, self.spellID) end
local function HideTooltip() GameTooltip:Hide() end

local function SlotOnEnter(self)
	local action = ActionID(db.page, self.slot)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if ActionTexture(action) then
		GameTooltip:SetAction(action)
	else
		GameTooltip:SetText(MULTI_CAST_TOOLTIP_NO_TOTEM or "No Totem", 1, 1, 1)
	end
	GameTooltip:AddLine((SLOT_NAMES[self.slot] or "") .. " totem - right-click or use the arrow to change", 0.6, 0.8, 1, true)
	GameTooltip:Show()
end

local function CreateFlyout()
	flyout = CreateFrame("Frame", "ShamanTotemBarFixFlyout", inner)
	flyout:SetSize(32, 30)
	flyout:SetFrameStrata("DIALOG")
	flyout:EnableMouse(true)
	flyout:Hide()

	flyout.top = flyout:CreateTexture(nil, "BACKGROUND")
	flyout.top:SetSize(32, 20)
	flyout.top:SetPoint("TOP", 0, -10)
	flyout.top:SetTexture(TEX)
	flyout.middle = flyout:CreateTexture(nil, "BACKGROUND")
	flyout.middle:SetSize(32, 20)
	flyout.middle:SetPoint("TOP", flyout.top, "BOTTOM")
	flyout.middle:SetPoint("BOTTOM")
	flyout.middle:SetTexture(TEX)

	local close = CreateFrame("Button", nil, flyout)
	close:SetSize(ARROW_W, ARROW_H)
	close:SetPoint("TOP")
	close:SetNormalTexture(TEX)
	local chl = close:CreateTexture(nil, "HIGHLIGHT")
	chl:SetTexture(TEX)
	chl:SetBlendMode("ADD")
	chl:SetSize(20, 11)
	chl:SetPoint("CENTER")
	chl:SetTexCoord(unpack(CLOSE_HIGHLIGHT_TC))
	close:SetScript("OnClick", function() HideFlyout() end)
	flyout.close = close
end

local function GetFlyButton(i)
	local b = flyButtons[i]
	if b then return b end
	b = NewSecureButton("ShamanTotemBarFixFlyoutButton" .. i, flyout, FLY_BUTTON)
	if i == 1 then
		b:SetPoint("BOTTOM", flyout, "BOTTOM", 0, FLY_FIRST)
	else
		b:SetPoint("BOTTOM", flyButtons[i - 1], "TOP", 0, FLY_SPACING)
	end
	b:SetScript("OnEnter", SpellButtonOnEnter)
	b:SetScript("OnLeave", HideTooltip)
	-- Runs after the secure handler (which does SetMultiCastSpell for "multispell").
	b:SetScript("PostClick", function(self)
		if flyout.mode == "page" and self.page then
			db.page = self.page
		end
		HideFlyout()
		UpdateAll()
	end)
	flyButtons[i] = b
	return b
end

HideFlyout = function()
	if flyout and flyout:IsShown() and not InCombatLockdown() then
		flyout:Hide()
	end
	flyout.mode, flyout.owner = nil, nil
end

-- entries: list of { spellID = n, icon = tex, tc = coords|nil, page = n|nil }
local function OpenFlyout(mode, owner, key, entries, action)
	for i, e in ipairs(entries) do
		local b = GetFlyButton(i)
		b.spellID = e.spellID
		b.page = e.page
		b.icon:SetTexture(e.icon)
		if e.tc then
			b.icon:SetTexCoord(e.tc[1], e.tc[2], e.tc[3], e.tc[4])
		else
			b.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
		end
		if mode == "slot" then
			b:SetAttribute("type", "multispell")
			b:SetAttribute("action", action)
			b:SetAttribute("spell", e.spellID)
		else
			b:SetAttribute("type", nil)
			b:SetAttribute("action", nil)
			b:SetAttribute("spell", nil)
		end
		b:Show()
	end
	for i = #entries + 1, #flyButtons do flyButtons[i]:Hide() end

	local height = FLY_FIRST + #entries * FLY_BUTTON + (#entries - 1) * FLY_SPACING + 2 + ARROW_H
	flyout:SetHeight(height)
	flyout.top:SetTexCoord(unpack(FLY_TOP_TC[key]))
	flyout.middle:SetTexCoord(unpack(FLY_MID_TC[key]))
	flyout.close:GetNormalTexture():SetTexCoord(unpack(ARROW_DOWN_TC[key]))
	flyout:ClearAllPoints()
	flyout:SetPoint("BOTTOM", owner, "TOP", 0, 0)
	flyout.mode, flyout.owner = mode, owner
	flyout:Show()
end

ToggleFlyout = function(mode, owner)
	if InCombatLockdown() then
		Print("Totems can't be changed in combat.")
		return
	end
	if flyout:IsShown() and flyout.owner == owner then
		HideFlyout()
		return
	end

	local entries = {}
	if mode == "page" then
		for page, spellID in ipairs(SUMMON_SPELLS) do
			if IsKnown(spellID) then
				entries[#entries + 1] = { spellID = spellID, icon = SpellTexture(spellID), page = page }
			end
		end
		if #entries == 0 then return end
		OpenFlyout("page", owner, "summon", entries)
	else
		local slot = owner.slot
		-- First entry clears the slot, exactly like Blizzard's flyout.
		entries[1] = { spellID = 0, icon = TEX, tc = EMPTY_TC[slot] }
		for _, spellID in ipairs(TotemSpells(slot)) do
			entries[#entries + 1] = { spellID = spellID, icon = SpellTexture(spellID) }
		end
		OpenFlyout("slot", owner, slot, entries, ActionID(db.page, slot))
	end
end

local function CreateSlotButton(slot)
	local b = NewSecureButton("ShamanTotemBarFixSlot" .. SLOT_NAMES[slot], inner, BUTTON_SIZE)
	b.slot = slot
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetAttribute("type1", "action")   -- left-click casts the totem in this slot

	b.background = b:CreateTexture(nil, "BACKGROUND")
	b.background:SetAllPoints()
	SetTex(b.background, EMPTY_TC[slot])

	b.overlay = b:CreateTexture(nil, "OVERLAY", nil, 1)
	b.overlay:SetSize(34, 34)
	b.overlay:SetPoint("CENTER")
	SetTex(b.overlay, OVERLAY_TC[slot])

	b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints()

	b:SetScript("OnEnter", SlotOnEnter)
	b:SetScript("OnLeave", HideTooltip)
	b:SetScript("PostClick", function(self, button)
		if button == "RightButton" then ToggleFlyout("slot", self) end
	end)

	b.arrow = NewArrow(b, slot, function() ToggleFlyout("slot", b) end)
	slotButtons[slot] = b
end

local function SavePosition()
	local point, _, relPoint, x, y = bar:GetPoint(1)
	db.point = { point, relPoint, x, y }
end

local function ApplyPosition()
	bar:ClearAllPoints()
	local p = db.point
	if p then
		bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 260)
	end
	bar:SetScale(db.scale or 1)
end

local function CreateFrames()
	bar = CreateFrame("Frame", "ShamanTotemBarFixFrame", UIParent)
	bar:SetSize(230, BUTTON_SIZE + EDGE * 2)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	bar:SetFrameStrata("MEDIUM")
	bar:Hide()

	inner = CreateFrame("Frame", "ShamanTotemBarFixInner", bar, "SecureHandlerStateTemplate")
	inner:SetAllPoints()
	RegisterStateDriver(inner, "visibility", "[vehicleui][overridebar] hide; show")

	summonButton = NewSecureButton("ShamanTotemBarFixCallButton", inner, BUTTON_SIZE)
	summonButton.cooldown = CreateFrame("Cooldown", nil, summonButton, "CooldownFrameTemplate")
	summonButton.cooldown:SetAllPoints()
	summonButton:SetScript("OnEnter", SpellButtonOnEnter)
	summonButton:SetScript("OnLeave", HideTooltip)
	summonButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	summonButton:SetAttribute("type1", "spell")   -- left-click casts the Call spell
	summonButton:SetScript("PostClick", function(self, button)
		if button == "RightButton" then ToggleFlyout("page", self) end
	end)
	pageArrow = NewArrow(summonButton, "summon", function() ToggleFlyout("page", summonButton) end)

	for _, slot in ipairs(SLOT_ORDER) do CreateSlotButton(slot) end

	recallButton = NewSecureButton("ShamanTotemBarFixRecallButton", inner, BUTTON_SIZE)
	recallButton:SetAttribute("type", "spell")
	recallButton:SetAttribute("spell", RECALL_SPELL)
	recallButton.spellID = RECALL_SPELL
	recallButton.cooldown = CreateFrame("Cooldown", nil, recallButton, "CooldownFrameTemplate")
	recallButton.cooldown:SetAllPoints()
	recallButton:SetScript("OnEnter", SpellButtonOnEnter)
	recallButton:SetScript("OnLeave", HideTooltip)

	CreateFlyout()

	-- Drag handle, only shown while unlocked.
	mover = CreateFrame("Frame", nil, bar)
	mover:SetPoint("TOPLEFT", -2, ARROW_H + 2)
	mover:SetPoint("BOTTOMRIGHT", 2, -2)
	mover:SetFrameStrata("HIGH")
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	local bg = mover:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0.6, 0.1, 0.45)
	local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	label:SetText("Totem bar - drag to move, /stbf lock when done")
	mover:SetScript("OnDragStart", function() if not InCombatLockdown() then bar:StartMoving() end end)
	mover:SetScript("OnDragStop", function() bar:StopMovingOrSizing(); SavePosition() end)
	mover:Hide()
end

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------
UpdateVisuals = function()
	if not bar then return end
	local summonSpell = SUMMON_SPELLS[db.page]
	summonButton.spellID = summonSpell
	summonButton.icon:SetTexture(SpellTexture(summonSpell))
	recallButton.icon:SetTexture(SpellTexture(RECALL_SPELL))

	for slot, b in pairs(slotButtons) do
		local tex = ActionTexture(ActionID(db.page, slot))
		if tex then
			b.icon:SetTexture(tex)
			b.icon:Show()
		else
			b.icon:Hide()
		end
	end
	if GameTooltip:IsShown() then
		local owner = GameTooltip:GetOwner()
		if owner and owner:GetScript("OnEnter") and owner:IsMouseOver() and owner:GetParent() == inner then
			owner:GetScript("OnEnter")(owner)
		end
	end
end

local function UpdateCooldowns()
	if not bar or not bar:IsShown() then return end
	for slot, b in pairs(slotButtons) do
		if b:IsShown() and C_ActionBar and C_ActionBar.GetActionCooldown then
			SetCooldown(b.cooldown, C_ActionBar.GetActionCooldown(ActionID(db.page, slot)))
		end
	end
	if C_Spell and C_Spell.GetSpellCooldown then
		if summonButton.spellID then
			SetCooldown(summonButton.cooldown, C_Spell.GetSpellCooldown(summonButton.spellID))
		end
		SetCooldown(recallButton.cooldown, C_Spell.GetSpellCooldown(RECALL_SPELL))
	end
end

local function ShouldShow(numSlots)
	if numSlots == 0 then return false end
	if db.mode == "always" then return true end
	if db.mode == "hidden" then return false end
	return IsGamepadUI()
end

-- Layout and secure attributes: only allowed out of combat.
UpdateAll = function()
	if not bar then return end
	if InCombatLockdown() then
		pendingUpdate = true
		UpdateVisuals()
		return
	end
	pendingUpdate = false

	if db.page < 1 or db.page > NUM_PAGES then db.page = 1 end
	-- Fall back to the first known Call spell if the saved one is unknown.
	if not IsKnown(SUMMON_SPELLS[db.page] or 0) then
		for page, spellID in ipairs(SUMMON_SPELLS) do
			if IsKnown(spellID) then db.page = page break end
		end
	end

	local x = EDGE
	local summonSpell = SUMMON_SPELLS[db.page]
	if summonSpell and IsKnown(summonSpell) then
		summonButton:SetAttribute("spell1", summonSpell)
		summonButton:ClearAllPoints()
		summonButton:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", x, EDGE)
		summonButton:Show()
		x = x + BUTTON_SIZE + EDGE
	else
		summonButton:Hide()
	end

	local numSlots, lastSlot = 0, nil
	for _, slot in ipairs(SLOT_ORDER) do
		local b = slotButtons[slot]
		if #TotemSpells(slot) > 0 then
			numSlots = numSlots + 1
			b:SetAttribute("action", ActionID(db.page, slot))
			b:ClearAllPoints()
			b:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", x, EDGE)
			b:Show()
			x = x + BUTTON_SIZE + GAP
			lastSlot = b
		else
			b:Hide()
		end
	end

	if lastSlot and IsKnown(RECALL_SPELL) then
		recallButton:ClearAllPoints()
		recallButton:SetPoint("LEFT", lastSlot, "RIGHT", GAP, 0)
		recallButton:Show()
		x = x + BUTTON_SIZE + GAP
	else
		recallButton:Hide()
	end

	bar:SetWidth(math.max(x, BUTTON_SIZE + EDGE * 2))
	HideFlyout()
	bar:SetShown(ShouldShow(numSlots))
	mover:SetShown(not db.locked)
	UpdateVisuals()
	UpdateCooldowns()
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Help()
	Print("commands (/stbf or /totembar):")
	Print("  auto - show only while the GamePad UI is on (default)")
	Print("  show - always show   |   hide - never show")
	Print("  unlock / lock - move the bar   |   reset - default position and scale")
	Print("  scale <0.5-2> - resize the bar")
	Print("  set <1-3> - pick Elements / Ancestors / Spirits   |   next - cycle them")
	Print("  debug - print the totem action slots")
end

local function Slash(msg)
	local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
	if cmd == "show" or cmd == "always" then
		db.mode = "always"; Print("bar always shown.")
	elseif cmd == "hide" then
		db.mode = "hidden"; Print("bar hidden. /stbf auto or /stbf show to bring it back.")
	elseif cmd == "auto" then
		db.mode = "auto"; Print("bar shown only while the GamePad UI is on.")
	elseif cmd == "unlock" then
		db.locked = false; Print("drag the green box to move the bar.")
	elseif cmd == "lock" then
		db.locked = true; Print("bar locked.")
	elseif cmd == "reset" then
		if InCombatLockdown() then Print("not in combat.") return end
		db.point, db.scale = nil, 1
		ApplyPosition()
	elseif cmd == "scale" then
		local s = tonumber(arg)
		if not s or s < 0.5 or s > 2 then Print("usage: /stbf scale 0.5-2") return end
		if InCombatLockdown() then Print("not in combat.") return end
		db.scale = s
		ApplyPosition()
	elseif cmd == "set" or cmd == "next" then
		if InCombatLockdown() then Print("not in combat.") return end
		local page = tonumber(arg)
		if cmd == "next" then
			for i = 1, NUM_PAGES do
				local p = (db.page + i - 1) % NUM_PAGES + 1
				if IsKnown(SUMMON_SPELLS[p]) then page = p break end
			end
		end
		if not page or not SUMMON_SPELLS[page] or not IsKnown(SUMMON_SPELLS[page]) then
			Print("that Call spell isn't known.") return
		end
		db.page = page
		Print("editing " .. (SpellName(SUMMON_SPELLS[page]) or ("set " .. page)) .. ".")
	elseif cmd == "debug" then
		local barIndex = C_ActionBar and C_ActionBar.GetMultiCastBarIndex and C_ActionBar.GetMultiCastBarIndex()
		Print(("GetMultiCastBarIndex=%s, gamepadUI=%s, mode=%s, page=%d"):format(
			tostring(barIndex), tostring(IsGamepadUI()), db.mode, db.page))
		for page = 1, NUM_PAGES do
			local parts = {}
			for _, slot in ipairs(SLOT_ORDER) do
				local action = ActionID(page, slot)
				local kind, id = GetActionInfo(action)
				parts[#parts + 1] = ("%s[%d]=%s"):format(SLOT_NAMES[slot], action,
					kind == "spell" and (SpellName(id) or tostring(id)) or "-")
			end
			Print(("%s: %s"):format(SpellName(SUMMON_SPELLS[page]) or page, table.concat(parts, "  ")))
		end
		return
	else
		Help() return
	end
	UpdateAll()
end

SLASH_SHAMANTOTEMBARFIX1 = "/stbf"
SLASH_SHAMANTOTEMBARFIX2 = "/totembar"
SlashCmdList.SHAMANTOTEMBARFIX = Slash

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")

local function SafeRegister(event)
	pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_LOGIN" then
		local _, class = UnitClass("player")
		if class ~= "SHAMAN" then
			self:UnregisterAllEvents()
			return
		end
		ShamanTotemBarFixDB = ShamanTotemBarFixDB or {}
		db = ShamanTotemBarFixDB
		for k, v in pairs(DEFAULTS) do
			if db[k] == nil then db[k] = v end
		end
		CreateFrames()
		ApplyPosition()

		for _, e in ipairs({
			"PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "UPDATE_MULTI_CAST_ACTIONBAR",
			"ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN",
			"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "INPUT_DEVICE_INTERFACE_TRANSITION",
		}) do
			SafeRegister(e)
		end
		UpdateAll()
	elseif event == "ACTIONBAR_SLOT_CHANGED" then
		UpdateVisuals()
		UpdateCooldowns()
	elseif event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
		UpdateCooldowns()
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Fires just before combat lockdown starts: last chance to close the flyout.
		HideFlyout()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingUpdate then UpdateAll() end
	else
		UpdateAll()
	end
end)
events:RegisterEvent("PLAYER_LOGIN")

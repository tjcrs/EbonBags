-- EbonBags - categorized all-in-one bags for WoW 3.3.5a (Project Ebonhold)
-- /ebb            toggle bags
-- /ebb height N   max column height in pixels (default 520)
-- /ebb reset      reset window position

---------------------------------------------------------------------------
-- Settings you may want to edit
---------------------------------------------------------------------------
-- Any item whose name contains one of these (case-insensitive) goes in "Tome of Echo"
local TOME_PATTERNS = { "tome of echo" }

local ICON        = 37   -- icon size
local GAP         = 4    -- space between icons
local PER_ROW     = 4    -- icons per row inside a section
local COL_GAP     = 14   -- space between columns
local HEADER_H    = 16   -- section title height
local SECTION_GAP = 8    -- space between sections
local PAD         = 10   -- window padding
local TOP_H       = 34   -- title bar height
local BOTTOM_H    = 40   -- bottom bar height (holds the bag bar)
local BAGSLOT     = 30   -- bag bar button size

---------------------------------------------------------------------------
-- Category definitions
---------------------------------------------------------------------------
local ORDER = {
    "Tome of Echo", "Quest", "BoE", "@SETS",
    "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist",
    "Hands", "Waist", "Legs", "Feet", "Finger", "Trinket",
    "One-Hand", "Two-Hand", "Off Hand", "Ranged", "Relic",
    "Bags", "Tradeskill", "Gem", "Glyph", "Reagent", "Consumable",
    "Ammo", "Key", "Miscellaneous", "Junk", "Free",
}
local RANK = {}
for i, name in ipairs(ORDER) do RANK[name] = i end

local EQUIP = {
    INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder",
    INVTYPE_CLOAK = "Back", INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest",
    INVTYPE_BODY = "Shirt", INVTYPE_TABARD = "Tabard", INVTYPE_WRIST = "Wrist",
    INVTYPE_HAND = "Hands", INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs",
    INVTYPE_FEET = "Feet", INVTYPE_FINGER = "Finger", INVTYPE_TRINKET = "Trinket",
    INVTYPE_WEAPON = "One-Hand", INVTYPE_WEAPONMAINHAND = "One-Hand",
    INVTYPE_WEAPONOFFHAND = "One-Hand", INVTYPE_2HWEAPON = "Two-Hand",
    INVTYPE_SHIELD = "Off Hand", INVTYPE_HOLDABLE = "Off Hand",
    INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged", INVTYPE_THROWN = "Ranged",
    INVTYPE_RELIC = "Relic", INVTYPE_BAG = "Bags", INVTYPE_QUIVER = "Bags",
    INVTYPE_AMMO = "Ammo",
}
local NO_ILVL = { INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_AMMO = true }

local TYPES = {
    ["Quest"] = "Quest", ["Trade Goods"] = "Tradeskill", ["Recipe"] = "Tradeskill",
    ["Gem"] = "Gem", ["Glyph"] = "Glyph", ["Reagent"] = "Reagent",
    ["Consumable"] = "Consumable", ["Key"] = "Key", ["Projectile"] = "Ammo",
    ["Container"] = "Bags", ["Quiver"] = "Bags",
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
EbonBagsDB = EbonBagsDB or {}
local buttons, headers, setOf = {}, {}, {}
local dirty, needRetry = true, false
local main, search, money

---------------------------------------------------------------------------
-- Tooltip scanning (BoE / quest detection)
---------------------------------------------------------------------------
local tip = CreateFrame("GameTooltip", "EbonBagsScanTip", nil, "GameTooltipTemplate")

local function ScanItem(bag, slot)
    tip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tip:ClearLines()
    tip:SetBagItem(bag, slot)
    local boe, quest = false, false
    for i = 2, tip:NumLines() do
        local fs = _G["EbonBagsScanTipTextLeft" .. i]
        local t = fs and fs:GetText()
        if t then
            if t == ITEM_SOULBOUND or t == ITEM_BIND_ON_PICKUP then
                boe = false
            elseif t == ITEM_BIND_ON_EQUIP then
                boe = true
            elseif t == ITEM_BIND_QUEST or t == ITEM_STARTS_QUEST then
                quest = true
            end
        end
    end
    tip:Hide()
    return boe, quest
end

local function BuildSets()
    wipe(setOf)
    if not GetNumEquipmentSets then return end
    for i = 1, GetNumEquipmentSets() do
        local name = GetEquipmentSetInfo(i)
        local ids = name and GetEquipmentSetItemIDs(name)
        if ids then
            for _, id in pairs(ids) do
                if id and id > 1 and not setOf[id] then setOf[id] = name end
            end
        end
    end
end

local function Categorize(bag, slot, link)
    local name, _, quality, ilvl, _, itype, _, _, equipLoc = GetItemInfo(link)
    if not name then
        needRetry = true
        return "Miscellaneous", "", 1, 0, ""
    end
    local lname = strlower(name)
    for _, p in ipairs(TOME_PATTERNS) do
        if lname:find(p, 1, true) then return "Tome of Echo", name, quality, ilvl, equipLoc end
    end

    local boe, quest = ScanItem(bag, slot)
    if quest or itype == "Quest" then return "Quest", name, quality, ilvl, equipLoc end

    local id = tonumber(link:match("item:(%d+)"))
    if id and setOf[id] then return "Set: " .. setOf[id], name, quality, ilvl, equipLoc end

    if boe then return "BoE", name, quality, ilvl, equipLoc end
    if quality == 0 then return "Junk", name, quality, ilvl, equipLoc end
    if equipLoc and EQUIP[equipLoc] then return EQUIP[equipLoc], name, quality, ilvl, equipLoc end
    return TYPES[itype] or "Miscellaneous", name, quality, ilvl, equipLoc
end

local function CatRank(cat)
    if RANK[cat] then return RANK[cat] end
    if cat:sub(1, 5) == "Set: " then return RANK["@SETS"] end
    return RANK["Miscellaneous"]
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
main = CreateFrame("Frame", "EbonBagsFrame", UIParent)
main:SetWidth(400) main:SetHeight(300)
main:SetFrameStrata("MEDIUM")
main:SetToplevel(true)
main:SetClampedToScreen(true)
main:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
main:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
main:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
main:EnableMouse(true)
main:SetMovable(true)
main:RegisterForDrag("LeftButton")
main:SetScript("OnDragStart", main.StartMoving)
main:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    EbonBagsDB.pos = { point, rel, x, y }
end)
main:Hide()
tinsert(UISpecialFrames, "EbonBagsFrame")

local title = main:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", PAD, -11)
title:SetText("Backpack")

local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 2, 2)

search = CreateFrame("EditBox", "EbonBagsSearch", main, "InputBoxTemplate")
search:SetWidth(150) search:SetHeight(18)
search:SetPoint("TOPRIGHT", -34, -8)
search:SetAutoFocus(false)
local searchHint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
searchHint:SetPoint("LEFT", 2, 0)
searchHint:SetText("Search")
search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
search:SetScript("OnEditFocusGained", function() searchHint:Hide() end)
search:SetScript("OnEditFocusLost", function(self)
    if self:GetText() == "" then searchHint:Show() end
end)

money = main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
money:SetPoint("BOTTOMRIGHT", -PAD, 14)

local function UpdateMoney()
    if GetCoinTextureString then
        money:SetText(GetCoinTextureString(GetMoney()))
    else
        money:SetText(floor(GetMoney() / 10000) .. "g")
    end
end

-- One hidden parent per bag: the Blizzard item-button template reads the bag ID from its parent.
local bagFrames = {}
for bag = 0, NUM_BAG_SLOTS do
    local f = CreateFrame("Frame", "EbonBagsBag" .. bag, main)
    f:SetID(bag)
    f:SetAllPoints(main)
    bagFrames[bag] = f
end


---------------------------------------------------------------------------
-- Bag bar: swap, add or remove your four equipped bags
---------------------------------------------------------------------------
local bagSlots = {}
local hoverBag -- bag currently hovered on the bag bar (highlights its items)

local function UpdateBagSlot(bs)
    local tex = GetInventoryItemTexture("player", bs.inv)
    bs.icon:SetTexture(tex or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
    SetItemButtonDesaturated(bs, IsInventoryItemLocked(bs.inv))
    local n = GetContainerNumSlots(bs.bag)
    if tex and n > 0 then bs.countText:SetText(n) bs.countText:Show() else bs.countText:Hide() end
    local q = GetInventoryItemQuality and GetInventoryItemQuality("player", bs.inv)
    local c = q and q >= 2 and ITEM_QUALITY_COLORS[q]
    if c then bs.border:SetBackdropBorderColor(c.r, c.g, c.b, 1)
    else bs.border:SetBackdropBorderColor(0.3, 0.3, 0.3, 1) end
end

local function UpdateBagBar()
    for _, bs in ipairs(bagSlots) do UpdateBagSlot(bs) end
end

local ApplySearch -- defined below

for i = 1, NUM_BAG_SLOTS do
    local bs = CreateFrame("Button", "EbonBagsBagSlot" .. i, main, "ItemButtonTemplate")
    bs:SetWidth(BAGSLOT) bs:SetHeight(BAGSLOT)
    bs:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", PAD + (i - 1) * (BAGSLOT + 4), 6)
    bs:SetNormalTexture("")
    bs.bag = i
    bs.inv = ContainerIDToInventoryID(i)
    bs.icon = _G[bs:GetName() .. "IconTexture"]
    bs.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bs.countText = _G[bs:GetName() .. "Count"]
    bs.border = CreateFrame("Frame", nil, bs)
    bs.border:SetAllPoints()
    bs.border:SetFrameLevel(bs:GetFrameLevel() + 3)
    bs.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })

    bs:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bs:RegisterForDrag("LeftButton")
    bs:SetScript("OnClick", function(self)
        if CursorHasItem() then PutItemInBag(self.inv) else PickupBagFromSlot(self.inv) end
    end)
    bs:SetScript("OnDragStart", function(self) PickupBagFromSlot(self.inv) end)
    bs:SetScript("OnReceiveDrag", function(self) PutItemInBag(self.inv) end)
    bs:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if not GameTooltip:SetInventoryItem("player", self.inv) then
            GameTooltip:SetText(EQUIP_CONTAINER or "Equip Container", 1, 1, 1)
        end
        GameTooltip:AddLine("Drag a bag here to equip or swap it.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag this bag off to remove it (it must be empty).", 0.7, 0.7, 0.7)
        GameTooltip:Show()
        hoverBag = self.bag
        ApplySearch()
    end)
    bs:SetScript("OnLeave", function()
        GameTooltip:Hide()
        hoverBag = nil
        ApplySearch()
    end)
    bagSlots[i] = bs
end

---------------------------------------------------------------------------
-- Item buttons
---------------------------------------------------------------------------
local function GetButton(bag, slot)
    local key = bag * 100 + slot
    local b = buttons[key]
    if b then return b end

    local name = "EbonBagsItem" .. bag .. "_" .. slot
    b = CreateFrame("Button", name, bagFrames[bag], "ContainerFrameItemButtonTemplate")
    b:SetID(slot)
    b:SetWidth(ICON) b:SetHeight(ICON)
    b:SetNormalTexture("")
    b.icon = _G[name .. "IconTexture"]
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.countText = _G[name .. "Count"]
    b.cooldown = _G[name .. "Cooldown"]
    b.bag, b.slot = bag, slot

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture(0, 0, 0, 0.6)

    b.border = CreateFrame("Frame", nil, b)
    b.border:SetAllPoints()
    b.border:SetFrameLevel(b:GetFrameLevel() + 3)
    b.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })

    b.ilvl = b.border:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.ilvl:SetPoint("TOPLEFT", 2, -2)

    buttons[key] = b
    return b
end

local function UpdateCooldown(b)
    local s, d, e = GetContainerItemCooldown(b.bag, b.slot)
    CooldownFrame_SetTimer(b.cooldown, s or 0, d or 0, e or 0)
end

local function UpdateLock(b)
    local _, _, locked = GetContainerItemInfo(b.bag, b.slot)
    SetItemButtonDesaturated(b, locked)
end

function ApplySearch()
    local q = strlower(strtrim(search:GetText() or ""))
    for _, b in pairs(buttons) do
        if b:IsShown() then
            local match = q == "" or b.isFree or (b.searchText and b.searchText:find(q, 1, true))
            if hoverBag and b.bag ~= hoverBag then match = false end
            if match then
                b:SetAlpha(1)
            else
                b:SetAlpha(0.2)
            end
        end
    end
end
search:SetScript("OnTextChanged", ApplySearch)

local function GetHeader(i)
    local h = headers[i]
    if not h then
        h = main:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetJustifyH("LEFT")
        headers[i] = h
    end
    return h
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local function DoLayout()
    dirty, needRetry = false, false
    for _, b in pairs(buttons) do b:Hide() b.isFree = nil end
    for _, h in ipairs(headers) do h:Hide() end

    local sections, freeCount, freeButton = {}, 0, nil

    for bag = 0, NUM_BAG_SLOTS do
        local _, bagType = GetContainerNumFreeSlots(bag)
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local b = GetButton(bag, slot)
                local cat, name, quality, ilvl, equipLoc = Categorize(bag, slot, link)
                local texture, count = GetContainerItemInfo(bag, slot)
                if not texture then needRetry = true end
                SetItemButtonTexture(b, texture)
                SetItemButtonCount(b, count)
                UpdateLock(b)
                UpdateCooldown(b)

                local c = ITEM_QUALITY_COLORS[quality or 1] or ITEM_QUALITY_COLORS[1]
                if quality and quality >= 2 then
                    b.border:SetBackdropBorderColor(c.r, c.g, c.b, 1)
                else
                    b.border:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                end
                if equipLoc and EQUIP[equipLoc] and not NO_ILVL[equipLoc] and ilvl and ilvl > 1 then
                    b.ilvl:SetText(ilvl)
                    b.ilvl:SetTextColor(c.r, c.g, c.b)
                    b.ilvl:Show()
                else
                    b.ilvl:Hide()
                end

                b.searchText = strlower(name) .. "\n" .. strlower(cat)
                sections[cat] = sections[cat] or {}
                tinsert(sections[cat], { b = b, name = name, q = quality or 1, ilvl = ilvl or 0 })
            elseif bagType == 0 then
                freeCount = freeCount + 1
                if not freeButton then freeButton = GetButton(bag, slot) end
            end
        end
    end

    -- Free slot: a real empty-slot button, so you can drop items on it
    if freeButton then
        local b = freeButton
        b.isFree = true
        SetItemButtonTexture(b, "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        SetItemButtonDesaturated(b, false)
        CooldownFrame_SetTimer(b.cooldown, 0, 0, 0)
        b.countText:SetText(freeCount)
        b.countText:Show()
        b.ilvl:Hide()
        b.border:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        b.searchText = nil
        sections["Free"] = { { b = b, name = "", q = 0, ilvl = 0 } }
    end

    -- Order sections
    local ordered = {}
    for cat, items in pairs(sections) do
        table.sort(items, function(a, b)
            if a.q ~= b.q then return a.q > b.q end
            if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
            if a.name ~= b.name then return a.name < b.name end
            return (a.b.bag * 100 + a.b.slot) < (b.b.bag * 100 + b.b.slot)
        end)
        local rows = ceil(#items / PER_ROW)
        tinsert(ordered, { cat = cat, items = items, h = HEADER_H + rows * (ICON + GAP) - GAP })
    end
    table.sort(ordered, function(a, b)
        local ra, rb = CatRank(a.cat), CatRank(b.cat)
        if ra ~= rb then return ra < rb end
        return a.cat < b.cat
    end)

    -- Pack sections into columns
    local colW = PER_ROW * ICON + (PER_ROW - 1) * GAP
    local target = EbonBagsDB.height or 520
    for _, s in ipairs(ordered) do if s.h > target then target = s.h end end

    local col, y, maxY = 0, 0, 0
    for i, s in ipairs(ordered) do
        if y > 0 and y + s.h > target then col, y = col + 1, 0 end
        local x = PAD + col * (colW + COL_GAP)
        local top = -(TOP_H + y)

        local h = GetHeader(i)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", main, "TOPLEFT", x, top)
        h:SetWidth(colW)
        h:SetText(s.cat)
        h:Show()

        for n, it in ipairs(s.items) do
            local r, c = floor((n - 1) / PER_ROW), (n - 1) % PER_ROW
            it.b:ClearAllPoints()
            it.b:SetPoint("TOPLEFT", main, "TOPLEFT", x + c * (ICON + GAP), top - HEADER_H - r * (ICON + GAP))
            it.b:Show()
        end

        y = y + s.h + SECTION_GAP
        if y - SECTION_GAP > maxY then maxY = y - SECTION_GAP end
    end

    local cols = col + 1
    UpdateBagBar()
    main:SetWidth(math.max(360, PAD * 2 + cols * colW + (cols - 1) * COL_GAP))
    main:SetHeight(TOP_H + maxY + BOTTOM_H + 4)
    UpdateMoney()
    ApplySearch()
end


-- Safe wrapper: if anything goes wrong, report it once and try again shortly
local lastErr
local function Layout()
    local ok, err = pcall(DoLayout)
    if ok then
        lastErr = nil
    else
        dirty = true
        if err ~= lastErr then
            lastErr = err
            DEFAULT_CHAT_FRAME:AddMessage("|cffff3333EbonBags error (please report):|r " .. tostring(err))
        end
    end
end

---------------------------------------------------------------------------
-- Open / close and replacing the default bags
---------------------------------------------------------------------------
local function Show() main:Show() end
local function Hide() main:Hide() end
local function Toggle() if main:IsShown() then main:Hide() else main:Show() end end
local function Mine(id) return id and id >= 0 and id <= NUM_BAG_SLOTS end

main:SetScript("OnShow", function()
    Layout()
    PlaySound("igBackPackOpen")
    if MainMenuBarBackpackButton then MainMenuBarBackpackButton:SetChecked(1) end
end)
main:SetScript("OnHide", function()
    search:ClearFocus()
    PlaySound("igBackPackClose")
    if MainMenuBarBackpackButton then MainMenuBarBackpackButton:SetChecked(nil) end
end)

local orig = {
    ToggleBag = ToggleBag, OpenBag = OpenBag, CloseBag = CloseBag,
    CloseAllBags = CloseAllBags, CloseBackpack = CloseBackpack,
}
ToggleBackpack = Toggle
OpenBackpack   = Show
CloseBackpack  = function() Hide() end
OpenAllBags    = function(force) if force then Show() else Toggle() end end
CloseAllBags   = function() orig.CloseAllBags() Hide() end
ToggleBag      = function(id) if Mine(id) then Toggle() else orig.ToggleBag(id) end end
OpenBag        = function(id) if Mine(id) then Show() else orig.OpenBag(id) end end
CloseBag       = function(id) if Mine(id) then Hide() else orig.CloseBag(id) end end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local OPEN_ON  = { MERCHANT_SHOW = 1, MAIL_SHOW = 1, BANKFRAME_OPENED = 1, AUCTION_HOUSE_SHOW = 1, TRADE_SHOW = 1, GUILDBANKFRAME_OPENED = 1 }
local CLOSE_ON = { MERCHANT_CLOSED = 1, MAIL_CLOSED = 1, BANKFRAME_CLOSED = 1, AUCTION_HOUSE_CLOSED = 1, TRADE_CLOSED = 1, GUILDBANKFRAME_CLOSED = 1 }
for e in pairs(OPEN_ON) do ev:RegisterEvent(e) end
for e in pairs(CLOSE_ON) do ev:RegisterEvent(e) end
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
                     "PLAYER_MONEY", "EQUIPMENT_SETS_CHANGED", "UNIT_INVENTORY_CHANGED" }) do
    ev:RegisterEvent(e)
end

ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local p = EbonBagsDB.pos
        main:ClearAllPoints()
        if p then main:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        else main:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60, 110) end
        BuildSets()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffEbonBags|r loaded - press B or type /ebb")
    elseif event == "BAG_UPDATE" or event == "UNIT_INVENTORY_CHANGED" then
        dirty = true
    elseif event == "EQUIPMENT_SETS_CHANGED" then
        BuildSets()
        dirty = true
    elseif event == "ITEM_LOCK_CHANGED" then
        for _, b in pairs(buttons) do if b:IsShown() and not b.isFree then UpdateLock(b) end end
        UpdateBagBar()
    elseif event == "BAG_UPDATE_COOLDOWN" then
        for _, b in pairs(buttons) do if b:IsShown() and not b.isFree then UpdateCooldown(b) end end
    elseif event == "PLAYER_MONEY" then
        UpdateMoney()
    elseif OPEN_ON[event] then
        Show()
    elseif CLOSE_ON[event] then
        Hide()
    end
end)

-- Batch updates: re-layout at most ~10 times a second, only while open.
local elapsed, retryTimer = 0, 0
ev:SetScript("OnUpdate", function(_, dt)
    if not main:IsShown() then return end
    if needRetry then
        retryTimer = retryTimer + dt
        if retryTimer > 1 then retryTimer = 0 dirty = true end
    end
    if dirty then
        elapsed = elapsed + dt
        if elapsed > (lastErr and 1 or 0.1) then elapsed = 0 Layout() end
    end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
SLASH_EBONBAGS1 = "/ebb"
SLASH_EBONBAGS2 = "/ebonbags"
SlashCmdList["EBONBAGS"] = function(msg)
    msg = strlower(strtrim(msg or ""))
    local h = tonumber(msg:match("^height%s+(%d+)"))
    if h then
        EbonBagsDB.height = h
        if main:IsShown() then Layout() end
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffEbonBags:|r column height set to " .. h)
    elseif msg == "reset" then
        EbonBagsDB.pos = nil
        main:ClearAllPoints()
        main:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60, 110)
    else
        Toggle()
    end
end

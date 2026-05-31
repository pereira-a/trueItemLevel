local frame       = CreateFrame("Frame")
local inspectName = nil
local inspectUnit = nil  -- fallback unit from NotifyInspect
local inspectGUID = nil  -- set only for user-initiated inspects (InspectUnit)
local currentUnit = nil
local itemLinks   = {}
local pendingIDs  = {}
local retrySlots  = {}   -- itemID → slot, for nil-link retries
local ilevelLabel = nil
local labelFrame  = nil

-- Fires for all inspects (user + background); save unit as fallback only.
hooksecurefunc("NotifyInspect", function(unit)
    inspectUnit = unit
end)

-- Fires only when user opens inspect window; marks this as a user inspect.
hooksecurefunc("InspectUnit", function(unit)
    inspectGUID = UnitGUID(unit)
end)


local function isTwoHandedWeapon(equipLoc)
    return equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_RANGED"
end

local function isTabardOrShirt(equipLoc)
    return equipLoc == "INVTYPE_TABARD" or equipLoc == "INVTYPE_BODY"
end

local function ensureLabel()
    if ilevelLabel then return end
    if not InspectFrame then return end

    labelFrame = CreateFrame("Frame", nil, UIParent)
    labelFrame:SetFrameStrata("TOOLTIP")
    labelFrame:SetSize(90, 20)
    labelFrame:SetPoint("LEFT", InspectPaperDollFrame.ViewButton, "RIGHT", 2, 0)

    ilevelLabel = labelFrame:CreateFontString(nil, "OVERLAY")
    ilevelLabel:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    ilevelLabel:SetAllPoints(labelFrame)
    ilevelLabel:SetTextColor(1, 0.82, 0)
    labelFrame:Hide()

    InspectFrame:HookScript("OnHide", function()
        labelFrame:Hide()
    end)
end

-- Mirrors Blizzard's GetAverageItemLevel logic (always divides by 16).
local function calculateItemLevel()
    local total, count = 0, 16

    local link16 = itemLinks[16]
    local link17 = itemLinks[17]
    local isTitansGrip = false
    if link16 and link17 then
        local _, _, _, equip16 = C_Item.GetItemInfoInstant(link16)
        local _, _, _, equip17 = C_Item.GetItemInfoInstant(link17)
        isTitansGrip = isTwoHandedWeapon(equip16) and isTwoHandedWeapon(equip17)
    end

    for slot = 1, 19 do
        local link = itemLinks[slot]
        if link ~= nil then
            local level = C_Item.GetDetailedItemLevelInfo(link)
            if level and level > 0 then
                local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
                if isTabardOrShirt(equipLoc) then level = 0 end
                -- Solo 2H counts double; Titan's Grip uses both slots normally.
                if isTwoHandedWeapon(equipLoc) and not isTitansGrip then
                    level = level * 2
                end
                total = total + level
            end
        end
    end
    return total / count
end


local function hasAnyItem()
    for slot = 1, 19 do
        if itemLinks[slot] ~= nil then return true end
    end
    return false
end

local function resetState()
    currentUnit = nil
    inspectName = nil
    itemLinks   = {}
    pendingIDs  = {}
    retrySlots  = {}
    frame:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
end

local function finalize()
    if next(pendingIDs) ~= nil then return end  -- still waiting on item data

    if not hasAnyItem() then
        if labelFrame then labelFrame:Hide() end
        resetState()
        return
    end

    local itemLevel = calculateItemLevel()
    print(string.format("|cFF00B4FF[True Item Level]|r |cFFFFFFFF%s|r \194\187 |cFFFFD700%.1f iLvl|r", inspectName, itemLevel))

    if ilevelLabel and labelFrame then
        ilevelLabel:SetText(string.format("%.1f iLvl", itemLevel))
    end

    resetState()
end

local function runForUnit(unit, name)
    currentUnit = unit
    inspectName = name
    itemLinks   = {}
    pendingIDs  = {}
    retrySlots  = {}
    frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")

    ensureLabel()
    if ilevelLabel and labelFrame then
        ilevelLabel:SetText("Loading...")
        labelFrame:Show()
    end

    for slot = 1, 19 do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            itemLinks[slot] = link
            local itemID = tonumber(link:match("item:(%d+)"))
            if itemID and not C_Item.IsItemDataCachedByID(itemID) then
                pendingIDs[itemID] = true
                C_Item.RequestLoadItemDataByID(itemID)
            end
        else
            -- Link unavailable; request data and retry link on ITEM_DATA_LOAD_RESULT.
            -- Skip if already cached — RequestLoadItemDataByID would be a no-op and
            -- the event would never fire, blocking pendingIDs forever.
            local itemID = GetInventoryItemID(unit, slot)
            if itemID and not C_Item.IsItemDataCachedByID(itemID) then
                pendingIDs[itemID] = true
                retrySlots[itemID] = slot
                C_Item.RequestLoadItemDataByID(itemID)
            end
        end
    end

    finalize()
end

SLASH_TRUEITEMLEVEL1 = "/debug"
SlashCmdList["TRUEITEMLEVEL"] = function()
    runForUnit("player", GetUnitName("player", true) or "player")
end

frame:RegisterEvent("INSPECT_READY")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "INSPECT_READY" then
        local guid = ...

        -- Background inspects (raid frames, LibGroupInSpecT) call NotifyInspect
        -- directly without InspectUnit, so inspectGUID stays nil — drop them.
        if inspectGUID == nil then return end
        if guid ~= inspectGUID then return end
        inspectGUID = nil

        local unit = UnitTokenFromGUID(guid) or inspectUnit or "inspect"
        if UnitIsUnit(unit, "player") then return end

        runForUnit(unit, GetUnitName(unit, true) or guid)

    elseif event == "ITEM_DATA_LOAD_RESULT" then
        local itemID = ...
        if not pendingIDs[itemID] then return end

        -- Retry link for slots that returned nil on first scan.
        local slot = retrySlots[itemID]
        if slot and currentUnit and not itemLinks[slot] then
            local link = GetInventoryItemLink(currentUnit, slot)
            if link then itemLinks[slot] = link end
        end

        pendingIDs[itemID] = nil
        finalize()
    end
end)

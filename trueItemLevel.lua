local frame       = CreateFrame("Frame")
local inspectUnit = nil
local inspectName = nil
local itemLinks   = {}
local pendingIDs  = {}
local ilevelLabel = nil


-- GetInventoryItemLink needs the unit and INSPECT_READY only gives the GUID
hooksecurefunc("NotifyInspect", function(unit)
    inspectUnit = unit
end)

local function isTwoHandedWeapon(equipLoc)
    return equipLoc == "INVTYPE_2HWEAPON"
end

local function isTabardOrShirt(equipLoc)
    return equipLoc == "INVTYPE_TABARD" or equipLoc == "INVTYPE_BODY"
end

local labelFrame = nil

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

-- Replicates the logic used by blizzard (https://warcraft.wiki.gg/wiki/API_GetAverageItemLevel)
-- Requires itemLinks to be populated
local function calculateItemLevel()
    local total, count = 0, 16 -- blizzard always devides by 16
    local hasTwoHand = false
    for slot = 1, 19 do
        local link = itemLinks[slot]
        if link ~= nil then
            local level = C_Item.GetDetailedItemLevelInfo(link)
            if level and level > 0 then
                local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)

                if isTabardOrShirt(equipLoc) then
                    -- tabards and shirts are ignored
                    level = 0
                end

                -- Double the item level contribution for two-handed weapons
                if isTwoHandedWeapon(equipLoc) and not hasTwoHand then
                    level = level * 2
                    hasTwoHand = true -- only double for the first two-handed weapon (to handle Warriors with Titan's Grip)
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

local function finalize()
    if not hasAnyItem() then return end
    if next(pendingIDs) ~= nil then return end

    local itemLevel = calculateItemLevel()
    print(string.format("|cFF00B4FF[True Item Level]|r |cFFFFFFFF%s|r \194\187 |cFFFFD700%.1f iLvl|r", inspectName, itemLevel))

    if labelFrame then
        ilevelLabel:SetText(string.format("%.1f iLvl", itemLevel))
        labelFrame:Show()
    end

    -- reset state
    inspectUnit = nil
    inspectName = nil
    itemLinks   = {}
    pendingIDs  = {}
    frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
end

local function runForUnit(unit, name)
    inspectUnit = unit
    inspectName = name
    itemLinks   = {}
    pendingIDs  = {}
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

    ensureLabel()
    if labelFrame then
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
            -- Link not available yet — item data isn't loaded.
            -- GetInventoryItemID can still return the raw item ID from the inspect
            -- packet, which lets request the data so GET_ITEM_INFO_RECEIVED fires
            local itemID = GetInventoryItemID(unit, slot)
            if itemID then
                pendingIDs[itemID] = true
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
        if inspectUnit == nil then
            return
        end

        local guid = ...
        local unit = inspectUnit or "inspect"
        inspectUnit = nil -- clear now so duplicate INSPECT_READY fires are ignored

        if UnitIsUnit(unit, "player") then return end

        local name = GetUnitName(unit, true) or guid
        runForUnit(unit, name)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID = ...
        pendingIDs[itemID] = nil
        finalize()
    end
end)

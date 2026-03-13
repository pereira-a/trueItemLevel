local frame       = CreateFrame("Frame")
local inspectUnit = nil
local inspectName = nil
local itemLinks   = {}


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

local function calculateCount()
    local count = 17
    local _, _, _, equipLoc16 = C_Item.GetItemInfoInstant(itemLinks[16] or 0)
    if ((itemLinks[16] == nil and itemLinks[17] == nil) or -- if both main hand and off hand are empty
            ((isTwoHandedWeapon(equipLoc16)) and (itemLinks[17] == nil))) then -- or if main hand is a two handed weapon (and not using Titans Grip)
        count = 16
    end
    return count
end

-- Replicates the logic used by blizzard (https://warcraft.wiki.gg/wiki/API_GetAverageItemLevel)
-- Requires itemLinks to be populated
local function calculateItemLevel() 
    local total, count = 0, calculateCount()
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
                -- if isTwoHandedWeapon(equipLoc) then
                --     level = level * 2
                -- end

                total = total + level
            end
        end
    end
    return total / count
end


local function finalize()
    if #itemLinks == 0 then return end -- no items, nothing to do / means GET_ITEM_INFO_RECEIVED fired for an unrelated task

    local allCached = true
    for slot = 1, 19 do
        local link = itemLinks[slot]
        if link ~= nil and not C_Item.IsItemDataCachedByID(link) then
            C_Item.RequestLoadItemDataByID(link)
            allCached = false
        end
    end
    if not allCached then return end    

    local itemLevel = calculateItemLevel()
    print(string.format("|cFF00B4FF[True Item Level]|r |cFFFFFFFF%s|r \194\187 |cFFFFD700%.1f iLvl|r", inspectName, itemLevel))

    -- reset state
    inspectUnit = nil
    inspectName = nil
    itemLinks   = {}
    frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
end

frame:RegisterEvent("INSPECT_READY")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "INSPECT_READY" then
        -- INSPECT_READY fires for every item. Ensure we only process the first time.
        if inspectUnit == nil then
            return
        end

        local guid  = ...
        local unit  = inspectUnit or "inspect"
        inspectName = GetUnitName(unit, true) or guid
        itemLinks   = {}

        for slot = 1, 19 do
            local link = GetInventoryItemLink(unit, slot)
            itemLinks[slot] = link
        end

        if #itemLinks > 0 then
            -- try to finalize immediately, in case all item info is already cached. If not, GET_ITEM_INFO_RECEIVED will fire when data is available
            finalize()
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        finalize()
    end
end)

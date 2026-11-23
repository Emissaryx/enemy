local tinsert = table.insert
local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local type = type


local function CloneValue(value)

    if (type(value) ~= "table") then
        return value
    end

    local res = {}

    for key, nestedValue in pairs(value)
    do
        if (type(nestedValue) ~= "function")
        then
            res[key] = CloneValue(nestedValue)
        end
    end

    return res
end


local function ExtendMissing(target, defaults)

    if (type(target) ~= "table" or type(defaults) ~= "table") then
        return
    end

    for key, value in pairs(defaults)
    do
        if (type(value) == "table")
        then
            if (type(target[key]) ~= "table")
            then
                target[key] = {}
            end

            ExtendMissing(target[key], value)
        end

        if (target[key] == nil)
        then
            target[key] = CloneValue(value)
        end
    end
end


local function MakeUnitFramePartKey(item)

    return tostring(item.type or "")
        .."\t"..tostring(item.name or "")
        .."\t"..tostring(item.playerType or "")
        .."\t"..tostring(item.playerTypeMatch or "")
end


local function MakeEffectsIndicatorKey(item)

    return tostring(item.name or "")
        .."\t"..tostring(item.icon or "")
        .."\t"..tostring(item.playerType or "")
        .."\t"..tostring(item.playerTypeMatch or "")
end


local function MakeClickCastingKey(item)

    return tostring(item.name or "")
        .."\t"..tostring(item.mouseButton or "")
        .."\t"..tostring(item.action or "")
end


local function MakeUniqueNameKey(item)

    if (item.name == nil) then
        return nil
    end

    local key = tostring(item.name)
    if (key == "") then
        return nil
    end

    return key
end


local function ClearWrongEffectFilterAbilityIds(item, defaultItem, wrongDefaultItem)

    if (type(item) ~= "table"
        or type(defaultItem) ~= "table"
        or type(wrongDefaultItem) ~= "table"
        or type(item.effectFilters) ~= "table"
        or type(wrongDefaultItem.effectFilters) ~= "table")
    then
        return
    end

    local defaultFilters = defaultItem.effectFilters or {}

    for index, wrongFilter in pairs(wrongDefaultItem.effectFilters)
    do
        local itemFilter = item.effectFilters[index]
        local defaultFilter = defaultFilters[index]

        if (type(itemFilter) == "table"
            and type(wrongFilter) == "table"
            and wrongFilter.abilityIds ~= nil
            and (type(defaultFilter) ~= "table" or defaultFilter.abilityIds == nil)
            and itemFilter.abilityIds == wrongFilter.abilityIds)
        then
            itemFilter.abilityIds = nil
            itemFilter.abilityIdsHash = nil
        end
    end
end


local listMergeSpecs =
{
    { key = "unitFramesParts", makeKey = MakeUnitFramePartKey, dedupeKey = MakeUniqueNameKey },
    { key = "effectsIndicators", makeKey = MakeEffectsIndicatorKey, dedupeKey = MakeUniqueNameKey },
    { key = "clickCastings", makeKey = MakeClickCastingKey, dedupeKey = MakeUniqueNameKey }
}


local function BuildListLookup(defaults, makeKey)

    local defaultsById = {}
    local defaultIdIsAmbiguous = {}
    local defaultsByKey = {}

    if (type(defaults) ~= "table") then
        return defaultsById, defaultIdIsAmbiguous, defaultsByKey
    end

    for _, item in ipairs(defaults)
    do
        if (item.id ~= nil)
        then
            local id = tostring(item.id)
            if (defaultsById[id] == nil)
            then
                defaultsById[id] = item
            else
                defaultsById[id] = item
                defaultIdIsAmbiguous[id] = true
            end
        end

        local key = makeKey(item)
        if (key ~= nil)
        then
            if (defaultsByKey[key] == nil)
            then
                defaultsByKey[key] = item
            else
                defaultsByKey[key] = false
            end
        end
    end

    return defaultsById, defaultIdIsAmbiguous, defaultsByKey
end


local function MergeSettingsList(list, defaults, makeKey, dedupeKey)

    if (type(list) ~= "table")
    then
        return nil
    end

    local defaultsById, defaultIdIsAmbiguous, defaultsByKey = BuildListLookup(defaults, makeKey)
    local merged = {}
    local seenNames = {}

    for _, item in ipairs(list)
    do
        local uniqueNameKey = nil
        local skipItem = false

        if (dedupeKey)
        then
            uniqueNameKey = dedupeKey(item)

            if (uniqueNameKey ~= nil and seenNames[uniqueNameKey])
            then
                -- Duplicate names are not valid in the config UI, so when they
                -- appear here they are stale legacy corruption from the old
                -- index-based merge. Keep the first entry and drop the rest.
                skipItem = true
            end
        end

        if (not skipItem and uniqueNameKey ~= nil)
        then
            seenNames[uniqueNameKey] = true
        end

        if (not skipItem)
        then
            local mergedItem = CloneValue(item)
            local defaultItem = nil
            local key = makeKey(item)
            local wrongDefaultItem = nil

            if (item.id ~= nil)
            then
                local id = tostring(item.id)
                local idMatch = defaultsById[id]
                if (type(idMatch) == "table"
                    and not defaultIdIsAmbiguous[id]
                    and makeKey(idMatch) == key)
                then
                    defaultItem = idMatch
                elseif (type(idMatch) == "table")
                then
                    wrongDefaultItem = idMatch
                end
            end

            if (defaultItem == nil)
            then
                if (key ~= nil and defaultsByKey[key] and defaultsByKey[key] ~= false)
                then
                    defaultItem = defaultsByKey[key]
                end
            end

            if (type(defaultItem) == "table")
            then
                ClearWrongEffectFilterAbilityIds(mergedItem, defaultItem, wrongDefaultItem)
                ExtendMissing(mergedItem, defaultItem)
            end

            tinsert(merged, mergedItem)
        end
    end

    return merged
end


-- Preserve ordered configuration lists exactly as the user saved them.
-- We still backfill missing fields on surviving entries by matching defaults
-- on stable ids first, then on a type/name style key as a fallback. Some
-- legacy/default entries have reused ids, so an id match must also match the
-- item key before nested defaults are copied into user settings.
function Enemy.ApplyDefaultSettings(settings, defaults)

    if (type(settings) ~= "table")
    then
        settings = {}
    end

    defaults = defaults or Enemy.DefaultSettings or {}

    local prevVersion = settings.version or 0
    local preservedLists = {}

    for _, spec in ipairs(listMergeSpecs)
    do
        if (type(settings[spec.key]) == "table")
        then
            preservedLists[spec.key] = MergeSettingsList(settings[spec.key], defaults[spec.key], spec.makeKey, spec.dedupeKey)
            settings[spec.key] = nil
        end
    end

    ExtendMissing(settings, defaults)

    for key, value in pairs(preservedLists)
    do
        settings[key] = value
    end

    settings.prevVersion = prevVersion
    settings.version = defaults.version

    return settings
end

-- Native windows may transfer only within one rebuild of their owning frame.
-- ObjectReuse separately decides whether Lua components can be retained.
local Enemy = Enemy
local Reuse = {}
Enemy.UnitFrameWindowReuse = Reuse
local scopes, windows = {}, {}
local owners = setmetatable ({}, { __mode = "k" })
local cancelled = {}
local stopping = false
-- Reuse only empty transaction storage. Native trust and data inspection are
-- recomputed for every call; a nested transaction never borrows an active scope.
-- Keep one cleared spare; never retain frame graphs between transactions.
local spareScope

local function ClearPrivateTable (value)
    for key in pairs (value) do value[key] = nil end
end

local function AcquireScope (parent, player)
    local scope = spareScope
    spareScope = nil
    if (not scope) then
        scope = { free = {}, created = {}, objects = {}, checkStorage = {}, dataStorage = {} }
    end
    scope.parent, scope.player = parent, player
    scope.checked, scope.dataChecked = scope.checkStorage, scope.dataStorage
    scope.checked[EnemyUnitFrame] = true
    scope.checked[EnemyUnitFramePart] = true
    scope.checked[EnemyEffectsIndicator] = true
    scope.checked[EnemyEffectFilter] = true
    return scope
end

local function RecycleScope (scope)
    if (stopping or spareScope) then return end
    local free, created, objects = scope.free, scope.created, scope.objects
    local checks, data = scope.checkStorage, scope.dataStorage
    ClearPrivateTable (free)
    ClearPrivateTable (created)
    ClearPrivateTable (objects)
    ClearPrivateTable (checks)
    ClearPrivateTable (data)
    ClearPrivateTable (scope)
    scope.free, scope.created, scope.objects = free, created, objects
    scope.checkStorage, scope.dataStorage = checks, data
    spareScope = scope
end
Reuse._nativeClasses = {}
Reuse._nativeTypes = setmetatable ({}, { __mode = "k" })
Reuse._nativeFilterTypes = {}
Reuse._nativeHelpers = {}

local helpers = {
    "UnitFramePart_OnRemove", "UnitFramePart_CreateWindow", "UnitFramePart_SetShowing",
    "UnitFramePart_OnUpdate_ProceedWindowInitialization", "UnitFramePart_OnUpdate_ProceedTextWindowInitialization",
    "UnitFramePart_OnUpdate_ProceedState", "UnitFramePart_OnUpdate_ProceedTextState",
    "UnitFramePart_OnUpdate_ProceedStateExceptColor", "UnitFramePart_OnUpdate_ProceedStateExceptShowing",
    "UnitFramePart_GetTexture", "UnitFramePart_ApplyTexture", "UnitFramePart_ApplyTexturePercentResize",
    "clone", "toString", "Split", "trim", "FixString", "NewId", "UnitFramesShouldIgnoreAltSpecForCareer",
    "UnitFrames_OnGroupsUpdated", "_UnitFramesDisableAll",
    "LogicalExpressionParse", "LogicalExpressionEvaluate", "UnitFramesGetLeaderIconState",
}

local function CaptureTable (value)
    local result = { functions = {}, keys = {}, methodKeys = {}, functionCount = 0 }
    for key, item in pairs (value) do
        result.keys[key] = true
        if (type (item) == "function") then
            result.functions[key] = item
            result.functionCount = result.functionCount + 1
            result.methodKeys[result.functionCount] = key
        end
    end
    return result
end

local function UnchangedTable (value, original)
    if (not original or getmetatable (value) ~= nil) then return false end
    local count, functions = 0, original.functions
    for key, item in pairs (value) do
        local callback = functions[key]
        if (callback) then
            if (item ~= callback) then return false end
            count = count + 1
        elseif (not original.keys[key]) then return false end
    end
    -- Counting matched functions detects deleted methods without a second walk.
    return count == original.functionCount
end

local function CheckedTable (value, original, scope)
    if (not scope or scope.uncached) then return UnchangedTable (value, original) end
    local valid = scope.checked[value]
    if (valid == nil) then valid = UnchangedTable (value, original); scope.checked[value] = valid end
    return valid
end

local function Invalidate (scope)
    if (not scope or scope.uncached) then return end
    scope.uncached = true
    scope.checked = nil
    scope.dataChecked = nil
    scope.careerSafe = false
    scope.hasNonReusable = true
    -- Unknown code may also touch earlier bound windows. Do not carry their
    -- native subtrees into a future stock rebuild after that callback returns.
    for _, record in ipairs (scope.created) do record.reusable = false end
end

local function TrustedClass (object, class, scope)
    local original = Reuse._nativeClasses and Reuse._nativeClasses[class]
    if (getmetatable (object) ~= class or class.__index ~= class or not CheckedTable (class, original, scope)) then return false end
    local keys, functions = original.methodKeys, original.functions
    for index = 1, #keys do
        local key = keys[index]
        if (object[key] ~= functions[key]) then return false end
    end
    return true
end

local function Trusted (object, kind, scope)
    if (not scope or scope.uncached or not scope.helpersChecked) then
        for key, callback in pairs (Reuse._nativeHelpers or {}) do if (Enemy[key] ~= callback) then return false end end
        if (scope) then scope.helpersChecked = true end
    end
    if (kind == "part") then
        if (not TrustedClass (object, EnemyUnitFramePart, scope)) then return false end
        local descriptor = object._type
        return descriptor and descriptor.key == object.type
            and Enemy.unitFramesParts.types[object.type] == descriptor
            and CheckedTable (descriptor, Reuse._nativeTypes[descriptor], scope)
    end
    if (not TrustedClass (object, EnemyEffectsIndicator, scope)
        or not CheckedTable (EnemyEffectFilter, Reuse._nativeClasses[EnemyEffectFilter], scope)
        or not object._windowReuseLoaded or object._checkDispell ~= object._windowReuseCheckDispell)
    then return false end
    for _, filter in ipairs (object.effectFilters) do
        if (getmetatable (filter) ~= EnemyEffectFilter or filter.IsMatch ~= filter._windowReuseMatcher) then return false end
        local original = Reuse._nativeClasses[EnemyEffectFilter]
        local keys, functions = original.methodKeys, original.functions
        for index = 1, #keys do
            local key = keys[index]
            if (key ~= "IsMatch" and filter[key] ~= functions[key]) then return false end
        end
        if (filter.type and (not filter._enemyFilterTypeData
            or not CheckedTable (filter._enemyFilterTypeData, Reuse._nativeFilterTypes[filter._enemyFilterTypeData], scope)))
        then return false end
    end
    return true
end

-- Known writers reapply native visual fields, so compatibility is the part
-- type/template, not an identical saved descriptor. Reject executable settings;
-- class-valued configuration previews expose only fields consumed by Load.
local partFields = { "name", "isEnabled", "playerTypeMatch", "playerType", "exceptMe",
    "archetypeMatch", "archetypes", "type", "data" }
local indicatorFields = { "name", "isEnabled", "logic", "canDispell", "playerTypeMatch",
    "playerType", "exceptMe", "archetypeMatch", "archetypes", "icon", "customIcon",
    "isCircleIcon", "isTimer", "color", "alpha", "labelScale", "scale", "anchorFrom",
    "anchorTo", "offsetX", "offsetY", "width", "height" }
local filterFields = { "filterName", "name", "nameMatch", "description", "descriptionMatch",
    "abilityIds", "typeMatch", "type", "durationType", "durationMin", "durationMax", "stackCount", "castedByMe" }

-- One inspection serves both the hook preflight and strict reset eligibility.
-- Scalar fields are checked inline; only nested tables recurse. Results live
-- solely within this uninterrupted stock rebuild, never across events/settings.
-- 0: executable hooks, 1: hook-free but not plain saved data, 2: plain data.
local function Inspect (value, depth, scope)
    local kind = type (value)
    if (kind ~= "table") then
        if (kind == "userdata" or kind == "thread") then return 0 end
        return kind == "function" and 1 or 2
    end
    if (depth > 16 or getmetatable (value) ~= nil) then return 0 end
    local checked = scope and not scope.uncached and scope.dataChecked
    local result = checked and checked[value]
    if (result ~= nil and result ~= false) then return result end
    result = 2
    for key, item in pairs (value) do
        local keyKind = type (key)
        if (keyKind ~= "string" and keyKind ~= "number") then result = 1 end
        local itemKind = type (item)
        if (itemKind == "table") then
            local nested = Inspect (item, depth + 1, scope)
            if (nested < result) then result = nested end
            if (result == 0) then break end
        elseif (itemKind == "userdata" or itemKind == "thread") then
            result = 0
            break
        elseif (itemKind == "function") then result = 1 end
    end
    if (checked) then checked[value] = result end
    return result
end

local function Plain (value, depth, scope)
    return Inspect (value, depth, scope) == 2
end

local function NoHooks (value, depth, scope)
    return Inspect (value, depth, scope) > 0
end

local function FieldsPlain (value, fields, scope)
    for _, key in ipairs (fields) do if (not Plain (value[key], 0, scope)) then return false end end
    return true
end

local function SafeDefinition (definition, kind, scope)
    if (type (definition) ~= "table") then return false end
    if (getmetatable (definition) == nil) then return Plain (definition, 0, scope) end
    if (not Trusted (definition, kind, scope)) then return false end
    if (kind == "part") then return FieldsPlain (definition, partFields, scope) end
    if (not FieldsPlain (definition, indicatorFields, scope) or getmetatable (definition.effectFilters) ~= nil) then return false end
    for _, filter in pairs (definition.effectFilters) do
        if (getmetatable (filter) == EnemyEffectFilter) then
            if (not FieldsPlain (filter, filterFields, scope)) then return false end
        elseif (not Plain (filter, 0, scope)) then return false end
    end
    return true
end

local function DefinitionHasNoHooks (definition, kind, scope)
    if (type (definition) ~= "table") then return false end
    if (getmetatable (definition) == nil) then return NoHooks (definition, 0, scope) end
    local class = kind == "part" and EnemyUnitFramePart or EnemyEffectsIndicator
    if (not TrustedClass (definition, class, scope)) then return false end
    for _, key in ipairs (kind == "part" and partFields or indicatorFields) do
        if (not NoHooks (definition[key], 0, scope)) then return false end
    end
    if (kind == "indicator") then
        if (type (definition.effectFilters) ~= "table" or getmetatable (definition.effectFilters) ~= nil) then return false end
        for _, filter in pairs (definition.effectFilters) do
            if (getmetatable (filter) == EnemyEffectFilter) then
                for _, key in ipairs (filterFields) do if (not NoHooks (filter[key], 0, scope)) then return false end end
            elseif (not NoHooks (filter, 0, scope)) then return false end
        end
    end
    return true
end

-- Conditional career textures may transfer only when later bindings cannot
-- change the player/spec inputs before first render. Earlier custom removal
-- invalidates this decision before career acquisition starts.
local function NativeSkipsDefinition (definition, kind, frame)
    if (type (definition) ~= "table" or getmetatable (definition) ~= nil) then return false end
    local archetypes = rawget (definition, "archetypes")
    local player = scopes[frame].player
    if (rawget (definition, "isEnabled")) then
        local playerType = rawget (definition, "playerType")
        local exceptMe = rawget (definition, "exceptMe")
        local mask = type (archetypes) == "table"
            and (rawget (archetypes, 1) or rawget (archetypes, 2) or rawget (archetypes, 3))
        local dispel = kind == "indicator" and rawget (definition, "canDispell") == 2
        if (playerType ~= 2 and playerType ~= 3 and not exceptMe and not mask and not dispel) then return false end
        -- Only speculate with raw native player fields. The native gate below
        -- decides the actual eligibility; unknown getters keep the full walk.
        if (type (player) ~= "table") then return false end
        local isSelf, inGroup = rawget (player, "isSelf"), rawget (player, "isInPlayerGroup")
        if (type (isSelf) ~= "boolean" or type (inGroup) ~= "boolean"
            or type (rawget (player, "career")) ~= "number") then return false end
        local inclusive = rawget (definition, "playerTypeMatch") == 1
        local candidate = (playerType == 2 and isSelf ~= inclusive)
            or (playerType == 3 and inGroup ~= inclusive)
            or (exceptMe and isSelf) or mask or dispel
        if (not candidate or type (Enemy.careerArchetypes) ~= "table" or getmetatable (Enemy.careerArchetypes) ~= nil) then return false end
        if (kind == "indicator" and (type (Enemy.groups) ~= "table" or getmetatable (Enemy.groups) ~= nil)) then return false end
    end

    if (archetypes ~= nil and (type (archetypes) ~= "table" or getmetatable (archetypes) ~= nil)) then return false end
    local class = kind == "part" and EnemyUnitFramePart or EnemyEffectsIndicator
    local original = Reuse._nativeClasses[class]
    local skip = rawget (class, "CanSkipConstruction")
    if (not original or skip ~= original.functions.CanSkipConstruction or getmetatable (class) ~= nil) then return false end
    local settings = frame.settings
    if (type (settings) ~= "table" or getmetatable (settings) ~= nil) then return false end
    local testMode = rawget (settings, "unitFramesTestMode")
    if (kind == "indicator" and testMode and rawget (definition, "isEnabled")) then return false end

    if (kind == "part") then
        local parts = Enemy.unitFramesParts
        if (type (parts) ~= "table" or getmetatable (parts) ~= nil) then return false end
        local types = rawget (parts, "types")
        local owned = rawget (parts, "_showingOwnedTypes")
        if (type (types) ~= "table" or getmetatable (types) ~= nil
            or type (owned) ~= "table" or getmetatable (owned) ~= nil) then return false end
        local descriptor = rawget (types, rawget (definition, "type"))
        if (type (descriptor) ~= "table" or getmetatable (descriptor) ~= nil) then return false end
        return skip (definition, player)
    end
    return skip (definition, player, testMode)
end

local function CareerResolversNative ()
    return GetIconData == Reuse._careerGetIconData and type (Icons) == "table"
        and getmetatable (Icons) == nil
        and rawget (Icons, "GetCareerIconIDFromCareerLine") == Reuse._careerGetCareerIcon
end

local function ClickBindingsSafe (frame, scope)
    local settings, clicks = rawget (frame, "settings"), rawget (frame, "clickCastings")
    if (type (settings) ~= "table" or getmetatable (settings) ~= nil
        or type (clicks) ~= "table" or getmetatable (clicks) ~= nil) then return false end
    local definitions = rawget (settings, "clickCastings")
    if (type (definitions) ~= "table" or getmetatable (definitions) ~= nil) then return false end
    if (not CheckedTable (EnemyClickCasting, Reuse._nativeClasses[EnemyClickCasting], scope)) then return false end
    for _, click in ipairs (clicks) do if (not TrustedClass (click, EnemyClickCasting, scope)) then return false end end
    for _, definition in pairs (definitions) do
        local meta = getmetatable (definition)
        if (meta == EnemyClickCasting) then
            if (not TrustedClass (definition, EnemyClickCasting, scope)) then return false end
            if (not NoHooks (definition.keyModifiers, 0, scope) or not NoHooks (definition.archetypes, 0, scope)) then return false end
        elseif (not NoHooks (definition, 0, scope)) then return false end
    end
    return true
end

local function HasTransferableCareerWindows (frame)
    for _, part in ipairs (frame.parts) do
        local owner = owners[part]
        if (owner and rawget (part, "type") == "careerIcon") then
            local record = owner.windowName and windows[owner.windowName]
            if (record and record.object == part and record.reusable
                and record.frame == frame and record.parent == frame.windowName) then return true end
            record = owner.altWindowName and windows[owner.altWindowName]
            if (record and record.object == part and record.reusable
                and record.frame == frame and record.parent == frame.windowName) then return true end
        end
    end
    return false
end

local function CareerBindingsSafe (frame, scope)
    if (not CareerResolversNative ()) then return false end
    for _, indicator in ipairs (frame.effectsIndicators) do
        if (indicator.Remove ~= Reuse._nativeClasses[EnemyEffectsIndicator].functions.Remove) then return false end
    end
    for _, definition in ipairs (frame.settings.unitFramesParts) do
        -- The native constructor eligibility gate already skips these rows.
        -- Their unused fields cannot execute a later bind or conversion hook.
        if (not NativeSkipsDefinition (definition, "part", frame)) then
            if (not DefinitionHasNoHooks (definition, "part", scope)) then return false end
            local descriptor = Enemy.unitFramesParts.types[definition.type]
            if (not descriptor or not CheckedTable (descriptor, Reuse._nativeTypes[descriptor], scope)) then return false end
            if (definition.data and definition.data.texture) then
                if (Enemy.UnitFramePart_GetTexture ~= Reuse._nativeHelpers.UnitFramePart_GetTexture
                    or getmetatable (Enemy.unitFramesParts.texturesByKeys) ~= nil
                    or not NoHooks (Enemy.UnitFramePart_GetTexture (definition.data.texture), 0, scope)) then return false end
            end
        end
    end
    for _, definition in ipairs (frame.settings.effectsIndicators) do
        if (not NativeSkipsDefinition (definition, "indicator", frame)
            and not DefinitionHasNoHooks (definition, "indicator", scope)) then return false end
    end
    return true
end

local function Destroy (record)
    if (windows[record.name] ~= record) then return end
    windows[record.name] = nil
    if (DoesWindowExist (record.name)) then DestroyWindow (record.name) end
end

local function DropUnused (scope)
    for _, record in pairs (scope.free) do Destroy (record) end
    ClearPrivateTable (scope.free)
end

function Reuse.Cancel (frame)
    local scope = scopes[frame]
    if (not scope) then return end
    scope.cancelled = true
    DropUnused (scope)
end

function Reuse.Check (frame)
    local scope = scopes[frame]
    if (scope and scope.cancelled) then error (cancelled) end
end

function Reuse.RegisterClass (class)
    Reuse._nativeClasses[class] = CaptureTable (class)
end

function Reuse.RegisterPartType (descriptor)
    Reuse._nativeTypes[descriptor] = CaptureTable (descriptor)
end

function Reuse.RegisterFilterTypes (types)
    for _, descriptor in pairs (types) do Reuse._nativeFilterTypes[descriptor] = CaptureTable (descriptor) end
end

function Reuse.RegisterHelpers ()
    for _, key in ipairs (helpers) do
        if (Enemy[key] and not Reuse._nativeHelpers[key]) then Reuse._nativeHelpers[key] = Enemy[key] end
    end
end

function Reuse.Capture ()
    Enemy.AddEventHandler ("UnitFrameWindowReuse", "Shutdown", function ()
        stopping = true
        spareScope = nil
        for frame in pairs (scopes) do Reuse.Cancel (frame) end
        windows = {}
    end)
end

function Reuse.BeforeConstruct (frame, definition, kind)
    local scope = scopes[frame]
    if (not scope) then return end
    if (scope.cancelled) then error (cancelled) end
    if (scope.uncached) then return end
    local valid = SafeDefinition (definition, kind, scope)
    scope.definition, scope.definitionSafe = definition, valid
    if (not valid) then Invalidate (scope) end
end

function Reuse.TextureIsPlain (part, texture)
    local owner = owners[part]
    local scope = owner and scopes[owner.frame]
    -- Fresh/extension paths do not need a reuse eligibility walk. Returning
    -- false also avoids probing descriptor fields with custom accessors early.
    if (not scope or scope.uncached) then return false end
    local valid = Plain (texture, 0, scope)
    if (valid) then owner.checkedTexture = texture else Invalidate (scope) end
    return valid
end

Reuse._constructionMethods = { TextureIsPlain = Reuse.TextureIsPlain }

function Reuse.Track (frame, object, kind, index, definition)
    local scope = scopes[frame]
    if (not scope or not index or type (object) ~= "table") then return end
    if (scope.cancelled) then error (cancelled) end
    local safe = not scope.uncached and scope.definition == definition and scope.definitionSafe == true
    local trusted = safe and Trusted (object, kind, scope)
    if (not trusted) then Invalidate (scope) end
    owners[object] = { frame = frame, kind = kind, index = index, definition = definition,
        trusted = trusted, scope = scope }
    scope.objects[#scope.objects + 1] = object
end

-- Return construction provenance, never cached validation of mutable data.
-- The definition survives only a fully reusable completed native transaction.
-- Callers still validate current classes, helpers and data before retaining.
function Reuse.GetConstructionSource (frame, object, kind)
    if (type (frame) ~= "table" or type (object) ~= "table") then return end
    local owner = owners[object]
    if (not owner or owner.frame ~= frame or owner.kind ~= kind or not owner.trusted
        or owner.scope or scopes[frame] or owner.definition == nil
        or rawget (object, "_frame") ~= frame) then return end
    local settings = rawget (frame, "settings")
    if (type (settings) ~= "table" or getmetatable (settings) ~= nil) then return end
    local definitions
    local name, altName
    if (kind == "part") then
        definitions = rawget (settings, "unitFramesParts")
        local state = rawget (object, "_t")
        if (type (state) ~= "table" or getmetatable (state) ~= nil) then return end
        name, altName = rawget (state, "windowName"), rawget (state, "altIconWindowName")
    elseif (kind == "indicator") then
        definitions = rawget (settings, "effectsIndicators")
        name = rawget (object, "windowName")
    else return end
    if (type (definitions) ~= "table" or getmetatable (definitions) ~= nil
        or type (owner.index) ~= "number" or rawget (definitions, owner.index) ~= owner.definition
        or name ~= owner.windowName or altName ~= owner.altWindowName) then return end
    local record = name and windows[name]
    if (not record or record.object ~= object or record.frame ~= frame or not record.reusable
        or record.parent ~= rawget (frame, "windowName") or not DoesWindowExist (name)) then return end
    if (altName) then
        record = windows[altName]
        if (not record or record.object ~= object or record.frame ~= frame or not record.reusable
            or record.parent ~= rawget (frame, "windowName") or not DoesWindowExist (altName)) then return end
    end
    return owner.index, owner.definition
end

Reuse._constructionMethods.GetConstructionSource = Reuse.GetConstructionSource

function Reuse.Acquire (object, template, parent, requestedName, texture, allowReuse, slot)
    local owner = owners[object]
    local scope = owner and scopes[owner.frame]
    if (not scope or owner.scope ~= scope) then
        CreateWindowFromTemplate (requestedName, template, parent)
        return requestedName, false
    end
    if (scope.cancelled or scope.parent ~= parent) then error (cancelled) end
    local coldCareer = scope.coldCareer and owner.kind == "part" and object.type == "careerIcon"
    local reusable = not scope.uncached and owner.trusted
        and (allowReuse ~= false or (coldCareer and scope.recordColdCareer))
        and (not texture or owner.checkedTexture == texture or Plain (texture, 0, scope))
    owner.checkedTexture = nil
    if (not reusable) then scope.hasNonReusable = true end
    slot = slot or "root"
    local key = owner.kind..":"..owner.index..":"..(owner.kind == "part" and object.type or "effect")..":"..slot..":"..template
    local old = scope.free[key]
    -- Cold career windows are always fresh. Remember clean ownership only for
    -- a later transaction; do not predict a conditional first-render write.
    local reused = not coldCareer and reusable and old and old.reusable and old.parent == parent
        and (allowReuse ~= "empty" or not old.hasTexture) and DoesWindowExist (old.name)
    if (old) then scope.free[key] = nil end
    local name = requestedName
    if (reused) then name = old.name end
    if (not reused and old) then Destroy (old) end
    local record = reused and old or { name = name, parent = parent, frame = owner.frame,
        key = key, slot = slot, reusable = reusable }
    record.object = object
    -- Register in-flight ownership before native reset/create can throw or reenter.
    windows[name] = record
    if (slot == "alt") then owner.altWindowName = name else owner.windowName = name end
    scope.created[#scope.created + 1] = record
    if (reused) then
        -- Indicator Update and AltSpec layout already clear their own anchors.
        if (owner.kind == "part" and slot == "root") then WindowClearAnchors (name) end
        if (scope.cancelled) then Destroy (record); error (cancelled) end
        if (template == "EA_Label_DefaultText") then LabelSetText (name, L"") end
        if (template == "EnemyDynamicImageTemplate" or template == "EnemyCircleImageTemplate") then
            LabelSetText (name.."TLabel", L"")
        end
    else
        CreateWindowFromTemplate (name, template, parent)
    end
    if (scope.cancelled) then
        Destroy (record)
        error (cancelled)
    end
    return name, reused == true
end

function Reuse.Release (object, name, showing)
    local record = windows[name]
    if (record and record.object == object) then
        local scope = scopes[record.frame]
        if (scope and not scope.cancelled and not scope.uncached and record.reusable and Trusted (object, owners[object].kind, scope)
            and DoesWindowExist (name))
        then
            if (object.type == "careerIcon") then
                record.hasTexture = object._t[record.slot == "alt" and "altTextureWritten" or "careerTextureWritten"] == true
            end
            if (showing ~= false) then WindowSetShowing (name, false) end
            if (scope.cancelled or windows[name] ~= record) then return end
            if (scope.free[record.key]) then Destroy (scope.free[record.key]) end
            scope.free[record.key] = record
            return
        end
        Destroy (record)
    elseif (DoesWindowExist (name)) then
        DestroyWindow (name)
    end
end

-- Extensions can replace Remove without calling our release helper. They keep
-- their normal native lifecycle, but must not leave a strong Lua owner here.
local function ForgetOwner (object)
    local owner = owners[object]
    local record = owner and owner.windowName and windows[owner.windowName]
    if (record and record.object == object) then windows[record.name] = nil end
    record = owner and owner.altWindowName and windows[owner.altWindowName]
    if (record and record.object == object) then windows[record.name] = nil end
end

local function ForgetOwners (objects)
    for _, object in ipairs (objects) do ForgetOwner (object) end
end

function Reuse.BeforeRemove (object, kind, frame)
    local class = kind == "part" and EnemyUnitFramePart or EnemyEffectsIndicator
    local original = Reuse._nativeClasses[class]
    local custom = not original or object.Remove ~= original.functions.Remove
    if (kind == "part") then
        local descriptor = object._type
        local nativeType = descriptor and Reuse._nativeTypes[descriptor]
        custom = custom or not nativeType or descriptor.OnRemove ~= nativeType.functions.OnRemove
            or Enemy.UnitFramePart_OnRemove ~= Reuse._nativeHelpers.UnitFramePart_OnRemove
    end
    if (custom) then
        local owner = owners[object]
        Invalidate (scopes[frame] or (owner and scopes[owner.frame]))
        ForgetOwner (object)
    end
end

function Reuse.GetPlayer (object)
    local owner = owners[object]
    local scope = owner and scopes[owner.frame]
    return scope and scope.careerSafe and scope.player
end

function Reuse.CanKeepSettings (frame)
    if (stopping or scopes[frame] or not frame.windowName) then return false end
    local check = { checked = {} }
    if (not TrustedClass (frame, EnemyUnitFrame, check)) then return false end
    for _, part in ipairs (frame.parts) do if (not Trusted (part, "part", check)) then return false end end
    for _, indicator in ipairs (frame.effectsIndicators) do if (not Trusted (indicator, "indicator", check)) then return false end end
    return true
end

function Reuse.CanRefreshSettings (frames)
    -- Public lifecycle overrides keep the original settings-call sequence and
    -- argument shape. Only the native path may skip its destructive preparation.
    if (Enemy.UnitFrames_OnGroupsUpdated ~= Reuse._nativeHelpers.UnitFrames_OnGroupsUpdated
        or Enemy._UnitFramesDisableAll ~= Reuse._nativeHelpers._UnitFramesDisableAll) then return false end
    local check = { checked = {} }
    for _, group in ipairs (frames) do
        for _, frame in ipairs (group) do
            if (not TrustedClass (frame, EnemyUnitFrame, check)) then return false end
        end
    end
    return true
end

local function RebuildChecked (frame, scope, callback, player)
    scope.coldCareer = not HasTransferableCareerWindows (frame)
    -- Click callbacks and outer settings reads have no just-in-time boundary
    -- of their own, so reject their hooks before either warm or cold binding.
    if (not ClickBindingsSafe (frame, scope)) then Invalidate (scope) end
    if (scope.coldCareer) then
        scope.recordColdCareer = CareerResolversNative ()
    else
        scope.careerSafe = not scope.uncached and CareerBindingsSafe (frame, scope)
    end
    callback (frame, player)
end

function Reuse.Run (frame, callback, player)
    local previous = scopes[frame]
    if (previous) then
        Reuse.Cancel (frame)
        scopes[frame] = nil
        local ok, result = pcall (callback, frame, player)
        scopes[frame] = previous
        if (not ok) then error (result) end
        return true
    end
    if (stopping) then return false end
    if (not DoesWindowExist (frame.windowName)) then return false end
    if (not TrustedClass (frame, EnemyUnitFrame)
        or not UnchangedTable (EnemyUnitFramePart, Reuse._nativeClasses[EnemyUnitFramePart])
        or not UnchangedTable (EnemyEffectsIndicator, Reuse._nativeClasses[EnemyEffectsIndicator])
        or not UnchangedTable (EnemyEffectFilter, Reuse._nativeClasses[EnemyEffectFilter]))
    then
        ForgetOwners (frame.parts)
        ForgetOwners (frame.effectsIndicators)
        callback (frame, player)
        return true
    end
    local oldParts, oldIndicators = frame.parts, frame.effectsIndicators
    -- The four class tables were validated above, with no intervening callback.
    -- Invalidate discards this seed before any unknown lifecycle code proceeds.
    local scope = AcquireScope (frame.windowName, player)
    scopes[frame] = scope
    local ok, result = pcall (RebuildChecked, frame, scope, callback, player)
    if (not ok or scope.cancelled) then
        scope.cancelled = true
        for _, object in ipairs (scope.objects) do
            local ownsWindow = false
            for _, record in ipairs (scope.created) do
                if (record.object == object and windows[record.name] == record) then ownsWindow = true; break end
            end
            if (ownsWindow and object.Remove) then pcall (object.Remove, object) end
        end
        for _, record in ipairs (scope.created) do Destroy (record) end
    end
    DropUnused (scope)
    if (scope.uncached or scope.cancelled or not ok) then
        ForgetOwners (oldParts)
        ForgetOwners (oldIndicators)
    end
    if (scope.hasNonReusable) then
        for _, record in ipairs (scope.created) do
            if (not record.reusable and windows[record.name] == record) then windows[record.name] = nil end
        end
    end
    scopes[frame] = nil
    local stockBuild = ok and not scope.cancelled and not scope.uncached and not scope.hasNonReusable
    for _, object in ipairs (scope.objects) do
        local owner = owners[object]
        if (owner and owner.scope == scope) then
            owner.scope = nil
            if (not stockBuild) then owner.definition = nil end
        end
    end
    if (not ok and result ~= cancelled) then
        frame.forcePlayerChanged = true
        RecycleScope (scope)
        error (result)
    end
    local wasCancelled = scope.cancelled
    if (wasCancelled) then frame.forcePlayerChanged = true end
    RecycleScope (scope)
    -- The second result is construction provenance for optional Lua-object
    -- retention. A callback restored after it ran is still not a stock build.
    return ok and not wasCancelled, stockBuild
end

function Reuse.GetPendingCount ()
    local scopesCount, freeCount = 0, 0
    for _, scope in pairs (scopes) do
        scopesCount = scopesCount + 1
        for _ in pairs (scope.free) do freeCount = freeCount + 1 end
    end
    return scopesCount, freeCount
end

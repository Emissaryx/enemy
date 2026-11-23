-- Immutable validation metadata is shared; live components remain frame-owned.
-- Receive UnitFrame's captured helpers so globals replaced during loading do
-- not change which helpers its retention path uses. Install only once.
-- Unused arguments preserve the compatible callback signatures.
-- luacheck: ignore 212/frame 212/player
function Enemy._InitializeUnitFrameObjectRetention (Enemy, pairs, ipairs, type, tonumber, InterfaceCore)
    Enemy._InitializeUnitFrameObjectRetention = nil
    local R = { enabled = true, stats = { trials = 0, retained = 0, primed = 0, fallback = 0, refreshed = 0,
        preparedNodes = 0, validationNodes = 0, validationFields = 0,
        sourcePreparedNodes = 0, sourceCacheBuilds = 0, sourceCacheHits = 0, sourceBorrowedNodes = 0 } }
    Enemy.UnitFrameObjectRetention = R
    local nativeNumber, nativeText = tonumber, tostring
    local nativeScale = InterfaceCore.GetScale
    local nativeUi = {
        WindowSetShowing = WindowSetShowing, WindowSetDimensions = WindowSetDimensions,
        WindowSetScale = WindowSetScale, WindowSetLayer = WindowSetLayer,
        WindowClearAnchors = WindowClearAnchors, WindowAddAnchor = WindowAddAnchor,
        LabelSetText = LabelSetText, DynamicImageSetTexture = DynamicImageSetTexture,
        DynamicImageSetTextureDimensions = DynamicImageSetTextureDimensions,
    }
    local partIgnore = { _t = true, _frame = true, _boundingBoxWindowName = true }
    local indicatorIgnore = { _frame = true, windowName = true, _isShowing = true,
        _lastTimerValue = true, _timerLabelAllowed = true, ticked = true,
        _timedPlayer = true, _boundingBoxWindowName = true }
    local clickIgnore = { frame = true }
    local classes
    local sourceKeys = { "unitFramesParts", "effectsIndicators", "clickCastings", "unitFramesScale",
        "unitFramesSize", "unitFramesLayer", "unitFramesTestMode", "unitFramesDisableAltSpecCheck",
        "unitFramesDisableAltSpecCheckForRunePriestZealot" }

    -- A flat, shallow expected-value map for each reachable table. Every
    -- validation walks actual keys once, so added/deleted keys and nested
    -- replacements are detected without recursion or transient snapshots.
    local function Prepare (plan, value, functions, leaves, ignored, class, depth)
        if (type (value) ~= "table" or depth > 20 or getmetatable (value) ~= class) then return false end
        if (plan.seen[value] or (plan.sharedSeen and plan.sharedSeen[value])) then return true end
        plan.seen[value] = true
        -- Private compact node: source, expected fields, field count, class, ignored keys.
        local node = { value, {}, 0, class, ignored }
        plan[#plan + 1] = node
        R.stats.preparedNodes = R.stats.preparedNodes + 1
        for key, item in pairs (value) do
            if (not ignored or not ignored[key]) then
                if (type (key) ~= "string" and type (key) ~= "number") then return false end
                local kind = type (item)
                if (kind == "userdata" or kind == "thread" or (kind == "function" and not functions)) then return false end
                node[2][key], node[3] = item, node[3] + 1
                plan.fields = (plan.fields or 0) + 1
                if (kind == "table" and not (leaves and leaves[item])
                    and not Prepare (plan, item, functions, leaves, nil, nil, depth + 1)) then return false end
            end
        end
        return true
    end

    local function Validate (plan)
        R.stats.validationNodes = R.stats.validationNodes + #plan
        R.stats.validationFields = R.stats.validationFields + plan.fields
        for index = 1, #plan do
            local node = plan[index]
            local value, expected, ignored = node[1], node[2], node[5]
            if (getmetatable (value) ~= node[4]) then return false end
            local count = 0
            if (ignored) then
                for key, item in pairs (value) do
                    if (not ignored[key]) then
                        if (expected[key] ~= item) then return false end
                        count = count + 1
                    end
                end
            else
                for key, item in pairs (value) do
                    if (expected[key] ~= item) then return false end
                    count = count + 1
                end
            end
            if (count ~= node[3]) then return false end
        end
        return true
    end

    -- One weak value cannot keep settings/frame graphs alive by itself. A
    -- successful frame token owns its immutable cache version until that token
    -- is discarded. Changed sources create a new version, never edit old nodes.
    local sourceCache = setmetatable ({}, { __mode = "v" })
    local function SourcePlan (frame)
        local entry = sourceCache[1]
        if (entry and entry.sorted == frame.sortedUnitFramesParts) then
            local sameRoots = true
            for _, key in ipairs (sourceKeys) do
                if (entry.source[key] ~= rawget (frame.settings, key)) then sameRoots = false; break end
            end
            -- This is fresh validation on every reuse, not cached success.
            if (sameRoots and Validate (entry.plan)) then
                R.stats.sourceCacheHits = R.stats.sourceCacheHits + 1
                return entry
            end
        end
        entry = { source = {}, sorted = frame.sortedUnitFramesParts, plan = { seen = {}, fields = 0 } }
        local before = R.stats.preparedNodes
        for _, key in ipairs (sourceKeys) do
            local value = rawget (frame.settings, key)
            entry.source[key] = value
            if (type (value) == "table") then
                if (not Prepare (entry.plan, value, false, nil, nil, nil, 0)) then return end
            elseif (type (value) == "function" or type (value) == "userdata" or type (value) == "thread") then return end
        end
        if (not Prepare (entry.plan, entry.sorted, false, nil, nil, nil, 0)) then return end
        entry.seen, entry.plan.seen = entry.plan.seen, nil
        R.stats.sourcePreparedNodes = R.stats.sourcePreparedNodes + R.stats.preparedNodes - before
        R.stats.sourceCacheBuilds = R.stats.sourceCacheBuilds + 1
        sourceCache[1] = entry
        return entry
    end

    local function NativeTable (value, captured)
        if (type (value) ~= "table" or not captured or getmetatable (value) ~= nil) then return false end
        local keys, functions, count = captured.keys, captured.functions, 0
        for key, item in pairs (value) do
            local fn = functions[key]
            if (fn) then
                if (item ~= fn) then return false end
                count = count + 1
            elseif (not keys[key]) then return false end
        end
        return count == captured.functionCount
    end

    local function NativeObject (object, class, skipMatcher)
        local captured = Enemy.UnitFrameWindowReuse._nativeClasses[class]
        if (getmetatable (object) ~= class or class.__index ~= class) then return false end
        local keys, functions = captured.methodKeys, captured.functions
        for index = 1, #keys do
            local key = keys[index]
            if ((not skipMatcher or key ~= "IsMatch") and object[key] ~= functions[key]) then return false end
        end
        return true
    end

    local function Trust (frame, token)
        local reuse = Enemy.UnitFrameWindowReuse
        if (classes and (classes[1] ~= EnemyUnitFrame or classes[2] ~= EnemyUnitFramePart
            or classes[3] ~= EnemyEffectsIndicator or classes[4] ~= EnemyEffectFilter
            or classes[5] ~= EnemyClickCasting)) then return false end
        local settings = rawget (frame, "settings")
        if (not R.enabled or not reuse or frame._updatingEffects or type (settings) ~= "table"
            or getmetatable (settings) ~= nil or settings.unitFramesTestMode or InterfaceCore.GetScale ~= nativeScale
            or _G.tonumber ~= nativeNumber or _G.tostring ~= nativeText
            or GetIconData ~= reuse._careerGetIconData or type (Icons) ~= "table"
            or getmetatable (Icons) ~= nil or rawget (Icons, "GetCareerIconIDFromCareerLine") ~= reuse._careerGetCareerIcon)
        then return false end
        for key, fn in pairs (nativeUi) do if (_G[key] ~= fn) then return false end end
        for key, fn in pairs (reuse._nativeHelpers) do if (Enemy[key] ~= fn) then return false end end
        classes = classes or { EnemyUnitFrame, EnemyUnitFramePart, EnemyEffectsIndicator, EnemyEffectFilter, EnemyClickCasting }
        for index = 1, #classes do
            local class = classes[index]
            if (not NativeTable (class, reuse._nativeClasses[class]) or class.__index ~= class) then return false end
        end
        if (not NativeObject (frame, EnemyUnitFrame)
            or getmetatable (Enemy.groups) ~= nil or getmetatable (Enemy.careerArchetypes) ~= nil) then return false end
        local registry = Enemy.unitFramesParts.texturesByKeys
        local partTypes, filterTypes, icons = Enemy.unitFramesParts.types, Enemy.EffectFilterTypes, Enemy.EffectsIndicatorIcons
        if (getmetatable (registry) ~= nil or type (partTypes) ~= "table" or getmetatable (partTypes) ~= nil
            or type (filterTypes) ~= "table" or getmetatable (filterTypes) ~= nil
            or type (icons) ~= "table" or getmetatable (icons) ~= nil) then return false end
        if (token) then
            for key, descriptor in pairs (token.types) do
                if (descriptor.key ~= key or rawget (partTypes, key) ~= descriptor
                    or not NativeTable (descriptor, reuse._nativeTypes[descriptor])) then return false end
            end
            for key, descriptor in pairs (token.filterTypes) do
                if (rawget (filterTypes, key) ~= descriptor
                    or not NativeTable (descriptor, reuse._nativeFilterTypes[descriptor])) then return false end
            end
            for key, texture in pairs (token.textures) do
                if ((rawget (registry, key) or false) ~= texture) then return false end
            end
            for key, icon in pairs (token.icons) do
                if ((rawget (icons, key) or false) ~= icon) then return false end
            end
            for _, row in ipairs (token.parts) do if (row.object._frame ~= frame) then return false end end
            for _, row in ipairs (token.indicators) do if (row.object._frame ~= frame) then return false end end
            for _, row in ipairs (token.clicks) do if (row.object.frame ~= frame) then return false end end
            return true
        end
        for _, part in ipairs (frame.parts) do
            if (not NativeObject (part, EnemyUnitFramePart) or part._frame ~= frame
                or not NativeTable (part._type, reuse._nativeTypes[part._type])
                or part._type.key ~= part.type or rawget (partTypes, part.type) ~= part._type) then return false end
            local key = part.data and part.data.texture
            local texture = key and rawget (registry, key)
            if (texture and getmetatable (texture) ~= nil) then return false end
        end
        for _, indicator in ipairs (frame.effectsIndicators) do
            if (not NativeObject (indicator, EnemyEffectsIndicator) or indicator._frame ~= frame
                or indicator._checkDispell ~= indicator._windowReuseCheckDispell) then return false end
            for _, filter in ipairs (indicator.effectFilters) do
                if (not NativeObject (filter, EnemyEffectFilter, true) or filter.IsMatch ~= filter._windowReuseMatcher) then return false end
                if (filter.type and (rawget (filterTypes, filter.type) ~= filter._enemyFilterTypeData
                    or not NativeTable (filter._enemyFilterTypeData, reuse._nativeFilterTypes[filter._enemyFilterTypeData]))) then return false end
            end
        end
        for _, click in ipairs (frame.clickCastings) do
            if (not NativeObject (click, EnemyClickCasting) or click.frame ~= frame) then return false end
        end
        return true
    end

    function R.CanPrime (frame, player)
        return R.enabled and type (player) == "table" and type (rawget (player, "career")) == "number"
            and type (rawget (player, "isSelf")) == "boolean" and type (rawget (player, "isInPlayerGroup")) == "boolean"
    end

    local function RecordObjects (plan, objects, output, leaves, ignored, class)
        for index, object in ipairs (objects) do
            if (not Prepare (plan, object, true, leaves, ignored, class, 0)) then return false end
            output[index] = { object = object }
        end
        return true
    end

    function R.Prime (frame, player)
        if (not Trust (frame)) then return end
        local reuse = Enemy.UnitFrameWindowReuse
        local getSource = reuse.GetConstructionSource
        if (type (getSource) ~= "function" or not reuse._constructionMethods
            or getSource ~= reuse._constructionMethods.GetConstructionSource) then return end
        local token = { source = {}, plan = { seen = {} }, parts = {}, indicators = {}, clicks = {}, types = {}, textures = {}, filterTypes = {}, icons = {},
            archetype = Enemy.careerArchetypes[player.career], isSelf = player.isSelf,
            inGroup = player.isInPlayerGroup, cleanse = Enemy.groups.canCleanse,
            groupType = Enemy.groups.groupType, globalScale = InterfaceCore.GetScale (),
            sorted = frame.sortedUnitFramesParts, settings = frame.settings }
        local shared = SourcePlan (frame)
        if (not shared) then return end
        token.sourcePlan = shared
        token.plan.sharedSeen = shared.seen
        token.plan.fields = shared.plan.fields
        for _, key in ipairs (sourceKeys) do token.source[key] = shared.source[key] end
        for index = 1, #shared.plan do token.plan[index] = shared.plan[index] end
        R.stats.sourceBorrowedNodes = R.stats.sourceBorrowedNodes + #shared.plan
        local leaves = {}
        for _, part in ipairs (frame.parts) do
            token.types[part.type] = part._type
            leaves[part._type] = true
            local key = part.data.texture
            local texture = key and Enemy.unitFramesParts.texturesByKeys[key]
            if (key) then token.textures[key] = texture or false end
            if (texture and not Prepare (token.plan, texture, false, nil, nil, nil, 0)) then return end
        end
        for _, indicator in ipairs (frame.effectsIndicators) do
            if (indicator.icon ~= nil) then
                local icon = rawget (Enemy.EffectsIndicatorIcons, indicator.icon)
                token.icons[indicator.icon] = icon or false
                if (icon and not Prepare (token.plan, icon, false, nil, nil, nil, 0)) then return end
            end
            for _, filter in ipairs (indicator.effectFilters) do
                leaves[filter] = true
                if (filter.type) then token.filterTypes[filter.type] = filter._enemyFilterTypeData end
            end
        end
        if (not RecordObjects (token.plan, frame.parts, token.parts, leaves, partIgnore, EnemyUnitFramePart)
            or not RecordObjects (token.plan, frame.effectsIndicators, token.indicators, leaves, indicatorIgnore, EnemyEffectsIndicator)
            or not RecordObjects (token.plan, frame.clickCastings, token.clicks, leaves, clickIgnore, EnemyClickCasting)) then return end
        for _, indicator in ipairs (frame.effectsIndicators) do
            for _, filter in ipairs (indicator.effectFilters) do
                if (not Prepare (token.plan, filter, true, nil, nil, EnemyEffectFilter, 0)) then return end
            end
        end
        for _, row in ipairs (token.parts) do
            row.index, row.definition = getSource (frame, row.object, "part")
            if (row.index == nil) then return end
        end
        for _, row in ipairs (token.indicators) do
            row.index, row.definition = getSource (frame, row.object, "indicator")
            if (row.index == nil) then return end
        end
        token.plan.seen, token.plan.sharedSeen = nil, nil
        frame._retainedObjects = token
        R.stats.primed = R.stats.primed + 1
    end

    function R.CanRetain (frame, player)
        if (not R.enabled) then return false end
        R.stats.trials = R.stats.trials + 1
        local token = frame._retainedObjects
        if (not token or not R.CanPrime (frame, player) or not Trust (frame, token)
            or EnemyEffectsIndicator.IsSweepRunning () or token.settings ~= frame.settings
            or token.sorted ~= frame.sortedUnitFramesParts or token.archetype ~= Enemy.careerArchetypes[player.career]
            or token.isSelf ~= player.isSelf or token.inGroup ~= player.isInPlayerGroup
            or token.cleanse ~= Enemy.groups.canCleanse or token.groupType ~= Enemy.groups.groupType
            or token.globalScale ~= InterfaceCore.GetScale ()) then
            R.stats.fallback = R.stats.fallback + 1
            return false
        end
        for _, key in ipairs (sourceKeys) do
            if (token.source[key] ~= rawget (frame.settings, key)) then return false end
        end
        if (#frame.parts ~= #token.parts or #frame.effectsIndicators ~= #token.indicators
            or #frame.clickCastings ~= #token.clicks) then return false end
        for index, row in ipairs (token.parts) do if (frame.parts[index] ~= row.object) then return false end end
        for index, row in ipairs (token.indicators) do if (frame.effectsIndicators[index] ~= row.object) then return false end end
        for index, row in ipairs (token.clicks) do if (frame.clickCastings[index] ~= row.object) then return false end end
        return Validate (token.plan)
    end

    local function BindRetainedPart (frame, row, reuse)
        local part = row.object
        part._t = {}
        reuse.BeforeConstruct (frame, row.definition, "part")
        reuse.Track (frame, part, "part", row.index, row.definition)
        part:Bind (frame)
        reuse.Check (frame)
    end

    function R.Refresh (frame, player)
        -- The client assert returns nothing; the caller already validated reuse.
        local token, reuse = frame._retainedObjects, Enemy.UnitFrameWindowReuse
        for _, row in ipairs (token.parts) do
            reuse.BeforeRemove (row.object, "part", frame)
            row.object:Remove ()
            reuse.Check (frame)
        end
        for _, row in ipairs (token.parts) do
            BindRetainedPart (frame, row, reuse)
        end
        for _, row in ipairs (token.indicators) do
            reuse.BeforeRemove (row.object, "indicator", frame)
            row.object:Remove ()
            reuse.Check (frame)
        end
        for _, row in ipairs (token.indicators) do
            reuse.BeforeConstruct (frame, row.definition, "indicator")
            reuse.Track (frame, row.object, "indicator", row.index, row.definition)
            row.object:Update (frame)
            reuse.Check (frame)
        end
        frame:_RefreshPopupPartLayers ()
        for _, click in ipairs (frame.clickCastings) do click:Remove (); click:Update (frame); reuse.Check (frame) end
        R.stats.refreshed = R.stats.refreshed + 1
    end

    function R.Rebind (frame, player)
        local token = frame._retainedObjects
        for index, part in ipairs (frame.parts) do
            local t, row = part._t, token.parts[index]
            row.wasShowing, row.wasAlt = t._isShowing, t.cache and t.cache.altIconShowing
            row.forceOrder = false
            if (part.type == "hpacbar" and t.cache.playerName ~= player.name) then
                -- The native writer keys its color gate on career/signatures,
                -- not on the changed name used to resolve per-player roles.
                t.cache.career = nil
            elseif (part.type == "careerIcon" and t.altTextureWritten) then
                -- A previously textured spec child cannot be reset to its
                -- template texture through a public blank-texture API. Use
                -- the stock pair binding/transfer policy, which recreates an
                -- absent-spec child while retaining the main root when safe.
                local reuse = Enemy.UnitFrameWindowReuse
                reuse.BeforeRemove (part, "part", frame)
                part:Remove ()
                reuse.Check (frame)
                BindRetainedPart (frame, row, reuse)
                row.forceOrder = true
            elseif (part.type == "careerIcon" and t._isShowing ~= true) then
                -- Preserve the fresh template's pre-state showing observation.
                WindowSetShowing (t.windowName, true)
                t._isShowing, t.cache.state = nil, nil
                row.forceOrder = true
            end
        end
        -- Current fresh rebuilds hide effects until their next normal event.
        -- This also unregisters timed ownership and clears the old countdown.
        for _, indicator in ipairs (frame.effectsIndicators) do
            indicator:EffectsUpdated (nil, false)
        end
        for _, click in ipairs (frame.clickCastings) do click:Remove (); click:Update (frame) end
        R.stats.retained = R.stats.retained + 1
    end

    function R.Finish (frame)
        local token, restack = frame._retainedObjects, false
        for index, part in ipairs (frame.parts) do
            local t, row = part._t, token.parts[index]
            if (row.forceOrder or (row.wasShowing ~= true and t._isShowing == true)
                or (row.wasAlt ~= true and t.cache and t.cache.altIconShowing == true)) then restack = true end
        end
        if (restack) then
            -- Reproduce fresh binding/show ordering only when visibility
            -- transitions could have raised a retained sibling. Keep caches
            -- and content; the normal no-transition swap does none of this.
            for _, part in ipairs (frame.parts) do
                local t = part._t
                WindowSetShowing (t.windowName, true)
                if (t.altIconWindowName) then WindowSetShowing (t.altIconWindowName, false) end
                if (part._type.OnLayerRefresh) then part._type.OnLayerRefresh (part)
                else WindowSetLayer (t.windowName, part.data.layer) end
            end
            for _, part in ipairs (frame.parts) do
                local t = part._t
                if (t.altIconWindowName) then
                    WindowSetShowing (t.altIconWindowName, t.cache.altIconShowing)
                    WindowSetShowing (t.windowName, t._isShowing)
                    if (t._isShowing and t.cache.altIconShowing and t.cache.careerIconLayer == t.cache.altIconLayer) then
                        WindowSetLayer (t.altIconWindowName, t.cache.altIconLayer)
                    end
                else
                    WindowSetShowing (t.windowName, t._isShowing)
                end
            end
        end
    end
end

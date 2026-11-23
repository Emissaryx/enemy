local Enemy = Enemy
local g
local tostring = tostring
local string_lower = string.lower
local type = type
local scaleReader, scaleWriter = WindowGetScale, WindowSetScale

local properties =
{
}

local function ToNameString (name)
	if (not name) then return nil end

	if (Enemy and Enemy.FixString) then
		name = Enemy.FixString (name)
	end

	if (type (name) ~= "string" and WStringToString) then
		name = WStringToString (name)
	end

	if (type (name) ~= "string") then
		name = tostring (name)
	end

	return name
end

local function NormalizeNameKey (name)
	local asString = ToNameString (name)
	if (not asString) then return nil end
	return string_lower (asString)
end

local function RaiseIconLayer (windowName, layer)
    -- An equal-layer assignment need not change native sibling order.
    WindowSetLayer (windowName, layer == Window.Layers.POPUP and Window.Layers.OVERLAY or Window.Layers.POPUP)
    WindowSetLayer (windowName, layer)
end

local function SyncAltIconLayers (part, force)
    local t = part._t
    local cache = t.cache
    local careerLayer = part.data.layer
    local altLayer = math.max (careerLayer, Window.Layers.OVERLAY)
    local careerChanged = force or cache.careerIconLayer ~= careerLayer

    if (careerChanged)
    then
        if (force) then RaiseIconLayer (t.windowName, careerLayer)
        else WindowSetLayer (t.windowName, careerLayer) end
        cache.careerIconLayer = careerLayer
    end
    if (force or cache.altIconLayer ~= altLayer or (careerChanged and careerLayer == altLayer))
    then
        if (force or (careerChanged and careerLayer == altLayer)) then RaiseIconLayer (t.altIconWindowName, altLayer)
        else WindowSetLayer (t.altIconWindowName, altLayer) end
        cache.altIconLayer = altLayer
    end
end

local function SyncAltIconLayout (part, contentOnly)
	local t = part._t
	local data = part.data

	if (not t or not data or not t.altIconWindowName or not t.windowName) then
		return
	end

	local cache = t.cache or {}
    SyncAltIconLayers (part)

	if (not cache.altIconAnchored) then
		WindowClearAnchors (t.altIconWindowName)
		WindowAddAnchor (t.altIconWindowName, "center", t.windowName, "center", 0, 0)
		cache.altIconAnchored = true
	end

	local width = data.size and data.size[1] or 0
	local height = data.size and data.size[2] or 0
	if (cache.altIconWidth ~= width or cache.altIconHeight ~= height) then
		cache.altIconWidth = width
		cache.altIconHeight = height
		WindowSetDimensions (t.altIconWindowName, width, height)
		DynamicImageSetTextureDimensions (t.altIconWindowName, width, height)
	end

    -- Scoreboard packets change icon content, not owned window geometry. A bind
    -- or ordinary part update reads native scale; a replaced root is unknown.
    if (not contentOnly or WindowGetScale ~= scaleReader or WindowSetScale ~= scaleWriter
        or cache.altIconScaleWindow ~= t.windowName) then
        local scale = WindowGetScale (t.windowName) or 1
        if (cache.altIconScale ~= scale) then
            cache.altIconScale = scale
            WindowSetScale (t.altIconWindowName, scale)
        end
        cache.altIconScaleWindow = t.windowName
    end

	t.cache = cache
end


-- This cache owns only Enemy's writes to the AltSpec child visibility.
-- Arbitrary external child-window mutation is unsupported and is not polled
-- for repair.
local function ResolveAltSpecIcon (part, player)
	local t = part._t
	local cache = t.cache

	local altSpecIcon = nil
	local map = Enemy.unitFrames and Enemy.unitFrames.altSpecIconByKey

	if (map and player.name)
	then
		if (cache.altSpecCareer ~= player.career)
		then
			cache.altSpecCareer = player.career
			cache.altSpecIgnored = Enemy.UnitFramesShouldIgnoreAltSpecForCareer and Enemy.UnitFramesShouldIgnoreAltSpecForCareer (player.career)
		end

		if (not cache.altSpecIgnored)
		then
			if (cache.altSpecName ~= player.name)
			then
				cache.altSpecName = player.name
				cache.altSpecNameKey = NormalizeNameKey (player.name)
			end

			local key = cache.altSpecNameKey
			if (key) then altSpecIcon = map[key] end
		end
	end

    return altSpecIcon
end

local function UpdateAltSpecIcon (part, player, contentOnly)
    local t = part._t
    local cache = t.cache
    local altSpecIcon = ResolveAltSpecIcon (part, player)

	if (altSpecIcon ~= cache.altSpecIcon)
	then
		cache.altSpecIcon = altSpecIcon

		if (cache.altSpecIcon and t.altIconWindowName)
		then
			local tex, tex_x, tex_y = GetIconData (cache.altSpecIcon)
			if (tex) then
				DynamicImageSetTexture (t.altIconWindowName, tex, tex_x, tex_y)
                t.altTextureWritten = true
			else
				cache.altSpecIcon = nil
			end
		end
	end

	if (t.altIconWindowName) then
        SyncAltIconLayout (part, contentOnly)
		local showAlt = (cache.altSpecIcon ~= nil) and WindowGetShowing (t.windowName)
		if (cache.altIconShowing ~= showAlt)
		then
			cache.altIconShowing = showAlt
			WindowSetShowing (t.altIconWindowName, showAlt)
		end
	end
end


function Enemy.UnitFramesParts_CareerIconInitialize ()
	g = Enemy.unitFramesParts

	g.types["careerIcon"] =
	{
		key = "careerIcon",
		name = L"Career icon",
		properties = properties,

		CreateConfigurationWindow = function (wn, root)
			Enemy.CreateConfigurationWindow (wn, root, properties, Enemy.UnitFramesUI_UnitFramePartDialog_UpdateExample)
		end,

		LoadConfigurationWindow = function (wn, part)
			Enemy.ConfigurationWindowLoadData (wn, part.data)
		end,

		SaveConfigurationWindow = function (wn, part)
			Enemy.ConfigurationWindowSaveData (wn, part.data)
		end,

		OnRemove = function (part)
			local t = part._t
            if (t and t.altIconWindowName) then
                if (Enemy.UnitFrameWindowReuse) then
                    Enemy.UnitFrameWindowReuse.Release (part, t.altIconWindowName, t.cache and t.cache.altIconShowing)
                elseif (DoesWindowExist (t.altIconWindowName)) then
                    DestroyWindow (t.altIconWindowName)
                end
                t.altIconWindowName = nil
            end
			Enemy.UnitFramePart_OnRemove (part)
		end,

		OnBind = function (part)

			local t = part._t

			t.cache = {}

            local player = Enemy.UnitFrameWindowReuse and Enemy.UnitFrameWindowReuse.GetPlayer (part)
            local rootPolicy, altPolicy = false, false
            if (player) then
                altPolicy = "empty"
                if (player.career > 0 and GetIconData (Icons.GetCareerIconIDFromCareerLine (player.career))) then rootPolicy = "write" end
                local alt = ResolveAltSpecIcon (part, player)
                if (alt and GetIconData (alt)) then altPolicy = "write" end
            end
            t.windowName = Enemy.UnitFramePart_CreateWindow (part, "EA_DynamicImage_DefaultSeparatorRight", "root", rootPolicy)

			Enemy.UnitFramePart_OnUpdate_ProceedWindowInitialization (part)
            t.cache.careerIconLayer = part.data.layer
			DynamicImageSetTextureDimensions (t.windowName, 32, 32)

            local altReused
            t.altIconWindowName, altReused = Enemy.UnitFramePart_CreateWindow (part, "EA_DynamicImage_DefaultSeparatorRight", "alt", altPolicy)
			WindowSetHandleInput (t.altIconWindowName, false)
			WindowSetAlpha (t.altIconWindowName, 1)
            if (not altReused) then WindowSetShowing (t.altIconWindowName, false) end
			t.cache.altIconShowing = false

			SyncAltIconLayout (part)
		end,

		OnScoreboardUpdate = function (part, player)
			UpdateAltSpecIcon (part, player, true)
		end,

        -- Effect indicators can rise on the Popup layer after this part was
        -- drawn. Restore the visible spec's priority without covering it.
        OnLayerRefresh = function (part)
            SyncAltIconLayers (part, true)
        end,

		OnUpdate = function (part, player)

			local t = part._t
			local cache = t.cache

			if (cache.career ~= player.career and player.career > 0)
			then
				cache.career = player.career

				local icon, icon_x, icon_y = GetIconData (Icons.GetCareerIconIDFromCareerLine (cache.career))
				DynamicImageSetTexture (t.windowName, icon, icon_x, icon_y)
                t.careerTextureWritten = icon ~= nil
			end

			UpdateAltSpecIcon (part, player)

			local wasShowing = t._isShowing
			Enemy.UnitFramePart_OnUpdate_ProceedState (part, player)
            -- Showing the main image can raise it over its same-layer overlay.
            -- Preserve its configured layer and restore only the pair's order.
            if (wasShowing ~= true and t._isShowing == true and cache.altIconShowing
                and cache.careerIconLayer == cache.altIconLayer)
            then
                RaiseIconLayer (t.altIconWindowName, cache.altIconLayer)
            end
		end
	}
    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.RegisterPartType (g.types["careerIcon"]) end
end

if (Enemy.UnitFrameWindowReuse) then
    Enemy.UnitFrameWindowReuse._careerGetIconData = GetIconData
    Enemy.UnitFrameWindowReuse._careerGetCareerIcon = Icons.GetCareerIconIDFromCareerLine
end

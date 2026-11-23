local Enemy = Enemy
local g = {}

local pairs = pairs
local next = next

local GUARD_PACKET_HEADER = "LibGuard"
local GUARD_INDICATOR_WINDOW = "EnemyGuardDistanceIndicator"
local guardIndicatorRender


local function GuardWipeTable (data)

	local key = next (data)

	while (key)
	do
		data[key] = nil
		key = next (data)
	end
end


local function GuardIndicatorInvalidate (preserveAnimation)

    local cache = guardIndicatorRender
    if (not cache) then return end
    local animated, animationAlpha = cache.animated, cache.animationAlpha
    GuardWipeTable (cache)
    if (preserveAnimation)
    then
        cache.animated = animated
        cache.animationAlpha = animationAlpha
    end
end


local function GuardIndicatorHide ()

    local cache = guardIndicatorRender
    if (not cache) then return end
    if (LayoutEditor.isActive) then GuardIndicatorInvalidate (); return end

    if (cache.showing ~= false)
    then
        WindowSetShowing (GUARD_INDICATOR_WINDOW, false)
        cache.showing = false
    end

    if (cache.animated ~= false)
    then
        WindowStopAlphaAnimation (GUARD_INDICATOR_WINDOW)
        cache.animated = false
        cache.alpha = nil
    end
    g.guardDistanceIndicatorAnimated = false
end


local function GuardIndicatorOnLayoutEdit (event)

    if (event ~= LayoutEditor.EDITING_END) then return end
    -- The native editor restores visibility, scale and alpha when detaching.
    GuardIndicatorInvalidate ()
    if (g.loading)
    then
        GuardIndicatorHide ()
    else
        Enemy.Guard_GuardIndicator_Update ()
    end
end


local function GuardRebuildPlayers ()

	GuardWipeTable (g.guardPlayers)

	if (g.outgoingGuardPlayerName)
	then
		g.guardPlayers[g.outgoingGuardPlayerName] = true
	end

	if (not g.imGuarder)
	then
		for player_name, _ in pairs (g.intercomGuardPlayers)
		do
			g.guardPlayers[player_name] = true
		end
	end

	if (g.settings and g.settings.guardIncomingPacketEnabled)
	then
		for player_name, _ in pairs (g.packetGuardPlayers)
		do
			g.guardPlayers[player_name] = true
		end
	end
end


local function GuardRefresh ()

    if (g.loading) then return end

	GuardRebuildPlayers ()
	Enemy.Guard_UpdateData ()
	Enemy.Guard_GuardMark_Update ()
	Enemy.Guard_GuardIndicator_Update ()
end


local function GuardPacketHandlingAvailable ()

    return type (ror_PacketHandling) == "table"
        and type (ror_PacketHandling.Register) == "function"
        and type (ror_PacketHandling.Unregister) == "function"
        and type (RegisterEventHandler) == "function"
        and type (UnregisterEventHandler) == "function"
        and type (TextLogGetUpdateEventId) == "function"
        and type (TextLogGetNumEntries) == "function"
        and type (TextLogGetEntry) == "function"
        and type (SystemData) == "table" and type (SystemData.TextLogUpdate) == "table"
        and type (SystemData.TextLogUpdate.ADDED) == "number"
        and type (SystemData.ChatLogFilters) == "table"
        and type (SystemData.ChatLogFilters.CHANNEL_9) == "number"
end


local function GuardGetPacketChatEvent ()
    if (not GuardPacketHandlingAvailable ()) then return nil end
    local event = TextLogGetUpdateEventId ("Chat")
    if (type (event) == "number") then return event end
    return nil
end


local function GuardSetPacketListenerEnabled (enable)
    local event = enable == true and GuardGetPacketChatEvent () or nil
    local handler = event and ror_PacketHandling or nil
    if (g.guardPacketHandler == handler and g.guardChatEvent == event) then return end

    -- LibGuard owns the dispatcher prefix. Observe Chat independently; never
    -- register, wrap or replace its packet callback.
    if (g.guardChatEvent)
    then
        g.guardChatUnregister (g.guardChatEvent, "Enemy.Guard_OnChatLogUpdated")
    end
    g.guardPacketHandler, g.guardChatEvent = handler, event
    g.guardChatUnregister = nil

    local hadPackets = next (g.packetGuardPlayers) ~= nil
    if (hadPackets) then GuardWipeTable (g.packetGuardPlayers) end
    if (event)
    then
        RegisterEventHandler (event, "Enemy.Guard_OnChatLogUpdated")
        g.guardChatUnregister = UnregisterEventHandler
    end

    if (hadPackets) then GuardRefresh () end
end


local function GuardPacketListenerActive ()

    return g.isPluginEnabled and g.settings.guardIncomingPacketEnabled
        and g.guardChatEvent ~= nil and g.guardPacketHandler == ror_PacketHandling
        and GuardPacketHandlingAvailable ()
end


local function GuardSetLoadingEventsEnabled (enable)

    if (not enable)
    then
        if (type (UnregisterEventHandler) == "function")
        then
            if (g.loadingBeginEvent)
            then
                UnregisterEventHandler (g.loadingBeginEvent, "Enemy.Guard_OnLoadingBegin")
            end
            if (g.loadingEndEvent)
            then
                UnregisterEventHandler (g.loadingEndEvent, "Enemy.Guard_OnLoadingEnd")
            end
        end
        g.loadingBeginEvent, g.loadingEndEvent = nil, nil
        return
    end

    if (g.loadingBeginEvent and g.loadingEndEvent) then return end
    local events = SystemData and SystemData.Events
    if (type (events) ~= "table"
        or type (events.LOADING_BEGIN) ~= "number"
        or type (events.LOADING_END) ~= "number"
        or type (RegisterEventHandler) ~= "function"
        or type (UnregisterEventHandler) ~= "function") then return end

    -- The reset needs both ends of loading; a begin-only hook would never resume.
    RegisterEventHandler (events.LOADING_BEGIN, "Enemy.Guard_OnLoadingBegin")
    g.loadingBeginEvent = events.LOADING_BEGIN
    RegisterEventHandler (events.LOADING_END, "Enemy.Guard_OnLoadingEnd")
    g.loadingEndEvent = events.LOADING_END
end

function Enemy.GuardInitialize ()

	Enemy.guard = g

	local career = GameData.Player.career.line
	g.imGuarder = (career == GameData.CareerLine.CHOSEN or career == GameData.CareerLine.BLACK_ORC or career == GameData.CareerLine.BLACKGUARD or
					career == GameData.CareerLine.KNIGHT or career == GameData.CareerLine.SWORDMASTER or career == GameData.CareerLine.IRON_BREAKER)

	g.guardPlayers = {}
	g.intercomGuardPlayers = {}
	g.packetGuardPlayers = {}

	if (not Enemy.Settings.guardMarkTemplate)
	then
		g.guardMarkTemplate = EnemyMarkTemplate.New ()
		g.guardMarkTemplate.color = { 65, 150, 255 }
		g.guardMarkTemplate.showCareerIcon = false
		g.guardMarkTemplate.display = 1
		g.guardMarkTemplate.text = L"G"
		g.guardMarkTemplate.font = "font_default_text_giant"
		g.guardMarkTemplate.scale = 0.8
		g.guardMarkTemplate.canClearOnClick = false
		g.guardMarkTemplate.neverExpire = true
		g.guardMarkTemplate.offsetY = 75

		Enemy.Settings.guardMarkTemplate = Enemy.clone (g.guardMarkTemplate)
	end

	-- UI: distance indicator
	CreateWindow ("EnemyGuardDistanceIndicator", true)
	LayoutEditor.RegisterWindow ("EnemyGuardDistanceIndicator", L"Enemy guard distance", L"Enemy guard distance indicator", false, false, false, nil)
    guardIndicatorRender = {}
    if (type (LayoutEditor.RegisterEditCallback) == "function" and not g.guardIndicatorLayoutCallbackRegistered)
    then
        LayoutEditor.RegisterEditCallback (GuardIndicatorOnLayoutEdit)
        g.guardIndicatorLayoutCallbackRegistered = true
    end

	-- static events
	Enemy.AddEventHandler ("Guard", "SettingsChanged", Enemy.Guard_OnSettingsChanged)
    Enemy.AddEventHandler ("Guard", "Shutdown", Enemy.Guard_OnShutdown)

	Enemy.AddEventHandler ("Guard", "ConfigDialogInitializeSections", function (sections)
		table.insert (sections,
		{
			name = "Guard",
			title = L"Guard",
			templateName = "EnemyGuardConfiguration",
			onInitialize = Enemy.GuardUI_ConfigDialog_OnInitialize,
			onLoad = Enemy.GuardUI_ConfigDialog_OnLoad,
			onSave = Enemy.GuardUI_ConfigDialog_OnSave,
			onReset = Enemy.GuardUI_ConfigDialog_OnReset
		})
	end)

	Enemy.TriggerEvent ("GuardInitialized")
end


function Enemy._GuardEnabledChanged (enable)

	if (enable)
	then
		if (g.guardMarkTemplate)
		then
			g.guardMarkTemplate:Load (g.settings.guardMarkTemplate)
		else
			g.guardMarkTemplate = EnemyMarkTemplate.New (g.settings.guardMarkTemplate)
		end

		g.guardMarkPlayerName = nil
	end

	if (g.isPluginEnabled == enable)
	then
		GuardSetPacketListenerEnabled (enable and g.settings.guardIncomingPacketEnabled)
		return
	end
	g.isPluginEnabled = enable

	if (g.isPluginEnabled)
	then
		Enemy.AddEventHandler ("Guard", "GroupsPlayerEffectsUpdated", Enemy.Guard_OnGroupsPlayerEffectsUpdated)
		Enemy.AddEventHandler ("Guard", "GroupsUpdated", Enemy.Guard_OnGroupsUpdated)
		Enemy.AddEventHandler ("Guard", "GroupsPlayerUpdated", Enemy.Guard_OnGroupsPlayerUpdated)
		Enemy.AddEventHandler ("Guard", "GroupsPlayerDistanceUpdated", Enemy.Guard_OnGroupsPlayerDistanceUpdated)
		Enemy.AddEventHandler ("Guard", "GroupsPlayerWorldObjectIdUpdated", Enemy.Guard_OnGroupsPlayerWorldObjectIdUpdated)
		Enemy.AddEventHandler ("Guard", "IntercomMessageGuard", Enemy.Guard_OnIntercomMessageGuard)
        GuardSetLoadingEventsEnabled (true)
        if (g.loadingBeginEvent and g.loadingEndEvent
            and SystemData.LoadingData and SystemData.LoadingData.isLoading)
        then
            Enemy.Guard_OnLoadingBegin ()
        elseif (g.loading)
        then
            Enemy.Guard_OnLoadingEnd ()
        end
	else
		Enemy.RemoveEventHandler ("Guard", "GroupsPlayerEffectsUpdated")
		Enemy.RemoveEventHandler ("Guard", "GroupsUpdated")
		Enemy.RemoveEventHandler ("Guard", "GroupsPlayerUpdated")
		Enemy.RemoveEventHandler ("Guard", "GroupsPlayerDistanceUpdated")
		Enemy.RemoveEventHandler ("Guard", "GroupsPlayerWorldObjectIdUpdated")
		Enemy.RemoveEventHandler ("Guard", "IntercomMessageGuard")
        GuardSetLoadingEventsEnabled (false)
	end

	GuardSetPacketListenerEnabled (g.isPluginEnabled and g.settings.guardIncomingPacketEnabled)
end

function Enemy.GuardDistanceUpdatesRequired ()
	if (not g.isPluginEnabled or g.loading) then return false end

	for _, _ in pairs (g.guardPlayers)
	do
		return true
	end

	return false
end


function Enemy.Guard_OnShutdown ()
    Enemy._GuardEnabledChanged (false)
end


function Enemy.Guard_OnSettingsChanged (settings)
	g.settings = settings
    GuardIndicatorInvalidate ()
	Enemy._GuardEnabledChanged (g.settings.guardEnabled)

    if (g.loading) then GuardIndicatorHide () end

	Enemy.Guard_UpdateData ()
	Enemy.Guard_GuardMark_Update ()
	Enemy.Guard_GuardIndicator_Update ()
end


function Enemy.Guard_OnLoadingBegin ()
    if (g.loading or not g.isPluginEnabled) then return end
    g.loading = true

    local hadDisplay = g.available or g.guardPlayerName or g.guardMarkPlayerName
    g.outgoingGuardPlayerName = nil
    GuardWipeTable (g.intercomGuardPlayers)
    GuardWipeTable (g.packetGuardPlayers)
    GuardWipeTable (g.guardPlayers)
    g.hasUnresolvedGuardPlayers = false
    g.available = false
    g.guardDistance = nil
    g.guardPlayerDirection = nil
    -- Roster callbacks can still carry pre-load effects. Only a new effects
    -- event may authorize outgoing discovery for each player after loading.
    g.staleGuardEffectPlayers = {}
    for _, player in pairs (Enemy.groups.players)
    do
        if (player.isInPlayerGroup and not player.isSelf)
        then
            g.staleGuardEffectPlayers[player] = true
        end
    end

    if (hadDisplay)
    then
        g.guardMarkTemplate:ClearMarks ()
        Enemy.Guard_SetGuardPlayerName (nil)
    end
    GuardIndicatorHide ()
    -- Loading may replace native presentation state. Repaint all content on
    -- the next valid guard, while duplicate loading/idle events stay silent.
    GuardIndicatorInvalidate ()
    if (not LayoutEditor.isActive)
    then
        guardIndicatorRender.showing = false
        guardIndicatorRender.animated = false
    end
    g.guardMarkPlayerName = nil
end


function Enemy.Guard_OnLoadingEnd ()
    -- The optional provider can load after Enemy; retry at a lifecycle boundary.
    if (g.isPluginEnabled and g.settings)
    then
        GuardSetPacketListenerEnabled (g.settings.guardIncomingPacketEnabled)
    end
    if (not g.loading) then return end
    g.loading = false
    -- Keep Apply/Remove packets received during loading; never clear again
    -- here or a valid new guard could be lost before the first visible frame.
    if (g.isPluginEnabled and next (g.packetGuardPlayers)) then GuardRefresh () end
end


function Enemy.Guard_OnChatLogUpdated (updateType, filterType)

    if (not GuardPacketListenerActive ()
        or updateType ~= SystemData.TextLogUpdate.ADDED
        or filterType ~= SystemData.ChatLogFilters.CHANNEL_9) then return end

    local count = TextLogGetNumEntries ("Chat")
    if (type (count) ~= "number" or count <= 0) then return end
    local _, entryFilter, text = TextLogGetEntry ("Chat", count - 1)
    if (entryFilter ~= filterType or text == nil) then return end
    text = tostring (text)
    if (string.sub (text, 1, 9) ~= "LibGuard:") then return end
    Enemy.Guard_OnPacket (text)
end


function Enemy.Guard_OnPacket (text)

    if (not GuardPacketListenerActive ()) then return end

	local data = StringSplit (tostring (text or ""), ":")
	if (not data or data[1] ~= GUARD_PACKET_HEADER) then return end

	local command = data[2]
	if (command ~= "Apply" and command ~= "Remove") then return end

	local player_name = Enemy.NormalizePlayerName (towstring (data[3] or ""))
	if (not player_name or player_name == L"" or player_name == Enemy.playerName) then return end

	if (command == "Apply")
	then
		g.packetGuardPlayers[player_name] = true
	else
		g.packetGuardPlayers[player_name] = nil
	end

	GuardRefresh ()
end


function Enemy.Guard_SetGuardPlayerName (playerName)
	g.guardPlayerName = playerName
	WindowSetGameActionData ("EnemyGuardDistanceIndicator", GameData.PlayerActions.SET_TARGET, 0, Enemy.isNil (g.guardPlayerName, L""))
end


function Enemy.Guard_OnGroupsUpdated ()

    if (g.loading) then return end

	local player_self = Enemy.groups.player
	if (not player_self or not player_self:IsInGroup ())
	then
		g.outgoingGuardPlayerName = nil
		GuardWipeTable (g.intercomGuardPlayers)
		GuardWipeTable (g.packetGuardPlayers)
		GuardRefresh ()
		return
	end

	local present_players = {}

	for k = 1, 6
	do
		local player = player_self.group[k]
		if (not player) then continue end

		present_players[player.name] = true

		Enemy.Guard_OnGroupsPlayerEffectsUpdated (player, true)
	end

	local changed = false
	if (g.outgoingGuardPlayerName and not present_players[g.outgoingGuardPlayerName])
	then
		g.outgoingGuardPlayerName = nil
		changed = true
	end

	for player_name, _ in pairs (g.intercomGuardPlayers)
	do
		if (not present_players[player_name])
		then
			g.intercomGuardPlayers[player_name] = nil
			changed = true
		end
	end

	for player_name, _ in pairs (g.packetGuardPlayers)
	do
		if (not present_players[player_name])
		then
			g.packetGuardPlayers[player_name] = nil
			changed = true
		end
	end

	if (changed or g.hasUnresolvedGuardPlayers)
	then
		-- A packet may arrive before its guarder exists in the rebuilt roster.
		GuardRefresh ()
	elseif (g.guardMarkPlayerName ~= g.guardPlayerName)
	then
		Enemy.Guard_GuardMark_Update ()
	end
end


function Enemy.Guard_OnGroupsPlayerEffectsUpdated (player, fromRoster)

    if (g.loading) then return end

    if (player.isSelf) then return end

    if (g.staleGuardEffectPlayers)
    then
        if (fromRoster and g.staleGuardEffectPlayers[player]) then return end
        if (not fromRoster) then g.staleGuardEffectPlayers[player] = nil end
    end

	if (not player.isInPlayerGroup or player.worldObjectId == 0) then return end

	local has_guard = false

	for _, effect in pairs (player.effects)
	do
		if (effect.castByPlayer and Enemy.GuardAbilityIds[effect.abilityId])
		then
			has_guard = true
			break
		end
	end

	if (g.outgoingGuardPlayerName == player.name and has_guard) then return end

	if (has_guard)
	then
		Enemy.Guard_StartGuarding (player)

	elseif (g.imGuarder and g.outgoingGuardPlayerName == player.name)
	then
		Enemy.Guard_StopGuarding ()
	end
end


function Enemy.Guard_GuardMark_Update ()

	if (not g.guardMarkTemplate or g.loading) then return end

	if (not g.guardPlayerName or not g.settings.guardMarkEnabled)
	then
		g.guardMarkTemplate:ClearMarks ()
		g.guardMarkPlayerName = nil

	elseif (g.guardMarkPlayerName ~= g.guardPlayerName)
	then
		g.guardMarkTemplate:ClearMarks ()
		g.guardMarkPlayerName = nil

		local player = Enemy.groups.players[g.guardPlayerName]
		if (not player or not player.worldObjectId or player.worldObjectId == 0) then return end

		g.guardMarkTemplate:ToggleMark (
			player.worldObjectId,
			player.name,
			true,
			true,
			player.career)

		g.guardMarkPlayerName = g.guardPlayerName
	end
end


function Enemy.Guard_StartGuarding (player)

    if (g.loading) then return end

	g.outgoingGuardPlayerName = player.name
	GuardRefresh ()
end


function Enemy.Guard_StopGuarding ()

	if (not g.outgoingGuardPlayerName) then return end

	g.outgoingGuardPlayerName = nil
	GuardRefresh ()
end


function Enemy.Guard_OnIntercomMessageGuard (from, command, playerName)

    if (g.loading) then return end

	from = Enemy.groups.players[from]
	local player = Enemy.groups.players[playerName]

	if (not from or from.isSelf) then return end

    -- Legacy Intercom receives guard ownership; it sends no announcements.
    if (not g.imGuarder and player)
	then
		if (not player.isSelf)
		then
			g.intercomGuardPlayers[from.name] = nil
		else
			if (command == L"Start")
			then
				g.intercomGuardPlayers[from.name] = true

			elseif (command == L"Stop")
			then
				g.intercomGuardPlayers[from.name] = nil
			end
		end

		GuardRefresh ()
	end
end


function Enemy.Guard_UpdateData ()

	g.available = false
	g.guardDistance = nil
	g.hasUnresolvedGuardPlayers = false

	local guard_player_name = nil

	for player_name, _ in pairs (g.guardPlayers)
	do
		local player = Enemy.groups.players[player_name]
		if (player)
		then
			local distance = player.distance or 999
			g.available = true

			if (g.guardDistance == nil or g.guardDistance > distance)
			then
				g.guardDistance = distance
				guard_player_name = player.name
			end
		else
			g.hasUnresolvedGuardPlayers = true
		end
	end

	local is_outgoing = guard_player_name and g.outgoingGuardPlayerName == guard_player_name
	local is_incoming = guard_player_name
		and ((g.settings.guardIncomingPacketEnabled and g.packetGuardPlayers[guard_player_name])
			or (not g.imGuarder and g.intercomGuardPlayers[guard_player_name]))

	if (is_outgoing and is_incoming)
	then
		g.guardPlayerDirection = "both"
	elseif (is_outgoing)
	then
		g.guardPlayerDirection = "outgoing"
	elseif (is_incoming)
	then
		g.guardPlayerDirection = "incoming"
	else
		g.guardPlayerDirection = nil
	end

	if (guard_player_name ~= g.guardPlayerName)
	then
		Enemy.Guard_SetGuardPlayerName (guard_player_name)
	end
end


function Enemy.Guard_OnGroupsPlayerUpdated (player)
	if (not player.isSelf) then return end
	Enemy.Guard_GuardIndicator_Update ()
end


function Enemy.Guard_OnGroupsPlayerWorldObjectIdUpdated (player)
	if (not player or not g.guardPlayers[player.name]) then return end
	Enemy.Guard_GuardMark_Update ()
end


function Enemy.Guard_OnGroupsPlayerDistanceUpdated (player)
	if (not g.guardPlayers[player.name]) then return end
	Enemy.Guard_UpdateData ()
	Enemy.Guard_GuardMark_Update ()
	Enemy.Guard_GuardIndicator_Update ()
end


function Enemy.Guard_GuardIndicator_Update ()

    local cache = guardIndicatorRender
    if (not cache or g.loading) then return end

    -- The editor owns the native window until its end callback. Hosts without
    -- that callback retain authoritative presentation writes on each update.
    if (LayoutEditor.isActive) then GuardIndicatorInvalidate (); return end
    if (not g.guardIndicatorLayoutCallbackRegistered) then GuardIndicatorInvalidate (true) end

    local settings = g.settings
    local player = Enemy.groups and Enemy.groups.player
    if (not settings or not g.isPluginEnabled or not player or
        settings.guardDistanceIndicator == 1 or
        (settings.guardDistanceIndicator == 3 and not player.isRVRFlagged) or
        not g.available or g.guardDistance == nil)
    then
        GuardIndicatorHide ()
        return
    end

    if (cache.showing ~= true)
    then
        WindowSetShowing (GUARD_INDICATOR_WINDOW, true)
        cache.showing = true
    end

    local handleInput = not settings.guardDistanceIndicatorClickThrough
    if (cache.handleInput ~= handleInput)
    then
        WindowSetHandleInput (GUARD_INDICATOR_WINDOW, handleInput)
        cache.handleInput = handleInput
    end
    if (cache.movable ~= settings.guardDistanceIndicatorMovable)
    then
        WindowSetMovable (GUARD_INDICATOR_WINDOW, settings.guardDistanceIndicatorMovable)
        cache.movable = settings.guardDistanceIndicatorMovable
    end

    local warning = g.guardDistance >= settings.guardDistanceIndicatorWarningDistance
    local color, scale, alpha
    if (warning)
    then
        color = settings.guardDistanceIndicatorColorWarning
        scale = settings.guardDistanceIndicatorScaleWarning
        alpha = settings.guardDistanceIndicatorAlphaWarning
    else
        color = settings.guardDistanceIndicatorColorNormal
        scale = settings.guardDistanceIndicatorScaleNormal
        alpha = settings.guardDistanceIndicatorAlphaNormal
    end

    -- Snapshot scalar values, since settings and color tables can be edited
    -- in place between otherwise identical distance or self-resource events.
    if (cache.red ~= color[1] or cache.green ~= color[2] or cache.blue ~= color[3])
    then
        WindowSetTintColor (GUARD_INDICATOR_WINDOW, color[1], color[2], color[3])
        cache.red, cache.green, cache.blue = color[1], color[2], color[3]
    end
    if (cache.scale ~= scale)
    then
        WindowSetScale (GUARD_INDICATOR_WINDOW, scale)
        cache.scale = scale
    end

    if (warning and settings.guardDistanceIndicatorAnimation and player.isInCombat)
    then
        if (cache.animated ~= true or cache.animationAlpha ~= alpha)
        then
            WindowStartAlphaAnimation (GUARD_INDICATOR_WINDOW, Window.AnimationType.LOOP, alpha / 4, alpha, 0.3, true, 0, 0)
            cache.animated = true
            cache.animationAlpha = alpha
            cache.alpha = nil
        end
        g.guardDistanceIndicatorAnimated = true
    else
        if (cache.animated ~= false)
        then
            WindowStopAlphaAnimation (GUARD_INDICATOR_WINDOW)
            cache.animated = false
            cache.alpha = nil
        end
        if (cache.alpha ~= alpha)
        then
            WindowSetAlpha (GUARD_INDICATOR_WINDOW, alpha)
            cache.alpha = alpha
        end
        g.guardDistanceIndicatorAnimated = false
    end

    local distance = g.guardDistance > 300 and "FAR" or g.guardDistance
    if (cache.distance ~= distance)
    then
        LabelSetText (GUARD_INDICATOR_WINDOW.."Text", distance == "FAR" and L"FAR" or towstring (distance))
        cache.distance = distance
    end
end


function Enemy.Guard_GuardIndicator_OnMouseOver ()

	if (not g.isPluginEnabled or not g.guardPlayerName) then return end

	Tooltips.CreateTextOnlyTooltip (SystemData.MouseOverWindow.name)

	if (g.guardPlayerDirection == "both")
	then
		Tooltips.SetTooltipText (1, 1, L"Distance to cross-guard partner")
	elseif (g.guardPlayerDirection == "outgoing")
	then
		Tooltips.SetTooltipText (1, 1, L"Distance to guarded player")
	else
		Tooltips.SetTooltipText (1, 1, L"Distance to the closest guarder")
	end

	Tooltips.SetTooltipText (1, 3, g.guardPlayerName)
	Tooltips.SetTooltipColor (1, 3, 150, 150, 255)

	Tooltips.SetTooltipText (3, 1, L"Click to target")

	Tooltips.AnchorTooltip (Tooltips.ANCHOR_CURSOR)
	Tooltips.Finalize()
end


function Enemy.Guard_GuardIndicator_OnLButtonUp ()
end


--------------------------------------------------------------- UI: Configuration
local config_dlg = {}

config_dlg.properties =
{
	guardEnabled =
	{
		key = "guardEnabled",
		order = 10,
		name = L"Enable guarding enhancements",
		type = "bool",
		default = Enemy.DefaultSettings.guardEnabled,
		tooltip = L"Enables guard distance and marks; required for incoming detection"
	},
	guardIncomingPacketEnabled =
	{
		key = "guardIncomingPacketEnabled",
		order = 15,
		name = L"Enable server-based incoming guard detection",
		type = "bool",
		default = Enemy.DefaultSettings.guardIncomingPacketEnabled,
		tooltip = L"Detects who guards you; requires guarding enhancements and ror_PacketHandling",
		onLoad = function (wnp, p, data)
			local available = GuardGetPacketChatEvent () ~= nil
			ButtonSetDisabledFlag (wnp.."Value", not available)
			ButtonSetPressedFlag (wnp.."Value", available and data[p.key] == true)
			p.tooltip = available
				and L"Detects who guards you; requires guarding enhancements and server support"
				or L"Unavailable: requires ror_PacketHandling and Chat packet support"
		end,
		onSave = function (wnp, p, data)
			data[p.key] = GuardGetPacketChatEvent () ~= nil and ButtonGetPressedFlag (wnp.."Value") == true
			p.onLoad (wnp, p, data)
		end
	},

	guardDistanceIndicatorTitle =
	{
		key = "guardDistanceIndicatorTitle",
		order = 20,
		name = L"Guard distance indicator",
		type = "title",
		paddingTop = 30
	},
	guardDistanceIndicator =
	{
		key = "guardDistanceIndicator",
		order = 30,
		name = L"Distance indicator",
		type = "select",
		default = Enemy.DefaultSettings.guardDistanceIndicator,
		values =
		{
			{ text = L"hide", value = 1 },
			{ text = L"show when available", value = 2 },
			{ text = L"show when available and PvP flagged", value = 3 }
		}
	},
	guardDistanceIndicatorMovable =
	{
		key = "guardDistanceIndicatorMovable",
		order = 35,
		name = L"Movable",
		type = "bool",
		default = Enemy.DefaultSettings.guardDistanceIndicatorMovable
	},
	guardDistanceIndicatorClickThrough =
	{
		key = "guardDistanceIndicatorClickThrough",
		order = 36,
		name = L"Click through",
		type = "bool",
		default = Enemy.DefaultSettings.guardDistanceIndicatorClickThrough,
		tooltip = L"If checked guard indicator will not be clickable (and movable too)"
	},
	guardDistanceIndicatorWarningDistance =
	{
		key = "guardDistanceIndicatorWarningDistance",
		order = 40,
		name = L"Warning distance",
		type = "int",
		min = 0,
		max = 1000,
		default = Enemy.DefaultSettings.guardDistanceIndicatorWarningDistance,
		tooltip = L"If the distance between you and guarder (or guarded player) will be more than this value, the indicator will switch to 'warning' mode"
	},
	guardDistanceIndicatorColorNormal =
	{
		key = "guardDistanceIndicatorColorNormal",
		order = 50,
		name = L"Normal color",
		type = "color",
		default = Enemy.DefaultSettings.guardDistanceIndicatorColorNormal
	},
	guardDistanceIndicatorColorWarning =
	{
		key = "guardDistanceIndicatorColorWarning",
		order = 60,
		name = L"Warning color",
		type = "color",
		default = Enemy.DefaultSettings.guardDistanceIndicatorColorWarning
	},
	guardDistanceIndicatorAlphaNormal =
	{
		key = "guardDistanceIndicatorAlphaNormal",
		order = 70,
		name = L"Normal opacity",
		type = "float",
		default = Enemy.DefaultSettings.guardDistanceIndicatorAlphaNormal,
		min = 0,
		max = 1
	},
	guardDistanceIndicatorAlphaWarning =
	{
		key = "guardDistanceIndicatorAlphaWarning",
		order = 80,
		name = L"Warning opacity",
		type = "float",
		default = Enemy.DefaultSettings.guardDistanceIndicatorAlphaWarning,
		min = 0,
		max = 1
	},
	guardDistanceIndicatorScaleNormal =
	{
		key = "guardDistanceIndicatorScaleNormal",
		order = 84,
		name = L"Normal scaling",
		type = "float",
		default = Enemy.DefaultSettings.guardDistanceIndicatorScaleNormal,
		min = 0,
		max = 10
	},
	guardDistanceIndicatorScaleWarning =
	{
		key = "guardDistanceIndicatorScaleWarning",
		order = 85,
		name = L"Warning scaling",
		type = "float",
		default = Enemy.DefaultSettings.guardDistanceIndicatorScaleWarning,
		min = 0,
		max = 10
	},
	guardDistanceIndicatorAnimation =
	{
		key = "guardDistanceIndicatorAnimation",
		order = 90,
		name = L"Enable warning animation (only in combat)",
		type = "bool",
		default = Enemy.DefaultSettings.guardDistanceIndicatorAnimation
	},

	guardMarkTitle =
	{
		key = "guardMarkTitle",
		order = 100,
		name = L"Guard mark",
		type = "title",
		paddingTop = 30
	},
	guardMarkEnabled =
	{
		key = "guardMarkEnabled",
		order = 110,
		name = L"Enable marking guarder/guarded player",
		type = "bool",
		default = Enemy.DefaultSettings.guardMarkEnabled
	},
	editGuardTemplate =
	{
		key = "editGuardTemplate",
		order = 120,
		name = L"Edit guard mark template",
		type = "button",
		windowWidth = 300,
		onClick = function ()
			config_dlg.guardMarkTemplate:Edit ()
			Enemy.Guard_OnSettingsChanged (config_dlg)
		end
	}
}


function Enemy.GuardUI_ConfigDialog_OnInitialize (section)

	config_dlg.section = section

	local root = config_dlg.section.windowName.."ContentScrollChild"
	config_dlg.cwn = root.."Config"
	Enemy.CreateConfigurationWindow (config_dlg.cwn, root, config_dlg.properties, Enemy.GuardUI_ConfigDialog_TestSettings)

	ScrollWindowUpdateScrollRect (config_dlg.section.windowName.."Content")
end


function Enemy.GuardUI_ConfigDialog_OnLoad (section)

	config_dlg.isLoading = true

	config_dlg.guardEnabled = Enemy.Settings.guardEnabled
	config_dlg.guardIncomingPacketEnabled = Enemy.Settings.guardIncomingPacketEnabled
	config_dlg.guardMarkTemplate = EnemyMarkTemplate.New (Enemy.Settings.guardMarkTemplate)
	config_dlg.guardDistanceIndicator = Enemy.Settings.guardDistanceIndicator
	config_dlg.guardDistanceIndicatorMovable = Enemy.Settings.guardDistanceIndicatorMovable
	config_dlg.guardDistanceIndicatorClickThrough = Enemy.Settings.guardDistanceIndicatorClickThrough
	config_dlg.guardDistanceIndicatorWarningDistance = Enemy.Settings.guardDistanceIndicatorWarningDistance
	config_dlg.guardDistanceIndicatorColorNormal = Enemy.clone (Enemy.Settings.guardDistanceIndicatorColorNormal)
	config_dlg.guardDistanceIndicatorColorWarning = Enemy.clone (Enemy.Settings.guardDistanceIndicatorColorWarning)
	config_dlg.guardDistanceIndicatorAlphaNormal = Enemy.Settings.guardDistanceIndicatorAlphaNormal
	config_dlg.guardDistanceIndicatorAlphaWarning = Enemy.Settings.guardDistanceIndicatorAlphaWarning
	config_dlg.guardDistanceIndicatorScaleNormal = Enemy.Settings.guardDistanceIndicatorScaleNormal
	config_dlg.guardDistanceIndicatorScaleWarning = Enemy.Settings.guardDistanceIndicatorScaleWarning
	config_dlg.guardDistanceIndicatorAnimation = Enemy.Settings.guardDistanceIndicatorAnimation
	config_dlg.guardMarkEnabled = Enemy.Settings.guardMarkEnabled

	Enemy.ConfigurationWindowLoadData (config_dlg.cwn, config_dlg)

	config_dlg.isLoading = false

	Enemy.GuardUI_ConfigDialog_TestSettings ()
end


function Enemy.GuardUI_ConfigDialog_OnReset (section)

	for k, v in pairs (Enemy.Settings)
	do
		if (not k:match("^guard.*")) then continue end
		Enemy.Settings[k] = nil
	end

	Enemy.Print ("Guard mark settings has been reset")
	InterfaceCore.ReloadUI ()
end


function Enemy.GuardUI_ConfigDialog_TestSettings ()

	if (config_dlg.isLoading) then return end

	Enemy.ConfigurationWindowSaveData (config_dlg.cwn, config_dlg)
	Enemy.Guard_OnSettingsChanged (config_dlg)
end


function Enemy.GuardUI_ConfigDialog_OnSave (section)

	Enemy.GuardUI_ConfigDialog_TestSettings ()
	config_dlg.guardMarkTemplate:ClearMarks ()

	Enemy.Settings.guardEnabled = config_dlg.guardEnabled
	Enemy.Settings.guardIncomingPacketEnabled = config_dlg.guardIncomingPacketEnabled
	Enemy.Settings.guardMarkTemplate = config_dlg.guardMarkTemplate
	Enemy.Settings.guardDistanceIndicator = config_dlg.guardDistanceIndicator
	Enemy.Settings.guardDistanceIndicatorWarningDistance = config_dlg.guardDistanceIndicatorWarningDistance
	Enemy.Settings.guardDistanceIndicatorMovable = config_dlg.guardDistanceIndicatorMovable
	Enemy.Settings.guardDistanceIndicatorClickThrough = config_dlg.guardDistanceIndicatorClickThrough
	Enemy.Settings.guardDistanceIndicatorColorNormal = Enemy.clone (config_dlg.guardDistanceIndicatorColorNormal)
	Enemy.Settings.guardDistanceIndicatorColorWarning = Enemy.clone (config_dlg.guardDistanceIndicatorColorWarning)
	Enemy.Settings.guardDistanceIndicatorAlphaNormal = config_dlg.guardDistanceIndicatorAlphaNormal
	Enemy.Settings.guardDistanceIndicatorAlphaWarning = config_dlg.guardDistanceIndicatorAlphaWarning
	Enemy.Settings.guardDistanceIndicatorScaleNormal = config_dlg.guardDistanceIndicatorScaleNormal
	Enemy.Settings.guardDistanceIndicatorScaleWarning = config_dlg.guardDistanceIndicatorScaleWarning
	Enemy.Settings.guardDistanceIndicatorAnimation = config_dlg.guardDistanceIndicatorAnimation
	Enemy.Settings.guardMarkEnabled = config_dlg.guardMarkEnabled

	return true
end

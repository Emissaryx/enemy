local Enemy = Enemy
local g = nil

local isAnchorDragged = false

local tinsert = table.insert
local tsort = table.sort
local pairs = pairs
local ipairs = ipairs
local unpack = unpack
local mfloor = math.floor
local mmax = math.max

-- Generated IDS rows and icons are owned by this module. Reset the cache when
-- their lifecycle is restarted so the next request is always authoritative.
local windowShowing = {}
local rowContent = {}
local previousDisplayCount = 0


local function HideOnTimeout ()
    Enemy.CombatLogUI_IDS_HideWindows ()
    g.idsHideTimer = nil
    return true
end


local function CompareValue (a, b)
    return a.value < b.value
end


local function ResetWindowShowing ()
    windowShowing = {}
    rowContent = {}
    previousDisplayCount = 0
end


local function SetWindowShowing (windowName, showing)
    showing = showing == true
    if (windowShowing[windowName] == showing) then return end

    WindowSetShowing (windowName, showing)
    windowShowing[windowName] = showing
end


function Enemy.CombatLogUI_IDS_Initialize ()

	g = Enemy.combatLog
	ResetWindowShowing ()
	g.ids = {}			-- stats
	g.idsWindows = {}	-- row windows list
	g.idsCareers = {}	-- attackers careers cache
	g.idsNamesByIndex = {}

	CreateWindow ("EnemyCombatLogIDSAnchor", true)
	WindowSetTintColor ("EnemyCombatLogIDSAnchorBackground", 0, 0, 0)
	WindowSetAlpha ("EnemyCombatLogIDSAnchor", 0)

	Enemy.AddEventHandler ("CombatLog_IDS", "CombatLogSettingsChanged", Enemy.CombatLogUI_IDS_OnSettingsChanged)
end


local function RegisterLayoutWindow ()

	if (g.idsLayoutRegistered) then return end

	LayoutEditor.RegisterWindow ("EnemyCombatLogIDSAnchor", L"Combat log IDS", L"Enemy combat log IDS anchor", false, false, false, nil)
	g.idsLayoutRegistered = true
end


local function UnregisterLayoutWindow ()

	if (not g.idsLayoutRegistered) then return end

	if (LayoutEditor.UnregisterWindow) then LayoutEditor.UnregisterWindow ("EnemyCombatLogIDSAnchor") end
	g.idsLayoutRegistered = false
end


local function RemoveHideTimer ()

	if (not g.idsHideTimer) then return end

	g.idsHideTimer:Remove()
	g.idsHideTimer = nil
end


function Enemy.CombatLogUI_IDSAnchor_OnLButtonDown ()
	isAnchorDragged = true
end


function Enemy.CombatLogUI_IDSAnchor_OnLButtonUp ()
	isAnchorDragged = false
end


function Enemy.CombatLogUI_IDSAnchor_OnMouseOver ()
	if (isAnchorDragged) then return end
	WindowStartAlphaAnimation ("EnemyCombatLogIDSAnchor", Window.AnimationType.SINGLE_NO_RESET, 0, 0.5, 0.3, true, 0, 1)
end


function Enemy.CombatLogUI_IDSAnchor_OnMouseOverEnd ()
	if (isAnchorDragged) then return end
	WindowStartAlphaAnimation ("EnemyCombatLogIDSAnchor", Window.AnimationType.SINGLE_NO_RESET, 0.5, 0, 0.3, true, 0, 1)
end


function Enemy.CombatLogUI_IDS_OnSettingsChanged (settings)

	if (settings.combatLogEnabled)
	then
		RegisterLayoutWindow ()
	else
		UnregisterLayoutWindow ()
	end

	local enabled = settings.combatLogEnabled and settings.combatLogIDSEnabled
	WindowSetShowing ("EnemyCombatLogIDSAnchor", enabled)

	if (enabled)
	then
		Enemy.AddEventHandler ("CombatLog_IDS", "CombatLogNewCombatEvent", Enemy.CombatLog_IDS_OnNewCombatEvent)
		Enemy.AddEventHandler ("CombatLog_IDS", "PlayerTargetUpdated", Enemy.CombatLog_IDS_OnPlayerTargetUpdated)

		Enemy.CombatLogUI_IDS_Update ()

		for index in ipairs (g.idsWindows)
		do
			Enemy._CombatLogUI_IDS_UpdateWindow (index)
		end
	else
		Enemy.RemoveEventHandler ("CombatLog_IDS", "CombatLogNewCombatEvent")
		Enemy.RemoveEventHandler ("CombatLog_IDS", "PlayerTargetUpdated")

		Enemy.CombatLogUI_IDS_HideWindows ()
		RemoveHideTimer ()
		ResetWindowShowing ()
	end
end


function Enemy.CombatLog_IDS_OnPlayerTargetUpdated (target)

	if (target.isNpc or target.isFriendly) then return end

	local old_career = g.idsCareers[target.name]
	g.idsCareers[target.name] = target.career

	if (old_career ~= target.career and g.ids[target.name])
	then
		Enemy.CombatLogUI_IDS_Update ()
	end
end


function Enemy.CombatLog_IDS_GetCareer (playerName)

	local res = g.idsCareers[playerName]
	if (res) then return res end

	-- try to look up scenario info module
	local sip = Enemy.scenarioInfo and Enemy.scenarioInfo.playersByName
	if (not sip) then return nil end

	local player = sip[playerName]
	if (not player) then return nil end

	res = player.career
	g.idsCareers[playerName] = res

	return res
end


function Enemy.CombatLogUI_IDS_HideWindows ()
	for _, wn in ipairs (g.idsWindows)
	do
		SetWindowShowing (wn, false)
	end
end


function Enemy.CombatLog_IDS_OnNewCombatEvent (combatEvent)

	if (combatEvent.type ~= Enemy.CombatLogTypes.IncommingDamage or not combatEvent.value) then return end

	local stats = g.ids[combatEvent.object]
	if (not stats)
	then
		stats =
		{
			name = combatEvent.object,
			total = 0,
			data = EnemyLinkedList.New ()
		}

		g.ids[combatEvent.object] = stats
	end

	-- add stats data
	stats.data:Add (combatEvent)
	stats.total = stats.total + combatEvent.value

	-- remove all combat events from all stats that exceeds measuring timeframe interval
	local max_time = stats.data.last.data.time - g.settings.combatLogIDSTimeframe
	local remove_keys = {}

	for _, stats_item in pairs (g.ids)
	do
		local tmp = stats_item.data.first
		while (tmp and tmp.data.time < max_time)
		do
			local old_combat_event = tmp.data

			stats_item.total = stats_item.total - old_combat_event.value

			stats_item.data:Remove (tmp)
			tmp = stats_item.data.first
		end

		if (not stats_item.data.first)
		then
			tinsert (remove_keys, stats_item.name)
		end
	end

	for _, remove_key in ipairs (remove_keys)
	do
		g.ids[remove_key] = nil
	end

	-- update hide timer
	RemoveHideTimer ()
    g.idsHideTimer = EnemyTimer.New ("CombatLogUI_IDS_HideAll", g.settings.combatLogIDSDisplayTime, HideOnTimeout)

	Enemy.CombatLogUI_IDS_Update ()
end


function Enemy._CombatLogUI_IDS_UpdateWindow (index)

	local wn = g.idsWindows[index]

	WindowClearAnchors (wn)
	WindowAddAnchor (wn, "center", "EnemyCombatLogIDSAnchor", "topleft",
		0, (g.settings.combatLogIDSRowSize[2] + g.settings.combatLogIDSRowPadding) * (index - 1))

	WindowSetDimensions (wn, unpack (g.settings.combatLogIDSRowSize))
	WindowSetScale (wn, g.settings.combatLogIDSRowScale)

    -- CombatLogIDS.xml reserves 35 px for the icon/inset and 65 for the
    -- value/right inset. Keep the right-anchored name inside that gap.
    local name_width = g.settings.combatLogIDSRowSize[1] - 35 - 65
    WindowSetDimensions (wn.."Name", mmax (1, name_width), 19)
    WindowSetShowing (wn.."Name", name_width > 0)

	local wn_background = wn.."Background"

	if (g.settings.combatLogIDSRowBackgroundAlpha > 0)
	then
		WindowSetTintColor (wn_background, unpack (g.settings.combatLogIDSRowBackground))
		WindowSetAlpha (wn_background, g.settings.combatLogIDSRowBackgroundAlpha)
		WindowSetShowing (wn_background, true)
	else
		WindowSetShowing (wn_background, false)
	end
end


function Enemy.CombatLogUI_IDS_Update ()

    -- Capacity hints keep every list and descriptor freshly owned. Captured
    -- insertion/sort helpers still receive the original calls and arguments.
    local data
    if (previousDisplayCount == 0) then data = {}
    elseif (previousDisplayCount == 1) then data = { nil }
    elseif (previousDisplayCount == 2) then data = { nil, nil }
    elseif (previousDisplayCount <= 4) then data = { nil, nil, nil, nil }
    elseif (previousDisplayCount == 5) then data = { nil, nil, nil, nil, nil }
    elseif (previousDisplayCount <= 8) then data = { nil, nil, nil, nil, nil, nil, nil, nil }
    elseif (previousDisplayCount <= 16) then data = { nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil }
    else data = {} end
	for _, stats in pairs (g.ids)
	do
		local s =
		{
			name = stats.name,
			value = stats.total
		}

		if (g.settings.combatLogIDSType == "dps")
		then
			local dtime = stats.data.last.data.time - stats.data.first.data.time
			if (dtime == 0)
			then
				dtime = 1
			end

			s.value = mfloor (s.value / dtime + 0.5)
		end

		if (s.value > 0)
		then
			tinsert (data, s)
		end
	end

	if (#data < 1)
	then
        previousDisplayCount = 0
		Enemy.CombatLogUI_IDS_HideWindows ()
		return
	end

    tsort (data, CompareValue)

	local index_from = #data
    previousDisplayCount = index_from
	local index_to = mmax (1, index_from - g.settings.combatLogIDSMaxRows + 1)
	local index = 1

	for k = index_from, index_to, -1
	do
		local s = data[k]
		g.idsNamesByIndex[index] = s.name

		local wn = g.idsWindows[index]
		if (not wn)
		then
			wn = "EnemyCombatLogIDSRow"..index
			g.idsWindows[index] = wn

			CreateWindowFromTemplate (wn, "EnemyCombatLogIDSRow", "Root")
			windowShowing[wn] = nil
			windowShowing[wn.."Icon"] = nil
			rowContent[wn] = nil
			Enemy._CombatLogUI_IDS_UpdateWindow (index)
		end

        local content = rowContent[wn]
        if (not content)
        then
            content = {}
            rowContent[wn] = content
        end

        if (content.name ~= s.name)
        then
            LabelSetText (wn.."Name", s.name)
            content.name = s.name
        end
        if (content.value ~= s.value)
        then
            LabelSetText (wn.."Value", Enemy.toWString (s.value))
            content.value = s.value
        end
		SetWindowShowing (wn, true)

		local career = Enemy.CombatLog_IDS_GetCareer (s.name)
		if (career)
		then
            if (content.career ~= career)
            then
                local icon, icon_x, icon_y = GetIconData (Icons.GetCareerIconIDFromCareerLine (career))
                DynamicImageSetTexture (wn.."Icon", icon, icon_x, icon_y)
                content.career = career
            end
			SetWindowShowing (wn.."Icon", true)
		else
			SetWindowShowing (wn.."Icon", false)
		end

		index = index + 1
	end

	while (index <= #g.idsWindows)
	do
		SetWindowShowing (g.idsWindows[index], false)
		index = index + 1
	end
end


function Enemy.CombatLogUI_IDS_OnRowLButtonDown ()

	local row_index = SystemData.ActiveWindow.name:match ("^EnemyCombatLogIDSRow(%d+).*$")
	if (not row_index) then return end

	local name = g.idsNamesByIndex[tonumber (row_index)]
	if (not name) then return end

	Enemy.SendChatMessage (L"/target "..name)
end







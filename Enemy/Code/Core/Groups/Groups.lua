local Enemy = Enemy
local g = {}
local ipairs = ipairs
local pairs = pairs
local next = next
local tinsert = table.insert
local mfloor = math.floor
local GetMapPointData = GetMapPointData
local FixString = Enemy.FixString

local MAX_MAP_POINTS = 511
local MAP_POINT_SCAN_BUDGET = 128
local DISTANCE_FIX_COEFFICIENT = 1 / 1.06
local MEMBER_EFFECT_REDRAW_INTERVAL_SECONDS = 0.75
local ROSTER_NAME_CACHE_LIMIT = 256
local GroupsRosterNameCache = {}
local GroupsRosterNameCacheSize = 0
local GroupsLastFullMemberRefreshTime = nil
local GroupsLastFullMemberRefreshPlayers = nil
local GroupsLastFullMemberRefreshType = nil
local GroupsMemberEventRevision = 0
local GroupsLastFullMemberRefreshRevision = nil

-- Cache only the deterministic raw-name conversion, never roster/player data.
-- Keep string and wstring keys exactly as supplied by the client.
local function GroupsNormalizeRosterName (name)
    if (name == nil) then return nil end
    local cached = GroupsRosterNameCache[name]
    if (cached ~= nil) then return cached end

    local normalized = FixString (name)
    if (GroupsRosterNameCacheSize >= ROSTER_NAME_CACHE_LIMIT)
    then
        GroupsRosterNameCache = {}
        GroupsRosterNameCacheSize = 0
    end
    GroupsRosterNameCache[name] = normalized
    GroupsRosterNameCacheSize = GroupsRosterNameCacheSize + 1
    return normalized
end

local function GroupsRefreshScenarioPartyRoles ()
    if (g.groupType ~= Enemy.GroupTypes.Scenario)
    then
        g.scenarioPartyMembers = nil
        return
    end
    if (IsWarBandActive () or GetNumGroupmates () <= 0)
    then
        g.scenarioPartyMembers = {}
        return
    end

    -- Scenario slots carry no leadership role. Use actual party membership;
    -- a missing snapshot is unknown, while an empty snapshot confirms departure.
    local data = PartyUtils.GetPartyData ()
    if (not data) then return end
    local members = {}
    local hasPartyMember = false
    for _, member in ipairs (data)
    do
        if (member.name and member.name ~= L"")
        then
            local name = GroupsNormalizeRosterName (member.name)
            if (name ~= Enemy.playerName)
            then
                members[name] = member.isGroupLeader == true
                hasPartyMember = true
            end
        end
    end
    if (hasPartyMember) then members[Enemy.playerName] = GameData.Player.isGroupLeader == true end
    g.scenarioPartyMembers = members
end

local function GroupsSetScenarioPartyRole (name, isLeader)
    local members = g.scenarioPartyMembers
    if (g.groupType ~= Enemy.GroupTypes.Scenario or not members or members[name] == nil) then return end
    isLeader = isLeader == true
    if (members[name] == isLeader) then return end
    members[name] = isLeader
    -- Also reaches a new party leader who is not present in the scenario.
    Enemy.TriggerEvent ("GroupsLeaderIconUpdated")
end

local GroupsMapScanCursor = 1
local GroupsMapScanSweep = 0
local GroupsActiveMapPlayers = {}

local MapPointTypeFilter =
{
	--[SystemData.MapPips.PLAYER] = true,
	[SystemData.MapPips.GROUP_MEMBER] = true,
	[SystemData.MapPips.WARBAND_MEMBER] = true,
	[SystemData.MapPips.DESTRUCTION_ARMY] = true,
	[SystemData.MapPips.ORDER_ARMY] = true
}

local function GroupsWipeTable (data)
	local key = next (data)

	while (key)
	do
		data[key] = nil
		key = next (data)
	end
end

local function GroupsStartMapSearch (player)
	if (player._enemyMapSearchSweep ~= nil) then return end

	GroupsMapScanCursor = 1
	player._enemyMapSearchSweep = GroupsMapScanSweep
end

local function HasExternalDistanceListeners ()
	if (not Enemy.events) then return false end

	local event = Enemy.events["GroupsPlayerDistanceUpdated"]
	if (not event or not event.keys) then return false end

	for key, _ in pairs (event.keys)
	do
		if (key ~= "UnitFrames" and key ~= "Guard")
		then
			return true
		end
	end

	return false
end

function Enemy.GroupsDistancePollingRequired ()
	if (g.groupType == Enemy.GroupTypes.Solo) then return false end

	if (Enemy.UnitFramesDistanceUpdatesRequired and Enemy.UnitFramesDistanceUpdatesRequired ()) then return true end
	if (Enemy.GuardDistanceUpdatesRequired and Enemy.GuardDistanceUpdatesRequired ()) then return true end
	if (Enemy.GroupIconsDistanceUpdatesRequired and Enemy.GroupIconsDistanceUpdatesRequired ()) then return true end

	return HasExternalDistanceListeners ()
end

local function GroupsMemberRefreshPollingRequired ()
	if (not g.player or not g.player.group) then return false end
	if (g.groupType == Enemy.GroupTypes.Solo) then return false end

	if (Enemy.UnitFramesMemberRefreshPollingRequired and Enemy.UnitFramesMemberRefreshPollingRequired ()) then return true end

	return false
end

local function GroupsGetBuffTargetTypeForPlayer (player)
	if (not player or not g.player or not player.index or player.isSelf) then return nil end
	if (not GameData or not GameData.BuffTargetType) then return nil end

	local index = player.index

	if (g.groupType == Enemy.GroupTypes.Group or index > g.player.index)
	then
		index = index - 1
	end

	if (index < 1) then return nil end

	local update_type = GameData.BuffTargetType.GROUP_MEMBER_START + (index - 1)
	if (update_type > GameData.BuffTargetType.GROUP_MEMBER_END) then return nil end

	return update_type
end

local function GroupsScenarioPlayerDeadStateChanged (player, data)
	if (player.hp == nil or data.health == nil) then return false end

	return (player.hp <= 0) ~= (data.health <= 0)
end

local function GroupsRefreshKnownScenarioPlayerFromData (player_data)
	if (not player_data or not player_data.sgroupindex or not player_data.sgroupslotnum) then return end

	local group = g.groups[player_data.sgroupindex]
	local player = group and group[player_data.sgroupslotnum] or nil
	if (not player or player.isSelf) then return end

	-- Scenario hit events already handle ordinary health changes. Poll only the
	-- dead/alive boundary so AP, morale, and normal HP churn cannot add redraws.
	local changed = GroupsScenarioPlayerDeadStateChanged (player, player_data)
	if (not changed) then return end

	player:LoadFromScenarioData (player_data)
	Enemy.TriggerEvent ("GroupsPlayerUpdated", player)
end

local function GroupsRefreshKnownPlayerFromData (player_data, healthOnly)
    if (not player_data or not player_data.name or player_data.name == L"") then return end

    local player = g.players[GroupsNormalizeRosterName (player_data.name)]
    if (not player or player.isSelf) then return end

    if (healthOnly)
    then
        local hp = player_data.healthPercent
        if (player.hp == nil or hp == nil or (player.hp <= 0) == (hp <= 0)) then return end
        player.hp = hp
        Enemy.TriggerEvent ("GroupsPlayerUpdated", player)
    elseif (player:LoadFromGroupData (player_data))
    then
        Enemy.TriggerEvent ("GroupsPlayerUpdated", player)
    end
end

local function GroupsRefreshMemberStatus (healthOnly)
    if (g.groupType == Enemy.GroupTypes.Scenario)
    then
        local data = GameData.GetScenarioPlayerGroups ()
        if (not data) then return false end

        for _, player_data in ipairs (data)
        do
            GroupsRefreshKnownScenarioPlayerFromData (player_data)
        end

    elseif (g.groupType == Enemy.GroupTypes.Warband)
    then
        local data = PartyUtils.GetWarbandData ()
        if (not data) then return false end

        for _, group_data in ipairs (data)
        do
            for _, player_data in ipairs (group_data.players or {})
            do
                GroupsRefreshKnownPlayerFromData (player_data, healthOnly)
            end
        end

    else
        local data = PartyUtils.GetPartyData ()
        if (not data) then return false end

        for _, player_data in ipairs (data)
        do
            GroupsRefreshKnownPlayerFromData (player_data, healthOnly)
        end
    end
    return true
end

local function GroupsRefreshMembers (healthOnly)
    if (g.updateInProgress) then return end

    Enemy._GroupsForceGroupsUpdateIfNeeded ()
    if (not g.player) then return end

    -- The fixed 1s status pass already covers health when both timers fall in
    -- this exact scheduler tick. Recent events never postpone either timer.
    local players = g.players
    local groupType = g.groupType
    local eventRevision = GroupsMemberEventRevision
    if (healthOnly
        and GroupsLastFullMemberRefreshTime == Enemy.time
        and GroupsLastFullMemberRefreshPlayers == players
        and GroupsLastFullMemberRefreshType == groupType
        and GroupsLastFullMemberRefreshRevision == eventRevision)
    then
        return
    end

    local refreshed = GroupsRefreshMemberStatus (healthOnly)
    if (not healthOnly and refreshed and g.players == players and g.groupType == groupType
        and GroupsMemberEventRevision == eventRevision)
    then
        GroupsLastFullMemberRefreshTime = Enemy.time
        GroupsLastFullMemberRefreshPlayers = players
        GroupsLastFullMemberRefreshType = groupType
        GroupsLastFullMemberRefreshRevision = eventRevision
    end
end

local function GroupsTriggerMemberEffectsUpdated (player, changed)
	local now = Enemy.time or 0

	if (changed)
	then
		player._enemyLastMemberEffectRedraw = now
		Enemy.TriggerEvent ("GroupsPlayerEffectsUpdated", player)
		return
	end

	if (not player._enemyLastMemberEffectRedraw or now - player._enemyLastMemberEffectRedraw >= MEMBER_EFFECT_REDRAW_INTERVAL_SECONDS)
	then
		player._enemyLastMemberEffectRedraw = now
		Enemy.TriggerEvent ("GroupsPlayerEffectsUpdated", player)
	end
end

function Enemy._GroupsKickDistanceScan ()
	GroupsMapScanCursor = 1
end

function Enemy._GroupsOnLocalZoneChanged ()
	local changed = false

	for _, player in pairs (g.players)
	do
		if (player:IsValid () and not player.isSelf and player:RefreshOutOfRegion ())
		then
			changed = true
			Enemy.TriggerEvent ("GroupsPlayerUpdated", player)
		end
	end

	if (changed) then Enemy._GroupsKickDistanceScan () end
end

local function GroupsMarkMissingCrossZonePlayersDistant ()
	local playerZoneId = GameData.Player.zone or 0
	if (playerZoneId <= 0) then return end

	for _, player in pairs (GroupsActiveMapPlayers)
	do
		local searchSweep = player._enemyMapSearchSweep
		local zoneId = player.zoneId or 0

		if (
			not player._enemyMapPointIndex
			and searchSweep ~= nil
			and GroupsMapScanSweep > searchSweep
			and zoneId > 0
			and zoneId ~= playerZoneId
			)
		then
			-- Some packets omit or briefly misreport isInSameRegion. A complete
			-- missing-pip sweep is the fallback proof that this cross-zone member
			-- has no usable local distance. Pin it until its zone/region changes so
			-- the bounded scan does not restart every second.
			if (player:SetOutOfRegion (true))
			then
				Enemy.TriggerEvent ("GroupsPlayerUpdated", player)
			end
		end
	end
end

function Enemy._GroupsDistanceTick ()
	GroupsWipeTable (GroupsActiveMapPlayers)
	local missingPlayers = 0

	-- Cached indexes turn the steady-state scan into one map lookup per active
	-- member. Invalid indexes fall back to the bounded cursor scan below.
	for name, player in pairs (g.players)
	do
		if (player:IsValid () and not player.isSelf and player.isOnline and not player.isOutOfRegion)
		then
			GroupsActiveMapPlayers[name] = player

			local mapPointIndex = player._enemyMapPointIndex
			if (mapPointIndex)
			then
				local mapPoint = GetMapPointData ("EA_Window_OverheadMapMapDisplay", mapPointIndex)
				if (
					mapPoint
					and mapPoint.name == player._enemyMapPointRawName
					and mapPoint.distance ~= nil
					and MapPointTypeFilter[mapPoint.pointType]
					)
				then
					player:SetDistance (mfloor (mapPoint.distance * DISTANCE_FIX_COEFFICIENT))
				else
					player._enemyMapPointIndex = nil
					player._enemyMapPointRawName = nil
					GroupsStartMapSearch (player)
					missingPlayers = missingPlayers + 1
				end
			else
				GroupsStartMapSearch (player)
				missingPlayers = missingPlayers + 1
			end
		end
	end

	if (missingPlayers <= 0)
	then
		return false
	end

	local scanned = 0
	while (scanned < MAP_POINT_SCAN_BUDGET)
	do
		local mapPointIndex = GroupsMapScanCursor
		local mapPoint = GetMapPointData ("EA_Window_OverheadMapMapDisplay", mapPointIndex)
		scanned = scanned + 1

		if (mapPoint and mapPoint.name and mapPoint.distance ~= nil and MapPointTypeFilter[mapPoint.pointType])
		then
			local player = GroupsActiveMapPlayers[FixString (mapPoint.name)]
			if (player and not player._enemyMapPointIndex)
			then
				player._enemyMapPointIndex = mapPointIndex
				player._enemyMapPointRawName = mapPoint.name
				player._enemyMapSearchSweep = nil
				player:SetDistance (mfloor (mapPoint.distance * DISTANCE_FIX_COEFFICIENT))
				missingPlayers = missingPlayers - 1
			end
		end

		GroupsMapScanCursor = GroupsMapScanCursor + 1
		if (GroupsMapScanCursor > MAX_MAP_POINTS)
		then
			GroupsMapScanCursor = 1
			GroupsMapScanSweep = GroupsMapScanSweep + 1
			break
		end

		if (missingPlayers <= 0) then break end
	end

	GroupsMarkMissingCrossZonePlayersDistant ()

	return false
end

--------------------------------------------------------------- Main
function Enemy.GroupsInitialize ()

	Enemy.groups = g
	g.initialized = false

	-- constants
	Enemy.GroupTypes =
	{
		Solo = 0,
		Group = 1,
		Warband = 2,
		Scenario = 3
	}

	Enemy.Archetypes =
	{
		Tank = 1,
		Dps = 2,
		Healer = 3
	}

	Enemy.careerArchetypes =
	{
		[GameData.CareerLine.IRON_BREAKER] = Enemy.Archetypes.Tank,
		[GameData.CareerLine.SWORDMASTER] = Enemy.Archetypes.Tank,
		[GameData.CareerLine.CHOSEN] = Enemy.Archetypes.Tank,
		[GameData.CareerLine.BLACK_ORC] = Enemy.Archetypes.Tank,
		[GameData.CareerLine.KNIGHT] = Enemy.Archetypes.Tank,
		[GameData.CareerLine.BLACKGUARD] = Enemy.Archetypes.Tank,

		[GameData.CareerLine.WITCH_HUNTER] = Enemy.Archetypes.Dps,
		[GameData.CareerLine.WHITE_LION] = Enemy.Archetypes.Dps,
		[GameData.CareerLine.MARAUDER] = Enemy.Archetypes.Dps,
		[GameData.CareerLine.WITCH_ELF] = Enemy.Archetypes.Dps,
		[GameData.CareerLine.BRIGHT_WIZARD] = Enemy.Archetypes.Dps,
		[GameData.CareerLine.MAGUS] = Enemy.Archetypes.Dps,
		[GameData.CareerLine.SORCERER] = Enemy.Archetypes.Dps,
		[GameData.CareerLine.ENGINEER] = Enemy.Archetypes.Dps,
		[GameData.CareerLine.SHADOW_WARRIOR] = Enemy.Archetypes.Dps,
		[GameData.CareerLine.SQUIG_HERDER] = Enemy.Archetypes.Dps,
		[GameData.CareerLine.CHOPPA] = Enemy.Archetypes.Dps,
		[GameData.CareerLine.SLAYER or GameData.CareerLine.HAMMERER] = Enemy.Archetypes.Dps,

		[GameData.CareerLine.WARRIOR_PRIEST] = Enemy.Archetypes.Healer,
		[GameData.CareerLine.DISCIPLE] = Enemy.Archetypes.Healer,
		[GameData.CareerLine.ARCHMAGE] = Enemy.Archetypes.Healer,
		[GameData.CareerLine.SHAMAN] = Enemy.Archetypes.Healer,
		[GameData.CareerLine.RUNE_PRIEST] = Enemy.Archetypes.Healer,
		[GameData.CareerLine.ZEALOT] = Enemy.Archetypes.Healer
	}

	local los_check_bility_ids =
	{
		[GameData.CareerLine.SHAMAN] = 1898, -- Gork'll Fix It
	    [GameData.CareerLine.RUNE_PRIEST] =  1587, -- Grungni's Gift
	    [GameData.CareerLine.DISCIPLE] =  9548, -- Restore Essence
	    [GameData.CareerLine.ARCHMAGE] =  9236, -- Healing Energy
	    [GameData.CareerLine.WARRIOR_PRIEST] =  8238, -- Divine Aid
	    [GameData.CareerLine.ZEALOT] =  8569, -- Flash Of Chaos
	    [GameData.CareerLine.IRON_BREAKER] =  1353, -- Oath Friend
	    [GameData.CareerLine.CHOSEN] =  8325, -- Guard (Chosen)
	    [GameData.CareerLine.SWORDMASTER] =  9008, -- Guard (Swordmaster)
	    [GameData.CareerLine.BLACK_ORC] =  1674, -- Save Da Runts
	    [GameData.CareerLine.KNIGHT] =  8013, -- Guard (Knight of the Blazing Sun)
	    [GameData.CareerLine.BLACKGUARD] =  9325, -- Guard (Black Guard)
	}
	g.losCheckAbilityId = los_check_bility_ids[GameData.Player.career.line]

	Enemy._GroupsInitializeCustomEffectFilters ()
	Enemy._GroupsReset ()

	-- UI: effect filter dialog
	CreateWindow ("EnemyEffectFilterDialog", false)

	-- events
	RegisterEventHandler (SystemData.Events.PLAYER_CUR_HIT_POINTS_UPDATED, "Enemy.Groups_OnCurrentPlayerUpdated")
	RegisterEventHandler (SystemData.Events.PLAYER_MAX_HIT_POINTS_UPDATED, "Enemy.Groups_OnCurrentPlayerUpdated")
	RegisterEventHandler (SystemData.Events.PLAYER_CUR_ACTION_POINTS_UPDATED, "Enemy.Groups_OnCurrentPlayerUpdated")
	RegisterEventHandler (SystemData.Events.PLAYER_MAX_ACTION_POINTS_UPDATED, "Enemy.Groups_OnCurrentPlayerUpdated")
	RegisterEventHandler (SystemData.Events.PLAYER_CAREER_RANK_UPDATED, "Enemy.Groups_OnCurrentPlayerUpdated")
	RegisterEventHandler (SystemData.Events.PLAYER_MORALE_UPDATED, "Enemy.Groups_OnCurrentPlayerUpdated")
    RegisterEventHandler (SystemData.Events.PLAYER_GROUP_LEADER_STATUS_UPDATED, "Enemy.Groups_OnCurrentPlayerUpdated")

	RegisterEventHandler (SystemData.Events.PLAYER_COMBAT_FLAG_UPDATED, "Enemy.Groups_OnCurrentPlayerCombatFlagUpdated")
	RegisterEventHandler (SystemData.Events.PLAYER_RVR_FLAG_UPDATED, "Enemy.Groups_OnCurrentPlayerUpdated")

	RegisterEventHandler (SystemData.Events.PLAYER_TARGET_UPDATED, "Enemy.OnPlayerTargetUpdated")
	RegisterEventHandler (SystemData.Events.SHOW_ALERT_TEXT, "Enemy.Groups_OnShowAlertText")

	RegisterEventHandler (SystemData.Events.PLAYER_PET_HEALTH_UPDATED, "Enemy.Groups_OnPlayerPetHealthUpdated")
--	RegisterEventHandler (SystemData.Events.PLAYER_PET_UPDATED, "Enemy.Groups_OnPlayerPetUpdated")

	RegisterEventHandler (SystemData.Events.SCENARIO_BEGIN, "Enemy.GroupsUpdateTypeScheduled")
	RegisterEventHandler (SystemData.Events.SCENARIO_END, "Enemy.GroupsUpdateTypeScheduled")
	RegisterEventHandler (SystemData.Events.SCENARIO_GROUP_JOIN, "Enemy.GroupsUpdateTypeScheduled")
	RegisterEventHandler (SystemData.Events.SCENARIO_GROUP_LEAVE, "Enemy.GroupsUpdateTypeScheduled")

	RegisterEventHandler(SystemData.Events.CITY_SCENARIO_BEGIN, "Enemy.GroupsUpdateTypeScheduled")
	RegisterEventHandler(SystemData.Events.CITY_SCENARIO_END, "Enemy.GroupsUpdateTypeScheduled")

	RegisterEventHandler (SystemData.Events.SCENARIO_PLAYERS_LIST_GROUPS_UPDATED, "Enemy.GroupsUpdate")
	RegisterEventHandler (SystemData.Events.SCENARIO_PLAYERS_LIST_RESERVATIONS_UPDATED, "Enemy.GroupsUpdate")

	RegisterEventHandler (SystemData.Events.SCENARIO_PLAYER_HITS_UPDATED, "Enemy.Groups_OnScenarioPlayerHitsUpdated")

	RegisterEventHandler (SystemData.Events.GROUP_UPDATED, "Enemy.GroupsUpdateTypeScheduled")
	RegisterEventHandler (SystemData.Events.GROUP_PLAYER_ADDED, "Enemy.GroupsUpdate")
	RegisterEventHandler (SystemData.Events.GROUP_STATUS_UPDATED, "Enemy.Groups_OnGroupStatusUpdated")

	RegisterEventHandler (SystemData.Events.BATTLEGROUP_UPDATED, "Enemy.GroupsUpdateTypeScheduled")
	RegisterEventHandler (SystemData.Events.BATTLEGROUP_MEMBER_UPDATED, "Enemy.Groups_OnBattlegroupMemberUpdated")

	RegisterEventHandler (SystemData.Events.PLAYER_TARGET_EFFECTS_UPDATED, "Enemy.Groups_OnPlayerTargetEffectsUpdated")
	RegisterEventHandler (SystemData.Events.PLAYER_EFFECTS_UPDATED, "Enemy.Groups_OnCurrentPlayerEffectsUpdated")
	RegisterEventHandler (SystemData.Events.GROUP_EFFECTS_UPDATED, "Enemy.Groups_OnGroupEffectUpdated")

	RegisterEventHandler (SystemData.Events.PLAYER_ZONE_CHANGED, "Enemy.GroupsCheckTarget")
	RegisterEventHandler (SystemData.Events.PLAYER_ZONE_CHANGED, "Enemy._GroupsOnLocalZoneChanged")
	if (SystemData.Events.PLAYER_RVRLAKE_CHANGED)
	then
		RegisterEventHandler (SystemData.Events.PLAYER_RVRLAKE_CHANGED, "Enemy._GroupsOnLocalZoneChanged")
	end
	if (SystemData.Events.PLAYER_AREA_CHANGED)
	then
		RegisterEventHandler (SystemData.Events.PLAYER_AREA_CHANGED, "Enemy._GroupsOnLocalZoneChanged")
	end

	if (g.losCheckAbilityId)
	then
		Enemy.AddTaskAction ("groups los check", function ()

			if (g.target and not g.target.isSelf)
			then
				g.target:SetLOS (not IsTargetValid (g.losCheckAbilityId))
			end

			return false
		end)
	end

	Enemy.GroupsUpdateType ()
	Enemy.TriggerEvent ("GroupsInitialized")

	EnemyTimer.New ("groups distance check", 1, function ()

		if (GroupsMemberRefreshPollingRequired ())
		then
			GroupsRefreshMembers ()
		end

		if (Enemy.GroupsDistancePollingRequired ())
		then
			Enemy._GroupsDistanceTick ()
		end

		return false
	end)

    EnemyTimer.New ("groups member health check", 0.5, function ()
        if (GroupsMemberRefreshPollingRequired ())
        then
            GroupsRefreshMembers (true)
        end
        return false
    end)
end


function Enemy._GroupsReset ()

    GroupsRosterNameCache = {}
    GroupsRosterNameCacheSize = 0
    GroupsLastFullMemberRefreshTime = nil
    GroupsLastFullMemberRefreshPlayers = nil
    GroupsLastFullMemberRefreshType = nil
    GroupsLastFullMemberRefreshRevision = nil

	g.groups = {}
	g.groupsPlayersCount = {}
	g.ungroupedPlayers = {}

	for group_index = 1, Enemy.MaxGroups
	do
		tinsert (g.groups, {})
		g.groupsPlayersCount[group_index] = 0
	end

	g.players = {}
	g.target = nil
end


local function GroupsUpdateTypeTask ()
    Enemy.GroupsUpdateType ()
    return true
end


function Enemy.GroupsUpdateTypeScheduled ()

	if (Enemy.GetTask ("groups type update")) then return end

	Enemy.AddTaskAction ("groups type update", GroupsUpdateTypeTask)
end


function Enemy.GroupsUpdateType ()

	-- determine group type
	local new_group_type = Enemy.GroupTypes.Solo

	if (GetNumGroupmates () > 0)
	then
		new_group_type = Enemy.GroupTypes.Group
	end

	if (IsWarBandActive ())
	then
		new_group_type = Enemy.GroupTypes.Warband
	end

	if (GameData.Player.isInScenario and GameData.Player.isInSiege)
	then
		new_group_type = Enemy.GroupTypes.Warband
	end

	if (GameData.Player.isInScenario or GameData.Player.isInSiege)
	then
		new_group_type = Enemy.GroupTypes.Scenario
	end

	if (new_group_type ~= g.groupType)
	then
		Enemy._GroupsReset ()
		Enemy.TriggerEvent ("GroupsTypeUpdated", new_group_type, g.groupType)
	end

	g.groupType = new_group_type

	Enemy.GroupsCheckTarget ()
	Enemy.GroupsUpdate ()
end


function Enemy.GroupsGetMaxGroups ()

	if (g.groupType == Enemy.GroupTypes.Warband or g.groupType == Enemy.GroupTypes.Scenario)
	then
		return Enemy.MaxGroups
	end

	return 1
end


function Enemy.IsPlayerInGroup ()
	return
		(
			g.groupType == Enemy.GroupTypes.Group
			or
			g.groupType == Enemy.GroupTypes.Warband
			or
			(
				g.groupType == Enemy.GroupTypes.Scenario
				and
				g.player.group
			)
		)
end


local function GroupsUpdateTask ()
    Enemy._GroupsUpdate ()
    return true
end


function Enemy.GroupsUpdate ()

	-- shedule groups update
	if (Enemy.GetTask ("groups sheduled update")) then return end

	Enemy.AddTaskAction ("groups sheduled update", GroupsUpdateTask)
end


function Enemy._GroupsForceGroupsUpdateIfNeeded ()

	if (Enemy.GetTask ("groups sheduled update") and not g.updateInProgress)
	then
		Enemy.RemoveTask ("groups sheduled update")
		Enemy._GroupsUpdate ()
	end
end


function Enemy._GroupsUpdate ()

	if (g.updateInProgress) then return end
	g.updateInProgress = true

	local old_player = g.player
	local old_players = g.players or {}
	local need_load_self

	local old_target_name = nil
	if (g.target)
	then
		old_target_name = g.target.name
	end

	local player_group_index = nil
	if (old_player) then player_group_index = old_player.groupIndex end

	if (g.groupType == Enemy.GroupTypes.Scenario)
	then
		-- in scenario

		local data = GameData.GetScenarioPlayerGroups ()
		if (not data)
		then
			g.updateInProgress = false
			Enemy.ReconcilePlayerEffectsExpiry (g.players)
			return
		end

		Enemy._GroupsReset ()

		for _, player_data in ipairs (data)
		do
            local name = GroupsNormalizeRosterName (player_data.name)
			local player = old_players[name]
			if (not player) then player = EnemyPlayer.New (name) end

			player:LoadFromScenarioData (player_data, true)

			if (not player:IsValid ()) then continue end

			g.players[player.name] = player

			if (player_data.sgroupindex > 0)
			then
				local group = g.groups[player_data.sgroupindex]

				player.group = group
				player.index = player_data.sgroupslotnum
				player.groupIndex = player_data.sgroupindex

				group[player.index] = player
			else
				player.index = nil
				player.group = nil
				player.groupIndex = nil

				tinsert (g.ungroupedPlayers, player)
			end
		end

		need_load_self = true

	elseif (g.groupType == Enemy.GroupTypes.Warband)
	then
		-- warband
		local data = PartyUtils.GetWarbandData ()
		if (not data)
		then
			g.updateInProgress = false
			Enemy.ReconcilePlayerEffectsExpiry (g.players)
			return
		end

		Enemy._GroupsReset ()

		for group_index, group_data in ipairs (data)
		do
			local group = g.groups[group_index]

			for player_index, player_data in ipairs (group_data.players)
			do
                local name = GroupsNormalizeRosterName (player_data.name)
				local player = old_players[name]
				if (not player) then player = EnemyPlayer.New (name) end

				player:LoadFromWarbandData (player_data, true)

				if (not player:IsValid ()) then continue end

				player.group = group
				player.index = player_index
				player.groupIndex = group_index

				g.players[player.name] = player
				group[player.index] = player
			end
		end

		need_load_self = true

	else
		-- group or solo

		local data = PartyUtils.GetPartyData ()
		if (not data)
		then
			g.updateInProgress = false
			Enemy.ReconcilePlayerEffectsExpiry (g.players)
			return
		end

		Enemy._GroupsReset ()

		local player = old_player
		if (not player) then player = EnemyPlayer.New (Enemy.playerName) end

		player:LoadFromCurrentPlayer (true)

		local group = g.groups[1]
		player.group = group
		player.index = 1
		player.groupIndex = 1

		g.players[player.name] = player
		group[1] = player

		for player_index, player_data in ipairs (data)
		do
			if player_data.name and player_data.name ~= L"" then
                local name = GroupsNormalizeRosterName (player_data.name)
				player = old_players[name]
				if (not player) then player = EnemyPlayer.New (name) end

				player:LoadFromGroupData (player_data, true)

				if (not player:IsValid ()) then continue end

				player.group = group
				player.index = player_index + 1
				player.groupIndex = 1

				g.players[player.name] = player
				group[player.index] = player
			end
		end

		need_load_self = false
	end

	g.player = g.players[Enemy.playerName]

	if (g.player)
	then
		if (need_load_self)
		then
			g.player:LoadFromCurrentPlayer (true)
		end

		for _, player in pairs (g.players)
		do
			player.isSelf = (player == g.player)
			player.isInPlayerGroup = (player.groupIndex ~= nil and player.groupIndex == g.player.groupIndex)

			if (player:IsInGroup())
			then
				g.groupsPlayersCount[player.groupIndex] = g.groupsPlayersCount[player.groupIndex] + 1
			end
		end

        GroupsRefreshScenarioPartyRoles ()
		Enemy.ReconcilePlayerEffectsExpiry (g.players)

		if (not g.initialized)
		then
			g.initialized = true

			-- update can cleanse
			if (g.player.career == GameData.CareerLine.BRIGHT_WIZARD)
			then
				g.canCleanse = "self"
				g.canCleanseHex = true
				g.canCleanseAilment = true
				g.canCleanseCurse = true

			elseif (g.player.career == GameData.CareerLine.WARRIOR_PRIEST or g.player.career == GameData.CareerLine.ZEALOT)
			then
				g.canCleanse = "all"
				g.canCleanseHex = true
				g.canCleanseAilment = false
				g.canCleanseCurse = true

			elseif (g.player.career == GameData.CareerLine.DISCIPLE or g.player.career == GameData.CareerLine.ARCHMAGE)
			then
				g.canCleanse = "all"
				g.canCleanseHex = true
				g.canCleanseAilment = true
				g.canCleanseCurse = false

			elseif (g.player.career == GameData.CareerLine.SHAMAN or g.player.career == GameData.CareerLine.RUNE_PRIEST)
			then
				g.canCleanse = "all"
				g.canCleanseHex = false
				g.canCleanseAilment = true
				g.canCleanseCurse = true

			else

				g.canCleanse = nil
				g.canCleanseHex = false
				g.canCleanseAilment = false
				g.canCleanseCurse = false
			end

			Enemy.TriggerEvent ("GroupsPlayerInitialized", g.player)
			Enemy.UpdateEffects ()
		end

		g.target = g.players[old_target_name]

		Enemy.TriggerEvent ("GroupsUpdated", player_group_index ~= g.player.groupIndex)

		-- Region changes discovered while rebuilding are deferred until every
		-- player has been rebound and GroupsUpdated consumers have reconciled
		-- their own roster caches. Guard and external distance listeners can
		-- then safely resolve the complete group from the narrow event.
		for _, player in pairs (g.players)
		do
			player:FlushDistanceEvent ()
		end
	else
		Enemy.ReconcilePlayerEffectsExpiry (g.players)
	end

	g.updateInProgress = false
end


function Enemy.UpdateEffects ()

	if (not g.player) then return end

	Enemy.Groups_OnCurrentPlayerEffectsUpdated (GetBuffs (GameData.BuffTargetType.SELF), true)

	if (g.player.group)
	then
		for k = 1, 6
		do
			local player = g.player.group[k]
			if (not player or player.isSelf) then continue end

			local update_type = GroupsGetBuffTargetTypeForPlayer (player)
			if (update_type)
			then
				Enemy.Groups_OnGroupEffectUpdated (update_type, GetBuffs (update_type), true)
			end
		end
	end
end


local GroupsBattlegroupMemberBurst = {}

function Enemy._GroupsUpdateBattlegroupMember (groupIndex, memberIndex)

    GroupsMemberEventRevision = GroupsMemberEventRevision + 1

	local player_data = PartyUtils.GetWarbandMember (groupIndex, memberIndex)
	if (not player_data or not player_data.name or player_data.name == L"") then return end

	local group = g.groups[groupIndex]
	local player = group and group[memberIndex] or nil
    local name = GroupsNormalizeRosterName (player_data.name)

	if (not player or player.name ~= name)
	then
		Enemy.GroupsUpdate ()
		return
	end

	if (player:LoadFromGroupData (player_data))
	then
		Enemy.TriggerEvent ("GroupsPlayerUpdated", player)
	end
end

local function GroupsDrainBattlegroupMembers ()
	Enemy._GroupsForceGroupsUpdateIfNeeded ()

	for key, hasRepeat in pairs (GroupsBattlegroupMemberBurst)
	do
		if (hasRepeat)
		then
			local groupIndex = mfloor (key / 10)
			Enemy._GroupsUpdateBattlegroupMember (groupIndex, key - groupIndex * 10)
		end
	end

	GroupsWipeTable (GroupsBattlegroupMemberBurst)
	return true
end

function Enemy.Groups_OnBattlegroupMemberUpdated (groupIndex, memberIndex)

	if (not groupIndex or not memberIndex) then return end

	local key = groupIndex * 10 + memberIndex
	local drainScheduled = Enemy.GetTask ("groups member updates") ~= nil

	if (drainScheduled)
	then
		if (GroupsBattlegroupMemberBurst[key] ~= nil)
		then
			GroupsBattlegroupMemberBurst[key] = true
		else
			GroupsBattlegroupMemberBurst[key] = false
			Enemy._GroupsUpdateBattlegroupMember (groupIndex, memberIndex)
		end
		return
	end

	GroupsWipeTable (GroupsBattlegroupMemberBurst)
	GroupsBattlegroupMemberBurst[key] = false

	Enemy.AddTaskAction ("groups member updates", GroupsDrainBattlegroupMembers)

	-- Preserve immediate delivery for each member's first packet in a burst.
	-- Repeats for the same member collapse into the deferred drain above.
	Enemy._GroupsForceGroupsUpdateIfNeeded ()
	Enemy._GroupsUpdateBattlegroupMember (groupIndex, memberIndex)
end


function Enemy.Groups_OnScenarioPlayerHitsUpdated (groupIndex, groupSlotNum, hits)

    GroupsMemberEventRevision = GroupsMemberEventRevision + 1

	Enemy._GroupsForceGroupsUpdateIfNeeded ()
	if (g.groupType ~= Enemy.GroupTypes.Scenario or not g.groups) then return end


	local group = g.groups[groupIndex]
	if (not group) then return end

	local player = group[groupSlotNum]
	if (not player) then return end

	if (player.hp ~= hits)
	then
		player.hp = hits
		Enemy.TriggerEvent ("GroupsPlayerUpdated", player)
	end
end


function Enemy.Groups_OnGroupStatusUpdated (memberIndex)

    GroupsMemberEventRevision = GroupsMemberEventRevision + 1

	Enemy._GroupsForceGroupsUpdateIfNeeded ()

	local player_data = PartyUtils.GetPartyMember (memberIndex)
	if (not player_data or not player_data.name or player_data.name == L"") then return end

    local name = GroupsNormalizeRosterName (player_data.name)
    GroupsSetScenarioPartyRole (name, player_data.isGroupLeader)
    local player = g.players[name]
	if (not player) then return end

    -- Party status still supplies fresh health, but warband role flags belong
    -- to the warband roster/member updates, not the separate party snapshot.
    if (player:LoadFromGroupData (player_data, nil, g.groupType == Enemy.GroupTypes.Warband))
	then
		Enemy.TriggerEvent ("GroupsPlayerUpdated", player)
	end
end


function Enemy.Groups_OnCurrentPlayerUpdated ()

	Enemy._GroupsForceGroupsUpdateIfNeeded ()
	if (not g.player) then return end
    GroupsSetScenarioPartyRole (Enemy.playerName, GameData.Player.isGroupLeader)

	if (g.player:LoadFromCurrentPlayer ())
	then
		Enemy.TriggerEvent ("GroupsPlayerUpdated", g.player)
	end
end


function Enemy.Groups_OnPlayerPetHealthUpdated ()

	Enemy._GroupsForceGroupsUpdateIfNeeded ()
	if (not g.player) then return end

	if (g.player:LoadPetFromCurrentPlayer ())
	then
		Enemy.TriggerEvent ("GroupsPlayerPetUpdated", g.player)
	end
end


function Enemy.Groups_OnCurrentPlayerCombatFlagUpdated ()

	Enemy._GroupsForceGroupsUpdateIfNeeded ()
	if (not g.player) then return end

	if (g.player.isInCombat ~= GameData.Player.inCombat)
	then
		g.player.isInCombat = GameData.Player.inCombat
		Enemy.TriggerEvent ("GroupsPlayerCombatUpdated", g.player)
	end
end


function Enemy.GroupsCheckTarget ()

	TargetInfo:UpdateFromClient ()

	if (not TargetInfo:UnitName (TargetInfo.FRIENDLY_TARGET))
	then
		Enemy._GroupsClearTarget ()
	end
end


function Enemy._GroupsClearTarget ()
	if (not g.target) then return end

	g.target:SetSelected (false)
	Enemy.TriggerEvent ("GroupsTargetChanged", g.target, nil)
	g.target = nil
end


local function GroupsFinishPlayerTargetUpdate (player, is_friendly_target)

	if (is_friendly_target)
	then
		player:SetSelected (true)

		if (g.losCheckAbilityId)
		then
			player:SetLOS (not IsTargetValid (g.losCheckAbilityId), true)
		end
	end

	Enemy.TriggerEvent ("GroupsPlayerUpdated", player)

	if (is_friendly_target)
	then
		local old_target = g.target
		if (old_target ~= player)
		then
			if (old_target)
			then
				old_target:SetSelected (false)
			end

			g.target = player

			Enemy.TriggerEvent ("GroupsTargetChanged", old_target, g.target)
		end
	end
end


function Enemy.Groups_OnPlayerTargetUpdated (target_classification, target_id, _target_type)

	if (target_classification == nil or target_id == nil or target_classification == TargetInfo.HOSTILE_TARGET) then return end

	local is_friendly_target = (target_classification == TargetInfo.FRIENDLY_TARGET)

	if (target_id == 0)
	then
		if (is_friendly_target) then Enemy._GroupsClearTarget () end
		return
	end

	TargetInfo:UpdateFromClient ()

	if (TargetInfo:UnitHealth (target_classification) == 0 and target_classification == "mouseovertarget")
	then
		return
	end

	Enemy._GroupsForceGroupsUpdateIfNeeded ()
	if (not g.player)
	then
		if (is_friendly_target) then Enemy._GroupsClearTarget () end
		return
	end

	local name = Enemy.FixString (TargetInfo:UnitName (target_classification))
	local player = g.players[name]

	if (not player)
	then
		if (is_friendly_target) then Enemy._GroupsClearTarget () end
		return
	end

	player:LoadFromTarget (target_classification, target_id)
	GroupsFinishPlayerTargetUpdate (player, is_friendly_target)
end


function Enemy._GroupsApplyPlayerTargetSnapshot (target)

	if (
			type (target) ~= "table"
			or target._groupsSnapshotReady ~= true
			or target.id == nil
			or target.type == nil
			or target.name == nil
			or target.career == nil
			or target.level == nil
			or target.hp == nil
			or type (target.entityId) ~= "number"
			or type (target.hp) ~= "number"
			or type (target.career) ~= "number"
			or type (target.level) ~= "number"
			or target.id == 0
			or target.type == TargetInfo.HOSTILE_TARGET
		)
	then
		return
	end

	local is_friendly_target = (target.type == TargetInfo.FRIENDLY_TARGET)

	if (target.hp == 0 and target.type == "mouseovertarget") then return end

	Enemy._GroupsForceGroupsUpdateIfNeeded ()
	if (not g.player)
	then
		if (is_friendly_target) then Enemy._GroupsClearTarget () end
		return
	end

	local player = g.players[target.name]

	if (not player)
	then
		if (is_friendly_target) then Enemy._GroupsClearTarget () end
		return
	end

	player.name = target.name
	player.career = target.career
	player.level = target.level
	player.hp = target.hp

	player.zoneId = GameData.Player.zone or 0
	player:SetObjectWorldId (target.entityId)

	player.isOnline = true

	GroupsFinishPlayerTargetUpdate (player, is_friendly_target)
end


function Enemy.Groups_OnShowAlertText ()

	for _, v in ipairs (SystemData.AlertText.VecText)
	do
        local name = v:match (GetStringFormat (StringTables.Default.TEXT_TARGET_PLAYER_ERROR, {L"(%S+)"}))
        if (not name) then continue end

        local player = g.players[Enemy.FixString (name)]
        if (not player) then continue end

        player:SetDistant (true)
    end
end


function Enemy.Groups_OnCurrentPlayerEffectsUpdated (updatedEffects, isFullList)


	if (not updatedEffects) then return end
	Enemy._GroupsForceGroupsUpdateIfNeeded ()
	if (not g.player) then return end

	if (g.player:LoadEffects (updatedEffects, isFullList))
	then
		Enemy.TriggerEvent ("GroupsPlayerEffectsUpdated", g.player)
	end
end


function Enemy.Groups_OnPlayerTargetEffectsUpdated (updateType, updatedEffects, isFullList)


	if (not updatedEffects or updateType ~= GameData.BuffTargetType.TARGET_FRIENDLY) then return end
	Enemy._GroupsForceGroupsUpdateIfNeeded ()

	local name = Enemy.FixString (TargetInfo:UnitName (TargetInfo.FRIENDLY_TARGET))
	local player = g.players[name]
	if (not player) then return end

	GroupsTriggerMemberEffectsUpdated (player, player:LoadEffects (updatedEffects, isFullList))
end


function Enemy.Groups_OnGroupEffectUpdated (updateType, updatedEffects, isFullList)


	if (not updatedEffects
		or
		updateType < GameData.BuffTargetType.GROUP_MEMBER_START
		or
		updateType > GameData.BuffTargetType.GROUP_MEMBER_END)
	then
		return
	end

	Enemy._GroupsForceGroupsUpdateIfNeeded ()
	if (not g.player or not g.player.group) then return end

	local index = updateType - GameData.BuffTargetType.GROUP_MEMBER_START + 1
	if (g.groupType == Enemy.GroupTypes.Group or index >= g.player.index)
	then
		index = index + 1
	end

	local player = g.player.group[index]
	if (not player) then return end

	GroupsTriggerMemberEffectsUpdated (player, player:LoadEffects (updatedEffects, isFullList))
end


--------------------------------------------------------------- Debug

function Enemy._GroupsDebugGetEffectsNames (effects)

	if (not effects) then return end

	local res = L""

	for _, effect in pairs (effects)
	do
		if (res:len() > 0)
		then
			res = res..L", "
		end

		res = res..L"#"..towstring (effect.abilityId)..L" "..effect.name

		if (effect.duration > 0)
		then
			res = res..L" "..towstring (Enemy.Round (effect.duration / 60.0, 1))..L"s"
		end

		if (effect.castByPlayer)
		then
			res = res..L" (mine)"
		end
	end

	return res
end


function Enemy.PrintEffects (groupIndex, playerIndex)

	local player

	if (type (groupIndex) == "string" or type (groupIndex) == "wstring")
	then
		groupIndex = Enemy.toWStringOrEmpty (groupIndex)
		player = g.players[groupIndex]

		if (not player)
		then
			Enemy.Print (L"Player '"..groupIndex..L"' not found.")
			return
		end

	elseif (groupIndex and playerIndex)
	then
		player = g.groups[groupIndex][playerIndex]

		if (not player)
		then
			Enemy.Print (L"Player with group index "..Enemy.toWStringOrEmpty (groupIndex)..L" and player index "..Enemy.toWStringOrEmpty (playerIndex)..L" not found.")
			return
		end
	else
		player = groupIndex
	end

	if (not player)
	then
		Enemy.Print ("Player not found.")
		return
	end

	Enemy.Print (player.name..L": "..Enemy._GroupsDebugGetEffectsNames (player.effects))
end


function Enemy._GroupsDebugEffects (text)

	if (not g.debugTarget) then return end
	Enemy.DebugClear ()

	if (text)
	then
		Enemy.DebugAdd (text)
	end

	if (g.groupType == Enemy.GroupTypes.Solo)
	then
		Enemy.DebugAdd ("Solo")
	elseif (g.groupType == Enemy.GroupTypes.Group)
	then
		Enemy.DebugAdd ("Group")
	elseif (g.groupType == Enemy.GroupTypes.Scenario)
	then
		Enemy.DebugAdd ("Scenario")
	else
		Enemy.DebugAdd ("Warband")
	end

	local player = g.players[g.debugTarget]
	if (not player) then return end

	Enemy.DebugAdd (player.name)
	Enemy.DebugAdd ("---------------------------------")

	for _, effect in pairs (player.effects)
	do
		local str = effect.name

		if (effect.castByPlayer)
		then
			str = str..L" (mine)"
		end

		Enemy.DebugAdd (str)
	end
end

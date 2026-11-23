local Enemy = Enemy
local g = {}

local CHECK_INTERVAL_SECONDS = 5
local PARTY_WINDOW_NAME = "GroupWindow"

local PARTY_EFFECT_HANDLERS =
{
	{ SystemData.Events.GROUP_EFFECTS_UPDATED, "GroupWindow.OnEffectsUpdated" }
}

local LEGACY_PARTY_REPAIR_HANDLERS =
{
	{ SystemData.Events.GROUP_UPDATED, "GroupWindow.OnGroupUpdated" },
	{ SystemData.Events.BATTLEGROUP_UPDATED, "GroupWindow.OnGroupUpdated" },
	{ SystemData.Events.GROUP_STATUS_UPDATED, "GroupWindow.OnStatusUpdated" },
	{ SystemData.Events.GROUP_EFFECTS_UPDATED, "GroupWindow.OnEffectsUpdated" },
	{ SystemData.Events.GROUP_PLAYER_ADDED, "GroupWindow.OnGroupPlayerAdded" },
	{ SystemData.Events.SCENARIO_BEGIN, "GroupWindow.OnScenarioBegin" },
	{ SystemData.Events.CITY_SCENARIO_BEGIN, "GroupWindow.OnScenarioBegin" },
	{ SystemData.Events.SCENARIO_END, "GroupWindow.OnScenarioEnd" },
	{ SystemData.Events.CITY_SCENARIO_END, "GroupWindow.OnScenarioEnd" },
	{ SystemData.Events.SCENARIO_GROUP_JOIN, "GroupWindow.OnScenarioGroupJoin" },
	{ SystemData.Events.SCENARIO_GROUP_LEAVE, "GroupWindow.OnScenarioGroupLeave" }
}

local LEGACY_WARBAND_REPAIR_HANDLERS =
{
	{ SystemData.Events.SCENARIO_BEGIN, "BattlegroupHUD.OnScenarioBegin" },
	{ SystemData.Events.CITY_SCENARIO_BEGIN, "BattlegroupHUD.OnScenarioBegin" },
	{ SystemData.Events.SCENARIO_END, "BattlegroupHUD.OnScenarioEnd" },
	{ SystemData.Events.CITY_SCENARIO_END, "BattlegroupHUD.OnScenarioEnd" },
	{ SystemData.Events.BATTLEGROUP_UPDATED, "BattlegroupHUD.Update" },
	{ SystemData.Events.BATTLEGROUP_MEMBER_UPDATED, "BattlegroupHUD.SingleMemberUpdate" }
}

local function WindowExists (windowName)
	if (DoesWindowExist) then return DoesWindowExist (windowName) end
	return true
end

local function IsLayoutWindowRegistered (windowName)
	if (not LayoutEditor or not LayoutEditor.windowsList) then return false end
	return LayoutEditor.windowsList[windowName] ~= nil
end

local function IsLayoutWindowUserHidden (windowName)
	if (not WindowExists (windowName)) then return false end

	if (LayoutEditor and LayoutEditor.windowsList)
	then
		local window_data = LayoutEditor.windowsList[windowName]
		return window_data ~= nil and window_data.isUserHidden == true
	end

	if (LayoutEditor and LayoutEditor.IsWindowUserHidden)
	then
		return LayoutEditor.IsWindowUserHidden (windowName) == true
	end

	return false
end

local function EnemyUnitFramesEnabled ()
	if (Enemy.unitFrames and Enemy.unitFrames.isPluginEnabled ~= nil) then
		return Enemy.unitFrames.isPluginEnabled == true
	end

	return Enemy.Settings and Enemy.Settings.unitFramesEnabled == true
end

local function CleanupEnabled ()
	return Enemy.Settings and Enemy.Settings.unitFramesReduceHiddenDefaultFrameUpdates == true
end

local function FeatureActive ()
	return CleanupEnabled () and EnemyUnitFramesEnabled ()
end

local function GetHiddenFramesText ()
	return "Default party frames are hidden"
end

local function GetEventStatusText ()
	return "Enemy has disabled the default party effects refresh handler"
end

local function SetHandlersEnabled (handlers, enabled)
	for _, handler in ipairs (handlers)
	do
		if (enabled)
		then
			RegisterEventHandler (handler[1], handler[2])
		else
			UnregisterEventHandler (handler[1], handler[2])
		end
	end
end

local function NormalizeHandlersEnabled (handlers)
	for _, handler in ipairs (handlers)
	do
		UnregisterEventHandler (handler[1], handler[2])
		RegisterEventHandler (handler[1], handler[2])
	end
end

local function MarkLegacyRepairDone ()
	if (Enemy.Settings) then Enemy.Settings.unitFramesDefaultFrameHandlersRepaired = true end
end

-- Earlier cleanup builds disabled broad default handlers; normalize them once for profiles that still have that cleanup enabled.
local function RepairLegacyDisabledHandlers ()
	if (not Enemy.Settings or Enemy.Settings.unitFramesDefaultFrameHandlersRepaired == true) then return end

	if (Enemy.Settings.unitFramesReduceHiddenDefaultFrameUpdates ~= true)
	then
		MarkLegacyRepairDone ()
		return
	end

	if (type (GroupWindow) ~= "table" or type (BattlegroupHUD) ~= "table") then return end

	NormalizeHandlersEnabled (LEGACY_PARTY_REPAIR_HANDLERS)
	NormalizeHandlersEnabled (LEGACY_WARBAND_REPAIR_HANDLERS)
	MarkLegacyRepairDone ()
end

local function RestoreDisabledHandlers ()
	if (g.partyEffectHandlersEnabled == false)
	then
		SetHandlersEnabled (PARTY_EFFECT_HANDLERS, true)
		g.partyEffectHandlersEnabled = true
	end
end

local function StopRefreshTimer ()
	if (not g.refreshTimer) then return end

	g.refreshTimer:Remove ()
	g.refreshTimer = nil
end

local function StartRefreshTimer ()
	if (g.refreshTimer) then return end

	g.refreshTimer = EnemyTimer.New ("default frame event refresh", CHECK_INTERVAL_SECONDS, function ()
		Enemy.DefaultFrameEventsRefresh ()
		return false
	end)
end

local function RefreshPartyEffectHandlers ()
	if (type (GroupWindow) ~= "table" or not IsLayoutWindowRegistered (PARTY_WINDOW_NAME)) then return end

	if (g.partyEffectHandlersEnabled == nil) then g.partyEffectHandlersEnabled = true end

	local user_hidden = IsLayoutWindowUserHidden (PARTY_WINDOW_NAME)
	local should_enable = not user_hidden

	if (should_enable ~= g.partyEffectHandlersEnabled)
	then
		SetHandlersEnabled (PARTY_EFFECT_HANDLERS, should_enable)
		g.partyEffectHandlersEnabled = should_enable
	end

	if (user_hidden and not should_enable)
	then
		return true
	end
end

local function PrintStartupNotice (party_status)
	if (not Enemy.Print or not party_status) then return end

	Enemy.Print ("Enemy unit frames are enabled. "..GetHiddenFramesText ().." in Layout Editor; "..GetEventStatusText ()..".")
end

function Enemy.DefaultFrameEventsRefresh ()
	RepairLegacyDisabledHandlers ()

	if (not FeatureActive ())
	then
		RestoreDisabledHandlers ()
		StopRefreshTimer ()
		return nil, nil
	end

	StartRefreshTimer ()

	local party_status = RefreshPartyEffectHandlers ()

	return party_status, nil
end

function Enemy.DefaultFrameEventsInitialize ()
	Enemy.AddEventHandler ("DefaultFrameEvents", "SettingsChanged", Enemy.DefaultFrameEventsRefresh)

	local party_status = Enemy.DefaultFrameEventsRefresh ()
	PrintStartupNotice (party_status)
end

local Enemy = Enemy
local g = {}
local tinsert = table.insert
local zoneRefreshTimer

local function GroupIconsCancelZoneRefresh ()
    if (not zoneRefreshTimer) then return end
    zoneRefreshTimer:Remove ()
    zoneRefreshTimer = nil
end

local function GroupIconsFlushZoneRefresh ()
    zoneRefreshTimer = nil
    if (g.isPluginEnabled) then Enemy.GroupIcons_OnGroupsUpdated (false) end
    return true
end

local function GroupIconsShouldTrackPlayer (player)

    return
        player
        and not (g.settings.groupIconsHideOnSelf and player.isSelf)
        and not (not g.settings.groupIconsShowOtherGroups and not player.isInPlayerGroup)
        and not (not g.settings.groupIconsShowOnMarkedPlayers and Enemy.MarksIsPlayerHasMark (player.name))
end


local function GroupIconsUpdatePlayerIcon (icon, player)

    if (GroupIconsShouldTrackPlayer (player))
    then
        icon:Enable ()
        icon:Update (player)
    else
        icon:Disable ()
    end
end


--------------------------------------------------------------- Main
function Enemy.GroupIconsInitialize ()

	Enemy.groupIcons = g

	g.icons = {}
	g.windowNameToCustomTargetEvents = {}

	for group_index = 1, Enemy.MaxGroups
	do
		local group_icons = {}
		tinsert (g.icons, group_icons)

		for index = 1, 6
		do
			local icon = EnemyGroupIcon.New (group_index, index)
			tinsert (group_icons, icon)
		end
	end

	g.petIcon = EnemyGroupIcon.New (0, 0, true)

	-- static events
	Enemy.AddEventHandler ("GroupIcons", "SettingsChanged", Enemy.GroupIcons_OnSettingsChanged)
    Enemy.AddEventHandler ("GroupIcons", "Shutdown", GroupIconsCancelZoneRefresh)
	Enemy.AddEventHandler ("GroupIcons", "ConfigDialogInitializeSections", function (sections)
		table.insert (sections,
		{
			name = "GroupIcons",
			title = L"Group icons",
			templateName = "EnemyGroupIconsConfiguration",
			onInitialize = Enemy.GroupIconsUI_ConfigDialog_OnInitialize,
			onLoad = Enemy.GroupIconsUI_ConfigDialog_OnLoad,
			onSave = Enemy.GroupIconsUI_ConfigDialog_OnSave,
			onReset = Enemy.GroupIconsUI_ConfigDialog_OnReset,
		})
	end)

	Enemy.TriggerEvent ("GroupIconsInitialized")
end


function Enemy._GroupIconsDisableAll ()

	for group_index = 1, Enemy.MaxGroups
	do
		for index = 1, 6
		do
			local icon = g.icons[group_index][index]
			icon:Disable ()
		end
	end

	g.petIcon:Disable()
end


function Enemy._GroupIconsEnabledChanged (enable)

	if (g.isPluginEnabled == enable) then return end
	g.isPluginEnabled = enable

	if (g.isPluginEnabled)
	then
		Enemy.AddEventHandler ("GroupIcons", "GroupsTypeUpdated", Enemy.GroupIcons_OnGroupsTypeUpdated)
		Enemy.AddEventHandler ("GroupIcons", "GroupsUpdated", Enemy.GroupIcons_OnGroupsUpdated)
		Enemy.AddEventHandler ("GroupIcons", "GroupsPlayerUpdated", Enemy.GroupIcons_OnGroupsPlayerUpdated)
		Enemy.AddEventHandler ("GroupIcons", "GroupsPlayerWorldObjectIdUpdated", Enemy.GroupIcons_OnGroupsPlayerUpdated)
		Enemy.AddEventHandler ("GroupIcons", "GroupsPlayerPetUpdated", Enemy.GroupIcons_OnGroupsPlayerPetUpdated)
		Enemy.AddEventHandler ("GroupIcons", "PlayerObjectWindowsChanged", Enemy.GroupIcons_OnPlayerObjectWindowsChanged)
		RegisterEventHandler (SystemData.Events.PLAYER_ZONE_CHANGED, "Enemy.GroupIcons_OnPlayerZoneChanged")

		g.wasEnabled = true
	else
		GroupIconsCancelZoneRefresh ()
		Enemy.RemoveEventHandler ("GroupIcons", "GroupsTypeUpdated")
		Enemy.RemoveEventHandler ("GroupIcons", "GroupsUpdated")
		Enemy.RemoveEventHandler ("GroupIcons", "GroupsPlayerUpdated")
		Enemy.RemoveEventHandler ("GroupIcons", "GroupsPlayerWorldObjectIdUpdated")
		Enemy.RemoveEventHandler ("GroupIcons", "GroupsPlayerPetUpdated")
		Enemy.RemoveEventHandler ("GroupIcons", "PlayerObjectWindowsChanged")

		if (g.wasEnabled)
		then
			UnregisterEventHandler (SystemData.Events.PLAYER_ZONE_CHANGED, "Enemy.GroupIcons_OnPlayerZoneChanged")
		end
	end
end


function Enemy.GroupIconsDistanceUpdatesRequired ()
	return g.isPluginEnabled == true
end


function Enemy.GroupIcons_OnSettingsChanged (settings)
	GroupIconsCancelZoneRefresh ()
	g.settings = settings
	Enemy._GroupIconsEnabledChanged (g.settings.groupIconsEnabled);

	if (g.isPluginEnabled)
	then
		for group_index = 1, Enemy.MaxGroups
		do
			for index = 1, 6
			do
				local icon = g.icons[group_index][index]
				icon:Reset (true)
				icon:ApplySettings (g.settings)
			end
		end

		g.petIcon:ApplySettings (g.settings)

		Enemy.GroupIcons_OnGroupsUpdated (true)
	else
		Enemy._GroupIconsDisableAll ()
	end
end


function Enemy.GroupIcons_OnPlayerZoneChanged ()
    if (not g.isPluginEnabled) then return end
    -- Border events can arrive in bursts. Keep the windows and refresh the
    -- latest roster after the burst, reusing the pending timer as well.
    if (zoneRefreshTimer)
    then
        zoneRefreshTimer:Reset ()
    else
        zoneRefreshTimer = EnemyTimer.New ("groupIcons.zoneRefresh", 0.25, GroupIconsFlushZoneRefresh)
    end
end


function Enemy.GroupIcons_OnGroupsTypeUpdated ()
	GroupIconsCancelZoneRefresh ()
	Enemy._GroupIconsDisableAll ()
end


function Enemy.GroupIcons_OnGroupsUpdated (playerGroupChanged)

	if (playerGroupChanged)
	then
		Enemy._GroupIconsDisableAll ()
	end

	local max_groups = Enemy.GroupsGetMaxGroups ()
	for group_index = 1, max_groups
	do
		local group = Enemy.groups.groups[group_index]

		for index = 1, 6
		do
			local player = group[index]
			local icon = g.icons[group_index][index]

			GroupIconsUpdatePlayerIcon (icon, player)
		end
	end

	local me = Enemy.groups.player
	if (not me or not me.pet)
	then
		g.petIcon:Disable()
	else
		g.petIcon:Enable ()
		g.petIcon:Update (me.pet)
	end
end


function Enemy.GroupIcons_OnPlayerObjectWindowsChanged (name, objectWindow)

	-- Marks are the only object windows that affect group-icon visibility.
	if (not objectWindow or not objectWindow.data or not objectWindow.data.isMark) then return end

	local player = Enemy.groups.players[name]
	if (not player or not player:IsInGroup ()) then return end

	local group_icons = g.icons[player.groupIndex]
	if (not group_icons) then return end

	local icon = group_icons[player.index]
	if (not icon) then return end

	GroupIconsUpdatePlayerIcon (icon, player)
end


function Enemy.GroupIcons_OnGroupsPlayerUpdated (player)

	if (Enemy.groups.updateInProgress) then return end
	if (not player:IsInGroup ()) then return end

	local group_icons = g.icons[player.groupIndex]
	if (not group_icons) then return end

	local icon = group_icons[player.index]
	if (not icon) then return end

	GroupIconsUpdatePlayerIcon (icon, player)
end


function Enemy.GroupIcons_OnGroupsPlayerPetUpdated (player)

	if (not player.isSelf) then return end

	if (not player.pet)
	then
		g.petIcon:Disable ()
		return
	end

	g.petIcon:Enable ()
	g.petIcon:Update (player.pet)
end


function Enemy.GroupIcons_GroupIcon_OnLButtonDown ()

	local custom_target_event = g.windowNameToCustomTargetEvents[SystemData.ActiveWindow.name]
	if (not custom_target_event) then return end

	BroadcastEvent (custom_target_event)
end


--------------------------------------------------------------- UI: Configuration
local dlg =
{
	properties =
	{
		groupIconsEnabled =
		{
			key = "groupIconsEnabled",
			order = 10,
			name = L"Enable group icons",
			type = "bool",
			default = Enemy.DefaultSettings.groupIconsEnabled,
			paddingLeft = 20
		},
		groupIconsTargetOnClick =
		{
			key = "groupIconsTargetOnClick",
			order = 20,
			name = L"Target on click",
			type = "bool",
			default = Enemy.DefaultSettings.groupIconsTargetOnClick
		},
		groupIconsClickThrough =
		{
			key = "groupIconsClickThrough",
			order = 25,
			name = L"Click through icons",
			tooltip = L"Lets mouse clicks pass through the icons to the game world. This also disables left-click on these overhead icons.",
			type = "bool",
			default = Enemy.DefaultSettings.groupIconsClickThrough
		},
		groupIconsHideOnSelf =
		{
			key = "groupIconsHideOnSelf",
			order = 30,
			name = L"Hide icon on self",
			type = "bool",
			default = Enemy.DefaultSettings.groupIconsHideOnSelf
		},
		groupIconsShowOtherGroups =
		{
			key = "groupIconsShowOtherGroups",
			order = 40,
			name = L"Show icons for other groups",
			type = "bool",
			default = Enemy.DefaultSettings.groupIconsShowOtherGroups
		},
		groupIconsShowOnMarkedPlayers =
		{
			key = "groupIconsShowOnMarkedPlayers",
			order = 50,
			name = L"Show icons on marked players",
			tooltip = L"Show icons the players you have marked with custom marks",
			type = "bool",
			default = Enemy.DefaultSettings.groupIconsShowOnMarkedPlayers
		},




		titleAppearance =
		{
			key = "titleAppearance",
			order = 60,
			name = L"Appearance",
			type = "title",
			paddingTop = 40
		},
		groupIconsScale =
		{
			key = "groupIconsScale",
			order = 70,
			name = L"Scale",
			type = "float",
			default = Enemy.DefaultSettings.groupIconsScale,
			min = 0,
			max = 5
		},
		groupIconsLayer =
		{
			key = "groupIconsLayer",
			order = 80,
			name = L"Layer",
			type = "select",
			default = Enemy.DefaultSettings.groupIconsLayer,
			values = Enemy.ConfigurationWindowGetLayersSelectValues
		},
		groupIconsAlpha =
		{
			key = "groupIconsAlpha",
			order = 90,
			name = L"Alpha",
			type = "float",
			default = Enemy.DefaultSettings.groupIconsAlpha,
			min = 0,
			max = 1
		},
		groupIconsOffset =
		{
			key = "groupIconsOffset",
			order = 100,
			name = L"Offset (XY)",
			type = "int[]",
			size = 2,
			default = Enemy.DefaultSettings.groupIconsOffset,
			min = { -1000, -1000 },
			max = { 1000, 1000 }
		},
		groupIconsHPColor =
		{
			key = "groupIconsHPColor",
			order = 110,
			name = L"HP color (RGB)",
			type = "color",
			default = Enemy.DefaultSettings.groupIconsHPColor
		},
		groupIconsHPBGColor =
		{
			key = "groupIconsHPBGColor",
			order = 120,
			name = L"HP background color",
			type = "color",
			default = Enemy.DefaultSettings.groupIconsHPBGColor
		},
		groupIconsBGColor =
		{
			key = "groupIconsBGColor",
			order = 130,
			name = L"Background color",
			type = "color",
			default = Enemy.DefaultSettings.groupIconsBGColor
		},
		groupIconsBGAlpha =
		{
			key = "groupIconsBGAlpha",
			order = 140,
			name = L"Background alpha",
			type = "float",
			default = Enemy.DefaultSettings.groupIconsBGAlpha,
			min = 0,
			max = 5
		},



		titleOtherGroups =
		{
			key = "titleOtherGroups",
			order = 150,
			name = L"Other groups (OG)",
			type = "title",
			paddingTop = 40
		},
		groupIconsOtherGroupsScale =
		{
			key = "groupIconsOtherGroupsScale",
			order = 160,
			name = L"Scale",
			type = "float",
			default = Enemy.DefaultSettings.groupIconsOtherGroupsScale,
			min = 0,
			max = 5
		},
		groupIconsOtherGroupsLayer =
		{
			key = "groupIconsOtherGroupsLayer",
			order = 170,
			name = L"Layer",
			type = "select",
			default = Enemy.DefaultSettings.groupIconsOtherGroupsLayer,
			values = Enemy.ConfigurationWindowGetLayersSelectValues
		},
		groupIconsOtherGroupsAlpha =
		{
			key = "groupIconsOtherGroupsAlpha",
			order = 180,
			name = L"Alpha",
			type = "float",
			default = Enemy.DefaultSettings.groupIconsOtherGroupsAlpha,
			min = 0,
			max = 1
		},
		groupIconsOtherGroupsOffset =
		{
			key = "groupIconsOtherGroupsOffset",
			order = 190,
			name = L"Offset (XY)",
			type = "int[]",
			size = 2,
			default = Enemy.DefaultSettings.groupIconsOtherGroupsOffset,
			min = { -1000, -1000 },
			max = { 1000, 1000 }
		},
		groupIconsOtherGroupsHPColor =
		{
			key = "groupIconsOtherGroupsHPColor",
			order = 200,
			name = L"HP color (RGB)",
			type = "color",
			default = Enemy.DefaultSettings.groupIconsOtherGroupsHPColor
		},
		groupIconsOtherGroupsHPBGColor =
		{
			key = "groupIconsOtherGroupsHPBGColor",
			order = 210,
			name = L"HP background color",
			type = "color",
			default = Enemy.DefaultSettings.groupIconsOtherGroupsHPBGColor
		},
		groupIconsOtherGroupsBGColor =
		{
			key = "groupIconsOtherGroupsBGColor",
			order = 220,
			name = L"Background color",
			type = "color",
			default = Enemy.DefaultSettings.groupIconsOtherGroupsBGColor
		},
		groupIconsOtherGroupsBGAlpha =
		{
			key = "groupIconsOtherGroupsBGAlpha",
			order = 230,
			name = L"Background alpha",
			type = "float",
			default = Enemy.DefaultSettings.groupIconsOtherGroupsBGAlpha,
			min = 0,
			max = 5
		},


		titlePet =
		{
			key = "titlePet",
			order = 240,
			name = L"Pet",
			type = "title",
			paddingTop = 40
		},
		groupIconsPetScale =
		{
			key = "groupIconsPetScale",
			order = 250,
			name = L"Scale",
			type = "float",
			default = Enemy.DefaultSettings.groupIconsPetScale,
			min = 0,
			max = 5
		},
		groupIconsPetLayer =
		{
			key = "groupIconsPetLayer",
			order = 260,
			name = L"Layer",
			type = "select",
			default = Enemy.DefaultSettings.groupIconsPetLayer,
			values = Enemy.ConfigurationWindowGetLayersSelectValues
		},
		groupIconsPetAlpha =
		{
			key = "groupIconsPetAlpha",
			order = 270,
			name = L"Alpha",
			type = "float",
			default = Enemy.DefaultSettings.groupIconsPetAlpha,
			min = 0,
			max = 1
		},
		groupIconsPetOffset =
		{
			key = "groupIconsPetOffset",
			order = 280,
			name = L"Offset (XY)",
			type = "int[]",
			size = 2,
			default = Enemy.DefaultSettings.groupIconsPetOffset,
			min = { -1000, -1000 },
			max = { 1000, 1000 }
		},
		groupIconsPetIconColor =
		{
			key = "groupIconsPetIconColor",
			order = 290,
			name = L"Icon color (RGB)",
			type = "color",
			default = Enemy.DefaultSettings.groupIconsPetIconColor
		},
		groupIconsPetHPColor =
		{
			key = "groupIconsPetHPColor",
			order = 300,
			name = L"HP color (RGB)",
			type = "color",
			default = Enemy.DefaultSettings.groupIconsPetHPColor
		},
		groupIconsPetHPBGColor =
		{
			key = "groupIconsPetHPBGColor",
			order = 310,
			name = L"HP background color",
			type = "color",
			default = Enemy.DefaultSettings.groupIconsPetHPBGColor
		},
		groupIconsPetBGColor =
		{
			key = "groupIconsPetBGColor",
			order = 320,
			name = L"Background color",
			type = "color",
			default = Enemy.DefaultSettings.groupIconsPetBGColor
		},
		groupIconsPetBGAlpha =
		{
			key = "groupIconsPetBGAlpha",
			order = 330,
			name = L"Background alpha",
			type = "float",
			default = Enemy.DefaultSettings.groupIconsPetBGAlpha,
			min = 0,
			max = 5
		}
	}
}

function Enemy.GroupIconsUI_ConfigDialog_OnInitialize (section)

	dlg.section = section

	local root = dlg.section.windowName.."ContentScrollChild"
	dlg.cwn = root.."Config"
	Enemy.CreateConfigurationWindow (dlg.cwn, root, dlg.properties, Enemy.GroupIconsUI_ConfigDialog_TestSettings)


	ScrollWindowUpdateScrollRect (dlg.section.windowName.."Content")
end


function Enemy.GroupIconsUI_ConfigDialog_OnLoad (section)

	dlg.isLoaded = false

	dlg.groupIconsEnabled = Enemy.Settings.groupIconsEnabled
	dlg.groupIconsTargetOnClick = Enemy.Settings.groupIconsTargetOnClick
	dlg.groupIconsClickThrough = Enemy.Settings.groupIconsClickThrough
	dlg.groupIconsHideOnSelf = Enemy.Settings.groupIconsHideOnSelf
	dlg.groupIconsShowOtherGroups = Enemy.Settings.groupIconsShowOtherGroups
	dlg.groupIconsShowOnMarkedPlayers = Enemy.Settings.groupIconsShowOnMarkedPlayers

	dlg.groupIconsScale = Enemy.Settings.groupIconsScale
	dlg.groupIconsLayer = Enemy.Settings.groupIconsLayer
	dlg.groupIconsAlpha = Enemy.Settings.groupIconsAlpha
	dlg.groupIconsOffset = Enemy.clone (Enemy.Settings.groupIconsOffset)
	dlg.groupIconsHPColor = Enemy.clone (Enemy.Settings.groupIconsHPColor)
	dlg.groupIconsHPBGColor = Enemy.clone (Enemy.Settings.groupIconsHPBGColor)
	dlg.groupIconsBGColor = Enemy.clone (Enemy.Settings.groupIconsBGColor)
	dlg.groupIconsBGAlpha = Enemy.Settings.groupIconsBGAlpha

	dlg.groupIconsOtherGroupsScale = Enemy.Settings.groupIconsOtherGroupsScale
	dlg.groupIconsOtherGroupsLayer = Enemy.Settings.groupIconsOtherGroupsLayer
	dlg.groupIconsOtherGroupsAlpha = Enemy.Settings.groupIconsOtherGroupsAlpha
	dlg.groupIconsOtherGroupsOffset = Enemy.clone (Enemy.Settings.groupIconsOtherGroupsOffset)
	dlg.groupIconsOtherGroupsHPColor = Enemy.clone (Enemy.Settings.groupIconsOtherGroupsHPColor)
	dlg.groupIconsOtherGroupsHPBGColor = Enemy.clone (Enemy.Settings.groupIconsOtherGroupsHPBGColor)
	dlg.groupIconsOtherGroupsBGColor = Enemy.clone (Enemy.Settings.groupIconsOtherGroupsBGColor)
	dlg.groupIconsOtherGroupsBGAlpha = Enemy.Settings.groupIconsOtherGroupsBGAlpha

	dlg.groupIconsPetScale = Enemy.Settings.groupIconsPetScale
	dlg.groupIconsPetLayer = Enemy.Settings.groupIconsPetLayer
	dlg.groupIconsPetAlpha = Enemy.Settings.groupIconsPetAlpha
	dlg.groupIconsPetOffset = Enemy.clone (Enemy.Settings.groupIconsPetOffset)
	dlg.groupIconsPetIconColor = Enemy.clone (Enemy.Settings.groupIconsPetIconColor)
	dlg.groupIconsPetHPColor = Enemy.clone (Enemy.Settings.groupIconsPetHPColor)
	dlg.groupIconsPetHPBGColor = Enemy.clone (Enemy.Settings.groupIconsPetHPBGColor)
	dlg.groupIconsPetBGColor = Enemy.clone (Enemy.Settings.groupIconsPetBGColor)
	dlg.groupIconsPetBGAlpha = Enemy.Settings.groupIconsPetBGAlpha


	Enemy.ConfigurationWindowLoadData (dlg.cwn, dlg)

  dlg.isLoaded = true

	Enemy.GroupIconsUI_ConfigDialog_TestSettings ()
end


function Enemy.GroupIconsUI_ConfigDialog_TestSettings ()

	if (not dlg.isLoaded) then return end

	Enemy.ConfigurationWindowSaveData (dlg.cwn, dlg)
	Enemy.GroupIcons_OnSettingsChanged (dlg)
end


function Enemy.GroupIconsUI_ConfigDialog_OnReset (section)

	for k, v in pairs (Enemy.Settings)
	do
		if (not k:match("^groupIcons.*")) then continue end
		Enemy.Settings[k] = nil
	end

	Enemy.Print ("Group icons settings has been reset")
	InterfaceCore.ReloadUI ()
end


function Enemy.GroupIconsUI_ConfigDialog_OnSave (section)

	Enemy.GroupIconsUI_ConfigDialog_TestSettings ()

	Enemy.Settings.groupIconsEnabled = dlg.groupIconsEnabled
	Enemy.Settings.groupIconsTargetOnClick = dlg.groupIconsTargetOnClick
	Enemy.Settings.groupIconsClickThrough = dlg.groupIconsClickThrough
	Enemy.Settings.groupIconsHideOnSelf = dlg.groupIconsHideOnSelf
	Enemy.Settings.groupIconsShowOtherGroups = dlg.groupIconsShowOtherGroups
  Enemy.Settings.groupIconsShowOnMarkedPlayers = dlg.groupIconsShowOnMarkedPlayers

	Enemy.Settings.groupIconsScale = dlg.groupIconsScale
	Enemy.Settings.groupIconsLayer = dlg.groupIconsLayer
	Enemy.Settings.groupIconsAlpha = dlg.groupIconsAlpha
	Enemy.Settings.groupIconsOffset = Enemy.clone (dlg.groupIconsOffset)
	Enemy.Settings.groupIconsHPColor = Enemy.clone (dlg.groupIconsHPColor)
	Enemy.Settings.groupIconsHPBGColor = Enemy.clone (dlg.groupIconsHPBGColor)
	Enemy.Settings.groupIconsBGColor = Enemy.clone (dlg.groupIconsBGColor)
	Enemy.Settings.groupIconsBGAlpha = dlg.groupIconsBGAlpha

	Enemy.Settings.groupIconsOtherGroupsScale = dlg.groupIconsOtherGroupsScale
	Enemy.Settings.groupIconsOtherGroupsLayer = dlg.groupIconsOtherGroupsLayer
	Enemy.Settings.groupIconsOtherGroupsAlpha = dlg.groupIconsOtherGroupsAlpha
	Enemy.Settings.groupIconsOtherGroupsOffset = Enemy.clone (dlg.groupIconsOtherGroupsOffset)
	Enemy.Settings.groupIconsOtherGroupsHPColor = Enemy.clone (dlg.groupIconsOtherGroupsHPColor)
	Enemy.Settings.groupIconsOtherGroupsHPBGColor = Enemy.clone (dlg.groupIconsOtherGroupsHPBGColor)
	Enemy.Settings.groupIconsOtherGroupsBGColor = Enemy.clone (dlg.groupIconsOtherGroupsBGColor)
	Enemy.Settings.groupIconsOtherGroupsBGAlpha = dlg.groupIconsOtherGroupsBGAlpha

	Enemy.Settings.groupIconsPetScale = dlg.groupIconsPetScale
	Enemy.Settings.groupIconsPetLayer = dlg.groupIconsPetLayer
	Enemy.Settings.groupIconsPetAlpha = dlg.groupIconsPetAlpha
	Enemy.Settings.groupIconsPetOffset = Enemy.clone (dlg.groupIconsPetOffset)
	Enemy.Settings.groupIconsPetIconColor = Enemy.clone (dlg.groupIconsPetIconColor)
	Enemy.Settings.groupIconsPetHPColor = Enemy.clone (dlg.groupIconsPetHPColor)
	Enemy.Settings.groupIconsPetHPBGColor = Enemy.clone (dlg.groupIconsPetHPBGColor)
	Enemy.Settings.groupIconsPetBGColor = Enemy.clone (dlg.groupIconsPetBGColor)
	Enemy.Settings.groupIconsPetBGAlpha = dlg.groupIconsPetBGAlpha

	return true
end

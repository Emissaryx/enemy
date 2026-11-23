local Enemy = Enemy
local g = {}
local tinsert = table.insert
local ipairs = ipairs
local pairs = pairs


local function MarksIsEmptyPlayerName (playerName)
	return (
		playerName == nil
		or
		playerName == L""
		or
		playerName == ""
	)
end


local function MarksNormalizePlayerName (playerName)

	playerName = Enemy.NormalizePlayerName (playerName)
	if (MarksIsEmptyPlayerName (playerName)) then return nil end

	return playerName
end


local function MarksGetPermanentTargetKey (template, playerName)

	playerName = MarksNormalizePlayerName (playerName)
	if (not playerName) then return nil, nil end

	if (template.permanentTargets[playerName] ~= nil)
	then
		return playerName, playerName
	end

	for existingPlayerName in pairs (template.permanentTargets)
	do
		if (MarksNormalizePlayerName (existingPlayerName) == playerName)
		then
			return existingPlayerName, playerName
		end
	end

	return nil, playerName
end


function Enemy.MarksInitialize ()

	Enemy.marks = g
	if (Enemy.Settings.markBarIconStyle ~= "arrow") then Enemy.Settings.markBarIconStyle = "original" end

	if (not Enemy.Settings.markTemplates)
	then
		Enemy.Settings.markTemplates = {}
	end

	-- load templates from addon settings
	g.templates = {}

	if (Enemy.Settings.prevVersion > 0)
	then
		if (Enemy.Settings.prevVersion < 66)
		then
			for _, template_data in ipairs (Enemy.Settings.markTemplates)
			do
				if (not template_data.color) then continue end
				template_data.color = { template_data.color.r, template_data.color.g, template_data.color.b }
			end

			for k, template_data in pairs (Enemy.Settings)
			do
				if (not k:match(".*MarkTemplate.*") or not template_data.color) then continue end
				template_data.color = { template_data.color.r, template_data.color.g, template_data.color.b }
			end
		end
	end

	for _, template_data in ipairs (Enemy.Settings.markTemplates)
	do
		local template = EnemyMarkTemplate.New (template_data)
		tinsert (g.templates, template)
	end

	Enemy.Settings.markTemplates = g.templates

	-- UI: EnemyMarksWindow
	CreateWindow ("EnemyMarksWindow", true)
	WindowSetTintColor ("EnemyMarksWindowBackground", 0, 0, 0)
	WindowSetAlpha ("EnemyMarksWindowBackground", 0)
	WindowSetAlpha ("EnemyMarksWindowAdd", 0.5)
	LayoutEditor.RegisterWindow ("EnemyMarksWindow", L"Enemy marks", L"Enemy marks window anchor", false, false, true, nil)

	-- events
	Enemy.AddEventHandler ("Marks", "IconCreateContextMenu", function (data)

		tinsert (data, { text = L"" })

		if (Enemy.MarksUI_EnemyMarksWindow_IsOpen ())
		then
			tinsert (data,
				{
					text = L"Hide marks window",
					callback = Enemy.MarksUI_EnemyMarksWindow_Hide
				})
		else
			tinsert (data,
				{
					text = L"Show marks window",
					callback = Enemy.MarksUI_EnemyMarksWindow_Open
				})
		end

		tinsert (data,
		{
			text = L"Clear all active marks",
			callback = function ()
				for _, template in ipairs (g.templates)
				do
					template:ClearMarks ()
				end
			end
		})
	end)

	Enemy.AddEventHandler ("Marks", "GroupsPlayerWorldObjectIdUpdated", function (player)
		Enemy._MarksCheckPlayerNewId (player.name, player.worldObjectId, true, player.career)
	end)

	Enemy.AddEventHandler ("Marks", "PlayerTargetUpdated", function (target)

		if (not target.isNpc and target.id > 0)
		then
			Enemy._MarksCheckPlayerNewId (target.name, target.id, target.isFriendly, target.career)
		end
	end)

	Enemy.MarksUI_EnemyMarksWindow_Update ()
	Enemy.TriggerEvent ("MarksInitialized")
end


function Enemy._MarksCheckPlayerNewId (name, id, isFriendly, career)

	name = MarksNormalizePlayerName (name)
	if (not name) then return end

	for index, template in ipairs (g.templates)
	do
		if (template.permanent and template.permanentTargets[name] == false)
		then
			template:ToggleMark (id, name, true, isFriendly, career)
		end
	end
end


function Enemy.MarksIsPlayerHasMark (name)

	local windows = Enemy.GetObjectWindowsForPlayer (name)
	if (not windows) then return false end

	for _, object_window in pairs (windows)
	do
		if (object_window.data.isMark)
		then
			return true
		end
	end

	return false
end


function Enemy.MarksDeleteTemplate (index)

	local template = g.templates[index]
	if (not template) then return end

	table.remove (g.templates, index)
	Enemy.MarksUI_EnemyMarksWindow_Update ()
end


function Enemy.MarksMoveTemplate (index, moveForward)

	if (moveForward)
	then
		if (index == #g.templates) then return end

		local tmp = g.templates[index + 1]
		g.templates[index + 1] = g.templates[index]
		g.templates[index] = tmp
	else
		if (index == 1) then return end

		local tmp = g.templates[index - 1]
		g.templates[index - 1] = g.templates[index]
		g.templates[index] = tmp
	end

	Enemy.MarksUI_EnemyMarksWindow_Update ()
end


function Enemy.MarksToggle (index)

	if (not index) then return end

	if (type (index) == "string" or type (index) == "wstring")
	then
		local name = Enemy.toWString (index)
		name = name:lower ()

		index = nil

		for k, v in ipairs (g.templates)
		do
			if (v.name:lower () == name)
			then
				index = k
				break
			end
		end

		if (not index) then return end
	end

	local template = g.templates[index]
	if (not template or not Enemy.latestTarget) then return end

	template:ToggleMark (Enemy.latestTarget.id,
						Enemy.latestTarget.name,
						not Enemy.latestTarget.isNpc,
						Enemy.latestTarget.isFriendly,
						Enemy.latestTarget.career)
end


function Enemy.MarksGetPermanentTemplates (playerName)

	playerName = MarksNormalizePlayerName (playerName)

	local data = {}

	for index, template in ipairs (g.templates)
	do
		if (template.permanent)
		then
			local color = template.color or { 255, 255, 255 }
			local is_in_list = false

			if (playerName ~= nil)
			then
				is_in_list = MarksGetPermanentTargetKey (template, playerName) ~= nil
			end

			tinsert (data,
			{
				index = index,
				name = template.name,
				color = { color[1] or 255, color[2] or 255, color[3] or 255 },
				isInList = is_in_list
			})
		end
	end

	return data
end


function Enemy.MarksAddPlayerToTemplate (index, playerName)

	if (index == nil or playerName == nil) then return false end

	local template = g.templates[index]
	if (not template or not template.permanent) then return false end

	local existingPlayerName
	existingPlayerName, playerName = MarksGetPermanentTargetKey (template, playerName)
	if (playerName == nil) then return false end

	if (existingPlayerName ~= nil)
	then
		if (existingPlayerName ~= playerName)
		then
			template.permanentTargets[playerName] = template.permanentTargets[existingPlayerName]
			template.permanentTargets[existingPlayerName] = nil
		end

		return false
	end

	template.permanentTargets[playerName] = false

	return true
end


function Enemy.MarksRemovePlayerFromTemplate (index, playerName)

	if (index == nil or playerName == nil) then return false end

	local template = g.templates[index]
	if (not template or not template.permanent) then return false end

	local existingPlayerName
	existingPlayerName, playerName = MarksGetPermanentTargetKey (template, playerName)
	if (playerName == nil) then return false end

	if (existingPlayerName == nil) then return false end
	template.permanentTargets[existingPlayerName] = nil

	return true
end


--------------------------------------------------------------- UI: Marks window
local marks_window = {}

function Enemy.MarksUI_EnemyMarksWindow_IsOpen ()
	return WindowGetShowing ("EnemyMarksWindow")
end

function Enemy.MarksUI_EnemyMarksWindow_Open (id)
	WindowSetShowing ("EnemyMarksWindow", true)
end

function Enemy.MarksUI_EnemyMarksWindow_Hide ()
	WindowSetShowing ("EnemyMarksWindow", false)
end

function Enemy.MarksUI_EnemyMarksWindow_OnLButtonDown ()
	marks_window.isDragged = true
end

function Enemy.MarksUI_EnemyMarksWindow_OnLButtonUp ()
	marks_window.isDragged = false
end

function Enemy.MarksUI_EnemyMarksWindow_OnMouseOver ()

	if (marks_window.isDragged) then return end

	WindowStartAlphaAnimation ("EnemyMarksWindowBackground", Window.AnimationType.SINGLE_NO_RESET, 0, 0.5, 0.3, true, 0, 1)
	WindowStartAlphaAnimation ("EnemyMarksWindowAdd", Window.AnimationType.SINGLE_NO_RESET, 0.5, 1.0, 0.3, true, 0, 1)
end

function Enemy.MarksUI_EnemyMarksWindow_OnMouseOverEnd ()

	if (marks_window.isDragged) then return end

	WindowStartAlphaAnimation ("EnemyMarksWindowBackground", Window.AnimationType.SINGLE_NO_RESET, 0.5, 0, 0.3, true, 0, 1)
	WindowStartAlphaAnimation ("EnemyMarksWindowAdd", Window.AnimationType.SINGLE_NO_RESET, 1.0, 0.5, 0.3, true, 0, 1)
end

function Enemy.MarksUI_EnemyMarksWindow_OnAddMouseOver ()
	Enemy.MarksUI_EnemyMarksWindow_OnMouseOver ()

	Tooltips.CreateTextOnlyTooltip ("EnemyMarksWindowAdd")
	Tooltips.SetTooltipText (1, 1, L"Add new mark template")

	Tooltips.AnchorTooltip (Tooltips.ANCHOR_CURSOR)
	Tooltips.Finalize()
end

function Enemy.MarksUI_EnemyMarksWindow_OnAddMouseOverEnd ()
	Enemy.MarksUI_EnemyMarksWindow_OnMouseOverEnd ()
end

function Enemy.MarksUI_EnemyMarksWindow_OnAddLButtonUp ()

	local template = EnemyMarkTemplate.New ()

	template:Edit (function (template)
		tinsert (g.templates, template)
		Enemy.MarksUI_EnemyMarksWindow_Update ()
	end)
end

function Enemy.MarksUI_EnemyMarksWindow_OnAddRButtonUp ()

	EA_Window_ContextMenu.CreateContextMenu ("EnemyMarksWindowAdd")
	local nextStyle = Enemy.Settings.markBarIconStyle == "arrow" and L"Use original tiles" or L"Use arrow icons"
	EA_Window_ContextMenu.AddMenuItem (nextStyle, Enemy.MarksUI_EnemyMarksWindow_ToggleIconStyle, false, true)
	EA_Window_ContextMenu.AddMenuDivider ()
    EA_Window_ContextMenu.AddMenuItem (L"Hide", Enemy.MarksUI_EnemyMarksWindow_Hide, false, true)
	EA_Window_ContextMenu.Finalize ()
end

function Enemy.MarksUI_EnemyMarksWindow_ToggleIconStyle ()
	Enemy.Settings.markBarIconStyle = Enemy.Settings.markBarIconStyle == "arrow" and "original" or "arrow"
	Enemy.MarksUI_EnemyMarksWindow_Update ()
end

function Enemy.MarksUI_EnemyMarksWindow_Update ()

	if (not Enemy.MarksUI_EnemyMarksWindow_IsOpen ()) then return end

	-- remove all windows
    local k = 1

	while (true)
	do
		local window_name = "EnemyMarkIcon"..k
		if (not DoesWindowExist (window_name)) then break end

		DestroyWindow (window_name)
		k = k + 1
	end

	-- create new windows
	local icon_padding = 10
	local icon_border = 10
	local window_dy = 32
	local window_dx = 0
	local useArrowIcons = Enemy.Settings.markBarIconStyle == "arrow"

	for index, template in ipairs (g.templates)
	do
		local window_name = "EnemyMarkIcon"..index

		CreateWindowFromTemplate (window_name, "EnemyMarkIcon", "EnemyMarksWindow")

		LabelSetText (window_name.."Text", Enemy.toWStringOrEmpty (template.name))
		local shape = template.shape or "enemy_mark_arrowdown"
		if (useArrowIcons)
		then
			DynamicImageSetTexture (window_name.."Background", shape, 0, 60)
			DynamicImageSetTextureDimensions (window_name.."Background", 100, 140)
			WindowSetDimensions (window_name, 32, 44)
			WindowSetDimensions (window_name.."Background", 31, 44)
			if (EnemyMarkTemplate.UsesBuiltInShapeColors (shape))
			then
				WindowSetTintColor (window_name.."Background", 255, 255, 255)
			else
				WindowSetTintColor (window_name.."Background", unpack (template.color))
			end
		else
			DynamicImageSetTexture (window_name.."Background", "enemy_mark_icon_template", 0, 0)
			DynamicImageSetTextureDimensions (window_name.."Background", 32, 32)
			WindowSetDimensions (window_name, 32, 32)
			WindowSetDimensions (window_name.."Background", 31, 32)
			WindowSetTintColor (window_name.."Background", unpack (template.color))
		end
		WindowSetScale (window_name, WindowGetScale ("EnemyMarksWindow"))

		local dx, dy = WindowGetDimensions (window_name)
		window_dy = math.max (window_dy, dy)
		window_dx = window_dx + dx

		if (index > 1)
		then
			WindowAddAnchor (window_name, "topright", "EnemyMarkIcon"..(index - 1), "topleft", icon_padding, 0)
			window_dx = window_dx + icon_padding
		else
			WindowAddAnchor (window_name, "topleft", "EnemyMarksWindow", "topleft", icon_border, icon_border)
		end
	end

	window_dx = icon_border + window_dx + icon_padding + 32 + icon_border
	window_dy = icon_border + window_dy + icon_border
	WindowSetDimensions ("EnemyMarksWindow", window_dx, window_dy)
end

----------------------------------------------------------------- UI: Mark icon

function Enemy.MarksUI_GetMouseOverTemplate ()

	local windowName = SystemData.ActiveWindow and SystemData.ActiveWindow.name
	if (not windowName or not windowName:match ("EnemyMarkIcon%d+"))
	then
		windowName = SystemData.MouseOverWindow and SystemData.MouseOverWindow.name
	end
	if (not windowName) then return nil end

	local index = windowName:match ("EnemyMarkIcon(%d+)")
	if (not index) then return nil end

	index = tonumber (index)

	return g.templates[index], index, windowName
end

function Enemy.MarksUI_EnemyMarkIcon_OnMouseOver ()

	local template = Enemy.MarksUI_GetMouseOverTemplate ()
	if (not template) then return end

	Tooltips.CreateTextOnlyTooltip (SystemData.MouseOverWindow.name)

	Tooltips.SetTooltipText (1, 1, L"Mark '"..Enemy.toWStringOrEmpty (template.name)..L"'")
	if (template.permanent)
	then
		Tooltips.SetTooltipText (1, 3, L"Permanent")
	end

	Tooltips.SetTooltipText (2, 1, L"")
	Tooltips.SetTooltipText (3, 1, L"Left click to mark target")
	Tooltips.SetTooltipText (4, 1, L"Right click to open context menu")
	Tooltips.SetTooltipText (5, 1, L"Alt+Left click to open recent marked players list")
	Tooltips.SetTooltipText (6, 1, L"Alt+Right click to clear all active marks")

	if (template.permanent)
	then
		Tooltips.SetTooltipText (7, 1, L"Ctrl+Left click to open permanent marked players list")
		Tooltips.SetTooltipText (8, 1, L"Ctrl+Right click to clear all active marks and stored targets list")
	end

	Tooltips.AnchorTooltip (Tooltips.ANCHOR_CURSOR)
	Tooltips.Finalize()
end

function Enemy.MarksUI_EnemyMarkIcon_OnLButtonUp (flags)

	local template, index = Enemy.MarksUI_GetMouseOverTemplate ()
	if (not template) then return end

	local show_normal_list = Enemy.IsAltPressed (flags)
	local show_permanent_list = Enemy.IsControlPressed (flags) and template.permanent

	if (show_normal_list or show_permanent_list)
	then
		g.contextMenuTemplateIndex = index
		g.contextMenuTemplate = template

		g.contextMenuTargets = {}

		if (show_permanent_list)
		then
			EA_Window_ContextMenu.CreateContextMenu (SystemData.MouseOverWindow.name, EA_Window_ContextMenu.CONTEXT_MENU_1, L"Permanent targets list")

			for k in pairs (template.permanentTargets)
			do
				tinsert (g.contextMenuTargets, k)
			end

		else
			EA_Window_ContextMenu.CreateContextMenu (SystemData.MouseOverWindow.name, EA_Window_ContextMenu.CONTEXT_MENU_1, L"Marked players")

			-- get active marks (for players only) and sort them by creation time
			local active_marks_data = {}

			for _, mark in ipairs (template._activeMarks)
			do
				if (not mark.isPlayer) then continue end
				tinsert (active_marks_data, { name = Enemy.FixString (mark.objectName), t = mark.t })
			end

			table.sort (active_marks_data, function (a, b)
				return a.t > b.t
			end)

			-- now get last 10 player names
			for k = 1, math.min (10, #active_marks_data)
			do
				tinsert (g.contextMenuTargets, active_marks_data[k].name)
			end
		end

		if (#g.contextMenuTargets < 1)
		then
			EA_Window_ContextMenu.AddMenuItem (L"No players", nil, true, true)
		else
			-- sort 10 names alphabetically
			table.sort (g.contextMenuTargets)

			-- put it to context menu
			for _, name in ipairs (g.contextMenuTargets)
			do
				EA_Window_ContextMenu.AddMenuItem (L"Target '"..name..L"'", Enemy.MarksUI_EnemyMarkIcon_Target, false, true)
			end

			EA_Window_ContextMenu.AddMenuDivider ()

			if (show_permanent_list)
			then
				EA_Window_ContextMenu.AddMenuItem (L"Clear all active marks and all stored targets list", Enemy.MarksUI_EnemyMarkIcon_ClearActiveMarksWithPermanent, false, true)
			else
				EA_Window_ContextMenu.AddMenuItem (L"Clear all active marks", Enemy.MarksUI_EnemyMarkIcon_ClearActiveMarks, false, true)
			end
		end

		EA_Window_ContextMenu.Finalize ()
	else
		Enemy.MarksToggle (index)
	end
end


function Enemy.MarksUI_EnemyMarkIcon_Target ()

	local index = SystemData.ActiveWindow.name:match (".*(%d+)")
	if (not index) then return end

	Enemy.SendChatMessage (L"/target "..g.contextMenuTargets[tonumber (index)])
end


function Enemy.MarksUI_EnemyMarkIcon_OnRButtonUp (flags)

	local template, index, windowName = Enemy.MarksUI_GetMouseOverTemplate ()
	if (not template) then return end

	g.contextMenuTemplateIndex = index
	g.contextMenuTemplate = template

	if (Enemy.IsAltPressed (flags))
	then
		Enemy.MarksUI_EnemyMarkIcon_ClearActiveMarks ()

	elseif (Enemy.IsControlPressed (flags))
	then
		Enemy.MarksUI_EnemyMarkIcon_ClearActiveMarksWithPermanent ()

	else

		EA_Window_ContextMenu.CreateContextMenu (windowName)

	    EA_Window_ContextMenu.AddMenuItem (L"Edit", Enemy.MarksUI_EnemyMarkIcon_Edit, false, true)

	    if (template.permanent)
	    then
            EA_Window_ContextMenu.AddMenuItem (L"Add player by name", Enemy.MarksUI_EnemyMarkIcon_AddPermanentTarget, false, true)
	    end

	    EA_Window_ContextMenu.AddMenuItem (L"Copy to new", Enemy.MarksUI_EnemyMarkIcon_Copy, false, true)
	    EA_Window_ContextMenu.AddMenuDivider ()
	    EA_Window_ContextMenu.AddMenuItem (L"Move left", Enemy.MarksUI_EnemyMarkIcon_MoveLeft, index == 1, true)
	    EA_Window_ContextMenu.AddMenuItem (L"Move right", Enemy.MarksUI_EnemyMarkIcon_MoveRight, index == #g.templates, true)
	    EA_Window_ContextMenu.AddMenuDivider ()
	    EA_Window_ContextMenu.AddMenuItem (L"Delete", Enemy.MarksUI_EnemyMarkIcon_Delete, false, true)
	    EA_Window_ContextMenu.AddMenuItem (L"Clear active marks", Enemy.MarksUI_EnemyMarkIcon_ClearActiveMarks, false, true)

	    if (template.permanent)
	    then
            EA_Window_ContextMenu.AddMenuItem (L"Clear all active marks and all stored targets list", Enemy.MarksUI_EnemyMarkIcon_ClearActiveMarksWithPermanent, false, true)
	    end

		EA_Window_ContextMenu.Finalize ()
	end
end

function Enemy.MarksUI_EnemyMarkIcon_AddPermanentTarget ()

	local template = g.contextMenuTemplate
	local template_index = g.contextMenuTemplateIndex
	if (not template or not template.permanent) then return end

	local function on_ok (playerName)

		if (not template_index or not template.permanent or g.templates[template_index] ~= template) then return end

		playerName = Enemy.NormalizePlayerName (playerName)

		if (MarksIsEmptyPlayerName (playerName))
		then
			Enemy.Print (L"No player name entered.")
			return
		end

		if (Enemy.MarksAddPlayerToTemplate (template_index, playerName))
		then
			Enemy.Print (L"Added '"..playerName..L"' to list '"..template.name..L"'.")
		else
			Enemy.Print (L"'"..playerName..L"' is already in list '"..template.name..L"'.")
		end
	end

	DialogManager.MakeTextEntryDialog (L"Add player by name",
	                                   L"Add player to '"..template.name..L"'",
	                                   L"",
	                                   on_ok,
	                                   nil,
	                                   250,
	                                   false)
end

function Enemy.MarksUI_EnemyMarkIcon_Edit ()

	g.contextMenuTemplate:Edit (function (template)
		Enemy.MarksUI_EnemyMarksWindow_Update ()
	end)
end

function Enemy.MarksUI_EnemyMarkIcon_Copy ()

	local template = EnemyMarkTemplate.New (g.contextMenuTemplate)

	template:Edit (function (template)
		tinsert (g.templates, template)
		Enemy.MarksUI_EnemyMarksWindow_Update ()
	end)
end

function Enemy.MarksUI_EnemyMarkIcon_MoveLeft ()
	Enemy.MarksMoveTemplate (g.contextMenuTemplateIndex, false)
end

function Enemy.MarksUI_EnemyMarkIcon_MoveRight ()
	Enemy.MarksMoveTemplate (g.contextMenuTemplateIndex, true)
end

function Enemy.MarksUI_EnemyMarkIcon_Delete ()

	DialogManager.MakeTwoButtonDialog (L"Delete mark template '"..g.templates[g.contextMenuTemplateIndex].name..L"' ?",
                                       L"Yes", Enemy.MarksUI_EnemyMarkIcon_DeleteConfirmed,
                                       L"No")
end


function Enemy.MarksUI_EnemyMarkIcon_DeleteConfirmed ()
	Enemy.MarksDeleteTemplate (g.contextMenuTemplateIndex)
end


function Enemy.MarksUI_EnemyMarkIcon_ClearActiveMarks ()
	g.contextMenuTemplate:ClearMarks ()
end


function Enemy.MarksUI_EnemyMarkIcon_ClearActiveMarksWithPermanent ()
	g.contextMenuTemplate:ClearMarks (true)
end

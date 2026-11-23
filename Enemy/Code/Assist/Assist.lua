local Enemy = Enemy
local g = {}

local MACRO_MARK = L"/script Enemy.Mark()"
local MACRO_TARGET_NAME = L"Enemy: Target"
local MACRO_TARGET = L"/script Enemy.Target()"

local function GetAssistMacroSlot ()
	if (not EA_Window_Macro or not EA_Window_Macro.NUM_MACROS) then return nil end
	return EA_Window_Macro.NUM_MACROS
end


local function SendEnemyAssistTarget ()

	if (not g.lastAssist or g.lastAssist == L"") then return end

	Enemy.SendChatMessage (L"/assist "..Enemy.toWString (g.lastAssist))
end


local function ClearNewTargetMark ()

	if (g.newTargetMarkTemplate) then g.newTargetMarkTemplate:ClearMarks () end

	local target = g.markedTarget
	g.markedTarget = nil

	if (target and Enemy._MarksCheckPlayerNewId)
	then
		Enemy._MarksCheckPlayerNewId (target.name, target.id, target.isFriendly, target.career)
	end
end

function Enemy.AssistInitialize ()

	Enemy.assist = g
	g.lastAssist = nil

	if (not Enemy.Settings.newTargetMarkTemplate)
	then
		g.newTargetMarkTemplate = EnemyMarkTemplate.New ()
		g.newTargetMarkTemplate.color = { b = 0, g = 0, r = 255 }
		g.newTargetMarkTemplate.display = 1
		g.newTargetMarkTemplate.text = L"KILL"

		Enemy.Settings.newTargetMarkTemplate = Enemy.clone (g.newTargetMarkTemplate)
	end

	local assist_macro_slot = GetAssistMacroSlot ()
	if (assist_macro_slot)
	then
		-- macros
		Enemy.CreateMacro (L"Enemy: Mark", MACRO_MARK, 210)
		Enemy.SetMacro (assist_macro_slot, MACRO_TARGET_NAME, MACRO_TARGET, 214)
	end

	-- UI
	CreateWindow ("EnemyTarget", false)
	LayoutEditor.RegisterWindow ("EnemyTarget", L"Enemy target", L"Enemy target", false, false, true, nil)

	-- events
	Enemy.AddEventHandler ("Assist", "SettingsChanged", Enemy.Assist_OnSettingsChanged)
	Enemy.AddEventHandler ("Assist", "IntercomMessage", Enemy.Assist_OnIntercomMessage)

	Enemy.AddEventHandler ("Assist", "ConfigDialogInitializeSections", function (sections)
		table.insert (sections,
		{
			name = "Assist",
			title = L"Assist",
			templateName = "EnemyAssistConfiguration",
			onInitialize = Enemy.AssistUI_ConfigDialog_OnInitialize,
			onLoad = Enemy.AssistUI_ConfigDialog_OnLoad,
			onSave = Enemy.AssistUI_ConfigDialog_OnSave,
			onReset = Enemy.AssistUI_ConfigDialog_OnReset
		})
	end)

	Enemy.TriggerEvent ("AssistInitialized")
end


function Enemy.Assist_OnSettingsChanged (settings)

	g.settings = settings

	ClearNewTargetMark ()

	if (g.settings.markNewTarget)
	then
		if (g.newTargetMarkTemplate)
		then
			g.newTargetMarkTemplate:Load (g.settings.newTargetMarkTemplate)
		else
			g.newTargetMarkTemplate = EnemyMarkTemplate.New (g.settings.newTargetMarkTemplate)
		end
	end

	if (g.markNewTarget ~= g.settings.markNewTarget)
	then
		g.markNewTarget = g.settings.markNewTarget

		if (g.settings.markNewTarget)
		then
			Enemy.AddEventHandler ("Assist", "PlayerTargetUpdated", Enemy.Assist_OnPlayerTargetUpdated)
		else
			Enemy.RemoveEventHandler ("Assist", "PlayerTargetUpdated")
		end
	end
end


function Enemy.Assist_OnIntercomMessage (from, targetName, playerFlag, careerId)

if (targetName == nil or playerFlag == nil) then return end

local is_player = (playerFlag == L"P")

if (is_player)
then
	Enemy.AssistUI_Target_Show (targetName, tonumber (careerId))
else
	Enemy.AssistUI_Target_Show (targetName)
end

	g.lastAssist = from
	g.lastTargetName = targetName

	if (g.settings.assistTargetOnNotifyClick)
	then
		WindowSetHandleInput ("EnemyTarget", true)
	else
		WindowSetHandleInput ("EnemyTarget", false)
	end

	if (g.settings.markNewTarget)
	then
		g.markTarget = true
		g.markTargetTimer = EnemyTimer.New ("assist mark target", 5, function ()
			g.markTarget = false
			return true

		end)
	end

	local assist_macro_slot = GetAssistMacroSlot ()
	if (assist_macro_slot)
	then
		Enemy.SetMacro (assist_macro_slot, L"Enemy: Assist "..g.lastAssist, MACRO_TARGET, 214)
	end
end


function Enemy.Mark ()

	local target = Enemy.latestTargets[TargetInfo.HOSTILE_TARGET]
	if (not target or target.hp <= 0) then return end

	if (not Enemy.CanSendIntercomMessage ())
	then
		Enemy.Print ("You must join an intercom channel before using Mark command")
		return
	end

	local message = L"Target::"

	if (target.isNpc)
	then
		message = message..target.name..L":N:"
	else
		message = message..target.name..L":P:"..target.career
	end

	Enemy.IntercomSendMessage ("", message)
end


function Enemy.Target ()
	SendEnemyAssistTarget ()
end


function Enemy.Assist_OnPlayerTargetUpdated (target)

	if (not g.markTarget
		or not g.lastTargetName
		or not target
		or target.isNpc
		or target.name ~= g.lastTargetName
		or target.id == 0) then return end

	ClearNewTargetMark ()
	g.newTargetMarkTemplate:ToggleMark (
		target.id,
		target.name,
		true,
		target.isFriendly,
		target.career)

	g.markedTarget =
	{
		id = target.id,
		name = target.name,
		isFriendly = target.isFriendly,
		career = target.career
	}

	g.markTarget = false

	if (g.markTargetTimer)
	then
		g.markTargetTimer:Remove ()
		g.markTargetTimer = nil
	end
end


function Enemy.TestTarget ()

	if (not Enemy.CanSendIntercomMessage ())
	then
		Enemy.Print ("You must create new or join existed intercom channel before using Mark command")
		return
	end

	Enemy.IntercomSendMessage ("mark", L"EnemyAddon:Mark:Test target:P:123:24")
end


function Enemy.TestTargetNotify ()
	Enemy.AssistUI_Target_Show (L"Test target", 24)
end

--------------------------------------------------------------- UI: Target
function Enemy.AssistUI_Target_Show (text, careerId)

	Enemy.RemoveTask ("targetwindow")
	WindowSetShowing ("EnemyTarget", false)

	if (careerId)
	then
		local tTex, x, y = GetIconData (Icons.GetCareerIconIDFromCareerLine (careerId))
		DynamicImageSetTexture ("EnemyTargetIcon", tTex, x, y)

		WindowSetShowing ("EnemyTargetIcon", true)
	else
		WindowSetShowing ("EnemyTargetIcon", false)
	end

	local display_text = Enemy.toWString (text)
	LabelSetText ("EnemyTargetText", display_text)
	LabelSetText ("EnemyTargetTextShadow", display_text)

	WindowSetShowing ("EnemyTarget", true)
	WindowSetShowing ("EnemyTargetGlow", true)
	WindowSetShowing ("EnemyTargetFlash", true)
	WindowSetShowing ("EnemyTargetSpark", true)
	AnimatedImageStartAnimation ("EnemyTargetGlow", 0, true, true, 0)
	AnimatedImageStartAnimation ("EnemyTargetFlash", 0, true, true, 0)
	AnimatedImageStartAnimation ("EnemyTargetSpark", 0, false, true, 0)
	WindowStartAlphaAnimation ("EnemyTarget", Window.AnimationType.SINGLE_NO_RESET, 0, 1, 0.5, true, 0, 1)

	-- Stop flashing after one quarter of the configured display time.
	local stop_flash_animation_time = Enemy.time + Enemy.Settings.targetShowDelay / 4
	local hide_time = Enemy.time + Enemy.Settings.targetShowDelay

	Enemy.AddTaskAction ("targetwindow",
		function ()
			if (Enemy.time >= stop_flash_animation_time)
			then
				AnimatedImageStopAnimation ("EnemyTargetFlash")
				return true
			end

			return false
		end
	)

	Enemy.AddTaskAction ("targetwindow",
		function ()
			if (Enemy.time >= hide_time)
			then
				WindowSetHandleInput ("EnemyTarget", false)
				WindowStartAlphaAnimation ("EnemyTarget", Window.AnimationType.SINGLE_NO_RESET, 1, 0, 0.2, true, 0, 1)
				return true
			end

			return false
		end
	)

	if (Enemy.Settings.soundOnNewTarget)
	then
		PlaySound (Enemy.Settings.soundOnNewTargetId)
	end
end

function Enemy.AssistUI_Target_OnLButtonDown ()

	if (not g.settings or not g.settings.assistTargetOnNotifyClick) then return end
	SendEnemyAssistTarget ()
end


--------------------------------------------------------------- UI: Configuration
local config_dlg = {}


function Enemy.AssistUI_ConfigDialog_OnInitialize (section)

	config_dlg.section = section

	LabelSetText (config_dlg.section.windowName.."MarkNewTargetLabel", L"Mark new target")
	ButtonSetText (config_dlg.section.windowName.."MarkNewTargetEditTemplateButton", L"edit mark template")
	LabelSetText (config_dlg.section.windowName.."NewTargetSoundLabel", L"Sound on new target")
	LabelSetText (config_dlg.section.windowName.."NewTargetSoundIdLabel", L"Sound")
	LabelSetText (config_dlg.section.windowName.."TargetOnNotifyClickLabel", L"Assist caller by clicking new target notification")

	config_dlg.newTargetSoundIdList = {}

	for k, v in pairs (GameData.Sound)
	do
		table.insert (config_dlg.newTargetSoundIdList, { name = Enemy.toWString (k), id = v })
	end

	table.sort (config_dlg.newTargetSoundIdList, function (a, b)
		return a.name < b.name
	end)

	config_dlg.newTargetSoundIdListById = {}

	for k, v in pairs (config_dlg.newTargetSoundIdList)
	do
		v.index = k
		ComboBoxAddMenuItem (config_dlg.section.windowName.."NewTargetSoundId", v.name)
		config_dlg.newTargetSoundIdListById[v.id] = v
	end

	LabelSetText (config_dlg.section.windowName.."MacrosLabel", L"Macroses (drag them to your hotbar)")

	local macros = DataUtils.GetMacros()
	local assist_macro_slot = GetAssistMacroSlot ()

	if (assist_macro_slot)
	then
		local macro_id = Enemy.GetMacroId (MACRO_MARK)
		if (macro_id)
		then
			local texture, x, y = GetIconData (macros[macro_id].iconNum)
			DynamicImageSetTexture (config_dlg.section.windowName.."MacroMarkIconBase", texture, x, y)
		end

		if (macros[assist_macro_slot])
		then
			local texture, x, y = GetIconData (macros[assist_macro_slot].iconNum)
			DynamicImageSetTexture (config_dlg.section.windowName.."MacroTargetIconBase", texture, x, y)
		end
	end
end


function Enemy.AssistUI_ConfigDialog_OnLoad (_section)

	config_dlg.soundOnNewTarget = Enemy.Settings.soundOnNewTarget
	ButtonSetPressedFlag (config_dlg.section.windowName.."NewTargetSound", config_dlg.soundOnNewTarget)

	config_dlg.markNewTarget = Enemy.Settings.markNewTarget
	config_dlg.newTargetMarkTemplate = EnemyMarkTemplate.New (Enemy.Settings.newTargetMarkTemplate)

	config_dlg.soundOnNewTargetId = Enemy.Settings.soundOnNewTargetId
	ComboBoxSetSelectedMenuItem (config_dlg.section.windowName.."NewTargetSoundId", config_dlg.newTargetSoundIdListById[config_dlg.soundOnNewTargetId].index)

	ButtonSetPressedFlag (config_dlg.section.windowName.."MarkNewTarget", config_dlg.markNewTarget)

	config_dlg.assistTargetOnNotifyClick = Enemy.Settings.assistTargetOnNotifyClick
	ButtonSetPressedFlag (config_dlg.section.windowName.."TargetOnNotifyClick", config_dlg.assistTargetOnNotifyClick)
end


function Enemy.AssistUI_ConfigDialog_OnNewTargetSoundChanged ()
	config_dlg.soundOnNewTarget = not config_dlg.soundOnNewTarget
	ButtonSetPressedFlag (config_dlg.section.windowName.."NewTargetSound", config_dlg.soundOnNewTarget)
end


function Enemy.AssistUI_ConfigDialog_OnMarkNewTargetChanged ()
	config_dlg.markNewTarget = not config_dlg.markNewTarget
	ButtonSetPressedFlag (config_dlg.section.windowName.."MarkNewTarget", config_dlg.markNewTarget)
end

function Enemy.AssistUI_ConfigDialog_OnNewTargetSoundIdSelChanged ()

	local index = ComboBoxGetSelectedMenuItem (config_dlg.section.windowName.."NewTargetSoundId")
	if (index < 1) then return end

	PlaySound (config_dlg.newTargetSoundIdList[index].id)
end

function Enemy.AssistUI_ConfigDialog_MarkNewTargetEditTemplate ()
	config_dlg.newTargetMarkTemplate:Edit ()
end


function Enemy.AssistUI_ConfigDialog_OnTargetOnNotifyClickChanged ()
	config_dlg.assistTargetOnNotifyClick = not config_dlg.assistTargetOnNotifyClick
	ButtonSetPressedFlag (config_dlg.section.windowName.."TargetOnNotifyClick", config_dlg.assistTargetOnNotifyClick)
end


local function OnMacroMouseDrag (text)

	if (not GetAssistMacroSlot ()) then return end

	if (not Cursor.IconOnCursor())
	then
		local macro_id
		if (type (text) == "number")
		then
			macro_id = text
		else
			macro_id = Enemy.GetMacroId (text)
		end

		local macros = DataUtils.GetMacros ()

		Cursor.PickUp (Cursor.SOURCE_MACRO, macro_id, macro_id, macros[macro_id].iconNum, false)
		EA_Window_Macro.UpdateDetails (macro_id)
	end
end


function Enemy.AssistUI_ConfigDialog_OnMacroMarkMouseDrag ()
	OnMacroMouseDrag (MACRO_MARK)
end


function Enemy.AssistUI_ConfigDialog_OnMacroTargetMouseDrag ()
	local assist_macro_slot = GetAssistMacroSlot ()
	if (assist_macro_slot)
	then
		OnMacroMouseDrag (assist_macro_slot)
	end
end


function Enemy.AssistUI_ConfigDialog_OnMacroMarkMouseOver ()
	Tooltips.CreateTextOnlyTooltip (config_dlg.section.windowName.."MacroMark")
	Tooltips.SetTooltipText (1, 1, L"Mark")
	Tooltips.SetTooltipText (2, 1, L"This macro will mark the selected enemy")
	Tooltips.SetTooltipText (3, 1, L"and broadcast it to the intercom channel")
	Tooltips.AnchorTooltip (Tooltips.ANCHOR_CURSOR)
	Tooltips.Finalize()
end


function Enemy.AssistUI_ConfigDialog_OnMacroTargetMouseOver ()
	Tooltips.CreateTextOnlyTooltip (config_dlg.section.windowName.."MacroTarget")
	Tooltips.SetTooltipText (1, 1, L"Target")
	Tooltips.SetTooltipText (2, 1, L"Assists the last Enemy caller")
	Tooltips.AnchorTooltip (Tooltips.ANCHOR_CURSOR)
	Tooltips.Finalize()
end


function Enemy.AssistUI_ConfigDialog_OnReset (_section)

	Enemy.Settings.soundOnNewTarget = nil
	Enemy.Settings.soundOnNewTargetId = nil
	Enemy.Settings.markNewTarget = nil
	Enemy.Settings.newTargetMarkTemplate = nil
	Enemy.Settings.assistTargetOnNotifyClick = nil

	Enemy.Print ("Assist settings has been reset")
	InterfaceCore.ReloadUI ()
end


function Enemy.AssistUI_ConfigDialog_OnSave (_section)

	Enemy.Settings.soundOnNewTarget = config_dlg.soundOnNewTarget
	Enemy.Settings.soundOnNewTargetId = config_dlg.newTargetSoundIdList[ComboBoxGetSelectedMenuItem (config_dlg.section.windowName.."NewTargetSoundId")].id

	Enemy.Settings.markNewTarget = config_dlg.markNewTarget
	Enemy.Settings.newTargetMarkTemplate = config_dlg.newTargetMarkTemplate

	Enemy.Settings.assistTargetOnNotifyClick = config_dlg.assistTargetOnNotifyClick

	return true
end

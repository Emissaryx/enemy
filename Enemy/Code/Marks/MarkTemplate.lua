local Enemy = Enemy

local tinsert = table.insert
local setmetatable = setmetatable
local pairs = pairs
local ipairs = ipairs
local unpack = unpack
local tostring = tostring

local MARK_WIDTH = 100
local MARK_HEIGHT = 200
local DEFAULT_MARK_SHAPE = "enemy_mark_arrowdown"

local function UsesBuiltInShapeColors (shape)
	return shape == "enemy_mark_arrow_heart" or shape == "enemy_mark_arrow_diamond"
		or shape == "enemy_mark_arrow_moon" or shape == "enemy_mark_arrow_skull"
		or shape == "enemy_mark_arrow_sugar_skull"
		or shape == "enemy_mark_arrow_crosshair" or shape == "enemy_mark_arrow_lightning"
		or shape == "enemy_mark_arrow_eye"
		or shape == "enemy_mark_arrow_crosshair_grim" or shape == "enemy_mark_arrow_lightning_grim"
		or shape == "enemy_mark_arrow_eye_grim"
		or shape == "enemy_mark_arrow_shield" or shape == "enemy_mark_arrow_shield_red"
		or shape == "enemy_mark_arrow_poop" or shape == "enemy_mark_arrow_crown_emoji"
		or shape == "enemy_mark_arrow_pill_red" or shape == "enemy_mark_arrow_pill_blue"
end


EnemyMarkTemplate = {}
EnemyMarkTemplate.__index = EnemyMarkTemplate
EnemyMarkTemplate.UsesBuiltInShapeColors = UsesBuiltInShapeColors


function EnemyMarkTemplate.New (data)
	local obj = {}
	setmetatable (obj, EnemyMarkTemplate)

	obj.id = Enemy.NewId ()
	obj.name = L""
	obj.color = { 255, 255, 255 }
	obj.alpha = 1.0
	obj.scale = 1.0
	obj.showCareerIcon = true
	obj.shape = DEFAULT_MARK_SHAPE
	obj.layer = Window.Layers.POPUP
	obj.offsetY = 50
	obj.targetOnClick = true
	obj.display = 2
	obj.text = L""
	obj.firstLetters = 4
	obj.font = "font_clear_large_bold"
	obj.canClearOnClick = true
	obj.neverExpire = false
	obj.unique = false

	obj.permanent = false
	obj.permanentTargets = {}

	obj._activeMarks = {}

	if (data)
	then
		obj:Load (data)
	end

	return obj
end


function EnemyMarkTemplate:Load (data)

	self.name = data.name

	if (data.color) then self.color = Enemy.clone (data.color) end
	self.alpha = data.alpha
	self.scale = data.scale
	self.showCareerIcon = data.showCareerIcon
	self.shape = data.shape or DEFAULT_MARK_SHAPE
	self.layer = data.layer
	self.offsetY = data.offsetY
	self.targetOnClick = data.targetOnClick
	self.display = data.display
	self.text = data.text
	self.firstLetters = data.firstLetters
	self.font = data.font or self.font
	self.canClearOnClick = data.canClearOnClick
	self.neverExpire = data.neverExpire
	self.unique = data.unique

	self.permanent = data.permanent
	if (data.permanentTargets)
	then
		self.permanentTargets = {}

		for k in pairs (data.permanentTargets)
		do
			local playerName = Enemy.NormalizePlayerName (k)
			if (playerName and playerName ~= L"")
			then
				self.permanentTargets[playerName] = false
			end
		end
	end

	self:Update ()
end


function EnemyMarkTemplate:Apply (windowName, objectName, isPlayer, isFriendly, careerId)

	WindowSetScale (windowName, self.scale)
	WindowSetLayer (windowName, self.layer)

	if (self.targetOnClick and isPlayer)
	then
		WindowSetHandleInput (windowName, true)

		if (isFriendly)
		then

			WindowSetGameActionData (windowName.."Content", GameData.PlayerActions.SET_TARGET, 0, objectName)
		end
	else
		WindowSetGameActionData (windowName.."Content", GameData.PlayerActions.SET_TARGET, 0, objectName)
		WindowSetHandleInput (windowName, false)
	end

	WindowSetAlpha (windowName.."Content", self.alpha)
	DynamicImageSetTexture (windowName.."ContentBackground", self.shape or DEFAULT_MARK_SHAPE, 0, 0)
	if (UsesBuiltInShapeColors (self.shape))
	then
		WindowSetTintColor (windowName.."ContentBackground", 255, 255, 255)
	else
		WindowSetTintColor (windowName.."ContentBackground", unpack (self.color))
	end

	if (self.offsetY >= 0)
	then
		WindowSetDimensions (windowName, MARK_WIDTH, MARK_HEIGHT + self.offsetY)
		WindowClearAnchors (windowName.."Content")
		WindowAddAnchor (windowName.."Content", "topleft", windowName, "topleft", 0, 0)
	else
		WindowSetDimensions (windowName, MARK_WIDTH, MARK_HEIGHT)
		WindowClearAnchors (windowName.."Content")
		WindowAddAnchor (windowName.."Content", "topleft", windowName, "topleft", 0, -self.offsetY)
	end

	-- force position update
	local object_window = Enemy.GetObjectWindow (windowName)
	if (object_window ~= nil) then object_window:Attach () end

	if (self.showCareerIcon and careerId and careerId > 0)
	then
		local icon, icon_x, icon_y = GetIconData (Icons.GetCareerIconIDFromCareerLine (careerId))
		DynamicImageSetTexture (windowName.."ContentIcon", icon, icon_x, icon_y)
		WindowSetShowing (windowName.."ContentIcon", true)
	else
		WindowSetShowing (windowName.."ContentIcon", false)
	end

	LabelSetFont (windowName.."ContentText", self.font, WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
	LabelSetText (windowName.."ContentText", L"")
	WindowSetDimensions (windowName.."ContentText", 200, 200)

	if (self.display == 1)
	then
		LabelSetText (windowName.."ContentText", Enemy.toWStringOrEmpty (self.text))
	elseif (objectName)
	then
		LabelSetText (windowName.."ContentText", Enemy.toWStringOrEmpty (objectName:sub (1, self.firstLetters)))
	end

	local text_real_dx, text_real_dy = LabelGetTextDimensions (windowName.."ContentText")
	WindowSetDimensions (windowName.."ContentText", text_real_dx, text_real_dy)
end


function EnemyMarkTemplate:ToggleMark (objectId, objectName, isPlayer, isFriendly, careerId)

	if (objectId == 0) then return end

	objectName = Enemy.FixString (objectName)
	if (isPlayer)
	then
		objectName = Enemy.NormalizePlayerName (objectName)
	end

	local window_name = "EnemyMark"
	if (isPlayer)
	then
		window_name = window_name..tostring (objectName)
	else
		window_name = window_name..objectId
	end

	local object_window = Enemy.GetObjectWindow (window_name)

	if (object_window ~= nil)
	then
		object_window:Remove ()

		if (object_window.data.template == self)
		then
			if (self.permanent and isPlayer and self.permanentTargets[objectName] ~= nil)
			then
				self.permanentTargets[objectName] = nil
			end

			return
		end
	end

	if (self.unique)
	then
		self:ClearMarks (true)
	end

	-- create mark
	CreateWindowFromTemplate (window_name, "EnemyMark", "Root")
	WindowSetShowing (window_name, false)

	-- register it
	local active_mark =
	{
		objectId = objectId,
		objectName = objectName,
		isPlayer = isPlayer,
		isFriendly = isFriendly,
		careerId = careerId,
		windowName = window_name,
		t = Enemy.time
	}

	tinsert (self._activeMarks, active_mark)

	if (isPlayer and self.permanent)
	then
		self.permanentTargets[objectName] = true
	end

	-- apply
	self:Apply (window_name, objectName, isPlayer, isFriendly, careerId)

	-- attach to world object
	local ow_data =
	{
		windowName = window_name,
		id = objectId,

		data =
		{
			template = self,
			isMark = true,
			manualTargetOnClick = self.targetOnClick and isPlayer and not isFriendly,
			canClearOnClick = self.canClearOnClick
		},

		removeCallback = function (item)

			local template = item.data.template

			for k, mark in ipairs (template._activeMarks)
			do
				if (mark.objectId == item.id)
				then
					table.remove (template._activeMarks, k)
					break
				end
			end

			if (item.playerName and template.permanentTargets[item.playerName] == true)
			then
				template.permanentTargets[item.playerName] = false
			end

			if (DoesWindowExist (item.windowName))
			then
				DestroyWindow (item.windowName)
			end
		end
	}

	if (self.neverExpire)
	then
		ow_data.inactiveTimeout = -1
	end

	if (isPlayer)
	then
		ow_data.playerName = objectName
	end

	EnemyObjectWindow.New (ow_data)
	WindowSetShowing (window_name, false)
end


function Enemy.MarkUI_EnemyMark_OnRButtonUp (flags)

	if (not Enemy.IsShiftPressed(flags)) then return end

	local object_window = Enemy.GetObjectWindow (WindowGetParent (SystemData.MouseOverWindow.name))
	if (not object_window or not object_window.data.canClearOnClick) then return end

	local template = object_window.data.template
	if (template.permanent and object_window.playerName and template.permanentTargets[object_window.playerName] ~= nil)
	then
		template.permanentTargets[object_window.playerName] = nil
	end

	object_window:Remove ()
end


function Enemy.MarkUI_EnemyMark_OnLButtonDown ()

	local object_window = Enemy.GetObjectWindow (WindowGetParent (SystemData.MouseOverWindow.name))
	if (object_window == nil or not object_window.data.manualTargetOnClick) then return end

	Enemy.SendChatMessage (L"/target "..Enemy.FixString (object_window.playerName))
end


function EnemyMarkTemplate:Update ()

	for _, mark in ipairs (self._activeMarks)
	do
		self:Apply (mark.windowName, mark.objectName, mark.isPlayer, mark.isFriendly, mark.careerId)
	end
end


function EnemyMarkTemplate:ClearMarks (clearPermanentTargets)

	local object_windows_to_remove = {}

	for _, mark in ipairs (self._activeMarks)
	do
		tinsert (object_windows_to_remove, mark.windowName)
	end

	self._activeMarks = {}

	for _, v in ipairs (object_windows_to_remove)
	do
		local object_window = Enemy.GetObjectWindow (v)
		if (not object_window) then continue end

		object_window:Remove ()
	end

	if (clearPermanentTargets)
	then
		self.permanentTargets = {}
	end
end


function EnemyMarkTemplate:Edit (onOkCallback)
	Enemy.MarksUI_MarkConfigDialog_Open (self, onOkCallback)
end



----------------------------------------------------------------- UI: Mark config dialog
local config_dlg =
{
	isInitialized = false,
	properties =
	{
		name =
		{
			key = "name",
			order = 10,
			name = L"Name",
			type = "string"
		},
		color =
		{
			key = "color",
			order = 20,
			name = L"Color",
			type = "color",
			default = {255, 255, 255},
			paddingTop = 6,
			tooltip = L"Template RGB colors apply to single-color arrows. Heart, Diamond, Moon, both Skulls, both Crosshairs, both Lightnings, both Eyes, both Shields, Poop, Crown Emoji, and both Pills keep their built-in colors."
		},
		shape =
		{
			key = "shape",
			order = 15,
			name = L"Arrow shape",
			type = "shapePicker",
			windowWidth = 720,
			onCreate = function (wnp, p) Enemy.MarksUI_MarkConfigDialog_CreateShapeSelector (wnp, p) end,
			onLoad = function (wnp, p, data) Enemy.MarksUI_MarkConfigDialog_LoadShapeSelector (wnp, p, data) end,
			onSave = function (wnp, p, data) Enemy.MarksUI_MarkConfigDialog_SaveShapeSelector (wnp, p, data) end,
			default = DEFAULT_MARK_SHAPE,
			paddingTop = 6,
			values =
			{
				{ text = L"Split arrow", value = "enemy_mark_arrowdown" },
				{ text = L"Old solid arrow", value = "enemy_mark_arrowdown_old" },
				{ text = L"Broadhead", value = "enemy_mark_arrow_broadhead" },
				{ text = L"Double chevron", value = "enemy_mark_arrow_chevron" },
				{ text = L"Spear point", value = "enemy_mark_arrow_spearpoint" },
				{ text = L"Sun point", value = "enemy_mark_arrow_sun" },
				{ text = L"Crown", value = "enemy_mark_arrow_crown" },
				{ text = L"Crown Emoji", value = "enemy_mark_arrow_crown_emoji" },
				{ text = L"Shield", value = "enemy_mark_arrow_shield" },
				{ text = L"Red Shield", value = "enemy_mark_arrow_shield_red" },
				{ text = L"Healer cross", value = "enemy_mark_arrow_healer_cross" },
				{ text = L"Heart", value = "enemy_mark_arrow_heart" },
				{ text = L"Diamond", value = "enemy_mark_arrow_diamond" },
				{ text = L"Crescent Moon", value = "enemy_mark_arrow_moon" },
				{ text = L"Crosshair Emoji", value = "enemy_mark_arrow_crosshair" },
				{ text = L"Grim Crosshair", value = "enemy_mark_arrow_crosshair_grim" },
				{ text = L"Lightning Emoji", value = "enemy_mark_arrow_lightning" },
				{ text = L"Grim Lightning", value = "enemy_mark_arrow_lightning_grim" },
				{ text = L"Eye Emoji", value = "enemy_mark_arrow_eye" },
				{ text = L"Grim Eye", value = "enemy_mark_arrow_eye_grim" },
				{ text = L"Skull", value = "enemy_mark_arrow_skull" },
				{ text = L"Sugar Skull Emoji", value = "enemy_mark_arrow_sugar_skull" },
				{ text = L"Poop Emoji", value = "enemy_mark_arrow_poop" },
				{ text = L"Red Pill Emoji", value = "enemy_mark_arrow_pill_red" },
				{ text = L"Blue Pill Emoji", value = "enemy_mark_arrow_pill_blue" }
			}
		},
		scale =
		{
			key = "scale",
			order = 25,
			name = L"Scale",
			type = "float",
			default = 1,
			min = 0,
			max = 5,
			paddingTop = 6
		},
		alpha =
		{
			key = "alpha",
			order = 30,
			name = L"Opacity",
			type = "float",
			default = 1,
			min = 0,
			max = 1,
			paddingTop = 6
		},
		layer =
		{
			key = "layer",
			order = 40,
			name = L"Layer",
			type = "select",
			default = Window.Layers.POPUP,
			values = Enemy.ConfigurationWindowGetLayersSelectValues,
			paddingTop = 6
		},
		offsetY =
		{
			key = "offsetY",
			order = 50,
			name = L"Offset (Y)",
			type = "int",
			default = 50,
			min = 0,
			max = 1000,
			paddingTop = 6
		},

		showCareerIcon =
		{
			key = "showCareerIcon",
			order = 60,
			name = L"Show career icon",
			type = "bool",
			default = true,
			paddingTop = 18
		},
		targetOnClick =
		{
			key = "targetOnClick",
			order = 70,
			name = L"Target on click",
			type = "bool",
			default = true,
			paddingTop = 6,
			tooltip = L"If checked then clicking on mark will target the marked player. Will not work on mobs and will work on enemies with slight delay but only if they are close enough. With this checked on you can shift right-click on mark to remove it."
		},
		permanent =
		{
			key = "permanent",
			order = 75,
			name = L"Permanent",
			type = "bool",
			default = false,
			paddingTop = 6,
			tooltip = L"Check to store all marked players even after relog. Will not work on mobs. Stored player will be automarked again when mouseovered or targeted."
		},
		unique =
		{
			key = "unique",
			order = 76,
			name = L"Unique",
			type = "bool",
			default = false,
			paddingTop = 6,
			tooltip = L"If checked then this mark will be put only on one latest target."
		},

		font =
		{
			key = "font",
			order = 80,
			name = L"Font",
			type = "select",
			default = "font_clear_large_bold",
			values = Enemy.ConfigurationWindowGetFontsSelectValues,
			paddingTop = 18
		},
		display =
		{
			key = "display",
			order = 90,
			name = L"Display",
			type = "select",
			default = "font_clear_large_bold",
			paddingTop = 6,
			values =
			{
				{ text = L"text", value = 1 },
				{ text = L"first N letters", value = 2 }
			}
		}
	},
	propertiesByDisplayType =
	{
		{
			text =
			{
				key = "text",
				order = 10,
				name = L"Text",
				type = "string",
				paddingTop = 6
			}
		},
		{
			firstLetters =
			{
				key = "firstLetters",
				order = 10,
				name = L"N",
				type = "integer",
				min = 1,
				max = 100,
				paddingTop = 6,
				default = 4
			}
		}
	}
}

local function GetMarkShapeOption (shape)
	for _, option in ipairs (config_dlg.properties.shape.values)
	do
		if (option.value == shape) then return option end
	end

	return nil
end


function Enemy.MarksUI_MarkConfigDialog_CreateShapeSelector (windowName, property)
	CreateWindowFromTemplate (windowName, "EnemyMarkTemplateShapeSelectorTemplate", config_dlg.cwn)
	LabelSetText (windowName.."Label", property.name)
end


function Enemy.MarksUI_MarkConfigDialog_UpdateShapeSelector (windowName, shape)
	local option = GetMarkShapeOption (shape) or GetMarkShapeOption (DEFAULT_MARK_SHAPE)
	if (not option) then return end
	shape = option.value

	DynamicImageSetTexture (windowName.."ValueIcon", shape, 0, 0)
	DynamicImageSetTextureDimensions (windowName.."ValueIcon", 100, 200)
	if (UsesBuiltInShapeColors (shape) or not config_dlg.data.color)
	then
		WindowSetTintColor (windowName.."ValueIcon", 255, 255, 255)
	else
		WindowSetTintColor (windowName.."ValueIcon", unpack (config_dlg.data.color))
	end
	LabelSetText (windowName.."ValueName", option.text)
end


function Enemy.MarksUI_MarkConfigDialog_LoadShapeSelector (windowName, property, data)
	if (not data.shape) then data.shape = DEFAULT_MARK_SHAPE end
	if (not GetMarkShapeOption (data.shape)) then data.shape = DEFAULT_MARK_SHAPE end
	Enemy.MarksUI_MarkConfigDialog_UpdateShapeSelector (windowName, data.shape)
end


function Enemy.MarksUI_MarkConfigDialog_SaveShapeSelector (windowName, property, data)
	data.shape = data.shape or DEFAULT_MARK_SHAPE
end


function Enemy.MarksUI_MarkConfigDialog_OpenShapePicker ()
	if (not config_dlg.shapePickerInitialized)
	then
		CreateWindow ("EnemyMarkShapePicker", false)
		LabelSetText ("EnemyMarkShapePickerTitleBarText", L"Choose arrow shape")
		config_dlg.shapePickerInitialized = true
	end

	Enemy.markShapePickerData = config_dlg.properties.shape.values
	local displayOrder = {}
	for index = 1, #Enemy.markShapePickerData
	do
		displayOrder[index] = index
	end
	ListBoxSetDisplayOrder ("EnemyMarkShapePickerList", displayOrder)
	WindowSetLayer ("EnemyMarkShapePicker", Window.Layers.OVERLAY)
	WindowSetShowing ("EnemyMarkShapePicker", true)
end


function Enemy.MarksUI_MarkConfigDialog_HideShapePicker ()
	WindowSetShowing ("EnemyMarkShapePicker", false)
end


function Enemy.MarksUI_MarkConfigDialog_PopulateShapePicker ()
	local list = EnemyMarkShapePickerList
	if (not list or not list.PopulatorIndices) then return end

	for rowIndex, dataIndex in ipairs (list.PopulatorIndices)
	do
		local option = Enemy.markShapePickerData[dataIndex]
		local rowName = "EnemyMarkShapePickerListRow"..rowIndex
		if (not option) then continue end

		DynamicImageSetTexture (rowName.."Icon", option.value, 0, 0)
		DynamicImageSetTextureDimensions (rowName.."Icon", 100, 200)
		if (UsesBuiltInShapeColors (option.value) or not config_dlg.data.color)
		then
			WindowSetTintColor (rowName.."Icon", 255, 255, 255)
		else
			WindowSetTintColor (rowName.."Icon", unpack (config_dlg.data.color))
		end
		LabelSetText (rowName.."Name", option.text)
	end
end


function Enemy.MarksUI_MarkConfigDialog_SelectShape ()
	local activeWindowName = SystemData.ActiveWindow and SystemData.ActiveWindow.name
	if (not activeWindowName) then return end
	local rowIndex = tonumber (activeWindowName:match ("EnemyMarkShapePickerListRow(%d+)Select"))
	if (not rowIndex) then return end

	local dataIndex = ListBoxGetDataIndex ("EnemyMarkShapePickerList", rowIndex)
	local option = dataIndex and Enemy.markShapePickerData[dataIndex]
	if (not option) then return end

	config_dlg.data.shape = option.value
	Enemy.MarksUI_MarkConfigDialog_UpdateShapeSelector (config_dlg.cwn.."___shape___", option.value)
	WindowSetShowing ("EnemyMarkShapePicker", false)
	Enemy.MarksUI_MarkConfigDialog_TestSettings ()
end


function Enemy.MarksUI_MarkConfigDialog_IsOpen ()
	return WindowGetShowing ("EnemyMarkConfigDialog")
end


function Enemy.MarksUI_MarkConfigDialog_Hide ()
	WindowSetShowing ("EnemyMarkConfigDialog", false)
	if (config_dlg.shapePickerInitialized) then WindowSetShowing ("EnemyMarkShapePicker", false) end
end


local function OnDisplayPropertyChanged ()

	config_dlg.isLoading = true

	local root2 = "EnemyMarkConfigDialogConfig2"
	config_dlg.cwn2 = root2.."W"

	if (DoesWindowExist (config_dlg.cwn2))
	then
		Enemy.ConfigurationWindowSaveData (config_dlg.cwn2, config_dlg.data)
		DestroyWindow (config_dlg.cwn2)
	end

	local width, height = Enemy.CreateConfigurationWindow (config_dlg.cwn2, root2, config_dlg.propertiesByDisplayType[config_dlg.data.display], Enemy.MarksUI_MarkConfigDialog_TestSettings2)
	WindowSetDimensions (root2, width, height)

	Enemy.ConfigurationWindowLoadData (config_dlg.cwn2, config_dlg.data)

	config_dlg.isLoading = false
end


function Enemy.MarksUI_MarkConfigDialog_Open (template, onOkCallback)

	if (not config_dlg.isInitialized)
	then
		-- initialize dialog UI
		CreateWindow ("EnemyMarkConfigDialog", false)
		LabelSetText ("EnemyMarkConfigDialogTitleBarText", L"Edit mark template")
		ButtonSetText ("EnemyMarkConfigDialogOkButton", L"OK")
		ButtonSetText ("EnemyMarkConfigDialogCancelButton", L"Cancel")

		local root = "EnemyMarkConfigDialogConfig"
		config_dlg.cwn = root.."W"
		local width, height = Enemy.CreateConfigurationWindow (config_dlg.cwn, root, config_dlg.properties, Enemy.MarksUI_MarkConfigDialog_TestSettings)
		WindowSetDimensions (root, width, height)

		config_dlg.isInitialized = true
	end

	-- proceed parameters
	config_dlg.template = template
	config_dlg.onOkCallback = onOkCallback

	config_dlg.data = EnemyMarkTemplate.New (template)
	if (config_dlg.cwn2 and DoesWindowExist (config_dlg.cwn2))
	then
		DestroyWindow (config_dlg.cwn2)
	end

	config_dlg.exampleCareerId = math.random (24)
	config_dlg.exampleObjectName = "Abcdefghijklmnopqrstuvwxyz"

	-- fill form
	config_dlg.isLoading = true

	Enemy.ConfigurationWindowLoadData (config_dlg.cwn, config_dlg.data)
	OnDisplayPropertyChanged ()

	config_dlg.isLoading = false

	WindowSetLayer ("EnemyMarkConfigDialog", Window.Layers.OVERLAY)
	WindowSetShowing ("EnemyMarkConfigDialog", true)
	Enemy.MarksUI_MarkConfigDialog_TestSettings ()
end

function Enemy.MarksUI_MarkConfigDialog_TestSettings ()

	if (config_dlg.isLoading) then return end

	Enemy.ConfigurationWindowSaveData (config_dlg.cwn, config_dlg.data)
	Enemy.MarksUI_MarkConfigDialog_UpdateShapeSelector (config_dlg.cwn.."___shape___", config_dlg.data.shape)
	OnDisplayPropertyChanged ()

	Enemy.MarksUI_MarkConfigDialog_UpdateExample ()
end


function Enemy.MarksUI_MarkConfigDialog_TestSettings2 ()
	if (config_dlg.isLoading) then return end

	Enemy.ConfigurationWindowSaveData (config_dlg.cwn2, config_dlg.data)
	Enemy.MarksUI_MarkConfigDialog_UpdateExample ()
end


function Enemy.MarksUI_MarkConfigDialog_UpdateExample ()
	config_dlg.data:Apply ("EnemyMarkConfigDialogExample",
								config_dlg.exampleObjectName,
								false,
								false,
								config_dlg.exampleCareerId)
end


function Enemy.MarksUI_MarkConfigDialog_Ok ()

	Enemy.MarksUI_MarkConfigDialog_TestSettings ()

	config_dlg.template:Load (config_dlg.data)

	if (config_dlg.onOkCallback)
	then
		config_dlg.onOkCallback (config_dlg.template)
	end

	Enemy.MarksUI_MarkConfigDialog_Hide ()
end

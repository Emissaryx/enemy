local Enemy = Enemy
local g
local properties =
{
	font =		{ key = "font",			order = 1,		name = L"Font",					type = "select",						default = "font_clear_medium_bold",						values = Enemy.ConfigurationWindowGetFontsSelectValues },
	align =		{ key = "align",		order = 2,		name = L"Align",				type = "select",						default = "left",										values = Enemy.ConfigurationWindowGetTextAlignsSelectValues }
}


function Enemy.UnitFramesParts_LevelTextInitialize ()
	g = Enemy.unitFramesParts

	g.types["levelText"] =
	{
		key = "levelText",
		name = L"Level text",
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

		OnRemove = Enemy.UnitFramePart_OnRemove,

		OnBind = function (part)

			local t = part._t

			t.cache = {}

			t.windowName = Enemy.UnitFramePart_CreateWindow (part, "EA_Label_DefaultText")

			Enemy.UnitFramePart_OnUpdate_ProceedTextWindowInitialization (part)
		end,

		OnUpdate = function (part, player)

			local t = part._t
			local cache = t.cache

			if (cache.level ~= player.level)
			then
				cache.level = player.level
				LabelSetText (t.windowName, Enemy.toWStringOrEmpty (cache.level))
			end

			Enemy.UnitFramePart_OnUpdate_ProceedTextState (part, player)
		end
	}
    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.RegisterPartType (g.types["levelText"]) end
end




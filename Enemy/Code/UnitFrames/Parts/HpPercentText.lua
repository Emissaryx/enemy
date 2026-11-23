local Enemy = Enemy
local g
local properties =
{
	font =		{ key = "font",			order = 1,		name = L"Font",					type = "select",						default = "font_clear_medium_bold",						values = Enemy.ConfigurationWindowGetFontsSelectValues },
	align =		{ key = "align",		order = 2,		name = L"Align",				type = "select",						default = "left",										values = Enemy.ConfigurationWindowGetTextAlignsSelectValues },
	prefix =	{ key = "prefix",		order = 3,		name = L"Prefix",				type = "string",						default = L"" },
	suffix =	{ key = "suffix",		order = 4,		name = L"Suffix",				type = "string",						default = L"%" }
}


function Enemy.UnitFramesParts_HpPercentTextInitialize ()
	g = Enemy.unitFramesParts

	g.types["hppText"] =
	{
		key = "hppText",
		name = L"HP % text",
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
			local data = part.data
			local cache = t.cache

			if (cache.hp ~= player.hp)
			then
				cache.hp = player.hp
				LabelSetText (t.windowName, Enemy.toWStringOrEmpty (data.prefix)..Enemy.toWStringOrEmpty (cache.hp)..Enemy.toWStringOrEmpty (data.suffix))
			end

			Enemy.UnitFramePart_OnUpdate_ProceedTextState (part, player)
		end
	}
    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.RegisterPartType (g.types["hppText"]) end
end




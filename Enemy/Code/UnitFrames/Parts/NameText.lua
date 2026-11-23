local Enemy = Enemy
local g
local properties =
{
	font =		{ key = "font",			order = 1,		name = L"Font",					type = "select",						default = "font_clear_medium_bold",						values = Enemy.ConfigurationWindowGetFontsSelectValues },
	align =		{ key = "align",		order = 2,		name = L"Align",				type = "select",						default = "left",										values = Enemy.ConfigurationWindowGetTextAlignsSelectValues },
	maxLength =	{ key = "maxLength",	order = 3,		name = L"Max length",			type = "int",							default = nil,					min = 1,				max = nil },
	wrap =		{ key = "wrap",			order = 4,		name = L"Word wrap",			type = "bool",							default = false }
}


function Enemy.UnitFramesParts_NameTextInitialize ()
	g = Enemy.unitFramesParts

	g.types["nameText"] =
	{
		key = "nameText",
		name = L"Name text",
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

			if (cache.name ~= player.name or cache.maxLength ~= data.maxLength)
			then
				cache.name = player.name
				cache.maxLength = data.maxLength
				local text = cache.name

				if (data.maxLength and text)
				then
					text = text:sub (1, data.maxLength)
				end

				LabelSetText (t.windowName, text)
			end

			Enemy.UnitFramePart_OnUpdate_ProceedTextState (part, player)
		end
	}
    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.RegisterPartType (g.types["nameText"]) end
end



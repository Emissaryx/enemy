local Enemy = Enemy
local g
local properties =
{
	texture =	{ key = "texture",		order = 1,		name = L"Texture",				type = "select",	default = "default",		values = Enemy.UnitFramePart_GetTexturesSelectValues }
}


function Enemy.UnitFramesParts_PanelInitialize ()
	g = Enemy.unitFramesParts

	g.types["panel"] =
	{
		key = "panel",
		name = L"Panel",
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
			local data = part.data

			t.cache = {}

			t.windowName = Enemy.UnitFramePart_CreateWindow (part, "EA_DynamicImage_DefaultSeparatorRight")

			Enemy.UnitFramePart_OnUpdate_ProceedWindowInitialization (part)
			Enemy.UnitFramePart_ApplyTexture (data.texture, t.windowName)
		end,

		OnUpdate = Enemy.UnitFramePart_OnUpdate_ProceedState
	}
    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.RegisterPartType (g.types["panel"]) end
end




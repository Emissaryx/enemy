local Enemy = Enemy
local g
local properties =
{
	texture =			{ key = "texture",				order = 1,		name = L"Texture",				type = "select",						default = "default",			values = Enemy.UnitFramePart_GetTexturesSelectValues },
	vertical =			{ key = "vertical",				order = 2,		name = L"Vertical mode",		type = "bool",							default = false },
	textureFullResize =	{ key = "textureFullResize",	order = 3,		name = L"Full resize",			type = "bool",							default = false }
}


function Enemy.UnitFramesParts_HpBarInitialize ()
	g = Enemy.unitFramesParts

	g.types["hpbar"] =
	{
		key = "hpbar",
		name = L"HP Bar",
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

		OnUpdate = function (part, player)

			local t = part._t
			local cache = t.cache

			if (cache.hp ~= player.hp)
			then
				cache.hp = player.hp

				if (cache.hp == 0)
				then
					cache.hideByDefult = true
				else
					cache.hideByDefult = false

					Enemy.UnitFramePart_ApplyTexturePercentResize (part, 0.01 * cache.hp)
				end
			end

			Enemy.UnitFramePart_OnUpdate_ProceedState (part, player, cache.hideByDefult)
		end
	}
    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.RegisterPartType (g.types["hpbar"]) end
end


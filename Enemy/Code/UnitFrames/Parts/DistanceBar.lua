local Enemy = Enemy
local g
local properties =
{
	texture =			{ key = "texture",				order = 1,		name = L"Texture",						type = "select",						default = "3bars",			values = Enemy.UnitFramePart_GetTexturesSelectValues },
	vertical =			{ key = "vertical",				order = 2,		name = L"Vertical mode",				type = "bool",							default = false },
	textureFullResize =	{ key = "textureFullResize",	order = 3,		name = L"Full resize",					type = "bool",							default = false },
	level1 =			{ key = "level1",				order = 4,		name = L"The 1st level distance",		type = "int",							default = 65,					min = 0,					max = 1000 },
	color1 =			{ key = "color1",				order = 5,		name = L"The 1st level color",			type = "color",			size = 3,		default = {190, 255, 50},		min = {0, 0, 0},			max = {255, 255, 255} },
	level2 =			{ key = "level2",				order = 6,		name = L"The 2nd level distance",		type = "int",							default = 100,					min = 0,					max = 1000 },
	color2 =			{ key = "color2",				order = 7,		name = L"The 2st level color",			type = "color",			size = 3,		default = {255, 190, 50},		min = {0, 0, 0},			max = {255, 255, 255} },
	level3 =			{ key = "level3",				order = 8,		name = L"The 3rd level distance",		type = "int",							default = 150,					min = 0,					max = 1000 },
	color3 =			{ key = "color3",				order = 9,		name = L"The 3st level color",			type = "color",			size = 3,		default = {255, 75, 75},		min = {0, 0, 0},			max = {255, 255, 255} }
}


function Enemy.UnitFramesParts_DistanceBarInitialize ()
	g = Enemy.unitFramesParts

	Enemy.UnitFramePlayerUpdateFilters.Distance.Parts["distanceBar"] = true

	g.types["distanceBar"] =
	{
		key = "distanceBar",
		name = L"Distance bar",
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

			t.cache =
			{
				hideByDefult = false
			}

			t.windowName = Enemy.UnitFramePart_CreateWindow (part, "EA_DynamicImage_DefaultSeparatorRight")

			Enemy.UnitFramePart_OnUpdate_ProceedWindowInitialization (part)
			Enemy.UnitFramePart_ApplyTexture (data.texture, t.windowName)
		end,

		OnUpdate = function (part, player)

			local t = part._t
			local data = part.data
			local cache = t.cache

			if (cache.distance ~= player.distance)
			then
				cache.distance = player.distance

				local color = data.color
				local level = 1

				for k = 1, 3
				do
					if (cache.distance < data["level"..k]) then break end

					level = k + 1
					color = data["color"..k]
				end

				local textureDx = nil
				local textureDy = nil
				if (not data.textureFullResize)
				then
					local texture = Enemy.UnitFramePart_GetTexture (data.texture)
					textureDx = texture and texture.dx or nil
					textureDy = texture and texture.dy or nil
				end

				-- This cache owns Enemy's writes to its generated distance-bar window.
				-- Direct external window mutation is unsupported, but public bound part
				-- data and texture descriptor changes apply on the next distance update.
				local resizeChanged =
					cache.distanceLevel ~= level
					or cache.distanceSize1 ~= data.size[1]
					or cache.distanceSize2 ~= data.size[2]
					or cache.distanceVertical ~= data.vertical
					or cache.distanceTextureFullResize ~= data.textureFullResize
					or cache.distanceTexture ~= data.texture
					or cache.distanceTextureDx ~= textureDx
					or cache.distanceTextureDy ~= textureDy

				if (resizeChanged)
				then
					cache.distanceLevel = level
					cache.distanceSize1 = data.size[1]
					cache.distanceSize2 = data.size[2]
					cache.distanceVertical = data.vertical
					cache.distanceTextureFullResize = data.textureFullResize
					cache.distanceTexture = data.texture
					cache.distanceTextureDx = textureDx
					cache.distanceTextureDy = textureDy

					Enemy.UnitFramePart_ApplyTexturePercentResize (part, 0.25 * level)
				end

				if (
					cache.distanceColor1 ~= color[1]
					or cache.distanceColor2 ~= color[2]
					or cache.distanceColor3 ~= color[3]
					)
				then
					cache.distanceColor1 = color[1]
					cache.distanceColor2 = color[2]
					cache.distanceColor3 = color[3]
					WindowSetTintColor (t.windowName, color[1], color[2], color[3])
				end
			end

			Enemy.UnitFramePart_OnUpdate_ProceedStateExceptColor (part, player, cache.hideByDefult)
		end
	}
    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.RegisterPartType (g.types["distanceBar"]) end
end


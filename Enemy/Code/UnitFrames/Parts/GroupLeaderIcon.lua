local Enemy = Enemy
local g
local properties =
{
	texture =	{ key = "texture",		order = 1,		name = L"Texture",				type = "select",		default = "star",		values = Enemy.UnitFramePart_GetTexturesSelectValues }
}

function Enemy.UnitFramesGetLeaderIconState (player)
    local frames = Enemy.unitFrames
    local groups = Enemy.groups
    if (frames and frames.leaderIconFlags and groups
        and not frames.settings.unitFramesTestMode
        and groups.players[player.name] == player)
    then
        return frames.leaderIconName == player.name
    end
    return player.isGroupLeader == true
end


function Enemy.UnitFramesParts_GroupLeaderIconInitialize ()
	g = Enemy.unitFramesParts

	g.types["groupLeaderIcon"] =
	{
		key = "groupLeaderIcon",
		name = L"Group leader icon",
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

            local is_group_leader = Enemy.UnitFramesGetLeaderIconState (player)
			if (cache.isGroupLeader ~= is_group_leader)
			then
				cache.isGroupLeader = is_group_leader
				Enemy.UnitFramePart_SetShowing (part, cache.isGroupLeader)
			end

			Enemy.UnitFramePart_OnUpdate_ProceedStateExceptShowing (part, player)
		end
	}
    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.RegisterPartType (g.types["groupLeaderIcon"]) end
end

if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.RegisterHelpers () end

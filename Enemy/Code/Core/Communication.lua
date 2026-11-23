local Enemy = Enemy

function Enemy.CommunicationInitialize ()

	Enemy.chatAdditionalDelay = 0
	Enemy.chatLastTimeSend = -1
	Enemy.chatFilters = {}
	Enemy.chatDelay = 1
	Enemy.chatThrottleDelay = 1


	RegisterEventHandler (SystemData.Events.CHAT_TEXT_ARRIVED, "Enemy.OnChatTextArrived")
	Enemy.TriggerEvent ("CommunicationInitialized")
end

function Enemy.CanSendChatMessage ()
	return (Enemy.time >= Enemy.chatLastTimeSend + Enemy.chatDelay + Enemy.chatAdditionalDelay)
end

function Enemy.SendChatMessage (text)

	SendChatText (text, L"")


	Enemy.chatLastTimeSend = Enemy.time
	Enemy.chatAdditionalDelay = 0
end

function Enemy.ThrottleChat ()
	Enemy.chatAdditionalDelay = Enemy.chatAdditionalDelay + Enemy.chatThrottleDelay
end

function Enemy.UnthrottleChat ()

	Enemy.chatAdditionalDelay = Enemy.chatAdditionalDelay - Enemy.chatThrottleDelay

	if (Enemy.chatAdditionalDelay < 0)
	then
		Enemy.chatAdditionalDelay = 0
	end
end

function Enemy.OnChatTextArrived ()

	local chat_type = GameData.ChatData.type
	local chat_filters = SystemData.ChatLogFilters

	local text = Enemy.toWString (GameData.ChatData.text)
	if (text == nil or text == L"") then return end

	if (chat_type == chat_filters.USER_ERROR)
	then
		if (text:find (L"Slow down!"))
		then
			Enemy.ThrottleChat ()
		end
	elseif (Enemy.chatFilters[chat_type] == true)
	then
		Enemy.UnthrottleChat ()
		Enemy.TriggerEvent ("ChatTextArrived", chat_type, Enemy.FixString (GameData.ChatData.name), text)
	end
end

--------------------------------------------------------------- Helpers
function Enemy.FindCustomChannel (name)

    local channel_name = Enemy.toWString (name:lower ())


	for k, v in pairs (ChatSettings.Channels)
	do
		if (v.labelText ~= nil)
		then
			local str = Enemy.toWString (v.labelText:lower ())

			if (str:find (channel_name))
			then
                return v.serverCmd, k
			end
		end
	end
    return false, false
end


function Enemy.HideChannel (_channelId)
	-- Chat log filter calls are disabled in the current RoR chat path.
end

function Enemy.JoinChannel (name, callback)


    -- Wait for the chat throttle before requesting the channel.


	Enemy.AddTaskAction ("channel",
		function ()

            local channel = Enemy.FindCustomChannel (name)
			if (not channel)
			then
				if (not Enemy.CanSendChatMessage ()) then return false end
				Enemy.SendChatMessage (L"/channeljoin "..name);
			end

			return true
		end
	)

    -- Finish only after the native channel list includes the joined channel.
	Enemy.AddTaskAction ("channel",
		function ()

			local channel, channelId = Enemy.FindCustomChannel (name)
			if (channel)
			then
				callback (name, channel, channelId)
				return true
			end

			return false
		end
	)
end

function Enemy.LeaveChannel (name, callback)

	-- send command to leave the channel
	Enemy.AddTaskAction ("channel",
			function (_data)

			if (not Enemy.CanSendChatMessage ()) then return false end

			Enemy.SendChatMessage (L"/channelleave "..name)
			callback ()

			return true
		end
	)
end

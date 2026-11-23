local Enemy = Enemy
local pairs = pairs
local ipairs = ipairs
local min = math.min
local max = math.max
local floor = math.floor
local next = next
local GameData = GameData

local DISTANT_DISTANCE = 250
local EnemyPlayerEffectDurationThresholdSettings = nil
local EnemyPlayerEffectDurationThresholdIndicators = nil
local EnemyPlayerEffectInitialDurationThresholds = nil
local EnemyPlayerEffectCurrentDurationThresholds = nil
local EnemyPlayerEffectChecksInitialDurationPositive = false
local EnemyPlayerEffectChecksCurrentDurationPositive = false

-- Other-group effect caches need local expiry, but one timer can service every
-- cached player without recreating linked-list timer items for each packet.
local EnemyPlayerEffectsExpiryPlayers = {}
local EnemyPlayerEffectsExpiryDirtyPlayers = {}
local EnemyPlayerEffectsExpiryTimer = nil
local EnemyPlayerEffectsExpiryTimeout = nil
local EnemyPlayerEffectsExpiryDuePlayers = {}
local EnemyPlayerEffectsExpirySweepRunning = false
local EnemyPlayerEffectsExpiryPendingPlayers = nil

local ENEMY_PLAYER_EFFECTS_EXPIRY_TIMER_KEY = "EnemyPlayerEffectsExpiry"

local EnemyPlayerEffectIndexedTypeKeys =
{
	-- Keep this narrow: indexing every boolean effect flag costs more during
	-- heavy effect storms than it saves. These are the broad hot-path defaults.
	"isHealing",
	"isBuff",
	"isBlessing"
}

local CareersWithPet =
{
	[GameData.CareerLine.WHITE_LION] = true,
	[GameData.CareerLine.MAGUS] = true,
	[GameData.CareerLine.ENGINEER] = true,
	[GameData.CareerLine.SQUIG_HERDER] = true
}

--------------------------------------------------------------- EnemyPlayer class
EnemyPlayer = {}
EnemyPlayer.__index = EnemyPlayer

function EnemyPlayer.New (name)
	local obj = {}
	setmetatable (obj, EnemyPlayer)

	-- defaults
	obj.name = name
	obj.career = 0
	obj.level = 0
	obj.hp = 0
	obj.ap = 0
	obj.morale = 0
	obj.isOnline = true
	obj.isDistant = false
	obj.isGroupLeader = false
	obj.worldObjectId = 0
	obj.zoneId = 0
	obj.distance = 0
	obj.rawIsInSameRegion = nil
	obj.isOutOfRegion = false

	obj.isSelected = false
	obj.isLOS = false

	obj.isInPlayerGroup = false
	obj.isSelf = false

	obj.pet = nil

	obj.effects = {}
	obj.effectsByAbilityId = {}
	obj.effectsByType = {}

	return obj
end


local function RemoveIndexedEffect (player, index)
	local oldEffect = player.effects[index]
	local abilityId = oldEffect and oldEffect.abilityId
	local effects = abilityId and player.effectsByAbilityId and player.effectsByAbilityId[abilityId]
	if (effects)
	then
		effects[index] = nil
		if (next (effects) == nil)
		then
			player.effectsByAbilityId[abilityId] = nil
		end
	end

	for _, typeKey in ipairs (EnemyPlayerEffectIndexedTypeKeys)
	do
		if (oldEffect and oldEffect[typeKey])
		then
			effects = player.effectsByType and player.effectsByType[typeKey]
			if (effects)
			then
				effects[index] = nil
				if (next (effects) == nil)
				then
					player.effectsByType[typeKey] = nil
				end
			end
		end
	end
end


local function AddIndexedEffect (player, index, effect)
	local abilityId = effect and effect.abilityId

	if (abilityId)
	then
		player.effectsByAbilityId = player.effectsByAbilityId or {}
		player.effectsByAbilityId[abilityId] = player.effectsByAbilityId[abilityId] or {}
		player.effectsByAbilityId[abilityId][index] = effect
	end

	player.effectsByType = player.effectsByType or {}
	for _, typeKey in ipairs (EnemyPlayerEffectIndexedTypeKeys)
	do
		if (effect[typeKey])
		then
			player.effectsByType[typeKey] = player.effectsByType[typeKey] or {}
			player.effectsByType[typeKey][index] = effect
		end
	end
end

local function ReplaceIndexedEffect (player, index, oldEffect, effect)
    -- Refreshes and stack changes usually keep the same index memberships.
    -- Replace their row references in place instead of destroying singleton
    -- buckets and allocating them again for every partial effect packet.
    local oldAbilityId = oldEffect and oldEffect.abilityId
    local abilityId = effect.abilityId
    if (oldAbilityId and oldAbilityId ~= abilityId)
    then
        local oldBucket = player.effectsByAbilityId[oldAbilityId]
        if (oldBucket)
        then
            oldBucket[index] = nil
            if (next (oldBucket) == nil) then player.effectsByAbilityId[oldAbilityId] = nil end
        end
    end
    if (abilityId)
    then
        local bucket = player.effectsByAbilityId[abilityId]
        if (not bucket)
        then
            bucket = {}
            player.effectsByAbilityId[abilityId] = bucket
        end
        bucket[index] = effect
    end

    for _, typeKey in ipairs (EnemyPlayerEffectIndexedTypeKeys)
    do
        local bucket = player.effectsByType[typeKey]
        if (effect[typeKey])
        then
            if (not bucket)
            then
                bucket = {}
                player.effectsByType[typeKey] = bucket
            end
            bucket[index] = effect
        elseif (oldEffect and oldEffect[typeKey] and bucket)
        then
            bucket[index] = nil
            if (next (bucket) == nil) then player.effectsByType[typeKey] = nil end
        end
    end
end

local function EnemyPlayerEffectAddDurationThreshold (thresholds, thresholdType, value)
	if (value == nil) then return end

	thresholds[#thresholds + 1] =
	{
		type = thresholdType,
		value = value
	}
end


local function EnemyPlayerEffectRefreshDurationThresholds ()
	local effectsIndicators = Enemy.Settings and Enemy.Settings.effectsIndicators
	if (EnemyPlayerEffectDurationThresholdSettings == Enemy.Settings and EnemyPlayerEffectDurationThresholdIndicators == effectsIndicators) then return end

	EnemyPlayerEffectDurationThresholdSettings = Enemy.Settings
	EnemyPlayerEffectDurationThresholdIndicators = effectsIndicators
	EnemyPlayerEffectInitialDurationThresholds = {}
	EnemyPlayerEffectCurrentDurationThresholds = {}
	EnemyPlayerEffectChecksInitialDurationPositive = false
	EnemyPlayerEffectChecksCurrentDurationPositive = false

	for _, indicator in pairs (effectsIndicators or {})
	do
		for _, filter in pairs (indicator.effectFilters or {})
		do
			if (filter.durationType == 2)
			then
				EnemyPlayerEffectChecksInitialDurationPositive = true
				EnemyPlayerEffectAddDurationThreshold (EnemyPlayerEffectInitialDurationThresholds, "min", filter.durationMin)
				EnemyPlayerEffectAddDurationThreshold (EnemyPlayerEffectInitialDurationThresholds, "max", filter.durationMax)

			elseif (filter.durationType == 4)
			then
				EnemyPlayerEffectChecksCurrentDurationPositive = true
				EnemyPlayerEffectAddDurationThreshold (EnemyPlayerEffectCurrentDurationThresholds, "min", filter.durationMin)
				EnemyPlayerEffectAddDurationThreshold (EnemyPlayerEffectCurrentDurationThresholds, "max", filter.durationMax)
			end
		end
	end
end


local function EnemyPlayerEffectCrossedDurationThreshold (oldValue, newValue, thresholds, checksPositive)
	oldValue = oldValue or 0
	newValue = newValue or 0

	if (checksPositive and ((oldValue > 0) ~= (newValue > 0))) then return true end

	for _, threshold in ipairs (thresholds or {})
	do
		if (threshold.type == "min")
		then
			if ((oldValue < threshold.value) ~= (newValue < threshold.value)) then return true end
		else
			if ((oldValue > threshold.value) ~= (newValue > threshold.value)) then return true end
		end
	end

	return false
end


local function EnemyPlayerEffectPrepareText (effect, oldEffect)
	if (effect._enemy) then return end

	-- EnemyEffectFilter's GetEffectName/GetEffectText normalize lazily.
	if (oldEffect and oldEffect.name == effect.name and oldEffect._enemyName)
	then
		effect._enemyName = oldEffect._enemyName
	end

	if (oldEffect and oldEffect.effectText == effect.effectText and oldEffect._enemyEffectText)
	then
		effect._enemyEffectText = oldEffect._enemyEffectText
	end

	effect._enemy = true
end


local function EnemyPlayerEffectPrepareTiming (effect, oldEffect)
	local oldDuration = nil
	if (
			oldEffect
			and oldEffect.abilityId == effect.abilityId
			and oldEffect.name == effect.name
			and oldEffect.effectText == effect.effectText
		)
	then
		oldDuration = oldEffect._enemyDuration
	end

	if (effect._enemyDuration)
	then
		if (not effect._enemyTimeout) then effect._enemyTimeout = Enemy.time + effect._enemyDuration end
		return
	end

	-- Preserve the first-seen duration for durationType=initial filters, but
	-- treat same-effect duration increases as refreshes so timer icons extend.
	if (oldDuration and oldEffect and effect.duration <= (oldEffect.duration or effect.duration))
	then
		effect._enemyDuration = oldDuration
		effect._enemyTimeout = oldEffect._enemyTimeout
	else
		effect._enemyDuration = max (0, effect.duration)
		effect._enemyTimeout = Enemy.time + effect._enemyDuration
		effect._enemyDurationRefreshed = oldDuration ~= nil
	end
end


local function EnemyPlayerEffectMaterialChanged (oldEffect, effect)
	-- Partial effect updates often repeat the same visible row many times per
	-- second. Only wake unit-frame indicator scans when a filter-relevant value
	-- changed or a configured duration threshold was crossed.
	if (not oldEffect) then return true end

	if (
			oldEffect.abilityId ~= effect.abilityId
			or oldEffect.iconNum ~= effect.iconNum
			or oldEffect.name ~= effect.name
			or oldEffect.effectText ~= effect.effectText
			or oldEffect.isBuff ~= effect.isBuff
			or oldEffect.isBlessing ~= effect.isBlessing
			or oldEffect.isHealing ~= effect.isHealing
			or oldEffect.isDefensive ~= effect.isDefensive
			or oldEffect.isDebuff ~= effect.isDebuff
			or oldEffect.isOffensive ~= effect.isOffensive
			or oldEffect.isDamaging ~= effect.isDamaging
			or oldEffect.isAilment ~= effect.isAilment
			or oldEffect.isHex ~= effect.isHex
			or oldEffect.isCurse ~= effect.isCurse
			or oldEffect.isStatsBuff ~= effect.isStatsBuff
			or oldEffect.isGranted ~= effect.isGranted
			or oldEffect.isPassive ~= effect.isPassive
			or oldEffect.permanentUntilDispelled ~= effect.permanentUntilDispelled
			or oldEffect.castByPlayer ~= effect.castByPlayer
			or oldEffect.stackCount ~= effect.stackCount
		)
	then
		return true
	end

	EnemyPlayerEffectRefreshDurationThresholds ()
	if (effect._enemyDurationRefreshed) then return true end

	return EnemyPlayerEffectCrossedDurationThreshold (oldEffect._enemyDuration, effect._enemyDuration, EnemyPlayerEffectInitialDurationThresholds, EnemyPlayerEffectChecksInitialDurationPositive)
		or EnemyPlayerEffectCrossedDurationThreshold (oldEffect.duration, effect.duration, EnemyPlayerEffectCurrentDurationThresholds, EnemyPlayerEffectChecksCurrentDurationPositive)
end


local function EnemyPlayerEffectUpdateStoredTiming (oldEffect, effect)
	oldEffect.duration = effect.duration
	oldEffect._enemyDuration = effect._enemyDuration
	oldEffect._enemyTimeout = effect._enemyTimeout
end


local function EnemyPlayerEffectsExpiryGetNextTimeout (player)
	local nextTimeout = nil
	local effects = player.effects
	if (not effects) then return nil end

	for _, effect in pairs (effects)
	do
		if (effect._enemyTimeout and (nextTimeout == nil or effect._enemyTimeout < nextTimeout))
		then
			nextTimeout = effect._enemyTimeout
		end
	end

	return nextTimeout
end


local function EnemyPlayerEffectsExpiryGetGlobalTimeout ()
	local nextTimeout = nil

	for _, timeout in pairs (EnemyPlayerEffectsExpiryPlayers)
	do
		if (timeout and (nextTimeout == nil or timeout < nextTimeout))
		then
			nextTimeout = timeout
		end
	end

	return nextTimeout
end


local function EnemyPlayerEffectsExpiryIsEligible (player, canonicalPlayers)
	local currentPlayer = Enemy.groups and Enemy.groups.player or nil

	return currentPlayer ~= nil
		and currentPlayer.name ~= nil
		and canonicalPlayers ~= nil
		and canonicalPlayers[currentPlayer.name] == currentPlayer
		and player ~= nil
		and player.name ~= nil
		and canonicalPlayers[player.name] == player
		and player:IsInGroup ()
		and not player.isInPlayerGroup
		and not player.isSelf
		and not (Enemy.groups and Enemy.groups.player == player)
end


local function EnemyPlayerEffectsExpiryUnregister (player)
	EnemyPlayerEffectsExpiryPlayers[player] = nil
	EnemyPlayerEffectsExpiryDirtyPlayers[player] = nil
	player._enemyEffectsExpiryTimeout = nil
end


local function EnemyPlayerEffectsExpiryScan (player)
	local timeout = EnemyPlayerEffectsExpiryGetNextTimeout (player)
	-- False marks an eligible, already-scanned player with no active deadline.
	EnemyPlayerEffectsExpiryPlayers[player] = timeout or false
	EnemyPlayerEffectsExpiryDirtyPlayers[player] = nil
	player._enemyEffectsExpiryTimeout = timeout
end


local function EnemyPlayerEffectsExpiryReconcile (canonicalPlayers)
	for player, _ in pairs (EnemyPlayerEffectsExpiryPlayers)
	do
		if (not EnemyPlayerEffectsExpiryIsEligible (player, canonicalPlayers))
		then
			EnemyPlayerEffectsExpiryUnregister (player)
		end
	end

	for player, _ in pairs (EnemyPlayerEffectsExpiryDirtyPlayers)
	do
		if (not EnemyPlayerEffectsExpiryIsEligible (player, canonicalPlayers))
		then
			EnemyPlayerEffectsExpiryUnregister (player)
		end
	end

	if (canonicalPlayers)
	then
		for _, player in pairs (canonicalPlayers)
		do
			if (EnemyPlayerEffectsExpiryIsEligible (player, canonicalPlayers))
			then
				if (EnemyPlayerEffectsExpiryPlayers[player] == nil or EnemyPlayerEffectsExpiryDirtyPlayers[player])
				then
					EnemyPlayerEffectsExpiryScan (player)
				end
			else
				EnemyPlayerEffectsExpiryUnregister (player)
			end
		end
	end

	return EnemyPlayerEffectsExpiryGetGlobalTimeout ()
end


local function EnemyPlayerEffectsExpirySetTimer (timeout)
	if (EnemyPlayerEffectsExpirySweepRunning) then return end
	if (EnemyPlayerEffectsExpiryTimeout == timeout and EnemyPlayerEffectsExpiryTimer) then return end

	EnemyPlayerEffectsExpiryTimeout = timeout

	if (timeout == nil)
	then
		if (EnemyPlayerEffectsExpiryTimer)
		then
			EnemyPlayerEffectsExpiryTimer:Remove ()
			EnemyPlayerEffectsExpiryTimer = nil
		end
		return
	end

	local duration = timeout - Enemy.time
	if (EnemyPlayerEffectsExpiryTimer)
	then
		EnemyPlayerEffectsExpiryTimer.duration = duration
		EnemyPlayerEffectsExpiryTimer:Reset ()
		return
	end

	EnemyPlayerEffectsExpiryTimer = EnemyTimer.New (ENEMY_PLAYER_EFFECTS_EXPIRY_TIMER_KEY, duration, function (timer)
		EnemyPlayerEffectsExpirySweepRunning = true
		local dueCount = 0

		for player, playerTimeout in pairs (EnemyPlayerEffectsExpiryPlayers)
		do
			if (playerTimeout and Enemy.time >= playerTimeout)
			then
				dueCount = dueCount + 1
				EnemyPlayerEffectsExpiryDuePlayers[dueCount] = player
			end
		end

		for dueIndex = 1, dueCount
		do
			local player = EnemyPlayerEffectsExpiryDuePlayers[dueIndex]
			EnemyPlayerEffectsExpiryDuePlayers[dueIndex] = nil

			-- Group rebuilds can replace an EnemyPlayer while its old deadline is
			-- still queued. Never mutate or publish from a stale object.
			local canonicalPlayers = EnemyPlayerEffectsExpiryPendingPlayers or (Enemy.groups and Enemy.groups.players)
			if (not EnemyPlayerEffectsExpiryIsEligible (player, canonicalPlayers))
			then
				EnemyPlayerEffectsExpiryUnregister (player)
			else
				local expiredEffectsChanged = false
				for index, effect in pairs (player.effects)
				do
					if (effect._enemyTimeout and Enemy.time >= effect._enemyTimeout)
					then
						RemoveIndexedEffect (player, index)
						player.effects[index] = nil
						expiredEffectsChanged = true
					end
				end
				EnemyPlayerEffectsExpiryDirtyPlayers[player] = true

				if (expiredEffectsChanged)
				then
					Enemy.TriggerEvent ("GroupsPlayerEffectsUpdated", player)
				end
			end
		end

		local canonicalPlayers = EnemyPlayerEffectsExpiryPendingPlayers or (Enemy.groups and Enemy.groups.players)
		EnemyPlayerEffectsExpiryPendingPlayers = nil

		-- Event handlers above may synchronously cleanse, refresh, add effects, or
		-- rebuild groups. Reconcile once from their final canonical state.
		local nextTimeout = EnemyPlayerEffectsExpiryReconcile (canonicalPlayers)
		EnemyPlayerEffectsExpiryTimeout = nextTimeout
		EnemyPlayerEffectsExpirySweepRunning = false

		if (nextTimeout == nil)
		then
			EnemyPlayerEffectsExpiryTimer = nil
			return true
		end

		timer.duration = nextTimeout - Enemy.time
		return false
	end)
end


local function EnemyPlayerEffectsExpiryRefresh (player)
	EnemyPlayerEffectsExpiryDirtyPlayers[player] = true
	if (EnemyPlayerEffectsExpirySweepRunning) then return end

	local oldRegistration = EnemyPlayerEffectsExpiryPlayers[player]
	local oldTimeout = oldRegistration or nil
	local canonicalPlayers = Enemy.groups and Enemy.groups.players or nil
	if (EnemyPlayerEffectsExpiryIsEligible (player, canonicalPlayers))
	then
		EnemyPlayerEffectsExpiryScan (player)
	else
		EnemyPlayerEffectsExpiryUnregister (player)
	end

	local newRegistration = EnemyPlayerEffectsExpiryPlayers[player]
	local newTimeout = newRegistration or nil
	if (oldTimeout == newTimeout) then return end

	if (
			EnemyPlayerEffectsExpiryTimeout == nil
			or (newTimeout and newTimeout < EnemyPlayerEffectsExpiryTimeout)
		)
	then
		EnemyPlayerEffectsExpirySetTimer (newTimeout)
	elseif (oldTimeout == EnemyPlayerEffectsExpiryTimeout)
	then
		EnemyPlayerEffectsExpirySetTimer (EnemyPlayerEffectsExpiryGetGlobalTimeout ())
	end
end


function Enemy.ReconcilePlayerEffectsExpiry (canonicalPlayers)
	if (EnemyPlayerEffectsExpirySweepRunning)
	then
		EnemyPlayerEffectsExpiryPendingPlayers = canonicalPlayers
		return
	end

	EnemyPlayerEffectsExpirySetTimer (EnemyPlayerEffectsExpiryReconcile (canonicalPlayers))
end


function EnemyPlayer:IsMainAssist ()

	local main_assist_member = PartyUtils.GetWarbandMainAssist ()
    local main_assist_name = nil

    if (main_assist_member)
    then
			main_assist_name = Enemy.FixString (main_assist_member.name)
    end

	return self.name == main_assist_name
end


function EnemyPlayer:IsValid ()
	return self.name ~= nil and self.name ~= L"" and self.career ~= 0
end


function EnemyPlayer:IsInGroup ()
	return self.group ~= nil
end


function EnemyPlayer:IsSelected ()
	return self.isSelected == true
end


function EnemyPlayer:IsLOS ()
	return self.isLOS == true
end

function EnemyPlayer:SetLOS (value, silent)

	if (self.isLOS == value or self.isSelf) then return end

	self.isLOS = value

	if (not silent) then Enemy.TriggerEvent ("GroupsPlayerUpdated", self) end
end

function EnemyPlayer:SetSelected (value)

	self.isSelected = value

	if (not self.isSelected and not self.isDistant)
	then
		self:SetLOS (false)
	end
end


function EnemyPlayer:SetDistant (value)

	if (self.isDistant == value or self.isSelf) then return end

	self.isDistant = value

	if (not self.isSelected and not self.isDistant)
	then
		self:SetLOS (false, true)
	end

	Enemy.TriggerEvent ("GroupsPlayerUpdated", self)
end


local function EnemyPlayerNotifyDistanceChanged (player, deferEvent)

	if (deferEvent)
	then
		player._enemyDistanceEventPending = true
	else
		Enemy.TriggerEvent ("GroupsPlayerDistanceUpdated", player)
	end
end


function EnemyPlayer:FlushDistanceEvent ()

	if (not self._enemyDistanceEventPending) then return false end

	self._enemyDistanceEventPending = nil
	Enemy.TriggerEvent ("GroupsPlayerDistanceUpdated", self)
	return true
end


function EnemyPlayer:SetDistance (value)

	if (self.isSelf) then return false end

	local distance = floor (0.5 + value)
	local isDistant = value >= DISTANT_DISTANCE
	local distanceChanged = self.distance ~= distance
	local distantChanged = self.isDistant ~= isDistant

	if (not distanceChanged and not distantChanged) then return false end

	self.distance = distance
	self._enemyMapSearchSweep = nil

	-- Preserve the public distance event even on a distant-state crossing.
	-- Guard and external listeners consume that event independently of the full
	-- player-state update fired by SetDistant.
	if (distanceChanged)
	then
		EnemyPlayerNotifyDistanceChanged (self, false)
	end

	if (distantChanged)
	then
		self:SetDistant (isDistant)
	end

	return true
end


function EnemyPlayer:SetDistanceUnavailable (silent, deferDistanceEvent)

	if (self.isSelf) then return false end

	local distanceChanged = self.distance ~= DISTANT_DISTANCE
	local distantChanged = not self.isDistant
	local changed = distanceChanged or distantChanged

	self.distance = DISTANT_DISTANCE
	self._enemyMapPointIndex = nil
	self._enemyMapPointRawName = nil
	self._enemyMapSearchSweep = nil

	if (distanceChanged)
	then
		EnemyPlayerNotifyDistanceChanged (self, deferDistanceEvent)
	end

	if (distantChanged)
	then
		if (silent)
		then
			self.isDistant = true
		else
			self:SetDistant (true)
		end
	end

	return changed
end


function EnemyPlayer:SetObjectWorldId (id)

	local old_id = self.worldObjectId
	self.worldObjectId = id

	if (old_id ~= id)
	then
		Enemy.TriggerEvent ("GroupsPlayerWorldObjectIdUpdated", self)
	end
end


function EnemyPlayer:SetOutOfRegion (value, deferDistanceEvent)

	value = value == true
	local wasOutOfRegion = self.isOutOfRegion
	local changed = self.isOutOfRegion ~= value
	self.isOutOfRegion = value

	if (value)
	then
		if (self:SetDistanceUnavailable (true, deferDistanceEvent)) then changed = true end

	elseif (wasOutOfRegion)
	then
		-- A region pin owns the synthetic distant state. Clear it when the
		-- member returns, then let the next cached map scan establish the real
		-- distance without leaving the member stuck as distant.
		self._enemyMapPointIndex = nil
		self._enemyMapPointRawName = nil
		self._enemyMapSearchSweep = nil

		if (not self.isSelf and (self.isDistant or self.distance ~= 0))
		then
			local distanceChanged = self.distance ~= 0
			self.isDistant = false
			self.distance = 0
			if (distanceChanged)
			then
				EnemyPlayerNotifyDistanceChanged (self, deferDistanceEvent)
			end
			if (not self.isSelected) then self:SetLOS (false, true) end
			changed = true
		end

		if (Enemy._GroupsKickDistanceScan)
		then
			Enemy._GroupsKickDistanceScan ()
		end
	end

	return changed
end


function EnemyPlayer:RefreshOutOfRegion (deferDistanceEvent)

	local playerZoneId = GameData.Player.zone or 0
	local zoneId = self.zoneId or 0
	local zonesKnown = playerZoneId > 0 and zoneId > 0
	local outOfRegion

	if (zonesKnown)
	then
		-- Adjacent RvR areas can have different zone ids while sharing map
		-- space. Require the server region flag or a completed missing-pip scan
		-- as confirmation, and keep that pin until the member returns.
		local zoneMismatch = zoneId ~= playerZoneId
		outOfRegion = zoneMismatch and (
			self.rawIsInSameRegion == false
			or (self.isOutOfRegion and self.rawIsInSameRegion == nil)
		)
	else
		outOfRegion = self.rawIsInSameRegion == false
	end

	return self:SetOutOfRegion (outOfRegion, deferDistanceEvent)
end


function EnemyPlayer:LoadFromScenarioData (data, deferDistanceEvent)

	local changed = false
	local career = Enemy.ScenarioCareerIdToLine[data.careerId]
	local ap = min (data.ap, 100)

	if (self.career ~= career) then self.career = career; changed = true end
	if (self.level ~= data.rank) then self.level = data.rank; changed = true end
	if (self.hp ~= data.health) then self.hp = data.health; changed = true end
	if (self.ap ~= ap) then self.ap = ap; changed = true end

	if (data.moraleLevel ~= nil and self.morale ~= data.moraleLevel)
	then
		self.morale = data.moraleLevel
		changed = true
	end

	local zoneId = GameData.Player.zone or 0
	if (self.zoneId ~= zoneId) then self.zoneId = zoneId; changed = true end
	self.rawIsInSameRegion = true
	if (self.isGroupLeader ~= false) then self.isGroupLeader = false; changed = true end
	if (self.isOnline ~= true) then self.isOnline = true; changed = true end
	if (self:SetOutOfRegion (false, deferDistanceEvent)) then changed = true end

	return changed
end


function EnemyPlayer:LoadFromWarbandData (data, deferDistanceEvent)
	return self:LoadFromGroupData (data, deferDistanceEvent)
end


function EnemyPlayer:LoadFromGroupData (data, deferDistanceEvent, keepGroupLeader)

	local changed = false
	local ap = min (data.actionPointPercent, 100)

	if (self.career ~= data.careerLine) then self.career = data.careerLine; changed = true end
	if (self.level ~= data.level) then self.level = data.level; changed = true end
	if (self.hp ~= data.healthPercent) then self.hp = data.healthPercent; changed = true end
	if (self.ap ~= ap) then self.ap = ap; changed = true end

	-- Some group/warband member packets can omit moraleLevel; preserve the last
	-- known value so morale number/bar parts do not blank or error on partial updates.
	if (data.moraleLevel ~= nil and self.morale ~= data.moraleLevel)
	then
		self.morale = data.moraleLevel
		changed = true
	end

	local zoneId = data.zoneNum or 0
	if (self.zoneId ~= zoneId) then self.zoneId = zoneId; changed = true end
	self.rawIsInSameRegion = data.isInSameRegion
	if (self:RefreshOutOfRegion (deferDistanceEvent)) then changed = true end
	-- World-object consumers have their own narrow event; do not turn an id-only
	-- packet into a full unit-frame/player redraw as well.
	self:SetObjectWorldId (data.worldObjNum or 0)

	if (self.isOnline ~= data.online) then self.isOnline = data.online; changed = true end
    local isGroupLeader = data.isGroupLeader
    if (self.isSelf) then isGroupLeader = GameData.Player.isGroupLeader end
    if (not keepGroupLeader and self.isGroupLeader ~= isGroupLeader)
    then
        self.isGroupLeader = isGroupLeader
        changed = true
    end

	if (CareersWithPet[self.career] and data.Pet and data.Pet.healthPercent)
	then
		local petHp = data.Pet.healthPercent
		if (not self.pet or self.pet.career ~= self.career or self.pet.hp ~= petHp)
		then
			self.pet =
			{
				owner = self,
				career = self.career,
				hp = petHp
			}
			changed = true
		end
	else
		if (self.pet)
		then
			self.pet = nil
			changed = true
		end
	end

	return changed
end


function EnemyPlayer:LoadFromCurrentPlayer (deferDistanceEvent)

	local changed = false
	local career = GameData.Player.career.line
	local hp = floor (100.0 * GameData.Player.hitPoints.current / GameData.Player.hitPoints.maximum)
	local ap = min (floor (100.0 * GameData.Player.actionPoints.current / GameData.Player.actionPoints.maximum), 100)
	local morale = GetPlayerMoraleLevel ()
	local zoneId = GameData.Player.zone or 0
	local worldObjectId = GameData.Player.worldObjNum or 0
	local isRVRFlagged = GameData.Player.rvrZoneFlagged or GameData.Player.rvrPermaFlagged

	if (self.career ~= career) then self.career = career; changed = true end
	if (self.level ~= GameData.Player.level) then self.level = GameData.Player.level; changed = true end
	if (self.hp ~= hp) then self.hp = hp; changed = true end
	if (self.ap ~= ap) then self.ap = ap; changed = true end
	if (self.morale ~= morale) then self.morale = morale; changed = true end
	if (self.zoneId ~= zoneId) then self.zoneId = zoneId; changed = true end
	self:SetObjectWorldId (worldObjectId)
	if (self.isOnline ~= true) then self.isOnline = true; changed = true end
	if (self.isGroupLeader ~= GameData.Player.isGroupLeader) then self.isGroupLeader = GameData.Player.isGroupLeader; changed = true end

	self.rawIsInSameRegion = true
	if (self:SetOutOfRegion (false, deferDistanceEvent)) then changed = true end
	self:SetDistant (false)

	if (self.isRVRFlagged ~= isRVRFlagged) then self.isRVRFlagged = isRVRFlagged; changed = true end
	if (self.isInCombat ~= GameData.Player.inCombat) then self.isInCombat = GameData.Player.inCombat; changed = true end

	if (self:LoadPetFromCurrentPlayer ()) then changed = true end

	return changed
end


function EnemyPlayer:LoadPetFromCurrentPlayer ()

	if (CareersWithPet[self.career] and GameData.Player.Pet and GameData.Player.Pet.healthPercent)
	then
		local pet = GameData.Player.Pet
		local name = Enemy.FixString (pet.name)
		local changed =
			not self.pet
			or self.pet.name ~= name
			or self.pet.career ~= self.career
			or self.pet.level ~= pet.level
			or self.pet.hp ~= pet.healthPercent
			or self.pet.worldObjectId ~= pet.objNum

		if (not changed) then return false end

		self.pet =
		{
			owner = self,
			name = name,
			career = self.career,
			level = pet.level,
			hp = pet.healthPercent,
			worldObjectId = pet.objNum
		}

		return true
	else
		if (self.pet)
		then
			self.pet = nil
			return true
		end
	end

	return false
end


function EnemyPlayer:LoadFromTarget (targetClassification, _targetId)

	self.name = Enemy.FixString (TargetInfo:UnitName (targetClassification))
	self.career = TargetInfo:UnitCareer (targetClassification)
	self.level = TargetInfo:UnitLevel (targetClassification)
	self.hp = TargetInfo:UnitHealth (targetClassification)

	self.zoneId = GameData.Player.zone or 0
	self:SetObjectWorldId (TargetInfo:UnitEntityId (targetClassification) or 0)

	self.isOnline = true
end


function EnemyPlayer:LoadEffects (data, isFullList)

	local loadEffectsChanged = isFullList == true
	local oldEffects = self.effects

	if (isFullList)
	then
		self.effects = {}
		self.effectsByAbilityId = {}
		self.effectsByType = {}
	end

	self.effectsByAbilityId = self.effectsByAbilityId or {}
	self.effectsByType = self.effectsByType or {}

	for index, effect in pairs (data)
	do
		local oldEffect = oldEffects and oldEffects[index]

		if (effect.effectIndex == nil or effect.iconNum == nil or effect.iconNum < 1)
		then
			if (oldEffect)
			then
				loadEffectsChanged = true
				if (not isFullList) then RemoveIndexedEffect (self, index) end
				self.effects[index] = nil
			end
		else
			EnemyPlayerEffectPrepareText (effect, oldEffect)
			EnemyPlayerEffectPrepareTiming (effect, oldEffect)

			if (not isFullList and oldEffect and not EnemyPlayerEffectMaterialChanged (oldEffect, effect))
			then
				EnemyPlayerEffectUpdateStoredTiming (oldEffect, effect)
			else
				loadEffectsChanged = true
				if (isFullList)
				then
					AddIndexedEffect (self, index, effect)
				else
					ReplaceIndexedEffect (self, index, oldEffect, effect)
				end
				self.effects[index] = effect
			end
		end
	end

	EnemyPlayerEffectsExpiryRefresh (self)


    -- Guard cleanup needs the actual packet even when visible values did not
    -- change. The optional observer is installed only for the local tank.
    if (Enemy.MyGuardCleanupOnEffectsLoaded)
    then
        Enemy.MyGuardCleanupOnEffectsLoaded (self, data, isFullList)
    end

	return loadEffectsChanged
end


function EnemyPlayer.GetExample ()

	local obj = EnemyPlayer.New (Enemy.groups.player.name)

	for k, v in pairs (Enemy.groups.player)
	do
		obj[k] = v
	end

	obj.distance = 123
	obj.isGroupLeader = true
	obj.morale = 4
	obj.isSelected = true

	return obj
end


function EnemyPlayer.GetRandomExample (group_index, index)

	local prefix = ""
	if group_index then prefix = prefix.."G:"..group_index end
	if index then prefix = prefix.."P:"..index end

	local obj = EnemyPlayer.New (towstring (Enemy.capitalize (prefix..(Enemy.GetRandomString2 (math.random (4, 15)))  )  ))

	obj.career = math.random (24)
	obj.level = math.random (40)
	obj.hp = math.random (0, 100)
	obj.ap = math.random (0, 100)
	obj.morale = math.random (0, 4)
	obj.distance = math.random (DISTANT_DISTANCE + 50)

	obj.isOnline = math.random (0, 10) ~= 5
	obj.isDistant = obj.distance >= DISTANT_DISTANCE
	obj.isGroupLeader = math.random (0, 1) == 0
	obj.isInPlayerGroup = math.random (0, 1) == 0
	obj.isSelected = math.random (0, 3) == 2
	obj.isLOS = math.random (0, 10) == 5
	obj.isSelf = obj.isInPlayerGroup and (math.random (0, 1) == 0)

	return obj
end

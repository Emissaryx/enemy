local Enemy = Enemy
local tinsert = table.insert
local tsort = table.sort
local ipairs = ipairs
local pairs = pairs
local type = type
local mceil = math.ceil
local InterfaceCore = InterfaceCore
local EmptyEffects = {}

local EffectsIndicatorCandidateTypes =
{
	isHealing = true,
	isBuff = true,
	isBlessing = true
}

local Icons =
{
	effect =
	{
		key = "effect",
		name = L"effect",
		texture = "enemy_unitframe_effect",
		x = 0, y = 0,
		width = 6, height = 9
	},

	effect2 =
	{
		key = "effect2",
		name = L"effect2",
		texture = "enemy_unitframe_effect2",
		x = 0, y = 0,
		width = 32, height = 32
	},

	guard =
	{
		key = "guard",
		name = L"guard",
		texture = "enemy_unitframe_guard",
		x = 0, y = 0,
		width = 16, height = 16
	},

	question =
	{
		key = "question",
		name = L"question",
		texture = "enemy_unitframe_question",
		x = 0, y = 0,
		width = 32, height = 32
	},

	stagger =
	{
		key = "stagger",
		name = L"stagger",
		texture = "enemy_unitframe_stagger",
		x = 0, y = 0,
		width = 32, height = 32
	},

	heal  =
	{
		key = "heal",
		name = L"heal debuff",
		texture = "enemy_unitframe_healdebuff",
		x = 0, y = 0,
		width = 32, height = 32
	},

	disabled =
	{
		key = "disabled",
		name = L"disabled",
		texture = "enemy_unitframe_disabled",
		x = 0, y = 0,
		width = 32, height = 32
	},

	dot =
	{
		key = "dot",
		name = L"dot",
		texture = "enemy_1dot",
		x = 0, y = 0,
		width = 10, height = 10
	}
}

Enemy.EffectsIndicatorIcons = Icons		-- for other addons

local EffectsIndicatorSweepInterval = 0.3
local EffectsIndicatorTimed = {}
local EffectsIndicatorTimedCount = 0
local EffectsIndicatorSweepTimer = nil
local EffectsIndicatorSweepRunning = false
local EffectsIndicatorExpired = {}
local EffectsIndicatorExpiredPlayers = {}


local function EffectsIndicatorSetShowing (indicator, show)
	if (not indicator.windowName) then return end

	show = show == true
	if (indicator._isShowing == show) then return end

	indicator._isShowing = show
	WindowSetShowing (indicator.windowName, show)

    -- Showing one sibling can raise it above later, already-visible entries.
    -- Restore order only on this transition, including direct preview/timer calls.
    local frame = indicator._frame
    if (show and frame and frame._RefreshEffectsIndicatorLayers)
    then
        frame:_RefreshEffectsIndicatorLayers (indicator)
    end
end


local function EffectsIndicatorSetTimerLabel (indicator, value)
	if (not indicator.windowName or indicator._lastTimerValue == value) then return end

	local text = L""
	if (value ~= nil and value > 0) then text = text..value end

	LabelSetText (indicator.windowName.."TLabel", text)
	indicator._lastTimerValue = value
end


local function EffectsIndicatorRenderTimer (indicator)
	local exactLeft = indicator.ticked - Enemy.time

	local value = nil
	if (indicator._timerLabelAllowed and exactLeft > 0)
	then
		value = mceil (exactLeft)
	end

	EffectsIndicatorSetTimerLabel (indicator, value)
	return exactLeft
end


local function EffectsIndicatorStopTimer (indicator)
	if (EffectsIndicatorTimed[indicator])
	then
		EffectsIndicatorTimed[indicator] = nil
		EffectsIndicatorTimedCount = EffectsIndicatorTimedCount - 1
	end

	indicator.ticked = 0
	indicator._timedPlayer = nil
	EffectsIndicatorSetTimerLabel (indicator, nil)

	if (
		EffectsIndicatorTimedCount == 0
		and EffectsIndicatorSweepTimer
		and not EffectsIndicatorSweepRunning
		)
	then
		local timer = EffectsIndicatorSweepTimer
		EffectsIndicatorSweepTimer = nil
		timer:Remove ()
	end
end


local function EffectsIndicatorSweep ()
	EffectsIndicatorSweepRunning = true

	local expiredCount = 0
	for indicator, _ in pairs (EffectsIndicatorTimed)
	do
		if (not indicator.windowName)
		then
			EffectsIndicatorStopTimer (indicator)
		elseif (EffectsIndicatorRenderTimer (indicator) <= 0)
		then
			expiredCount = expiredCount + 1
			EffectsIndicatorExpired[expiredCount] = indicator
			EffectsIndicatorExpiredPlayers[expiredCount] = indicator._timedPlayer
			EffectsIndicatorStopTimer (indicator)
		end
	end

	-- Recheck only when a tracked timeout actually expires. This preserves the
	-- first-match fast paths while allowing another matching effect to take over.
	for index = 1, expiredCount
	do
		local indicator = EffectsIndicatorExpired[index]
		local player = EffectsIndicatorExpiredPlayers[index]

		EffectsIndicatorExpired[index] = nil
		EffectsIndicatorExpiredPlayers[index] = nil

		if (indicator.windowName and player)
		then
			indicator:EffectsUpdated (player, false)
		else
			EffectsIndicatorSetShowing (indicator, false)
		end
	end

	EffectsIndicatorSweepRunning = false

	if (EffectsIndicatorTimedCount == 0)
	then
		EffectsIndicatorSweepTimer = nil
		return true
	end

	return false
end


local function EffectsIndicatorStartTimer (indicator, player, timeout)
	indicator.ticked = timeout
	indicator._timedPlayer = player
	EffectsIndicatorRenderTimer (indicator)

	if (not EffectsIndicatorTimed[indicator])
	then
		EffectsIndicatorTimed[indicator] = true
		EffectsIndicatorTimedCount = EffectsIndicatorTimedCount + 1
	end

	if (not EffectsIndicatorSweepTimer)
	then
		EffectsIndicatorSweepTimer = EnemyTimer.New ("EnemyEffectsIndicatorSweep", EffectsIndicatorSweepInterval, EffectsIndicatorSweep)
	end
end


local function EffectsIndicatorGetMatchTimeout (indicator, effect)
	if (not effect) then return false, nil end
	-- Repent's reduced-damage component remains until broken, beyond its initial
	-- timed detaunt. Keep its icon event-driven instead of expiring it by duration.
	if (effect.abilityId == 8245 or effect.permanentUntilDispelled == true) then return true, nil end

	local duration = effect.duration
	if (type (duration) ~= "number" or duration <= 0)
	then
		-- Permanent or malformed-duration effects retain the old icon-only
		-- behavior, but they do not keep the shared duration sweep alive.
		return true, nil
	end

	local timeout = effect._enemyTimeout
	if (type (timeout) ~= "number")
	then
		timeout = Enemy.time + duration
		-- Example data and third-party callers may bypass EnemyPlayer's timing
		-- preparation. Pin their fallback once so repeated updates cannot turn a
		-- countdown into a sliding duration.
		effect._enemyTimeout = timeout
	end

	if (timeout <= Enemy.time) then return false, nil end
	return true, timeout
end


local function EffectsIndicatorGetPositiveCandidateType (effectFilter)
	if (
			effectFilter
			and not effectFilter.abilityIdsHash
			and effectFilter.typeMatch == 1
			and EffectsIndicatorCandidateTypes[effectFilter.type]
		)
	then
		return effectFilter.type
	end

	return nil
end


local function EffectsIndicatorGetSimpleCandidateType (effectFilters)
	local candidateType = nil

	for _, effectFilter in ipairs (effectFilters or {})
	do
		local filterType = EffectsIndicatorGetPositiveCandidateType (effectFilter)
		if (filterType == nil) then return nil end
		if (candidateType ~= nil and candidateType ~= filterType) then return nil end
		candidateType = filterType
	end

	return candidateType
end


local function EffectsIndicatorExpressionContainsOr (expression)
	for _, value in ipairs (expression or {})
	do
		if (value == "or") then return true end
		if (type (value) == "table" and EffectsIndicatorExpressionContainsOr (value)) then return true end
	end

	return false
end


local function EffectsIndicatorExpressionContainsNot (expression)
	for _, value in ipairs (expression or {})
	do
		if (value == "not") then return true end
		if (type (value) == "table" and EffectsIndicatorExpressionContainsNot (value)) then return true end
	end

	return false
end


local function EffectsIndicatorGetAbilityCandidateIds (effectFilters)
	local candidateAbilityIds = {}
	local hasAbilityIdFilter = false

	for _, effectFilter in ipairs (effectFilters or {})
	do
		if (not effectFilter.abilityIdsHash) then return nil end

		hasAbilityIdFilter = true
		for abilityId, _ in pairs (effectFilter.abilityIdsHash)
		do
			candidateAbilityIds[abilityId] = true
		end
	end

	if (hasAbilityIdFilter) then return candidateAbilityIds end
	return nil
end


local function EffectsIndicatorGetExpressionCandidateType (expression, filtersByNames, isNegated)
	local negateNext = isNegated == true

	for _, value in ipairs (expression or {})
	do
		if (value == "not")
		then
			negateNext = not negateNext
		elseif (value == "and")
		then
			negateNext = isNegated == true
		elseif (type (value) == "table")
		then
			local nestedType = EffectsIndicatorGetExpressionCandidateType (value, filtersByNames, negateNext)
			if (nestedType) then return nestedType end
			negateNext = isNegated == true
		else
			if (not negateNext)
			then
				local filterType = EffectsIndicatorGetPositiveCandidateType (filtersByNames[value])
				if (filterType) then return filterType end
			end
			negateNext = isNegated == true
		end
	end

	return nil
end

--------------------------------------------------------------- EnemyEffectsIndicator class
EnemyEffectsIndicator = {}
EnemyEffectsIndicator.__index = EnemyEffectsIndicator

-- A sweep keeps a bounded list of expired indicator/player pairs. Rebinding
-- one of those same objects before its queued row runs would revive old work.
function EnemyEffectsIndicator.IsSweepRunning ()
    return EffectsIndicatorSweepRunning
end

local ConstructorSources = Enemy._constructorSources or {}
local LogicStringSource = ConstructorSources.logicString
local LogicParseHelpers = {
    LogicalExpressionParse = ConstructorSources.LogicalExpressionParse,
    toString = ConstructorSources.toString,
    tostring = ConstructorSources.tostring,
    stringLen = LogicStringSource and LogicStringSource.len,
    stringSub = LogicStringSource and LogicStringSource.sub,
}
EnemyEffectsIndicator._logicParseHelpers = LogicParseHelpers
local LogicStringLibrary = LogicStringSource and LogicStringSource.library
local LogicStringMetatable = LogicStringSource and LogicStringSource.metatable
local LogicTrees, LogicKeys, LogicCursor = {}, {}, 1
local LogicCacheLimit, LogicLengthLimit = 64, 4096

local function CopyLogicTree (tree, depth)
    if (type (tree) ~= "table" or getmetatable (tree) ~= nil or depth > 32) then return nil end
    local copy = {}
    for index, token in ipairs (tree) do
        if (type (token) == "table") then
            copy[index] = CopyLogicTree (token, depth + 1)
            if (not copy[index]) then return nil end
        elseif (type (token) == "string") then
            copy[index] = token
        else
            return nil
        end
    end
    return copy
end

local function ParseIndicatorLogic (logic)
    -- Keep the legacy call target and argument evaluation order, including a
    -- custom converter's optional parser start-position return value.
    local parse, convert = Enemy.LogicalExpressionParse, Enemy.toString
    local kind = type (logic)
    if ((kind ~= "string" and kind ~= "wstring")
        or parse ~= LogicParseHelpers.LogicalExpressionParse or convert ~= LogicParseHelpers.toString
        or tostring ~= LogicParseHelpers.tostring or string ~= LogicStringLibrary
        or string.len ~= LogicParseHelpers.stringLen or string.sub ~= LogicParseHelpers.stringSub
        or getmetatable ("") ~= LogicStringMetatable
        or (LogicStringMetatable and (type (LogicStringMetatable) ~= "table"
            or rawget (LogicStringMetatable, "__index") ~= LogicStringLibrary)))
    then
        return parse (convert (logic))
    end
    local text, startPos = convert (logic)
    if (type (text) ~= "string" or #text > LogicLengthLimit or startPos ~= nil
        or Enemy.LogicalExpressionParse ~= parse)
    then return parse (text, startPos) end
    local tree = LogicTrees[text]
    if (tree) then return CopyLogicTree (tree, 0) end
    tree = parse (text)
    local copy = CopyLogicTree (tree, 0)
    if (not copy) then return tree end
    -- The parser's tree stays private. Every indicator gets a separate mutable
    -- copy and still builds its current filters, name map and cleanse callback.
    local oldKey = LogicKeys[LogicCursor]
    if (oldKey ~= nil) then LogicTrees[oldKey] = nil end
    LogicKeys[LogicCursor], LogicTrees[text] = text, tree
    LogicCursor = LogicCursor % LogicCacheLimit + 1
    return copy
end

function EnemyEffectsIndicator.New (data)
	local obj = {}
	setmetatable (obj, EnemyEffectsIndicator)

	-- defaults
	obj.id = tostring (Enemy.NewId ())

	obj.isEnabled = true
	obj.name = nil
	obj.logic = nil
	obj.canDispell = 1
	obj.playerTypeMatch = 1
	obj.playerType = 3
	obj.exceptMe = false
	obj.archetypeMatch = 1
    obj.archetypes = { false, false, false }

    obj.effectFilters = {}

	obj.icon = "effect"
	obj.customIcon = nil
	obj.isCircleIcon = false
	obj.isTimer = false
    obj.color = { r = 255, g = 255, b = 255 }
	obj.alpha = 1
	obj.scale = 1

	obj.labelScale = 1


	obj.anchorFrom = 5
	obj.anchorTo = 5
	obj.offsetX = 20
	obj.offsetY = nil
	obj.width = nil

	obj.height = nil

	obj.ticked = 0
	obj._lastTimerValue = nil
	obj._timerLabelAllowed = false
	obj._isShowing = nil

	if (data)
	then
		obj:Load (data)
	end

	return obj
end


function EnemyEffectsIndicator:Load (data)
	EffectsIndicatorStopTimer (self)

	self.name = data.name
	self.isEnabled = data.isEnabled
	self.logic = data.logic
	-- Older/custom profiles can save a blank logic field as L"". Blank means
	-- "any filter", so keep it on the simple path instead of the expensive
	-- custom-expression path during effect storms.
	if (self.logic ~= nil and Enemy.toString (self.logic) == "")
	then
		self.logic = nil
	end
	self.canDispell = data.canDispell
	self.playerTypeMatch = data.playerTypeMatch
	self.playerType = data.playerType
	self.exceptMe = data.exceptMe
	self.archetypeMatch = data.archetypeMatch

	if (data.archetypes)
	then
		self.archetypes =
		{
			data.archetypes[1] or false,
			data.archetypes[2] or false,
			data.archetypes[3] or false
		}
	end

	if (data.effectFilters)
	then
		self.effectFilters = {}

		for _, effect_filter in pairs (data.effectFilters)
		do
			tinsert (self.effectFilters, EnemyEffectFilter.New (effect_filter))
		end
	end

	self.icon = data.icon
	self.customIcon = data.customIcon
	self.isCircleIcon = data.isCircleIcon
	self.isTimer = data.isTimer


	if (data.color)
	then
		self.color =
		{
			r = data.color.r or 0,
			g = data.color.g or 0,
			b = data.color.b or 0
		}
	end

	self.alpha = data.alpha
	self.labelScale = data.labelScale

	self.scale = data.scale
	self.anchorFrom = data.anchorFrom
	self.anchorTo = data.anchorTo
	self.offsetX = data.offsetX
	self.offsetY = data.offsetY
	self.width = data.width
	self.height = data.height

	self._archetypesFilterPresent = (self.archetypes[1] or self.archetypes[2] or self.archetypes[3])

	self.ticked = 0

	-- prepare logic data and functions
	if (self.logic)
	then
		self._logicExpression = ParseIndicatorLogic (self.logic)

		self._effectFiltersByNames = {}
		for _, effect_filter in pairs (self.effectFilters)
		do
			self._effectFiltersByNames[Enemy.toString (effect_filter.filterName)] = effect_filter
		end
	else
		self._logicExpression = nil
	end

	-- Pressure limiting must never hide indicators that can match only effects
	-- cast by the local player. Custom logic stays on the complete-update path
	-- because its combined filter meaning is not safe to simplify here.
	self._selfCastOnly = false
	if (not self._logicExpression and #self.effectFilters > 0)
	then
		self._selfCastOnly = true
		for _, effect_filter in ipairs (self.effectFilters)
		do
			if (effect_filter._enemyFilterRequiresPlayerCaster ~= true)
			then
				self._selfCastOnly = false
				break
			end
		end
	end

	self._candidateEffectType = nil
	if (self._logicExpression)
	then
		-- Expressions with "or" keep the full scan, because any one branch can
		-- be the valid match. Positive required types in "and"-only expressions
		-- can safely use the narrow per-player type index.
		if (not EffectsIndicatorExpressionContainsOr (self._logicExpression))
		then
			self._candidateEffectType = EffectsIndicatorGetExpressionCandidateType (self._logicExpression, self._effectFiltersByNames, false)
		end
	else
		self._candidateEffectType = EffectsIndicatorGetSimpleCandidateType (self.effectFilters)
	end

	self._abilityIdFilterIndex = nil
	self._candidateAbilityIds = nil
	if (not self._logicExpression)
	then
		local abilityIdFilterIndex
		local hasAbilityIdFilter = false
		local hasOtherFilter = false

		for _, effect_filter in ipairs (self.effectFilters)
		do
			if (effect_filter.abilityIdsHash)
			then
				hasAbilityIdFilter = true
                abilityIdFilterIndex = abilityIdFilterIndex or {}
				for abilityId, _ in pairs (effect_filter.abilityIdsHash)
				do
					abilityIdFilterIndex[abilityId] = abilityIdFilterIndex[abilityId] or {}
					tinsert (abilityIdFilterIndex[abilityId], effect_filter)
				end
			else
				hasOtherFilter = true
			end
		end

		if (hasAbilityIdFilter and not hasOtherFilter)
		then
			self._abilityIdFilterIndex = abilityIdFilterIndex
		end
	elseif (not EffectsIndicatorExpressionContainsNot (self._logicExpression))
	then
		-- Custom "or"/"and" expressions made only from ability-id filters still
		-- cannot match effects with unrelated ids. Use the id union as a
		-- candidate gate, then evaluate the original expression unchanged.
		self._candidateAbilityIds = EffectsIndicatorGetAbilityCandidateIds (self.effectFilters)
	end

	-- prepare can dispell check function
	if (self.canDispell ~= 1)
	then
		if (not Enemy.groups.canCleanse)
		then
			self._checkDispell = function (player, effect)
				return (self.canDispell == 3)
			end

		else
			if (Enemy.groups.canCleanse == "self")
			then
				self._checkDispell = function (player, effect)

					return (
								player.isSelf
								and
								(
									(
										(effect.isHex and Enemy.groups.canCleanseHex)
										or
										(effect.isAilment and Enemy.groups.canCleanseAilment)
										or
										(effect.isCurse and Enemy.groups.canCleanseCurse)

									) == (self.canDispell == 2)
								)
							)
				end
			else
				self._checkDispell = function (player, effect)

					return (
								(effect.isHex and Enemy.groups.canCleanseHex)
								or
								(effect.isAilment and Enemy.groups.canCleanseAilment)
								or
								(effect.isCurse and Enemy.groups.canCleanseCurse)

							) == (self.canDispell == 2)
				end
			end
		end
	end
    self._windowReuseCheckDispell = self._checkDispell
    self._windowReuseLoaded = true
end


function EnemyEffectsIndicator:Hide ()
	EffectsIndicatorSetShowing (self, false)
end


function EnemyEffectsIndicator:Show ()
	EffectsIndicatorSetShowing (self, true)
end


function EnemyEffectsIndicator:Edit (settings, onOkCallback)

	Enemy.UnitFramesUI_EffectsIndicatorDialog_Open (self, settings, self.id, function (old, new)

		old:Load (new)

		if (onOkCallback)
		then
			onOkCallback (self)
		end
	end)
end


function EnemyEffectsIndicator:Remove ()
	EffectsIndicatorStopTimer (self)
    self._frame = nil

	if (self.windowName)
	then
        if (Enemy.UnitFrameWindowReuse)
        then
            Enemy.UnitFrameWindowReuse.Release (self, self.windowName, self._isShowing)
        elseif (DoesWindowExist (self.windowName)) then
            DestroyWindow (self.windowName)
        end
		self.windowName = nil
		self._isShowing = nil
		self._lastTimerValue = nil
		self._timerLabelAllowed = false
	end

	self:BoundingBoxSetShowing (false)
end


function EnemyEffectsIndicator:BoundingBoxSetShowing (show)

	if (self._boundingBoxWindowName)
	then
		if (DoesWindowExist (self._boundingBoxWindowName)) then DestroyWindow (self._boundingBoxWindowName) end
		self._boundingBoxWindowName = nil
	end

	if (show and self.windowName)
	then
		self._boundingBoxWindowName = "BoundingBox"..Enemy.NewId ()
		CreateWindowFromTemplate (self._boundingBoxWindowName, "EnemyRectangleTemplate", self.windowName)
		WindowSetLayer (self._boundingBoxWindowName, Window.Layers.OVERLAY)
		WindowAddAnchor (self._boundingBoxWindowName, "topleft", self.windowName, "topleft", 0, 0)
		WindowAddAnchor (self._boundingBoxWindowName, "bottomright", self.windowName, "bottomright", 0, 0)
	end
end


function EnemyEffectsIndicator:Update (frame)

	if (not frame) then return end
    self._frame = frame

    local texture, texture_x, texture_y
	local dx, dy

	local icon = Icons[self.icon]
	if (icon)
	then
		texture = icon.texture
		texture_x = icon.x
		texture_y = icon.y
		dx = icon.width
		dy = icon.height
	else
		texture, texture_x, texture_y = GetIconData (self.customIcon or 1)
		dx, dy = 64, 64
	end

	if (self.width ~= nil) then dx = self.width end
	if (self.height ~= nil) then dy = self.height end

	if (not self.windowName)
	then
        local template = self.isCircleIcon and "EnemyCircleImageTemplate" or "EnemyDynamicImageTemplate"
        local name = "EnemyEffectsIndicator"..self.id
        local reused = false
        if (Enemy.UnitFrameWindowReuse)
        then
            name, reused = Enemy.UnitFrameWindowReuse.Acquire (self, template, frame.windowName, name, nil, texture ~= nil)
        else
            CreateWindowFromTemplate (name, template, frame.windowName)
        end
        self.windowName = name

        if (not reused) then WindowSetShowing (self.windowName, false) end
		self._isShowing = false
		self._lastTimerValue = nil

		self.isCircleIconCurrent = self.isCircleIcon
		WindowSetLayer (self.windowName, Window.Layers.POPUP)

	elseif (self.isCircleIcon ~= self.isCircleIconCurrent)
	then
		self:Remove ()
		self:Update (frame)
		return
	end

	local global_scale = InterfaceCore.GetScale ()

	WindowSetDimensions (self.windowName, dx, dy)
	WindowSetScale (self.windowName, self.scale * frame.settings.unitFramesScale * global_scale)
	if (self.labelScale == nil) then
		self.labelScale = 1
	end
	if (self.isTimer == nil) then
		self.isTimer = false
	end
	self._timerLabelAllowed = (self.isTimer == true and dx > 20 and dy > 20)
	WindowSetScale (self.windowName.."TLabel", self.labelScale * frame.settings.unitFramesScale * global_scale)
	WindowSetShowing(self.windowName.."TLabel", self.isTimer)
	if (self.ticked and self.ticked > Enemy.time and self.isTimer == true)
	then
		EffectsIndicatorRenderTimer (self)
	else
		EffectsIndicatorSetTimerLabel (self, nil)
	end


	WindowClearAnchors (self.windowName)
	WindowAddAnchor (self.windowName, Enemy.Anchors[self.anchorFrom], frame.windowName, Enemy.Anchors[self.anchorTo], self.offsetX or 0, self.offsetY or 0)

	if (self.isCircleIcon)
	then
		CircleImageSetTexture (self.windowName, texture, texture_x + dx / 2, texture_y + dy / 2)
	else
		DynamicImageSetTexture (self.windowName, texture, texture_x, texture_y)
	end

	WindowSetTintColor (self.windowName, self.color.r, self.color.g, self.color.b)
	WindowSetAlpha (self.windowName, self.alpha)
end


--
-- Check wherever any effect on specified player can possibly light up this effect indicator
--
local function CanMatch (data, player, fromSettings)
    if ((data.playerType == 2 and player.isSelf ~= (data.playerTypeMatch == 1))
        or (data.playerType == 3 and player.isInPlayerGroup ~= (data.playerTypeMatch == 1))
        or (data.exceptMe and player.isSelf))
    then
        return false
    end

    local archetypes = data.archetypes
    local filterPresent = data._archetypesFilterPresent
    if (fromSettings)
    then
        filterPresent = archetypes and (archetypes[1] or archetypes[2] or archetypes[3])
    end

    if (filterPresent)
    then
        local index = Enemy.careerArchetypes[player.career]
        local selected = archetypes[index]
        if (fromSettings)
        then
            -- Load copies only these three slots and replaces holes with false.
            -- An unknown career still indexes nil, even for an exclusion mask.
            if (index == 1 or index == 2 or index == 3)
            then
                selected = selected or false
            else
                selected = nil
            end
        end
        if (selected ~= (data.archetypeMatch == 1)) then return false end
    end

    if (data.canDispell == 2
        and (not Enemy.groups.canCleanse or (Enemy.groups.canCleanse == "self" and not player.isSelf)))
    then
        return false
    end

    return true
end


function EnemyEffectsIndicator:CanMatch (player)
    return CanMatch (self, player, false)
end


-- Skip allocations only while the complete built-in construction/match path is
-- intact. Replaced public callbacks retain their original invocation order.
local constructionMethods =
{
    New = EnemyEffectsIndicator.New,
    Load = EnemyEffectsIndicator.Load,
    CanMatch = EnemyEffectsIndicator.CanMatch,
    __index = EnemyEffectsIndicator,
}
EnemyEffectsIndicator._constructionMethods = constructionMethods
local constructionKeys = {}

local constructionFilterMethods =
{
    New = EnemyEffectFilter.New,
    Load = EnemyEffectFilter.Load,
    __index = EnemyEffectFilter,
}
EnemyEffectFilter._constructionMethods = constructionFilterMethods
if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.RegisterClass (EnemyEffectFilter) end
local constructionFilterKeys = {}
for key in pairs (EnemyEffectFilter) do constructionFilterKeys[key] = true end


function EnemyEffectsIndicator.CanSkipConstruction (data, player, testMode)
    -- New objects inherit from the class, including fields Load assigns nil.
    -- Added defaults or assignment/prototype hooks require real construction.
    if (getmetatable (EnemyEffectsIndicator) ~= nil) then return false end
    for key in pairs (EnemyEffectsIndicator)
    do
        if (not constructionKeys[key]) then return false end
    end
    for key, original in pairs (constructionMethods)
    do
        if (EnemyEffectsIndicator[key] ~= original) then return false end
    end
    if (type (data) ~= "table" or getmetatable (data) ~= nil
        or (data.archetypes and getmetatable (data.archetypes) ~= nil))
    then
        return false
    end
    if (getmetatable (EnemyEffectFilter) ~= nil) then return false end
    for key in pairs (EnemyEffectFilter)
    do
        if (not constructionFilterKeys[key]) then return false end
    end
    for key, original in pairs (constructionFilterMethods)
    do
        if (EnemyEffectFilter[key] ~= original) then return false end
    end
    return not data.isEnabled or (not testMode and not CanMatch (data, player, true))
end


local function EffectsIndicatorCheckLogicalFilter (name, indicator, effect)
    local filter = indicator._effectFiltersByNames[name]
    if (filter == nil) then return false end
    return filter:IsMatch (effect)
end


function EnemyEffectsIndicator:EffectsUpdated (player, testMode)

	local show
	local matchedTimeout = nil

	if (testMode)
	then
		show = true
	elseif (not player)
	then
		show = false
	else
		show = false

		local abilityIdFilterIndex = self._abilityIdFilterIndex
		if (abilityIdFilterIndex and player.effectsByAbilityId)
		then
			for abilityId, effect_filters in pairs (abilityIdFilterIndex)
			do
				local effects = player.effectsByAbilityId[abilityId]
				if (effects)
				then
					for _, effect in pairs (effects)
					do
						if (self._checkDispell and not self._checkDispell (player, effect)) then continue end

						for _, effect_filter in ipairs (effect_filters)
						do
							if (effect_filter:IsMatch (effect))
							then
								local matchCanShow
								matchCanShow, matchedTimeout = EffectsIndicatorGetMatchTimeout (self, effect)
								if (matchCanShow) then show = true end
								break
							end
						end

						if (show) then break end
					end
				end

				if (show) then break end
			end

		elseif (self._candidateAbilityIds and player.effectsByAbilityId)
		then
			for abilityId, _ in pairs (self._candidateAbilityIds)
			do
				local effects = player.effectsByAbilityId[abilityId]
				if (effects)
				then
					for _, effect in pairs (effects)
					do
						if (self._checkDispell and not self._checkDispell (player, effect)) then continue end

                        if (Enemy.LogicalExpressionEvaluate (self._logicExpression, EffectsIndicatorCheckLogicalFilter, self, effect))
						then
							local matchCanShow
							matchCanShow, matchedTimeout = EffectsIndicatorGetMatchTimeout (self, effect)
							if (matchCanShow)
							then
								show = true
								break
							end
						end
					end
				end

				if (show) then break end
			end

		else
			local effects = player.effects
			if (self._candidateEffectType)
			then
				effects = player.effectsByType and player.effectsByType[self._candidateEffectType] or nil
			end

			for _, effect in pairs (effects or EmptyEffects)
			do
				if (self._checkDispell and not self._checkDispell (player, effect)) then continue end

				local match = false

				if (self._logicExpression == nil)
				then
					-- simple 'or' logic
					for _, effect_filter in ipairs (self.effectFilters)
					do
						if (effect_filter:IsMatch (effect))
						then
							match = true
							break
						end
					end
				else
					-- custom logic expression
                    match = Enemy.LogicalExpressionEvaluate (self._logicExpression, EffectsIndicatorCheckLogicalFilter, self, effect)
				end

				if (match)
				then
					local matchCanShow
					matchCanShow, matchedTimeout = EffectsIndicatorGetMatchTimeout (self, effect)
					if (matchCanShow)
					then
						show = true
						break
					end
				end
			end
		end
	end

	if (show and matchedTimeout)
	then
		EffectsIndicatorStartTimer (self, player, matchedTimeout)
	else
		EffectsIndicatorStopTimer (self)
	end

	EffectsIndicatorSetShowing (self, show)
end


----------------------------------------------------------------- UI: Effect indicator dialog
local dlg =
{
	isInitialized = false,
	effectFiltersListSelectedIndex = nil,
	exampleConfigParameters =
	{
		exampleShowBoundingBox =
		{
			key = "exampleShowBoundingBox",
			order = 10,
			name = L"Show bounding box",
			type = "bool",
			default = false,
			windowWidth = 300
		},
		exampleShowUnitFrameBoundingBox =
		{
			key = "exampleShowUnitFrameBoundingBox",
			order = 20,
			name = L"Show unit frame bounding box",
			type = "bool",
			default = false,
			windowWidth = 300
		},
		exampleHideOthers =
		{
			key = "exampleHideOthers",
			order = 30,
			name = L"Hide other effects indicators",
			type = "bool",
			default = true,
			windowWidth = 300
		},
		exampleNew =
		{
			key = "exampleNew",
			order = 40,
			name = L"New example",
			type = "button",
			windowWidth = 150
		}
	}
}


function Enemy.UnitFramesUI_EffectsIndicatorDialog_IsOpen ()
	return WindowGetShowing ("EnemyEffectsIndicatorDialog")
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_Hide ()

	dlg.example:Remove ()
	dlg.data:Remove ()
	if (dlg.wnExampleCfg and DoesWindowExist (dlg.wnExampleCfg)) then DestroyWindow (dlg.wnExampleCfg) end

	WindowSetShowing ("EnemyEffectsIndicatorDialog", false)
end

function Enemy.UnitFramesUI_EffectsIndicatorDialog_OnLogicMouseOver ()
	Tooltips.CreateTextOnlyTooltip (SystemData.MouseOverWindow.name)
	Tooltips.SetTooltipText (1, 1, L"Use filter names with and/or/not")
	Tooltips.SetTooltipText (2, 1, L"Leave blank = any filter")
	Tooltips.AnchorTooltip (Tooltips.ANCHOR_CURSOR)
	Tooltips.Finalize()
end

function Enemy.UnitFramesUI_EffectsIndicatorDialog_Open (data, settings, ignoreId, onOkCallback)

	dlg.isLoading = true

	if (not dlg.isInitialized)
	then
		-- initialize dialog UI
		CreateWindow ("EnemyEffectsIndicatorDialog", false)

		LabelSetText ("EnemyEffectsIndicatorDialogTitleBarText", L"Effects indicator")
		ButtonSetText ("EnemyEffectsIndicatorDialogOkButton", L"OK")
		ButtonSetText ("EnemyEffectsIndicatorDialogCancelButton", L"Cancel")

		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildNameLabel", L"Name")

		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersLabel", L"Effect filters")
		WindowSetTintColor ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersListBackground", 100, 100, 100)
		WindowSetAlpha ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersListBackground", 0.5)
		ButtonSetText ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersAddButton", L"Add")
		ButtonSetText ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersEditButton", L"Edit")
		ButtonSetText ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersDeleteButton", L"Delete")
		ButtonSetText ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersUpButton", L"Up")
		ButtonSetText ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersDownButton", L"Down")

		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildLogicLabel", L"Logic")

		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildCanDispellLabel", L"I can dispell it")
		ComboBoxAddMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildCanDispell", L"doesn't matter")
		ComboBoxAddMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildCanDispell", L"yes")
		ComboBoxAddMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildCanDispell", L"no")

		ComboBoxAddMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildPlayerTypeMatch", L"Only on")
		ComboBoxAddMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildPlayerTypeMatch", L"Except for")
		ComboBoxAddMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildPlayerType", L"all")
		ComboBoxAddMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildPlayerType", L"me")
		ComboBoxAddMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildPlayerType", L"my group")
		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildExceptMeLabel", L"except me")

		ComboBoxAddMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildArchetypeMatch", L"Only on")
		ComboBoxAddMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildArchetypeMatch", L"Except for")
		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildArchetype1Label", L"tanks")
		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildArchetype2Label", L"dps")
		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildArchetype3Label", L"healers")

		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildIconLabel", L"Icon")

		dlg.iconsData = {}
		for _, v in pairs(Icons)
		do
			tinsert (dlg.iconsData, v)
		end

		tsort (dlg.iconsData, function (a, b)
			return a.name < b.name
		end)

		tinsert (dlg.iconsData,
		{
			key = "other",
			name = L"other"
		})

		for _, v in ipairs (dlg.iconsData)
		do
			ComboBoxAddMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildIcon", v.name)
		end

		ComboBoxAddMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildIcon", L"other")

		ButtonSetText ("EnemyEffectsIndicatorDialogContentScrollChildChooseIconButton", L"choose")
		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildCircleIconLabel", L"circle")

		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildSizeLabel", L"Size override (XY)")

		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildColorLabel", L"Color (RGB)")
		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildAlphaLabel", L"Alpha")
		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildScaleLabel", L"Scale")
		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildLScaleLabel", L"Text Scale")
                LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildLScaleCheckLabel", L"enabled")


		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildAnchorLabel", L"Anchor")
		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildAnchorLabel2", L"to")

		for _, v in pairs (Enemy.Anchors)
		do
			ComboBoxAddMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildAnchorFrom", Enemy.toWString (v))
			ComboBoxAddMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildAnchorTo", Enemy.toWString (v))
		end

		LabelSetText ("EnemyEffectsIndicatorDialogContentScrollChildOffsetLabel", L"Offset (XY)")

		dlg.isInitialized = true
	end

	-- proceed parameters
	dlg.oldData = data
	dlg.onOkCallback = onOkCallback

	dlg.data = EnemyEffectsIndicator.New (data)

	dlg.settings =
	{
		effectsIndicators = {},
		clickCastings = {}
	}

	if (settings)
	then
		for k, v in pairs (settings)
		do
			if (not k:match("^unitFrames.*")) then continue end
			dlg.settings[k] = v
		end

		if (settings.effectsIndicators)
		then
			for _, effect_indicator in pairs (settings.effectsIndicators)
			do
				if (effect_indicator.id == ignoreId or not effect_indicator.isEnabled) then continue end
				tinsert (dlg.settings.effectsIndicators, Enemy.clone (effect_indicator))
			end
		end
	end

	dlg.settings.unitFramesTestMode = true

	-- example
	dlg.example = EnemyUnitFrame.New (100 + Enemy.NewId (), 100 + Enemy.NewId ())
	dlg.example:ApplySettings (dlg.settings)
	dlg.example:Enable ()

	dlg.examplePlayer = EnemyPlayer.GetRandomExample ()
	dlg.example:Update (dlg.examplePlayer)

	WindowClearAnchors (dlg.example.windowName)
	WindowAddAnchor (dlg.example.windowName, "topright", "EnemyEffectsIndicatorDialog", "topleft", 50, 200)
	WindowSetLayer (dlg.example.windowName, Window.Layers.OVERLAY)

	dlg.wnExampleCfg = "EnemyEffectsIndicatorDialogExampleCfg"
	dlg.exampleConfigParameters.exampleNew.onClick = Enemy.UnitFramesUI_EffectsIndicatorDialog_OnNewExampleClick
	Enemy.CreateConfigurationWindow (dlg.wnExampleCfg, "Root", dlg.exampleConfigParameters, Enemy.UnitFramesUI_EffectsIndicatorDialog_UpdateExample)
	WindowClearAnchors (dlg.wnExampleCfg)
	WindowAddAnchor (dlg.wnExampleCfg, "bottomleft", dlg.example.windowName, "topleft", 0, 50)

	-- fill form

	TextEditBoxSetText ("EnemyEffectsIndicatorDialogContentScrollChildName", Enemy.isNil (dlg.data.name, L""))

	dlg.effectFiltersListSelectedIndex = nil

	TextEditBoxSetText ("EnemyEffectsIndicatorDialogContentScrollChildLogic", Enemy.isNil (dlg.data.logic, L""))

	ComboBoxSetSelectedMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildCanDispell", dlg.data.canDispell)
	ComboBoxSetSelectedMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildPlayerTypeMatch", dlg.data.playerTypeMatch)
	ComboBoxSetSelectedMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildPlayerType", dlg.data.playerType)
	ButtonSetPressedFlag ("EnemyEffectsIndicatorDialogContentScrollChildExceptMe", dlg.data.exceptMe)

	ComboBoxSetSelectedMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildArchetypeMatch", dlg.data.archetypeMatch)
	for k, a in pairs(dlg.data.archetypes)
	do
		ButtonSetPressedFlag ("EnemyEffectsIndicatorDialogContentScrollChildArchetype"..k, a)
	end

	for k, v in pairs (dlg.iconsData)
	do
		if (v.key == dlg.data.icon)
		then
			ComboBoxSetSelectedMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildIcon", k)
		end
	end

	ButtonSetPressedFlag ("EnemyEffectsIndicatorDialogContentScrollChildCircleIcon", dlg.data.isCircleIcon)
	ButtonSetPressedFlag ("EnemyEffectsIndicatorDialogContentScrollChildLScaleCheckBox", dlg.data.isTimer)
	TextEditBoxSetText ("EnemyEffectsIndicatorDialogContentScrollChildSizeX", Enemy.toWStringOrEmpty (dlg.data.width))
	TextEditBoxSetText ("EnemyEffectsIndicatorDialogContentScrollChildSizeY", Enemy.toWStringOrEmpty (dlg.data.height))
	SliderBarSetCurrentPosition ("EnemyEffectsIndicatorDialogContentScrollChildColorR", dlg.data.color.r / 255.0)
	SliderBarSetCurrentPosition ("EnemyEffectsIndicatorDialogContentScrollChildColorG", dlg.data.color.g / 255.0)
	SliderBarSetCurrentPosition ("EnemyEffectsIndicatorDialogContentScrollChildColorB", dlg.data.color.b / 255.0)
	SliderBarSetCurrentPosition ("EnemyEffectsIndicatorDialogContentScrollChildAlpha", dlg.data.alpha)
	TextEditBoxSetText ("EnemyEffectsIndicatorDialogContentScrollChildScale", Enemy.toWString (dlg.data.scale))
	TextEditBoxSetText ("EnemyEffectsIndicatorDialogContentScrollChildLScale", Enemy.toWString (dlg.data.labelScale))
	ComboBoxSetSelectedMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildAnchorFrom", dlg.data.anchorFrom)

	ComboBoxSetSelectedMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildAnchorTo", dlg.data.anchorTo)
	TextEditBoxSetText ("EnemyEffectsIndicatorDialogContentScrollChildOffsetX", Enemy.toWStringOrEmpty (dlg.data.offsetX))
	TextEditBoxSetText ("EnemyEffectsIndicatorDialogContentScrollChildOffsetY", Enemy.toWStringOrEmpty (dlg.data.offsetY))

	Enemy.ConfigurationWindowReset (dlg.wnExampleCfg)

	dlg.isLoading = false
	WindowSetShowing ("EnemyEffectsIndicatorDialog", true)

	Enemy.UnitFramesUI_EffectsIndicatorDialog_UpdateExample ()
	Enemy.UnitFramesUI_EffectsIndicatorDialog_OnEffectFiltersListSelChanged ()
	Enemy.UnitFramesUI_EffectsIndicatorDialog_OnIconSelChanged ()

	ScrollWindowSetOffset ("EnemyEffectsIndicatorDialogContent", 0)
	ScrollWindowUpdateScrollRect ("EnemyEffectsIndicatorDialogContent")
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_OnEffectFiltersListPopulate ()

	if (dlg.isLoading or not EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersList.PopulatorIndices) then return end

	local row_window_name

	for k, v in ipairs (EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersList.PopulatorIndices)
	do
		row_window_name = "EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersListRow"..k

		if (v == dlg.effectFiltersListSelectedIndex)
		then
			WindowSetShowing (row_window_name.."Background", true)
			WindowSetAlpha (row_window_name.."Background", 0.5)
			WindowSetTintColor (row_window_name.."Background", 200, 200, 100)
		else
			WindowSetShowing (row_window_name.."Background", false)
		end
	end
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_UpdateEffectFiltersList ()

	if (dlg.isLoading) then return end

	Enemy.effectsIndicatorEffectsListData = {}
	Enemy.effectsIndicatorEffectsListIndexes = {}

	for k, data in ipairs(dlg.data.effectFilters)
	do
		tinsert (Enemy.effectsIndicatorEffectsListData, data)
		tinsert (Enemy.effectsIndicatorEffectsListIndexes, k)
	end

	ListBoxSetDisplayOrder ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersList", Enemy.effectsIndicatorEffectsListIndexes)
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_OnEffectFiltersListLButtonUp ()

	if (dlg.isLoading) then return end

	local data_index = ListBoxGetDataIndex ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersList", WindowGetId (SystemData.MouseOverWindow.name))

	if (data_index == nil)
	then
		dlg.effectFiltersListSelectedIndex = nil
	else
		dlg.effectFiltersListSelectedIndex = Enemy.effectsIndicatorEffectsListIndexes[data_index]
	end

	Enemy.UnitFramesUI_EffectsIndicatorDialog_OnEffectFiltersListSelChanged ()
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_OnEffectFiltersListSelChanged ()

	if (dlg.isLoading) then return end

	if (not dlg.data.effectFilters[dlg.effectFiltersListSelectedIndex])
	then
		dlg.effectFiltersListSelectedIndex = nil
	end

	Enemy.UnitFramesUI_EffectsIndicatorDialog_UpdateEffectFiltersList ()
	ButtonSetDisabledFlag ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersEditButton", dlg.effectFiltersListSelectedIndex == nil)
	ButtonSetDisabledFlag ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersDeleteButton", dlg.effectFiltersListSelectedIndex == nil)
	ButtonSetDisabledFlag ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersUpButton", dlg.effectFiltersListSelectedIndex == nil or dlg.effectFiltersListSelectedIndex == 1)
	ButtonSetDisabledFlag ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersDownButton", dlg.effectFiltersListSelectedIndex == nil or dlg.effectFiltersListSelectedIndex == #dlg.data.effectFilters)
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_EffectFiltersAdd ()

	if (dlg.isLoading) then return end

	local effect_filter = EnemyEffectFilter.New ()
	effect_filter:Edit (function (effectFilter)

		tinsert (dlg.data.effectFilters, effectFilter)

		dlg.effectFiltersListSelectedIndex = #dlg.data.effectFilters
		Enemy.UnitFramesUI_EffectsIndicatorDialog_OnEffectFiltersListSelChanged ()
	end)
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_EffectFiltersEdit ()

	if (dlg.isLoading
		or not dlg.effectFiltersListSelectedIndex
		or ButtonGetDisabledFlag ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersEditButton")) then return end

	local effect_filter = dlg.data.effectFilters[dlg.effectFiltersListSelectedIndex]
	effect_filter:Edit (function (effectFilter)
		Enemy.UnitFramesUI_EffectsIndicatorDialog_UpdateEffectFiltersList ()
	end)
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_EffectFiltersDelete ()

	if (dlg.isLoading
		or not dlg.effectFiltersListSelectedIndex
		or ButtonGetDisabledFlag ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersDeleteButton")) then return end

	DialogManager.MakeTwoButtonDialog (L"Delete effect filter '"..Enemy.isNil (dlg.data.effectFilters[dlg.effectFiltersListSelectedIndex].filterName, L"")..L"' ?",
                                       L"Yes", function ()

                                               table.remove (dlg.data.effectFilters, dlg.effectFiltersListSelectedIndex)
                                               dlg.effectFiltersListSelectedIndex = nil
                                               Enemy.UnitFramesUI_EffectsIndicatorDialog_OnEffectFiltersListSelChanged ()
                                       end,
                                       L"No")
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_EffectFiltersUp ()

	if (not dlg.effectFiltersListSelectedIndex
		or ButtonGetDisabledFlag ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersUpButton")) then return end

	local index = dlg.effectFiltersListSelectedIndex

	local tmp = dlg.data.effectFilters[index - 1]
	dlg.data.effectFilters[index - 1] = dlg.data.effectFilters[index]
	dlg.data.effectFilters[index] = tmp

	dlg.effectFiltersListSelectedIndex = index - 1
	Enemy.UnitFramesUI_EffectsIndicatorDialog_OnEffectFiltersListSelChanged ()
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_EffectFiltersDown ()

	if (not dlg.effectFiltersListSelectedIndex
		or ButtonGetDisabledFlag ("EnemyEffectsIndicatorDialogContentScrollChildEffectFiltersDownButton")) then return end

	local index = dlg.effectFiltersListSelectedIndex

	local tmp = dlg.data.effectFilters[index + 1]
	dlg.data.effectFilters[index + 1] = dlg.data.effectFilters[index]
	dlg.data.effectFilters[index] = tmp

	dlg.effectFiltersListSelectedIndex = index + 1
	Enemy.UnitFramesUI_EffectsIndicatorDialog_OnEffectFiltersListSelChanged ()
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_OnExceptMeChanged ()

	if (dlg.isLoading) then return end

	dlg.data.exceptMe = not dlg.data.exceptMe
	ButtonSetPressedFlag ("EnemyEffectsIndicatorDialogContentScrollChildExceptMe", dlg.data.exceptMe)
end


local function _OnArchetypeChanged (n)

	if (dlg.isLoading) then return end

	dlg.data.archetypes[n] = not dlg.data.archetypes[n]
	ButtonSetPressedFlag ("EnemyEffectsIndicatorDialogContentScrollChildArchetype"..n, dlg.data.archetypes[n])
end

function Enemy.UnitFramesUI_EffectsIndicatorDialog_OnArchetype1Changed ()
	_OnArchetypeChanged (1)
end

function Enemy.UnitFramesUI_EffectsIndicatorDialog_OnArchetype2Changed ()
	_OnArchetypeChanged (2)
end

function Enemy.UnitFramesUI_EffectsIndicatorDialog_OnArchetype3Changed ()
	_OnArchetypeChanged (3)
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_OnIconSelChanged ()

	if (dlg.isLoading) then return end

	local value = ComboBoxGetSelectedMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildIcon")
	ButtonSetDisabledFlag ("EnemyEffectsIndicatorDialogContentScrollChildChooseIconButton", value <= #Icons)
	Enemy.UnitFramesUI_EffectsIndicatorDialog_UpdateExample ()
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_ChooseIcon ()

	if (dlg.isLoading or ButtonGetDisabledFlag ("EnemyEffectsIndicatorDialogContentScrollChildChooseIconButton")) then return end

	Enemy.UI_ChooseIconDialog_Open (function (iconId)
		dlg.data.customIcon = iconId
		Enemy.UnitFramesUI_EffectsIndicatorDialog_UpdateExample ()
	end)
end

function Enemy.UnitFramesUI_EffectsIndicatorDialog_OnCircleIconChanged ()

	if (dlg.isLoading) then return end

	dlg.data.isCircleIcon = not dlg.data.isCircleIcon
	ButtonSetPressedFlag ("EnemyEffectsIndicatorDialogContentScrollChildCircleIcon", dlg.data.isCircleIcon)
	Enemy.UnitFramesUI_EffectsIndicatorDialog_UpdateExample ()
end

function Enemy.UnitFramesUI_EffectsIndicatorDialog_OnLScaleCheckBoxChanged()

	if (dlg.isLoading) then return end

	dlg.data.isTimer = not dlg.data.isTimer
	ButtonSetPressedFlag ("EnemyEffectsIndicatorDialogContentScrollChildLScaleCheckBox", dlg.data.isTimer)
	Enemy.UnitFramesUI_EffectsIndicatorDialog_UpdateExample ()
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_UpdateExample ()

	if (dlg.isLoading) then return end

	-- get data from form
	dlg.data.name = Enemy.isEmpty (TextEditBoxGetText ("EnemyEffectsIndicatorDialogContentScrollChildName"), nil)
	dlg.data.logic = Enemy.isEmpty (TextEditBoxGetText ("EnemyEffectsIndicatorDialogContentScrollChildLogic"), nil)
	dlg.data.canDispell = ComboBoxGetSelectedMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildCanDispell")

	dlg.data.playerTypeMatch = ComboBoxGetSelectedMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildPlayerTypeMatch")
	dlg.data.playerType = ComboBoxGetSelectedMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildPlayerType")

	dlg.data.archetypeMatch = ComboBoxGetSelectedMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildArchetypeMatch")
	dlg.data.archetypes =
	{
		ButtonGetPressedFlag ("EnemyEffectsIndicatorDialogContentScrollChildArchetype1"),
		ButtonGetPressedFlag ("EnemyEffectsIndicatorDialogContentScrollChildArchetype2"),
		ButtonGetPressedFlag ("EnemyEffectsIndicatorDialogContentScrollChildArchetype3")
	}

	dlg.data.icon = dlg.iconsData[ComboBoxGetSelectedMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildIcon")].key
	dlg.data.width = Enemy.clamp (1, 1000, Enemy.ConvertToInteger (TextEditBoxGetText ("EnemyEffectsIndicatorDialogContentScrollChildSizeX")))
	dlg.data.height = Enemy.clamp (1, 1000, Enemy.ConvertToInteger (TextEditBoxGetText ("EnemyEffectsIndicatorDialogContentScrollChildSizeY")))
	dlg.data.color.r = math.floor (SliderBarGetCurrentPosition ("EnemyEffectsIndicatorDialogContentScrollChildColorR") * 255.0 + 0.5)
	dlg.data.color.g = math.floor (SliderBarGetCurrentPosition ("EnemyEffectsIndicatorDialogContentScrollChildColorG") * 255.0 + 0.5)
	dlg.data.color.b = math.floor (SliderBarGetCurrentPosition ("EnemyEffectsIndicatorDialogContentScrollChildColorB") * 255.0 + 0.5)
	dlg.data.alpha = SliderBarGetCurrentPosition ("EnemyEffectsIndicatorDialogContentScrollChildAlpha")
	dlg.data.scale = Enemy.clamp (0, 10, Enemy.isNil (Enemy.ConvertToFloat (TextEditBoxGetText ("EnemyEffectsIndicatorDialogContentScrollChildScale")), 0))
	dlg.data.labelScale = Enemy.clamp (0, 10, Enemy.isNil (Enemy.ConvertToFloat (TextEditBoxGetText ("EnemyEffectsIndicatorDialogContentScrollChildLScale")), 0))
	dlg.data.labelScale = Enemy.clamp (0, 10, Enemy.isNil (Enemy.ConvertToFloat (TextEditBoxGetText ("EnemyEffectsIndicatorDialogContentScrollChildLScale")), 0))
	dlg.data.anchorFrom = ComboBoxGetSelectedMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildAnchorFrom")
	dlg.data.anchorTo = ComboBoxGetSelectedMenuItem ("EnemyEffectsIndicatorDialogContentScrollChildAnchorTo")
	dlg.data.offsetX = Enemy.clamp (-5000, 5000, Enemy.ConvertToFloat (TextEditBoxGetText ("EnemyEffectsIndicatorDialogContentScrollChildOffsetX")))
	dlg.data.offsetY = Enemy.clamp (-5000, 5000, Enemy.ConvertToFloat (TextEditBoxGetText ("EnemyEffectsIndicatorDialogContentScrollChildOffsetY")))


	Enemy.ConfigurationWindowSaveData (dlg.wnExampleCfg, dlg)

	for _, v in pairs (dlg.settings.effectsIndicators)
	do
		v.isEnabled = not dlg.exampleHideOthers
	end

	dlg.example.forcePlayerChanged = true
	dlg.example:Update (dlg.examplePlayer)
	dlg.example:UpdateEffects (dlg.examplePlayer)
	dlg.example:BoundingBoxSetShowing (dlg.exampleShowUnitFrameBoundingBox)

	dlg.data:Update (dlg.example)
	dlg.data:EffectsUpdated (dlg.examplePlayer, true)
	dlg.data:BoundingBoxSetShowing (dlg.exampleShowBoundingBox)
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_OnNewExampleClick ()

	dlg.data:Remove ()

	for _, v in pairs (dlg.settings.effectsIndicators)
	do
		v.isEnabled = not dlg.exampleHideOthers
	end

	dlg.examplePlayer = EnemyPlayer.GetRandomExample ()
	dlg.example.forcePlayerChanged = true
	dlg.example:Update (dlg.examplePlayer)
	dlg.example:UpdateEffects (dlg.examplePlayer)
	dlg.example:BoundingBoxSetShowing (dlg.exampleShowUnitFrameBoundingBox)

	dlg.data:Update (dlg.example)
	dlg.data:EffectsUpdated (dlg.examplePlayer, true)
	dlg.data:BoundingBoxSetShowing (dlg.exampleShowBoundingBox)
end


function Enemy.UnitFramesUI_EffectsIndicatorDialog_Ok ()

	if (dlg.isLoading or not Enemy.UnitFramesUI_EffectsIndicatorDialog_IsOpen ()) then return end

	Enemy.UnitFramesUI_EffectsIndicatorDialog_UpdateExample ()

	if (#dlg.data.effectFilters < 1)
	then
		DialogManager.MakeOneButtonDialog (L"You should add at least one effect filter", L"Ok")
		return
	end

	if (dlg.data.logic)
	then
		local expr = Enemy.LogicalExpressionParse (Enemy.toString (dlg.data.logic))
		local effect_filters_names = {}

		for _, v in ipairs (dlg.data.effectFilters)
		do
			local name = Enemy.toString (v.filterName)
			if (effect_filters_names[name])
			then
				DialogManager.MakeOneButtonDialog (L"Dublicate filter name: "..Enemy.toWString (name), L"Ok")
				return
			end

			effect_filters_names[name] = true
		end

		local functions = Enemy.LogicalExpressionGetFunctions (expr)

		for f, _ in pairs (functions)
		do
			if (effect_filters_names[f] == nil)
			then
				DialogManager.MakeOneButtonDialog (L"Error in logic expression: function '"..Enemy.toWString (f)..L"' not found.", L"Ok")
				return
			end
		end
	end

	if (dlg.onOkCallback)
	then
		dlg.onOkCallback (dlg.oldData, dlg.data)
	end

	Enemy.UnitFramesUI_EffectsIndicatorDialog_Hide ()
end


-- Capture the completed class, including methods declared below its matcher.
-- Later extension fields must not silently become inherited object defaults.
for key in pairs (EnemyEffectsIndicator) do constructionKeys[key] = true end

if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.RegisterClass (EnemyEffectsIndicator) end

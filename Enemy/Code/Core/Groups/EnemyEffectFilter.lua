local Enemy = Enemy

-- LUA calls
local FixString = Enemy.FixString
local ipairs = ipairs
local pairs = pairs
local tinsert = table.insert
local tonumber = tonumber
local tostring = tostring
local type = type
local string_find = string.find
local string_lower = string.lower
local string_match = string.match

local Types =
{
	["isDebuff"] = { text = L"debuff", value = "isDebuff" },
	["isAilment"] = { text = L"ailment", value = "isAilment" },
	["isHex"] = { text = L"hex", value = "isHex" },
	["isCurse"] = { text = L"curse", value = "isCurse" },
	["isOffensive"] = { text = L"offensive", value = "isOffensive" },
	["isDamaging"] = { text = L"damaging", value = "isDamaging" },
	["isDefensive"] = { text = L"defensive", value = "isDefensive" },
	["isHealing"] = { text = L"healing", value = "isHealing" },
	["isBuff"] = { text = L"buff", value = "isBuff" },
	["isBlessing"] = { text = L"blessing", value = "isBlessing" },
	["isStatsBuff"] = { text = L"stats buff", value = "isStatsBuff" },
	["isGranted"] = { text = L"granted", value = "isGranted" },
	["isPassive"] = { text = L"passive", value = "isPassive" }
}

Enemy.EffectFilterTypes = Types		-- for other addons


-- Custom effect filter types

--
-- Heal debuffs
-- Partial credits for heal debuffs data goes to majeric, the author of SquaredHDIndicator addon
-- Keep these as effect ability ids observed on active buffs/debuffs, not cast
-- action ids. Several old action ids looked plausible but never matched effects.
--
local HealDebuffsAbilityIds =
{
	In =
	{
		Destr =
		{
			-- Zealot
			[3075]  = 35,  -- Changer's Touch
			[8613]  = 50,  -- Windblock
			-- Squig Herder
			[1853]  = 50,  -- Rotten Arrer
			-- Witch Elf
			[9424]  = 50,  -- Black Lotus Blade
			-- Choppa
			[1773]  = 50,  -- No More Helpin' (2H)
			[1746]  = 50,  -- No More Helpin'
			[1803]  = 50,  -- Yer Goin Down!
			-- Shaman
			[1905]  = 50,  -- Gork's Barbs
			-- Marauder
			[8401]  = 50,  -- Tainted Claw
			-- Disciple of Khaine
			[32124] = 50,  -- Lacerate (Curse of Khaine tactic)
			-- weapon proc
			[10717] = 25   -- Guile
		},

		Order =
		{
			-- Warrior Priest
			[8270] = 50,  -- Absence of Faith
			-- Slayer
			[1434] = 50,  -- Deep Wound
			[1501] = 50,  -- Looks Like a Challenge
			-- Bright Wizard
			[3569] = 50,  -- Playing with Fire
			[8184] = 50,  -- Playing with Fire
			-- Witch Hunter
			[8112] = 50,  -- Punish the False
			-- Rune Priest
			[1633] = 35,  -- Rune of Nullification
			[3393] = 35,  -- Rune of Nullification
			-- Archmage
			[3915] = 50,  -- Scatter the Winds
			[9247] = 50,  -- Scatter the Winds
			-- Shadow Warrior
			[9109] = 50,  -- Shadow Sting
			-- weapon proc
			[10717] = 25   -- Guile
		}
	},
	Out =
	{
		Destr =
		{
			-- Witch Elf
			[3598] = 50, 			-- Kiss of Death
			[3811] = 50, 			-- Kiss of Death
			[9407] = 50, 			-- Kiss of Death
			[20263] = 50, 			-- Kiss of Death
			-- Blackguard
			[3372] = 50, 			-- Mind Killer
			[9317] = 50 			-- Mind Killer
		},

		Order =
		{
			-- Iron Breaker
			[1410] = 50,			-- Punishing Knock
			[3166] = 50,			-- Punishing Knock
			[3469] = 50,			-- Punishing Knock

			-- Witch Hunter
			[3002] = 50, 			-- Blessed Bullets of Confession
			[3784] = 50, 			-- Blessed Bullets of Confession
			[8099] = 50, 			-- Blessed Bullets of Confession

			-- Knight of the blazing sun
			[3493] = 25, 			-- Now's Our Chance!
			[8036] = 25, 			-- Now's Our Chance!

			-- White Lion
			[9191] = 50 			-- Thin the Herd
		}
	}
}

Enemy.HealDebuffsAbilityIds = HealDebuffsAbilityIds		-- for external usage

local HealDebuffIn = {}
local HealDebuffOut = {}

Types["healDebuffIn50"] =
{
	text = L"incoming heal debuff 50%",
	value = "healDebuffIn50",

	IsMatch = function (effect)
		return HealDebuffIn[effect.abilityId] == 50
	end
}

Types["healDebuffIn25"] =
{
	text = L"incoming heal debuff 25%",
	value = "healDebuffIn25",

	IsMatch = function (effect)
		return HealDebuffIn[effect.abilityId] == 25
	end
}

Types["healDebuffIn35"] =
{
	text = L"incoming heal debuff 35%",
	value = "healDebuffIn35",

	IsMatch = function (effect)
		return HealDebuffIn[effect.abilityId] == 35
	end
}

Types["healDebuffIn"] =
{
	text = L"incoming heal debuff",
	value = "healDebuffIn",

	IsMatch = function (effect)
		return HealDebuffIn[effect.abilityId] ~= nil
	end
}

Types["healDebuffOut50"] =
{
	text = L"outgoing heal debuff 50%",
	value = "healDebuffOut50",

	IsMatch = function (effect)
		return HealDebuffOut[effect.abilityId] == 50
	end
}

Types["healDebuffOut25"] =
{
	text = L"outgoing heal debuff 25%",
	value = "healDebuffOut25",

	IsMatch = function (effect)
		return HealDebuffOut[effect.abilityId] == 25
	end
}

Types["healDebuffOut"] =
{
	text = L"outgoing heal debuff",
	value = "healDebuffOut",

	IsMatch = function (effect)
		return HealDebuffOut[effect.abilityId] ~= nil
	end
}


--
-- Stagger
-- These are effect ability ids observed on stagger debuffs. Avoid adding older
-- action ids here unless they are verified as active effect ids.
--
local StaggerAbilityIds =
{
	Destr =
	{
		-- Chosen
		[3031] = true,	-- Quake

		-- DoK
		[3707] = true,	-- Universal Confusion

		-- Magus
		[3167] = true,	-- Detonation (Daemonic Infestation)

		-- Witch Elf
		[3032] = true,	-- Agile Escape

		-- Zealot
		[3027] = true,	-- Aethyric Shock

		-- Sorcerer
		[3168] = true	-- Scintillating Energy
	},
	Order =
	{
		-- Engineer
		[3034] = true,	-- Detonation (Land Mine)

		-- KotBS
		[3030] = true,	-- Heaven's Fury

		-- Rune Priest
		[3028] = true,	-- Rune of Binding

		-- Shadow Warrior
		[3029] = true,	-- Instill Fear

		-- Warrior Priest
		[3035] = true,	-- Penance

		-- Witch Hunter
		[3033] = true	-- Declare Anathema
	}
}

Enemy.StaggerAbilityIds = StaggerAbilityIds		-- for external usage

local Staggers = {}

Types["stagger"] =
{
	text = L"stagger",
	value = "stagger",

	IsMatch = function (effect)
		return Staggers[effect.abilityId] == true
	end
}


--
-- Guard
--
local GuardAbilityIds =
{
	[1008] = true,	-- Guard
	[1363] = true,	-- Guard
	[8013] = true,	-- Guard
	[8325] = true,	-- Guard
	[9008] = true,	-- Guard
	[9325] = true,	-- Guard

	[1674] = true	-- Save Da Runts
}

Enemy.GuardAbilityIds = GuardAbilityIds		-- for external usage

Types["guard"] =
{
	text = L"guard",
	value = "guard",

	IsMatch = function (effect)
		return GuardAbilityIds[effect.abilityId] == true
	end
}


--
-- Polymorphed
--
local PolymorphedAbilityIds =
{
	[24533] = true,		-- Champion of Tchar'zanek
	[24534] = true,		-- Champion of Karl Franz
	[24535] = true,		-- Champion Buff
	[24543] = true,		-- Champion Buff Applied
	[24544] = true,		-- Champion Buff - 1 - Tank
	[24545] = true,		-- Champion Buff - 1 - DPS Melee
	[24546] = true,		-- Champion Buff - 1 - DPS Range
	[24547] = true,		-- Champion Buff - 1 - Healer
	[24548] = true,		-- Champion Buff - 2 - Tank
	[24549] = true,		-- Champion Buff - 2 - DPS Melee
	[24550] = true,		-- Champion Buff - 2 - DPS Range
	[24551] = true,		-- Champion Buff - 2 - Healer

	[24561] = true,		-- Skaven Skirmisher
	[24855] = true,		-- Skaven Play-as-Monster
}

Enemy.PolymorphedAbilityIds = PolymorphedAbilityIds		-- for external usage


--------------------------------------------------------------- Helper functions

function Enemy._GroupsInitializeCustomEffectFilters ()

	if (GameData.Player.realm == GameData.Realm.ORDER)
	then
		HealDebuffIn = HealDebuffsAbilityIds.In.Destr
		HealDebuffOut = HealDebuffsAbilityIds.Out.Destr
		Staggers = StaggerAbilityIds.Destr
	else
		HealDebuffIn = HealDebuffsAbilityIds.In.Order
		HealDebuffOut = HealDebuffsAbilityIds.Out.Order
		Staggers = StaggerAbilityIds.Order
	end

	Enemy.TriggerEvent ("GroupsInitializeCustomEffectFilters", Types)
end


--------------------------------------------------------------- EnemyEffectFilter class
EnemyEffectFilter = {}
EnemyEffectFilter.__index = EnemyEffectFilter


function EnemyEffectFilter.New (data)
	local obj = {}
	setmetatable (obj, EnemyEffectFilter)

	-- defaults
	obj.filterName = nil
	obj.name = nil
	obj.nameMatch = 1
	obj.description = nil
	obj.descriptionMatch = 2
	obj.abilityIds = nil
	obj.typeMatch = 1
	obj.type = nil
	obj.durationType = 1
	obj.durationMin = nil
	obj.durationMax = nil
	obj.stackCount = nil
	obj.castedByMe = 1

	if (data)
	then
		obj:Load (data)
	end

	return obj
end

local function NormalizeFilterText (value)
	if (value == nil) then return nil end
	if (type (value) ~= "string") then value = tostring (value) end
	if (value == nil or value == "") then return nil end
	return string_lower (value)
end

local function GetEffectName (effect)
	local value = effect._enemyName
	if (value and type (value) == "string") then return value end

	-- Preserve career-suffix stripping from the removed eager normalization.
	value = NormalizeFilterText (value or FixString (effect.name))
	effect._enemyName = value
	return value or ""
end

local function GetEffectText (effect)
	local value = effect._enemyEffectText
	if (value and type (value) == "string") then return value end

	value = NormalizeFilterText (value or FixString (effect.effectText))
	effect._enemyEffectText = value
	return value or ""
end


local function EnemyEffectFilterBuildMatcher (filter)
	local abilityIdsHash = filter.abilityIdsHash
	local filterType = filter.type
	local filterTypeData = filter._enemyFilterTypeData
	local filterTypeIsPositive = filter._enemyFilterTypeIsPositive
	local checksDuration = filter._enemyFilterChecksDuration
	local checksInitialDuration = filter._enemyFilterChecksInitialDuration
	local checksCurrentDuration = filter._enemyFilterChecksCurrentDuration
	local checksPermanentDuration = filter._enemyFilterChecksPermanentDuration
	local durationMin = filter._enemyFilterDurationMin
	local durationMax = filter._enemyFilterDurationMax
	local stackCount = filter._enemyFilterStackCount
	local checksCaster = filter._enemyFilterChecksCaster
	local requiresPlayerCaster = filter._enemyFilterRequiresPlayerCaster
	local requiresOtherCaster = filter._enemyFilterRequiresOtherCaster
	local hasName = filter._enemyFilterHasName
	local filterName = filter.name
	local nameMatch = filter._enemyFilterNameMatch
	local hasDescription = filter._enemyFilterHasDescription
	local filterDesc = filter.description
	local descriptionMatch = filter._enemyFilterDescriptionMatch

	return function (_filter, effect)
		if (abilityIdsHash and abilityIdsHash[effect.abilityId] ~= true) then return false end

		if (filterType)
		then
			if (not filterTypeData.IsMatch)
			then
				if (effect[filterTypeData.value] ~= filterTypeIsPositive) then return false end
			else
				if (filterTypeData.IsMatch (effect) ~= filterTypeIsPositive) then return false end
			end
		end

		if (checksDuration)
		then
			if (checksInitialDuration)
			then
				if (effect._enemyDuration <= 0) then return false end
				if (durationMin and effect._enemyDuration < durationMin) then return false end
				if (durationMax and effect._enemyDuration > durationMax) then return false end

			elseif (checksCurrentDuration)
			then
				if (effect.duration <= 0) then return false end
				if (durationMin and effect.duration < durationMin) then return false end
				if (durationMax and effect.duration > durationMax) then return false end

			elseif (checksPermanentDuration)
			then
				if (not effect.permanentUntilDispelled) then return false end
			end
		end

		if (stackCount and effect.stackCount ~= stackCount)
		then
			return false
		end

		if (checksCaster)
		then
			if (not (requiresPlayerCaster and effect.castByPlayer)
				and
				not (requiresOtherCaster and not effect.castByPlayer))
			then return false end
		end

		if (hasName)
		then
			local effectName = GetEffectName (effect)
			if (nameMatch == 1)
			then
				if (effectName ~= filterName) then return false end
			elseif (nameMatch == 2)
			then
				if (not string_find (effectName, filterName, 1, true)) then return false end
			elseif (nameMatch == 3)
			then
				if (not string_match (effectName, filterName)) then return false end
			end
		end

		if (hasDescription)
		then
			local effectText = GetEffectText (effect)
			if (descriptionMatch == 1)
			then
				if (effectText ~= filterDesc) then return false end
			elseif (descriptionMatch == 2)
			then
				if (not string_find (effectText, filterDesc, 1, true)) then return false end
			elseif (descriptionMatch == 3)
			then
				if (not string_match (effectText, filterDesc)) then return false end
			end
		end

		return true
	end
end

-- Cache immutable parsing results only. Every filter still receives its own
-- public hash and matcher, including on reload. Preserve numeric conversion on
-- every load: LuaPlus may have captured a custom tonumber before this module.
local ConstructorSources = Enemy._constructorSources or {}
local AbilityIdParseHelpers = { Split = ConstructorSources.Split, trim = ConstructorSources.trim,
    tonumber = tonumber, strings = ConstructorSources.strings }
EnemyEffectFilter._abilityIdParseHelpers = AbilityIdParseHelpers
local AbilityIdTokens, AbilityIdTokenKeys, AbilityIdTokenCursor = {}, {}, 1
local AbilityIdTokenLimit = 128

local function AbilityIdToNumber (token, radix)
    local abilityId = tonumber (token, radix)
    if (abilityId == nil and type (token) ~= "string") then
        abilityId = tonumber (tostring (token), radix)
    end
    return abilityId
end

local function IdStringMethodsUnchanged (value, valueType)
    local source = AbilityIdParseHelpers.strings and AbilityIdParseHelpers.strings[valueType]
    if (not source or getmetatable (value) ~= source.metatable
        or (type (source.metatable) == "table" and rawget (source.metatable, "__index") ~= source.index))
    then return false end
    if (valueType == "string") then
        return string == source.library and string.len == source.len and string.find == source.find
            and string.sub == source.sub and string.match == source.match
    end
    return value.len == source.len and value.find == source.find and value.sub == source.sub and value.match == source.match
end

local function CanCacheAbilityIds (filter, value)
    local valueType = type (value)
    return (valueType == "string" or valueType == "wstring")
        and getmetatable (filter) == EnemyEffectFilter and getmetatable (EnemyEffectFilter) == nil
        and EnemyEffectFilter.__index == EnemyEffectFilter and rawget (EnemyEffectFilter, "__newindex") == nil
        and Enemy.Split == AbilityIdParseHelpers.Split and Enemy.trim == AbilityIdParseHelpers.trim
        and _G.tonumber == AbilityIdParseHelpers.tonumber
        and IdStringMethodsUnchanged (value, valueType)
end

local function CacheAbilityIdTokens (value, tokens)
    local oldKey = AbilityIdTokenKeys[AbilityIdTokenCursor]
    if (oldKey ~= nil) then AbilityIdTokens[oldKey] = nil end
    AbilityIdTokenKeys[AbilityIdTokenCursor] = value
    AbilityIdTokens[value] = tokens
    AbilityIdTokenCursor = AbilityIdTokenCursor % AbilityIdTokenLimit + 1
end


function EnemyEffectFilter:Load (data)

	self.filterName = data.filterName
	self.name = data.name
	self.nameMatch = data.nameMatch
	self.description = data.description
	self.descriptionMatch = data.descriptionMatch
	self.abilityIds = data.abilityIds
	self.typeMatch = data.typeMatch
	self.type = data.type
	self.durationType = data.durationType
	self.durationMin = data.durationMin
	self.durationMax = data.durationMax
	self.stackCount = data.stackCount
	self.castedByMe = data.castedByMe

	self.name = NormalizeFilterText (self.name)
	self.description = NormalizeFilterText (self.description)

	-- Cache derived match flags here so heavy effect storms do not reinterpret
	-- the same filter settings for every candidate effect row.
	self._enemyFilterTypeData = self.type and Types[self.type] or nil
	self._enemyFilterTypeIsPositive = self.typeMatch == 1
	self._enemyFilterChecksDuration = self.durationType ~= 1
	self._enemyFilterChecksInitialDuration = self.durationType == 2
	self._enemyFilterChecksCurrentDuration = self.durationType == 4
	self._enemyFilterChecksPermanentDuration = self._enemyFilterChecksDuration and not self._enemyFilterChecksInitialDuration and not self._enemyFilterChecksCurrentDuration
	self._enemyFilterDurationMin = self.durationMin
	self._enemyFilterDurationMax = self.durationMax
	self._enemyFilterStackCount = self.stackCount
	self._enemyFilterChecksCaster = self.castedByMe ~= 1
	self._enemyFilterRequiresPlayerCaster = self.castedByMe == 2
	self._enemyFilterRequiresOtherCaster = self.castedByMe == 3
	self._enemyFilterHasName = self.name ~= nil and self.name ~= ""
	self._enemyFilterNameMatch = self.nameMatch
	self._enemyFilterHasDescription = self.description ~= nil and self.description ~= ""
	self._enemyFilterDescriptionMatch = self.descriptionMatch

	self.hasDurationLimit = (
								(self.durationType == 2 or self.durationType == 4)
								and
								(self.durationMin ~= nil or self.durationMax ~= nil)
							)

	if (self.abilityIds)
	then
		self.abilityIdsHash = {}

		local has_ids = false
        local value = self.abilityIds
        local canCache = CanCacheAbilityIds (self, value)
        local tokens = canCache and AbilityIdTokens[value]
        if (tokens) then
            for _, token in ipairs (tokens) do
                local abilityId = AbilityIdToNumber (token)
                if (abilityId ~= nil) then
                    self.abilityIdsHash[abilityId] = true
                    has_ids = true
                end
            end
        else
            local parsed = canCache and {}
            for _, v in ipairs (Enemy.Split (value, L",", true)) do
                if (parsed) then
                    local token = Enemy.trim (v)
                    local abilityId = AbilityIdToNumber (token)
                    if (abilityId ~= nil) then
                        self.abilityIdsHash[abilityId] = true
                        parsed[#parsed + 1] = token
                        has_ids = true
                    end
                else
                    local token, radix = Enemy.trim (v)
                    local abilityId = AbilityIdToNumber (token, radix)
                    if (abilityId ~= nil) then
                        self.abilityIdsHash[abilityId] = true
                        has_ids = true
                    end
                end
            end
            if (parsed) then CacheAbilityIdTokens (value, parsed) end
        end

		if (not has_ids)
		then
			self.abilityIdsHash = nil
		end
	else
		self.abilityIdsHash = nil
	end

	self.IsMatch = EnemyEffectFilterBuildMatcher (self)
    self._windowReuseMatcher = self.IsMatch
end


function EnemyEffectFilter:Edit (onOkCallback)

	Enemy.GroupsUI_EffectFilterDialog_Open (self, function (old, new)

		old:Load (new)

		if (onOkCallback)
		then
			onOkCallback (self)
		end
	end)
end


function EnemyEffectFilter:IsMatch (effect)
	local match = EnemyEffectFilterBuildMatcher (self)
	self.IsMatch = match
    self._windowReuseMatcher = match
	return match (self, effect)
end

----------------------------------------------------------------- UI: Effect filter dialog
local effect_filter_dlg =
{
	isInitialized = false
}

function Enemy.GroupsUI_EffectFilterDialog_IsOpen ()
	return WindowGetShowing ("EnemyEffectFilterDialog")
end


function Enemy.GroupsUI_EffectFilterDialog_Hide ()
	WindowSetShowing ("EnemyEffectFilterDialog", false)
end


function Enemy.GroupsUI_EffectFilterDialog_Open (data, onOkCallback)

	if (not effect_filter_dlg.isInitialized)
	then
		-- initialize dialog UI
		LabelSetText ("EnemyEffectFilterDialogTitleBarText", L"Effect filter")
		ButtonSetText ("EnemyEffectFilterDialogOkButton", L"OK")
		ButtonSetText ("EnemyEffectFilterDialogCancelButton", L"Cancel")

		LabelSetText ("EnemyEffectFilterDialogFilterNameLabel", L"Filter name")

		LabelSetText ("EnemyEffectFilterDialogNameLabel", L"Effect name")
		ComboBoxAddMenuItem ("EnemyEffectFilterDialogNameMatch", L"exact")
		ComboBoxAddMenuItem ("EnemyEffectFilterDialogNameMatch", L"substring")
		ComboBoxAddMenuItem ("EnemyEffectFilterDialogNameMatch", L"regexp")

		LabelSetText ("EnemyEffectFilterDialogDescriptionLabel", L"Effect description")
		ComboBoxAddMenuItem ("EnemyEffectFilterDialogDescriptionMatch", L"exact")
		ComboBoxAddMenuItem ("EnemyEffectFilterDialogDescriptionMatch", L"substring")
		ComboBoxAddMenuItem ("EnemyEffectFilterDialogDescriptionMatch", L"regexp")

		LabelSetText ("EnemyEffectFilterDialogAbilityIdsLabel", L"Ability ids")

		ComboBoxAddMenuItem ("EnemyEffectFilterDialogTypeMatch", L"Type is")
		ComboBoxAddMenuItem ("EnemyEffectFilterDialogTypeMatch", L"Type is not")


		effect_filter_dlg.typeComboBoxValues = Enemy.UI_PrepareComboBoxValuesArray (Types,
				function (_k, v)
				return { text = v.text, value = v.value }
			end,
			function (a, b)
				return a.text < b.text
			end)

		tinsert (effect_filter_dlg.typeComboBoxValues, 1, { text= L"any", value = nil })

		for _, v in pairs (effect_filter_dlg.typeComboBoxValues)
		do
			ComboBoxAddMenuItem ("EnemyEffectFilterDialogType", v.text)
		end


		LabelSetText ("EnemyEffectFilterDialogDurationLabel", L"Duration")
		ComboBoxAddMenuItem ("EnemyEffectFilterDialogDurationType", L"doesn't matter")
		ComboBoxAddMenuItem ("EnemyEffectFilterDialogDurationType", L"has initial duration")
		ComboBoxAddMenuItem ("EnemyEffectFilterDialogDurationType", L"permanent")
		ComboBoxAddMenuItem ("EnemyEffectFilterDialogDurationType", L"has current duration")
		LabelSetText ("EnemyEffectFilterDialogDurationLabel2", L" ... ")

		LabelSetText ("EnemyEffectFilterDialogStackCountLabel", L"Stack count")

		LabelSetText ("EnemyEffectFilterDialogCastedByMeLabel", L"Casted by me")
		ComboBoxAddMenuItem ("EnemyEffectFilterDialogCastedByMe", L"doesn't matter")
		ComboBoxAddMenuItem ("EnemyEffectFilterDialogCastedByMe", L"yes")
		ComboBoxAddMenuItem ("EnemyEffectFilterDialogCastedByMe", L"no")

		effect_filter_dlg.isInitialized = true
	end

	-- proceed parameters
	effect_filter_dlg.oldData = data
	effect_filter_dlg.data = EnemyEffectFilter.New (data)
	effect_filter_dlg.onOkCallback = onOkCallback

	-- fill form
	TextEditBoxSetText ("EnemyEffectFilterDialogFilterName", Enemy.isNil (effect_filter_dlg.data.filterName, L""))

	TextEditBoxSetText ("EnemyEffectFilterDialogName", Enemy.isNil (effect_filter_dlg.data.name, L""))
	ComboBoxSetSelectedMenuItem ("EnemyEffectFilterDialogNameMatch", effect_filter_dlg.data.nameMatch)

	TextEditBoxSetText ("EnemyEffectFilterDialogDescription", Enemy.isNil (effect_filter_dlg.data.description, L""))
	ComboBoxSetSelectedMenuItem ("EnemyEffectFilterDialogDescriptionMatch", effect_filter_dlg.data.descriptionMatch)

	TextEditBoxSetText ("EnemyEffectFilterDialogAbilityIds", Enemy.isNil (effect_filter_dlg.data.abilityIds, L""))

	ComboBoxSetSelectedMenuItem ("EnemyEffectFilterDialogTypeMatch", effect_filter_dlg.data.typeMatch)

	Enemy.UI_SetComboBoxValueByValuesArray ("EnemyEffectFilterDialogType", effect_filter_dlg.typeComboBoxValues, function (_k, v)
		return (v.value == effect_filter_dlg.data.type)
	end)

	ComboBoxSetSelectedMenuItem ("EnemyEffectFilterDialogDurationType", effect_filter_dlg.data.durationType)
	Enemy.GroupsUI_EffectFilterDialog_OnDurationTypeSelChanged ()
	TextEditBoxSetText ("EnemyEffectFilterDialogDurationMin", Enemy.toWStringOrEmpty (effect_filter_dlg.data.durationMin))
	TextEditBoxSetText ("EnemyEffectFilterDialogDurationMax", Enemy.toWStringOrEmpty (effect_filter_dlg.data.durationMax))

	TextEditBoxSetText ("EnemyEffectFilterDialogStackCount", Enemy.toWStringOrEmpty (effect_filter_dlg.data.stackCount))

	ComboBoxSetSelectedMenuItem ("EnemyEffectFilterDialogCastedByMe", effect_filter_dlg.data.castedByMe)


	WindowSetShowing ("EnemyEffectFilterDialog", true)
end


function Enemy.GroupsUI_EffectFilterDialog_OnDurationTypeSelChanged ()
	local val = ComboBoxGetSelectedMenuItem ("EnemyEffectFilterDialogDurationType")
	WindowSetShowing ("EnemyEffectFilterDialogDurationMin", val == 2 or val == 4)
	WindowSetShowing ("EnemyEffectFilterDialogDurationMax", val == 2 or val == 4)
	WindowSetShowing ("EnemyEffectFilterDialogDurationLabel2", val == 2 or val == 4)
end

function Enemy.GroupsUI_EffectFilterDialog_OnAbilityIdsMouseOver ()

	Tooltips.CreateTextOnlyTooltip (SystemData.MouseOverWindow.name)
	Tooltips.SetTooltipText (1, 1, L"To get ability ids type")
	Tooltips.SetTooltipText (2, 1, L"/script Enemy.GetAbilityIds(\"Ability name\")")
	Tooltips.AnchorTooltip (Tooltips.ANCHOR_CURSOR)
	Tooltips.Finalize()
end


function Enemy.GroupsUI_EffectFilterDialog_Ok ()

	if (not Enemy.GroupsUI_EffectFilterDialog_IsOpen ()) then return end

	-- get data from form
	effect_filter_dlg.data.filterName = Enemy.isEmpty (TextEditBoxGetText ("EnemyEffectFilterDialogFilterName"), L"")

	if (not Enemy.LogicalExpressionIsValidFunctionName (Enemy.toString (effect_filter_dlg.data.filterName)))
	then
		DialogManager.MakeOneButtonDialog (L"Invalid name specified. Name should not contain any spaces and can not be 'and', 'or', 'not' keyword.", L"Ok")
		return
	end

	effect_filter_dlg.data.name = Enemy.isEmpty (TextEditBoxGetText ("EnemyEffectFilterDialogName"), nil)
	effect_filter_dlg.data.nameMatch = ComboBoxGetSelectedMenuItem ("EnemyEffectFilterDialogNameMatch")

	effect_filter_dlg.data.description = Enemy.isEmpty (TextEditBoxGetText ("EnemyEffectFilterDialogDescription"))
	effect_filter_dlg.data.descriptionMatch = ComboBoxGetSelectedMenuItem ("EnemyEffectFilterDialogDescriptionMatch")

	effect_filter_dlg.data.abilityIds = Enemy.isEmpty (TextEditBoxGetText ("EnemyEffectFilterDialogAbilityIds"))

	effect_filter_dlg.data.typeMatch = ComboBoxGetSelectedMenuItem ("EnemyEffectFilterDialogTypeMatch")

	effect_filter_dlg.data.type = effect_filter_dlg.typeComboBoxValues[ComboBoxGetSelectedMenuItem ("EnemyEffectFilterDialogType")].value

	effect_filter_dlg.data.durationType = ComboBoxGetSelectedMenuItem ("EnemyEffectFilterDialogDurationType")
	effect_filter_dlg.data.durationMin = Enemy.clamp (0, 9999, Enemy.ConvertToFloat (TextEditBoxGetText ("EnemyEffectFilterDialogDurationMin")))
	effect_filter_dlg.data.durationMax = Enemy.clamp (0, 9999, Enemy.ConvertToFloat (TextEditBoxGetText ("EnemyEffectFilterDialogDurationMax")))

	effect_filter_dlg.data.stackCount = Enemy.clamp (0, 100, Enemy.ConvertToInteger (TextEditBoxGetText ("EnemyEffectFilterDialogStackCount")))

	effect_filter_dlg.data.castedByMe = ComboBoxGetSelectedMenuItem ("EnemyEffectFilterDialogCastedByMe")

	if (effect_filter_dlg.onOkCallback)
	then
		effect_filter_dlg.onOkCallback (effect_filter_dlg.oldData, effect_filter_dlg.data)
	end

	Enemy.GroupsUI_EffectFilterDialog_Hide ()
end

if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.RegisterFilterTypes (Types) end

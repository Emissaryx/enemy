local Enemy = Enemy
local tinsert = table.insert
local tsort = table.sort
local ipairs = ipairs
local pairs = pairs
local mfloor = math.floor
local tonumber = tonumber
local type = type
local pcall = pcall
local InterfaceCore = InterfaceCore

Enemy.UnitFramePlayerUpdateFilters =
{
	Distance =
	{
		Parts = {}
	}
}


local function GetTooltipLevelText (player)

	local level_text = Enemy.toWStringOrEmpty (player.level)..L" lvl"

	if (
			type (player) ~= "table"
			or
			player.name == nil
			or
			player.name == L""
		)
	then
		return level_text
	end

	if (type (AutoBand) ~= "table" or type (AutoBand.get_realm_rank_lookup_result) ~= "function")
	then
		return level_text
	end

	local ok, lookup = pcall (AutoBand.get_realm_rank_lookup_result, player.name, { allow_cache_fallback = true })
	if (not ok or type (lookup) ~= "table")
	then
		return level_text
	end

	local rr = tonumber (lookup.rr)
	if (rr == nil)
	then
		return level_text
	end

	rr = mfloor (rr)
	if (rr < 0)
	then
		return level_text
	end

	return Enemy.toWStringOrEmpty (player.level)..L"/"..towstring (rr)
end

local function GetPlayerDisplayState (player)
    if (not player.isOnline) then return Enemy.PlayerStates.Offline end
    if (player.hp == 0) then return Enemy.PlayerStates.Dead end
    if (player.isDistant or player.isLOS) then return Enemy.PlayerStates.Distant end
    return Enemy.PlayerStates.Normal
end

local function StorePlayerDisplayState (frame, player)
	frame.playerDisplayState = GetPlayerDisplayState (player)
	frame.playerPartCareer = player.career
	frame.playerHP = player.hp
	frame.playerAP = player.ap
	frame.playerMorale = player.morale
	frame.playerLevel = player.level
	frame.playerIsOnline = player.isOnline
	frame.playerIsDistant = player.isDistant
	frame.playerIsLOS = player.isLOS
	frame.playerIsGroupLeader = player.isGroupLeader
	frame.playerIsSelected = player.isSelected
	frame.playerIsInPlayerGroup = player.isInPlayerGroup
	frame.playerIsSelf = player.isSelf
end

local function HasPlayerDisplayStateChanged (frame, player)
	if (
		frame.playerPartCareer ~= player.career
		or frame.playerHP ~= player.hp
		or frame.playerAP ~= player.ap
		or frame.playerMorale ~= player.morale
		or frame.playerLevel ~= player.level
		or frame.playerIsGroupLeader ~= player.isGroupLeader
		or frame.playerIsSelected ~= player.isSelected
		or frame.playerIsInPlayerGroup ~= player.isInPlayerGroup
		or frame.playerIsSelf ~= player.isSelf)
    then
        return true
    end

    if (frame.playerIsOnline == player.isOnline
        and frame.playerIsDistant == player.isDistant
        and frame.playerIsLOS == player.isLOS)
    then
        return false
    end
    if (frame.playerDisplayState ~= GetPlayerDisplayState (player)) then return true end

    -- Only built-in writers consume the combined display state. Extensions
    -- may use the raw flags, including callbacks replaced after construction.
    local types = Enemy.unitFramesParts
    if (not types._displayStateHelpers) then return true end
    for key, callback in pairs (types._displayStateHelpers) do
        if (Enemy[key] ~= callback) then return true end
    end
    for _, part in ipairs (frame.parts)
    do
        if (not types._displayStateWriters
            or not part._type
            or part._type.key ~= part.type
            or types._displayStateWriters[part._type] ~= part._type.OnUpdate
            or part.Update ~= types._displayStatePartUpdate)
        then
            return true
        end
        -- Career overlays reconcile against the root's previous visibility.
        -- A masked flag change must still deliver that pending reconciliation.
        local t = part._t
        if (part.type == "careerIcon" and t and t.cache and t.altIconWindowName
            and t.cache.altIconShowing ~= (t.cache.altSpecIcon ~= nil and t._isShowing == true))
        then
            return true
        end
    end
    -- Advance only masked transitions; unchanged packets remain write-free.
    frame.playerIsOnline = player.isOnline
    frame.playerIsDistant = player.isDistant
    frame.playerIsLOS = player.isLOS
    return false
end

local function GetVisualPartLayer (data)
	local part_data = data and (data.data or data)
	if (not part_data) then return 0 end

	return tonumber (part_data.layer) or 0
end

local function GetSortedVisualPartSettings (settings)
	local parts = {}

	for index, data in ipairs (settings.unitFramesParts)
	do
		local layer = GetVisualPartLayer (data)
		tinsert (parts,
		{
			index = index,
			layer = layer,
			data = data
		})

		if (layer == Window.Layers.POPUP)
		then
			parts.hasPopupLayer = true
		end
	end

	tsort (parts, function (a, b)
		if (a.layer == b.layer) then return a.index < b.index end
		return a.layer < b.layer
	end)

	return parts
end

Enemy.UnitFramesGetSortedVisualPartSettings = GetSortedVisualPartSettings


--------------------------------------------------------------- EnemyUnitFrame class
EnemyUnitFrame = {}
EnemyUnitFrame.__index = EnemyUnitFrame


function EnemyUnitFrame.New (groupIndex, index)
    -- Reserve room for runtime fields without creating visible keys. Alternating
    -- effect-batch fields on a full hash otherwise reallocates it every packet.
    local obj = {
        groupIndex = nil,
        index = nil,
        isEnabled = nil,
        isSelected = nil,
        parts = nil,
        partsByType = nil,
        effectsIndicators = nil,
        clickCastings = nil,
        playerName = nil,
        playerCareer = nil,
        playerGroupIndex = nil,
        playerPartCareer = nil,
        playerHP = nil,
        playerAP = nil,
        playerMorale = nil,
        playerLevel = nil,
        playerIsOnline = nil,
        playerIsDistant = nil,
        playerIsLOS = nil,
        playerIsGroupLeader = nil,
        playerIsSelected = nil,
        playerIsInPlayerGroup = nil,
        playerIsSelf = nil,
        playerDisplayState = nil,
        settings = nil,
        windowName = nil,
        sortedUnitFramesParts = nil,
        hasPopupUnitFrameParts = nil,
        forcePlayerChanged = nil,
        _retainedObjects = nil,
        _retainedForceRefresh = nil,
        _effectsUpdateGeneration = nil,
        _updatingEffects = nil,
        _effectsLayerShown = nil,
        _effectsUpdateIndicators = nil,
    }
	setmetatable (obj, EnemyUnitFrame)

	obj.groupIndex = groupIndex
	obj.index = index

	obj.isEnabled = false
	obj.isSelected = false

	obj.parts = {}
	obj.partsByType = {}
	obj.effectsIndicators = {}
	obj.clickCastings = {}

	return obj
end


function EnemyUnitFrame:Reset (partial)

    if (partial and self._retainedObjects and not self._updatingEffects) then
        self._retainedForceRefresh = true
    else
        self._retainedObjects = nil
        self._retainedForceRefresh = nil
    end
    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Cancel (self) end
    self._effectsUpdateGeneration = (self._effectsUpdateGeneration or 0) + 1
    self._updatingEffects = nil
    self._effectsLayerShown = nil
    self._effectsUpdateIndicators = nil

	self.playerCareer = nil
	self.playerDisplayState = nil
	self.playerPartCareer = nil
	self.playerHP = nil
	self.playerAP = nil
	self.playerName = nil
	self.playerLevel = nil
	self.playerIsDistant = nil
	self.playerMorale = nil
	self.playerIsOnline = nil
	self.playerIsLOS = nil
	self.playerIsGroupLeader = nil
	self.playerIsSelected = nil
	self.playerIsInPlayerGroup = nil
	self.playerIsSelf = nil
	self.playerGroupIndex = nil

	if (not partial)
	then
		self:_RemoveAllParts ()
		self:_RemoveAllEffectsIndicators ()
		self:_RemoveAllClickCastings ()
	end
end


function EnemyUnitFrame:Remove ()

    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Cancel (self) end

	self:_RemoveAllParts ()
	self:_RemoveAllEffectsIndicators ()
	self:_RemoveAllClickCastings ()

	if (self.windowName)
	then
		DestroyWindow (self.windowName)
		self.windowName = nil
	end

	self:BoundingBoxSetShowing (false)
	self:Reset ()
end


function EnemyUnitFrame:BoundingBoxSetShowing (show)

	if (self._boundingBoxWindowName)
	then
		if (DoesWindowExist (self._boundingBoxWindowName)) then DestroyWindow (self._boundingBoxWindowName) end
		self._boundingBoxWindowName = nil
	end

	local global_scale = InterfaceCore.GetScale ()

	if (self.isEnabled and show)
	then
		self._boundingBoxWindowName = "BoundingBox"..Enemy.NewId ()
		CreateWindowFromTemplate (self._boundingBoxWindowName, "EnemyRectangleTemplate", self.windowName)
		WindowAddAnchor (self._boundingBoxWindowName, "topleft", self.windowName, "topleft", 0, 0)
		WindowAddAnchor (self._boundingBoxWindowName, "bottomright", self.windowName, "bottomright", 0, 0)
		WindowSetLayer (self._boundingBoxWindowName, Window.Layers.OVERLAY)
		WindowSetScale (self.windowName, self.settings.unitFramesScale * global_scale)
	end
end


function EnemyUnitFrame:IsEnabled ()
	return self.isEnabled
end


function EnemyUnitFrame:Disable ()

	if (not self.windowName) then return end
	WindowSetShowing (self.windowName, false)

	self.isEnabled = false
	self:Reset ()
end


function EnemyUnitFrame:Enable ()

	if (not self.windowName) then return end
	WindowSetShowing (self.windowName, true)
	self.isEnabled = true
end


function EnemyUnitFrame:_ShowAllEffectsIndicators ()

	for _, effects_indicator in ipairs (self.effectsIndicators)
	do
		effects_indicator:Show ()
	end
end

function EnemyUnitFrame:_RemoveAllParts ()

	local parts = self.parts
	for _, v in ipairs (parts)
	do
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.BeforeRemove (v, "part", self) end
		v:Remove ()
        if (self.parts ~= parts) then return end
	end

	self.parts = {}
	self.partsByType = {}
end

function EnemyUnitFrame:_RefreshPopupPartLayers ()

	if (not self.hasPopupUnitFrameParts) then return end

	for _, part in ipairs (self.parts)
	do
		local t = part._t
		local layer = GetVisualPartLayer (part)
		if (t and t.windowName and layer == Window.Layers.POPUP)
		then
            if (part._type and part._type.OnLayerRefresh)
            then
                part._type.OnLayerRefresh (part)
            else
                -- Reassigning an unchanged layer may be a native no-op. Move
                -- through another layer without toggling visibility/animations.
                WindowSetLayer (t.windowName, Window.Layers.OVERLAY)
                WindowSetLayer (t.windowName, layer)
            end
		end
	end
end

function EnemyUnitFrame:_RemoveAllEffectsIndicators ()

	local indicators = self.effectsIndicators
	for _, v in ipairs (indicators)
	do
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.BeforeRemove (v, "indicator", self) end
		v:Remove ()
        if (self.effectsIndicators ~= indicators) then return end
	end

	self.effectsIndicators = {}
end

function EnemyUnitFrame:_RefreshEffectsIndicatorLayers (shownIndicator)

    if (self._updatingEffects)
    then
        -- UpdateEffects visits list order: remember only the first new show.
        self._effectsLayerShown = self._effectsLayerShown or shownIndicator
        return
    end

    local afterShown = false
    for _, indicator in ipairs (self.effectsIndicators)
    do
        if (afterShown)
        then
            if (indicator._isShowing and indicator.windowName)
            then
                WindowSetLayer (indicator.windowName, Window.Layers.OVERLAY)
                WindowSetLayer (indicator.windowName, Window.Layers.POPUP)
            end
        elseif (indicator == shownIndicator)
        then
            afterShown = true
        end
    end

    -- Keep the existing frame-part priority, and ignore standalone dialog previews.
    if (afterShown) then self:_RefreshPopupPartLayers () end
end

function EnemyUnitFrame:_RemoveAllClickCastings ()

	local clicks = self.clickCastings
	for _, v in ipairs (clicks)
	do
		v:Remove ()
        if (self.clickCastings ~= clicks) then return end
	end

	self.clickCastings = {}
end


function EnemyUnitFrame:_RecreateAllParts (player)

    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end
	self:_RemoveAllParts ()
    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end

	for _, entry in ipairs (self.sortedUnitFramesParts or GetSortedVisualPartSettings (self.settings))
	do
		if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end
		local data = entry.data
        if (EnemyUnitFramePart.CanSkipConstruction and EnemyUnitFramePart.CanSkipConstruction (data, player)) then continue end
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.BeforeConstruct (self, data, "part") end
		local obj = EnemyUnitFramePart.New (data)
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end

		if (not obj.isEnabled or not obj:CanMatch (player)) then continue end
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end

		tinsert (self.parts, obj)
		self.partsByType[obj.type] = self.partsByType[obj.type] or {}
		tinsert (self.partsByType[obj.type], obj)
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Track (self, obj, "part", entry.index, data) end
		obj:Bind (self)
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end
	end
end


function EnemyUnitFrame:_RecreateAllEffectsIndicators (player)

    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end
	self:_RemoveAllEffectsIndicators ()
    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end

    for index, data in ipairs (self.settings.effectsIndicators)
	do
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end
        if (EnemyEffectsIndicator.CanSkipConstruction and EnemyEffectsIndicator.CanSkipConstruction (data, player, self.settings.unitFramesTestMode)) then continue end
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.BeforeConstruct (self, data, "indicator") end
		local obj = EnemyEffectsIndicator.New (data)
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end

		if (not obj.isEnabled or (not self.settings.unitFramesTestMode and not obj:CanMatch (player))) then continue end
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end

		tinsert (self.effectsIndicators, obj)
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Track (self, obj, "indicator", index, data) end
		obj:Update (self)
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end
	end
end


function EnemyUnitFrame:_RecreateAllClickCastings (player)

    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end
	self:_RemoveAllClickCastings ()
    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end

	for _, data in pairs (self.settings.clickCastings)
	do
        if (EnemyClickCasting.CanSkipConstruction and EnemyClickCasting.CanSkipConstruction (data, player)) then continue end
		local obj = EnemyClickCasting.New (data)
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end

		if (not obj.isEnabled or not obj:CanMatch (player)) then continue end
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end

		tinsert (self.clickCastings, obj)
		obj:Update (self)
        if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Check (self) end
	end
end


function EnemyUnitFrame:ApplySettings (settings, sortedUnitFramesParts, preserveNative)

    self._retainedObjects = nil
    local keepParts = preserveNative and Enemy.UnitFrameWindowReuse
        and Enemy.UnitFrameWindowReuse.CanKeepSettings (self)
    if (preserveNative) then
        if (keepParts) then
            WindowSetShowing (self.windowName, false)
            self.isEnabled = false
            self:Reset (true)
        else
            self:Disable ()
        end
    end
    if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.Cancel (self) end

	self.settings = settings
	self.sortedUnitFramesParts = sortedUnitFramesParts or GetSortedVisualPartSettings (settings)
	self.hasPopupUnitFrameParts = self.sortedUnitFramesParts.hasPopupLayer == true

	if (not self.windowName)
	then
		self.windowName = "EnemyUnitFrame"..tostring (self.groupIndex).."_"..tostring (self.index)
		CreateWindowFromTemplate (self.windowName, "EnemyUnitFrame", "Root")

		self:Disable ()
	end

	local global_scale = InterfaceCore.GetScale ()

	WindowSetDimensions (self.windowName, self.settings.unitFramesSize[1], self.settings.unitFramesSize[2])
	WindowSetLayer (self.windowName, self.settings.unitFramesLayer)
	WindowSetScale (self.windowName, self.settings.unitFramesScale * global_scale)

    if (not keepParts) then
        self:_RemoveAllParts ()
        self:_RemoveAllEffectsIndicators ()
        self:_RemoveAllClickCastings ()
    end
	self.forcePlayerChanged = true
end


function EnemyUnitFrame:UpdatePosition ()

	if (not Enemy.unitFrames.positionMatrix or not self.windowName) then return end

	local pos_group = Enemy.unitFrames.positionMatrix[self.groupIndex]
	if (not pos_group) then return end

	local pos = pos_group[self.index]
	if (not pos) then return end

	WindowClearAnchors (self.windowName)
	WindowAddAnchor (self.windowName, "topleft", pos.anchorWindow.windowName, "topleft", mfloor (0.5 + pos.x), mfloor (0.5 + pos.y))
end


local function RebuildFrame (frame, player)
    frame:_RecreateAllParts (player)
    frame:_RecreateAllEffectsIndicators (player)
    frame:_RefreshPopupPartLayers ()
    frame:_RecreateAllClickCastings (player)
end

local function RebindRetainedFrame (frame, player)
    if (frame._retainedForceRefresh) then Enemy.UnitFrameObjectRetention.Refresh (frame, player)
    else Enemy.UnitFrameObjectRetention.Rebind (frame, player) end
end

function EnemyUnitFrame:Update (player)

	if (not self.isEnabled) then return end

	local playerChanged = self.forcePlayerChanged
		or
		(self.playerCareer ~= player.career and player.career > 0)
		or
		self.playerName ~= player.name
		or
		self.playerGroupIndex ~= player.groupIndex

	if (not playerChanged and not HasPlayerDisplayStateChanged (self, player))
	then
		return
	end

    local retention = Enemy.UnitFrameObjectRetention
    local retain = playerChanged and retention and retention.CanRetain (self, player)
    local refresh = retain and (self._retainedForceRefresh or self.forcePlayerChanged)
    if (refresh) then self._retainedForceRefresh = true end
    -- Cold rendering already pays construction once. Prepare only when a
    -- caller actually replaces existing components; that first refresh keeps
    -- its ordinary construction and includes the one-time preparation cost.
    local prime = playerChanged and not retain and retention
        and (#self.parts > 0 or #self.effectsIndicators > 0 or #self.clickCastings > 0)
        and retention.CanPrime (self, player)
	if (playerChanged)
	then
		if (not retain) then self._retainedObjects = nil; self._retainedForceRefresh = nil end
		self.playerCareer = player.career
		self.playerName = player.name
		self.playerGroupIndex = player.groupIndex

        if (Enemy.UnitFrameWindowReuse)
        then
            local updated, stockBuild = Enemy.UnitFrameWindowReuse.Run (self, retain and RebindRetainedFrame or RebuildFrame, player)
            if (not updated) then return end
            prime = prime and stockBuild
        else
            RebuildFrame (self, player)
            prime = false
        end
	end

	StorePlayerDisplayState (self, player)

	for _, part in ipairs (self.parts)
	do
		part:Update (player, self.settings.unitFramesTestMode)
	end

	if (retain and not refresh) then retention.Finish (self) end
	self.forcePlayerChanged = false
    self._retainedForceRefresh = nil
    if (prime) then retention.Prime (self, player) end
end


function EnemyUnitFrame:UpdateDistance (player)

	local f = Enemy.UnitFramePlayerUpdateFilters.Distance.Parts

	for _, part in ipairs (self.parts)
	do
		if (f[part.type])
		then
			part:Update (player, self.settings.unitFramesTestMode)
		end
	end
end


function EnemyUnitFrame:UpdatePartsByType (player, partTypes)

	if (not self.isEnabled or not partTypes) then return end

	local partsByType = self.partsByType
	for partType, _ in pairs (partTypes)
	do
		local parts = partsByType[partType]
		if (parts)
		then
			for _, part in ipairs (parts)
			do
				if (part._type and part._type.OnScoreboardUpdate)
				then
					part._type.OnScoreboardUpdate (part, player)
				else
					part:Update (player, self.settings.unitFramesTestMode)
				end
			end
		end
	end
end


local function UpdateFrameEffects (frame, player, selfCastOnly, indicators, generation)
    local testMode = frame.settings.unitFramesTestMode
    local skipped = false
    for _, indicator in ipairs (indicators)
    do
        if (not selfCastOnly or testMode or indicator._selfCastOnly)
        then
            indicator:EffectsUpdated (player, testMode)
        else
            skipped = true
        end
        -- A callback can reset/rebuild this frame. Do not visit its old list.
        if (frame._effectsUpdateGeneration ~= generation or frame.effectsIndicators ~= indicators) then break end
    end
    return skipped
end

local function FirstPendingEffectsIndicator (indicators, first, second)
    if (not first) then return second end
    if (not second or first == second) then return first end
    -- Nested passes can show an earlier entry after an outer pass showed a
    -- later one. Keep the earliest list entry so the final restack covers both.
    for _, indicator in ipairs (indicators)
    do
        if (indicator == first or indicator == second) then return indicator end
    end
end

function EnemyUnitFrame:UpdateEffects (player, selfCastOnly)

    if (not self.isEnabled) then return false end
    local indicators = self.effectsIndicators
    local generation = self._effectsUpdateGeneration
    local wasUpdating = self._updatingEffects and self._effectsUpdateIndicators == indicators
    local previousShown = wasUpdating and self._effectsLayerShown or nil
    self._updatingEffects = true
    self._effectsLayerShown = nil
    self._effectsUpdateIndicators = indicators

    -- One retained body preserves error propagation without a closure per
    -- packet. Successful earlier indicators still need their layers restored.
    local ok, skipped = pcall (UpdateFrameEffects, self, player, selfCastOnly, indicators, generation)
    if (self._effectsUpdateGeneration == generation and self.effectsIndicators == indicators)
    then
        local shown = FirstPendingEffectsIndicator (indicators, previousShown, self._effectsLayerShown)
        self._updatingEffects = wasUpdating or nil
        self._effectsLayerShown = wasUpdating and shown or nil
        self._effectsUpdateIndicators = wasUpdating and indicators or nil
        if (shown and not wasUpdating)
        then
            if (ok) then
                self:_RefreshEffectsIndicatorLayers (shown)
            else
                -- A secondary layer callback error must not replace the
                -- original filter error. Batching is already cleared here.
                pcall (self._RefreshEffectsIndicatorLayers, self, shown)
            end
        end
    elseif (self._effectsUpdateIndicators == indicators)
    then
        self._updatingEffects = nil
        self._effectsLayerShown = nil
        self._effectsUpdateIndicators = nil
    end

    if (not ok) then error (skipped, 0) end
    return skipped
end


function EnemyUnitFrame:ProceedClickCasting (mouseButton, flags)

	for _, click_casting in pairs (self.clickCastings)
	do
		if (click_casting:IsMatch (mouseButton, flags))
		then
			return click_casting:Proceed ()
		end
	end

	WindowSetGameActionData (self.windowName, 0, 0, L"")

	return false
end


function Enemy._GetUnitFrameFromWindowName (name)
	local group_index, index = name:match ("EnemyUnitFrame(%d+)_(%d+)")
	if (group_index == nil or index == nil) then return nil end

	local frame_group = Enemy.unitFrames.frames[tonumber (group_index)]
	if (not frame_group) then return nil end

	local frame = frame_group[tonumber (index)]
	if (not frame) then return nil end

	return group_index, index, frame
end


function Enemy.UnitFramesUI_UnitFrame_OnLButtonDown (flags)

	local _, _, frame = Enemy._GetUnitFrameFromWindowName (SystemData.MouseOverWindow.name)
	if (not frame) then return end

	local e = { cancel = false }
	Enemy.TriggerEvent ("UnitFramesOnMouse", e, 1, true, flags, frame)
	if (e.cancel) then return end

	frame.lButtonProceeded = frame:ProceedClickCasting (1, flags)

	if (not frame.lButtonProceeded)
	then
		WindowSetGameActionData (frame.windowName, GameData.PlayerActions.SET_TARGET, 0, frame.playerName)
	end
end


function Enemy.UnitFramesUI_UnitFrame_OnMButtonDown (flags)

	local _, _, frame = Enemy._GetUnitFrameFromWindowName (SystemData.MouseOverWindow.name)
	if (not frame) then return end

	local e = { cancel = false }
	Enemy.TriggerEvent ("UnitFramesOnMouse", e, 2, true, flags, frame)
	if (e.cancel) then return end

	frame.mButtonProceeded = frame:ProceedClickCasting (2, flags)

	if (frame.mButtonProceeded and WindowGameAction)
	then
		WindowGameAction (frame.windowName)
	end
end


function Enemy.UnitFramesUI_UnitFrame_OnRButtonDown (flags)

	local _, _, frame = Enemy._GetUnitFrameFromWindowName (SystemData.MouseOverWindow.name)
	if (not frame) then return end

	local e = { cancel = false }
	Enemy.TriggerEvent ("UnitFramesOnMouse", e, 3, true, flags, frame)
	if (e.cancel) then return end

	frame.rButtonProceeded = frame:ProceedClickCasting (3, flags)

	if (frame.rButtonProceeded and WindowGameAction)
	then
		WindowGameAction (frame.windowName)
	end
end


function Enemy.UnitFramesUI_UnitFrame_OnLButtonUp (flags)

	local _, _, frame = Enemy._GetUnitFrameFromWindowName (SystemData.MouseOverWindow.name)
	if (not frame) then return end

	local e = { cancel = false }
	Enemy.TriggerEvent ("UnitFramesOnMouse", e, 1, false, flags, frame)

	if (GetDesiredInteractAction () == SystemData.InteractActions.TELEPORT)
	then
		UseItemTargeting.SendTeleport ()
	end
end


function Enemy.UnitFramesUI_UnitFrame_OnMButtonUp (flags)

	local _, _, frame = Enemy._GetUnitFrameFromWindowName (SystemData.MouseOverWindow.name)
	if (not frame) then return end

	local e = { cancel = false }
	Enemy.TriggerEvent ("UnitFramesOnMouse", e, 2, false, flags, frame)
end


function Enemy.UnitFramesUI_UnitFrame_OnRButtonUp (flags)

	local _, _, frame = Enemy._GetUnitFrameFromWindowName (SystemData.MouseOverWindow.name)
	if (not frame or frame.rButtonProceeded) then return end

	local e = { cancel = false }
	Enemy.TriggerEvent ("UnitFramesOnMouse", e, 3, false, flags, frame)
	if (e.cancel) then return end

	local player = Enemy.groups.players[frame.playerName]
	local self_player = Enemy.groups.player
	if (not player or not self_player) then return end

	SystemData.UserInput.selectedGroupMember = player.name

	local custom_menu_items = {}
	local is_in_group_or_warband = (Enemy.groups.groupType == Enemy.GroupTypes.Group or Enemy.groups.groupType == Enemy.GroupTypes.Warband)

	table.insert (custom_menu_items, PlayerMenuWindow.NewCustomItem (GetString (StringTables.Default.LABEL_GROUP_OPTIONS), EA_Window_OpenParty.OpenToManageTab, false))
	table.insert (custom_menu_items, PlayerMenuWindow.NewCustomItem (L"Unit frames options", function () Enemy.UI_ConfigDialog_Open ("UnitFrames") end, false))
	table.insert (custom_menu_items, PlayerMenuWindow.NewCustomItem (L"Group icons options", function () Enemy.UI_ConfigDialog_Open ("GroupIcons") end, false))

	if (is_in_group_or_warband)
	then
		if (self_player.isGroupLeader)
		then
			table.insert (custom_menu_items, PlayerMenuWindow.NewCustomItem (GetString (StringTables.Default.LABEL_PARTY_FORM_WARPARTY), GroupWindow.OnFormWarparty, Enemy.groups.groupType == Enemy.GroupTypes.Warband))

			if (Enemy.groups.groupType == Enemy.GroupTypes.Group)
			then
				table.insert (custom_menu_items, PlayerMenuWindow.NewCustomItem (GetString (StringTables.Default.LABEL_MAKE_LEADER), GroupWindow.OnMakeLeader, player.isSelf or not player.isOnline))
			else
				table.insert (custom_menu_items, PlayerMenuWindow.NewCustomItem (GetString (StringTables.Default.LABEL_MAKE_LEADER), BattlegroupHUD.OnMenuClickMakeLeader, player.isSelf or not player.isOnline))
			end
		end

		if (Enemy.groups.groupType == Enemy.GroupTypes.Group)
		then
			table.insert (custom_menu_items, PlayerMenuWindow.NewCustomItem (GetString (StringTables.Default.LABEL_LEAVE_GROUP), GroupWindow.OnLeaveGroup, false))
		else
			table.insert (custom_menu_items, PlayerMenuWindow.NewCustomItem (GetString (StringTables.Default.LABEL_LEAVE_GROUP), BattlegroupHUD.OnMenuClickLeaveGroup, false))
		end
	end

	if (self_player.isGroupLeader or self_player:IsMainAssist ())
	then
		if (Enemy.groups.groupType == Enemy.GroupTypes.Group)
		then
			table.insert (custom_menu_items, PlayerMenuWindow.NewCustomItem (GetString (StringTables.Default.LABEL_MAKE_MAIN_ASSIST), GroupWindow.OnMakeMainAssist,
				player:IsMainAssist () or not player.isOnline))
		else
			table.insert (custom_menu_items, PlayerMenuWindow.NewCustomItem (GetString (StringTables.Default.LABEL_MAKE_MAIN_ASSIST), BattlegroupHUD.OnMenuClickMakeMainAssist,
				player:IsMainAssist () or not player.isOnline))
		end
	end

	PlayerMenuWindow.ShowMenu (player.name, 0, custom_menu_items)
end


function Enemy.UnitFramesUI_UnitFrame_OnMouseOver (flags)

	local _, _, frame = Enemy._GetUnitFrameFromWindowName (SystemData.MouseOverWindow.name)
	if (not frame) then return end

	if (
		frame.settings.unitFramesTooltipMode == "never"
		or
		(frame.settings.unitFramesTooltipMode == "shift" and not Enemy.IsShiftPressed(flags))
		or
		(frame.settings.unitFramesTooltipMode == "alt" and not Enemy.IsAltPressed(flags))
		or
		(frame.settings.unitFramesTooltipMode == "ctrl" and not Enemy.IsControlPressed(flags))
		)
	then
		return
	end

	local player = Enemy.groups.players[frame.playerName]
	local self_player = Enemy.groups.player
	if (not player or not self_player) then return end

	Tooltips.CreateTextOnlyTooltip (SystemData.MouseOverWindow.name)

	Tooltips.SetTooltipText (1, 1, player.name)
	Tooltips.SetTooltipColor (1, 1, 150, 150, 255)

	if (player.groupIndex)
	then
		Tooltips.SetTooltipText (1, 3, L"Group "..player.groupIndex)
		Tooltips.SetTooltipColor (1, 3, 100, 100, 100)
	end

	Tooltips.SetTooltipText (2, 1, GetCareerLine (player.career))
	Tooltips.SetTooltipText (2, 3, GetTooltipLevelText (player))

	local k = 2

	if (player.zoneId > 0)
	then
		k = k + 1
		Tooltips.SetTooltipText (k, 1, L"Location")
		Tooltips.SetTooltipText (k, 3, GetZoneName (player.zoneId))
		Tooltips.SetTooltipColor (k, 3, 200, 255, 100)
	end

	if (player.isGroupLeader or player.isDistant or player.isLOS or not player.isOnline)
	then
		k = k + 1
		Tooltips.SetTooltipText (k, 1, L" ")
	end

	if (player.isGroupLeader)
	then
		k = k + 1

		if (Enemy.groups.groupType == Enemy.GroupTypes.Warband)
		then
			Tooltips.SetTooltipText (k, 1, L"Warband leader")
		else
			Tooltips.SetTooltipText (k, 1, L"Group leader")
		end

		Tooltips.SetTooltipColor (k, 1, 200, 255, 100)
	end

	if (player.distance and not player.isSelf)
	then
		k = k + 1
		Tooltips.SetTooltipText (k, 1, L"Distance")
		Tooltips.SetTooltipText (k, 3, towstring (player.distance))
	end

	if (player.isDistant)
	then
		k = k + 1
		Tooltips.SetTooltipText (k, 1, L"Distant")
		Tooltips.SetTooltipColor (k, 1, 150, 150, 150)
	end

	if (player.isLOS)
	then
		k = k + 1
		Tooltips.SetTooltipText (k, 1, L"Out of LOS")
		Tooltips.SetTooltipColor (k, 1, 150, 150, 150)
	end

	if (not player.isOnline)
	then
		k = k + 1
		Tooltips.SetTooltipText (k, 1, L"Offline")
		Tooltips.SetTooltipColor (k, 1, 255, 150, 150)
	end

	Tooltips.AnchorTooltip (Tooltips.ANCHOR_CURSOR)
	Tooltips.Finalize()
end

if (Enemy.UnitFrameWindowReuse) then Enemy.UnitFrameWindowReuse.RegisterClass (EnemyUnitFrame) end

if (Enemy._InitializeUnitFrameObjectRetention) then
    Enemy._InitializeUnitFrameObjectRetention (Enemy, pairs, ipairs, type, tonumber, InterfaceCore)
end

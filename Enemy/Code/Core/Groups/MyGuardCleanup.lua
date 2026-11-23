-- Adapted from Caffeine's MyGuardCleanup in VinyUI 7.2.1 / Enemy 3.0.1.
-- An acquisition record identifies one observed recipient application. Keeping
-- that identity distinct from a later same-slot application avoids parallel
-- player/index/ability/generation fields in the self association.
local Enemy = Enemy
local pairs = pairs
local GuardAbilityIds = Enemy.GuardAbilityIds
local initialized = false
local scopePlayer, scopeGroupIndex, scopeGroupType
local selfGuardIndex, recipient, selfRecipient
local selfAssociationAmbiguous = false
local retiredGuards, retirementOrder = {}, 0
local loadingBeginEvent, loadingEndEvent
local activeWrite, restoring = nil, false
local removedEffect = {}

local function Reset ()
    scopePlayer, scopeGroupIndex, scopeGroupType = nil, nil, nil
    selfGuardIndex, recipient, selfRecipient = nil, nil, nil
    selfAssociationAmbiguous = false
    retiredGuards, retirementOrder = {}, 0
end


local function IsMyGuard (effect)
    return effect and effect.castByPlayer and GuardAbilityIds[effect.abilityId]
end


local function IsCurrentMember (player)
    local groups = Enemy.groups
    return player and groups and groups.players and groups.players[player.name] == player
        and (player == scopePlayer or (not player.isSelf and player.isInPlayerGroup))
end


local function ReconcileScope ()
    local groups = Enemy.groups
    local player = groups and groups.player
    if (not player or not player.group or not groups.players or groups.players[player.name] ~= player)
    then
        Reset ()
        return false
    end
    if (scopePlayer ~= player or scopeGroupIndex ~= player.groupIndex or scopeGroupType ~= groups.groupType)
    then
        Reset ()
        scopePlayer, scopeGroupIndex, scopeGroupType = player, player.groupIndex, groups.groupType
    end
    if (recipient and not IsCurrentMember (recipient.player)) then recipient = nil end
    if (selfRecipient and not IsCurrentMember (selfRecipient.player))
    then
        selfGuardIndex, selfRecipient = nil, nil
        selfAssociationAmbiguous = false
    end
    return true
end


local function ReconcileRoster ()
    if (not ReconcileScope ()) then return end
    for member in pairs (retiredGuards) do
        if (not IsCurrentMember (member)) then retiredGuards[member] = nil end
    end
end


local function FindMyGuard (player, data, isFullList, preferredIndex)
    local effect = preferredIndex and player.effects[preferredIndex]
    if (IsMyGuard (effect) and (not data or isFullList or data[preferredIndex]))
    then
        return preferredIndex, effect.abilityId
    end
    for abilityId in pairs (GuardAbilityIds) do
        local bucket = player.effectsByAbilityId and player.effectsByAbilityId[abilityId]
        if (bucket)
        then
            for index, candidate in pairs (bucket) do
                if (candidate.castByPlayer and (not data or isFullList or data[index]))
                then
                    return index, abilityId
                end
            end
        end
    end
end


local function SameSlot (record, player, index, abilityId)
    return record and record.player == player and record.index == index and record.abilityId == abilityId
end


local function AssociateSelfGuard (ambiguous)
    selfRecipient = recipient
    selfAssociationAmbiguous = ambiguous == true
end


local function ForgetRecoverableGuards ()
    for _, record in pairs (retiredGuards) do record.effect = nil end
end

-- A wrapped cache writer may deliver a native update before delegating our
-- write. Preserve that completed native row if the later delegation replaces
-- it. Pointer identity is used only to detect replacement, never to decide
-- whether a native observation belongs to the addon.
local function WriteEffect (player, index, effect, notify)
    local write = {
        player = player, index = index, previous = activeWrite,
        packet = { [index] = effect or removedEffect },
    }
    activeWrite = write
    local ok, changed = pcall (player.LoadEffects, player, write.packet, false)
    activeWrite = write.previous
    local repaired = false
    if (write.native and player.effects[index] ~= write.observed)
    then
        local repairedOk, result = pcall (WriteEffect, player, index, write.effect, false)
        if (not repairedOk and ok) then ok, changed = false, result end
        repaired = repairedOk and result
    end
    if (not ok) then error (changed, 0) end
    if (notify ~= false and (changed or repaired) and IsCurrentMember (player))
    then
        player._enemyLastMemberEffectRedraw = Enemy.time or 0
        Enemy.TriggerEvent ("GroupsPlayerEffectsUpdated", player)
    end
    return changed or repaired
end


local function RetireGuard (record, remember)
    if (not record or not IsCurrentMember (record.player) or record.player == scopePlayer) then return end
    local effect = record.player.effects[record.index]
    if (not IsMyGuard (effect) or effect.abilityId ~= record.abilityId) then return end
    retirementOrder = retirementOrder + 1
    record.order = retirementOrder
    record.effect = remember ~= false and Enemy.clone (effect) or nil
    retiredGuards[record.player] = record
    WriteEffect (record.player, record.index)
end


local function RestoreRetiredGuard (freshSelf)
    if (restoring or not ReconcileScope () or recipient or not FindMyGuard (scopePlayer)) then return end
    local record
    for member, saved in pairs (retiredGuards) do
        local cached = member.effects[saved.index]
        if (not IsCurrentMember (member) or (cached ~= nil and cached ~= saved.effect))
        then
            retiredGuards[member] = nil
        elseif (saved.effect and (not record or saved.order > record.order))
        then
            record = saved
        end
    end
    if (not record) then return end
    local member, effect = record.player, record.effect
    local ambiguous = not freshSelf and not SameSlot (selfRecipient, member, record.index, record.abilityId)
    local registry, guardIndex = retiredGuards, selfGuardIndex
    restoring = true
    local ok, err = pcall (WriteEffect, member, record.index, effect, false)
    restoring = false
    if (not ok) then error (err, 0) end
    if (not ReconcileScope () or not IsCurrentMember (member)) then return end
    if (registry ~= retiredGuards or recipient or selfGuardIndex ~= guardIndex
        or retiredGuards[member] ~= record or record.effect ~= effect
        or member.effects[record.index] ~= effect
        or not IsMyGuard (effect) or effect.abilityId ~= record.abilityId)
    then
        -- A later native recipient wins. Its same-slot row is authoritative
        -- even when LoadEffects retained the synthetic row object unchanged.
        local current = member.effects[record.index]
        if (not SameSlot (recipient, member, record.index, record.abilityId)
            and IsMyGuard (current) and current.abilityId == record.abilityId)
        then
            WriteEffect (member, record.index)
        elseif (SameSlot (recipient, member, record.index, record.abilityId))
        then
            member._enemyLastMemberEffectRedraw = Enemy.time or 0
            Enemy.TriggerEvent ("GroupsPlayerEffectsUpdated", member)
        end
        return
    end
    retiredGuards[member] = nil
    recipient = { player = member, index = record.index, abilityId = record.abilityId }
    AssociateSelfGuard (ambiguous)
    member._enemyLastMemberEffectRedraw = Enemy.time or 0
    Enemy.TriggerEvent ("GroupsPlayerEffectsUpdated", member)
end


local function OnEffectsLoaded (player, data, isFullList)
    local write = activeWrite
    while (write) do
        if (write.player == player and write.packet == data) then return end
        write = write.previous
    end
    write = activeWrite
    while (write) do
        if (write.player == player and (isFullList or data[write.index] ~= nil))
        then
            write.native = true
            write.observed = player.effects[write.index]
            write.effect = write.observed and Enemy.clone (write.observed) or nil
        end
        write = write.previous
    end
    if (not ReconcileScope () or not IsCurrentMember (player)) then return end
    local retired = retiredGuards[player]
    if (retired and (isFullList or data[retired.index] ~= nil)) then retiredGuards[player] = nil end
    if (player == scopePlayer)
    then
        local previousIndex, wasAmbiguous = selfGuardIndex, selfAssociationAmbiguous
        local observedIndex = FindMyGuard (player, data, isFullList, selfGuardIndex)
        local currentIndex = observedIndex or FindMyGuard (player, nil, false, selfGuardIndex)
        local associated = selfRecipient == recipient
        local oldRecipient
        if (previousIndex and not currentIndex and recipient and (not selfRecipient or associated or wasAmbiguous))
        then
            oldRecipient, recipient = recipient, nil
        end
        selfGuardIndex = currentIndex
        if (observedIndex)
        then
            if (previousIndex and previousIndex ~= currentIndex and (not selfRecipient or associated))
            then
                selfRecipient, selfAssociationAmbiguous = nil, false
            else
                local ambiguous = previousIndex == currentIndex and (wasAmbiguous or (selfRecipient and not associated))
                if (recipient or previousIndex ~= currentIndex) then AssociateSelfGuard (ambiguous) end
            end
        elseif (not currentIndex)
        then
            selfRecipient, selfAssociationAmbiguous = nil, false
        end
        local cancelled = previousIndex and not currentIndex and not wasAmbiguous and (oldRecipient ~= nil or recipient == nil)
        if (cancelled) then ForgetRecoverableGuards () end
        RetireGuard (oldRecipient, not cancelled)
        if (not cancelled and currentIndex and not oldRecipient) then RestoreRetiredGuard (previousIndex ~= currentIndex) end
        return
    end
    local preferred = recipient and recipient.player == player and recipient.index or nil
    local index, abilityId = FindMyGuard (player, data, isFullList, preferred)
    if (index)
    then
        retiredGuards[player] = nil
        local oldRecipient = recipient
        local acquired = not SameSlot (recipient, player, index, abilityId)
        if (acquired)
        then
            recipient = { player = player, index = index, abilityId = abilityId,
                mayBeStale = SameSlot (retired, player, index, abilityId) == true }
            if (oldRecipient and oldRecipient.mayBeStale) then selfAssociationAmbiguous = true end
        end
        if (acquired and selfGuardIndex and not selfRecipient) then AssociateSelfGuard () end
        if (acquired) then RetireGuard (oldRecipient) end
    elseif (recipient and recipient.player == player and not IsMyGuard (player.effects[recipient.index]))
    then
        local recover = recipient.mayBeStale
        if (recover and selfRecipient and selfRecipient.player == player) then selfAssociationAmbiguous = true end
        recipient = nil
        if (recover) then RestoreRetiredGuard () else ForgetRecoverableGuards () end
    end
end


local function Shutdown ()
    if (Enemy.MyGuardCleanupOnEffectsLoaded == OnEffectsLoaded) then Enemy.MyGuardCleanupOnEffectsLoaded = nil end
    if (type (UnregisterEventHandler) == "function")
    then
        if (loadingBeginEvent) then UnregisterEventHandler (loadingBeginEvent, "Enemy.MyGuardCleanupOnLoadingBegin") end
        if (loadingEndEvent) then UnregisterEventHandler (loadingEndEvent, "Enemy.MyGuardCleanupOnLoadingEnd") end
    end
    loadingBeginEvent, loadingEndEvent = nil, nil
    Enemy.RemoveEventHandler ("MyGuardCleanup", "GroupsUpdated")
    Enemy.RemoveEventHandler ("MyGuardCleanup", "GroupsTypeUpdated")
    Enemy.RemoveEventHandler ("MyGuardCleanup", "Shutdown")
    initialized = false
    Reset ()
end
Enemy.MyGuardCleanupOnLoadingBegin = Reset
Enemy.MyGuardCleanupOnLoadingEnd = ReconcileScope

function Enemy.MyGuardCleanupInitialize ()
    if (initialized or Enemy.careerArchetypes[GameData.Player.career.line] ~= Enemy.Archetypes.Tank) then return end
    initialized = true
    Reset ()
    Enemy.MyGuardCleanupOnEffectsLoaded = OnEffectsLoaded
    Enemy.AddEventHandler ("MyGuardCleanup", "GroupsUpdated", ReconcileRoster)
    Enemy.AddEventHandler ("MyGuardCleanup", "GroupsTypeUpdated", Reset)
    Enemy.AddEventHandler ("MyGuardCleanup", "Shutdown", Shutdown)
    local events = SystemData and SystemData.Events
    if (events and type (events.LOADING_BEGIN) == "number" and type (events.LOADING_END) == "number"
        and type (RegisterEventHandler) == "function" and type (UnregisterEventHandler) == "function")
    then
        loadingBeginEvent, loadingEndEvent = events.LOADING_BEGIN, events.LOADING_END
        RegisterEventHandler (loadingBeginEvent, "Enemy.MyGuardCleanupOnLoadingBegin")
        RegisterEventHandler (loadingEndEvent, "Enemy.MyGuardCleanupOnLoadingEnd")
    end
    if (not ReconcileScope ()) then return end
    selfGuardIndex = FindMyGuard (scopePlayer)
    for _, player in pairs (Enemy.groups.players) do
        if (player ~= scopePlayer and IsCurrentMember (player))
        then
            local index, abilityId = FindMyGuard (player)
            if (index)
            then
                if (recipient) then recipient = nil; return end
                recipient = { player = player, index = index, abilityId = abilityId }
            end
        end
    end
    if (selfGuardIndex) then AssociateSelfGuard () end
end

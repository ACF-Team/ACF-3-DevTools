util.AddNetworkString("ACF_DevTools_EntityKeyValue")

local EntityKeyValues = ACF_DevTools.EntityKeyValues or {}
ACF_DevTools.EntityKeyValues = EntityKeyValues
local ReliabilityTracking_Ents = {}
local ReliabilityTracking_Phys = {}

function EntityKeyValues.WriteEntityIdxKeyValue(EntIdx, CategoryName, Key, Value)
    local TrackReliability = ReliabilityTracking_Ents[EntIdx]
    if not TrackReliability then
        TrackReliability = 0
        ReliabilityTracking_Ents[EntIdx] = 0
    end

    -- We'll send reliable messages every 0.5 seconds or so.
    local Now = SysTime()
    local IsReliable = (Now - TrackReliability) > 0.5
    if IsReliable then
        -- Set track reliability so we don't send reliable messages for this amount of time.
        ReliabilityTracking_Ents[EntIdx] = Now
    end

    net.Start("ACF_DevTools_EntityKeyValue", not IsReliable)
    net.WriteUInt(0, 2) -- type
    net.WriteUInt(EntIdx, MAX_EDICT_BITS)
    net.WriteString(CategoryName)
    net.WriteType(Key)
    net.WriteType(Value)
    net.Broadcast()
end

function EntityKeyValues.WritePhysObjIdxKeyValue(EntIdx, PhysObjIdx, CategoryName, Key, Value)
    local TblTrackReliability = ReliabilityTracking_Ents[EntIdx]
    if not TblTrackReliability then
        TblTrackReliability = {}
        ReliabilityTracking_Ents[EntIdx] = TblTrackReliability
    end
    local TrackReliability = TblTrackReliability[PhysObjIdx]
    if not TrackReliability then
        TrackReliability = 0
        TblTrackReliability[PhysObjIdx] = 0
    end

    -- We'll send reliable messages every 0.5 seconds or so.
    local Now = SysTime()
    local IsReliable = (Now - TrackReliability) > 0.5
    if IsReliable then
        -- Set track reliability so we don't send reliable messages for this amount of time.
        TblTrackReliability[PhysObjIdx] = Now
    end

    net.Start("ACF_DevTools_EntityKeyValue", not IsReliable)
    net.WriteUInt(1, 2) -- type
    net.WriteUInt(EntIdx, MAX_EDICT_BITS)
    net.WriteUInt(PhysObjIdx, 8)
    net.WriteString(CategoryName)
    net.WriteType(Key)
    net.WriteType(Value)
    net.Broadcast()
end

function EntityKeyValues.WriteEntityKeyValue(Entity, CategoryName, Key, Value)
    return EntityKeyValues.WriteEntityIdxKeyValue(Entity:EntIndex(), CategoryName, Key, Value)
end

function EntityKeyValues.WritePhysObjKeyValue(PhysObj, CategoryName, Key, Value)
    return EntityKeyValues.WriteEntityIdxKeyValue(PhysObj:GetEntity():EntIndex(), PhysObj:GetIndex(), CategoryName, Key, Value)
end
--[[
EntityKeyValues.WriteEntityKeyValue(Entity(95), "Testing 123", "Thing", 4)
EntityKeyValues.WriteEntityKeyValue(Entity(95), "ACF-3", "Hmmmmm", 4)
EntityKeyValues.WriteEntityKeyValue(Entity(95), "Testing 123", "Thing", 4)
EntityKeyValues.WriteEntityKeyValue(Entity(95), "Testing 123", "Thing 2", 4)
]]
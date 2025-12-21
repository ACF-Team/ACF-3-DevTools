util.AddNetworkString("ACF_DevTools_EntityKeyValue")

local EntityKeyValues = ACF_DevTools.EntityKeyValues or {}
ACF_DevTools.EntityKeyValues = EntityKeyValues

function EntityKeyValues.WriteEntityIdxKeyValue(EntIdx, CategoryName, Key, Value)
    net.Start("ACF_DevTools_EntityKeyValue")
    net.WriteUInt(0, 2) -- type
    net.WriteUInt(EntIdx, MAX_EDICT_BITS)
    net.WriteString(CategoryName)
    net.WriteType(Key)
    net.WriteType(Value)
    net.Broadcast()
end

function EntityKeyValues.WritePhysObjIdxKeyValue(EntIdx, PhysObjIdx, CategoryName, Key, Value)
    net.Start("ACF_DevTools_EntityKeyValue")
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
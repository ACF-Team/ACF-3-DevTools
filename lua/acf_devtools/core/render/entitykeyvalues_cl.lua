local RenderData = {}

local EntityKeyValues = ACF_DevTools.EntityKeyValues or {}
ACF_DevTools.EntityKeyValues = EntityKeyValues

function EntityKeyValues.GetEntityData(EntIdx)
    local EntityData = RenderData[EntIdx]
    if not EntityData then
        EntityData = {
            Categories = {},
            PhysObjs = {},
            Collapsed = false
        }

        RenderData[EntIdx] = EntityData
    end

    return EntityData
end

function EntityKeyValues.GetPhysObjData(EntIdx, PhysObjIdx)
    local EntityData  = EntityKeyValues.GetEntityData(EntIdx)
    local PhysObjData = EntityData.PhysObjs[PhysObjIdx]
    if not PhysObjData then
        PhysObjData = {
            Categories = {},
            Collapsed = false
        }

        EntityData.PhysObjs[EntIdx] = PhysObjData
    end

    return PhysObjData
end


function EntityKeyValues.IsEntityEmpty(EntityObj)
    if next(EntityObj.Categories) == nil and next(EntityObj.PhysObjs) == nil then return true end
    for _, CategoryObject in pairs(EntityObj.Categories) do
        if not EntityKeyValues.IsCategoryEmpty(CategoryObject) then return false end
    end
    for _, PhysObj in pairs(EntityObj.PhysObjs) do
        if not EntityKeyValues.IsPhysObjEmpty(PhysObj) then return false end
    end
    return true
end

function EntityKeyValues.IsPhysObjEmpty(PhysObj)
    if next(PhysObj.Categories) == nil then return true end
    for _, CategoryObject in pairs(PhysObj.Categories) do
        if not EntityKeyValues.IsCategoryEmpty(CategoryObject) then return false end
    end
    return true
end

function EntityKeyValues.IsCategoryEmpty(CategoryObject)
    return next(CategoryObject.Data) == nil
end

function EntityKeyValues.GetEntityCategory(EntIdx, Name)
    local EntityData = EntityKeyValues.GetEntityData(EntIdx)
    local Category = EntityData.Categories[Name]
    if not Category then
        Category = {
            Data = {}
        }
        EntityData.Categories[Name] = Category
    end

    return Category
end

function EntityKeyValues.GetPhysObjCategory(EntIdx, PhysObjIdx, Name)
    local PhysObjData = EntityKeyValues.GetPhysObjData(EntIdx, PhysObjIdx)
    local Category    = PhysObjData.Categories[Name]
    if not Category then
        Category = {
            Data = {}
        }
        PhysObjData.Categories[Name] = Category
    end

    return Category
end

function EntityKeyValues.IterateEntities()
    return SortedPairs(RenderData)
end

function EntityKeyValues.IteratePhysObjs(EntityData)
    return SortedPairs(EntityData.PhysObjs)
end

function EntityKeyValues.IterateEntityCategories(EntIdx)
    return SortedPairs(EntityKeyValues.GetEntityData(EntIdx).Categories)
end

function EntityKeyValues.IteratePhysObjCategories(EntIdx, PhysObjIdx)
    return SortedPairs(EntityKeyValues.GetPhysObjData(EntIdx, PhysObjIdx).Categories)
end

function EntityKeyValues.IterateEntityCategoryData(Category)
    return SortedPairs(Category.Data)
end

function EntityKeyValues.IteratePhysObjCategoryData(Category)
    return SortedPairs(Category.Data)
end

function EntityKeyValues.WriteEntityIdxKeyValue(EntIdx, CategoryName, Key, Value)
    local Category = EntityKeyValues.GetEntityCategory(EntIdx, CategoryName)
    Category.Data[Key] = Value
end

function EntityKeyValues.WritePhysObjIdxKeyValue(EntIdx, PhysObjIdx, CategoryName, Key, Value)
    local Category = EntityKeyValues.GetPhysObjCategory(EntIdx, PhysObjIdx, CategoryName)
    Category.Data[Key] = Value
end

function EntityKeyValues.WriteEntityKeyValue(Entity, CategoryName, Key, Value)
    return EntityKeyValues.WriteEntityIdxKeyValue(Entity:EntIndex(), CategoryName, Key, Value)
end

function EntityKeyValues.WritePhysObjKeyValue(PhysObj, CategoryName, Key, Value)
    return EntityKeyValues.WriteEntityIdxKeyValue(PhysObj:GetEntity():EntIndex(), PhysObj:GetIndex(), CategoryName, Key, Value)
end

function EntityKeyValues.ClearEntityState(EntityData)
    table.Empty(EntityData.Categories)
    table.Empty(EntityData.PhysObjs)
    EntityData.Collapsed = false
end

surface.CreateFont("ACF_DebugFixedLarge", {
    font = "Consolas",
    size = 18,
    weight = 900
})

surface.CreateFont("ACF_DebugFixedLarge2", {
    font = "Consolas",
    size = 16,
    weight = 900
})

surface.CreateFont("ACF_DebugFixedSmall", {
    font = "Consolas",
    size = 13,
    weight = 900
})

local function DrawOneLine(Key, Value, MaxKeyLen, X, Y, YOff)
    local Text = Key .. string.rep(' ', math.max(MaxKeyLen - #Key, 0)) .. ": " .. tostring(Value)
    surface.SetFont("ACF_DebugFixedSmall")
    local W, H = surface.GetTextSize(Text)
    X, Y = X, Y + YOff
    surface.SetDrawColor(0, 0, 0, 150)
    local Pad = 2
    surface.DrawRect(X - Pad, Y - (H / 2), W + (Pad * 2), H)
    draw.SimpleTextOutlined(Text, "ACF_DebugFixedSmall", X, Y, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)
    return YOff + 13
end

local function RenderPhysObj(X, Y, Clicked, EntIdx, Ent, PhysObjIdx, PhysObjData)
    local Pos = Ent:WorldSpaceCenter()
    local ScreenPos = Pos:ToScreen()

    local IsEntityCollapsed = PhysObjData.Collapsed
    local W, H = draw.SimpleTextOutlined("[" .. (IsEntityCollapsed and "+" or "-") .. "][Entity #" .. EntIdx .. "][PhysObj #" .. PhysObjIdx .. "]", "ACF_DebugFixedLarge", ScreenPos.x, ScreenPos.y, color_White, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)

    if Clicked and X >= ScreenPos.x and X <= ScreenPos.x + W and Y >= (ScreenPos.y - (H / 2)) and Y <= (ScreenPos.y + H - (H / 2)) then
        PhysObjData.Collapsed = not PhysObjData.Collapsed
    end

    local OffsetY = 20

    if not PhysObjData.Collapsed then
        for CategoryName, Category in EntityKeyValues.IteratePhysObjCategories(EntIdx, PhysObjIdx) do
            local IsCategoryCollapsed = Category.Collapsed
            local TX, TY = ScreenPos.x + 12, ScreenPos.y + OffsetY
            W, H = draw.SimpleTextOutlined("[" .. (IsCategoryCollapsed and "+" or "-") .. "] " .. CategoryName, "ACF_DebugFixedLarge2", TX, TY, color_White, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)
            if Clicked and X >= TX and X <= TX + W and Y >= (TY - (H / 2)) and Y <= (TY + H - (H / 2)) then
                Category.Collapsed = not Category.Collapsed
            end
            OffsetY = OffsetY + 24
            if not IsCategoryCollapsed then
                for Key, Value in EntityKeyValues.IterateEntityCategoryData(Category) do
                    OffsetY = DrawOneLine(Key, Value, 20, ScreenPos.x + 24, ScreenPos.y, OffsetY)
                end
                OffsetY = OffsetY + 8
            end
        end
    end
end

local function RenderEntity(X, Y, Clicked, EntIdx, Ent, EntityData)
    local Pos = Ent:WorldSpaceCenter()
    local ScreenPos = Pos:ToScreen()

    local IsEntityCollapsed = EntityData.Collapsed
    local W, H = draw.SimpleTextOutlined("[" .. (IsEntityCollapsed and "+" or "-") .. "][Entity #" .. EntIdx .. "]", "ACF_DebugFixedLarge", ScreenPos.x, ScreenPos.y, color_White, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)

    if Clicked and X >= ScreenPos.x and X <= ScreenPos.x + W and Y >= (ScreenPos.y - (H / 2)) and Y <= (ScreenPos.y + H - (H / 2)) then
        EntityData.Collapsed = not EntityData.Collapsed
    end

    local OffsetY = 20

    if not EntityData.Collapsed then
        for CategoryName, Category in EntityKeyValues.IterateEntityCategories(EntIdx) do
            local IsCategoryCollapsed = Category.Collapsed
            local TX, TY = ScreenPos.x + 12, ScreenPos.y + OffsetY
            W, H = draw.SimpleTextOutlined("[" .. (IsCategoryCollapsed and "+" or "-") .. "] " .. CategoryName, "ACF_DebugFixedLarge2", TX, TY, color_White, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)
            if Clicked and X >= TX and X <= TX + W and Y >= (TY - (H / 2)) and Y <= (TY + H - (H / 2)) then
                Category.Collapsed = not Category.Collapsed
            end
            OffsetY = OffsetY + 24
            if not IsCategoryCollapsed then
                for Key, Value in EntityKeyValues.IterateEntityCategoryData(Category) do
                    OffsetY = DrawOneLine(Key, Value, 20, ScreenPos.x + 24, ScreenPos.y, OffsetY)
                end
                OffsetY = OffsetY + 8
            end
        end

        for PhysObjIdx, PhysObjData in EntityKeyValues.IteratePhysObjs(EntityData) do
            if EntityKeyValues.IsPhysObjEmpty(PhysObjData) then continue end

            RenderPhysObj(X, Y, Clicked, EntIdx, Ent, PhysObjIdx, PhysObjData)
        end
    end
end

local WasHeld

hook.Add("HUDPaint", "ACF_EntityKeyValues", function()
    local X, Y = input.GetCursorPos()
    local Down = input.IsButtonDown(MOUSE_LEFT)
    local Clicked = WasHeld == false and Down == true
    WasHeld = Down

    for EntIdx, EntityData in EntityKeyValues.IterateEntities() do
        local Ent = Entity(EntIdx)
        if not IsValid(Ent) then
            EntityKeyValues.ClearEntityState(EntityData)
            continue
        end

        if EntityKeyValues.IsEntityEmpty(EntityData) then continue end
        RenderEntity(X, Y, Clicked, EntIdx, Ent, EntityData)
--[[
        for _, PhysObj in ipairs(EntPhys) do
            local IsCollapsed = Collapsed[EntIdx] and Collapsed[EntIdx][PhysObj.Index] == true
            local Pos = Ent:LocalToWorld(PhysObj.Position)
            local ScreenPos = Pos:ToScreen()
            local W, H = draw.SimpleTextOutlined("[" .. (IsCollapsed and "+" or "-") .. "][Entity #" .. EntIdx .. "][PhysObj #" .. PhysObj.Index .. "]", "ACF_DebugFixedLarge", ScreenPos.x, ScreenPos.y, color_White, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)

            if Clicked and X >= ScreenPos.x and X <= ScreenPos.x + W and Y >= (ScreenPos.y - (H / 2)) and Y <= (ScreenPos.y + H - (H / 2)) then
                -- Collapse now
                if not Collapsed[EntIdx] then Collapsed[EntIdx] = {} end
                Collapsed[EntIdx][PhysObj.Index] = not Collapsed[EntIdx][PhysObj.Index]
            end

            local OffsetY = 0
            if not IsCollapsed then
                for Key, Value in SortedPairs(PhysObj) do
                    OffsetY = DrawOneLine(Key, Value, 20, ScreenPos.x, ScreenPos.y, OffsetY)
                end
            end
        end]]
    end
end)

net.Receive("ACF_DevTools_EntityKeyValue", function()
    local Type = net.ReadUInt(2)
    if Type == 0 then -- ent
        EntityKeyValues.WriteEntityIdxKeyValue(net.ReadUInt(MAX_EDICT_BITS), net.ReadString(), net.ReadType(), net.ReadType())
    elseif Type == 1 then -- physobj
        EntityKeyValues.WritePhysObjIdxKeyValue(net.ReadUInt(MAX_EDICT_BITS), net.ReadUInt(8), net.ReadString(), net.ReadType(), net.ReadType())
    end
end)

--[[
EntityKeyValues.WriteEntityIdxKeyValue(90, "Testing 123", "Thing", 4)
EntityKeyValues.WriteEntityIdxKeyValue(90, "ACF-3", "Hmmmmm", 4)

EntityKeyValues.WriteEntityIdxKeyValue(90, "Testing 123", "Thing", 4)
EntityKeyValues.WriteEntityIdxKeyValue(90, "Testing 123", "Thing 2", 4)]]
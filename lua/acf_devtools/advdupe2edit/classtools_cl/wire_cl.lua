local DupeEditor = ACF_DevTools.DupeEditor

local WIRE_COLOR      = Color(255, 255, 255, 110)
local WIRE_HIGHLIGHT  = Color(255, 170, 40, 255)

local function GetWires(EntData)
    local Mods = EntData.EntityMods
    if not istable(Mods) then return end
    for _, Key in ipairs({"WireDupeInfo", "SFDupeInfo"}) do
        local Info = Mods[Key]
        if istable(Info) and istable(Info.Wires) then return Info.Wires end
    end
end
DupeEditor.GetWires = GetWires

-- Points from the input end to the output end, in dupe space
local function WirePoints(View, DestIdx, Wire)
    local Dest = View.Models[DestIdx]
    local Src = View.Models[Wire.Src]
    if not Dest or not Src then return end

    local Points = {LocalToWorld(isvector(Wire.StartPos) and Wire.StartPos or vector_origin, angle_zero, Dest.Pos, Dest.Ang)}
    if istable(Wire.Path) then
        for _, Point in ipairs(Wire.Path) do
            local Info = istable(Point) and View.Models[Point.Entity]
            if Info and isvector(Point.Pos) then
                Points[#Points + 1] = LocalToWorld(Point.Pos, angle_zero, Info.Pos, Info.Ang)
            end
        end
    end
    Points[#Points + 1] = LocalToWorld(isvector(Wire.SrcPos) and Wire.SrcPos or vector_origin, angle_zero, Src.Pos, Src.Ang)
    return Points
end

local function WireColor(Wire)
    local Col = Wire.Color
    if DupeEditor.IsColorTable(Col) then return Color(Col.r, Col.g, Col.b, 200) end
    return WIRE_COLOR
end

local function AddWireLines(Points, Colors, View, DestIdx, Wire, Col)
    local List = WirePoints(View, DestIdx, Wire)
    if not List then return end
    for I = 2, #List do
        Points[#Points + 1] = List[I - 1]
        Points[#Points + 1] = List[I]
        Colors[#Colors + 1] = Col or WireColor(Wire)
    end
end

DupeEditor.RegisterLayer("Wires", {
    Label = "Wires",
    Icon = "icon16/connect.png",
    Default = false,
    PostDraw3D = function(View, Session)
        local Cache = View:GetLayerCache("Wires")
        if not Cache.Points then
            local Points, Colors = {}, {}
            for Idx, EntData in pairs(Session.Dupe.Entities) do
                local Wires = GetWires(EntData)
                if Wires then
                    for _, Wire in pairs(Wires) do
                        if istable(Wire) then AddWireLines(Points, Colors, View, Idx, Wire) end
                    end
                end
            end
            Cache.Points, Cache.Colors = Points, Colors
        end
        DupeEditor.DrawLineBatch(Cache.Points, Cache.Colors)
    end,
})

-- Every input elsewhere in the dupe that reads from Idx
local function FindOutputs(Session, Idx)
    local Out = {}
    for Other, EntData in pairs(Session.Dupe.Entities) do
        local Wires = GetWires(EntData)
        if Wires then
            for Input, Wire in pairs(Wires) do
                if istable(Wire) and Wire.Src == Idx then
                    Out[#Out + 1] = {Other, Input, Wire}
                end
            end
        end
    end
    table.sort(Out, function(A, B) return A[1] < B[1] end)
    return Out
end

local function AddWireList(Panel, Ctx)
    local Session, EntIdx, EntData = Ctx.Session, Ctx.EntIdx, Ctx.EntData
    local Ents = Session.Dupe.Entities
    local Wires = GetWires(EntData) or {}

    local List = Panel:Add("DListView")
    List:Dock(TOP)
    List:DockMargin(0, 4, 0, 0)
    List:SetMultiSelect(false)
    List:AddColumn("Dir"):SetFixedWidth(30)
    List:AddColumn("Port")
    List:AddColumn("Entity")
    List:AddColumn("Other Port")

    for _, Input in ipairs(DupeEditor.SortedKeys(Wires)) do
        local Wire = Wires[Input]
        if istable(Wire) then
            local Src = Ents[Wire.Src]
            local Line = List:AddLine("in", tostring(Input), "[" .. tostring(Wire.Src) .. "] " .. (Src and tostring(Src.Class) or "missing!"), tostring(Wire.SrcId))
            Line.Target, Line.Wires, Line.Input = Wire.Src, Wires, Input
        end
    end
    Ctx.WireOutputs = FindOutputs(Session, EntIdx)
    for _, Entry in ipairs(Ctx.WireOutputs) do
        local Line = List:AddLine("out", tostring(Entry[3].SrcId), "[" .. Entry[1] .. "] " .. tostring(Ents[Entry[1]].Class), tostring(Entry[2]))
        Line.Target, Line.Wires, Line.Input = Entry[1], GetWires(Ents[Entry[1]]), Entry[2]
    end

    List:SetTall(math.Clamp(#List:GetLines() * 17 + 20, 40, 260))
    List:SetTooltip("Double click to jump to it")

    function List.DoDoubleClick(_, _, Line)
        if Ents[Line.Target] then Session:Select(Line.Target) end
    end
    function List.OnRowSelected(_, _, Line)
        Ctx.HighlightWire = {Line.Wires, Line.Input}
    end
    function List.OnRowRightClick(_, _, Line)
        local Menu = DermaMenu()
        if Ents[Line.Target] then
            Menu:AddOption("Go to Entity [" .. Line.Target .. "]", function() Session:Select(Line.Target) end):SetIcon("icon16/arrow_right.png")
        end
        Menu:AddOption("Remove Wire", function()
            Session:Set(Line.Wires, Line.Input, nil)
            Session:Emit("StructureChanged")
            Session:Emit("FocusChanged")
        end):SetIcon("icon16/disconnect.png")
        Menu:Open()
    end

    return #List:GetLines()
end

DupeEditor.RegisterClassTool("*", {
    Name = "Wiring",
    Icon = "icon16/connect.png",
    ShouldShow = function(EntData)
        return GetWires(EntData) ~= nil or (isstring(EntData.Class) and string.StartsWith(EntData.Class, "gmod_wire"))
    end,
    Build = function(Panel, Ctx)
        local Count = AddWireList(Panel, Ctx)
        if Count == 0 then Ctx.AddLine("Wires", "none") end
    end,
    Draw3D = function(View, Ctx)
        local Session, EntIdx = Ctx.Session, Ctx.EntIdx
        local EntData = Session.Dupe.Entities[EntIdx]
        if not EntData then return end

        local Points, Colors = {}, {}
        for Input, Wire in pairs(GetWires(EntData) or {}) do
            local Hl = Ctx.HighlightWire
            local Col = Hl and Hl[2] == Input and Hl[1] == GetWires(EntData) and WIRE_HIGHLIGHT or nil
            if istable(Wire) then AddWireLines(Points, Colors, View, EntIdx, Wire, Col) end
        end
        Ctx.WireOutputs = Ctx.WireOutputs or FindOutputs(Session, EntIdx)
        for _, Entry in ipairs(Ctx.WireOutputs) do
            local Hl = Ctx.HighlightWire
            local Col = Hl and Hl[2] == Entry[2] and Hl[1] == GetWires(Session.Dupe.Entities[Entry[1]]) and WIRE_HIGHLIGHT or nil
            AddWireLines(Points, Colors, View, Entry[1], Entry[3], Col)
        end
        DupeEditor.DrawLineBatch(Points, Colors)
    end,
})

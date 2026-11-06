local DupeEditor = ACF_DevTools.DupeEditor or {}
ACF_DevTools.DupeEditor = DupeEditor

-- Kept across reloads so autorefreshing one file doesn't drop the others' registrations
DupeEditor.ClassTools = DupeEditor.ClassTools or {}
DupeEditor.Layers     = DupeEditor.Layers or {}
DupeEditor.LayerOrder = DupeEditor.LayerOrder or {}

surface.CreateFont("ACF_DupeEditor_Code", {
    font = "Consolas",
    size = 15,
    weight = 500
})

surface.CreateFont("ACF_DupeEditor_Label", {
    font = "Consolas",
    size = 15,
    weight = 900
})

surface.CreateFont("ACF_DupeEditor_Header", {
    font = "Tahoma",
    size = 15,
    weight = 900
})

-- Per-class operators. Def = {Name, Icon, ShouldShow(EntData), Build(Panel, Ctx), Draw3D(View, Ctx)}
function DupeEditor.RegisterClassTool(Classes, Def)
    if isstring(Classes) then Classes = {Classes} end

    Def.Classes = {}
    for _, Class in ipairs(Classes) do
        Def.Classes[Class] = true
    end

    local Tools = DupeEditor.ClassTools
    for I, Existing in ipairs(Tools) do
        if Existing.Name == Def.Name then
            Tools[I] = Def
            return Def
        end
    end
    Tools[#Tools + 1] = Def
    return Def
end

function DupeEditor.GetClassTools(EntData)
    local Out = {}
    for _, Def in ipairs(DupeEditor.ClassTools) do
        if (Def.Classes[EntData.Class] or Def.Classes["*"]) and (not Def.ShouldShow or Def.ShouldShow(EntData)) then
            Out[#Out + 1] = Def
        end
    end
    return Out
end

-- 3D view overlays. Def = {Label, Icon, Default, PreDraw3D, Draw3D, PostDraw3D, Draw2D, GetPickBoxes, Cleanup}
function DupeEditor.RegisterLayer(Name, Def)
    Def.Name = Name
    if not DupeEditor.Layers[Name] then
        DupeEditor.LayerOrder[#DupeEditor.LayerOrder + 1] = Name
    end
    DupeEditor.Layers[Name] = Def
    return Def
end

do
    local TypeOrder = {number = 1, string = 2}
    local function KeySorter(A, B)
        local TA, TB = type(A), type(B)
        if TA ~= TB then
            return (TypeOrder[TA] or 3) < (TypeOrder[TB] or 3)
        end
        if TA == "number" or TA == "string" then return A < B end
        return tostring(A) < tostring(B)
    end

    -- SortedPairs errors on tables with mixed key types
    function DupeEditor.SortedKeys(Tbl)
        local Keys = {}
        for Key in pairs(Tbl) do
            Keys[#Keys + 1] = Key
        end
        table.sort(Keys, KeySorter)
        return Keys
    end
end

function DupeEditor.IsBinary(Str)
    if string.find(Str, "[%z\1-\8\11\12\14-\31\127]") then return true end
    return utf8.len(Str) == nil
end

function DupeEditor.IsColorTable(Value)
    return istable(Value) and isnumber(Value.r) and isnumber(Value.g) and isnumber(Value.b)
end

function DupeEditor.GetTransform(EntData)
    local Phys = EntData.PhysicsObjects and EntData.PhysicsObjects[0]
    if not Phys then return vector_origin, angle_zero end
    return Phys.Pos or vector_origin, Phys.Angle or angle_zero
end

do
    local Cache = {}
    function DupeEditor.ClassColor(Class)
        Class = tostring(Class)
        local Col = Cache[Class]
        if not Col then
            Col = HSVToColor(tonumber(util.CRC(Class)) % 360, 0.55, 0.95)
            Cache[Class] = Col
        end
        return Col
    end
end

-- Keys that hold an entity index from the dupe
DupeEditor.RefKeys = {
    DupeParentID = true,
    Src          = true,
    Entity       = true,
    Index        = true,
    link         = true,
}

function DupeEditor.Notify(Text, Type)
    if AdvDupe2 and AdvDupe2.Notify then
        AdvDupe2.Notify(Text, Type or NOTIFY_GENERIC, 5)
    else
        notification.AddLegacy(Text, Type or NOTIFY_GENERIC, 5)
    end
end

do
    local Serialize
    function Serialize(Value, Indent, Seen)
        local T = type(Value)
        if T == "string" then return string.format("%q", Value) end
        if T == "number" then
            if Value ~= Value then return "0 / 0" end
            if Value == math.huge then return "math.huge" end
            if Value == -math.huge then return "-math.huge" end
            return tostring(Value)
        end
        if T == "Vector" then return string.format("Vector(%s, %s, %s)", Value[1], Value[2], Value[3]) end
        if T == "Angle" then return string.format("Angle(%s, %s, %s)", Value[1], Value[2], Value[3]) end
        if T ~= "table" then return tostring(Value) end
        if Seen[Value] then return "nil --[[ cycle ]]" end
        if next(Value) == nil then return "{}" end
        Seen[Value] = true

        local Inner = Indent .. "    "
        local Lines = {}
        for _, Key in ipairs(DupeEditor.SortedKeys(Value)) do
            local KeyText
            if isstring(Key) and string.match(Key, "^[%a_][%w_]*$") then
                KeyText = Key
            else
                KeyText = "[" .. Serialize(Key, Inner, Seen) .. "]"
            end
            Lines[#Lines + 1] = Inner .. KeyText .. " = " .. Serialize(Value[Key], Inner, Seen)
        end

        Seen[Value] = nil
        return "{\n" .. table.concat(Lines, ",\n") .. "\n" .. Indent .. "}"
    end

    function DupeEditor.Serialize(Value)
        return Serialize(Value, "", {})
    end
end

function DupeEditor.ReplaceInsensitive(Str, Find, Replace)
    local Lower, LowerFind = string.lower(Str), string.lower(Find)
    local Out, Pos = {}, 1
    while true do
        local A, B = string.find(Lower, LowerFind, Pos, true)
        if not A then break end
        Out[#Out + 1] = string.sub(Str, Pos, A - 1)
        Out[#Out + 1] = Replace
        Pos = B + 1
    end
    Out[#Out + 1] = string.sub(Str, Pos)
    return table.concat(Out)
end

function DupeEditor.PopupParent()
    if IsValid(g_ContextMenu) and g_ContextMenu:IsVisible() then return g_ContextMenu end
end

-- Opts = {ReadOnly, OnApply(Text), Buttons = {{Label, Icon, Fn(Text, Entry)}}}
function DupeEditor.OpenTextWindow(Title, Text, Opts)
    Opts = Opts or {}

    local Frame = vgui.Create("DFrame")
    Frame:SetTitle(Title)
    Frame:SetSize(math.min(960, ScrW() - 100), math.min(720, ScrH() - 100))
    Frame:Center()
    Frame:SetSizable(true)
    Frame:SetMinWidth(400)
    Frame:SetMinHeight(240)
    Frame:DockPadding(6, 30, 6, 6)
    Frame:MakePopup()

    local Bottom = Frame:Add("DPanel")
    Bottom:Dock(BOTTOM)
    Bottom:DockMargin(0, 4, 0, 0)
    Bottom:SetTall(28)
    Bottom:SetPaintBackground(false)

    local Entry = Frame:Add("DTextEntry")
    Entry:Dock(FILL)
    Entry:SetMultiline(true)
    Entry:SetFont("ACF_DupeEditor_Code")
    Entry:SetVerticalScrollbarEnabled(true)
    Entry:SetText(Text or "")
    if Opts.ReadOnly then Entry:SetEditable(false) end

    local function GetText()
        local Txt = string.gsub(Entry:GetValue(), "\r", "")
        return Txt
    end
    Frame.GetText = GetText

    local function AddButton(Label, Icon, Fn)
        local Button = Bottom:Add("DButton")
        Button:Dock(RIGHT)
        Button:DockMargin(4, 0, 0, 0)
        Button:SetText(Label)
        if Icon then Button:SetImage(Icon) end
        Button:SizeToContentsX(Icon and 34 or 24)
        Button.DoClick = function() Fn(GetText(), Entry) end
        return Button
    end

    AddButton("Close", "icon16/cross.png", function() Frame:Close() end)
    if Opts.OnApply and not Opts.ReadOnly then
        AddButton("Apply", "icon16/tick.png", function(Txt)
            Opts.OnApply(Txt)
            Frame:Close()
        end)
    end
    for _, Def in ipairs(Opts.Buttons or {}) do
        AddButton(Def[1], Def[2], Def[3])
    end

    local Copy = Bottom:Add("DButton")
    Copy:Dock(LEFT)
    Copy:SetText("Copy All")
    Copy:SetImage("icon16/page_copy.png")
    Copy:SizeToContentsX(34)
    Copy.DoClick = function()
        SetClipboardText(GetText())
        DupeEditor.Notify("Copied!")
    end

    local Info = Bottom:Add("DLabel")
    Info:Dock(FILL)
    Info:DockMargin(8, 0, 0, 0)
    Info:SetDark(true)
    function Info:Think()
        local Value = Entry:GetValue()
        if Value == self.LastValue then return end
        self.LastValue = Value
        local _, Lines = string.gsub(Value, "\n", "")
        self:SetText(string.NiceSize(#Value) .. ", " .. (Lines + 1) .. " lines")
    end

    return Frame, Entry
end

-- Anything erroring between mesh.Begin/End hard crashes the game ("Getting a dynamic mesh without resolving the previous one")
local function CleanChannel(V)
    V = tonumber(V) or 255
    if V ~= V then return 255 end
    return math.Clamp(V, 0, 255)
end

local function IsFiniteVector(V)
    if not isvector(V) then return false end
    local X, Y, Z = V.x, V.y, V.z
    return X == X and Y == Y and Z == Z and math.abs(X) < 1e9 and math.abs(Y) < 1e9 and math.abs(Z) < 1e9
end

function DupeEditor.DrawLineBatch(Points, Colors, DepthTest)
    if not istable(Points) or not istable(Colors) then return end

    local Starts, Ends, Rs, Gs, Bs, As = {}, {}, {}, {}, {}, {}
    for I = 1, #Colors do
        local A, B, C = Points[I * 2 - 1], Points[I * 2], Colors[I]
        if IsFiniteVector(A) and IsFiniteVector(B) and istable(C) then
            local N = #Starts + 1
            Starts[N], Ends[N] = A, B
            Rs[N], Gs[N], Bs[N], As[N] = CleanChannel(C.r), CleanChannel(C.g), CleanChannel(C.b), CleanChannel(C.a)
        end
    end

    local Count = #Starts
    if Count == 0 then return end

    if DepthTest then
        render.SetColorMaterial()
    else
        render.SetColorMaterialIgnoreZ()
    end

    local First = 1
    while First <= Count do
        local Batch = math.min(Count - First + 1, 4096)
        mesh.Begin(MATERIAL_LINES, Batch)
        for I = First, First + Batch - 1 do
            mesh.Position(Starts[I])
            mesh.Color(Rs[I], Gs[I], Bs[I], As[I])
            mesh.AdvanceVertex()
            mesh.Position(Ends[I])
            mesh.Color(Rs[I], Gs[I], Bs[I], As[I])
            mesh.AdvanceVertex()
        end
        mesh.End()
        First = First + Batch
    end
end

--------------------------------------------------------------------------------
-- Session
--------------------------------------------------------------------------------

local SESSION = {}
SESSION.__index = SESSION
DupeEditor.SessionMeta = SESSION

function DupeEditor.NewSession(Dupe, Info, MoreInfo, Name)
    local Session = setmetatable({}, SESSION)
    Session.Dupe      = Dupe
    Session.Info      = Info or {}
    Session.MoreInfo  = MoreInfo or {}
    Session.Name      = Name or "Current Clipboard"
    Session.Selected  = {}
    Session.Hidden    = {}
    Session.UndoStack = {}
    Session.RedoStack = {}
    Session.Listeners = {}
    Session.Dirty     = false
    Session.FileSize  = tonumber(Session.Info.size)

    for Key in pairs(DupeEditor.ReservedInfoKeys or {}) do
        Session.Info[Key] = nil
    end

    Dupe.Entities    = Dupe.Entities or {}
    Dupe.Constraints = Dupe.Constraints or {}
    Dupe.HeadEnt     = Dupe.HeadEnt or {Index = next(Dupe.Entities), Pos = Vector(), Z = 0}

    if not table.IsSequential(Dupe.Constraints) then
        local List = {}
        for _, Key in ipairs(DupeEditor.SortedKeys(Dupe.Constraints)) do
            List[#List + 1] = Dupe.Constraints[Key]
        end
        Dupe.Constraints = List
    end

    return Session
end

function SESSION:Listen(Event, Owner, Fn)
    local List = self.Listeners[Event]
    if not List then
        List = {}
        self.Listeners[Event] = List
    end
    List[Owner] = Fn
end

function SESSION:Emit(Event, ...)
    local List = self.Listeners[Event]
    if not List then return end

    local Calls = {}
    for Owner, Fn in pairs(List) do
        if isstring(Owner) or IsValid(Owner) then
            Calls[#Calls + 1] = Fn
        else
            List[Owner] = nil
        end
    end
    for _, Fn in ipairs(Calls) do
        Fn(...)
    end
end

function SESSION:MarkDirty()
    if self.Dirty then return end
    self.Dirty = true
    self:Emit("DirtyChanged")
end

function SESSION:ClearDirty()
    if not self.Dirty then return end
    self.Dirty = false
    self:Emit("DirtyChanged")
end

-- Selection

function SESSION:SetSelection(List, Primary, Source)
    local Ents = self.Dupe.Entities
    table.Empty(self.Selected)
    for _, Idx in ipairs(List) do
        if Ents[Idx] then self.Selected[Idx] = true end
    end

    if Primary == nil or not self.Selected[Primary] then
        if self.Primary and self.Selected[self.Primary] then
            Primary = self.Primary
        else
            Primary = List[#List]
            if not self.Selected[Primary] then Primary = next(self.Selected) end
        end
    end

    self.Primary = Primary
    self.ActiveConstraint = nil
    self:Emit("SelectionChanged", Source)
    self:Emit("FocusChanged")
end

-- Mode: nil replaces, "add", "toggle"
function SESSION:Select(Idx, Mode, Source)
    if Mode == nil then
        return self:SetSelection({Idx}, Idx, Source)
    end

    local List = self:GetSelectedList()
    if Mode == "toggle" and self.Selected[Idx] then
        table.RemoveByValue(List, Idx)
        return self:SetSelection(List, nil, Source)
    end

    List[#List + 1] = Idx
    self:SetSelection(List, Idx, Source)
end

function SESSION:ClearSelection(Source)
    self:SetSelection({}, nil, Source)
end

function SESSION:IsSelected(Idx)
    return self.Selected[Idx] == true
end

function SESSION:GetSelectedList()
    local List = table.GetKeys(self.Selected)
    table.sort(List)
    return List
end

function SESSION:SelectionCount()
    return table.Count(self.Selected)
end

function SESSION:FocusConstraint(Idx)
    self.ActiveConstraint = Idx
    self:Emit("FocusChanged")
end

-- Visibility (3D view only, not saved)

function SESSION:SetHidden(List, Hidden)
    for _, Idx in ipairs(List) do
        self.Hidden[Idx] = Hidden or nil
    end
    self:Emit("VisibilityChanged")
end

function SESSION:Isolate(List)
    table.Empty(self.Hidden)
    local Keep = {}
    for _, Idx in ipairs(List) do Keep[Idx] = true end
    for Idx in pairs(self.Dupe.Entities) do
        if not Keep[Idx] then self.Hidden[Idx] = true end
    end
    self:Emit("VisibilityChanged")
end

function SESSION:UnhideAll()
    table.Empty(self.Hidden)
    self:Emit("VisibilityChanged")
end

-- History

function SESSION:PushHistory(Entry)
    if self.Group then
        local Entries = self.Group.Entries
        Entries[#Entries + 1] = Entry
        return
    end

    local Stack = self.UndoStack
    Stack[#Stack + 1] = Entry
    if #Stack > 256 then table.remove(Stack, 1) end
    table.Empty(self.RedoStack)
    self:Emit("HistoryChanged")
end

function SESSION:BeginGroup(Label)
    if self.Group then
        self.Group.Depth = self.Group.Depth + 1
        return
    end
    self.Group = {Label = Label, Entries = {}, Depth = 1}
end

function SESSION:EndGroup()
    local Group = self.Group
    if not Group then return end
    Group.Depth = Group.Depth - 1
    if Group.Depth > 0 then return end
    self.Group = nil

    local Entries = Group.Entries
    if #Entries == 0 then return end
    if #Entries == 1 then
        Entries[1].Label = Group.Label or Entries[1].Label
        Entries[1].Tbl = nil
        return self:PushHistory(Entries[1])
    end

    self:PushHistory({
        Label = Group.Label,
        Undo  = function()
            for I = #Entries, 1, -1 do Entries[I].Undo() end
        end,
        Redo  = function()
            for I = 1, #Entries do Entries[I].Redo() end
        end,
    })
end

function SESSION:Batch(Label, Fn, ...)
    self:BeginGroup(Label)
    local Ok, Err = xpcall(Fn, debug.traceback, ...)
    self:EndGroup()
    if not Ok then ErrorNoHalt(Err .. "\n") end
end

-- Every edit from the UI goes through here so it can be undone
function SESSION:Set(Tbl, Key, Value)
    local Old = Tbl[Key]
    if Old == Value and type(Old) == type(Value) then return end
    Tbl[Key] = Value

    local Now  = RealTime()
    local Last = not self.Group and self.UndoStack[#self.UndoStack]
    if Last and Last.Tbl == Tbl and Last.Key == Key and Now - Last.Time < 1 then
        Last.New  = Value
        Last.Time = Now
    else
        local Entry = {Tbl = Tbl, Key = Key, Old = Old, New = Value, Time = Now, Label = "Edit " .. tostring(Key)}
        Entry.Undo = function() Tbl[Key] = Entry.Old end
        Entry.Redo = function() Tbl[Key] = Entry.New end
        self:PushHistory(Entry)
    end

    self:MarkDirty()
    self:Emit("ValueChanged", Tbl, Key)
end

function SESSION:CanUndo() return #self.UndoStack > 0 end
function SESSION:CanRedo() return #self.RedoStack > 0 end

function SESSION:Undo()
    local Entry = table.remove(self.UndoStack)
    if not Entry then return end
    Entry.Undo()
    self.RedoStack[#self.RedoStack + 1] = Entry
    self:AfterHistory()
end

function SESSION:Redo()
    local Entry = table.remove(self.RedoStack)
    if not Entry then return end
    Entry.Redo()
    self.UndoStack[#self.UndoStack + 1] = Entry
    self:AfterHistory()
end

function SESSION:AfterHistory()
    for Idx in pairs(self.Selected) do
        if not self.Dupe.Entities[Idx] then self.Selected[Idx] = nil end
    end
    if self.Primary and not self.Selected[self.Primary] then self.Primary = next(self.Selected) end
    if self.ActiveConstraint and not self.Dupe.Constraints[self.ActiveConstraint] then self.ActiveConstraint = nil end

    self:MarkDirty()
    self:Emit("HistoryChanged")
    self:Emit("StructureChanged")
    self:Emit("SelectionChanged")
    self:Emit("FocusChanged")
end

-- Records a structural change that can't be expressed as Set calls
function SESSION:Apply(Label, Do, Undo)
    Do()
    self:PushHistory({Label = Label, Undo = Undo, Redo = Do})
    self:MarkDirty()
end

-- Queries

function SESSION:ConstraintRefs(Constraint)
    local Refs = {}
    if not istable(Constraint.Entity) then return Refs end
    for I = 1, 4 do
        local Ent = Constraint.Entity[I]
        if istable(Ent) and Ent.Index and not Ent.World and Ent.Index ~= 0 then
            Refs[#Refs + 1] = Ent.Index
        end
    end
    return Refs
end

function SESSION:GetConstraintsOf(Idx)
    local Out = {}
    for I, Constraint in ipairs(self.Dupe.Constraints) do
        for _, Ref in ipairs(self:ConstraintRefs(Constraint)) do
            if Ref == Idx then
                Out[#Out + 1] = I
                break
            end
        end
    end
    return Out
end

function SESSION:GetParent(Idx)
    local EntData = self.Dupe.Entities[Idx]
    local Info = EntData and EntData.BuildDupeInfo
    return Info and Info.DupeParentID
end

function SESSION:GetChildrenMap()
    local Map = {}
    for Idx in pairs(self.Dupe.Entities) do
        local Parent = self:GetParent(Idx)
        if Parent then
            Map[Parent] = Map[Parent] or {}
            table.insert(Map[Parent], Idx)
        end
    end
    return Map
end

-- Adds every descendant (through parenting) of the given entities
function SESSION:WithDescendants(List)
    local Map = self:GetChildrenMap()
    local Seen, Out = {}, {}
    local function Add(Idx)
        if Seen[Idx] then return end
        Seen[Idx] = true
        Out[#Out + 1] = Idx
        for _, Child in ipairs(Map[Idx] or {}) do Add(Child) end
    end
    for _, Idx in ipairs(List) do Add(Idx) end
    return Out
end

-- Everything connected through constraints and parenting
function SESSION:GetConnected(List)
    local Ents = self.Dupe.Entities
    local Links = {}
    local function Link(A, B)
        if not Ents[A] or not Ents[B] then return end
        Links[A] = Links[A] or {}
        Links[B] = Links[B] or {}
        Links[A][B] = true
        Links[B][A] = true
    end
    for _, Constraint in ipairs(self.Dupe.Constraints) do
        local Refs = self:ConstraintRefs(Constraint)
        for I = 2, #Refs do Link(Refs[1], Refs[I]) end
    end
    for Idx in pairs(Ents) do
        local Parent = self:GetParent(Idx)
        if Parent then Link(Idx, Parent) end
    end

    local Seen, Out, Queue = {}, {}, {}
    for _, Idx in ipairs(List) do Queue[#Queue + 1] = Idx end
    while #Queue > 0 do
        local Idx = table.remove(Queue)
        if not Seen[Idx] then
            Seen[Idx] = true
            Out[#Out + 1] = Idx
            for Other in pairs(Links[Idx] or {}) do
                if not Seen[Other] then Queue[#Queue + 1] = Other end
            end
        end
    end
    return Out
end

function SESSION:GetEntitiesOfClass(Class)
    local Out = {}
    for Idx, EntData in pairs(self.Dupe.Entities) do
        if EntData.Class == Class then Out[#Out + 1] = Idx end
    end
    table.sort(Out)
    return Out
end

function SESSION:NextFreeIndex()
    local Max = 0
    for Idx in pairs(self.Dupe.Entities) do
        if isnumber(Idx) and Idx > Max then Max = Idx end
    end
    return Max + 1
end

function SESSION:ResolvePath(Root, Path)
    local Tbl = Root
    for I = 1, #Path - 1 do
        Tbl = Tbl[Path[I]]
        if not istable(Tbl) then return end
    end
    return Tbl, Path[#Path]
end

-- Structural edits

function SESSION:RemoveEntities(List)
    local Ents = self.Dupe.Entities
    local Cons = self.Dupe.Constraints
    local Head = self.Dupe.HeadEnt

    local Removed = {}
    local Count = 0
    for _, Idx in ipairs(List) do
        if Ents[Idx] then
            Removed[Idx] = Ents[Idx]
            Count = Count + 1
        end
    end
    if Count == 0 then return 0, 0 end

    local RemovedCons = {}
    for I, Constraint in ipairs(Cons) do
        for _, Ref in ipairs(self:ConstraintRefs(Constraint)) do
            if Removed[Ref] then
                RemovedCons[#RemovedCons + 1] = {I, Constraint}
                break
            end
        end
    end

    local OldHead = Head.Index
    local NewHead = OldHead
    if Removed[OldHead] then
        NewHead = nil
        for _, Idx in ipairs(DupeEditor.SortedKeys(Ents)) do
            if not Removed[Idx] then NewHead = Idx break end
        end
    end

    self:Apply("Delete " .. Count .. " entities", function()
        for Idx in pairs(Removed) do
            Ents[Idx] = nil
            self.Selected[Idx] = nil
            self.Hidden[Idx] = nil
        end
        for I = #RemovedCons, 1, -1 do
            table.remove(Cons, RemovedCons[I][1])
        end
        Head.Index = NewHead
    end, function()
        for Idx, EntData in pairs(Removed) do Ents[Idx] = EntData end
        for I = 1, #RemovedCons do
            table.insert(Cons, RemovedCons[I][1], RemovedCons[I][2])
        end
        Head.Index = OldHead
    end)

    if self.Primary and not self.Selected[self.Primary] then self.Primary = next(self.Selected) end
    self.ActiveConstraint = nil
    self:Emit("StructureChanged")
    self:Emit("SelectionChanged")
    self:Emit("FocusChanged")

    return Count, #RemovedCons
end

function SESSION:RemoveConstraints(List)
    local Cons = self.Dupe.Constraints
    table.sort(List)
    local Removed = {}
    for _, I in ipairs(List) do
        if Cons[I] then Removed[#Removed + 1] = {I, Cons[I]} end
    end
    if #Removed == 0 then return end

    self:Apply("Delete " .. #Removed .. " constraints", function()
        for I = #Removed, 1, -1 do table.remove(Cons, Removed[I][1]) end
    end, function()
        for I = 1, #Removed do table.insert(Cons, Removed[I][1], Removed[I][2]) end
    end)

    self.ActiveConstraint = nil
    self:Emit("StructureChanged")
    self:Emit("FocusChanged")
end

local function RemapWire(Wire, Map)
    if not istable(Wire) then return end
    if Map[Wire.Src] then Wire.Src = Map[Wire.Src] end
    if not istable(Wire.Path) then return end
    for _, Point in pairs(Wire.Path) do
        if istable(Point) and Map[Point.Entity] then Point.Entity = Map[Point.Entity] end
    end
end

local function RemapWires(EntData, Map)
    local Mods = EntData.EntityMods
    if not Mods then return end
    for _, Key in ipairs({"WireDupeInfo", "SFDupeInfo"}) do
        local Wires = istable(Mods[Key]) and Mods[Key].Wires
        if istable(Wires) then
            for _, Wire in pairs(Wires) do RemapWire(Wire, Map) end
        end
    end
end

function SESSION:DuplicateEntities(List, Offset)
    local Ents = self.Dupe.Entities
    local Cons = self.Dupe.Constraints
    Offset = Offset or Vector()

    local Map, NewList = {}, {}
    local Next = self:NextFreeIndex()
    for _, Idx in ipairs(List) do
        if Ents[Idx] then
            Map[Idx] = Next
            NewList[#NewList + 1] = Next
            Next = Next + 1
        end
    end
    if #NewList == 0 then return {} end

    local Copies = {}
    for Old, New in pairs(Map) do
        local Copy = table.Copy(Ents[Old])
        local Phys = Copy.PhysicsObjects and Copy.PhysicsObjects[0]
        if Phys and Phys.Pos then Phys.Pos = Phys.Pos + Offset end
        local Parent = Copy.BuildDupeInfo and Copy.BuildDupeInfo.DupeParentID
        if Parent and Map[Parent] then Copy.BuildDupeInfo.DupeParentID = Map[Parent] end
        RemapWires(Copy, Map)
        Copies[New] = Copy
    end

    local NewCons = {}
    for _, Constraint in ipairs(Cons) do
        local Refs = self:ConstraintRefs(Constraint)
        local All = #Refs > 0
        for _, Ref in ipairs(Refs) do
            if not Map[Ref] then All = false break end
        end
        if All then
            local Copy = table.Copy(Constraint)
            for I = 1, 4 do
                local Ent = Copy.Entity[I]
                if istable(Ent) and Map[Ent.Index] then Ent.Index = Map[Ent.Index] end
            end
            NewCons[#NewCons + 1] = Copy
        end
    end

    local Start = #Cons
    self:Apply("Duplicate " .. #NewList .. " entities", function()
        for Idx, Copy in pairs(Copies) do Ents[Idx] = Copy end
        for I, Copy in ipairs(NewCons) do Cons[Start + I] = Copy end
    end, function()
        for Idx in pairs(Copies) do Ents[Idx] = nil end
        for I = #NewCons, 1, -1 do table.remove(Cons, Start + I) end
    end)

    self:Emit("StructureChanged")
    self:SetSelection(NewList)
    return NewList
end

-- Moves and/or rotates entities (and their parented children) around Pivot
function SESSION:TransformEntities(List, Offset, Rotation, Pivot)
    local Ents = self.Dupe.Entities
    List = self:WithDescendants(List)
    Offset   = Offset or Vector()
    Rotation = Rotation or Angle()
    Pivot    = Pivot or self:GetCenter(List)

    local Old, New = {}, {}
    for _, Idx in ipairs(List) do
        local EntData = Ents[Idx]
        if EntData and istable(EntData.PhysicsObjects) then
            for Bone, Phys in pairs(EntData.PhysicsObjects) do
                if Phys.Pos and Phys.Angle then
                    Old[Phys] = {Vector(Phys.Pos), Angle(Phys.Angle)}
                    local Pos, Ang
                    if Bone == 0 then
                        local LPos, LAng = WorldToLocal(Phys.Pos, Phys.Angle, Pivot, angle_zero)
                        Pos, Ang = LocalToWorld(LPos, LAng, Pivot, Rotation)
                        Pos = Pos + Offset
                    else
                        Pos = LocalToWorld(Phys.Pos, angle_zero, vector_origin, Rotation)
                        Ang = select(2, LocalToWorld(vector_origin, Phys.Angle, vector_origin, Rotation))
                    end
                    New[Phys] = {Pos, Ang}
                end
            end
        end
    end
    if next(Old) == nil then return end

    local function Write(Set)
        for Phys, Data in pairs(Set) do
            Phys.Pos   = Vector(Data[1])
            Phys.Angle = Angle(Data[2])
        end
    end

    self:Apply("Move " .. #List .. " entities", function() Write(New) end, function() Write(Old) end)
    self:Emit("StructureChanged")
    self:Emit("FocusChanged")
end

function SESSION:GetCenter(List)
    local Sum, Count = Vector(), 0
    for _, Idx in ipairs(List) do
        local EntData = self.Dupe.Entities[Idx]
        if EntData then
            Sum = Sum + DupeEditor.GetTransform(EntData)
            Count = Count + 1
        end
    end
    return Count > 0 and Sum / Count or Sum
end

function SESSION:SetHead(Idx)
    if not self.Dupe.Entities[Idx] then return end
    self:Set(self.Dupe.HeadEnt, "Index", Idx)
    self:Emit("StructureChanged")
end

-- Search through every entity's data. Opts = {Keys, Values, Selected, Max}
function SESSION:Search(Query, Opts)
    Opts = Opts or {}
    Query = string.lower(Query)
    local Results = {}
    if Query == "" then return Results end

    local Max = Opts.Max or 1000
    local IsBinary = DupeEditor.IsBinary

    local function Walk(EntIdx, Tbl, Path, Depth)
        if Depth > 24 then return end
        for _, Key in ipairs(DupeEditor.SortedKeys(Tbl)) do
            if #Results >= Max then return end
            local Value = Tbl[Key]
            local NewPath = {unpack(Path)}
            NewPath[#NewPath + 1] = Key

            local Hit = Opts.Keys ~= false and string.find(string.lower(tostring(Key)), Query, 1, true)
            if not Hit and Opts.Values ~= false and not istable(Value) then
                if isstring(Value) then
                    Hit = not IsBinary(Value) and string.find(string.lower(Value), Query, 1, true)
                else
                    Hit = string.find(string.lower(tostring(Value)), Query, 1, true)
                end
            end
            if Hit then
                Results[#Results + 1] = {Entity = EntIdx, Path = NewPath, Value = Value}
            end
            if istable(Value) then Walk(EntIdx, Value, NewPath, Depth + 1) end
        end
    end

    for _, Idx in ipairs(DupeEditor.SortedKeys(self.Dupe.Entities)) do
        if #Results >= Max then break end
        if not Opts.Selected or self.Selected[Idx] then
            Walk(Idx, self.Dupe.Entities[Idx], {}, 0)
        end
    end
    return Results
end

-- Encoding

function SESSION:BuildDupeTable()
    local Dupe = self.Dupe
    return {Entities = Dupe.Entities, Constraints = Dupe.Constraints, HeadEnt = Dupe.HeadEnt, Description = Dupe.Description}
end

function SESSION:Validate()
    if not AdvDupe2.CheckValidDupe then return true end
    local Ok, Err = AdvDupe2.CheckValidDupe(self:BuildDupeTable(), {})
    if Ok then return true end
    return false, Err
end

-- Header keys the encoder writes itself
DupeEditor.ReservedInfoKeys = {check = true, size = true}

-- Keeps the dupe's own header info (creator, date...) instead of restamping it
function SESSION:Encode(Callback)
    local Info = {}
    for Key, Value in pairs(self.Info) do
        if not DupeEditor.ReservedInfoKeys[Key] then
            local CleanKey = string.gsub(tostring(Key), "[]", "")
            local CleanValue = string.gsub(tostring(Value), "[]", "")
            Info[CleanKey] = CleanValue
        end
    end
    if next(Info) == nil then Info = AdvDupe2.GenerateDupeStamp(LocalPlayer()) end
    AdvDupe2.Encode(self:BuildDupeTable(), Info, Callback)
end

--------------------------------------------------------------------------------
-- Shared entity menu (entity list, 3D view)
--------------------------------------------------------------------------------

function DupeEditor.AddEntityOptions(Menu, Session)
    local Selected = Session:GetSelectedList()
    local Count = #Selected
    local Primary = Session.Primary

    if Count == 0 then
        Menu:AddOption("Unhide All", function() Session:UnhideAll() end):SetIcon("icon16/lightbulb.png")
        return
    end

    Menu:AddOption("Focus in 3D View", function() Session:Emit("FocusRequest", Selected) end):SetIcon("icon16/zoom.png")
    Menu:AddOption("Hide", function() Session:SetHidden(Selected, true) end):SetIcon("icon16/lightbulb_off.png")
    Menu:AddOption("Isolate", function() Session:Isolate(Selected) end):SetIcon("icon16/lightbulb.png")
    Menu:AddOption("Unhide All", function() Session:UnhideAll() end):SetIcon("icon16/lightbulb_add.png")
    Menu:AddSpacer()

    local Sub, SubOption = Menu:AddSubMenu("Select")
    SubOption:SetIcon("icon16/cursor.png")
    Sub:AddOption("Whole Contraption", function()
        Session:SetSelection(Session:GetConnected(Selected), Primary)
    end):SetIcon("icon16/link.png")
    Sub:AddOption("Children", function()
        Session:SetSelection(Session:WithDescendants(Selected), Primary)
    end):SetIcon("icon16/arrow_down.png")
    if Primary and Session:GetParent(Primary) then
        Sub:AddOption("Parent", function()
            Session:Select(Session:GetParent(Primary))
        end):SetIcon("icon16/arrow_up.png")
    end
    if Primary then
        local Class = Session.Dupe.Entities[Primary].Class
        Sub:AddOption("All " .. tostring(Class), function()
            Session:SetSelection(Session:GetEntitiesOfClass(Class), Primary)
        end):SetIcon("icon16/bricks.png")
    end
    Sub:AddOption("Invert", function()
        local List = {}
        for Idx in pairs(Session.Dupe.Entities) do
            if not Session.Selected[Idx] then List[#List + 1] = Idx end
        end
        Session:SetSelection(List)
    end):SetIcon("icon16/arrow_switch.png")

    Menu:AddSpacer()
    if Primary and Count == 1 then
        Menu:AddOption("Set as Head Entity", function() Session:SetHead(Primary) end):SetIcon("icon16/star.png")
        Menu:AddOption("Copy Class", function() SetClipboardText(tostring(Session.Dupe.Entities[Primary].Class)) end):SetIcon("icon16/page_copy.png")
        Menu:AddOption("Copy Model", function() SetClipboardText(tostring(Session.Dupe.Entities[Primary].Model)) end):SetIcon("icon16/page_copy.png")
    end
    Menu:AddOption("Duplicate", function() Session:DuplicateEntities(Selected) end):SetIcon("icon16/page_white_copy.png")
    Menu:AddOption(Count == 1 and "Delete This Entity" or ("Delete " .. Count .. " Entities"), function()
        local _, Cons = Session:RemoveEntities(Selected)
        if Cons > 0 then DupeEditor.Notify("Removed " .. Cons .. " constraints too") end
    end):SetIcon("icon16/delete.png")
end

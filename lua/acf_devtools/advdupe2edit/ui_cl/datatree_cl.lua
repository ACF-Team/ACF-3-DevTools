local DupeEditor = ACF_DevTools.DupeEditor

local Modifiers = {}
DupeEditor.Modifiers = Modifiers

local function NewModifier(Name, Icon)
    local Def = {}
    Modifiers[Name] = Def
    Def.Name = Name
    Def.Icon = Icon
    return Def
end

local function EnumModifier(Name, ENUM_PREFIX)
    ENUM_PREFIX = ENUM_PREFIX .. "_"
    local LUT = {}
    for Key, Value in pairs(_G) do
        if isnumber(Value) and string.StartsWith(Key, ENUM_PREFIX) then
            LUT[Value] = Key
        end
    end

    local Def = NewModifier(Name, "icon16/collision_on.png")
    function Def.SelfLoadContents(Node, Key, Value, Session, Data)
        local Combo = Node:Add("DComboBox")
        Combo:Dock(RIGHT)
        Combo:DockMargin(4, 0, 4, 0)
        Combo:SetSize(200, 0)
        Combo:SetSortItems(false)
        local Values = table.GetKeys(LUT)
        table.sort(Values)
        for _, EnumValue in ipairs(Values) do
            Combo:AddChoice(LUT[EnumValue], EnumValue, EnumValue == Value)
        end
        if not LUT[Value] then Combo:SetValue(tostring(Value)) end
        function Combo:OnSelect(_, _, EnumValue)
            Session:Set(Data, Key, EnumValue)
        end
    end
    return Def
end

EnumModifier("CollisionGroup", "COLLISION_GROUP")

local StandardIcons = {}
-- These are only used if the modifiers/class specific stuff isn't caught
StandardIcons.Angle                = "icon16/arrow_rotate_anticlockwise.png"
StandardIcons.Frozen               = "icon16/weather_snow.png"
StandardIcons.Pos                  = "icon16/map_go.png"
StandardIcons.Position             = "icon16/map_go.png"
StandardIcons.Args                 = "icon16/sitemap.png"
StandardIcons.Class                = "icon16/application_osx_terminal.png"
StandardIcons.Model                = "icon16/user_gray.png"
StandardIcons.PhysicsObjects       = "icon16/folder_brick.png"
StandardIcons.EntityMods           = "icon16/wrench.png"
StandardIcons.BuildDupeInfo        = "icon16/brick_edit.png"
StandardIcons.Wires                = "icon16/connect.png"
StandardIcons.DupeParentID         = "icon16/arrow_up.png"
StandardIcons.colour               = "icon16/color_wheel.png"
StandardIcons.Color                = "icon16/color_wheel.png"
StandardIcons.material             = "icon16/picture.png"

local TypeIcons = {
    number = "icon16/text_list_numbers.png",
    string = "icon16/text_signature.png",
    boolean = "icon16/accept.png",
    table = "icon16/table.png",
    Vector = "icon16/map_go.png",
    Angle = "icon16/arrow_rotate_anticlockwise.png",
}

local R_COLOR = Color(255, 150, 150)
local G_COLOR = Color(150, 255, 150)
local B_COLOR = Color(150, 150, 255)

local R_BORDER_COLOR = Color(50, 30, 30)
local G_BORDER_COLOR = Color(30, 50, 30)
local B_BORDER_COLOR = Color(30, 30, 50)

local function ProduceSimpleBGPaint(C, B)
    return function(self, W, H)
        surface.SetDrawColor(C)
        surface.DrawRect(0, 0, W, H)
        surface.SetDrawColor(B)
        surface.DrawOutlinedRect(0, 0, W, H)

        DNumberWang.Paint(self, W, H)
    end
end

local function CreateInputPanel(Parent, Insides)
    local Panel = Parent:Add("DPanel")
    Panel:SetPaintBackground(false)
    Panel:DockMargin(4, 0, 4, 0)
    Panel:SetSize(200, 0)
    Panel:Dock(RIGHT)

    local Element
    if Insides then
        Element = Panel:Add(Insides)
        Element:Dock(FILL)
    end

    return Panel, Element
end

local function NewWang(Parent)
    local Wang = Parent:Add("DNumberWang")
    Wang:SetMin(-math.huge)
    Wang:SetMax(math.huge)
    Wang:SetDecimals(4)
    return Wang
end

local function PathKey(Path)
    local Parts = {}
    for I, Key in ipairs(Path) do
        Parts[I] = (isnumber(Key) and "#" or "") .. tostring(Key)
    end
    return table.concat(Parts, "/")
end
DupeEditor.PathKey = PathKey

local function CopyValue(Value)
    if istable(Value) then return table.Copy(Value) end
    if isvector(Value) then return Vector(Value) end
    if isangle(Value) then return Angle(Value) end
    return Value
end
DupeEditor.CopyValue = CopyValue

local function PrettyValue(Value)
    if isstring(Value) then
        if DupeEditor.IsBinary(Value) then return "<binary, " .. string.NiceSize(#Value) .. ">" end
        if #Value > 80 then return string.sub(Value, 1, 80) .. "..." end
        return Value
    end
    if isnumber(Value) then return tostring(math.Round(Value, 4)) end
    if isvector(Value) or isangle(Value) then
        return string.format("%.2f %.2f %.2f", Value[1], Value[2], Value[3])
    end
    if istable(Value) then return "{" .. table.Count(Value) .. "}" end
    return tostring(Value)
end
DupeEditor.PrettyValue = PrettyValue

-- Puts a small widget on the first line of a node that can have children
local function AttachLineWidget(Node, Widget, Width)
    local OldLayout = Node.PerformLayout
    function Node:PerformLayout(W, H)
        OldLayout(self, W, H)
        local Line = self:GetLineHeight()
        Widget:SetPos(self:GetWide() - Width - 8, 1)
        Widget:SetSize(Width, Line - 2)
    end
end

local TREE = {}

function DupeEditor.CreateDataTree(Parent, Session)
    local Tree = Parent:Add("DTree")
    for Key, Value in pairs(TREE) do
        Tree[Key] = Value
    end
    Tree.Session     = Session
    Tree.Expanded    = {}
    Tree.NodesByPath = {}
    return Tree
end

-- Kind is "Entity" or "Constraint". Index is the entity/constraint index.
function TREE:SetData(Data, Kind, Index)
    self.Data  = Data
    self.Kind  = Kind
    self.Index = Index
    self:RebuildTree()
end

function TREE:RebuildTree()
    self:Clear()
    table.Empty(self.NodesByPath)
    if istable(self.Data) then
        self:AddNodes(self, self.Data, {})
    end

    self:InvalidateLayout()
end

function TREE:CollapseAll()
    table.Empty(self.Expanded)
    self:RebuildTree()
end

function TREE:Reveal(Path)
    for I = 1, #Path - 1 do
        self.Expanded[PathKey({unpack(Path, 1, I)})] = true
    end
    self:RebuildTree()

    local Node = self.NodesByPath[PathKey(Path)]
    if not IsValid(Node) then return end
    self:SetSelectedItem(Node)
    timer.Simple(0, function()
        if IsValid(self) and IsValid(Node) then self:ScrollToChild(Node) end
    end)
end

function TREE:AddNodes(Parent, Data, Path)
    for _, Key in ipairs(DupeEditor.SortedKeys(Data)) do
        self:AddValueNode(Parent, Data, Key, Path)
    end
end

function TREE:AddValueNode(Parent, Data, Key, ParentPath)
    local Session = self.Session
    local Value = Data[Key]
    local T = type(Value)

    local Path = {unpack(ParentPath)}
    Path[#Path + 1] = Key
    local PathStr = PathKey(Path)

    local Interpreter = #ParentPath == 0 and Modifiers[Key] or nil
    local Icon = Interpreter and Interpreter.Icon or StandardIcons[Key] or TypeIcons[T] or "icon16/bullet_black.png"

    local Label = tostring(Key)
    if T == "table" then Label = Label .. "  [" .. table.Count(Value) .. "]" end

    local Node = Parent:AddNode(Label, Icon)
    Node:DockMargin(0, 2, 0, 2)
    Node.DataTable = Data
    Node.DataKey   = Key
    Node.DataPath  = Path
    self.NodesByPath[PathStr] = Node

    function Node.DoRightClick()
        self:OpenNodeMenu(Node)
        return true
    end

    if Interpreter and Interpreter.SelfLoadContents then
        Interpreter.SelfLoadContents(Node, Key, Value, Session, Data)
        return Node
    end

    if T == "table" then
        self:BuildTableNode(Node, Data, Key, Value, Path, PathStr)
    elseif T == "number" then
        self:BuildNumberNode(Node, Data, Key, Value)
    elseif T == "string" then
        self:BuildStringNode(Node, Data, Key, Value)
    elseif T == "boolean" then
        local _, Check = CreateInputPanel(Node, "DCheckBox")
        Check:SetChecked(Value)
        Check:Dock(RIGHT)
        Check:DockMargin(0, 1, 0, 1)
        Check:SetSize(14, 0)

        function Check:OnChange(V)
            Session:Set(Data, Key, V)
        end
    elseif T == "Vector" or T == "Angle" then
        self:BuildVectorNode(Node, Data, Key, Value)
    else
        local _, Lbl = CreateInputPanel(Node, "DLabel")
        Lbl:SetText(tostring(Value))
        Lbl:SetDark(true)
    end

    return Node
end

function TREE:BuildTableNode(Node, Data, Key, Value, Path, PathStr)
    if DupeEditor.IsColorTable(Value) then
        local Swatch = Node:Add("DButton")
        Swatch:SetText("")
        Swatch:SetTooltip("Edit Color")
        function Swatch:Paint(W, H)
            local Col = Data[Key]
            if not istable(Col) then return end
            surface.SetDrawColor(Col.r or 255, Col.g or 255, Col.b or 255, 255)
            surface.DrawRect(0, 0, W, H)
            surface.SetDrawColor(0, 0, 0, 180)
            surface.DrawOutlinedRect(0, 0, W, H)
        end
        Swatch.DoClick = function() self:OpenColorEditor(Data, Key) end
        AttachLineWidget(Node, Swatch, 48)
    end

    if next(Value) == nil then return end

    Node:SetForceShowExpander(true)
    local Loaded = false
    local OldSetExpanded = Node.SetExpanded
    function Node.SetExpanded(Pnl, Expand, NoAnim)
        if Expand and not Loaded then
            Loaded = true
            self:AddNodes(Pnl, Value, Path)
        end
        self.Expanded[PathStr] = Expand or nil
        return OldSetExpanded(Pnl, Expand, NoAnim)
    end
    function Node.DoClick(Pnl)
        Pnl:SetExpanded(not Pnl:GetExpanded())
        return true
    end

    if self.Expanded[PathStr] then Node:SetExpanded(true, true) end
end

function TREE:BuildNumberNode(Node, Data, Key, Value)
    local Session = self.Session
    local Inner, Text = CreateInputPanel(Node, "DNumberWang")
    Text:SetMin(-math.huge)
    Text:SetMax(math.huge)
    Text:SetDecimals(4)
    Text:SetValue(Value)

    local PutNaN = Inner:Add("DButton")
    local PutInf = Inner:Add("DButton")
    PutNaN:Dock(RIGHT)
    PutNaN:SetSize(28, 0)
    PutNaN:SetText("NaN")

    PutInf:Dock(RIGHT)
    PutInf:SetSize(28, 0)
    PutInf:SetText("Inf")

    function PutNaN:DoClick()
        Text:SetText("nan")
        Session:Set(Data, Key, 0 / 0)
    end

    function PutInf:DoClick()
        Text:SetText("inf")
        Session:Set(Data, Key, 1 / 0)
    end

    if DupeEditor.RefKeys[Key] and Session.Dupe.Entities[Value] then
        local Go = Inner:Add("DImageButton")
        Go:Dock(RIGHT)
        Go:DockMargin(2, 1, 0, 1)
        Go:SetSize(16, 0)
        Go:SetStretchToFit(false)
        Go:SetImage("icon16/arrow_right.png")
        Go:SetTooltip("Go to entity [" .. Value .. "] " .. tostring(Session.Dupe.Entities[Value].Class))
        function Go:DoClick()
            local Target = Data[Key]
            if Session.Dupe.Entities[Target] then Session:Select(Target) end
        end
    end

    Text:MoveToFront()
    function Text:OnValueChanged(V)
        Session:Set(Data, Key, V)
    end
end

function TREE:BuildStringNode(Node, Data, Key, Value)
    local Session = self.Session

    if DupeEditor.IsBinary(Value) then
        local Panel, Lbl = CreateInputPanel(Node, "DLabel")
        Lbl:SetDark(true)
        Lbl:SetText("<binary, " .. string.NiceSize(#Value) .. ">")
        Panel:SetTooltip("Binary data, can't edit it here")
        return
    end

    local Long = #Value > 200 or string.find(Value, "\n", 1, true)
    local Inner, Text = CreateInputPanel(Node, "DTextEntry")

    local More = Inner:Add("DButton")
    More:Dock(RIGHT)
    More:DockMargin(2, 0, 0, 0)
    More:SetSize(22, 0)
    More:SetText("...")
    More:SetTooltip("Edit in Window")
    function More.DoClick()
        DupeEditor.OpenTextWindow(tostring(Key), Data[Key], {
            OnApply = function(NewText)
                Session:Set(Data, Key, NewText)
                if IsValid(self) then self:RebuildTree() end
            end
        })
    end

    Text:MoveToFront()
    if Long then
        Text:SetText(PrettyValue(string.gsub(Value, "\n", " ")))
        Text:SetEditable(false)
        return
    end

    Text:SetText(Value)
    function Text:OnChange()
        Session:Set(Data, Key, self:GetText())
    end
end

function TREE:BuildVectorNode(Node, Data, Key, Value)
    local Session = self.Session
    local Ctor = isvector(Value) and Vector or Angle
    local X, Y, Z = Value:Unpack()

    local Inner, _ = CreateInputPanel(Node)
    local Z_Slider = NewWang(Inner)
    local Y_Slider = NewWang(Inner)
    local X_Slider = NewWang(Inner)

    local VPadding = 1
    function Inner:PerformLayout(W, H)
        local WidthPer  = (W / 3)
        local HeightPer = H - (VPadding * 2)
        X_Slider:SetPos(0, VPadding)
        X_Slider:SetSize(WidthPer, HeightPer)

        Y_Slider:SetPos(WidthPer, VPadding)
        Y_Slider:SetSize(WidthPer, HeightPer)

        Z_Slider:SetPos(WidthPer * 2, VPadding)
        Z_Slider:SetSize(WidthPer, HeightPer)
    end

    X_Slider:SetPaintBackground(false)
    Y_Slider:SetPaintBackground(false)
    Z_Slider:SetPaintBackground(false)
    X_Slider.Paint = ProduceSimpleBGPaint(R_COLOR, R_BORDER_COLOR)
    Y_Slider.Paint = ProduceSimpleBGPaint(G_COLOR, G_BORDER_COLOR)
    Z_Slider.Paint = ProduceSimpleBGPaint(B_COLOR, B_BORDER_COLOR)

    X_Slider:SetValue(X)
    Y_Slider:SetValue(Y)
    Z_Slider:SetValue(Z)

    -- Replace instead of mutate, so undo keeps the old one
    local function Write(Component, V)
        local New = Ctor(Data[Key])
        New[Component] = V
        Session:Set(Data, Key, New)
    end

    function X_Slider:OnValueChanged(V) Write(1, V) end
    function Y_Slider:OnValueChanged(V) Write(2, V) end
    function Z_Slider:OnValueChanged(V) Write(3, V) end
end

function TREE:OpenColorEditor(Data, Key)
    local Session = self.Session
    local Frame = vgui.Create("DFrame")
    Frame:SetTitle("Color - " .. tostring(Key))
    Frame:SetSize(300, 260)
    Frame:Center()
    Frame:MakePopup()

    local Mixer = Frame:Add("DColorMixer")
    Mixer:Dock(FILL)
    Mixer:SetAlphaBar(true)
    local Col = Data[Key]
    Mixer:SetColor(Color(Col.r or 255, Col.g or 255, Col.b or 255, Col.a or 255))

    function Mixer.ValueChanged(_, New)
        local Copy = table.Copy(Data[Key])
        Copy.r, Copy.g, Copy.b, Copy.a = New.r, New.g, New.b, New.a
        Session:Set(Data, Key, Copy)
    end

    function Frame.OnClose()
        if IsValid(self) then self:RebuildTree() end
    end
end

local AddTypes = {
    {"String",  "icon16/text_signature.png",            function() return "" end},
    {"Number",  "icon16/text_list_numbers.png",         function() return 0 end},
    {"Boolean", "icon16/accept.png",                    function() return false end},
    {"Vector",  "icon16/map_go.png",                    function() return Vector() end},
    {"Angle",   "icon16/arrow_rotate_anticlockwise.png", function() return Angle() end},
    {"Table",   "icon16/table.png",                     function() return {} end},
    {"Color",   "icon16/color_wheel.png",               function() return {r = 255, g = 255, b = 255, a = 255} end},
}

function TREE:PromptAddKey(Tbl, Path, MakeDefault)
    Derma_StringRequest("Add Key", "Key name (numbers become number keys)", "", function(Text)
        local NewKey = tonumber(Text) or Text
        if NewKey == "" or Tbl[NewKey] ~= nil then
            DupeEditor.Notify("Bad key (empty or already exists)", NOTIFY_ERROR)
            return
        end
        self.Session:Set(Tbl, NewKey, MakeDefault())
        self.Expanded[PathKey(Path)] = true
        self:RebuildTree()
    end)
end

-- Writes Value at the same path on every other selected entity that has it
function TREE:ApplyToSelection(Value, Path)
    local Session = self.Session
    local Ents = Session.Dupe.Entities
    local Applied = 0
    Session:BeginGroup("Apply " .. tostring(Path[#Path]) .. " to selection")
    for Idx in pairs(Session.Selected) do
        local Tbl, Key
        if Idx ~= self.Index and Ents[Idx] then Tbl, Key = Session:ResolvePath(Ents[Idx], Path) end
        if Tbl then
            Session:Set(Tbl, Key, CopyValue(Value))
            Applied = Applied + 1
        end
    end
    Session:EndGroup()
    return Applied
end

function TREE:OpenNodeMenu(Node)
    local Session = self.Session
    local Data, Key, Path = Node.DataTable, Node.DataKey, Node.DataPath
    local Value = Data[Key]
    local Menu = DermaMenu()

    Menu:AddOption("Copy Value", function()
        SetClipboardText(istable(Value) and DupeEditor.Serialize(Value) or tostring(Value))
    end):SetIcon("icon16/page_copy.png")
    Menu:AddOption("Copy as Lua", function()
        SetClipboardText(DupeEditor.Serialize(Value))
    end):SetIcon("icon16/script.png")
    Menu:AddOption("Copy Path", function()
        local Parts = {}
        for I, K in ipairs(Path) do
            Parts[I] = isnumber(K) and "[" .. K .. "]" or ("." .. tostring(K))
        end
        SetClipboardText(table.concat(Parts))
    end):SetIcon("icon16/link.png")

    if self.Kind == "Entity" and Session:SelectionCount() > 1 then
        Menu:AddSpacer()
        local Others = Session:SelectionCount() - 1
        Menu:AddOption("Apply to " .. Others .. " Other Selected", function()
            local Applied = self:ApplyToSelection(Data[Key], Path)
            DupeEditor.Notify("Applied to " .. Applied .. " entities")
            Session:Emit("StructureChanged")
        end):SetIcon("icon16/table_multiple.png")
    end

    Menu:AddSpacer()
    if istable(Value) then
        local Sub, SubOption = Menu:AddSubMenu("Add Key")
        SubOption:SetIcon("icon16/add.png")
        for _, Def in ipairs(AddTypes) do
            Sub:AddOption(Def[1], function() self:PromptAddKey(Value, Path, Def[3]) end):SetIcon(Def[2])
        end
    end

    if isnumber(Value) and DupeEditor.RefKeys[Key] and Session.Dupe.Entities[Value] then
        Menu:AddOption("Go to Entity [" .. Value .. "]", function() Session:Select(Value) end):SetIcon("icon16/arrow_right.png")
    end

    Menu:AddOption("Delete Key", function()
        Session:Set(Data, Key, nil)
        self:RebuildTree()
    end):SetIcon("icon16/delete.png")

    Menu:Open()
end

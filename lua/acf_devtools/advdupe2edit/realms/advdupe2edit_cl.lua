local DupeEditor = ACF_DevTools.DupeEditor

local OpenDupe

list.Set("DesktopWindows", "ACF_AdvDupe2_Editor", {
    title	= "Adv. Dupe 2 Editor",
    icon	= "materials/icon16/database_table.png",
    width	= 520,
    height	= 700,
    init	= function(_, window)
        window:Close()
        if IsValid(ACF_DevTools.CurrentAdvDupe2Notice) then
            ACF_DevTools.CurrentAdvDupe2Notice:Remove()
            ACF_DevTools.CurrentAdvDupe2Notice = nil
        end

        local AdvDupe2Notice = Derma_Message("Downloading...", "Adv. Dupe 2 Editor", "Hide Notice")
        ACF_DevTools.CurrentAdvDupe2Notice = AdvDupe2Notice

        RunConsoleCommand("start_advdupe2_download")
    end
})

local VALUE_COLOR = Color(40, 44, 52)

-- Label that truncates with an ellipsis
local function EllipsisLabel(Parent, Text)
    local Panel = Parent:Add("DPanel")
    Panel:SetPaintBackground(false)
    Panel:SetTooltip(Text)
    function Panel:Paint(W, H)
        surface.SetFont("DermaDefault")
        local Shown = Text
        if surface.GetTextSize(Shown) > W then
            local Len = #Shown
            while Len > 0 and surface.GetTextSize(string.sub(Shown, 1, Len) .. "...") > W do
                Len = Len - 1
            end
            Shown = string.sub(Shown, 1, Len) .. "..."
        end
        draw.SimpleText(Shown, "DermaDefault", 0, H / 2, VALUE_COLOR, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return Panel
end

local function AddSectionHeader(Parent, Text, Icon)
    local Header = Parent:Add("DPanel")
    Header:Dock(TOP)
    Header:DockMargin(0, 8, 0, 2)
    Header:SetTall(22)
    Header:SetPaintBackground(false)

    if Icon then
        local Img = Header:Add("DImage")
        Img:Dock(LEFT)
        Img:DockMargin(0, 3, 6, 3)
        Img:SetSize(16, 16)
        Img:SetImage(Icon)
    end

    local Lbl = Header:Add("DLabel")
    Lbl:Dock(FILL)
    Lbl:SetFont("ACF_DupeEditor_Header")
    Lbl:SetDark(true)
    Lbl:SetText(Text)
    return Header, Lbl
end

local function AddButton(Parent, Text, Icon, Fn)
    local Button = Parent:Add("DButton")
    Button:Dock(TOP)
    Button:DockMargin(0, 4, 0, 0)
    Button:SetTall(24)
    Button:SetText(Text)
    if Icon then Button:SetImage(Icon) end
    Button.DoClick = Fn
    return Button
end

local function AddRow(Parent, Label, Height)
    local Row = Parent:Add("DPanel")
    Row:Dock(TOP)
    Row:DockMargin(0, 4, 0, 0)
    Row:SetTall(Height or 22)
    Row:SetPaintBackground(false)

    local Lbl = Row:Add("DLabel")
    Lbl:Dock(LEFT)
    Lbl:SetWide(72)
    Lbl:SetDark(true)
    Lbl:SetText(Label)
    return Row
end

local function AddRowButton(Row, Text, Icon, Fn)
    local Button = Row:Add("DButton")
    Button:Dock(RIGHT)
    Button:DockMargin(4, 0, 0, 0)
    Button:SetText(Text)
    if Icon then Button:SetImage(Icon) end
    Button:SizeToContentsX(Icon and 30 or 20)
    Button.DoClick = Fn
    return Button
end

local function AddXYZ(Row)
    local Holder = Row:Add("DPanel")
    Holder:Dock(FILL)
    Holder:SetPaintBackground(false)
    local Wangs = {}
    for I = 1, 3 do
        local Wang = Holder:Add("DNumberWang")
        Wang:SetMin(-math.huge)
        Wang:SetMax(math.huge)
        Wang:SetDecimals(3)
        Wang:SetValue(0)
        Wangs[I] = Wang
    end
    function Holder:PerformLayout(W, H)
        local Each = (W - 8) / 3
        for I = 1, 3 do
            Wangs[I]:SetPos((I - 1) * (Each + 4), 0)
            Wangs[I]:SetSize(Each, H)
        end
    end
    return function() return Wangs[1]:GetValue(), Wangs[2]:GetValue(), Wangs[3]:GetValue() end
end

local function EncodeSubset(Session, List, Callback)
    local Ents = {}
    for _, Idx in ipairs(List) do
        Ents[Idx] = Session.Dupe.Entities[Idx]
    end
    local Fake = {Entities = Ents, Constraints = {}, HeadEnt = Session.Dupe.HeadEnt}
    AdvDupe2.Encode(Fake, AdvDupe2.GenerateDupeStamp(LocalPlayer()), Callback)
end

--------------------------------------------------------------------------------
-- File handling
--------------------------------------------------------------------------------

local function SaveAs(Session, Done)
    local Ok, Err = Session:Validate()
    if not Ok then
        Derma_Message("Can't save, the dupe is broken:\n" .. tostring(Err), "Adv. Dupe 2 Editor", "OK")
        return
    end

    local Folder = AdvDupe2.DataFolder or "advdupe2"
    Derma_StringRequest("Save As", "File name (goes in data/" .. Folder .. "/)", Session.Name, function(Name)
        Name = string.Trim(Name)
        if Name == "" then return end

        Session:Encode(function(Data)
            local Path = AdvDupe2.GetFilename(Folder .. "/" .. Name)
            if not Path then
                DupeEditor.Notify("File was not saved! (Too many files with that name)", NOTIFY_ERROR)
                return
            end

            file.CreateDir(string.GetPathFromFilename(Path))
            local Handle = file.Open(Path, "wb", "DATA")
            if not Handle then
                DupeEditor.Notify("File was not saved! (Could not open file for writing)", NOTIFY_ERROR)
                return
            end
            Handle:Write(Data)
            Handle:Close()

            Session.Name = string.StripExtension(string.GetFileFromFilename(Path))
            Session:ClearDirty()
            DupeEditor.Notify("Saved! (data/" .. Path .. ", " .. string.NiceSize(#Data) .. ")")
            if Done then Done() end
        end)
    end)
end

local function SendToServer(Session)
    local Ok, Err = Session:Validate()
    if not Ok then
        Derma_Message("Can't send, the dupe is broken:\n" .. tostring(Err), "Adv. Dupe 2 Editor", "OK")
        return
    end
    if AdvDupe2.Uploading then
        DupeEditor.Notify("Already uploading, hold on", NOTIFY_ERROR)
        return
    end

    local Notice = Derma_Message("Sending...", "Please wait", "Close Popup (does not cancel)")
    Session:Encode(function(Data)
        net.Start("AdvDupe2_ReceiveFile")
        net.WriteString(Session.Name)
        AdvDupe2.Uploading = net.WriteStream(Data, function()
            if AdvDupe2.ClearFileUpload then AdvDupe2.ClearFileUpload() else AdvDupe2.Uploading = false end
            if IsValid(Notice) then Notice:Remove() end
            notification.AddLegacy("OK!", NOTIFY_GENERIC, 5)
        end)
        net.SendToServer()
        Session:ClearDirty()
    end)
end

local function OpenWhenPossible(Dupe, Info, MoreInfo, Name)
    if OpenDupe(Dupe, Info, MoreInfo, Name) then return end

    -- We need to delay it. Not sure why, but it fixes a load issue
    local HookName = "TempOpenDupeDelay_" .. SysTime()
    hook.Add("OnContextMenuOpen", HookName, function()
        timer.Simple(0.05, function()
            if OpenDupe(Dupe, Info, MoreInfo, Name) then
                hook.Remove("OnContextMenuOpen", HookName)
            end
        end)
    end)
end

function DupeEditor.OpenFile(Path)
    local Data = file.Read(Path, "DATA")
    if not Data then
        DupeEditor.Notify("File could not be read", NOTIFY_ERROR)
        return
    end

    local Success, Dupe, Info, MoreInfo = AdvDupe2.Decode(Data)
    if not Success then
        DupeEditor.Notify("File could not be decoded. (" .. tostring(Dupe) .. ")", NOTIFY_ERROR)
        return
    end
    if Info.ad1 then
        DupeEditor.Notify("AD1 files aren't supported (re-copy it with AD2 first)", NOTIFY_ERROR)
        return
    end

    OpenWhenPossible(Dupe, Info, MoreInfo, string.StripExtension(string.GetFileFromFilename(Path)))
end

local function OpenFileDialog()
    local Frame = vgui.Create("DFrame")
    Frame:SetTitle("Open Dupe File")
    Frame:SetSize(math.min(760, ScrW() - 100), math.min(480, ScrH() - 100))
    Frame:Center()
    Frame:SetSizable(true)
    Frame:DockPadding(6, 30, 6, 6)
    Frame:MakePopup()

    local Hint = Frame:Add("DLabel")
    Hint:Dock(BOTTOM)
    Hint:DockMargin(0, 4, 0, 0)
    Hint:SetText("Double click a dupe to open it")

    local Browser = Frame:Add("DFileBrowser")
    Browser:Dock(FILL)
    Browser:SetPath("DATA")
    Browser:SetBaseFolder(AdvDupe2.DataFolder or "advdupe2")
    Browser:SetFileTypes("*.txt")
    Browser:SetOpen(true)
    function Browser.OnDoubleClick(_, Path)
        Frame:Close()
        DupeEditor.OpenFile(Path)
    end
end
DupeEditor.OpenFileDialog = OpenFileDialog

--------------------------------------------------------------------------------
-- Left side lists
--------------------------------------------------------------------------------

local function EntityLabel(Session, Idx)
    local EntData = Session.Dupe.Entities[Idx]
    if not EntData then return "[" .. tostring(Idx) .. "] missing!" end
    return "[" .. Idx .. "] " .. tostring(EntData.Class)
end

local function BuildEntityList(Parent, Session)
    local Panel = Parent:Add("DPanel")
    Panel:SetPaintBackground(false)

    local Search = Panel:Add("DTextEntry")
    Search:Dock(TOP)
    Search:DockMargin(0, 0, 0, 4)
    Search:SetPlaceholderText("Filter by index/class/model...")

    local List = Panel:Add("DListView")
    List:Dock(FILL)
    List:SetMultiSelect(true)
    List:AddColumn("#"):SetFixedWidth(44)
    List:AddColumn("Class")
    List:AddColumn("Model")

    local LinesByIdx = {}
    local Syncing = false

    local function ApplySelection()
        Syncing = true
        List:ClearSelection()
        for Idx in pairs(Session.Selected) do
            local Line = LinesByIdx[Idx]
            if IsValid(Line) then Line:SetSelected(true) end
        end
        Syncing = false

        local Line = LinesByIdx[Session.Primary]
        if IsValid(Line) then
            local _, Y = Line:GetPos()
            local Scroll = List.VBar:GetScroll()
            local View = List:GetTall() - 40
            if Y < Scroll or Y > Scroll + View then
                List.VBar:AnimateTo(Y - View / 2, 0.2)
            end
        end
    end

    local function Rebuild()
        List:Clear()
        table.Empty(LinesByIdx)
        local Filter = string.lower(string.Trim(Search:GetValue()))
        for _, Idx in ipairs(DupeEditor.SortedKeys(Session.Dupe.Entities)) do
            local EntData = Session.Dupe.Entities[Idx]
            local Class, Model = tostring(EntData.Class or "<?CLASSNAME?>"), tostring(EntData.Model or "")
            if Filter == "" or string.find(tostring(Idx), Filter, 1, true) or string.find(string.lower(Class), Filter, 1, true) or string.find(string.lower(Model), Filter, 1, true) then
                local Line = List:AddLine(Idx, Class, Model)
                Line:SetSortValue(1, Idx)
                Line.EntIdx = Idx
                LinesByIdx[Idx] = Line
            end
        end
        ApplySelection()
    end
    Panel.Rebuild = Rebuild

    function Search:OnChange() Rebuild() end

    local OldClickLine = List.OnClickLine
    function List.OnClickLine(Pnl, Line, Clear)
        if Pnl:GetMultiSelect() and input.IsKeyDown(KEY_LCONTROL) and Line:IsLineSelected() then
            Line:SetSelected(false)
        else
            OldClickLine(Pnl, Line, Clear)
        end
        Pnl.PrimaryLine = Line
        Pnl.SelectionDirty = true
    end

    function List:Think()
        if not self.SelectionDirty or Syncing then return end
        self.SelectionDirty = false
        local Out = {}
        for _, Line in ipairs(self:GetSelected()) do
            Out[#Out + 1] = Line.EntIdx
        end
        local Primary = IsValid(self.PrimaryLine) and self.PrimaryLine:IsLineSelected() and self.PrimaryLine.EntIdx or nil
        Session:SetSelection(Out, Primary, List)
    end

    function List.DoDoubleClick(_, _, Line)
        Session:Emit("FocusRequest", {Line.EntIdx})
    end

    function List.OnRowRightClick()
        List:Think()
        local Menu = DermaMenu()
        DupeEditor.AddEntityOptions(Menu, Session)
        Menu:Open()
    end

    Session:Listen("SelectionChanged", Panel, function(Source)
        if Source ~= List then ApplySelection() end
    end)
    Session:Listen("StructureChanged", Panel, Rebuild)
    Session:Listen("ValueChanged", Panel, function(_, Key)
        if Key == "Class" or Key == "Model" then Panel.NeedsRebuild = RealTime() end
    end)
    function Panel:Think()
        if self.NeedsRebuild and RealTime() - self.NeedsRebuild > 0.4 then
            self.NeedsRebuild = nil
            Rebuild()
        end
    end

    Rebuild()
    return Panel
end

local function BuildConstraintList(Parent, Session)
    local Panel = Parent:Add("DPanel")
    Panel:SetPaintBackground(false)

    local OnlySelected = Panel:Add("DCheckBoxLabel")
    OnlySelected:Dock(TOP)
    OnlySelected:DockMargin(2, 0, 0, 4)
    OnlySelected:SetText("Only show selected?")
    OnlySelected:SetDark(true)

    local List = Panel:Add("DListView")
    List:Dock(FILL)
    List:SetMultiSelect(true)
    List:AddColumn("#"):SetFixedWidth(36)
    List:AddColumn("Type")
    List:AddColumn("Ent 1")
    List:AddColumn("Ent 2")

    local function EntText(Constraint, I)
        local Ent = istable(Constraint.Entity) and Constraint.Entity[I]
        if not istable(Ent) then return "" end
        if Ent.World or Ent.Index == 0 then return "world" end
        return EntityLabel(Session, Ent.Index)
    end

    local function Rebuild()
        List:Clear()
        local Filter = OnlySelected:GetChecked() and Session.Selected or nil
        for I, Constraint in ipairs(Session.Dupe.Constraints) do
            local Show = true
            if Filter then
                Show = false
                for _, Ref in ipairs(Session:ConstraintRefs(Constraint)) do
                    if Filter[Ref] then Show = true break end
                end
            end
            if Show then
                local Line = List:AddLine(I, tostring(Constraint.Type), EntText(Constraint, 1), EntText(Constraint, 2))
                Line:SetSortValue(1, I)
                Line.ConstraintIdx = I
                if I == Session.ActiveConstraint then Line:SetSelected(true) end
            end
        end
    end
    Panel.Rebuild = Rebuild

    function OnlySelected:OnChange() Rebuild() end

    function List.OnRowSelected(_, _, Line)
        Session:FocusConstraint(Line.ConstraintIdx)
    end

    function List.OnRowRightClick(_, _, Line)
        local Selected = List:GetSelected()
        local Menu = DermaMenu()
        local Constraint = Session.Dupe.Constraints[Line.ConstraintIdx]
        if Constraint then
            Menu:AddOption("Select Entities", function()
                Session:SetSelection(Session:ConstraintRefs(Constraint))
            end):SetIcon("icon16/cursor.png")
            Menu:AddOption("Focus in 3D View", function()
                Session:Emit("FocusRequest", Session:ConstraintRefs(Constraint))
            end):SetIcon("icon16/zoom.png")
        end
        Menu:AddOption("Delete " .. #Selected .. " Constraint(s)", function()
            local Indices = {}
            for _, L in ipairs(Selected) do Indices[#Indices + 1] = L.ConstraintIdx end
            Session:RemoveConstraints(Indices)
        end):SetIcon("icon16/delete.png")
        Menu:Open()
    end

    Session:Listen("StructureChanged", Panel, Rebuild)
    Session:Listen("SelectionChanged", Panel, function()
        if OnlySelected:GetChecked() then Rebuild() end
    end)

    Rebuild()
    return Panel
end

local function BuildClassList(Parent, Session)
    local List = Parent:Add("DListView")
    List:SetMultiSelect(false)
    List:AddColumn("Class")
    List:AddColumn("Count"):SetFixedWidth(56)

    local function Rebuild()
        List:Clear()
        local Counts = {}
        for _, EntData in pairs(Session.Dupe.Entities) do
            local Class = tostring(EntData.Class)
            Counts[Class] = (Counts[Class] or 0) + 1
        end
        for Class, Count in pairs(Counts) do
            local Line = List:AddLine(Class, Count)
            Line:SetSortValue(2, Count)
            Line.Class = Class
        end
        List:SortByColumn(2, true)
    end

    function List.DoDoubleClick(_, _, Line)
        Session:SetSelection(Session:GetEntitiesOfClass(Line.Class))
    end

    function List.OnRowRightClick(_, _, Line)
        local Ents = Session:GetEntitiesOfClass(Line.Class)
        local Menu = DermaMenu()
        Menu:AddOption("Select All (" .. #Ents .. ")", function() Session:SetSelection(Ents) end):SetIcon("icon16/cursor.png")
        Menu:AddOption("Hide", function() Session:SetHidden(Ents, true) end):SetIcon("icon16/lightbulb_off.png")
        Menu:AddOption("Show", function() Session:SetHidden(Ents, false) end):SetIcon("icon16/lightbulb.png")
        Menu:AddOption("Isolate", function() Session:Isolate(Ents) end):SetIcon("icon16/lightbulb_add.png")
        Menu:AddSpacer()
        Menu:AddOption("Delete All " .. Line.Class, function()
            Derma_Query("Delete all " .. #Ents .. " " .. Line.Class .. " entities?", "Adv. Dupe 2 Editor", "Delete", function()
                local _, Cons = Session:RemoveEntities(Ents)
                if Cons > 0 then DupeEditor.Notify("Also removed " .. Cons .. " constraints.") end
            end, "Cancel")
        end):SetIcon("icon16/delete.png")
        Menu:Open()
    end

    Session:Listen("StructureChanged", List, Rebuild)
    Rebuild()
    return List
end

local function BuildSearch(Parent, Session, GetTree)
    local Panel = Parent:Add("DPanel")
    Panel:SetPaintBackground(false)

    local Top = Panel:Add("DPanel")
    Top:Dock(TOP)
    Top:SetTall(22)
    Top:SetPaintBackground(false)

    local Query = Top:Add("DTextEntry")
    Query:Dock(FILL)
    Query:SetPlaceholderText("Search...")

    local Go = Top:Add("DButton")
    Go:Dock(RIGHT)
    Go:DockMargin(4, 0, 0, 0)
    Go:SetWide(22)
    Go:SetText("")
    Go:SetImage("icon16/magnifier.png")
    Go:SetTooltip("Search")

    local Options = Panel:Add("DPanel")
    Options:Dock(TOP)
    Options:DockMargin(0, 4, 0, 4)
    Options:SetTall(16)
    Options:SetPaintBackground(false)

    local function Option(Text, Default)
        local Check = Options:Add("DCheckBoxLabel")
        Check:Dock(LEFT)
        Check:DockMargin(2, 0, 10, 0)
        Check:SetText(Text)
        Check:SetDark(true)
        Check:SetValue(Default)
        Check:SizeToContents()
        return Check
    end
    local Keys     = Option("Keys", true)
    local Values   = Option("Values", true)
    local Selected = Option("Selected only", false)

    local Bottom = Panel:Add("DPanel")
    Bottom:Dock(BOTTOM)
    Bottom:DockMargin(0, 4, 0, 0)
    Bottom:SetTall(22)
    Bottom:SetPaintBackground(false)

    local Replace = Bottom:Add("DTextEntry")
    Replace:Dock(FILL)
    Replace:SetPlaceholderText("Replace with...")

    local ReplaceButton = Bottom:Add("DButton")
    ReplaceButton:Dock(RIGHT)
    ReplaceButton:DockMargin(4, 0, 0, 0)
    ReplaceButton:SetText("Replace All")
    ReplaceButton:SizeToContentsX(16)

    local Results = Panel:Add("DListView")
    Results:Dock(FILL)
    Results:SetMultiSelect(false)
    Results:AddColumn("Ent"):SetFixedWidth(44)
    Results:AddColumn("Path")
    Results:AddColumn("Value")

    local Found = {}
    local function Run()
        Results:Clear()
        Found = Session:Search(Query:GetValue(), {Keys = Keys:GetChecked(), Values = Values:GetChecked(), Selected = Selected:GetChecked()})
        for _, Result in ipairs(Found) do
            local Parts = {}
            for I, K in ipairs(Result.Path) do Parts[I] = tostring(K) end
            local Line = Results:AddLine(Result.Entity, table.concat(Parts, "."), DupeEditor.PrettyValue(Result.Value))
            Line:SetSortValue(1, Result.Entity)
            Line.Result = Result
        end
        if #Found >= 1000 then DupeEditor.Notify("Too many results, only showing 1000") end
    end

    Go.DoClick = Run
    function Query:OnEnter() Run() end

    function Results.OnRowSelected(_, _, Line)
        local Result = Line.Result
        if not Session.Dupe.Entities[Result.Entity] then return end
        Session:Select(Result.Entity)
        local Tree = GetTree()
        if IsValid(Tree) then Tree:Reveal(Result.Path) end
    end

    function ReplaceButton.DoClick()
        local Find, With = Query:GetValue(), Replace:GetValue()
        if Find == "" then return end
        local Count = 0
        Session:Batch("Replace " .. Find, function()
            for _, Result in ipairs(Found) do
                local Root = Session.Dupe.Entities[Result.Entity]
                local Tbl, Key = Root and Session:ResolvePath(Root, Result.Path)
                local Value = Tbl and Tbl[Key]
                if isstring(Value) and not DupeEditor.IsBinary(Value) then
                    local New = DupeEditor.ReplaceInsensitive(Value, Find, With)
                    if New ~= Value then
                        Session:Set(Tbl, Key, New)
                        Count = Count + 1
                    end
                end
            end
        end)
        DupeEditor.Notify("Replaced " .. Count .. " values")
        Session:Emit("StructureChanged")
        Session:Emit("FocusChanged")
        Run()
    end

    return Panel
end

local function AddTextRow(Parent, Label, Get, Set)
    local Row = AddRow(Parent, Label)
    local Entry = Row:Add("DTextEntry")
    Entry:Dock(FILL)
    Entry:SetText(Get())
    function Entry:OnChange() Set(self:GetValue()) end
    function Entry:Refresh()
        if not self:HasFocus() then self:SetText(Get()) end
    end
    return Entry
end

local function BuildInformation(Parent, Session)
    local Panel = Parent:Add("DPanel")
    Panel:SetPaintBackground(false)

    local Form = Panel:Add("DPanel")
    Form:Dock(TOP)
    Form:SetTall(56)
    Form:SetPaintBackground(false)

    local NameEntry = AddTextRow(Form, "Name", function() return Session.Name end, function(Text)
        Session:Set(Session, "Name", Text)
    end)
    NameEntry:SetTooltip("File name for saving/sending")
    local DescEntry = AddTextRow(Form, "Description", function()
        return isstring(Session.Dupe.Description) and Session.Dupe.Description or ""
    end, function(Text)
        Session:Set(Session.Dupe, "Description", Text)
    end)

    local HeaderRow = AddRow(Panel, "")
    HeaderRow:DockMargin(0, 6, 0, 0)

    -- Header info and HeadEnt are edited in place through this
    local Proxy = {["Header Info"] = Session.Info, HeadEnt = Session.Dupe.HeadEnt}
    local InfoTree = DupeEditor.CreateDataTree(Panel, Session)
    InfoTree:Dock(TOP)
    InfoTree:DockMargin(0, 4, 0, 0)
    InfoTree:SetTall(190)
    InfoTree.Expanded["Header Info"] = true

    AddRowButton(HeaderRow, "Restamp", "icon16/user_edit.png", function()
        local Stamp = AdvDupe2.GenerateDupeStamp(LocalPlayer())
        Session:Batch("Restamp", function()
            for Key, Value in pairs(Stamp) do Session:Set(Session.Info, Key, tostring(Value)) end
        end)
        InfoTree:RebuildTree()
    end):SetTooltip("Set creator/date/time to you and now")
    AddRowButton(HeaderRow, "Add Key", "icon16/add.png", function()
        InfoTree:PromptAddKey(Session.Info, {"Header Info"}, function() return "" end)
    end)
    local HeaderLabel = HeaderRow:GetChildren()[1]
    HeaderLabel:SetFont("ACF_DupeEditor_Header")
    HeaderLabel:SetText("Header")
    HeaderLabel:SizeToContentsX()

    local Stats = Panel:Add("DTree")
    Stats:Dock(FILL)
    Stats:DockMargin(0, 4, 0, 0)

    local function Rebuild()
        NameEntry:Refresh()
        DescEntry:Refresh()
        InfoTree:SetData(Proxy, "Info")

        Stats:Clear()
        local Dupe = Session.Dupe
        local Models, P2M, Chips, Parented = {}, 0, 0, 0
        for Idx, EntData in pairs(Dupe.Entities) do
            Models[tostring(EntData.Model)] = true
            local Class = tostring(EntData.Class)
            if string.StartsWith(Class, "sent_prop2mesh") then P2M = P2M + 1 end
            if Class == "starfall_processor" or Class == "gmod_wire_expression2" then Chips = Chips + 1 end
            if Session:GetParent(Idx) then Parented = Parented + 1 end
        end

        local Root = Stats:AddNode("Stats", "icon16/chart_bar.png")
        Root:AddNode("Entities: " .. table.Count(Dupe.Entities), "icon16/bricks.png")
        Root:AddNode("Constraints: " .. #Dupe.Constraints, "icon16/link.png")
        Root:AddNode("Parented: " .. Parented, "icon16/arrow_join.png")
        Root:AddNode("Models: " .. table.Count(Models), "icon16/user_gray.png")
        Root:AddNode("E2s/Starfalls: " .. Chips, "icon16/script.png")
        Root:AddNode("P2M controllers: " .. P2M, "icon16/shape_group.png")
        Root:AddNode("Head: " .. EntityLabel(Session, Dupe.HeadEnt.Index), "icon16/star.png")
        if Session.FileSize then Root:AddNode("File size: " .. string.NiceSize(Session.FileSize), "icon16/disk.png") end
        Root:SetExpanded(true, true)

        if next(Session.MoreInfo) then
            local More = Stats:AddNode("AD1 Info", "icon16/note.png")
            for _, Key in ipairs(DupeEditor.SortedKeys(Session.MoreInfo)) do
                More:AddNode(tostring(Key) .. ": " .. DupeEditor.PrettyValue(Session.MoreInfo[Key]), "icon16/bullet_black.png")
            end
        end
    end

    Session:Listen("StructureChanged", Panel, Rebuild)
    Rebuild()
    return Panel
end

--------------------------------------------------------------------------------
-- Tools
--------------------------------------------------------------------------------

local function BuildEditorTools(Parent, Session)
    local Scroll = Parent:Add("DScrollPanel")
    Scroll:GetCanvas():DockPadding(6, 0, 6, 6)

    local _, SelLabel = AddSectionHeader(Scroll, "Selection", "icon16/cursor.png")
    function SelLabel:Think()
        local Count = Session:SelectionCount()
        if Count ~= self.LastCount then
            self.LastCount = Count
            self:SetText("Selection (" .. Count .. ")")
        end
    end

    local function NeedSelection()
        local List = Session:GetSelectedList()
        if #List == 0 then DupeEditor.Notify("Nothing selected", NOTIFY_ERROR) end
        return List
    end

    AddButton(Scroll, "Estimate Size of Selection", "icon16/calculator.png", function()
        local List = NeedSelection()
        if #List == 0 then return end
        EncodeSubset(Session, List, function(Data)
            Derma_Message("The estimated size is " .. string.NiceSize(#Data) .. ".")
        end)
    end)
    AddButton(Scroll, "Select Contraption", "icon16/link.png", function()
        local List = NeedSelection()
        if #List > 0 then Session:SetSelection(Session:GetConnected(List), Session.Primary) end
    end)
    AddButton(Scroll, "Duplicate Selected", "icon16/page_white_copy.png", function()
        local List = NeedSelection()
        if #List > 0 then Session:DuplicateEntities(List) end
    end)
    AddButton(Scroll, "Set as Head Entity", "icon16/star.png", function()
        if Session.Primary then Session:SetHead(Session.Primary) end
    end)
    AddButton(Scroll, "Delete Selected", "icon16/delete.png", function()
        local List = NeedSelection()
        if #List == 0 then return end
        local _, Cons = Session:RemoveEntities(List)
        if Cons > 0 then DupeEditor.Notify("Also removed " .. Cons .. " constraints.") end
    end)

    AddSectionHeader(Scroll, "Move / Rotate", "icon16/arrow_inout.png")
    local MoveRow = AddRow(Scroll, "Offset")
    AddRowButton(MoveRow, "Move", nil, function()
        local List = NeedSelection()
        if #List == 0 then return end
        Session:TransformEntities(List, Vector(MoveRow.GetValues()), Angle())
    end)
    MoveRow.GetValues = AddXYZ(MoveRow)

    local RotRow = AddRow(Scroll, "Rotate")
    AddRowButton(RotRow, "Rotate", nil, function()
        local List = NeedSelection()
        if #List == 0 then return end
        Session:TransformEntities(List, Vector(), Angle(RotRow.GetValues()))
    end)
    RotRow.GetValues = AddXYZ(RotRow)

    local Note = Scroll:Add("DLabel")
    Note:Dock(TOP)
    Note:DockMargin(0, 4, 0, 0)
    Note:SetDark(true)
    Note:SetText("(rotates around the center, children follow)")

    AddSectionHeader(Scroll, "Set on Selection", "icon16/table_multiple.png")

    local ModelRow = AddRow(Scroll, "Model")
    local ModelEntry
    AddRowButton(ModelRow, "Set", nil, function()
        local List = NeedSelection()
        local Model = ModelEntry:GetValue()
        if #List == 0 or Model == "" then return end
        Session:Batch("Set model", function()
            for _, Idx in ipairs(List) do Session:Set(Session.Dupe.Entities[Idx], "Model", Model) end
        end)
        Session:Emit("StructureChanged")
        Session:Emit("FocusChanged")
    end)
    ModelEntry = ModelRow:Add("DTextEntry")
    ModelEntry:Dock(FILL)
    ModelEntry:SetPlaceholderText("models/...")

    local MatRow = AddRow(Scroll, "Material")
    local MatEntry
    AddRowButton(MatRow, "Set", nil, function()
        local List = NeedSelection()
        if #List == 0 then return end
        local Mat = MatEntry:GetValue()
        Session:Batch("Set material", function()
            for _, Idx in ipairs(List) do
                local EntData = Session.Dupe.Entities[Idx]
                if not istable(EntData.EntityMods) then Session:Set(EntData, "EntityMods", {}) end
                Session:Set(EntData.EntityMods, "material", Mat ~= "" and {MaterialOverride = Mat} or nil)
            end
        end)
        Session:Emit("StructureChanged")
        Session:Emit("FocusChanged")
    end)
    MatEntry = MatRow:Add("DTextEntry")
    MatEntry:Dock(FILL)
    MatEntry:SetPlaceholderText("(empty to clear)")

    local ColRow = AddRow(Scroll, "Color")
    local PickedColor = Color(255, 255, 255, 255)
    AddRowButton(ColRow, "Set", nil, function()
        local List = NeedSelection()
        if #List == 0 then return end
        Session:Batch("Set color", function()
            for _, Idx in ipairs(List) do
                local EntData = Session.Dupe.Entities[Idx]
                if not istable(EntData.EntityMods) then Session:Set(EntData, "EntityMods", {}) end
                local Old = istable(EntData.EntityMods.colour) and EntData.EntityMods.colour or {}
                local New = table.Copy(Old)
                New.Color = {r = PickedColor.r, g = PickedColor.g, b = PickedColor.b, a = PickedColor.a}
                New.RenderMode = New.RenderMode or (PickedColor.a < 255 and RENDERMODE_TRANSCOLOR or RENDERMODE_NORMAL)
                New.RenderFX = New.RenderFX or 0
                Session:Set(EntData.EntityMods, "colour", New)
            end
        end)
        Session:Emit("StructureChanged")
        Session:Emit("FocusChanged")
    end)
    local Swatch = ColRow:Add("DButton")
    Swatch:Dock(FILL)
    Swatch:SetText("")
    function Swatch:Paint(W, H)
        surface.SetDrawColor(PickedColor.r, PickedColor.g, PickedColor.b, 255)
        surface.DrawRect(0, 0, W, H)
        surface.SetDrawColor(0, 0, 0, 180)
        surface.DrawOutlinedRect(0, 0, W, H)
        local Dark = PickedColor.r + PickedColor.g + PickedColor.b > 380
        draw.SimpleText(string.format("%d %d %d %d", PickedColor.r, PickedColor.g, PickedColor.b, PickedColor.a), "DermaDefault", 6, H / 2, Dark and color_black or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    function Swatch.DoClick()
        local Frame = vgui.Create("DFrame")
        Frame:SetTitle("Pick Color")
        Frame:SetSize(300, 260)
        Frame:Center()
        Frame:MakePopup()
        local Mixer = Frame:Add("DColorMixer")
        Mixer:Dock(FILL)
        Mixer:SetAlphaBar(true)
        Mixer:SetColor(PickedColor)
        function Mixer.ValueChanged(_, New) PickedColor = Color(New.r, New.g, New.b, New.a) end
    end

    local ModRow = AddRow(Scroll, "Modifier")
    local ModCombo
    AddRowButton(ModRow, "Remove", nil, function()
        local List = NeedSelection()
        local _, Mod = ModCombo:GetSelected()
        if #List == 0 or not Mod then return end
        local Count = 0
        Session:Batch("Remove " .. Mod, function()
            for _, Idx in ipairs(List) do
                local Mods = Session.Dupe.Entities[Idx].EntityMods
                if istable(Mods) and Mods[Mod] ~= nil then
                    Session:Set(Mods, Mod, nil)
                    Count = Count + 1
                end
            end
        end)
        DupeEditor.Notify("Removed " .. Mod .. " from " .. Count .. " entities")
        Session:Emit("StructureChanged")
        Session:Emit("FocusChanged")
    end)
    ModCombo = ModRow:Add("DComboBox")
    ModCombo:Dock(FILL)
    ModCombo:SetValue("EntityMods key...")
    local function RefreshMods()
        local Keys = {}
        for Idx in pairs(Session.Selected) do
            local Mods = Session.Dupe.Entities[Idx] and Session.Dupe.Entities[Idx].EntityMods
            if istable(Mods) then
                for Key in pairs(Mods) do Keys[tostring(Key)] = true end
            end
        end
        ModCombo:Clear()
        ModCombo:SetValue("EntityMods key...")
        for _, Key in ipairs(DupeEditor.SortedKeys(Keys)) do ModCombo:AddChoice(Key, Key) end
    end
    Session:Listen("SelectionChanged", ModCombo, RefreshMods)
    Session:Listen("StructureChanged", ModCombo, RefreshMods)

    AddSectionHeader(Scroll, "Dupe", "icon16/database_table.png")

    AddButton(Scroll, "Validate Dupe", "icon16/tick.png", function()
        local Ok, Err = Session:Validate()
        Derma_Message(Ok and "Looks good!" or ("Broken: " .. tostring(Err)), "Validate Dupe", "OK")
    end)
    AddButton(Scroll, "Estimate Size of Whole Dupe", "icon16/calculator.png", function()
        Session:Encode(function(Data)
            Derma_Message("The estimated size is " .. string.NiceSize(#Data) .. ".")
        end)
    end)
    AddButton(Scroll, "Copy Selection as Lua", "icon16/script.png", function()
        local List = NeedSelection()
        if #List == 0 then return end
        local Out = {}
        for _, Idx in ipairs(List) do Out[Idx] = Session.Dupe.Entities[Idx] end
        SetClipboardText(DupeEditor.Serialize(Out))
        DupeEditor.Notify("Copied " .. #List .. " entities!")
    end)

    return Scroll
end

local function BuildClassTools(Parent, Session, Viewport)
    local Scroll = Parent:Add("DScrollPanel")
    Scroll:GetCanvas():DockPadding(6, 0, 6, 6)

    local function Rebuild()
        Scroll:Clear()
        Viewport:SetClassTools(nil)

        local Idx = Session.Primary
        local EntData = Idx and Session.Dupe.Entities[Idx]
        if not EntData then
            AddSectionHeader(Scroll, "Nothing selected")
            return
        end

        local Tools = DupeEditor.GetClassTools(EntData)
        if #Tools == 0 then
            AddSectionHeader(Scroll, "No tools for " .. tostring(EntData.Class))
            return
        end

        local Active = {}
        for _, Def in ipairs(Tools) do
            local Ctx = {Session = Session, EntIdx = Idx, EntData = EntData, View = Viewport.Canvas}
            Active[#Active + 1] = {Def, Ctx}
            AddSectionHeader(Scroll, Def.Name .. "  [" .. Idx .. "]", Def.Icon)

            local Contents = Scroll:Add("DPanel")
            Contents:Dock(TOP)
            Contents:SetPaintBackground(false)

            local function Relayout()
                Contents:InvalidateLayout(true)
                Contents:SizeToChildren(false, true)
                Contents:SetTall(Contents:GetTall() + 4)
                Scroll:InvalidateLayout()
            end

            Ctx.Panel = Contents
            Ctx.Relayout = Relayout
            function Ctx.AddLine(Label, Value)
                local Row = AddRow(Contents, Label, 18)
                Row:DockMargin(0, 2, 0, 0)
                local Val = EllipsisLabel(Row, tostring(Value))
                Val:Dock(FILL)
                return Row
            end
            function Ctx.AddButton(Text, Icon, Fn)
                return AddButton(Contents, Text, Icon, Fn)
            end

            local Ok, Err = xpcall(Def.Build, debug.traceback, Contents, Ctx)
            if not Ok then
                ErrorNoHalt(Err .. "\n")
                Ctx.AddLine("Error", "class tool broke, check console")
            end
            Relayout()
        end

        Viewport:SetClassTools(Active)
    end

    Session:Listen("FocusChanged", Scroll, Rebuild)
    Session:Listen("StructureChanged", Scroll, Rebuild)
    Rebuild()
    return Scroll
end

--------------------------------------------------------------------------------
-- Main window
--------------------------------------------------------------------------------

function OpenDupe(Dupe, Info, MoreInfo, Name)
    if not g_ContextMenu:IsVisible() then return false end

    local Session = DupeEditor.NewSession(Dupe, Info, MoreInfo, Name)

    local Frame = vgui.Create("DFrame", g_ContextMenu)
    Frame:SetSize(math.min(1500, ScrW() - 60), math.min(860, ScrH() - 60))
    Frame:Center()
    Frame:SetSizable(true)
    Frame:SetMinWidth(900)
    Frame:SetMinHeight(500)

    local function UpdateTitle()
        if not IsValid(Frame) then return end
        Frame:SetTitle("Adv. Dupe 2 Editor - " .. Session.Name .. (Session.Dirty and " *" or ""))
    end
    UpdateTitle()
    Session:Listen("DirtyChanged", Frame, UpdateTitle)
    Session:Listen("ValueChanged", Frame, function(Tbl)
        if Tbl == Session then UpdateTitle() end
    end)

    -- Pinned windows are their own popup, so they stay up without holding C
    Frame.ACF_DupeEditorFrame = true
    local Pin = Frame:Add("DButton")
    Pin:SetText("")
    Pin:SetImage("icon16/attach.png")
    Pin:SetIsToggle(true)
    Pin:SetTooltip("Pin? (keeps it open outside the C menu)")

    local function SetPinned(Pinned)
        if Frame.Pinned == Pinned then return end
        Frame.Pinned = Pinned
        local X, Y = Frame:LocalToScreen(0, 0)
        if Pinned then
            Frame:SetParent(vgui.GetWorldPanel())
            Frame:MakePopup()
            Frame:SetKeyboardInputEnabled(false)
        else
            Frame:SetParent(g_ContextMenu)
            Frame:SetKeyboardInputEnabled(false)
            Frame:SetMouseInputEnabled(true)
        end
        Frame:SetPos(Frame:GetParent():ScreenToLocal(X, Y))
        Pin:SetToggle(Pinned)
    end
    Frame.SetPinned = SetPinned
    function Pin:OnToggled(State) SetPinned(State) end

    local OldLayout = Frame.PerformLayout
    function Frame:PerformLayout(W, H)
        OldLayout(self, W, H)
        Pin:SetPos(W - 31 * 3 - 4 - 30, 2)
        Pin:SetSize(26, 20)
    end

    function Frame.btnClose.DoClick()
        if not Session.Dirty then return Frame:Close() end
        Derma_Query("You have unsaved changes. Close anyway?", "Adv. Dupe 2 Editor", "Close", function() Frame:Close() end, "Cancel")
    end

    local Bar = Frame:Add("DMenuBar")
    Bar:Dock(TOP)
    Bar:DockMargin(0, 0, 0, 4)

    -- Bottom bar
    local Bottom = Frame:Add("DPanel")
    Bottom:Dock(BOTTOM)
    Bottom:DockMargin(4, 4, 4, 4)
    Bottom:SetTall(32)
    Bottom:SetPaintBackground(false)

    local UndoButton = Bottom:Add("DButton")
    UndoButton:Dock(LEFT)
    UndoButton:SetWide(32)
    UndoButton:SetText("")
    UndoButton:SetImage("icon16/arrow_undo.png")
    UndoButton.DoClick = function() Session:Undo() end

    local RedoButton = Bottom:Add("DButton")
    RedoButton:Dock(LEFT)
    RedoButton:DockMargin(4, 0, 0, 0)
    RedoButton:SetWide(32)
    RedoButton:SetText("")
    RedoButton:SetImage("icon16/arrow_redo.png")
    RedoButton.DoClick = function() Session:Redo() end

    local SendBack = Bottom:Add("DButton")
    SendBack:Dock(RIGHT)
    SendBack:DockMargin(4, 0, 0, 0)
    SendBack:SetText("Send to Server Clipboard")
    SendBack:SetImage("icon16/server_go.png")
    SendBack:SizeToContentsX(40)
    SendBack.DoClick = function() SendToServer(Session) end

    local SaveButton = Bottom:Add("DButton")
    SaveButton:Dock(RIGHT)
    SaveButton:SetText("Save As...")
    SaveButton:SetImage("icon16/disk.png")
    SaveButton:SizeToContentsX(40)
    SaveButton.DoClick = function() SaveAs(Session, UpdateTitle) end

    local Status = Bottom:Add("DLabel")
    Status:Dock(FILL)
    Status:DockMargin(10, 0, 0, 0)
    Status:SetFont("ACF_DupeEditor_Header")
    function Status:Think()
        local Text = table.Count(Session.Dupe.Entities) .. " entities, " .. #Session.Dupe.Constraints .. " constraints"
        local Count = Session:SelectionCount()
        if Count > 0 then Text = Text .. "  |  " .. Count .. " selected" end
        if Session.Dirty then Text = Text .. "  |  unsaved changes" end
        if Text ~= self.LastText then
            self.LastText = Text
            self:SetText(Text)
        end
    end

    local function UpdateHistoryButtons()
        local Undo = Session.UndoStack[#Session.UndoStack]
        local Redo = Session.RedoStack[#Session.RedoStack]
        UndoButton:SetEnabled(Undo ~= nil)
        RedoButton:SetEnabled(Redo ~= nil)
        UndoButton:SetTooltip(Undo and ("Undo " .. tostring(Undo.Label)) or "Nothing to undo")
        RedoButton:SetTooltip(Redo and ("Redo " .. tostring(Redo.Label)) or "Nothing to redo")
    end
    Session:Listen("HistoryChanged", Bottom, UpdateHistoryButtons)
    UpdateHistoryButtons()

    -- Layout
    local Internals = Frame:Add("DPanel")
    Internals:Dock(FILL)

    local DividerLeftMiddle = Internals:Add("DHorizontalDivider")
    local DividerRight = DividerLeftMiddle:Add("DHorizontalDivider")
    DividerLeftMiddle:Dock(FILL)
        DividerLeftMiddle:SetLeftWidth(330)
        DividerLeftMiddle:SetDividerWidth(8)
        DividerLeftMiddle:SetLeftMin(260)
        DividerLeftMiddle:SetRightMin(500)
        DividerRight:SetLeftWidth(460)
        DividerRight:SetDividerWidth(8)
        DividerRight:SetLeftMin(300)
        DividerRight:SetRightMin(240)

    local Lists = DividerLeftMiddle:Add("DPropertySheet")
    DividerLeftMiddle:SetLeft(Lists)
    DividerLeftMiddle:SetRight(DividerRight)

    local MiddlePanel = DividerRight:Add("DVerticalDivider")
    DividerRight:SetLeft(MiddlePanel)
    MiddlePanel:SetTopHeight(math.floor(Frame:GetTall() * 0.5))

    local ModelView = DividerRight:Add("DPropertySheet")
    DividerRight:SetRight(ModelView)

    local DataView = MiddlePanel:Add("DPropertySheet")
    MiddlePanel:SetTop(DataView)

    local SpecializedDataView = MiddlePanel:Add("DPropertySheet")
    MiddlePanel:SetBottom(SpecializedDataView)

    -- Data view
    local DataPanel = DataView:Add("DPanel")
    DataPanel:SetPaintBackground(false)
    DataView:AddSheet("Data View", DataPanel, "icon16/database.png")

    local DataHeader = DataPanel:Add("DPanel")
    DataHeader:Dock(TOP)
    DataHeader:DockMargin(0, 0, 0, 4)
    DataHeader:SetTall(22)
    DataHeader:SetPaintBackground(false)

    local ViewPanel = DupeEditor.CreateDataTree(DataPanel, Session)
    ViewPanel:Dock(FILL)

    local CopyLua = DataHeader:Add("DButton")
    CopyLua:Dock(RIGHT)
    CopyLua:DockMargin(4, 0, 0, 0)
    CopyLua:SetText("Copy as Lua")
    CopyLua:SetImage("icon16/script.png")
    CopyLua:SizeToContentsX(34)
    CopyLua.DoClick = function()
        if ViewPanel.Data then SetClipboardText(DupeEditor.Serialize(ViewPanel.Data)) end
    end

    local Collapse = DataHeader:Add("DButton")
    Collapse:Dock(RIGHT)
    Collapse:SetText("Collapse All")
    Collapse:SetImage("icon16/arrow_in.png")
    Collapse:SizeToContentsX(34)
    Collapse.DoClick = function() ViewPanel:CollapseAll() end

    local DataTitle = DataHeader:Add("DLabel")
    DataTitle:Dock(FILL)
    DataTitle:SetFont("ACF_DupeEditor_Header")
    DataTitle:SetDark(true)

    local function LoadFocus()
        local Constraint = Session.ActiveConstraint and Session.Dupe.Constraints[Session.ActiveConstraint]
        if Constraint then
            DataTitle:SetText("Constraint #" .. Session.ActiveConstraint .. " (" .. tostring(Constraint.Type) .. ")")
            ViewPanel:SetData(Constraint, "Constraint", Session.ActiveConstraint)
            return
        end

        local Idx = Session.Primary
        local EntData = Idx and Session.Dupe.Entities[Idx]
        if EntData then
            local Count = Session:SelectionCount()
            DataTitle:SetText(EntityLabel(Session, Idx) .. (Count > 1 and ("  (+" .. (Count - 1) .. " more selected)") or ""))
            ViewPanel:SetData(EntData, "Entity", Idx)
        else
            DataTitle:SetText("Nothing selected")
            ViewPanel:SetData(nil)
        end
    end
    Session:Listen("FocusChanged", DataPanel, LoadFocus)
    Session:Listen("StructureChanged", DataPanel, LoadFocus)

    -- 3D view
    local Viewport = vgui.Create("ACF_DupeViewport", ModelView)
    ModelView:AddSheet("Model View", Viewport, "icon16/user.png")
    Viewport:SetSession(Session)

    -- Tools
    local EditorTools = BuildEditorTools(SpecializedDataView, Session)
    SpecializedDataView:AddSheet("Editor Tools", EditorTools, "icon16/table_edit.png")

    local ClassTools = BuildClassTools(SpecializedDataView, Session, Viewport)
    local ClassSheet = SpecializedDataView:AddSheet("Class Tools", ClassTools, "icon16/script_edit.png")

    -- Lists
    Lists:AddSheet("Entities", BuildEntityList(Lists, Session), "icon16/bricks.png")
    Lists:AddSheet("Constraints", BuildConstraintList(Lists, Session), "icon16/link.png")
    Lists:AddSheet("Classes", BuildClassList(Lists, Session), "icon16/application_view_list.png")
    Lists:AddSheet("Search", BuildSearch(Lists, Session, function() return ViewPanel end), "icon16/magnifier.png")
    Lists:AddSheet("Information", BuildInformation(Lists, Session), "icon16/note_edit.png")

    -- Jump to class tools when picking something that has them
    Session:Listen("SelectionChanged", SpecializedDataView, function()
        local EntData = Session.Primary and Session.Dupe.Entities[Session.Primary]
        if not EntData then return end
        local Tools = DupeEditor.GetClassTools(EntData)
        local Specific = false
        for _, Def in ipairs(Tools) do
            if not Def.Classes["*"] then Specific = true break end
        end
        if Specific then SpecializedDataView:SetActiveTab(ClassSheet.Tab) end
    end)

    -- Menu bar
    local FileMenu = Bar:AddMenu("File")
    FileMenu:AddOption("Open Clipboard", function()
        RunConsoleCommand("start_advdupe2_download")
    end):SetIcon("icon16/page_paste.png")
    FileMenu:AddOption("Open File...", OpenFileDialog):SetIcon("icon16/folder_explore.png")
    FileMenu:AddSpacer()
    FileMenu:AddOption("Save As...", function() SaveAs(Session, UpdateTitle) end):SetIcon("icon16/disk.png")
    FileMenu:AddOption("Send to Server Clipboard", function() SendToServer(Session) end):SetIcon("icon16/server_go.png")
    FileMenu:AddSpacer()
    FileMenu:AddOption("Close", function() Frame.btnClose:DoClick() end):SetIcon("icon16/cross.png")

    local EditMenu = Bar:AddMenu("Edit")
    EditMenu:AddOption("Undo", function() Session:Undo() end):SetIcon("icon16/arrow_undo.png")
    EditMenu:AddOption("Redo", function() Session:Redo() end):SetIcon("icon16/arrow_redo.png")
    EditMenu:AddSpacer()
    EditMenu:AddOption("Select All", function()
        Session:SetSelection(table.GetKeys(Session.Dupe.Entities))
    end):SetIcon("icon16/table_select_all.png")
    EditMenu:AddOption("Select None", function() Session:ClearSelection() end):SetIcon("icon16/table.png")
    EditMenu:AddOption("Invert Selection", function()
        local List = {}
        for Idx in pairs(Session.Dupe.Entities) do
            if not Session.Selected[Idx] then List[#List + 1] = Idx end
        end
        Session:SetSelection(List)
    end):SetIcon("icon16/arrow_switch.png")
    EditMenu:AddSpacer()
    EditMenu:AddOption("Duplicate Selected", function()
        Session:DuplicateEntities(Session:GetSelectedList())
    end):SetIcon("icon16/page_white_copy.png")
    EditMenu:AddOption("Delete Selected", function()
        local _, Cons = Session:RemoveEntities(Session:GetSelectedList())
        if Cons and Cons > 0 then DupeEditor.Notify("Also removed " .. Cons .. " constraints.") end
    end):SetIcon("icon16/delete.png")

    local ViewMenu = Bar:AddMenu("View")
    ViewMenu:AddOption("Frame All", function() Viewport.Canvas:FrameAll() end):SetIcon("icon16/arrow_out.png")
    ViewMenu:AddOption("Focus Selection", function() Viewport.Canvas:FocusSelection() end):SetIcon("icon16/zoom.png")
    ViewMenu:AddSpacer()
    ViewMenu:AddOption("Hide Selected", function() Session:SetHidden(Session:GetSelectedList(), true) end):SetIcon("icon16/lightbulb_off.png")
    ViewMenu:AddOption("Isolate Selected", function() Session:Isolate(Session:GetSelectedList()) end):SetIcon("icon16/lightbulb.png")
    ViewMenu:AddOption("Unhide All", function() Session:UnhideAll() end):SetIcon("icon16/lightbulb_add.png")

    LoadFocus()
    DupeEditor.LastSession = Session
    return true
end

DupeEditor.OpenDupe = OpenWhenPossible

-- Pinned windows aren't under the context menu, so they need their own keyboard focus handling
local function FindPinnedFrame(Pnl)
    while IsValid(Pnl) do
        if Pnl.ACF_DupeEditorFrame then return Pnl.Pinned and Pnl or nil end
        Pnl = Pnl:GetParent()
    end
end

hook.Add("OnTextEntryGetFocus", "ACF_DupeEditor_Pinned", function(Pnl)
    local Frame = FindPinnedFrame(Pnl)
    if Frame then Frame:SetKeyboardInputEnabled(true) end
end)

hook.Add("OnTextEntryLoseFocus", "ACF_DupeEditor_Pinned", function(Pnl)
    local Frame = FindPinnedFrame(Pnl)
    if Frame then Frame:SetKeyboardInputEnabled(false) end
end)

net.Receive("ACF_Devtools_Advdupe2Download", function(_)
    net.ReadBool()
    net.ReadStream(nil, function(data)
        if IsValid(ACF_DevTools.CurrentAdvDupe2Notice) then
            ACF_DevTools.CurrentAdvDupe2Notice:Remove()
            ACF_DevTools.CurrentAdvDupe2Notice = nil
        end

        if not data then
            AdvDupe2.Notify("File was not saved! (No data)", NOTIFY_ERROR, 5)
            return
        end

        local Success, Dupe, Info, MoreInfo = AdvDupe2.Decode(data)
        if not Success then
            AdvDupe2.Notify("DEBUG CHECK: " .. tostring(Dupe), NOTIFY_ERROR)
            return
        end

        AdvDupe2.Notify("Received dupe.", NOTIFY_GENERIC, 5)
        OpenWhenPossible(Dupe, Info, MoreInfo, "Current Clipboard")
    end)
end)

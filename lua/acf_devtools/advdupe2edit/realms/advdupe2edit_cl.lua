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

--[[local function CreateGroupBox(Parent, Name)
    local Panel = vgui.Create("DPanel", Parent)

    surface.SetFont("DermaDefault")
    local TX, TY = surface.GetTextSize(Name)
    local Padding = (TY / 2) + 4
    function Panel:Paint(W, H)
        local Dark = self:GetSkin().text_dark

        surface.SetDrawColor(Dark)
        local WP = W - (Padding * 2)
        local HP = H - (Padding * 2)

        surface.DrawLine(Padding, Padding, Padding, HP)
        surface.DrawLine(WP, Padding, WP, HP)
        surface.DrawLine(Padding, HP, WP, HP)

        surface.DrawLine(Padding, Padding, 32, Padding)
        surface.DrawLine(32 + TX + 8, Padding, WP, Padding)

        draw.SimpleText(Name, "DermaDefault", 32 + 4, Padding, Dark, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    Panel:DockPadding(Padding, Padding, Padding, Padding)
    return Panel
end]]

local Modifiers = {}
local Classes   = {}
local LoadNodes

local function NewModifier(Name, Icon)
    local Def = {}
    Modifiers[Name] = Def
    Def.Name = Name
    Def.Icon = Icon
    return Def
end

local function NewClass(Name, Icon)
    local Def = {}
    Classes[Name] = Def
    Def.Name = Name
    Def.Icon = Icon
    return Def
end

local function EnumModifier(Name, ENUM_PREFIX)
    ENUM_PREFIX = ENUM_PREFIX .. "_"
    local LUT = {}
    for Key, Value in pairs(_G) do
        if string.StartsWith(Key, ENUM_PREFIX) then
            LUT[Value] = Key
        end
    end

    local Def = NewModifier(Name, "icon16/collision_on.png")
    function Def.SelfLoadContents(Node, Key, Value)
        local Text = Node:Add("DTextEntry")
        Text:SetText(LUT[Value] or tostring(Value))
        Text:Dock(RIGHT)
        Text:DockMargin(4, 0, 4, 0)
        Text:SetSize(200, 0)
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


local function OpenDupe(Dupe, Info, MoreInfo)
    if not g_ContextMenu:IsVisible() then return false end
    local SelectedEntityIdx = -1

    local Frame = vgui.Create("DFrame", g_ContextMenu)
    Frame:SetSize(1200, 720)
    Frame:Center()
    Frame:SetTitle("Adv. Dupe 2 Viewer")
    Frame:SetSizable(true)

    local SendBack = Frame:Add("DButton")
    SendBack:Dock(BOTTOM)
    SendBack:DockMargin(4, 4, 4, 4)
    SendBack:SetSize(32, 32)
    SendBack:SetText("Send to Server Clipboard")

    function SendBack:DoClick()
        local Notice = Derma_Message("Sending...", "Please wait", "Close Popup (does not cancel)")
        local Tab = {Entities = Dupe.Entities, Constraints = Dupe.Constraints, HeadEnt = Dupe.HeadEnt}

        AdvDupe2.Encode(Tab, AdvDupe2.GenerateDupeStamp(LocalPlayer()), function(data)
            net.Start("AdvDupe2_ReceiveFile")
            net.WriteString("reencoded")
            net.WriteStream(data, function()
                Notice:Remove()
                notification.AddLegacy("OK!", NOTIFY_GENERIC, 5)
            end)
            AdvDupe2.Uploading = false
            net.SendToServer()
        end)
    end

    local Internals = Frame:Add("DPanel")
    Internals:Dock(FILL)

    local DividerLeftMiddle = Internals:Add("DHorizontalDivider")
    local DividerRight = DividerLeftMiddle:Add("DHorizontalDivider")
    DividerLeftMiddle:Dock(FILL)
        DividerLeftMiddle:SetLeftWidth(300)
        DividerLeftMiddle:SetDividerWidth(8)
        DividerLeftMiddle:SetLeftMin(300)
        DividerLeftMiddle:SetRightMin(384)
        DividerRight:SetLeftWidth(500)
        DividerRight:SetDividerWidth(8)
        DividerRight:SetLeftMin(200)
        DividerRight:SetRightMin(200)

    local Lists = DividerLeftMiddle:Add("DPropertySheet")
    DividerLeftMiddle:SetLeft(Lists)
    DividerLeftMiddle:SetRight(DividerRight)

    local MiddlePanel = DividerRight:Add("DVerticalDivider")
    DividerRight:SetLeft(MiddlePanel)
    MiddlePanel:SetTopHeight(400)

    local ModelView = DividerRight:Add("DPropertySheet")
    DividerRight:SetRight(ModelView)

    local EntitiesPanel = Lists:Add("DScrollPanel")
    Lists:AddSheet("Entities", EntitiesPanel, "icon16/bricks.png")

    local ConstraintsPanel = Lists:Add("DListView")
    Lists:AddSheet("Constraints", ConstraintsPanel, "icon16/link.png")

    local InformationPanel = Lists:Add("DTree")
    Lists:AddSheet("Information", InformationPanel, "icon16/note_edit.png")

    local DataView = MiddlePanel:Add("DPropertySheet")
    MiddlePanel:SetTop(DataView)

    local SpecializedDataView = MiddlePanel:Add("DPropertySheet")
    MiddlePanel:SetBottom(SpecializedDataView)

    local ViewPanel = DataView:Add("DTree")
    DataView:AddSheet("Data View", ViewPanel, "icon16/database.png")

    local ToolBtnHeight = 32
    local EditorTools = SpecializedDataView:Add("DScrollPanel")
    SpecializedDataView:AddSheet("Editor Tools", EditorTools, "icon16/table_edit.png")
    do
        local EstimateSizeHelper = EditorTools:Add("DButton")
        EstimateSizeHelper:SetSize(ToolBtnHeight, ToolBtnHeight)
        EstimateSizeHelper:Dock(TOP)
        EstimateSizeHelper:SetText("Estimate Size of Entity")
        function EstimateSizeHelper:DoClick()
            if SelectedEntityIdx == -1 then return end
            -- Fake encode one entity for testing
            local FakeEncode = {Entities = {[SelectedEntityIdx] = Dupe.Entities[SelectedEntityIdx]}, Constraints = {}, HeadEnt = Dupe.Entities[SelectedEntityIdx]}
            AdvDupe2.Encode(FakeEncode, AdvDupe2.GenerateDupeStamp(LocalPlayer()), function(data)
                local Size = #data
                Derma_Message("The estimated size is " .. string.NiceSize(Size) .. ".")
            end)
        end
    end

    local ChipTools = SpecializedDataView:Add("DScrollPanel")
    SpecializedDataView:AddSheet("Chip Specific Tools", ChipTools, "icon16/script_edit.png")

    local ModelViewSheet = ModelView:Add("DPanel")
    ModelView:AddSheet("Model View", ModelViewSheet, "icon16/user.png")

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

            IsPaintingSelfContents = true
            DNumberWang.Paint(self, W, H)
            IsPaintingSelfContents = false
        end
    end

    local DepressedDrawColor               = Color(150, 150, 150)
    local SelectedHighlightedDrawColor     = Color(218, 238, 255)
    local SelectedDrawColor                = Color(136, 198, 255)
    local HighlightDrawColor               = Color(238, 238, 238)
    local function ProducePaintSelectedButton(IsSelectedFn)
        return function(self, width, height)
            local DrawColor
            local TextColor = color_black
            if IsSelectedFn() then
                if self.Hovered then
                    if input.IsMouseDown(MOUSE_LEFT) then
                        DrawColor = DepressedDrawColor
                    else
                        DrawColor = SelectedHighlightedDrawColor
                    end
                else
                    DrawColor = SelectedDrawColor
                end
                TextColor = color_white
                DrawColor = DrawColor:Copy()
                if not self.SelectTime then
                    self.SelectTime = RealTime()
                end
                DrawColor:AddBrightness(math.Remap(math.cos((RealTime() - self.SelectTime) * 6), -1, 1, 0, -0.2))
            elseif input.IsMouseDown(MOUSE_LEFT) and self.Hovered then
                DrawColor = DepressedDrawColor
            elseif self.Hovered then
                DrawColor = HighlightDrawColor
            else
                DrawColor = DrawColor
            end

            self:GetSkin().tex.Button(0, 0, width, height, DrawColor)
        end
    end
    local TypeIcons = {
        number = "icon16/text_list_numbers.png",
        string = "icon16/text_signature.png",
        boolean = "icon16/accept.png",
        table = "icon16/table.png",
        Vector = "icon16/map_go.png",
        Angle = "icon16/arrow_rotate_anticlockwise.png",
    }

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

    function LoadNodes(Class, Parent, Data, Last)
        if not IsValid(Parent) then return end

        for Key, Value in SortedPairs(Data) do
            local Interpreter
            if Last == nil then
                Interpreter = Modifiers[Key] or Classes[Key]
            end

            local t = type(Value)
            local Node = Parent:AddNode(Key, Interpreter and Interpreter.Icon or StandardIcons[Key] or TypeIcons[t] or "icon16/bullet_black.png")
            Node:DockMargin(0, 2, 0, 2)

            if not Interpreter or not Interpreter.SelfLoadContents then
                if t == "table" then
                    if next(Value) then
                        Node.Expander:SetVisible(true)
                        Node.Expander.SetVisible = function() end -- Nah
                    end
                    local ExpandedOnce = false
                    local OldDoClick = Node.DoClick
                    function Node:DoClick()
                        OldDoClick(self)
                        if not ExpandedOnce then LoadNodes(Class, Node, Value, Parent) end
                        ExpandedOnce = true
                        self:SetExpanded(not self:GetExpanded())
                    end
                    Node.Expander.DoClick = function() Node:DoClick() end

                elseif t == "number" or tonumber(Value) ~= nil then
                    local Inner, Text = CreateInputPanel(Node, "DNumberWang")
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
                        Data[Key] = 0 / 0
                    end

                    function PutInf:DoClick()
                        Text:SetText("inf")
                        Data[Key] = 1 / 0
                    end

                    Text:MoveToFront()
                    function Text:OnValueChanged(V)
                        Data[Key] = V
                    end
                elseif t == "string" then
                    local _, Text = CreateInputPanel(Node, "DTextEntry")
                    Text:SetText(Value)

                    function Text:OnChange()
                        Data[Key] = self:GetText()
                    end
                elseif t == "boolean" then
                    local _, Text = CreateInputPanel(Node, "DCheckBox")
                    Text:SetChecked(Value)
                    Text:Dock(RIGHT)
                    Text:DockMargin(0, 1, 0, 1)
                    Text:SetSize(14, 0)

                    function Text:OnChange(V)
                        Data[Key] = V
                    end
                elseif t == "Vector" or t == "Angle" then
                    local X, Y, Z = Value:Unpack()

                    local Inner, _ = CreateInputPanel(Node)
                    local Z_Slider = Inner:Add("DNumberWang")
                    local Y_Slider = Inner:Add("DNumberWang")
                    local X_Slider = Inner:Add("DNumberWang")

                    local HPadding = 4
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

                    function X_Slider:OnValueChanged(V) Value[1] = V end
                    function Y_Slider:OnValueChanged(V) Value[2] = V end
                    function Z_Slider:OnValueChanged(V) Value[3] = V end
                end
            elseif Interpreter and Interpreter.SelfLoadContents then
                Interpreter.SelfLoadContents(Node, Key, Value)
            end
        end
    end

    local function LoadEntity(EntityIdx, EntityData)
        ViewPanel:Clear()
        LoadNodes(EntityData.Class, ViewPanel, EntityData)
    end

    for EntityIdx, Data in pairs(Dupe.Entities) do
        local SelectEntButton = EntitiesPanel:Add("DButton")
        SelectEntButton:Dock(TOP)
        SelectEntButton:SetSize(32, 24)
        SelectEntButton:SetText("[" .. EntityIdx .. "] " .. (Data.Class or "<?CLASSNAME?>"))

        SelectEntButton.Paint = ProducePaintSelectedButton(function() return EntityIdx == SelectedEntityIdx end)

        function SelectEntButton:DoClick()
            LoadEntity(EntityIdx, Data)
            SelectedEntityIdx = EntityIdx
        end
    end

    return true
end

net.Receive("ACF_Devtools_Advdupe2Download", function(_)
    net.ReadBool()
    net.ReadStream(nil, function(data)
        if IsValid(ACF_DevTools.CurrentAdvDupe2Notice) then
            ACF_DevTools.CurrentAdvDupe2Notice:Remove()
            ACF_DevTools.CurrentAdvDupe2Notice = nil
        end

        if not data then
            AdvDupe2.Notify("File was not saved! (No data)",NOTIFY_ERROR,5)
            return
        end

        local Success, Dupe, Info, MoreInfo = AdvDupe2.Decode(data)
        if not Success then
            AdvDupe2.Notify("DEBUG CHECK: " .. dDupepe, NOTIFY_ERROR)
            return
        end

        AdvDupe2.Notify("Received dupe.", NOTIFY_GENERIC, 5)

        if not OpenDupe(Dupe, Info, MoreInfo) then
            -- We need to delay it. Not sure why, but it fixes a load issue
            local Name = "TempOpenDupeDelay_" .. SysTime()
            hook.Add("OnContextMenuOpen", Name, function()
                timer.Simple(0.05, function()
                    if OpenDupe(Dupe, Info, MoreInfo) then
                        hook.Remove("OnContextMenuOpen", Name)
                    end
                end)
            end)
        end
    end)
end)
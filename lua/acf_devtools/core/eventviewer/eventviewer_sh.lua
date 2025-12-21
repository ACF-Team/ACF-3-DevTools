local EventViewer = ACF_DevTools.EventViewer or {}
ACF_DevTools.EventViewer = EventViewer

local acf_eventviewer_enable = CreateConVar("acf_eventviewer_enable", "0", FCVAR_NOTIFY + FCVAR_REPLICATED, "Enable/disable event viewer functionality", 0, 1)
local EnableEventViewer = acf_eventviewer_enable:GetBool()
cvars.AddChangeCallback("acf_eventviewer_enable", function(_, _, _)
    EnableEventViewer = acf_eventviewer_enable:GetBool()
end, "ACF_CheckEvents")

function EventViewer.Enabled() return EnableEventViewer end

if SERVER then
    util.AddNetworkString("ACF_EventViewerMsg")

    function EventViewer.AppendEvent(UniqueID, ...)
        if not EnableEventViewer then return end
        local Count = select('#', ...)

        net.Start("ACF_EventViewerMsg")
        net.WriteString(UniqueID)
        net.WriteBool(false)
        net.WriteUInt(Count, 8)
        for I = 1, Count do
            net.WriteType(select(I, ...))
        end
        net.Broadcast()
    end

    function EventViewer.StartEvent(UniqueID)
        if not EnableEventViewer then return end

        net.Start("ACF_EventViewerMsg")
        net.WriteString(UniqueID)
        net.WriteBool(true)
        net.WriteUInt(0, 8)
        net.Broadcast()
    end
end

local RegisteredEventDefs = {}
function EventViewer.DefineEvent(Name)
    local Ev = {}
    RegisteredEventDefs[Name] = Ev
    return Ev
end

-- just in case someone does something dumb, don't break the entire color_white copy...
-- ... although this should be set by-value anyway and not used by reference...
local CurrentRenderingColor = color_white:Copy()
local IsPrimaryFocusData = false

function EventViewer.CurrentRenderingColor() return CurrentRenderingColor end
function EventViewer.IsPrimaryFocusData() return IsPrimaryFocusData end

do
    local IconsPerKey = {
        mask      = "icon16/film.png",
        start     = "icon16/control_start.png",
        endpos    = "icon16/control_end.png",
        filter    = "icon16/cut.png",
        mins      = "icon16/shape_rotate_anticlockwise.png",
        maxs      = "icon16/shape_rotate_clockwise.png",
        output    = "icon16/table_go.png",

        Mask      = "icon16/film.png",
        Pos       = "icon16/cross.png",
        Tracer    = "icon16/wand.png",
        Id        = "icon16/table_relationship.png",
        Crate     = "icon16/shape_square.png",
        Index     = "icon16/text_list_numbers.png",
        Owner     = "icon16/user.png",
        Gun       = "icon16/gun.png",
        Flight    = "icon16/arrow_up.png",
        Color     = "icon16/color_wheel.png",
        LastThink = "icon16/clock.png"
    }

    function EventViewer.AddKeyValueNode(Node, Key, Value, IconOverride)
        return Node:AddNode(tostring(Key) .. " : " .. tostring(Value), IconOverride and IconOverride or (IconsPerKey[Key] or "icon16/bullet_add.png"))
    end

    function EventViewer.AddTableNode(Node, Name, Table, IconOverride)
        local TableNode = Name == nil and Node or Node:AddNode(tostring(Name), IconOverride and IconOverride or (IconsPerKey[Name] or "icon16/bullet_add.png"))
        for Key, Value in pairs(Table) do
            EventViewer.AddKeyValueNode(TableNode, Key, Value)
        end
    end

    function EventViewer.AddTraceNode(Node, Name, Table, IconOverride)
        local TableNode = Name == nil and Node or Node:AddNode(tostring(Name), IconOverride and IconOverride or (IconsPerKey[Name] or "icon16/bullet_add.png"))
        for Key, Value in pairs(Table) do
            if Key == "filter" then
                if type(Value) == "table" then
                    EventViewer.AddTableNode(TableNode, Key, Value)
                else
                    EventViewer.AddKeyValueNode(TableNode, Key, Value)
                end
            else
                EventViewer.AddKeyValueNode(TableNode, Key, Value)
            end
        end
    end
end

-- UI rendering
if CLIENT then
    local ClientReceivedEvents = {}
    local ClientReceivedEventOrder = {}
    hook.Run("ACF_EventViewer_ClearAllEvents")

    concommand.Add("acf_eventviewer_clear", function()
        table.Empty(ClientReceivedEvents)
        table.Empty(ClientReceivedEventOrder)
        hook.Run("ACF_EventViewer_ClearAllEvents")
    end)

    net.Receive("ACF_EventViewerMsg", function()
        local EventIdx = net.ReadString()
        local Clear = net.ReadBool()

        if not ClientReceivedEvents[EventIdx] then
            ClientReceivedEvents[EventIdx] = {}
            ClientReceivedEventOrder[#ClientReceivedEventOrder + 1] = EventIdx
            hook.Run("ACF_EventViewer_NewEvent", EventIdx, ClientReceivedEvents[EventIdx])
        end

        local DebugInfo = ClientReceivedEvents[EventIdx]
        if Clear then
            table.Empty(DebugInfo)
            hook.Run("ACF_EventViewer_ClearEventData", EventIdx, DebugInfo)
        end

        local Count = net.ReadUInt(8)
        if Count > 0 then
            local Data = {}
            for I = 1, Count do
                Data[I] = net.ReadType()
            end
            DebugInfo[#DebugInfo + 1] = Data
            hook.Run("ACF_EventViewer_NewEventInfoReceived", EventIdx, Data, #DebugInfo)
        end
    end)

    local function TryRunDefFunction(Def, Name, Event)
        local Func = Def and Def[Name] or nil
        if Func then
            Func(unpack(Event, 2))
        end
    end
    local function RunFunctionForEvents(Name)
        if not EnableEventViewer then return end
        IsPrimaryFocusData = false

        local OnlyRenderThisEventIdx = hook.Run("ACF_EventViewer_GetEventIdxToRender")
        local OnlyRenderThisDataIdx  = hook.Run("ACF_EventViewer_GetEventDataIdxToRender")
        for EventIdx, Info in pairs(ClientReceivedEvents) do
            CurrentRenderingColor = HSVToColor(util.CRC(EventIdx) % 360, 0.9, 1)

            if not OnlyRenderThisEventIdx or OnlyRenderThisEventIdx == EventIdx then
                for Idx, Event in ipairs(Info) do
                    IsPrimaryFocusData = Idx == OnlyRenderThisDataIdx
                    if not OnlyRenderThisDataIdx or IsPrimaryFocusData then
                        local Type = Event[1]
                        local Def  = RegisteredEventDefs[Type]
                        TryRunDefFunction(Def, Name, Event)
                    end
                end
            end
        end
    end

    hook.Add("PreDrawEffects", "ACF_DrawEventViewer", function()
        RunFunctionForEvents("Render3D")
    end)

    hook.Add("PostDrawEvents", "ACF_DrawEventViewer", function()
        RunFunctionForEvents("Render2D")
    end)

    concommand.Add("acf_eventviewer_open", function()
        local Menu = vgui.Create("DFrame")
        Menu:SetTitle("Event Viewer")
        Menu:SetSize(760, 760)
        Menu:MakePopup()
        Menu:Center()
        Menu:DockPadding(8, 32, 8, 8)

        local Clear = Menu:Add("DButton")
        Clear:SetConsoleCommand("acf_eventviewer_clear")
        Clear:Dock(BOTTOM)
        Clear:SetText("Clear All")

        local Events = Menu:Add("DListView")
        Events:AddColumn("Event Name")
        for _, Key in ipairs(ClientReceivedEventOrder) do
            local Data = ClientReceivedEvents[Key]
            Events:AddLine(Key, Data)
        end
        Events:DockMargin(4, 4, 4, 4)
        Events:Dock(LEFT)
        Events:SetSize(200)

        local ClearSelection = Menu:Add("DButton")
        ClearSelection:Dock(TOP)
        ClearSelection:SetText("Clear Selected Item")
        ClearSelection:DockMargin(4, 4, 4, 4)

        local Info = Menu:Add("DTree")
        Info:Dock(FILL)
        Info:DockMargin(4, 4, 4, 4)
        hook.Add("ACF_EventViewer_GetEventIdxToRender", Info, function()
            local _, Selected = Events:GetSelectedLine()

            if IsValid(Selected) then return Selected:GetValue(1) end
        end)

        hook.Add("ACF_EventViewer_GetEventDataIdxToRender", Info, function()
            local Selected = Info:GetSelectedItem()
            if IsValid(Selected) then return Selected.ACF_Idx end
        end)

        function ClearSelection:DoClick()
            Info:SetSelectedItem(nil)
        end

        local LoadedEventIdx, LoadedData
        local function AppendDataPiece(Num, DataPiece)
            local Type = DataPiece[1]
            local EventDef = RegisteredEventDefs[Type]
            local Node = Info:AddNode("[#" .. Num .. "] " .. Type, EventDef and EventDef.Icon or "icon16/information.png")
            Node.ACF_Idx = Num
            local Func = EventDef and EventDef.BuildNode or nil
            if Func then Func(Node, unpack(DataPiece, 2)) end
        end

        local function LoadData(Index, Data)
            Info:Clear()
            LoadedEventIdx, LoadedData = Index, Data

            for I, DataPiece in ipairs(LoadedData) do
                AppendDataPiece(I, DataPiece)
            end
        end
        Events.OnRowSelected = function(_, _, Line)
            LoadData(Line:GetValue(1), Line:GetValue(2))
        end

        hook.Add("ACF_EventViewer_ClearAllEvents", Events, function()
            Events:Clear()
            Info:Clear()
        end)

        hook.Add("ACF_EventViewer_ClearEventData", Events, function(_, Idx)
            if LoadedEventIdx == Idx then
                Info:Clear()
            end
        end)

        hook.Add("ACF_EventViewer_NewEventInfoReceived", Events, function(_, Idx, DataPiece, Num)
            if LoadedEventIdx == Idx then
                AppendDataPiece(Num, DataPiece)
            end
        end)

        hook.Add("ACF_EventViewer_NewEvent", Events, function(_, EventIdx, Data)
            Events:AddLine(EventIdx, Data)
        end)
    end)
end
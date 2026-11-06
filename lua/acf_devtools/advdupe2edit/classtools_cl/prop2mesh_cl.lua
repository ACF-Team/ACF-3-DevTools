local DupeEditor = ACF_DevTools.DupeEditor

local P2M_CLASSES = {sent_prop2mesh = true, sent_prop2mesh_legacy = true}
-- Keeps our mesh builds out of prop2mesh's own cache
local CRC_PREFIX  = "acfdupeedit_"

local SELECT_COLOR = Color(255, 170, 40)
local WireframeMat = Material("models/wireframe")

local function GetP2M(EntData)
    local Mod = istable(EntData.EntityMods) and EntData.EntityMods.prop2mesh
    if not istable(Mod) or not istable(Mod[1]) then return end
    if not istable(Mod[2]) then Mod[2] = {} end
    return Mod[1], Mod[2]
end

local DecodeCache = {}
local function GetParts(Partlists, Crc)
    local Data = Partlists[Crc]
    if not isstring(Data) then return end
    local Cached = DecodeCache[Data]
    if Cached == nil then
        local Json = util.Decompress(Data)
        Cached = Json and util.JSONToTable(Json) or false
        DecodeCache[Data] = Cached
    end
    return Cached or nil
end

local function WriteParts(Session, Controller, Partlists, Parts)
    local Json = util.TableToJSON(Parts)
    if not Json then return end
    local Data = util.Compress(Json)
    local Crc = util.CRC(Data)
    Session:Batch("Edit P2M parts", function()
        Session:Set(Partlists, Crc, Data)
        Session:Set(Controller, "crc", Crc)
    end)
end

local function UniqueID(Controller)
    local UVs = math.min(math.abs(math.floor(tonumber(Controller.uvs) or 0)), 512)
    return UVs .. "_" .. (Controller.bump and 1 or 0)
end

local function GetScale(Controller)
    return isvector(Controller.scale) and Controller.scale or Vector(1, 1, 1)
end

local function ControllerFrame(Info, Controller)
    local LinkPos = isvector(Controller.linkpos) and Controller.linkpos or vector_origin
    local LinkAng = isangle(Controller.linkang) and Controller.linkang or angle_zero
    return LocalToWorld(LinkPos, LinkAng, Info.Pos, Info.Ang)
end

--------------------------------------------------------------------------------
-- Mesh cache
--------------------------------------------------------------------------------

local Meshes = {}
local Users  = {}

local function GetMesh(Data, Crc, UID)
    local Key = Crc .. "_" .. UID
    local Entry = Meshes[Key]
    if Entry then return Entry end

    Entry = {State = "building", Meshes = {}}
    Meshes[Key] = Entry
    if not (prop2mesh and prop2mesh.getMesh) then
        Entry.State = "failed"
    else
        -- false means it's already queued, the hook still fires for it
        prop2mesh.getMesh(CRC_PREFIX .. Crc, UID, Data)
    end
    return Entry
end

hook.Add("prop2mesh_hook_meshdone", "ACF_DupeEditor_P2M", function(Crc, UID, MData)
    if not isstring(Crc) or string.sub(Crc, 1, #CRC_PREFIX) ~= CRC_PREFIX then return end
    local Entry = Meshes[string.sub(Crc, #CRC_PREFIX + 1) .. "_" .. tostring(UID)]
    if not Entry or Entry.State ~= "building" then return end

    if not istable(MData) or not istable(MData.meshes) then
        Entry.State = "failed"
        return
    end

    for _, Tris in ipairs(MData.meshes) do
        if #Tris > 0 then
            local IM = Mesh()
            IM:BuildFromTriangles(Tris)
            Entry.Meshes[#Entry.Meshes + 1] = IM
        end
    end
    Entry.Mins, Entry.Maxs = MData.vmins, MData.vmaxs
    Entry.Parts, Entry.Verts = MData.pcount, MData.vcount
    Entry.State = "ready"
end)

local function DestroyAll()
    for _, Entry in pairs(Meshes) do
        for _, IM in ipairs(Entry.Meshes) do
            if IsValid(IM) then IM:Destroy() end
        end
    end
    Meshes = {}
    DecodeCache = {}
end

--------------------------------------------------------------------------------
-- Layer
--------------------------------------------------------------------------------

local MatCache = {}
local function GetMaterial(Path)
    if not isstring(Path) or Path == "" then Path = "hunter/myplastic" end
    local Mat = MatCache[Path]
    if not Mat then
        Mat = Material(Path)
        MatCache[Path] = Mat
    end
    return Mat
end

local function DrawController(View, Info, Controller, Entry, Alpha)
    local Pos, Ang = ControllerFrame(Info, Controller)
    local M = Matrix()
    M:SetTranslation(Pos)
    M:SetAngles(Ang)
    M:Scale(GetScale(Controller))

    local ClipCount, PrevClip = 0, nil
    if istable(Controller.clips) and #Controller.clips > 0 then
        PrevClip = render.EnableClipping(true)
        for _, Clip in ipairs(Controller.clips) do
            if istable(Clip) and isnumber(Clip[4]) then
                local Normal = Vector(Clip[1], Clip[2], Clip[3])
                Normal:Rotate(Ang)
                render.PushCustomClipPlane(Normal, Normal:Dot(Pos + Normal * Clip[4]))
                ClipCount = ClipCount + 1
            end
        end
    end

    local Col = View.Settings.ColorByClass and DupeEditor.ClassColor(Info.Class)
        or (DupeEditor.IsColorTable(Controller.col) and Controller.col) or color_white
    render.SetColorModulation(Col.r / 255, Col.g / 255, Col.b / 255)
    render.SetBlend(Alpha or math.max((Col.a or 255) / 255, 0.1))
    render.SetMaterial(GetMaterial(Controller.mat))

    cam.PushModelMatrix(M)
    for _, IM in ipairs(Entry.Meshes) do
        if IsValid(IM) then IM:Draw() end
    end
    cam.PopModelMatrix()

    for _ = 1, ClipCount do
        render.PopCustomClipPlane()
    end
    if PrevClip ~= nil then render.EnableClipping(PrevClip) end
end

local function GetControllerEnts(View, Session)
    local Cache = View:GetLayerCache("Prop2Mesh")
    if not Cache.List then
        local List = {}
        for Idx, EntData in pairs(Session.Dupe.Entities) do
            if P2M_CLASSES[EntData.Class] and GetP2M(EntData) then List[#List + 1] = Idx end
        end
        Cache.List = List
    end
    return Cache.List, Cache
end

-- Calls Fn(Idx, Info, Controller, Entry) for every controller with a built mesh
local function ForEachReady(View, Session, Fn)
    local List = GetControllerEnts(View, Session)
    local Ents = Session.Dupe.Entities
    for _, Idx in ipairs(List) do
        local Info = View.Models[Idx]
        local EntData = Ents[Idx]
        local Controllers, Partlists = GetP2M(EntData or {})
        if Info and Controllers then
            for _, Controller in ipairs(Controllers) do
                local Data = istable(Controller) and Partlists[Controller.crc]
                if isstring(Data) then
                    local Entry = GetMesh(Data, Controller.crc, UniqueID(Controller))
                    if Entry.State == "ready" then Fn(Idx, Info, Controller, Entry) end
                end
            end
        end
    end
end

local PartEnt
local function GetPartEnt()
    if not IsValid(PartEnt) then
        PartEnt = ClientsideModel("models/error.mdl", RENDERGROUP_OPAQUE)
        PartEnt:SetNoDraw(true)
    end
    return PartEnt
end

local function DrawHighlightedPart(View, Session)
    local Hl = DupeEditor.P2MHighlight
    if not Hl or Hl.Session ~= Session then return end
    local Info = View.Models[Hl.Idx]
    local EntData = Session.Dupe.Entities[Hl.Idx]
    if not Info or not EntData then return end
    local Controllers, Partlists = GetP2M(EntData)
    local Controller = Controllers and Controllers[Hl.Controller]
    local Parts = Controller and GetParts(Partlists, Controller.crc)
    local Part = Parts and Parts[Hl.Part]
    local Model = Part and (Part.prop or Part.holo)
    if not isstring(Model) then return end

    local Pos, Ang = ControllerFrame(Info, Controller)
    local M = Matrix()
    M:SetTranslation(Pos)
    M:SetAngles(Ang)
    M:Scale(GetScale(Controller))
    local PartM = Matrix()
    PartM:SetTranslation(isvector(Part.pos) and Part.pos or vector_origin)
    PartM:SetAngles(isangle(Part.ang) and Part.ang or angle_zero)
    if isvector(Part.scale) then PartM:Scale(Part.scale) end

    local Ent = GetPartEnt()
    if Ent:GetModel() ~= Model then Ent:SetModel(Model) end
    Ent:SetPos(vector_origin)
    Ent:SetAngles(angle_zero)
    Ent:EnableMatrix("RenderMultiply", M * PartM)

    cam.IgnoreZ(true)
    render.ModelMaterialOverride(WireframeMat)
    render.SetColorModulation(1, 0.67, 0.16)
    render.SetBlend(1)
    Ent:DrawModel()
    render.ModelMaterialOverride()
    cam.IgnoreZ(false)
    render.SetColorModulation(1, 1, 1)
end

local function ScaledBounds(Entry, Controller)
    local S = GetScale(Controller)
    local Mins = Vector(Entry.Mins.x * S.x, Entry.Mins.y * S.y, Entry.Mins.z * S.z)
    local Maxs = Vector(Entry.Maxs.x * S.x, Entry.Maxs.y * S.y, Entry.Maxs.z * S.z)
    OrderVectors(Mins, Maxs)
    return Mins, Maxs
end

DupeEditor.RegisterLayer("Prop2Mesh", {
    Label = "Prop2Mesh",
    Icon = "icon16/shape_group.png",
    Default = true,
    Draw3D = function(View, Session, XRay)
        Users[View] = true
        local Selected, Hidden = Session.Selected, Session.Hidden
        ForEachReady(View, Session, function(Idx, Info, Controller, Entry)
            if Hidden[Idx] then return end
            if XRay and not Selected[Idx] then
                render.OverrideDepthEnable(true, false)
                DrawController(View, Info, Controller, Entry, 0.08)
                render.OverrideDepthEnable(false)
            else
                DrawController(View, Info, Controller, Entry)
            end
        end)
        render.SetColorModulation(1, 1, 1)
        render.SetBlend(1)
    end,
    PostDraw3D = function(View, Session)
        local Selected = Session.Selected
        ForEachReady(View, Session, function(Idx, Info, Controller, Entry)
            if not Selected[Idx] or not Entry.Mins then return end
            local Pos, Ang = ControllerFrame(Info, Controller)
            local Mins, Maxs = ScaledBounds(Entry, Controller)
            render.DrawWireframeBox(Pos, Ang, Mins, Maxs, SELECT_COLOR, false)
        end)
        DrawHighlightedPart(View, Session)
    end,
    Draw2D = function(_, _, _, H)
        local Building = 0
        for _, Entry in pairs(Meshes) do
            if Entry.State == "building" then Building = Building + 1 end
        end
        if Building > 0 then
            DupeEditor.DrawViewLabel("building " .. Building .. " prop2mesh meshes...", 8, H - 46, "DermaDefault", color_white)
        end
    end,
    GetPickBoxes = function(View, Session)
        local Boxes = {}
        ForEachReady(View, Session, function(Idx, Info, Controller, Entry)
            if not Entry.Mins then return end
            local Pos, Ang = ControllerFrame(Info, Controller)
            local Mins, Maxs = ScaledBounds(Entry, Controller)
            Boxes[#Boxes + 1] = {Idx, Pos, Ang, Mins, Maxs}
        end)
        return Boxes
    end,
    Cleanup = function(View)
        Users[View] = nil
        for Other in pairs(Users) do
            if not IsValid(Other) then Users[Other] = nil end
        end
        if next(Users) == nil then
            DestroyAll()
            if IsValid(PartEnt) then PartEnt:Remove() end
        end
    end,
})

--------------------------------------------------------------------------------
-- Class tool
--------------------------------------------------------------------------------

local function PartType(Part)
    if Part.prop then return "prop", Part.prop end
    if Part.holo then return "holo", Part.holo end
    if Part.objd then return "obj", tostring(Part.objn or Part.objd) end
    if Part.primitive then return "primitive", tostring(istable(Part.primitive) and Part.primitive.construct or "?") end
    return "?", ""
end

local function FormatVec(V)
    if not isvector(V) and not isangle(V) then return "" end
    return string.format("%.2f %.2f %.2f", V[1], V[2], V[3])
end

local function OpenPartsWindow(Session, EntIdx, Controller, ControllerIdx, Partlists)
    local Frame = vgui.Create("DFrame")
    Frame:SetTitle("Prop2Mesh Parts - [" .. EntIdx .. "] controller #" .. ControllerIdx)
    Frame:SetSize(math.min(900, ScrW() - 100), math.min(600, ScrH() - 100))
    Frame:Center()
    Frame:SetSizable(true)
    Frame:DockPadding(6, 30, 6, 6)
    Frame:MakePopup()

    local Hint = Frame:Add("DLabel")
    Hint:Dock(BOTTOM)
    Hint:DockMargin(0, 4, 0, 0)
    Hint:SetText("Click a part to see it in the 3D view, right click to remove")

    local List = Frame:Add("DListView")
    List:Dock(FILL)
    List:SetMultiSelect(true)
    List:AddColumn("#"):SetFixedWidth(40)
    List:AddColumn("Type"):SetFixedWidth(70)
    List:AddColumn("Source")
    List:AddColumn("Pos")
    List:AddColumn("Ang")
    List:AddColumn("Scale")

    local function Refresh()
        List:Clear()
        local Parts = GetParts(Partlists, Controller.crc)
        if not Parts then return end
        for I, Part in ipairs(Parts) do
            local Type, Source = PartType(Part)
            local Line = List:AddLine(I, Type, Source, FormatVec(Part.pos), FormatVec(Part.ang), FormatVec(Part.scale))
            Line:SetSortValue(1, I)
            Line.PartIdx = I
        end
    end

    function List.OnRowSelected(_, _, Line)
        DupeEditor.P2MHighlight = {Session = Session, Idx = EntIdx, Controller = ControllerIdx, Part = Line.PartIdx}
    end

    function List.OnRowRightClick()
        local Selected = List:GetSelected()
        local Menu = DermaMenu()
        Menu:AddOption("Remove " .. #Selected .. " Part(s)", function()
            local Parts = GetParts(Partlists, Controller.crc)
            if not Parts then return end
            local Remove = {}
            for _, Line in ipairs(Selected) do Remove[Line.PartIdx] = true end
            local New = {custom = Parts.custom}
            for I, Part in ipairs(Parts) do
                if not Remove[I] then New[#New + 1] = Part end
            end
            WriteParts(Session, Controller, Partlists, New)
            DupeEditor.P2MHighlight = nil
            Session:Emit("FocusChanged")
            Refresh()
        end):SetIcon("icon16/delete.png")
        if #Selected == 1 then
            local Parts = GetParts(Partlists, Controller.crc)
            local Part = Parts and Parts[Selected[1].PartIdx]
            local _, Source = PartType(Part or {})
            Menu:AddOption("Copy Source", function() SetClipboardText(Source) end):SetIcon("icon16/page_copy.png")
        end
        Menu:Open()
    end

    function Frame.OnClose()
        DupeEditor.P2MHighlight = nil
    end

    Refresh()
end

local function AddRow(Panel, Label)
    local Row = Panel:Add("DPanel")
    Row:Dock(TOP)
    Row:DockMargin(0, 4, 0, 0)
    Row:SetTall(22)
    Row:SetPaintBackground(false)

    local Lbl = Row:Add("DLabel")
    Lbl:Dock(LEFT)
    Lbl:SetWide(80)
    Lbl:SetDark(true)
    Lbl:SetText(Label)
    return Row
end

local function BuildControllerEditor(Panel, Session, EntIdx, Controller, Index, Partlists)
    Panel:Clear()

    local NameRow = AddRow(Panel, "Name")
    local Name = NameRow:Add("DTextEntry")
    Name:Dock(FILL)
    Name:SetText(isstring(Controller.name) and Controller.name or "")
    function Name:OnChange() Session:Set(Controller, "name", self:GetText()) end

    local MatRow = AddRow(Panel, "Material")
    local Mat = MatRow:Add("DTextEntry")
    Mat:Dock(FILL)
    Mat:SetText(isstring(Controller.mat) and Controller.mat or "")
    function Mat:OnChange() Session:Set(Controller, "mat", self:GetText()) end

    local ColRow = AddRow(Panel, "Color")
    local Swatch = ColRow:Add("DButton")
    Swatch:Dock(FILL)
    Swatch:SetText("")
    function Swatch:Paint(W, H)
        local Col = DupeEditor.IsColorTable(Controller.col) and Controller.col or color_white
        surface.SetDrawColor(Col.r, Col.g, Col.b, 255)
        surface.DrawRect(0, 0, W, H)
        surface.SetDrawColor(0, 0, 0, 180)
        surface.DrawOutlinedRect(0, 0, W, H)
        draw.SimpleText("a " .. (Col.a or 255), "DermaDefault", 6, H / 2, (Col.r + Col.g + Col.b) > 380 and color_black or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    function Swatch.DoClick()
        local Frame = vgui.Create("DFrame")
        Frame:SetTitle("Controller Color")
        Frame:SetSize(300, 260)
        Frame:Center()
        Frame:MakePopup()
        local Mixer = Frame:Add("DColorMixer")
        Mixer:Dock(FILL)
        Mixer:SetAlphaBar(true)
        local Col = DupeEditor.IsColorTable(Controller.col) and Controller.col or color_white
        Mixer:SetColor(Color(Col.r, Col.g, Col.b, Col.a or 255))
        function Mixer.ValueChanged(_, New)
            Session:Set(Controller, "col", {r = New.r, g = New.g, b = New.b, a = New.a})
        end
    end

    local ScaleRow = AddRow(Panel, "Scale")
    local Wangs = {}
    for I = 3, 1, -1 do
        local Wang = ScaleRow:Add("DNumberWang")
        Wang:Dock(RIGHT)
        Wang:DockMargin(4, 0, 0, 0)
        Wang:SetMin(-math.huge)
        Wang:SetMax(math.huge)
        Wang:SetDecimals(4)
        Wang:SetValue(GetScale(Controller)[I])
        function Wang.OnValueChanged(_, V)
            local New = Vector(GetScale(Controller))
            New[I] = V
            Session:Set(Controller, "scale", New)
        end
        Wangs[I] = Wang
    end
    function ScaleRow.PerformLayout(_, W)
        local Each = math.floor((W - 80 - 12) / 3)
        for I = 1, 3 do Wangs[I]:SetWide(Each) end
    end

    local UVRow = AddRow(Panel, "UV Scale")
    local UV = UVRow:Add("DNumberWang")
    UV:Dock(LEFT)
    UV:SetWide(80)
    UV:SetMin(0)
    UV:SetMax(512)
    UV:SetDecimals(0)
    UV:SetValue(tonumber(Controller.uvs) or 0)
    function UV.OnValueChanged(_, V) Session:Set(Controller, "uvs", math.floor(V)) end

    local Bump = UVRow:Add("DCheckBoxLabel")
    Bump:Dock(LEFT)
    Bump:DockMargin(12, 3, 0, 0)
    Bump:SetText("Bumpmap?")
    Bump:SetDark(true)
    Bump:SetValue(Controller.bump == true)
    function Bump.OnChange(_, V) Session:Set(Controller, "bump", V) end

    local Buttons = AddRow(Panel, "")
    local Parts = Buttons:Add("DButton")
    Parts:Dock(LEFT)
    Parts:SetText("Parts...")
    Parts:SetImage("icon16/application_view_list.png")
    Parts:SizeToContentsX(34)
    Parts.DoClick = function() OpenPartsWindow(Session, EntIdx, Controller, Index, Partlists) end

    local ClipCount = istable(Controller.clips) and #Controller.clips or 0
    local Clips = Buttons:Add("DButton")
    Clips:Dock(LEFT)
    Clips:DockMargin(4, 0, 0, 0)
    Clips:SetText("Clear Clips (" .. ClipCount .. ")")
    Clips:SetImage("icon16/cut.png")
    Clips:SizeToContentsX(34)
    Clips:SetEnabled(ClipCount > 0)
    function Clips.DoClick()
        Session:Set(Controller, "clips", {})
        Session:Emit("FocusChanged")
    end

    Panel:InvalidateLayout(true)
    Panel:SizeToChildren(false, true)
end

DupeEditor.RegisterClassTool(table.GetKeys(P2M_CLASSES), {
    Name = "Prop2Mesh",
    Icon = "icon16/shape_group.png",
    ShouldShow = function(EntData) return GetP2M(EntData) ~= nil end,
    Build = function(Panel, Ctx)
        local Session, EntIdx = Ctx.Session, Ctx.EntIdx
        local Controllers, Partlists = GetP2M(Ctx.EntData)

        local TotalParts, TotalSize = 0, 0
        for _, Data in pairs(Partlists) do
            if isstring(Data) then TotalSize = TotalSize + #Data end
        end
        for _, Controller in ipairs(Controllers) do
            local Parts = istable(Controller) and GetParts(Partlists, Controller.crc)
            if Parts then TotalParts = TotalParts + #Parts end
        end

        Ctx.AddLine("Controllers", tostring(#Controllers))
        Ctx.AddLine("Parts", tostring(TotalParts))
        Ctx.AddLine("Data", table.Count(Partlists) .. " partlists, " .. string.NiceSize(TotalSize) .. " zipped")
        if not (prop2mesh and prop2mesh.getMesh) then
            Ctx.AddLine("Note", "Prop2Mesh isn't installed (no 3D preview)")
        end

        local List = Panel:Add("DListView")
        List:Dock(TOP)
        List:DockMargin(0, 4, 0, 0)
        List:SetMultiSelect(false)
        List:AddColumn("#"):SetFixedWidth(28)
        List:AddColumn("Name")
        List:AddColumn("Material")
        List:AddColumn("Parts"):SetFixedWidth(44)
        List:SetTall(math.Clamp(#Controllers * 17 + 20, 40, 200))

        for I, Controller in ipairs(Controllers) do
            if istable(Controller) then
                local Parts = GetParts(Partlists, Controller.crc)
                local Line = List:AddLine(I, tostring(Controller.name or ""), tostring(Controller.mat or ""), Parts and #Parts or "-")
                Line:SetSortValue(1, I)
                Line.Controller, Line.Index = Controller, I
            end
        end

        local Editor = Panel:Add("DPanel")
        Editor:Dock(TOP)
        Editor:DockMargin(0, 4, 0, 0)
        Editor:SetPaintBackground(false)
        Editor:SetTall(0)

        function List.OnRowSelected(_, _, Line)
            BuildControllerEditor(Editor, Session, EntIdx, Line.Controller, Line.Index, Partlists)
            Panel:InvalidateLayout(true)
            Panel:SizeToChildren(false, true)
            if Ctx.Relayout then Ctx.Relayout() end
        end

        if #Controllers == 1 then
            List:SelectFirstItem()
        end
    end,
})

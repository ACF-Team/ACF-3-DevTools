local DupeEditor = ACF_DevTools.DupeEditor

local WireframeMat = Material("models/wireframe")

local BG_COLOR         = Color(24, 28, 38)
local GRID_COLOR       = Color(255, 255, 255, 12)
local GRID_MAJOR_COLOR = Color(255, 255, 255, 30)
local AXIS_X_COLOR     = Color(255, 90, 90, 160)
local AXIS_Y_COLOR     = Color(90, 255, 90, 160)
local AXIS_Z_COLOR     = Color(90, 140, 255, 160)
local SELECT_COLOR     = Color(255, 170, 40)
local SELECT2_COLOR    = Color(255, 220, 140)
local HOVER_COLOR      = Color(140, 200, 255)
local HEAD_COLOR       = Color(255, 240, 90)
local TEXT_COLOR       = Color(235, 238, 245)
local TEXT_DIM_COLOR   = Color(160, 168, 185)
local LABEL_BG_COLOR   = Color(10, 12, 18, 200)

local METER = 39.37

local function GetModelName(Model)
    if not isstring(Model) or string.sub(Model, -4) ~= ".mdl" then return "models/error.mdl" end
    if not file.Exists(Model, "GAME") then return "models/error.mdl" end
    return Model
end

local function DrawLabel(Text, X, Y, Font, Col, AlignX)
    surface.SetFont(Font)
    local W, H = surface.GetTextSize(Text)
    if AlignX == TEXT_ALIGN_CENTER then X = X - W / 2 end
    surface.SetDrawColor(LABEL_BG_COLOR)
    surface.DrawRect(X - 4, Y - 2, W + 8, H + 4)
    surface.SetTextColor(Col)
    surface.SetTextPos(X, Y)
    surface.DrawText(Text)
    return W, H
end
DupeEditor.DrawViewLabel = DrawLabel

--------------------------------------------------------------------------------
-- Canvas
--------------------------------------------------------------------------------

local CANVAS = {}

function CANVAS:Init()
    self.Models     = {}
    self.Queue      = {}
    self.QueueCount = 0
    self.Version    = 0
    self.CamAng     = Angle(25, 135, 0)
    self.Target     = Vector()
    self.GoalTarget = Vector()
    self.Dist       = 400
    self.GoalDist   = 400
    self.FOV        = 60
    self.Radius     = 200
    self.LayerCache = {}
    self.LayerState = {}
    self.Settings   = {
        ColorByClass = cookie.GetNumber("acf_dupeeditor_classcolors", 0) == 1,
        XRay         = false,
    }

    for _, Name in ipairs(DupeEditor.LayerOrder) do
        local Def = DupeEditor.Layers[Name]
        self.LayerState[Name] = cookie.GetNumber("acf_dupeeditor_layer_" .. Name, Def.Default and 1 or 0) == 1
    end

    self:SetMouseInputEnabled(true)
end

function CANVAS:SetSession(Session)
    self.Session = Session
    Session:Listen("StructureChanged", self, function() self:Sync() end)
    Session:Listen("ValueChanged", self, function() self.NeedsSync = true end)
    Session:Listen("FocusRequest", self, function(List) self:FocusEntities(List) end)
    Session:Listen("VisibilityChanged", self, function() self.HoverIdx = nil end)
    self:Sync()
    self.PendingFrame = true
end

function CANVAS:IsLayerEnabled(Name)
    return self.LayerState[Name] == true
end

function CANVAS:SetLayerEnabled(Name, Enabled)
    self.LayerState[Name] = Enabled
    cookie.Set("acf_dupeeditor_layer_" .. Name, Enabled and 1 or 0)
end

function CANVAS:SetSetting(Name, Value)
    self.Settings[Name] = Value
    if Name == "ColorByClass" then cookie.Set("acf_dupeeditor_classcolors", Value and 1 or 0) end
end

-- Per-layer scratch data that's thrown away whenever the dupe changes
function CANVAS:GetLayerCache(Name)
    local Cache = self.LayerCache[Name]
    if not Cache or Cache.Version ~= self.Version then
        Cache = {Version = self.Version}
        self.LayerCache[Name] = Cache
    end
    return Cache
end

function CANVAS:CallLayers(Method, ...)
    for _, Name in ipairs(DupeEditor.LayerOrder) do
        local Def = DupeEditor.Layers[Name]
        if self.LayerState[Name] and Def[Method] then
            Def[Method](self, self.Session, ...)
        end
    end
end

-- Model sync

function CANVAS:Sync()
    local Ents = self.Session.Dupe.Entities
    for Idx in pairs(self.Models) do
        if not Ents[Idx] then self:RemoveModel(Idx) end
    end
    for Idx, EntData in pairs(Ents) do
        self:SyncEntity(Idx, EntData)
    end
    self.NeedsSync = false
    self.LastSync = RealTime()
    self.Version = self.Version + 1
end

function CANVAS:RemoveModel(Idx)
    local Info = self.Models[Idx]
    if Info and IsValid(Info.Ent) then Info.Ent:Remove() end
    self.Models[Idx] = nil
    if self.Queue[Idx] then
        self.Queue[Idx] = nil
        self.QueueCount = self.QueueCount - 1
    end
end

function CANVAS:SyncEntity(Idx, EntData)
    local Info = self.Models[Idx]
    if not Info then
        Info = {}
        self.Models[Idx] = Info
    end

    if Info.RawModel ~= EntData.Model then
        Info.RawModel = EntData.Model
        local Model = GetModelName(EntData.Model)
        if Info.Model ~= Model then
            if IsValid(Info.Ent) then Info.Ent:Remove() end
            Info.Ent = nil
            Info.Model = Model
            Info.Failed = nil
            if not self.Queue[Idx] then
                self.Queue[Idx] = true
                self.QueueCount = self.QueueCount + 1
            end
        end
    end

    local Pos, Ang = DupeEditor.GetTransform(EntData)
    Info.Pos   = Vector(Pos)
    Info.Ang   = Angle(Ang)
    Info.Class = EntData.Class
    Info.Scale = tonumber(EntData.ModelScale) or 1
    Info.Skin  = tonumber(EntData.Skin) or 0
    Info.BodyG = istable(EntData.BodyG) and EntData.BodyG or nil

    local Mods = istable(EntData.EntityMods) and EntData.EntityMods or {}
    local Colour = istable(Mods.colour) and Mods.colour.Color
    Info.Color = DupeEditor.IsColorTable(Colour) and Colour or nil
    local Mat = istable(Mods.material) and Mods.material.MaterialOverride
    Info.Material = isstring(Mat) and Mat or ""

    if IsValid(Info.Ent) then
        self:ApplyAppearance(Info)
    else
        Info.Mins = Info.Mins or Vector(-4, -4, -4)
        Info.Maxs = Info.Maxs or Vector(4, 4, 4)
        Info.Center = Info.Pos
    end
end

function CANVAS:ApplyAppearance(Info)
    local Ent = Info.Ent
    Ent:SetPos(Info.Pos)
    Ent:SetAngles(Info.Ang)
    Ent:SetSkin(Info.Skin)
    Ent:SetMaterial(Info.Material)
    if Info.BodyG then
        for Id, Value in pairs(Info.BodyG) do
            Ent:SetBodygroup(tonumber(Id) or 0, tonumber(Value) or 0)
        end
    end

    local Scale = Info.Scale
    if Scale ~= 1 then
        local M = Matrix()
        M:Scale(Vector(Scale, Scale, Scale))
        Ent:EnableMatrix("RenderMultiply", M)
    else
        Ent:DisableMatrix("RenderMultiply")
    end

    local Mins, Maxs = Ent:GetModelBounds()
    Info.Mins = Mins * Scale
    Info.Maxs = Maxs * Scale
    Info.Center = LocalToWorld((Info.Mins + Info.Maxs) * 0.5, angle_zero, Info.Pos, Info.Ang)
end

function CANVAS:ProcessQueue()
    if self.QueueCount <= 0 then return end

    local Budget = 48
    for Idx in pairs(self.Queue) do
        self.Queue[Idx] = nil
        self.QueueCount = self.QueueCount - 1

        local Info = self.Models[Idx]
        if Info then
            local Ent = ClientsideModel(Info.Model, RENDERGROUP_OPAQUE)
            if IsValid(Ent) then
                Ent:SetNoDraw(true)
                Ent:DrawShadow(false)
                Info.Ent = Ent
                self:ApplyAppearance(Info)
            else
                Info.Failed = true
            end
        end

        Budget = Budget - 1
        if Budget <= 0 then break end
    end

    if self.QueueCount <= 0 then
        self.Version = self.Version + 1
        if self.PendingFrame then
            self.PendingFrame = nil
            self:FrameAll(true)
        end
    end
end

function CANVAS:OnRemove()
    for Idx in pairs(self.Models) do
        self:RemoveModel(Idx)
    end
    for _, Name in ipairs(DupeEditor.LayerOrder) do
        local Def = DupeEditor.Layers[Name]
        if Def.Cleanup then Def.Cleanup(self) end
    end
end

-- Camera

function CANVAS:GetCamera()
    return self.Target - self.CamAng:Forward() * self.Dist, self.CamAng
end

-- Uses util.AimVector so picking matches whatever cam.Start3D does with the FOV
function CANVAS:GetProjectionScale(W, H)
    if self.ProjW == W and self.ProjH == H and self.ProjFOV == self.FOV then return self.ProjScale end
    local Dir = util.AimVector(angle_zero, self.FOV, W / 2 + 100, H / 2, W, H)
    self.ProjScale = 100 / (Dir.y ~= 0 and math.abs(Dir.y / Dir.x) or 1)
    self.ProjW, self.ProjH, self.ProjFOV = W, H, self.FOV
    return self.ProjScale
end

function CANVAS:ScreenRay(X, Y)
    local CamPos, CamAng = self:GetCamera()
    local W, H = self:GetSize()
    return CamPos, util.AimVector(CamAng, self.FOV, X, Y, W, H)
end

function CANVAS:Project(Pos)
    local CamPos, CamAng = self:GetCamera()
    local W, H = self:GetSize()
    local Delta = Pos - CamPos
    local Forward = Delta:Dot(CamAng:Forward())
    if Forward <= 0.1 then return end
    local Scale = self:GetProjectionScale(W, H)
    return W / 2 + Delta:Dot(CamAng:Right()) / Forward * Scale, H / 2 - Delta:Dot(CamAng:Up()) / Forward * Scale
end

local function ExpandBounds(Mins, Maxs, Info)
    local A, B = Info.Mins, Info.Maxs
    for I = 0, 7 do
        local Corner = Vector(bit.band(I, 1) == 0 and A.x or B.x, bit.band(I, 2) == 0 and A.y or B.y, bit.band(I, 4) == 0 and A.z or B.z)
        local World = LocalToWorld(Corner, angle_zero, Info.Pos, Info.Ang)
        Mins.x, Mins.y, Mins.z = math.min(Mins.x, World.x), math.min(Mins.y, World.y), math.min(Mins.z, World.z)
        Maxs.x, Maxs.y, Maxs.z = math.max(Maxs.x, World.x), math.max(Maxs.y, World.y), math.max(Maxs.z, World.z)
    end
end

function CANVAS:GetEntityBounds(List)
    local Mins = Vector(math.huge, math.huge, math.huge)
    local Maxs = -Mins
    local Any = false
    for _, Idx in ipairs(List) do
        local Info = self.Models[Idx]
        if Info and Info.Mins then
            ExpandBounds(Mins, Maxs, Info)
            Any = true
        end
    end
    if not Any then return end
    return Mins, Maxs
end

function CANVAS:FocusEntities(List, Instant)
    local Mins, Maxs = self:GetEntityBounds(List)
    if not Mins then return end
    local Radius = math.max((Maxs - Mins):Length() * 0.5, 8)
    self.GoalTarget = (Mins + Maxs) * 0.5
    self.GoalDist = Radius / math.tan(math.rad(self.FOV * 0.5)) * 1.1
    if Instant then
        self.Target = Vector(self.GoalTarget)
        self.Dist = self.GoalDist
    end
end

function CANVAS:FrameAll(Instant)
    local List = {}
    for Idx in pairs(self.Models) do
        if not self.Session.Hidden[Idx] then List[#List + 1] = Idx end
    end
    local Mins, Maxs = self:GetEntityBounds(List)
    if Mins then self.Radius = math.max((Maxs - Mins):Length() * 0.5, 8) end
    self:FocusEntities(List, Instant)
end

function CANVAS:FocusSelection()
    local List = self.Session:GetSelectedList()
    if #List == 0 then return self:FrameAll() end
    self:FocusEntities(List)
end

-- Picking

function CANVAS:PickAll(X, Y)
    local Start, Dir = self:ScreenRay(X, Y)
    local Delta = Dir * 1000000
    local Hidden = self.Session.Hidden
    local Best = {}

    local function Test(Idx, Pos, Ang, Mins, Maxs)
        local Hit, _, Frac = util.IntersectRayWithOBB(Start, Delta, Pos, Ang, Mins, Maxs)
        if Hit and (not Best[Idx] or Frac < Best[Idx]) then Best[Idx] = Frac end
    end

    for Idx, Info in pairs(self.Models) do
        if not Hidden[Idx] and Info.Mins then
            Test(Idx, Info.Pos, Info.Ang, Info.Mins, Info.Maxs)
        end
    end

    for _, Name in ipairs(DupeEditor.LayerOrder) do
        local Def = DupeEditor.Layers[Name]
        if self.LayerState[Name] and Def.GetPickBoxes then
            for _, Box in ipairs(Def.GetPickBoxes(self, self.Session)) do
                if not Hidden[Box[1]] then Test(Box[1], Box[2], Box[3], Box[4], Box[5]) end
            end
        end
    end

    local Hits = {}
    for Idx, Frac in pairs(Best) do
        Hits[#Hits + 1] = {Idx, Frac}
    end
    table.sort(Hits, function(A, B) return A[2] < B[2] end)
    return Hits
end

function CANVAS:ClickSelect(X, Y)
    local Session = self.Session
    local Hits = self:PickAll(X, Y)
    local Ctrl, Shift = input.IsControlDown(), input.IsShiftDown()

    if #Hits == 0 then
        if not Ctrl and not Shift then Session:ClearSelection(self) end
        self.LastClick = nil
        return
    end

    local Now  = RealTime()
    local Last = self.LastClick
    local Same = Last and math.abs(Last.X - X) <= 3 and math.abs(Last.Y - Y) <= 3

    if Same and Now - Last.Time < 0.3 then
        self.LastClick = nil
        self:FocusEntities({Last.Idx})
        return
    end

    -- Clicking the same spot again goes to the next thing under the cursor
    local Cycle = 1
    if Same and Last.Count == #Hits then Cycle = Last.Cycle % #Hits + 1 end
    local Pick = Hits[Cycle][1]
    self.LastClick = {X = X, Y = Y, Time = Now, Cycle = Cycle, Count = #Hits, Idx = Pick}

    if Ctrl then
        Session:Select(Pick, "toggle", self)
    elseif Shift then
        Session:Select(Pick, "add", self)
    else
        Session:Select(Pick, nil, self)
    end
end

function CANVAS:OpenContextMenu(X, Y)
    local Session = self.Session
    local Hits = self:PickAll(X, Y)
    local Pick = Hits[1] and Hits[1][1]
    if Pick and not Session:IsSelected(Pick) then
        Session:Select(Pick, nil, self)
    end

    local Menu = DermaMenu()
    DupeEditor.AddEntityOptions(Menu, Session)
    Menu:AddSpacer()
    Menu:AddOption("Frame All", function() self:FrameAll() end):SetIcon("icon16/arrow_out.png")
    Menu:Open()
end

-- Input

function CANVAS:OnMousePressed(Code)
    self:MouseCapture(true)
    local X, Y = self:CursorPos()
    self.Press = {Code = Code, X = X, Y = Y, LastX = X, LastY = Y, Moved = false}
end

function CANVAS:OnMouseReleased(Code)
    self:MouseCapture(false)
    local Press = self.Press
    self.Press = nil
    if not Press or Press.Code ~= Code or Press.Moved then return end

    local X, Y = self:CursorPos()
    if Code == MOUSE_LEFT then
        self:ClickSelect(X, Y)
    elseif Code == MOUSE_RIGHT then
        self:OpenContextMenu(X, Y)
    end
end

function CANVAS:OnMouseWheeled(Delta)
    self.GoalDist = math.Clamp(self.GoalDist * (0.85 ^ Delta), 2, 500000)
    return true
end

function CANVAS:Think()
    if not self.Session then return end
    self:ProcessQueue()
    if self.NeedsSync and RealTime() - (self.LastSync or 0) > 0.1 then self:Sync() end

    local X, Y = self:CursorPos()
    local Press = self.Press
    if Press then
        if not Press.Moved and math.abs(X - Press.X) + math.abs(Y - Press.Y) > 3 then Press.Moved = true end
        if Press.Moved then
            local DX, DY = X - Press.LastX, Y - Press.LastY
            if Press.Code == MOUSE_LEFT and not input.IsShiftDown() then
                self.CamAng.y = self.CamAng.y - DX * 0.4
                self.CamAng.p = math.Clamp(self.CamAng.p + DY * 0.4, -89, 89)
            else
                local Scale = self.Dist * 0.0018
                local Move = self.CamAng:Right() * (-DX * Scale) + self.CamAng:Up() * (DY * Scale)
                self.Target = self.Target + Move
                self.GoalTarget = self.GoalTarget + Move
            end
        end
        Press.LastX, Press.LastY = X, Y
    elseif self:IsHovered() then
        if X ~= self.HoverX or Y ~= self.HoverY or self.HoverVersion ~= self.Version then
            self.HoverX, self.HoverY, self.HoverVersion = X, Y, self.Version
            local Hits = self:PickAll(X, Y)
            self.HoverIdx = Hits[1] and Hits[1][1]
            self.HoverCount = #Hits
        end
    else
        self.HoverIdx = nil
        self.HoverX = nil
    end

    local T = math.min(FrameTime() * 14, 1)
    self.Target = LerpVector(T, self.Target, self.GoalTarget)
    self.Dist = Lerp(T, self.Dist, self.GoalDist)
end

-- Drawing

function CANVAS:DrawInfo(Info, Alpha)
    local Col = self.Settings.ColorByClass and DupeEditor.ClassColor(Info.Class) or Info.Color
    local A = Alpha or 1
    if Col then
        render.SetColorModulation((Col.r or 255) / 255, (Col.g or 255) / 255, (Col.b or 255) / 255)
        if not Alpha then A = math.max((Col.a or 255) / 255, 0.1) end
    else
        render.SetColorModulation(1, 1, 1)
    end
    render.SetBlend(A)
    Info.Ent:DrawModel()
end

local function DrawFallbackBox(Info, Col)
    render.DrawWireframeBox(Info.Pos, Info.Ang, Info.Mins, Info.Maxs, Col, true)
end

function CANVAS:Render3D()
    local Session = self.Session
    local Selected = Session.Selected
    local Hidden = Session.Hidden
    local XRay = self.Settings.XRay and next(Selected) ~= nil

    render.SuppressEngineLighting(true)
    render.SetLightingOrigin(self.Target)
    render.ResetModelLighting(0.3, 0.32, 0.36)
    render.SetModelLighting(BOX_TOP, 1, 1, 1)
    render.SetModelLighting(BOX_FRONT, 0.62, 0.62, 0.66)
    render.SetModelLighting(BOX_BACK, 0.45, 0.45, 0.5)
    render.SetModelLighting(BOX_LEFT, 0.55, 0.55, 0.6)
    render.SetModelLighting(BOX_RIGHT, 0.7, 0.7, 0.74)
    render.SetModelLighting(BOX_BOTTOM, 0.18, 0.18, 0.22)

    self:CallLayers("PreDraw3D")

    for Idx, Info in pairs(self.Models) do
        if not Hidden[Idx] and (not XRay or Selected[Idx]) then
            if IsValid(Info.Ent) then
                self:DrawInfo(Info)
            elseif Info.Failed then
                DrawFallbackBox(Info, TEXT_DIM_COLOR)
            end
        end
    end

    render.SetColorModulation(1, 1, 1)
    render.SetBlend(1)
    self:CallLayers("Draw3D", XRay)

    if XRay then
        render.OverrideDepthEnable(true, false)
        for Idx, Info in pairs(self.Models) do
            if not Hidden[Idx] and not Selected[Idx] and IsValid(Info.Ent) then
                self:DrawInfo(Info, 0.1)
            end
        end
        render.OverrideDepthEnable(false)
    end

    -- Selection on top of everything
    cam.IgnoreZ(true)
    render.ModelMaterialOverride(WireframeMat)
    for Idx in pairs(Selected) do
        local Info = self.Models[Idx]
        if Info and IsValid(Info.Ent) and not Hidden[Idx] then
            local Col = Idx == Session.Primary and SELECT_COLOR or SELECT2_COLOR
            render.SetColorModulation(Col.r / 255, Col.g / 255, Col.b / 255)
            render.SetBlend(0.35)
            Info.Ent:DrawModel()
        end
    end
    render.ModelMaterialOverride()
    cam.IgnoreZ(false)
    render.SetColorModulation(1, 1, 1)
    render.SetBlend(1)

    for Idx in pairs(Selected) do
        local Info = self.Models[Idx]
        if Info and Info.Mins and not Hidden[Idx] then
            render.DrawWireframeBox(Info.Pos, Info.Ang, Info.Mins, Info.Maxs, Idx == Session.Primary and SELECT_COLOR or SELECT2_COLOR, false)
        end
    end

    local Hover = self.HoverIdx and self.Models[self.HoverIdx]
    if Hover and Hover.Mins and not Selected[self.HoverIdx] then
        render.DrawWireframeBox(Hover.Pos, Hover.Ang, Hover.Mins, Hover.Maxs, HOVER_COLOR, false)
    end

    local Head = self.Models[Session.Dupe.HeadEnt.Index]
    if Head then
        local Size = math.Clamp(self.Dist * 0.02, 1, 40)
        render.DrawWireframeSphere(Head.Pos, Size, 8, 8, HEAD_COLOR, false)
    end

    self:CallLayers("PostDraw3D")
    DupeEditor.DrawActiveConstraint(self, Session)

    for _, Entry in ipairs(self.ActiveClassTools or {}) do
        if Entry[1].Draw3D then Entry[1].Draw3D(self, Entry[2]) end
    end

    render.SetColorModulation(1, 1, 1)
    render.SetBlend(1)
    render.SuppressEngineLighting(false)
end

function CANVAS:Render2D(W, H)
    local Session = self.Session
    self:CallLayers("Draw2D", W, H)

    local Hover = self.HoverIdx
    local EntData = Hover and Session.Dupe.Entities[Hover]
    if EntData and not self.Press then
        local X, Y = self:CursorPos()
        local Text = "[" .. Hover .. "] " .. tostring(EntData.Class)
        if (self.HoverCount or 0) > 1 then Text = Text .. "  (" .. self.HoverCount .. " under cursor)" end
        local _, TH = DrawLabel(Text, X + 16, Y + 12, "ACF_DupeEditor_Label", TEXT_COLOR)
        DrawLabel(tostring(EntData.Model), X + 16, Y + 16 + TH, "DermaDefault", TEXT_DIM_COLOR)
    end

    local Status = table.Count(Session.Dupe.Entities) .. " entities"
    local SelCount = Session:SelectionCount()
    if SelCount > 0 then Status = Status .. ", " .. SelCount .. " selected" end
    local HiddenCount = table.Count(Session.Hidden)
    if HiddenCount > 0 then Status = Status .. ", " .. HiddenCount .. " hidden" end
    if self.QueueCount > 0 then Status = Status .. "  |  loading models (" .. self.QueueCount .. " left)" end
    DrawLabel(Status, 8, H - 24, "DermaDefault", TEXT_COLOR)

    surface.SetFont("DermaDefault")
    local Help = "LMB: orbit/select | RMB: pan | Scroll: zoom | Double click: focus | Click again: next one behind"
    local HW = surface.GetTextSize(Help)
    if HW + 32 < W - 200 then
        DrawLabel(Help, W - HW - 8, H - 24, "DermaDefault", TEXT_DIM_COLOR)
    end
end

function CANVAS:Paint(W, H)
    surface.SetDrawColor(BG_COLOR)
    surface.DrawRect(0, 0, W, H)
    if not self.Session then return true end

    local X, Y = self:LocalToScreen(0, 0)
    local CamPos, CamAng = self:GetCamera()
    local Near = math.Clamp(self.Dist * 0.005, 0.5, 16)
    local Far = math.max(self.Dist + self.Radius * 8, 30000)

    cam.Start3D(CamPos, CamAng, self.FOV, X, Y, W, H, Near, Far)
        render.ClearDepth()
        local Ok, Err = pcall(self.Render3D, self)
        if not Ok then
            render.ModelMaterialOverride()
            render.SuppressEngineLighting(false)
            cam.IgnoreZ(false)
            render.OverrideDepthEnable(false)
            ErrorNoHalt("[Dupe Editor] " .. tostring(Err) .. "\n")
        end
    cam.End3D()

    self:Render2D(W, H)
    return true
end

vgui.Register("ACF_DupeViewCanvas", CANVAS, "DPanel")

--------------------------------------------------------------------------------
-- Viewport (toolbar + canvas)
--------------------------------------------------------------------------------

local VIEW = {}

function VIEW:Init()
    self:SetPaintBackground(false)

    self.Toolbar = self:Add("DPanel")
    self.Toolbar:Dock(TOP)
    self.Toolbar:SetTall(28)
    self.Toolbar:DockPadding(4, 4, 4, 4)

    self.Canvas = self:Add("ACF_DupeViewCanvas")
    self.Canvas:Dock(FILL)
end

function VIEW:AddToolButton(Icon, Tooltip, Gap)
    local Button = self.Toolbar:Add("DButton")
    Button:Dock(LEFT)
    Button:DockMargin(Gap and 10 or 0, 0, 4, 0)
    Button:SetSize(24, 20)
    Button:SetText("")
    Button:SetImage(Icon)
    Button:SetTooltip(Tooltip)
    return Button
end

function VIEW:AddToggle(Icon, Tooltip, Value, OnToggled, Gap)
    local Button = self:AddToolButton(Icon, Tooltip, Gap)
    Button:SetIsToggle(true)
    Button:SetToggle(Value)
    function Button:OnToggled(State) OnToggled(State) end
    return Button
end

function VIEW:SetSession(Session)
    local Canvas = self.Canvas
    Canvas:SetSession(Session)

    for I, Name in ipairs(DupeEditor.LayerOrder) do
        local Def = DupeEditor.Layers[Name]
        self:AddToggle(Def.Icon, "Show " .. Def.Label, Canvas:IsLayerEnabled(Name), function(State)
            Canvas:SetLayerEnabled(Name, State)
        end, I == 1 and false)
    end

    self:AddToggle("icon16/color_wheel.png", "Color by Class", Canvas.Settings.ColorByClass, function(State)
        Canvas:SetSetting("ColorByClass", State)
    end, true)
    self:AddToggle("icon16/eye.png", "X-Ray (see through to the selection)", Canvas.Settings.XRay, function(State)
        Canvas:SetSetting("XRay", State)
    end)

    local Frame = self:AddToolButton("icon16/arrow_out.png", "Frame All", true)
    Frame.DoClick = function() Canvas:FrameAll() end
    local Focus = self:AddToolButton("icon16/zoom.png", "Focus Selection")
    Focus.DoClick = function() Canvas:FocusSelection() end
    local Unhide = self:AddToolButton("icon16/lightbulb.png", "Unhide All")
    Unhide.DoClick = function() Session:UnhideAll() end
end

-- List of {Def, Ctx}
function VIEW:SetClassTools(Active)
    self.Canvas.ActiveClassTools = Active
end

vgui.Register("ACF_DupeViewport", VIEW, "DPanel")

--------------------------------------------------------------------------------
-- Built-in layers
--------------------------------------------------------------------------------

DupeEditor.RegisterLayer("Grid", {
    Label = "Grid",
    Icon = "icon16/application_view_tile.png",
    Default = true,
    PreDraw3D = function(View, Session)
        local Cache = View:GetLayerCache("Grid")
        if not Cache.Points then
            local List = table.GetKeys(View.Models)
            local Mins, Maxs = View:GetEntityBounds(List)
            Mins = Mins or Vector(-200, -200, 0)
            Maxs = Maxs or Vector(200, 200, 0)

            local Z = -(tonumber(Session.Dupe.HeadEnt.Z) or 0)
            if Z < Mins.z - 1 or Z > Maxs.z then Z = Mins.z end

            local Span = math.max(Maxs.x - Mins.x, Maxs.y - Mins.y, METER * 4)
            local Step = METER
            while Span / Step > 80 do Step = Step * 2 end

            local X0 = math.floor((Mins.x - Span * 0.25) / Step) * Step
            local X1 = math.ceil((Maxs.x + Span * 0.25) / Step) * Step
            local Y0 = math.floor((Mins.y - Span * 0.25) / Step) * Step
            local Y1 = math.ceil((Maxs.y + Span * 0.25) / Step) * Step

            local Points, Colors = {}, {}
            local function Add(A, B, Col)
                Points[#Points + 1] = A
                Points[#Points + 1] = B
                Colors[#Colors + 1] = Col
            end
            for X = X0, X1, Step do
                Add(Vector(X, Y0, Z), Vector(X, Y1, Z), math.Round(X / Step) % 5 == 0 and GRID_MAJOR_COLOR or GRID_COLOR)
            end
            for Y = Y0, Y1, Step do
                Add(Vector(X0, Y, Z), Vector(X1, Y, Z), math.Round(Y / Step) % 5 == 0 and GRID_MAJOR_COLOR or GRID_COLOR)
            end

            local Len = Step * 2
            local Origin = Vector(0, 0, Z)
            Add(Origin, Origin + Vector(Len, 0, 0), AXIS_X_COLOR)
            Add(Origin, Origin + Vector(0, Len, 0), AXIS_Y_COLOR)
            Add(Origin, Origin + Vector(0, 0, Len), AXIS_Z_COLOR)
            Cache.Points, Cache.Colors = Points, Colors
        end

        DupeEditor.DrawLineBatch(Cache.Points, Cache.Colors, true)
    end,
})

local ConstraintColors = {
    Weld          = Color(110, 150, 255),
    NoCollide     = Color(150, 150, 150, 90),
    Axis          = Color(255, 150, 60),
    Ballsocket    = Color(255, 230, 80),
    AdvBallsocket = Color(255, 210, 60),
    Rope          = Color(200, 150, 100),
    Elastic       = Color(120, 255, 140),
    Slider        = Color(255, 90, 200),
    Hydraulic     = Color(90, 230, 230),
    Muscle        = Color(90, 200, 230),
    Winch         = Color(200, 120, 255),
    Pulley        = Color(220, 160, 255),
    Motor         = Color(255, 80, 80),
    Keepupright   = Color(200, 200, 255),
}

function DupeEditor.ConstraintColor(Type)
    return ConstraintColors[Type] or DupeEditor.ClassColor(Type)
end

local function ConstraintPoint(View, Ent)
    local Info = View.Models[Ent.Index]
    if not Info then return end
    local LPos = isvector(Ent.LPos) and Ent.LPos or vector_origin
    return LocalToWorld(LPos, angle_zero, Info.Pos, Info.Ang)
end

DupeEditor.RegisterLayer("Constraints", {
    Label = "Constraints",
    Icon = "icon16/link.png",
    Default = false,
    PostDraw3D = function(View, Session)
        local Cache = View:GetLayerCache("Constraints")
        if not Cache.Points then
            local Points, Colors, Owners = {}, {}, {}
            for I, Constraint in ipairs(Session.Dupe.Constraints) do
                local Last
                for J = 1, 4 do
                    local Ent = istable(Constraint.Entity) and Constraint.Entity[J]
                    local Point = istable(Ent) and Ent.Index and ConstraintPoint(View, Ent)
                    if Point then
                        if Last then
                            Points[#Points + 1] = Last
                            Points[#Points + 1] = Point
                            Colors[#Colors + 1] = DupeEditor.ConstraintColor(Constraint.Type)
                            Owners[#Owners + 1] = I
                        end
                        Last = Point
                    end
                end
            end
            Cache.Points, Cache.Colors, Cache.Owners = Points, Colors, Owners
        end
        DupeEditor.DrawLineBatch(Cache.Points, Cache.Colors)
    end,
})

-- Always drawn for the focused constraint, even with the layer off
function DupeEditor.DrawActiveConstraint(View, Session)
    local Constraint = Session.ActiveConstraint and Session.Dupe.Constraints[Session.ActiveConstraint]
    if not Constraint or not istable(Constraint.Entity) then return end

    local Last
    local Size = math.Clamp(View.Dist * 0.01, 0.5, 20)
    for J = 1, 4 do
        local Ent = Constraint.Entity[J]
        local Point = istable(Ent) and Ent.Index and ConstraintPoint(View, Ent)
        if Point then
            render.DrawWireframeSphere(Point, Size, 8, 8, SELECT_COLOR, false)
            if Last then render.DrawLine(Last, Point, SELECT_COLOR, false) end
            Last = Point
        end
    end
end

local PARENT_COLOR = Color(120, 255, 200, 140)

DupeEditor.RegisterLayer("Parents", {
    Label = "Parenting",
    Icon = "icon16/arrow_join.png",
    Default = false,
    PostDraw3D = function(View, Session)
        local Cache = View:GetLayerCache("Parents")
        if not Cache.Points then
            local Points, Colors = {}, {}
            for Idx, Info in pairs(View.Models) do
                local Parent = View.Models[Session:GetParent(Idx) or -1]
                if Parent and Info.Center and Parent.Center then
                    Points[#Points + 1] = Info.Center
                    Points[#Points + 1] = Parent.Center
                    Colors[#Colors + 1] = PARENT_COLOR
                end
            end
            Cache.Points, Cache.Colors = Points, Colors
        end
        DupeEditor.DrawLineBatch(Cache.Points, Cache.Colors)
    end,
})

DupeEditor.RegisterLayer("Labels", {
    Label = "Labels",
    Icon = "icon16/tag_blue.png",
    Default = true,
    Draw2D = function(View, Session)
        local Count = 0
        for Idx in pairs(Session.Selected) do
            local Info = View.Models[Idx]
            if Info and Info.Center and not Session.Hidden[Idx] then
                local X, Y = View:Project(Info.Center)
                if X then
                    DrawLabel("[" .. Idx .. "] " .. tostring(Info.Class), X, Y, "DermaDefault", TEXT_COLOR, TEXT_ALIGN_CENTER)
                end
                Count = Count + 1
                if Count >= 64 then break end
            end
        end
    end,
})

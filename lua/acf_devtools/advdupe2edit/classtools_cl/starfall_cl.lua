local DupeEditor = ACF_DevTools.DupeEditor

-- Same layout as SF.CompressFiles / SF.DecompressFiles, so this works without Starfall loaded
local function ReadUInt32(Str, Pos)
    local A, B, C, D = string.byte(Str, Pos, Pos + 3)
    return D * 0x1000000 + C * 0x10000 + B * 0x100 + A, Pos + 4
end

local function WriteUInt32(X)
    return string.char(X % 0x100, bit.rshift(X, 8) % 0x100, bit.rshift(X, 16) % 0x100, bit.rshift(X, 24) % 0x100)
end

local function DecompressFiles(Data)
    Data = util.Decompress(Data)
    if not Data or #Data < 8 then return end

    local Pos = 5
    local Count
    Count, Pos = ReadUInt32(Data, Pos)
    local Headers = {}
    for I = 1, Count do
        local NameLen, Size
        NameLen, Pos = ReadUInt32(Data, Pos)
        local Name = string.sub(Data, Pos, Pos + NameLen - 1)
        Pos = Pos + NameLen
        Size, Pos = ReadUInt32(Data, Pos)
        Headers[I] = {Name, Size}
    end

    local Files = {}
    for _, Header in ipairs(Headers) do
        Files[Header[1]] = string.sub(Data, Pos, Pos + Header[2] - 1)
        Pos = Pos + Header[2]
    end
    return Files
end

local function CompressFiles(Files)
    local Header = {WriteUInt32(0), WriteUInt32(table.Count(Files))}
    local Codes = {}
    for _, Name in ipairs(DupeEditor.SortedKeys(Files)) do
        local Code = Files[Name]
        Header[#Header + 1] = WriteUInt32(#Name) .. Name .. WriteUInt32(#Code)
        Codes[#Codes + 1] = Code
    end
    return util.Compress(table.concat(Header) .. table.concat(Codes))
end

local function GetStarfall(EntData)
    local Info = istable(EntData.EntityMods) and EntData.EntityMods.SFDupeInfo
    return istable(Info) and istable(Info.starfall) and Info.starfall or nil
end

-- Returns files, legacy
local function ReadFiles(SFData)
    if isstring(SFData.files) then
        return DecompressFiles(SFData.files), false
    elseif istable(SFData.source) then
        return table.Copy(SFData.source), true
    end
end

local function WriteFiles(Session, SFData, Files, Legacy)
    if Legacy then
        Session:Set(SFData, "source", Files)
    else
        Session:Set(SFData, "files", CompressFiles(Files))
    end
end

local function OpenInSFEditor(Name, Code)
    if not (SF and SF.Editor and SF.Editor.openWithCode) then
        DupeEditor.Notify("Starfall editor not found", NOTIFY_ERROR)
        return
    end
    SF.Editor.openWithCode(Name, Code, true)
end

local function GetSFEditorCode()
    if not (SF and SF.Editor and SF.Editor.editor) then return end
    local Ok, Code = pcall(SF.Editor.getCode)
    if Ok and isstring(Code) then return SF.Editor.normalizeCode and SF.Editor.normalizeCode(Code) or Code end
end

local function OpenFilesWindow(Session, EntIdx, SFData)
    local Files, Legacy = ReadFiles(SFData)
    if not Files then
        DupeEditor.Notify("Couldn't read the chip's files", NOTIFY_ERROR)
        return
    end

    local Main = SFData.mainfile
    local Current = Main
    local Dirty = false

    local Frame, Entry = DupeEditor.OpenTextWindow("Starfall Files - [" .. EntIdx .. "]", Files[Current] or "", {
        OnApply = function(Text)
            if Current then Files[Current] = Text end
            Session:Batch("Edit Starfall files", function()
                WriteFiles(Session, SFData, Files, Legacy)
                Session:Set(SFData, "mainfile", Main)
            end)
            Session:Emit("FocusChanged")
            DupeEditor.Notify("Saved " .. table.Count(Files) .. " files into the dupe")
        end,
        Buttons = {
            {"Open in SF Editor", "icon16/script_go.png", function(Text) OpenInSFEditor(Current, Text) end},
        }
    })

    local List = Frame:Add("DListView")
    List:Dock(LEFT)
    List:DockMargin(0, 0, 4, 0)
    List:SetWide(260)
    List:SetMultiSelect(false)
    List:AddColumn("File")
    List:AddColumn("Size"):SetFixedWidth(64)

    local function Store()
        if Current and Dirty then Files[Current] = Frame.GetText() end
        Dirty = false
    end

    local function Refresh()
        List:Clear()
        for _, Name in ipairs(DupeEditor.SortedKeys(Files)) do
            local Label = Name == Main and (Name .. "  (main)") or Name
            local Line = List:AddLine(Label, string.NiceSize(#Files[Name]))
            Line.FileName = Name
            Line:SetSortValue(2, #Files[Name])
            if Name == Current then Line:SetSelected(true) end
        end
    end

    function Entry.OnChange() Dirty = true end

    function List.OnRowSelected(_, _, Line)
        Store()
        Current = Line.FileName
        Entry:SetText(Files[Current] or "")
    end

    function List.OnRowRightClick(_, _, Line)
        local Name = Line.FileName
        local Menu = DermaMenu()
        Menu:AddOption("Set as Main File", function()
            Main = Name
            Refresh()
        end):SetIcon("icon16/star.png")
        Menu:AddOption("Rename...", function()
            Derma_StringRequest("Rename File", "New name", Name, function(NewName)
                if NewName == "" or Files[NewName] then return end
                Store()
                Files[NewName], Files[Name] = Files[Name], nil
                if Main == Name then Main = NewName end
                if Current == Name then Current = NewName end
                Refresh()
            end)
        end):SetIcon("icon16/textfield_rename.png")
        Menu:AddOption("Remove", function()
            Store()
            Files[Name] = nil
            if Current == Name then
                Current = nil
                Entry:SetText("")
            end
            Refresh()
        end):SetIcon("icon16/delete.png")
        Menu:Open()
    end

    local Add = List:Add("DButton")
    Add:Dock(BOTTOM)
    Add:SetText("Add File...")
    Add:SetImage("icon16/page_add.png")
    function Add.DoClick()
        Derma_StringRequest("Add File", "File name (like libs/thing.txt)", "", function(Name)
            if Name == "" or Files[Name] then return end
            Store()
            Files[Name] = ""
            Current = Name
            Entry:SetText("")
            Refresh()
        end)
    end

    local Pull = List:Add("DButton")
    Pull:Dock(BOTTOM)
    Pull:SetText("Pull from SF Editor")
    Pull:SetImage("icon16/arrow_left.png")
    Pull:SetTooltip("Copies your current SF editor tab into this file")
    function Pull.DoClick()
        local Code = GetSFEditorCode()
        if not Code then
            DupeEditor.Notify("SF editor isn't open", NOTIFY_ERROR)
            return
        end
        Entry:SetText(Code)
        Dirty = true
    end

    Refresh()
end

DupeEditor.RegisterClassTool("starfall_processor", {
    Name = "Starfall",
    Icon = "icon16/script.png",
    ShouldShow = function(EntData) return GetStarfall(EntData) ~= nil end,
    Build = function(_, Ctx)
        local Session, EntIdx = Ctx.Session, Ctx.EntIdx
        local SFData = GetStarfall(Ctx.EntData)
        local Files, Legacy = ReadFiles(SFData)

        local Total = 0
        for _, Code in pairs(Files or {}) do Total = Total + #Code end

        Ctx.AddLine("Main file", tostring(SFData.mainfile))
        Ctx.AddLine("Files", Files and (table.Count(Files) .. " (" .. string.NiceSize(Total) .. ")") or "couldn't decode")
        Ctx.AddLine("Format", Legacy and "old (source table)" or ("v" .. tostring(SFData.ver)))
        if SFData.udata then Ctx.AddLine("User data", tostring(SFData.udata)) end

        if Files then
            local Names = DupeEditor.SortedKeys(Files)
            local Includes = {}
            for _, Name in ipairs(Names) do
                if Name ~= SFData.mainfile then Includes[#Includes + 1] = Name end
            end
            if #Includes > 0 then Ctx.AddLine("Includes", table.concat(Includes, ", ")) end
        end

        Ctx.AddButton("View/Edit Files...", "icon16/script_edit.png", function()
            OpenFilesWindow(Session, EntIdx, SFData)
        end)
        Ctx.AddButton("Open Main File in SF Editor", "icon16/script_go.png", function()
            local Current = ReadFiles(SFData)
            if Current then OpenInSFEditor(SFData.mainfile, Current[SFData.mainfile] or "") end
        end)
        Ctx.AddButton("Open All Files in SF Editor", "icon16/script_link.png", function()
            for Name, Code in SortedPairs(ReadFiles(SFData) or {}) do
                OpenInSFEditor(Name, Code)
            end
        end)
        Ctx.AddButton("Pull Main File from SF Editor", "icon16/arrow_left.png", function()
            local Code = GetSFEditorCode()
            if not Code then
                DupeEditor.Notify("SF editor isn't open", NOTIFY_ERROR)
                return
            end
            Derma_Query("Overwrite " .. tostring(SFData.mainfile) .. " with your current SF editor tab?", "Starfall", "Overwrite", function()
                local Current, IsLegacy = ReadFiles(SFData)
                if not Current then return end
                Current[SFData.mainfile] = Code
                WriteFiles(Session, SFData, Current, IsLegacy)
                Session:Emit("FocusChanged")
                DupeEditor.Notify("Done!")
            end, "Cancel")
        end)
    end,
})

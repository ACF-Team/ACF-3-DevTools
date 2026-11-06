local DupeEditor = ACF_DevTools.DupeEditor

-- E2 swaps quotes and newlines for single bytes in _original
local QUOTE_BYTE   = string.char(163)
local NEWLINE_BYTE = string.char(128)

local function DecodeCode(Str)
    return string.Replace(string.Replace(Str, QUOTE_BYTE, "\""), NEWLINE_BYTE, "\n")
end

local function EncodeCode(Str)
    return string.Replace(string.Replace(Str, "\"", QUOTE_BYTE), "\n", NEWLINE_BYTE)
end

local function GetE2Editor()
    if not wire_expression2_editor and initE2Editor then initE2Editor() end
    return wire_expression2_editor
end

local function OpenInE2Editor(Name, Code)
    local Editor = GetE2Editor()
    if not Editor then
        DupeEditor.Notify("E2 editor not found", NOTIFY_ERROR)
        return
    end
    Editor:Open(Name, Code, true)
end

local function WriteCode(Session, EntData, Code)
    Session:Batch("Edit E2 code", function()
        Session:Set(EntData, "_original", EncodeCode(Code))
        local Name = string.match(Code, "@name ([^\n]*)")
        if Name then Session:Set(EntData, "_name", string.Trim(Name)) end
    end)
    Session:Emit("FocusChanged")
end

local function PortList(Ports)
    if not istable(Ports) or not istable(Ports[1]) then return end
    local Out = {}
    for I, Name in ipairs(Ports[1]) do
        local Type = istable(Ports[2]) and Ports[2][I]
        Out[#Out + 1] = Type and (Name .. ":" .. string.lower(tostring(Type))) or tostring(Name)
    end
    return table.concat(Out, ", ")
end

DupeEditor.RegisterClassTool("gmod_wire_expression2", {
    Name = "Expression 2",
    Icon = "icon16/page_white_gear.png",
    Build = function(_, Ctx)
        local Session, EntData, EntIdx = Ctx.Session, Ctx.EntData, Ctx.EntIdx
        local Raw = EntData._original

        Ctx.AddLine("Name", tostring(EntData._name or "generic"))
        if EntData.filepath then Ctx.AddLine("File", tostring(EntData.filepath)) end
        if istable(EntData.code_author) then
            Ctx.AddLine("Author", tostring(EntData.code_author.name) .. " (" .. tostring(EntData.code_author.steamID) .. ")")
        end
        if not isstring(Raw) then
            Ctx.AddLine("Code", "none (duped with errors?)")
            return
        end

        local Code = DecodeCode(Raw)
        local _, Lines = string.gsub(Code, "\n", "")
        Ctx.AddLine("Code", string.NiceSize(#Code) .. ", " .. (Lines + 1) .. " lines")

        local Inputs, Outputs = PortList(EntData._inputs), PortList(EntData._outputs)
        if Inputs and Inputs ~= "" then Ctx.AddLine("Inputs", Inputs) end
        if Outputs and Outputs ~= "" then Ctx.AddLine("Outputs", Outputs) end
        if istable(EntData._vars) and next(EntData._vars) then
            Ctx.AddLine("Saved vars", table.Count(EntData._vars))
        end

        Ctx.AddButton("View/Edit Code...", "icon16/script_edit.png", function()
            DupeEditor.OpenTextWindow("Expression 2 - [" .. EntIdx .. "] " .. tostring(EntData._name), DecodeCode(EntData._original or ""), {
                OnApply = function(Text) WriteCode(Session, EntData, Text) end,
                Buttons = {
                    {"Open in E2 Editor", "icon16/script_go.png", function(Text) OpenInE2Editor(EntData.filepath, Text) end},
                }
            })
        end)
        Ctx.AddButton("Open in E2 Editor", "icon16/script_go.png", function()
            OpenInE2Editor(EntData.filepath, DecodeCode(EntData._original or ""))
        end)
        Ctx.AddButton("Pull Code from E2 Editor", "icon16/arrow_left.png", function()
            local Editor = wire_expression2_editor
            if not Editor then
                DupeEditor.Notify("E2 editor isn't open", NOTIFY_ERROR)
                return
            end
            Derma_Query("Overwrite this chip's code with your current E2 editor tab?", "Expression 2", "Overwrite", function()
                WriteCode(Session, EntData, string.gsub(Editor:GetCode(), "\r", ""))
                DupeEditor.Notify("Done!")
            end, "Cancel")
        end)

        local Includes = istable(EntData.inc_files) and DupeEditor.SortedKeys(EntData.inc_files) or {}
        for _, Path in ipairs(Includes) do
            Ctx.AddButton("Include: " .. tostring(Path), "icon16/page_white_text.png", function()
                local Inc = EntData.inc_files[Path]
                if not isstring(Inc) then return end
                DupeEditor.OpenTextWindow("E2 Include - " .. tostring(Path), Inc, {
                    OnApply = function(Text)
                        Session:Set(EntData.inc_files, Path, Text)
                        Session:Emit("FocusChanged")
                    end,
                    Buttons = {
                        {"Open in E2 Editor", "icon16/script_go.png", function(Text) OpenInE2Editor(Path, Text) end},
                    }
                })
            end)
        end
    end,
})

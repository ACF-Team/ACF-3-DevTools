util.AddNetworkString("ACF_Devtools_Advdupe2Download")

concommand.Add("start_advdupe2_download", function(ply)
    -- Get their clipboard, serialize, network over like a regular dupe
    if not ply.AdvDupe2 or not ply.AdvDupe2.Entities or next(ply.AdvDupe2.Entities) == nil then
        AdvDupe2.Notify(ply, "Duplicator is empty, nothing to transmit.", NOTIFY_ERROR)
        return
    end

    net.Start("AdvDupe2_SetDupeInfo")
        net.WriteString("Current Clipboard")
        net.WriteString(ply:Nick())
        net.WriteString(os.date("%d %B %Y"))
        net.WriteString(os.date("%I:%M %p"))
        net.WriteString("")
        net.WriteString("")
        net.WriteString(table.Count(ply.AdvDupe2.Entities))
        net.WriteString(#ply.AdvDupe2.Constraints)
    net.Send(ply)

    local Tab = {Entities = ply.AdvDupe2.Entities, Constraints = ply.AdvDupe2.Constraints, HeadEnt = ply.AdvDupe2.HeadEnt}

    AdvDupe2.Encode(Tab, AdvDupe2.GenerateDupeStamp(ply), function(data)
        net.Start("ACF_Devtools_Advdupe2Download")
        net.WriteBool(autosave)
        net.WriteStream(data, function()

        end)
        net.Send(ply)
    end)
end)
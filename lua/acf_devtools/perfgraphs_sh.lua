if SERVER then
    util.AddNetworkString("ACF_DevTools_NetworkServerPerf")
    timer.Create("ACF_DevTools_NetworkServerPerf", 0.1, 0, function()
        net.Start("ACF_DevTools_NetworkServerPerf")
        net.WriteFloat(FrameTime())
        net.WriteFloat(physenv.GetLastSimulationTime())
        net.WriteUInt(collectgarbage("count"), 32)
        net.Broadcast()
    end)
end

if CLIENT then
    local WatchCPU_CL, WatchGC_CL, WatchCPU_SV, WatchGC_SV, WatchPhys_CL, WatchPhys_SV
    local ServerCPU, ServerPhysTime, ServerGC = 0, 0, 0

    net.Receive("ACF_DevTools_NetworkServerPerf", function()
        ServerCPU = net.ReadFloat()
        ServerPhysTime = net.ReadFloat()
        ServerGC = net.ReadUInt(32)
    end)

    local Red    = Color(255, 70, 70)
    local Green  = Color(100, 255, 70)

    local Orange = Color(255, 181, 70)
    local Blue   = Color(70, 255, 240)

    local Purple = Color(166, 70, 255)
    local Pink   = Color(255, 70, 209)

    local function Evaluate(Value)
        WatchCPU_CL, WatchGC_CL = nil, nil
        WatchCPU_SV, WatchGC_SV = nil, nil
        WatchPhys_CL, WatchPhys_SV = nil
        if #Value <= 0 then
            hook.Remove("HUDPaint", "ACF_GCWatch")
            return
        end

        for _, Piece in ipairs(Value) do
            if Piece == "cpucl" then
                WatchCPU_CL = ACF_DevTools.PerfGraph()
                WatchCPU_CL.Divisor = 1 / 1000
            elseif Piece == "memcl" then
                WatchGC_CL  = ACF_DevTools.PerfGraph()
                WatchGC_CL.Divisor = 1024
            elseif Piece == "cpusv" then
                WatchCPU_SV = ACF_DevTools.PerfGraph()
                WatchCPU_SV.Divisor = 1 / 1000
            elseif Piece == "memsv" then
                WatchGC_SV  = ACF_DevTools.PerfGraph()
                WatchGC_SV.Divisor = 1024
            elseif Piece == "phycl" then
                WatchPhys_CL  = ACF_DevTools.PerfGraph()
                WatchPhys_CL.Divisor = 1 / 1000
            elseif Piece == "physv" then
                WatchPhys_SV  = ACF_DevTools.PerfGraph()
                WatchPhys_SV.Divisor = 1 / 1000
            end
        end

        hook.Add("HUDPaint", "ACF_GCWatch", function()
            local WidthOneGraph = ScrW() / 5
            local OneGraphPadding = 32
            -- For positioning purposes, do this first
            local CL_Graphs = 0
            local SV_Graphs = 0
            if WatchCPU_CL ~= nil then CL_Graphs = CL_Graphs + 1 end
            if WatchGC_CL ~= nil then CL_Graphs = CL_Graphs + 1 end
            if WatchCPU_SV ~= nil then SV_Graphs = SV_Graphs + 1 end
            if WatchGC_SV ~= nil then SV_Graphs = SV_Graphs + 1 end
            if WatchPhys_CL ~= nil then CL_Graphs = CL_Graphs + 1 end
            if WatchPhys_SV ~= nil then SV_Graphs = SV_Graphs + 1 end

            if WatchCPU_CL ~= nil then
                WatchCPU_CL:Add(FrameTime())
                WatchCPU_CL:Draw("CL: FrameTime() [milliseconds]", 48, ScrH() - (120 * CL_Graphs), WidthOneGraph, 96, Red)
                CL_Graphs = CL_Graphs - 1
            end

            if WatchGC_CL ~= nil then
                WatchGC_CL:Add(collectgarbage("count"))
                WatchGC_CL:Draw("CL: collectgarbage(\"count\") [MB]", 48, ScrH() - (120 * CL_Graphs), WidthOneGraph, 96, Green)
                CL_Graphs = CL_Graphs - 1
            end

            if WatchCPU_SV ~= nil then
                WatchCPU_SV:Add(ServerCPU)
                WatchCPU_SV:Draw("SV: FrameTime() [milliseconds]", 48 + WidthOneGraph + OneGraphPadding, ScrH() - (120 * SV_Graphs), WidthOneGraph, 96, Orange)
                SV_Graphs = SV_Graphs - 1
            end

            if WatchGC_SV ~= nil then
                WatchGC_SV:Add(ServerGC)
                WatchGC_SV:Draw("SV: collectgarbage(\"count\") [MB]", 48 + WidthOneGraph + OneGraphPadding, ScrH() - (120 * SV_Graphs), WidthOneGraph, 96, Blue)
                SV_Graphs = SV_Graphs - 1
            end

            if WatchPhys_CL ~= nil then
                WatchPhys_CL:Add(physenv.GetLastSimulationTime())
                WatchPhys_CL:Draw("CL: physenv.GetLastSimulationTime()", 48, ScrH() - (120 * CL_Graphs), WidthOneGraph, 96, Purple)
                CL_Graphs = CL_Graphs - 1
            end

            if WatchPhys_SV ~= nil then
                WatchPhys_SV:Add(ServerPhysTime)
                WatchPhys_SV:Draw("SV: physenv.GetLastSimulationTime()", 48 + WidthOneGraph + OneGraphPadding, ScrH() - (120 * SV_Graphs), WidthOneGraph, 96, Pink)
                SV_Graphs = SV_Graphs - 1
            end
        end)
    end

    local acf_perfgraphs = CreateClientConVar("acf_perfgraphs", "", false, false, "Shows performance graphs. The value are space-separated values.\n\nAcceptable arguments: cpucl, memcl, cpusv, memsv, phycl, physv")

    cvars.AddChangeCallback("acf_perfgraphs", function(_, _, Value)
        Evaluate(string.Explode(' ', Value))
    end)

    Evaluate(string.Explode(' ', acf_perfgraphs:GetString()))
end
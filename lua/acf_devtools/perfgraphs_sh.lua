if SERVER then
    util.Add("ACF_DevTools_NetworkServerPerf")
    timer.Create("ACF_DevTools_NetworkServerPerf", 0.1, 0, function()
        net.Start("ACF_DevTools_NetworkServerPerf")
        net.WriteFloat(FrameTime())
        net.WriteUInt(collectgarbage("count"), 32)
        net.Broadcast()
    end)
end

if CLIENT then
    local MAX_DEBUG_ITEMS = 512
    local function ConstantLengthNumericalQueue(capacity)
        local obj = {}
        obj.Divisor = 1
        local pointer = 0
        local length = 0
        local startat = 0
        local backing = {}
        for i = 1, capacity do
            backing[i - 1] = 0
        end
        function obj:Add(item)
            if length < capacity then
                length = length + 1
            else
                startat = startat + 1
                if startat >= capacity then
                    startat = 0
                end
            end

            if pointer >= capacity then pointer = pointer % capacity end
            backing[pointer] = item
            pointer = pointer + 1
        end
        function obj:Get(i)
            return backing[(i + startat) % capacity] / self.Divisor
        end

        function obj:Length() return length end


        function obj:Start() return startat end

        function obj:Min()
            local ret = math.huge
            for i = 1, length do
                ret = math.min(ret, backing[i - 1])
            end
            return ret / self.Divisor
        end

        function obj:Max()
            local ret = 0
            for i = 1, length do
                ret = math.max(ret, backing[i - 1])
            end
            return ret / self.Divisor
        end

        function obj:Average()
            local ret = 0
            for i = 1, length do
                ret = ret + backing[i - 1]
            end
            return ret / length / self.Divisor
        end

        return obj
    end

    local v1, v2 = Vector(), Vector()
    local function drawLine(startX, startY, endX, endY, thickness, color)
        if not startX then return end
        if not startY then return end
        if not endX then return end
        if not endY then return end

        thickness = thickness or 1
        color = color or color_white

        local x, y   = endX - startX, endY - startY
        local cx, cy = (startX + endX) / 2, (startY + endY) / 2
        local dist   = math.sqrt((x^2) + (y^2))

        local a      = -math.atan2(y, x)
        local s, c   = math.sin(a), math.cos(a)

        v1:SetUnpacked(cx, cy, 0)
        v2:SetUnpacked(s, c, -thickness)
        mesh.Begin(MATERIAL_QUADS, 1)
        xpcall(function()
            mesh.QuadEasy(v1, v2, dist, thickness, color)
            mesh.End()
        end, function() mesh.End() print(debug.traceback(err)) end)
    end

    local color_grey = Color(173, 173, 173)
    local formatString = "%.2f"
    local formatString2 = "avg: %.2f"

    function ACF_DevTools.PerfGraph()
        local Queue = ConstantLengthNumericalQueue(MAX_DEBUG_ITEMS)
        function Queue:Draw(label, x, y, w, h, c)
            w, h = w or 450, h or 64
            surface.SetDrawColor(20, 25, 35, 200)
            surface.DrawRect(x, y, w, h)

            local xPadding = 48

            local count, min, max, avg = self:Length(), self:Min(), self:Max(), self:Average()
            drawLine(x + xPadding, y + 4, x + xPadding, y + h - 4, 2, color_grey)
            drawLine(x + xPadding, y + h - 4, x + w - 4, y + h - 4, 2, color_grey)
            for i = 0, MAX_DEBUG_ITEMS - 1 do
                if i + 1 >= count then break end

                local finalPos = i + 1
                local x1 = x + xPadding + 4 + math.Remap(i, 0, MAX_DEBUG_ITEMS, 0, w - xPadding - 8)
                local x2 = x + xPadding + 4 + math.Remap(finalPos, 0, MAX_DEBUG_ITEMS, 0, w - xPadding - 8)
                local y1 = self:Get(i)
                local y2 = self:Get(finalPos)

                drawLine(
                    x1, y + math.Remap(y1, min, max, h - 4, 16),
                    x2, y + math.Remap(y2, min, max, h - 4, 16),
                    3, c)
            end

            draw.SimpleText(label, "DebugFixed", x + (w / 2), y, color_white, TEXT_ALIGN_CENTER)
            draw.SimpleText(formatString:format(max), "DebugFixed", x + xPadding - 4, y, color_white, TEXT_ALIGN_RIGHT)
            draw.SimpleText(formatString:format(min), "DebugFixed", x + xPadding - 4, y + h, color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
            draw.SimpleText(formatString2:format(avg), "DebugFixed", x + w - 4, y, color_white, TEXT_ALIGN_RIGHT)
        end
        return Queue
    end
end

if CLIENT then
    local WatchCPU_CL, WatchGC_CL, WatchCPU_SV, WatchGC_SV
    local ServerCPU, ServerGC = 0, 0

    net.Receive("ACF_DevTools_NetworkServerPerf", function()
        ServerCPU = net.ReadFloat()
        ServerGC = net.ReadUInt(32)
    end)

    local Red    = Color(255, 70, 70)
    local Green  = Color(100, 255, 70)

    local Orange = Color(255, 181, 70)
    local Blue   = Color(70, 255, 240)

    local function Evaluate(Value)
        WatchCPU_CL, WatchGC_CL = nil, nil
        WatchCPU_SV, WatchGC_SV = nil, nil

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
            end
        end

        hook.Add("HUDPaint", "ACF_GCWatch", function()
            local WidthOneGraph = ScrW() / 5
            -- For positioning purposes, do this first
            local Graphs = 0
            if WatchCPU_CL ~= nil then Graphs = Graphs + 1 end
            if WatchGC_CL ~= nil then Graphs = Graphs + 1 end
            if WatchCPU_SV ~= nil then Graphs = Graphs + 1 end
            if WatchGC_SV ~= nil then Graphs = Graphs + 1 end

            if WatchCPU_CL ~= nil then
                WatchCPU_CL:Add(FrameTime())
                WatchCPU_CL:Draw("CL: FrameTime() [milliseconds]", 24, ScrH() - (120 * Graphs), WidthOneGraph, 96, Red)
                Graphs = Graphs - 1
            end

            if WatchGC_CL ~= nil then
                WatchGC_CL:Add(collectgarbage("count"))
                WatchGC_CL:Draw("CL: collectgarbage(\"count\") [MB]", 48 + WidthOneGraph, ScrH() - (120 * Graphs), WidthOneGraph, 96, Green)
                Graphs = Graphs - 1
            end

            if WatchCPU_CL ~= nil then
                WatchCPU_SV:Add(ServerCPU)
                WatchCPU_SV:Draw("SV: FrameTime() [milliseconds]", 24, ScrH() - (120 * Graphs), WidthOneGraph, 96, Orange)
                Graphs = Graphs - 1
            end

            if WatchGC_CL ~= nil then
                WatchGC_SV:Add(ServerGC)
                WatchGC_SV:Draw("SV: collectgarbage(\"count\") [MB]", 48 + WidthOneGraph, ScrH() - (120 * Graphs), WidthOneGraph, 96, Blue)
                Graphs = Graphs - 1
            end
        end)
    end

    local acf_perfgraphs = CreateClientConVar("acf_perfgraphs", "", false, false, "Shows performance graphs. The value are space-separated values.\n\nAcceptable arguments: cpucl, memcl, cpusv, memsv")

    cvars.AddChangeCallback("acf_perfgraphs", function(_, _, Value)
        Evaluate(string.Explode(' ', Value))
    end)

    Evaluate(acf_perfgraphs:GetInt())
end
local MAX_DEBUG_ITEMS = 512
if CLIENT then
    local v1, v2 = Vector(), Vector()

    local color_grey = Color(173, 173, 173)
    local formatString  = "%.2f"
    local formatString2 = "avg: %.2f"

    -- Scratch arrays reused every Draw call (no GC pressure)
    local _x1 = {}
    local _y1 = {}
    local _x2 = {}
    local _y2 = {}
    local _sx = {}
    local _sy = {}
    local _c  = {}
    local _thickness = {}
    local _pendingLines = 0

    local function flushLines()
        if _pendingLines == 0 then return end
        mesh.Begin(MATERIAL_QUADS, _pendingLines)
        xpcall(function()
            for i = 1, _pendingLines do
                if _x1[i] then
                    local x   = _x2[i] - _x1[i]
                    local y   = _y2[i] - _y1[i]
                    local cx  = (_x1[i] + _x2[i]) * 0.5
                    local cy  = (_y1[i] + _y2[i]) * 0.5
                    local dist = math.sqrt(x * x + y * y)
                    local a    = -math.atan2(y, x)
                    v1:SetUnpacked(cx, cy, 0)
                    v2:SetUnpacked(math.sin(a), math.cos(a), -_thickness[i])
                    mesh.QuadEasy(v1, v2, dist, _thickness[i], _c[i])
                end
            end
            mesh.End()
        end, function(err)
            mesh.End()
            print(debug.traceback(err))
        end)
        _pendingLines = 0
    end

    local function queueLine(startX, startY, endX, endY, thickness, color)
        if not startX or not startY or not endX or not endY then return end
        _pendingLines = _pendingLines + 1
        _x1[_pendingLines] = startX
        _y1[_pendingLines] = startY
        _x2[_pendingLines] = endX
        _y2[_pendingLines] = endY
        _thickness[_pendingLines] = thickness or 1
        _c[_pendingLines]  = color or color_white
    end

    function ACF_DevTools.PerfGraph()
        local Queue = ACF_DevTools.ConstantLengthNumericalQueue(MAX_DEBUG_ITEMS)

        function Queue:Draw(label, x, y, w, h, c)
            w, h = w or 450, h or 64

            surface.SetDrawColor(20, 25, 35, 200)
            surface.DrawRect(x, y, w, h)

            local xPadding = 48
            local count, min, max, avg = self:Length(), self:Min(), self:Max(), self:Average()

            if math.abs(min - max) < 0.001 then
                min = min - 0.01
            end

            -- Queue axis lines
            queueLine(x + xPadding,     y + 4,       x + xPadding,     y + h - 4, 2, color_grey)
            queueLine(x + xPadding,     y + h - 4,   x + w - 4,        y + h - 4, 2, color_grey)

            -- Pre-compute shared constants outside the loop
            local xInner = x + xPadding + 4
            local xRange = w - xPadding - 8
            local yTop   = 16
            local yBot   = h - 4

            for i = 0, MAX_DEBUG_ITEMS - 1 do
                if i + 1 >= count then break end
                local finalPos = i + 1
                local x1 = xInner + math.Remap(i,        0, MAX_DEBUG_ITEMS, 0, xRange)
                local x2 = xInner + math.Remap(finalPos, 0, MAX_DEBUG_ITEMS, 0, xRange)
                local y1 = y + math.Remap(self:Get(i),        min, max, yBot, yTop)
                local y2 = y + math.Remap(self:Get(finalPos), min, max, yBot, yTop)
                queueLine(x1, y1, x2, y2, 3, c)
            end

            -- Emit all queued lines as one mesh call
            flushLines()

            draw.SimpleText(label,                       "DebugFixed", x + (w / 2),       y,     color_white, TEXT_ALIGN_CENTER)
            draw.SimpleText(formatString:format(max),    "DebugFixed", x + xPadding - 4,  y,     color_white, TEXT_ALIGN_RIGHT)
            draw.SimpleText(formatString:format(min),    "DebugFixed", x + xPadding - 4,  y + h, color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
            draw.SimpleText(formatString2:format(avg),   "DebugFixed", x + w - 4,         y,     color_white, TEXT_ALIGN_RIGHT)
        end

        return Queue
    end
end
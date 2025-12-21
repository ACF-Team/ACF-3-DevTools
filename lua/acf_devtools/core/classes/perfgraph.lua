local MAX_DEBUG_ITEMS = 512

if CLIENT then
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
        local Queue = ACF_DevTools.ConstantLengthNumericalQueue(MAX_DEBUG_ITEMS)
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

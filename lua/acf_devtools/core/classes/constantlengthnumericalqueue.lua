function ACF_DevTools.ConstantLengthNumericalQueue(capacity)
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
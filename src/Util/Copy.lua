local function copy(tbl, cache)
	if not cache then
		cache = { tbl = true }
	end

	local newTable = {}
	local mt = getmetatable(tbl)
	for i, v in pairs(tbl) do
		if typeof(v) == "table" then
			if cache[v] then
				newTable[i] = v
			else
				cache[v] = true
				newTable[i] = copy(v, cache)
			end
		else
			newTable[i] = v
		end
	end
	setmetatable(newTable, mt)
	return newTable
end

return copy

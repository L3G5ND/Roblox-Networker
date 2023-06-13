local Util = script.Parent
local Assert = require(Util.Assert)

local function equal(v1, v2)
	if v1 == v2 then
		return true
	end
	if typeof(v1) == "function" or typeof(v2) == "function" then
		return false
	end
	if typeof(v1) == "table" and typeof(v2) == "table" then
		if #v1 ~= #v2 then
			return false
		end
		return true, true
	end
	return false
end

local function deepEqual(v1, v2, howDeep)
	Assert(howDeep == nil or typeof(howDeep) == "number", "Invalid argument #1 (Must be of type 'number')")
	local equal, table = equal(v1, v2)
	if not equal then
		return false
	else
		if not table then
			return true
		else
			for i, v in pairs(v1) do
				if not howDeep or howDeep > 0 then
					if not deepEqual(v, v2[i], (howDeep and howDeep - 1)) then
						return false
					end
				else
					local equal = equal(v1, v2)
					if not equal then
						return false
					end
				end
			end
			for i, v in pairs(v2) do
				if not howDeep or howDeep > 0 then
					if not deepEqual(v, v1[i], (howDeep and howDeep - 1)) then
						return false
					end
				else
					local equal = equal(v1, v2)
					if not equal then
						return false
					end
				end
			end
			return true
		end
	end
end

return deepEqual

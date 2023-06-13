local TypeMarker = {}
local Internal = {}

TypeMarker.Mark = function(typeMarker)
	assert(typeof(typeMarker) == "string", string.format("typeMarker must be a string, got %s", typeof(typeMarker)))

	local marker = newproxy(true)

	getmetatable(marker).__tostring = function()
		return ("TypeMarker(%s)"):format(typeMarker)
	end

	Internal[marker] = marker
	return marker
end

TypeMarker.Is = function(typeMarker)
	return Internal[typeMarker]
end

return setmetatable(TypeMarker, { Internal })

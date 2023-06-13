return function(condition, message, level)
	if not condition then
		error("[Networker] - " .. message, level or 3)
	end
end

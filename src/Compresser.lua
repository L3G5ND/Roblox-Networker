local HttpService = game:GetService("HttpService")

local Util = script.Parent.Util
local Assert = require(Util.Assert)
local Copy = require(Util.Copy)
local DeepEqual = require(Util.DeepEqual)

local Symbol = require(script.Parent.Symbol)

local dupeRequestymbol = Symbol.create("DupeRequest")

local function fromHex(input)
	return string.gsub(input, "..", function(hex)
		return string.char(tonumber(hex, 16))
	end)
end

local function toHex(input)
	return string.gsub(input, ".", function(char)
		return string.format("%02X", string.byte(char))
	end)
end

local Compresser = {}

function Compresser.compress(payload)
	Assert(typeof(payload) == "table", "Invalid argument #1 (must be a 'table')")
	local compressedPayload = Copy(payload)
	local searchedIndexes = {}
	for index, request in compressedPayload do
		local compresserIndex = #request + 1
		local compressedLength = 1
		if typeof(request) == "table" then
			local requestCopy = Copy(request)
			for otherIndex, otherRequest in compressedPayload do
				if
					table.find(searchedIndexes, otherIndex)
					or otherIndex == index
					or typeof(otherRequest) ~= "table"
				then
					continue
				end
				if DeepEqual(requestCopy, otherRequest) then
					table.remove(compressedPayload, otherIndex)
					compressedLength = math.min(compressedLength + 1, 65535)
				end
			end
		end
		if compressedLength > 1 then
			request[compresserIndex] = dupeRequestymbol .. string.pack("H", compressedLength)
		end
		table.insert(searchedIndexes, index)
	end
	return compressedPayload
end

function Compresser.decompress(compressedPayload)
	local decompressedPayload = {}
	for index, request in compressedPayload do
		local num = 1
		for argIndex, arg in request do
			if typeof(arg) == "string" then
				local s, e = string.find(arg, dupeRequestymbol)
				if s and s == 1 then
					num = string.unpack("H", string.sub(arg, e + 1))
					request[argIndex] = nil
				end
			end
			for i = 0, num - 1 do
				decompressedPayload[index + i] = request
			end
		end
	end
	return decompressedPayload
end

function Compresser.createUUID()
	return string.gsub(string.upper(HttpService:GenerateGUID(false)), "-", "")
end

function Compresser.compressUUID(id)
	return fromHex(id)
end

function Compresser.decompressUUID(input)
	return toHex(input)
end

return Compresser

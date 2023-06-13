local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Util = script.Parent.Util
local Assert = require(Util.Assert)
local Copy = require(Util.Copy)
local DeepEqual = require(Util.DeepEqual)

local CrossSymbol = require(script.Parent.CrossSymbol)

local isServer = RunService:IsServer()

local compresserId
if isServer then
	compresserId = CrossSymbol.create("Compresser")
else
	compresserId = CrossSymbol.get("Compresser")
end

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

function Compresser.compress(input)
	Assert(typeof(input) == "table", "Invalid argument #1 (must be a 'table')")
	input = Copy(input)
	local searchedKeys = {}
	for key, request in input do
		local compresserIndex
		local compressedLength = 1
		if typeof(request) == "table" then
			local requestCopy = Copy(request)
			for otherKey, otherRequest in input do
				if table.find(searchedKeys, otherKey) or otherKey == key or typeof(otherRequest) ~= "table" then
					continue
				end
				if DeepEqual(requestCopy, otherRequest) then
					compressedLength += 1
					input[otherKey] = nil
					if not compresserIndex then
						compresserIndex = #request + 1
						request[compresserIndex] = compresserId
					end
					request[compresserIndex] = compresserId .. string.pack("H", compressedLength)
				end
			end
		end
		table.insert(searchedKeys, key)
	end
	return input
end

function Compresser.decompress(input)
	local output = {}
	for key, request in input do
		local num = 1
		for argIndex, arg in request do
			if typeof(arg) == "string" then
				local s, e = string.find(arg, compresserId)
				if s and s == 1 then
					num = string.unpack("H", string.sub(arg, e + 1))
					request[argIndex] = nil
				end
			end
			for i = 0, num - 1 do
				output[key + i] = request
			end
		end
	end
	return output
end

function Compresser.createUUID()
	return string.gsub(HttpService:GenerateGUID(false), "-", "")
end

function Compresser.compressUUID(id)
	return fromHex(id or Compresser.createId())
end

function Compresser.decompressUUID(input)
	return toHex(input)
end

return Compresser

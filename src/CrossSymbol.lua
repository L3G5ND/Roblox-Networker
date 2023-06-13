local RunService = game:GetService("RunService")

local Util = script.Parent.Util
local Assert = require(Util.Assert)

local isServer = RunService:IsServer()

local function getRemote()
	if isServer then
		local remote = Instance.new("RemoteEvent", script.Parent)
		remote.Name = "SymbolRemote"
		return remote
	else
		return script.Parent:WaitForChild("SymbolRemote")
	end
end

local symbolRemote = getRemote()

local function packNumber(num)
	return string.pack("H", num):gsub("[\00]+$", "")
end

local idToSymbols = {}
local symbolToId = {}
local symbolsNum = 0

local CrossSymbol = {}

function CrossSymbol.create(id)
	Assert(isServer, "You can only create symbols on the client")
	Assert(idToSymbols[id] == nil, "Invalid argument #1 (Symbol already exists)")
	Assert(symbolsNum <= 65535, "Maximum symbols created")

	symbolsNum += 1

	local symbol = packNumber(symbolsNum)

	idToSymbols[id] = symbol
	symbolToId[symbol] = id

	symbolRemote:FireAllClients(id, symbol)

	return symbol
end

function CrossSymbol.waitForSymbol(id)
	while not idToSymbols[id] do
		task.wait()
	end
	return idToSymbols[id]
end
CrossSymbol.waitFor = CrossSymbol.waitForSymbol

function CrossSymbol.waitForId(symbol)
	while not symbolToId[symbol] do
		task.wait()
	end
	return symbolToId[symbol]
end

function CrossSymbol.getSymbol(id)
	return idToSymbols[id]
end
CrossSymbol.get = CrossSymbol.getSymbol

function CrossSymbol.getId(symbol)
	return symbolToId[symbol]
end

if not isServer then
	local thread = coroutine.running()
	symbolRemote.OnClientEvent:Connect(function(arg1, arg2)
		if typeof(arg1) == "table" then
			idToSymbols = arg1
			for id, symbol in idToSymbols do
				symbolToId[symbol] = id
			end
		end
		idToSymbols[arg1] = arg2
		task.spawn(thread)
	end)
	symbolRemote:FireServer()
	coroutine.yield()
else
	symbolRemote.OnServerEvent:Connect(function(plr)
		symbolRemote:FireClient(plr, idToSymbols)
	end)
end

return CrossSymbol
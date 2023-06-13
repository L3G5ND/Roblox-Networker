local RunService = game:GetService("RunService")

local Util = script.Parent.Util
local Assert = require(Util.Assert)

local Compresser = require(script.Parent.Compresser)
local CrossSymbol = require(script.Parent.CrossSymbol)

local InvokeSymbol = CrossSymbol.waitFor("Invoke")
local InvokeResponseSymbol = CrossSymbol.waitFor("InvokeResponse")

local remote = script.Parent:WaitForChild("NetworkerRemote")

local ClientNetworker = {}
ClientNetworker._networkers = {}
ClientNetworker._sendQueue = {}

function ClientNetworker.new(name, context)
	Assert(type(name) == "string", "Invalid argument #1 (must be a 'string')")
	Assert(context == nil or typeof(context) == "table", "Invalid argument #2 (must be a 'table' or 'nil')")

	if ClientNetworker._networkers[name] ~= nil then
		if ClientNetworker._networkers[name] == false then
			while not ClientNetworker._networkers[name] do
				task.wait()
			end
		end
		return ClientNetworker._networkers[name]
	end
	ClientNetworker._networkers[name] = false

	local self = setmetatable({}, { __index = ClientNetworker })
	self._name = name
	self._symbol = CrossSymbol.waitFor(name)
	self._isAlive = true
	self._connections = {}
	self._invokeThreads = {}
	self._onInvoke = nil
	self._rate = context and context.rate or nil
	self._inboundMiddleware = context and context.inboundMiddleware or {}
	self._outboundMiddleware = context and context.outboundMiddleware or {}

	ClientNetworker._networkers[self._name] = self

	return self
end

function ClientNetworker.getNetworker(name)
	return ClientNetworker._networkers[name]
end

function ClientNetworker:Fire(...)
	table.insert(ClientNetworker._sendQueue, {
		networker = self,
		args = { ... },
	})
end

function ClientNetworker:Invoke(...)
	local thread = coroutine.running()
	table.insert(ClientNetworker._sendQueue, {
		invoke = true,
		thread = thread,
		networker = self,
		args = { ... },
	})
	return coroutine.yield()
end

function ClientNetworker:OnInvoke(callback)
	Assert(typeof(callback) == "function", "Invalid argument #1 (must be a 'function')")
	self._onInvoke = callback
end

function ClientNetworker:Once(callback)
	Assert(typeof(callback) == "function", "Invalid argument #1 (must be a 'function')")
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function ClientNetworker:Connect(callback)
	Assert(typeof(callback) == "function", "Invalid argument #1 (must be a 'function')")
	return self:_connect(callback)
end

function ClientNetworker:DisconnectAll()
	for _, connection in self._connections do
		if connection._metadata.isImportant then
			continue
		end
		connection:Disconnect()
	end
end

function ClientNetworker:getName()
	return self._name
end

function ClientNetworker:getRate()
	return self._rate
end

function ClientNetworker:setRate(rate)
	Assert(typeof(rate) == "number", "Invalid argument #1 (must be a 'number')")
	self._rate = rate
end

function ClientNetworker:Destroy()
	ClientNetworker._networkers[self._name] = nil
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._isAlive = false
end

function ClientNetworker:_connect(callback, isImportant)
	local connections = self._connections

	local connection = {
		_metadata = {
			callback = callback,
			isImportant = isImportant,
		},
		_id = Compresser.createUUID(),
		_isAlive = true,
	}
	setmetatable(connection, { __index = connection })

	function connection:Disconnect()
		self._isAlive = false
		connections[self._id] = nil
	end

	connections[connection._id] = connection
	return connection
end

function ClientNetworker:_handleOutboundRequest(request)
	if not self._isAlive then
		return
	end

	local data = { self._symbol }
	if request.invoke then
		local id = Compresser.createUUID()
		self._invokeThreads[id] = request.thread
		table.insert(data, InvokeSymbol .. Compresser.compressUUID(id))
	elseif request.invokeResponse then
		table.insert(data, InvokeResponseSymbol .. request.id)
	end
	for _, arg in request.args do
		table.insert(data, arg)
	end

	return data
end

function ClientNetworker:_handleInboundRequest(request)
	if not self._isAlive then
		return
	end

	if typeof(request[2]) == "string" then
		if string.find(request[2], "^" .. InvokeSymbol) then
			local _, e = string.find(request[2], "^" .. InvokeSymbol)
			local id = string.sub(request[2], e + 1, request[2]:len())
			local args = self._onInvoke and table.pack(self._onInvoke(table.unpack(request, 3))) or {}
			table.insert(ClientNetworker._sendQueue, {
				invokeResponse = true,
				id = id,
				networker = self,
				args = { table.unpack(args) },
			})
			return
		end
		if string.find(request[2], "^" .. InvokeResponseSymbol) then
			local _, e = string.find(request[2], "^" .. InvokeResponseSymbol)
			local id = Compresser.decompressUUID(string.sub(request[2], e + 1, request[2]:len()))
			task.spawn(self._invokeThreads[id], table.unpack(request, 3))
			self._invokeThreads[id] = nil
			return
		end
	end

	for _, connection in self._connections do
		connection._metadata.callback(table.unpack(request, 2))
	end
end

RunService.Heartbeat:Connect(function()
	local payload = {}

	for _, request in ClientNetworker._sendQueue do
		task.spawn(function()
			table.insert(payload, request.networker:_handleOutboundRequest(request))
		end)
	end
	table.clear(ClientNetworker._sendQueue)

	remote:FireServer(Compresser.compress(payload))
end)

remote.OnClientEvent:Connect(function(payload)
	payload = Compresser.decompress(payload)
	for _, request in payload do
		task.spawn(function()
			local networker = ClientNetworker.getNetworker(CrossSymbol.getId(request[1]))
			if networker then
				networker:_handleInboundRequest(request)
			end
		end)
	end
end)

return ClientNetworker

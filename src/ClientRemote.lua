local RunService = game:GetService("RunService")

local Util = script.Parent.Util
local Assert = require(Util.Assert)
local TypeMarker = require(Util.TypeMarker)

local Compresser = require(script.Parent.Compresser)
local Symbol = require(script.Parent.Symbol)

local DropMiddlewareMarker = TypeMarker.Mark("DropMiddleware")

local InvokeSymbol = Symbol.waitFor("Invoke")
local InvokeResponseSymbol = Symbol.waitFor("InvokeResponse")

local networkerRemote = script.Parent:WaitForChild("NetworkerRemote")

local ClientRemote = {}
ClientRemote._remotes = {}
ClientRemote._sendQueue = {}

function ClientRemote.new(name, context)
	Assert(type(name) == "string", "Invalid argument #1 (must be a 'string')")
	Assert(context == nil or typeof(context) == "table", "Invalid argument #2 (must be a 'table' or 'nil')")

	if ClientRemote._remotes[name] ~= nil then
		if ClientRemote._remotes[name] == false then
			while not ClientRemote._remotes[name] do
				task.wait()
			end
		end
		return ClientRemote._remotes[name]
	end
	ClientRemote._remotes[name] = false

	local self = setmetatable({}, {
		__index = ClientRemote,
		__tostring = function()
			return "[Networker]"
		end,
	})

	self._name = name
	self._symbol = Symbol.waitFor(name)
	self._isAlive = true
	self._connections = {}
	self._invokeThreads = {}
	self._onInvoke = nil
	self._lastSendTime = nil
	self._rate = context and context.rate or nil
	self._inboundMiddleware = context and context.inboundMiddleware or {}
	self._outboundMiddleware = context and context.outboundMiddleware or {}

	ClientRemote._remotes[self._name] = self

	return self
end

function ClientRemote.getRemote(name)
	return ClientRemote._remotes[name]
end

function ClientRemote.DropMiddleware()
	return DropMiddlewareMarker
end

function ClientRemote:Fire(...)
	table.insert(ClientRemote._sendQueue, {
		remote = self,
		args = { ... },
	})
end

function ClientRemote:Invoke(...)
	local thread = coroutine.running()
	table.insert(ClientRemote._sendQueue, {
		invoke = true,
		thread = thread,
		remote = self,
		args = { ... },
	})
	return coroutine.yield()
end

function ClientRemote:OnInvoke(callback)
	Assert(typeof(callback) == "function", "Invalid argument #1 (must be a 'function')")
	self._onInvoke = callback
end

function ClientRemote:Once(callback)
	Assert(typeof(callback) == "function", "Invalid argument #1 (must be a 'function')")
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function ClientRemote:Connect(callback)
	Assert(typeof(callback) == "function", "Invalid argument #1 (must be a 'function')")
	return self:_connect(callback)
end

function ClientRemote:DisconnectAll()
	for _, connection in self._connections do
		if connection._metadata.isImportant then
			continue
		end
		connection:Disconnect()
	end
end

function ClientRemote:getName()
	return self._name
end

function ClientRemote:getRate()
	return self._rate
end

function ClientRemote:setRate(rate)
	Assert(typeof(rate) == "number", "Invalid argument #1 (must be a 'number')")
	self._rate = rate
end

function ClientRemote:setInboundMiddleware(table)
	Assert(typeof(table) == "table", "Invalid argument #1 (must be a 'table')")
	self._inboundMiddleware = table
end

function ClientRemote:setOutboundMiddleware(table)
	Assert(typeof(table) == "table", "Invalid argument #1 (must be a 'table')")
	self._outboundMiddleware = table
end

function ClientRemote:getSelf()
	local tbl = {}
	for key, value in self do
		tbl[key] = value
	end
	return tbl
end

function ClientRemote:Destroy()
	ClientRemote._remotes[self._name] = nil
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._isAlive = false
end

function ClientRemote:_connect(callback, isImportant)
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

function ClientRemote:_handleOutboundRequest(request)
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

	local args = request.args
	if self._outboundMiddleware and #self._outboundMiddleware > 0 then
		for _, callback in self._outboundMiddleware do
			local result = { callback(table.unpack(args)) }
			if result[1] == DropMiddlewareMarker then
				return
			end
			args = result
		end
	end
	for _, arg in args do
		table.insert(data, arg)
	end

	request.didSend = true

	return data
end

function ClientRemote:_handleInboundRequest(request)
	if not self._isAlive then
		return
	end

	local eventType = 1
	if typeof(request[2]) == "string" then
		if string.find(request[2], "^" .. InvokeSymbol) then
			eventType = 2
		end
		if string.find(request[2], "^" .. InvokeResponseSymbol) then
			eventType = 3
		end
	end

	local argPos = eventType == 1 and 2 or 3
	local args = table.move(request, argPos, #request, 1, {})
	if self._inboundMiddleware and #self._inboundMiddleware > 0 then
		for _, callback in self._inboundMiddleware do
			local result = { callback(table.unpack(args)) }
			if result[1] == DropMiddlewareMarker then
				return
			end
			args = result
		end
	end

	if eventType == 1 then
		for _, connection in self._connections do
			connection._metadata.callback(table.unpack(args))
		end
	elseif eventType == 2 then
		local _, e = string.find(request[2], "^" .. InvokeSymbol)
		local id = string.sub(request[2], e + 1, request[2]:len())
		local args = self._onInvoke and { self._onInvoke(table.unpack(args)) } or {}
		table.insert(ClientRemote._sendQueue, {
			isImportant = true,
			invokeResponse = true,
			id = id,
			remote = self,
			args = { table.unpack(args) },
		})
	elseif eventType == 3 then
		local _, e = string.find(request[2], "^" .. InvokeResponseSymbol)
		local id = Compresser.decompressUUID(string.sub(request[2], e + 1, request[2]:len()))
		task.spawn(self._invokeThreads[id], table.unpack(args))
		self._invokeThreads[id] = nil
	end
end

RunService.Heartbeat:Connect(function()
	local pendingQueue = {}
	local payload = {}

	for _, request in ClientRemote._sendQueue do
		local remote = request.remote
		if not request.isImportant then
			if remote._rate and remote._rate ~= 0 and remote._lastSendTime then
				if os.clock() - remote._lastSendTime < remote._rate then
					table.insert(pendingQueue, request)
					continue
				end
			end
		end

		local data
		local success = pcall(function()
			data = request.remote:_handleOutboundRequest(request)
		end)

		if success then
			table.insert(payload, data)
		end
	end

	for _, request in ClientRemote._sendQueue do
		if request.didSend and not request.invoke and not request.invokeResponse then
			request.remote._lastSendTime = os.clock()
		end
	end

	table.clear(ClientRemote._sendQueue)
	for i, request in pendingQueue do
		ClientRemote._sendQueue[i] = request
	end

	if #payload > 0 then
		networkerRemote:FireServer(Compresser.compress(payload))
	end
end)

networkerRemote.OnClientEvent:Connect(function(payload)
	payload = Compresser.decompress(payload)
	for _, request in payload do
		task.spawn(function()
			local remote = ClientRemote.getRemote(Symbol.getId(request[1]))
			if remote then
				remote:_handleInboundRequest(request)
			end
		end)
	end
end)

return ClientRemote

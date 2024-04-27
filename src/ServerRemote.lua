local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Util = script.Parent.Util
local Assert = require(Util.Assert)
local TypeMarker = require(Util.TypeMarker)

local Compresser = require(script.Parent.Compresser)
local Symbol = require(script.Parent.Symbol)

local DropMiddlewareMarker = TypeMarker.Mark("DropMiddleware")

local NilSymbol = Symbol.create("nil")
local InvokeSymbol = Symbol.create("Invoke")
local InvokeResponseSymbol = Symbol.create("InvokeResponse")

local networkerRemote = Instance.new("RemoteEvent", script.Parent)
networkerRemote.Name = "NetworkerRemote"

local ServerRemote = {}
ServerRemote._remotes = {}
ServerRemote._sendQueue = {}

function ServerRemote.new(name, context)
	Assert(type(name) == "string", "Invalid argument #1 (must be a 'string')")
	Assert(context == nil or typeof(context) == "table", "Invalid argument #2 (must be a 'table' or 'nil')")

	if ServerRemote._remotes[name] ~= nil then
		if ServerRemote._remotes[name] == false then
			while not ServerRemote._remotes[name] do
				task.wait()
			end
		end
		return ServerRemote._remotes[name]
	end
	ServerRemote._remotes[name] = false

	local self = setmetatable({}, {
		__index = ServerRemote,
		__tostring = function()
			return "[Networker]"
		end,
	})

	self._name = name
	self._symbol = Symbol.create(name)
	self._isAlive = true
	self._connections = {}
	self._invokeThreads = {}
	self._onInvoke = nil
	self._lastSendTime = nil
	self._rate = context and context.rate
	self._inboundMiddleware = context and context.inboundMiddleware
	self._outboundMiddleware = context and context.outboundMiddleware

	ServerRemote._remotes[self._name] = self

	return self
end

function ServerRemote.getRemote(name)
	return ServerRemote._remotes[name]
end

function ServerRemote.DropMiddleware()
	return DropMiddlewareMarker
end

function ServerRemote:Fire(clients, ...)
	Assert(
		typeof(clients) == "Instance" and clients.ClassName == "Player" or typeof(clients) == "table",
		"Invalid argument #1 (must be a table or player instance)"
	)

	table.insert(ServerRemote._sendQueue, {
		remote = self,
		clients = clients,
		args = { ... },
	})
end

function ServerRemote:FireAll(...)
	table.insert(ServerRemote._sendQueue, {
		remote = self,
		clients = "all",
		args = { ... },
	})
end

function ServerRemote:FireAllExcept(blacklisted, ...)
	if typeof(blacklisted) == "Instance" and blacklisted.ClassName == "Player" then
		blacklisted = { blacklisted }
	end
	Assert(typeof(blacklisted) == "table", "Invalid argument #1 (must be a table or player instance)")

	local clients = {}

	for _, plr in Players:GetPlayers() do
		if table.find(blacklisted, plr) then
			continue
		end
		table.insert(clients, plr)
	end

	table.insert(ServerRemote._sendQueue, {
		remote = self,
		clients = clients,
		args = { ... },
	})
end

function ServerRemote:Invoke(plr, ...)
	Assert(
		typeof(plr) == "Instance" and plr.ClassName == "Player",
		"Invalid argument #1 (must be a table or player instance)"
	)
	local thread = coroutine.running()
	table.insert(ServerRemote._sendQueue, {
		invoke = true,
		thread = thread,
		remote = self,
		clients = plr,
		args = { ... },
	})
	return coroutine.yield()
end

function ServerRemote:OnInvoke(callback)
	Assert(typeof(callback) == "function", "Invalid argument #1 (must be a 'function')")
	self._onInvoke = callback
end

function ServerRemote:Once(callback)
	Assert(typeof(callback) == "function", "Invalid argument #1 (must be a 'function')")
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function ServerRemote:Connect(callback)
	Assert(typeof(callback) == "function", "Invalid argument #1 (must be a 'function')")
	return self:_connect(callback)
end

function ServerRemote:DisconnectAll()
	for _, connection in self._connections do
		if connection._metadata.isImportant then
			continue
		end
		connection:Disconnect()
	end
end

function ServerRemote:getName()
	return self._name
end

function ServerRemote:getRate()
	return self._rate
end

function ServerRemote:setRate(rate)
	Assert(typeof(rate) == "number", "Invalid argument #1 (must be a 'number')")
	self._rate = rate
end

function ServerRemote:setInboundMiddleware(table)
	Assert(typeof(table) == "table", "Invalid argument #1 (must be a 'table')")
	self._inboundMiddleware = table
end

function ServerRemote:setOutboundMiddleware(table)
	Assert(typeof(table) == "table", "Invalid argument #1 (must be a 'table')")
	self._outboundMiddleware = table
end

function ServerRemote:getSelf()
	local tbl = {}
	for key, value in self do
		tbl[key] = value
	end
	return tbl
end

function ServerRemote:Destroy()
	ServerRemote._remotes[self._name] = nil
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._isAlive = false
end

function ServerRemote:_connect(callback, isImportant)
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

function ServerRemote:_handleOutboundRequest(request)
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

	local clients = {}
	if request.clients == "all" then
		for _, client in Players:GetPlayers() do
			table.insert(clients, client)
		end
	elseif typeof(request.clients) == "table" then
		for _, client in clients do
			table.insert(clients, client)
		end
	elseif typeof(request.clients) == "Instance" and request.clients.ClassName == "Player" then
		table.insert(clients, request.clients)
	end

	local args = request.args
	if self._outboundMiddleware and #self._outboundMiddleware > 0 then
		for _, callback in self._outboundMiddleware do
			local result = { callback(clients, table.unpack(args)) }
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

	return clients, data
end

function ServerRemote:_handleInboundRequest(plr, request)
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
			local result = { callback(plr, table.unpack(args)) }
			if result[1] == DropMiddlewareMarker then
				return
			end
			args = result
		end
	end

	if eventType == 1 then
		for _, connection in self._connections do
			connection._metadata.callback(plr, table.unpack(args))
		end
	elseif eventType == 2 then
		local _, e = string.find(request[2], "^" .. InvokeSymbol)
		local id = string.sub(request[2], e + 1, request[2]:len())
		local args = self._onInvoke and { self._onInvoke(plr, table.unpack(args)) } or {}
		table.insert(ServerRemote._sendQueue, {
			isImportant = true,
			invokeResponse = true,
			id = id,
			remote = self,
			clients = plr,
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
	local payloads = {}

	for _, request in ServerRemote._sendQueue do
		local remote = request.remote
		if not request.isImportant then
			if remote._rate and remote._rate ~= 0 and remote._lastSendTime then
				if os.clock() - remote._lastSendTime < remote._rate then
					table.insert(pendingQueue, request)
					continue
				end
			end
		end

		local clients, data
		local success = pcall(function()
			clients, data = remote:_handleOutboundRequest(request)
		end, function() end)

		if success then
			for _, client in clients do
				if not payloads[client] then
					payloads[client] = {}
				end
				table.insert(payloads[client], data)
			end
		end
	end

	for _, request in ServerRemote._sendQueue do
		if request.didSend and not request.invoke and not request.invokeResponse then
			request.remote._lastSendTime = os.clock()
		end
	end

	table.clear(ServerRemote._sendQueue)
	for i, request in pendingQueue do
		ServerRemote._sendQueue[i] = request
	end

	for client, payload in payloads do
		networkerRemote:FireClient(client, Compresser.compress(payload))
	end
end)

networkerRemote.OnServerEvent:Connect(function(plr, payload)
	payload = Compresser.decompress(payload)
	for _, request in payload do
		task.spawn(function()
			local remote = ServerRemote.getRemote(Symbol.getId(request[1]))
			if remote then
				remote:_handleInboundRequest(plr, request)
			end
		end)
	end
end)

return ServerRemote

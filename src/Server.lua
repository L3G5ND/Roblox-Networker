local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Util = script.Parent.Util
local Assert = require(Util.Assert)
local Error = require(Util.Error)

local Compresser = require(script.Parent.Compresser)
local CrossSymbol = require(script.Parent.CrossSymbol)

local NilSymbol = CrossSymbol.create("nil")
local InvokeSymbol = CrossSymbol.create("Invoke")
local InvokeResponseSymbol = CrossSymbol.create("InvokeResponse")

local remote = Instance.new("RemoteEvent", script.Parent)
remote.Name = "NetworkerRemote"

local ServerNetworker = {}
ServerNetworker._networkers = {}
ServerNetworker._sendQueue = {}

function ServerNetworker.new(name, context)
	Assert(type(name) == "string", "Invalid argument #1 (must be a 'string')")
	Assert(
		ServerNetworker._networkers[name] == nil,
		'Invalid argument #1 (Networker with name: "' .. name .. '" already exists)'
	)
	Assert(context == nil or typeof(context) == "table", "Invalid argument #2 (must be a 'table' or 'nil')")

	if ServerNetworker._networkers[name] ~= nil then
		if ServerNetworker._networkers[name] == false then
			while not ServerNetworker._networkers[name] do
				task.wait()
			end
		end
		return ServerNetworker._networkers[name]
	end
	ServerNetworker._networkers[name] = false

	local self = setmetatable({}, { __index = ServerNetworker })
	self._name = name
	self._symbol = CrossSymbol.create(name)
	self._isAlive = true
	self._connections = {}
	self._invokeThreads = {}
	self._onInvoke = nil
	self._rate = context and context.rate or nil
	self._inboundMiddleware = context and context.inboundMiddleware or {}
	self._outboundMiddleware = context and context.outboundMiddleware or {}

	ServerNetworker._networkers[self._name] = self

	return self
end

function ServerNetworker.getNetworker(name)
	return ServerNetworker._networkers[name]
end

function ServerNetworker:Fire(clients, ...)
	Assert(
		typeof(clients) == "Instance" and clients.ClassName == "Player" or typeof(clients) == "table",
		"Invalid argument #1 (must be a table or player instance)"
	)

	table.insert(ServerNetworker._sendQueue, {
		networker = self,
		clients = clients,
		args = { ... },
	})
end

function ServerNetworker:FireAll(...)
	table.insert(ServerNetworker._sendQueue, {
		networker = self,
		clients = "all",
		args = { ... },
	})
end

function ServerNetworker:FireAllExcept(blacklisted, ...)
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

	table.insert(ServerNetworker._sendQueue, {
		networker = self,
		clients = clients,
		args = { ... },
	})
end

function ServerNetworker:Invoke(plr, ...)
	Assert(
		typeof(plr) == "Instance" and plr.ClassName == "Player",
		"Invalid argument #1 (must be a table or player instance)"
	)
	local thread = coroutine.running()
	table.insert(ServerNetworker._sendQueue, {
		invoke = true,
		thread = thread,
		networker = self,
		clients = plr,
		args = { ... },
	})
	return coroutine.yield()
end

function ServerNetworker:OnInvoke(callback)
	Assert(typeof(callback) == "function", "Invalid argument #1 (must be a 'function')")
	self._onInvoke = callback
end

function ServerNetworker:Once(callback)
	Assert(typeof(callback) == "function", "Invalid argument #1 (must be a 'function')")
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function ServerNetworker:Connect(callback)
	Assert(typeof(callback) == "function", "Invalid argument #1 (must be a 'function')")
	return self:_connect(callback)
end

function ServerNetworker:DisconnectAll()
	for _, connection in self._connections do
		if connection._metadata.isImportant then
			continue
		end
		connection:Disconnect()
	end
end

function ServerNetworker:getName()
	return self._name
end

function ServerNetworker:getRate()
	return self._rate
end

function ServerNetworker:setRate(rate)
	Assert(typeof(rate) == "number", "Invalid argument #1 (must be a 'number')")
	self._rate = rate
end

function ServerNetworker:Destroy()
	ServerNetworker._networkers[self._name] = nil
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._isAlive = false
end

function ServerNetworker:_connect(callback, isImportant)
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

function ServerNetworker:_handleOutboundRequest(request, addToPayload)
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

	local clients = request.clients
	if clients == "all" then
		for _, client in Players:GetPlayers() do
			addToPayload(client, data)
		end
	elseif typeof(clients) == "table" then
		for _, client in clients do
			addToPayload(client, data)
		end
	elseif typeof(clients) == "Instance" and clients.ClassName == "Player" then
		addToPayload(clients, data)
	end
end

function ServerNetworker:_handleInboundRequest(plr, request)
	if not self._isAlive then
		return
	end

	if typeof(request[2]) == "string" then
		if string.find(request[2], "^" .. InvokeSymbol) then
			local _, e = string.find(request[2], "^" .. InvokeSymbol)
			local id = string.sub(request[2], e + 1, request[2]:len())
			local args = self._onInvoke and table.pack(self._onInvoke(table.unpack(request, 3))) or {}
			table.insert(ServerNetworker._sendQueue, {
				invokeResponse = true,
				id = id,
				networker = self,
				clients = plr,
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
	local payloads = {}

	local function addToPayload(client, data)
		if not payloads[client] then
			payloads[client] = {}
		end
		table.insert(payloads[client], data)
	end

	for _, request in ServerNetworker._sendQueue do
		task.spawn(function()
			request.networker:_handleOutboundRequest(request, addToPayload)
		end)
	end

	table.clear(ServerNetworker._sendQueue)

	for client, payload in payloads do
		remote:FireClient(client, Compresser.compress(payload))
	end
end)

remote.OnServerEvent:Connect(function(plr, payload)
	payload = Compresser.decompress(payload)
	for _, request in payload do
		task.spawn(function()
			local networker = ServerNetworker.getNetworker(CrossSymbol.getId(request[1]))
			if networker then
				networker:_handleInboundRequest(plr, request)
			end
		end)
	end
end)

return ServerNetworker

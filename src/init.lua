local RunService = game:GetService("RunService")

local Networker = {}
Networker._Networkers = {}

local networkerTypeNameEnding = {
	RemoteEvent = "Event",
	RemoteFunction = "Function",
	BindableEvent = "BindableEvent",
	BindableFunction = "BindableFunction",
}

local function createNetworker(api, networkerType)
	local path = Networker._Networkers
	for i, v in pairs(string.split(api, "/")) do
		if not path[v] then
			path[v] = {}
		end
		path = path[v]
	end
	if path[networkerType] then
		path[networkerType]:Destroy()
	end
	path[networkerType] = Instance.new(networkerType, script)
	path[networkerType].Name = api .. networkerTypeNameEnding[networkerType]

	return path[networkerType]
end

local function getNetworker(api, networkerType)
	return script:FindFirstChild(api .. networkerTypeNameEnding[networkerType])
end

local function getNetworkerOrError(api, networkerType)
	local networker = script:FindFirstChild(api .. networkerTypeNameEnding[networkerType])
	if not networker then
		error(api..' never created on the server', 1)
	end
	return networker
end

if RunService:IsServer() then
	Networker.OnEvent = function(api, func)
		local networker = getNetworker(api, "RemoteEvent")
		if not networker then
			networker = createNetworker(api, "RemoteEvent")
		end
		networker.OnServerEvent:Connect(func)
	end

	Networker.OnInvoke = function(api, func)
		local networker = getNetworker(api, "RemoteFunction")
		if not networker then
			networker = createNetworker(api, "RemoteFunction")
		end
		networker.OnServerInvoke = func
	end

	Networker.OnBindableEvent = function(api, func)
		local networker = getNetworker(api, "BindableEvent")
		if not networker then
			networker = createNetworker(api, "BindableEvent")
		end
		networker.Event:Connect(func)
	end

	Networker.OnBindableInvoke = function(api, func)
		local networker = getNetworker(api, "BindableFunction")
		if not networker then
			networker = createNetworker(api, "BindableFunction")
		end
		networker.OnInvoke = func
	end

	Networker.Send = function(api, client, ...)
		getNetworker(api, "RemoteEvent"):FireClient(client, ...)
	end

	Networker.SendAll = function(api, ...)
		getNetworker(api, "RemoteEvent"):FireAllClients(...)
	end

	Networker.Get = function(api, client, ...)
		return getNetworker(api, "RemoteFunction"):InvokeClient(client, ...)
	end

	Networker.Fire = function(api, ...)
		getNetworker(api, "BindableEvent"):Fire(...)
	end

	Networker.Invoke = function(api, ...)
		getNetworker(api, "BindableFunction"):Invoke(...)
	end
else
	Networker.OnEvent = function(api, func)
		getNetworkerOrError(api, "RemoteEvent").OnClientEvent:Connect(func)
	end

	Networker.OnInvoke = function(api, func)
		getNetworkerOrError(api, "RemoteFunction").OnClientInvoke = func
	end

	Networker.OnBindableEvent = function(api, func)
		local path = getNetworker(api, "BindableEvent")
		if not path then
			path = createNetworker(api, "BindableEvent")
		end
		path.BindableEvent.OnEvent:Connect(func)
	end

	Networker.OnBindableInvoke = function(api, func)
		local path = getNetworker(api, "BindableFunction")
		if not path then
			path = createNetworker(api, "BindableFunction")
		end
		path.BindableFunction.OnInvoke = func
	end

	Networker.Send = function(api, ...)
		getNetworkerOrError(api, "RemoteEvent"):FireServer(...)
	end

	Networker.Get = function(api, ...)
		return getNetworkerOrError(api, "BindableEvent"):InvokeServer(...)
	end

	Networker.Fire = function(api, ...)
		getNetworkerOrError(api, "BindableEvent"):Fire(...)
	end

	Networker.Invoke = function(api, ...)
		getNetworkerOrError(api, "BindableFunction"):Invoke(...)
	end
end

Networker.createNetworker = function(api, networkerType)
	assert(networkerTypeNameEnding[networkerType], networkerType .. " is not a valid NetworkerType")
	createNetworker(api, networkerType)
end
Networker.getNetworker = getNetworker
Networker.getNetworkerOrError = getNetworkerOrError

return Networker

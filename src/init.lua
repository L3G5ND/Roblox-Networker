local RunService = game:GetService("RunService")

local Remote = RunService:IsServer() and require(script.ServerRemote) or require(script.ClientRemote)

local NetworkerAPI = {}

NetworkerAPI.new = Remote.new

NetworkerAPI.DropMiddleware = Remote.DropMiddleware

NetworkerAPI.symbol = require(script.Symbol)

return NetworkerAPI

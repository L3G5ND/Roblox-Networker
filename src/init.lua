local RunService = game:GetService("RunService")

local networker = RunService:IsServer() and require(script.Server) or require(script.Client)

local NetworkerAPI = {}

NetworkerAPI.new = networker.new

NetworkerAPI.symbol = require(script.CrossSymbol)

return NetworkerAPI

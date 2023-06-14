local RS = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Networker = require(RS.Networker)
local Settings = require(RS.Settings)

if Settings.StressTest then
    if Settings.NativeNetworking then
        local remote = Instance.new("RemoteEvent")
        remote.Name = "StressRemote"
        remote.Parent = RS
    
        RunService.Heartbeat:Connect(function()
            for _ = 1, 200 do
                remote:FireAllClients()
            end
        end)
    else
        local remote = Networker.new('StressRemote')
        RunService.Heartbeat:Connect(function()
            for _ = 1, 200 do
                remote:FireAll()
            end
        end)
    end
else
    local remote = Networker.new('TestRemote', {
        rate = 5,
        inboundMiddleware = {
            function(player, ...)
                return ...
            end,
        },
        outboundMiddleware = {
            function(players, ...)
                return ...
            end,
        }
    })
    Players.PlayerAdded:Connect(function(plr)
        remote:OnInvoke(function(plr, a, b, c)
            print('[Invoke]', plr, a, b, c)
            return c, b, a
        end)
        remote:Connect(function(...)
            print('[Fire]', ...)
        end)
        remote:Once(function(...)
            print('[Once]', ...)
        end)

        task.wait(4)

        remote:Fire(plr, 'Fire 1 from server')
        remote:Fire(plr, 'Fire 2 from server')
        print('[Invoke]', remote:Invoke(plr, 'a', 'b', 'c'))
        task.wait()
        remote:Fire(plr, 'Fire 3 from server')
    end)
end

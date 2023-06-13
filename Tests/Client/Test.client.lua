local RS = game:GetService('ReplicatedStorage')

local Networker = require(RS.Networker)
local Settings = require(RS.Settings)

if Settings.StressTest then
    if Settings.NativeNetworking then
        local remote = RS:WaitForChild("StressRemote")
        remote.OnClientEvent:Connect(function() end)
    else
        local remote = Networker.new('StressRemote')
        remote:Connect(function() end)
    end
else
    local remote = Networker.new('TestRemote', {
        rate = 5,
        inboundMiddleware = {
            function(...)
                return ...
            end,
        },
        outboundMiddleware = {
            function(...)
                return ...
            end,
        }
    })
    remote:OnInvoke(function(a, b, c)
        print('[Invoke]', a, b, c)
        return c, b, a
    end)
    remote:Connect(function(...)
        print('[Fire]', ...)
    end)
    remote:Once(function(...)
        print('[Once]', ...)
    end)

    remote:Fire('Fire 1 from client')
    remote:Fire('Fire 2 from client')
    print('[Invoke]', remote:Invoke('a', 'b', 'c'))
    task.wait()
    remote:Fire('Fire 3 from client')
end

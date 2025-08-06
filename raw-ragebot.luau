-- defensive peek by listening humanoid state jumping, after jump over then set pos to floor
-- store and fix pos if raycast from pos hit target, delay ping * 2
-- if player shot by ragebot, create context, dont shoot player until health changes, timeout 2 secs
local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")
local uis = game:GetService("UserInputService")
local run_service = game:GetService("RunService")
local local_player = players.LocalPlayer
local events = replicated_storage["_CS.Events"]
local weapon_list = events.GetList:Invoke()
local ping = game:GetService("Stats").PerformanceStats.Ping

local rage_bot = {}
rage_bot.raycast_params = RaycastParams.new()
rage_bot.raycast_params.FilterType = Enum.RaycastFilterType.Exclude
rage_bot.raycast_params.FilterDescendantsInstances = {workspace.RayIgnore}
rage_bot.body_parts = {"Head"}
rage_bot.position_logs = {}
rage_bot.player_ctxs = {} -- dict, boolean flag

-- server-side check
function rage_bot.integrity()
    local v126 = string.len(rage_bot.gun.Name)
    local v127 = rage_bot.gun_settings
    local v128 = 1
    for v129 = 1, v126 do
        local v132 = v128 + string.byte(string.sub(rage_bot.gun.Name, v129, v129))
        v128 = v132 + string.byte(string.sub(rage_bot.gun.Name, v129, v129))
    end
    return tonumber(string.sub(tostring(v128 * replicated_storage.ServerRunTime.Value * rage_bot.gun.Handle.Mag.Value * v126 * v127.Firerate * v127.Accuracy), 1, 16))
end

function rage_bot.replicate_hit(Hit, Position, Normal)
    events.AmmoRemover:FireServer(rage_bot.gun.Handle.Mag)
    events.CreateBulletHole:Fire(Position, Hit, Normal, true)
    events.WeaponServer:FireServer("Player", Hit.Parent.Humanoid, rage_bot.gun.Name, Hit, rage_bot.gun_settings.Accuracy, rage_bot.integrity(), replicated_storage.ServerRunTime.Value)
    events.PlayerHit:Fire(rage_bot.gun_settings.Damage, rage_bot.target_ctx.Instance.Name, rage_bot.target_ctx.Instance.Parent)
end

function rage_bot.scan(player)
    local origin = rage_bot.character.Head.Position
    for _, body_part in rage_bot.body_parts do
        local target = player.Character[body_part]
        local magnitude = (target.Position - origin).Magnitude
        local first_result = rage_bot.raycast(origin, (target - origin).Unit * magnitude)
        if first_result and first_result.Instance:IsDescendantOf(player.Character) then
            return {
                position = first_result.Position;
                instance = target;
                normal = first_result.Normal;
            }
        end
        for idx = #rage_bot.position_logs, 1, -1 do
            local position_ctx = rage_bot.position_logs[idx]
            local delta = target - position_ctx.origin
            local result = rage_bot.raycast(origin, delta.Unit * magnitude)
            if result and result.Instance:IsDescendantOf(player.Character) then
                return {
                    position_ctx = position_ctx;
                    position = result.Position;
                    instance = target;
                    normal = result.Normal;
                }
            end
        end
    end
end

function rage_bot.vector3_to_normal_id(vec)
    local directions = {
        [Enum.NormalId.Top] = Vector3.new(0, 1, 0),
        [Enum.NormalId.Bottom] = Vector3.new(0, -1, 0),
        [Enum.NormalId.Front] = Vector3.new(0, 0, -1),
        [Enum.NormalId.Back] = Vector3.new(0, 0, 1),
        [Enum.NormalId.Right] = Vector3.new(1, 0, 0),
        [Enum.NormalId.Left] = Vector3.new(-1, 0, 0),
    }
    local best_match = Enum.NormalId.Top
    local best_dot = -math.huge
    for normal_id, dir in next, directions do
        local dot = vec:Dot(dir)
        if dot > best_dot then
            best_dot = dot
            best_match = normal_id
        end
    end
    return best_match
end

function rage_bot.fire_shot()
    if rage_bot.gun_settings.Firemode == "Shot" or rage_bot.gun_settings.Firemode == "Sniper" then
        events.GunDetailClient:Fire(rage_bot.target_ctx.Position, rage_bot.target_ctx.Instance, rage_bot.gun.Handle.Shot, "Shotgun", rage_bot.vector3_to_normal_id(rage_bot.target_ctx.Normal))
        if rage_bot.gun_settings.Pump then
            if rage_bot.gun_settings.Firemode == "Sniper" then
                task.delay(0.3, function()
                    events.ShootAnim:Fire("Bolt", 0.5, rage_bot.gun.Name)
                end)
            else
                events.ShootAnim:Fire("Bolt", 0.7, rage_bot.gun.Name, nil, nil, nil, true)
            end
        end
        events.ShootAnim:Fire("Shoot", nil, rage_bot.gun.Name)
        if rage_bot.gun_settings.Firemode == "Sniper" then
            events.ShootAnim:Fire("Shoot", nil, rage_bot.gun.Name, "Pump")
        else
            for _ = 1, 6 do
                events.ShootAnim:Fire("Shoot", nil, rage_bot.gun.Name, "Pump")
            end
        end
    else
        events.GunDetailClient:Fire(rage_bot.target_ctx.Position, rage_bot.target_ctx.Instance, rage_bot.gun.Handle.Shot, nil, rage_bot.vector3_to_normal_id(rage_bot.target_ctx.Normal))
        events.ShootAnim:Fire("Shoot", nil, rage_bot.gun.Name)
    end
end

function rage_bot.think()
    if not rage_bot.gun or #rage_bot.body_parts == 0 or rage_bot.gun.Handle.Mag.Value < 1 or rage_bot.character.Humanoid.Health < 1 then return end
    local origin = rage_bot.character.Head.Position
    local targets = {}
    for _, player in next, players:GetPlayers() do
        if player == local_player then continue end
        if rage_bot.player_ctxs[player] then continue end
        local priority = player.Character and not player.Character:FindFirstChild("ForceField") and player.Character:FindFirstChild("Head")
        if not priority or (priority.Position - origin).Magnitude > rage_bot.gun_settings.BulletSpeed then continue end
        local Humanoid = player.Character:FindFirstChild("Humanoid")
        if not Humanoid or Humanoid.Health < 1 then continue end
        local display = priority:FindFirstChild("PlayerDisplay")
        if not display or display.Wanted.Text ~= "Wanted" then continue end
        table.insert(targets, player)
    end
    if #targets == 0 then return end
    table.sort(targets, function(a, b)
        return (origin - a.Character.Head.Position).Magnitude < (origin  - b.Character.Head.Position).Magnitude
    end)
    for idx = 1, #targets do
        local target = targets[idx]
        local result = rage_bot.scan(target)
        if result then
            rage_bot.target_ctx = result
            if rage_bot.target_ctx.player_ctx then
                rage_bot.character.HumanoidRootPart.Position = rage_bot.target_ctx.position_ctx.primary_origin
                table.clear(rage_bot.position_logs)
            end
            rage_bot.player_ctxs[target] = true
            local humanoid: Humanoid = target.Character:FindFirstChild("Humanoid")
            local listen_health = humanoid.HealthChanged:Once(function()
                rage_bot.player_ctxs[target] = false
            end)
            task.delay(2, function()
                listen_health:Disconnect()
                rage_bot.player_ctxs[target] = false -- idk if theres a race condition here
            end)
            rage_bot.fire_shot()
            for i = 1, rage_bot.bullets_needed() do
                if rage_bot.gun_settings.Firemode == "Shot" or rage_bot.gun_settings.Firemode == "Sniper" then
                    if rage_bot.gun_settings.Firemode == "Sniper" then
                        rage_bot.replicate_hit(rage_bot.target_ctx.Instance, rage_bot.target_ctx.Position, rage_bot.target_ctx.Normal)
                    else
                        for _ = 1, 6 do
                            rage_bot.replicate_hit(rage_bot.target_ctx.Instance, rage_bot.target_ctx.Position, rage_bot.target_ctx.Normal)
                        end
                    end
                else
                    rage_bot.replicate_hit(rage_bot.target_ctx.Instance, rage_bot.target_ctx.Position, rage_bot.target_ctx.Normal)
                end
            end
            return
        end
    end
end

-- NOTE: if fixed pos then call table.clear(rage_bot.position_logs)
function rage_bot.update_logs()
    for i = 1, #rage_bot.position_logs do
        if rage_bot.position_logs[i].ts + ping:GetValue() / 1000 < tick() then
            table.remove(rage_bot.position_logs, i)
        end
    end
    if rage_bot.character.HumanoidRootPart.AssemblyLinearVelocity.Magnitude < 10 then return end
    table.insert(rage_bot.position_logs, {
        ts = tick();
        origin = rage_bot.character.Head.Position;
        primary_origin = rage_bot.character.HumanoidRootPart.Position
    })
end

function rage_bot.ignored(instance)
    if instance:IsDescendantOf(workspace.PlayerVehicles) then
        if instance.Name == "Window" then
            return true
        end
        local user_vehicle = rage_bot.get_vehicle()
        if user_vehicle and instance:IsDescendantOf(user_vehicle) then
            return true
        end
    end
end

function rage_bot.get_vehicle()
    local seat = rage_bot.character.Humanoid.SeatPart
    if not seat then return end
    for _, vehicle in next, workspace.PlayerVehicles:GetChildren() do
        if vehicle:IsDescendantOf(seat) then
            return vehicle
        end
    end
end

function rage_bot.raycast(from, to, depth)
    depth = depth or 0
    if depth > 8 then return end
    local result = workspace:Raycast(from, to, rage_bot.raycast_params)
    if result and rage_bot.ignored(result.Instance) then
        rage_bot.raycast_params:AddToFilter(result.Instance)
        return rage_bot.raycast(result.Position, to, depth + 1)
    end
    return result
end

-- pls no waste boolets
function rage_bot.bullets_needed()
    return math.min(math.ceil(100/rage_bot.gun_settings.Damage), rage_bot.gun.Handle.Mag.Value)
end

function rage_bot.defensive_peek(old, _)
    if old == Enum.HumanoidStateType.Jumping then
        local hrp = rage_bot.character.HumanoidRootPart
        local origin = hrp.Position
        local result = rage_bot.raycast(origin, origin - Vector3.new(0, 1024, 0))
        if result then
            hrp.Position = Vector3.new(origin.X, result.Position.Y + hrp.Size.Y / 2, origin.Z)
        end
    end
end

function rage_bot.weapon(tool)
    local main_gun_script = tool:FindFirstChild("MainGunScript")
    if not main_gun_script then return end
    rage_bot.gun = tool
    rage_bot.gun_settings = weapon_list[tool.Name]
    rage_bot.gun_settings.BulletSpeed = rage_bot.gun_settings.BulletSpeed or 700
    local update_logs = run_service.PreRender:Connect(rage_bot.update_logs)
    local think = run_service.Stepped:Connect(rage_bot.think)
    local defensive = rage_bot.character.Humanoid.StateChanged:Connect(rage_bot.defensive_peek)
    local unused; unused = tool.AncestryChanged:Connect(function(_, parent)
        if parent ~= rage_bot.character or not rage_bot.character then
            rage_bot.gun = nil
            think:Disconnect()
            defensive:Disconnect()
            update_logs:Disconnect()
            unused:Disconnect()
        end
    end)
end

function rage_bot.bhop(delta)
    local humanoid = rage_bot.character:FindFirstChild("Humanoid")
    if not humanoid then return end
    if uis:IsKeyDown(Enum.KeyCode.Space) then
        humanoid.Jump = true
        if humanoid.FloorMaterial == Enum.Material.Air then
            rage_bot.character:TranslateBy(humanoid.MoveDirection * delta * 32)
		end
    end
end

function rage_bot.setup(character)
    rage_bot.character = character
    if character:FindFirstChildOfClass("Tool") then
        rage_bot.weapon(character:FindFirstChildOfClass("Tool"))
    end
    local detect_weapon = character.ChildAdded:Connect(rage_bot.weapon)
    local bhop = run_service.Heartbeat:Connect(rage_bot.bhop)
    local died; died = character.AncestryChanged:Connect(function(_, parent)
        if not parent then
            detect_weapon:Disconnect()
            bhop:Disconnect()
            died:Disconnect()
        end
    end)
end

local_player.CharacterAdded:Connect(rage_bot.setup)

if local_player.Character then
    rage_bot.setup(local_player.Character)
end

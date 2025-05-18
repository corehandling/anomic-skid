-- doesnt check wall but distance???
-- i dont know much about anomic and only like decompiled 2 scripts and made this under a day combined
-- works with xeno, solara 

if _G.hack then return end _G.hack = true

local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")
local virtual_input = game:GetService("VirtualInputManager")
local run_service = game:GetService("RunService")
local uis = game:GetService("UserInputService")
local local_player = players.LocalPlayer
local events = replicated_storage["_CS.Events"]
local weapon_list = events.GetList:Invoke()

local rage_bot = {}

rage_bot.body_parts = {"Head", "UpperTorso", "LowerTorso"}
rage_bot.last_shot = tick()
rage_bot.extra_bullets = 999

function rage_bot.dynamic_resolution(distance)
    return distance < 250 and 4 or 3
end

function rage_bot.get_points(origin, part, magnitude)
    local points = {}
    local padding = math.min(part.Size.X, part.Size.Y, part.Size.Z) * 0.05
    local size = part.Size - Vector3.new(padding, padding, padding)
    local resolution = rage_bot.dynamic_resolution(magnitude)
    for x = 0, resolution - 1 do
        for y = 0, resolution - 1 do
            for z = 0, resolution - 1 do
                local offset = (part.CFrame * CFrame.new((x/(resolution-1)-0.5)*size.X, (y/(resolution-1)-0.5)*size.Y, (z/(resolution-1)-0.5)*size.Z)).Position
                if (offset - origin).Magnitude > magnitude then continue end
                table.insert(points, offset)
            end
        end
    end
    return points
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

function rage_bot.raycast(from, to)
    local result = workspace:Raycast(from, to, rage_bot.raycast_params)
    if result and rage_bot.ignored(result.Instance) then
        rage_bot.raycast_params:AddToFilter(result.Instance)
        return rage_bot.raycast(result.Position, to)
    end
    return result
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
    events.CreateBulletHole:Fire(Position, Hit, Normal, true)
    events.WeaponServer:FireServer("Player", Hit.Parent.Humanoid, rage_bot.gun.Name, Hit, rage_bot.gun_settings.Accuracy, rage_bot.integrity(), replicated_storage.ServerRunTime.Value)
    events.PlayerHit:Fire(rage_bot.gun_settings.Damage, rage_bot.current_target.Instance.Name, rage_bot.current_target.Instance.Parent)
end

function rage_bot.fire_shot()
    if rage_bot.gun_settings.Firemode == "Shot" or rage_bot.gun_settings.Firemode == "Sniper" then
        events.GunDetailClient:Fire(rage_bot.current_target.Position, rage_bot.current_target.Instance, rage_bot.gun.Handle.Shot, "Shotgun", rage_bot.vector3_to_normal_id(rage_bot.current_target.Normal))
        events.AmmoRemover:FireServer(rage_bot.gun.Handle.Mag)
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
            rage_bot.replicate_hit(rage_bot.current_target.Instance, rage_bot.current_target.Position, rage_bot.current_target.Normal)
        else
            for _ = 1, 6 do
                events.ShootAnim:Fire("Shoot", nil, rage_bot.gun.Name, "Pump")
                rage_bot.replicate_hit(rage_bot.current_target.Instance, rage_bot.current_target.Position, rage_bot.current_target.Normal)
            end
        end
    else
        events.GunDetailClient:Fire(rage_bot.current_target.Position, rage_bot.current_target.Instance, rage_bot.gun.Handle.Shot, nil, rage_bot.vector3_to_normal_id(rage_bot.current_target.Normal))
        events.ShootAnim:Fire("Shoot", nil, rage_bot.gun.Name)
        rage_bot.replicate_hit(rage_bot.current_target.Instance, rage_bot.current_target.Position, rage_bot.current_target.Normal)
    end
end

function rage_bot.scan(player)
    local origin = rage_bot.character.Head.Position
    for _, body_part in rage_bot.body_parts do
        local target = player.Character[body_part]
        local magnitude = (target.Position - origin).Magnitude
        local points = rage_bot.get_points(origin, target, magnitude)
        for idx = 1, #points do
            local delta = points[idx] - origin
            local result = rage_bot.raycast(origin, delta.Unit * magnitude)
            if result and result.Instance:IsDescendantOf(player.Character) then
                return {
                    Position = result.Position;
                    Instance = target;
                    Normal = result.Normal;
                }
            end
        end
    end
end

function rage_bot.think()
    if not rage_bot.gun or #rage_bot.body_parts == 0 or rage_bot.gun.Handle.Mag.Value < 1 or rage_bot.character.Humanoid.Health < 1 or tick() - rage_bot.last_shot < 60 / rage_bot.gun_settings.Firerate then return end
    local origin = rage_bot.character.Head.Position
    local targets = {}
    for _, player in next, players:GetPlayers() do
        if player == local_player then continue end
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
        local result = rage_bot.scan(targets[idx])
        if result then
            rage_bot.current_target = result
            for _ = 1, math.min(rage_bot.extra_bullets, rage_bot.gun.Handle.Mag.Value) do
                rage_bot.fire_shot()
            end
            return
        end
    end
end

function rage_bot.weapon(tool)
    local main_gun_script = tool:FindFirstChild("MainGunScript")
    if not main_gun_script then return end
    uis.MouseBehavior = Enum.MouseBehavior.LockCenter
    rage_bot.gun = tool
    rage_bot.gun_settings = weapon_list[tool.Name]
    local reserved = replicated_storage.PlayerAmmo[local_player.Name][weapon_list[tool.Name].AmmoType]
    if tool.Handle.Mag.Value == 0 and reserved ~= 0 then
        task.delay(0.2, function()
            virtual_input:SendKeyEvent(true, Enum.KeyCode.R, false, game)
            virtual_input:SendKeyEvent(false, Enum.KeyCode.R, false, game)
        end)
    end
    rage_bot.character.Humanoid.AutoRotate = false
    rage_bot.gun_settings.BulletSpeed = rage_bot.gun_settings.BulletSpeed or 700
    local fired = tool.Handle.Mag.Changed:Connect(function(ammo)
        rage_bot.last_shot = tick()
        if ammo == 0 and reserved ~= 0 then
            task.delay(0.2, function()
                virtual_input:SendKeyEvent(true, Enum.KeyCode.R, false, game)
                virtual_input:SendKeyEvent(false, Enum.KeyCode.R, false, game)
            end)
        end
    end)
    local unused; unused = tool.AncestryChanged:Connect(function(_, parent)
        if parent ~= rage_bot.character or not rage_bot.character then
            uis.MouseBehavior = Enum.MouseBehavior.Default
            rage_bot.character.Humanoid.AutoRotate = true
            rage_bot.gun = nil
            fired:Disconnect()
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
    rage_bot.raycast_params = RaycastParams.new()
    rage_bot.raycast_params.FilterType = Enum.RaycastFilterType.Exclude
    rage_bot.raycast_params.FilterDescendantsInstances = {workspace.RayIgnore}
    if character:FindFirstChildOfClass("Tool") then
        rage_bot.weapon(character:FindFirstChildOfClass("Tool"))
    end
    local detect_weapon = character.ChildAdded:Connect(rage_bot.weapon)
    local bhop = run_service.Heartbeat:Connect(rage_bot.bhop)
    local think = run_service.Stepped:Connect(rage_bot.think)
    local died; died = character.AncestryChanged:Connect(function(_, parent)
        if not parent then
            detect_weapon:Disconnect()
            bhop:Disconnect()
            think:Disconnect()
            died:Disconnect()
        end
    end)
end

local_player.CharacterAdded:Connect(rage_bot.setup)

if local_player.Character then
    rage_bot.setup(local_player.Character)
end

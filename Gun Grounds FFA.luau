local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local Bot = {}
Bot.LastShot = tick()

function Bot.Hit(Info)
    ReplicatedStorage.Remotes.PlayerReQuests.GunShot:FireServer(
        Bot.Gun.BodyAttach["Gun Sound"],
        Bot.Gun:FindFirstChild("Muz") and Bot.Gun.Muz.Flash or nil,
        Bot.Gun:FindFirstChild("Muz2") and Bot.Gun.Muz2.Flash or nil
    )
    for _ = 1, Bot.Gun.Configuration.PelletAmount.Value do
        Bot.Gun.Remotes.S:FireServer()
        Bot.Gun.Remotes.CheckShot:FireServer(
            Bot.Ammo,
            Bot.Gun.Configuration.spread.Value,
            Bot.Gun.Configuration.Ammo.Value,
            Bot.Gun.Configuration.reloadTime.Value,
            CFrame.new(Workspace.CurrentCamera.CFrame.Position, Info.Position),
            Info.Position,
            Info.Instance,
            Bot.Gun.Seed.Value + 11
        )
        ReplicatedStorage.Remotes.PlayerReQuests.ProjectileFinished:FireServer(
            tick(),
            CFrame.new(Info.Position, Info.Position + Info.Normal),
            Bot.Gun.Configuration:FindFirstChild("HitEffect") and Bot.Gun.Configuration.HitEffect.Value or "Gib_T"
        )
        if Bot.Gun:FindFirstChild("Muz") and 4 < (Info.Position - Bot.Gun.Muz.LOC.WorldPosition).Magnitude then
            ReplicatedStorage.Remotes.PlayerReQuests.ProjectileRender:FireServer(
                tick(),
                Bot.Character,
                Bot.Gun.Muz.LOC.WorldPosition,
                Info.Position,
                Bot.Gun.Configuration:FindFirstChild("BulletForce") and Bot.Gun.Configuration.BulletForce.Value or 85,
                0,
                Vector3.zero,
                Bot.Gun.Configuration:FindFirstChild("Bullet") and Bot.Gun.Configuration.Bullet.Value or "Bullet"
            )
        end
    end
end

function Bot.Weapon(Tool)
    if not Tool:FindFirstChild("Configuration") then return end
    Bot.Gun = Tool
    Bot.Ammo = Tool.Configuration.Ammo.Value
    local AmmoCounter; AmmoCounter = RunService.Heartbeat:Connect(function()
        if LocalPlayer.PlayerGui:FindFirstChild("GunOverlay") then
            AmmoCounter:Disconnect()
            AmmoCounter = LocalPlayer.PlayerGui.GunOverlay.ScreenSize.AmmoFrame.BarCon.TextLabel.Changed:Connect(function()
                Bot.LastShot = tick()
                Bot.Ammo = tonumber(LocalPlayer.PlayerGui.GunOverlay.ScreenSize.AmmoFrame.BarCon.TextLabel.Text)
            end)
        end
    end)
    local Unused; Unused = Tool.AncestryChanged:Connect(function(_, Parent)
        if not Bot.Character or Parent ~= Bot.Character then
            Unused:Disconnect()
            AmmoCounter:Disconnect()
            Bot.Gun = nil
        end
    end)
end

function Bot.Scan()
    if not Bot.Gun or Bot.Ammo <= 0 or tick() - Bot.LastShot < (Bot.Gun.Configuration:FindFirstChild("FireRate") and Bot.Gun.Configuration.FireRate.Value or 0.1) then return end
    for _, Player in next, Players:GetPlayers() do
        if Player == LocalPlayer then continue end
        local Head = Player.Character and Player.Character:FindFirstChild("Head")
        if not Head then continue end
        local Result = Workspace:Raycast(Workspace.CurrentCamera.CFrame.Position, (Head.Position - Workspace.CurrentCamera.CFrame.Position).Unit * (Head.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude, Bot.Params)
        if Result and Result.Instance:IsDescendantOf(Player.Character) then
            LocalPlayer.PlayerGui.GunOverlay.ScreenSize.AmmoFrame.BarCon.TextLabel.Text = tostring(tonumber(LocalPlayer.PlayerGui.GunOverlay.ScreenSize.AmmoFrame.BarCon.TextLabel.Text) - 1)
            Bot.Hit({
                Position = Result.Position;
                Instance = Head;
                Normal = Result.Normal;
            })
            return
        end
    end
end

function Bot.Setup(Character)
    Bot.Character = Character
    Bot.Params = RaycastParams.new()
    Bot.Params.FilterType = Enum.RaycastFilterType.Exclude
    Bot.Params.FilterDescendantsInstances = {Character, Workspace.bulletStorage, Workspace.Debug}
    if Character:FindFirstChildOfClass("Tool") then
        Bot.Weapon(Character:FindFirstChildOfClass("Tool"))
    end
    local WeaponEvent = Character.ChildAdded:Connect(Bot.Weapon)
    local ScanEvent = RunService.PostSimulation:Connect(Bot.Scan)
    local Dead; Dead = Character.AncestryChanged:Connect(function(_, Parent)
        if not Parent then
            WeaponEvent:Disconnect()
            ScanEvent:Disconnect()
            Dead:Disconnect()
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(Bot.Setup)

if LocalPlayer.Character then
    Bot.Setup(LocalPlayer.Character)
end

print("loadedz")

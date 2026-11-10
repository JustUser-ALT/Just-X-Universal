-- UGC Animation Conflict and Rig Diagnostic V14
-- Checks active Animator tracks and Motor6D.Transform changes while directly playing R6 Think clips.
-- Does not modify Animate AnimationIds or restart Animate.
-- Stops/destroys only tracks and Animation instances created by this diagnostic.

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local TESTS = {
    {Name = "Idle1", Id = "rbxassetid://77943023928454", Duration = 4},
    {Name = "Walk", Id = "rbxassetid://110376969855395", Duration = 4},
    {Name = "Run", Id = "rbxassetid://130316627494431", Duration = 4},
}

local function log(message)
    print("[UGC V14] " .. tostring(message))
end

local character = localPlayer.Character
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

if not character or not humanoid or not animator then
    log("ERROR: Character, Humanoid or Animator missing. No changes made.")
    return
end

local function getTracks()
    local ok, tracks = pcall(function()
        return animator:GetPlayingAnimationTracks()
    end)
    return ok and tracks or {}
end

local function trackDescription(track)
    local animation = track.Animation
    local animationId = animation and animation.AnimationId or "unknown"
    local name = animation and animation.Name or "unnamed"
    return string.format(
        "Name=%s | ID=%s | Priority=%s | Playing=%s | Length=%.3f | Weight=%.3f",
        name,
        animationId,
        tostring(track.Priority),
        tostring(track.IsPlaying),
        track.Length,
        track.WeightCurrent
    )
end

local function getMotors()
    local motors = {}
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("Motor6D") then
            motors[#motors + 1] = descendant
        end
    end
    return motors
end

local function transformDelta(a, b)
    local relative = a:ToObjectSpace(b)
    local _, angle = relative:ToAxisAngle()
    return relative.Position.Magnitude, math.abs(angle)
end

local function snapshotTransforms(motors)
    local snapshot = {}
    for _, motor in ipairs(motors) do
        snapshot[motor] = motor.Transform
    end
    return snapshot
end

local function reportChangedMotors(motors, before)
    local changed = {}
    for _, motor in ipairs(motors) do
        local old = before[motor]
        if old and motor.Parent then
            local positionDelta, angleDelta = transformDelta(old, motor.Transform)
            if positionDelta > 0.001 or angleDelta > math.rad(1) then
                changed[#changed + 1] = {
                    Name = motor.Name,
                    Path = motor:GetFullName(),
                    Position = positionDelta,
                    Angle = math.deg(angleDelta),
                }
            end
        end
    end

    table.sort(changed, function(a, b)
        return a.Angle + a.Position > b.Angle + b.Position
    end)

    log("Motor6D transforms changed: " .. tostring(#changed) .. "/" .. tostring(#motors))
    for index = 1, math.min(#changed, 12) do
        local item = changed[index]
        log(string.format(
            "Joint %s | PositionDelta=%.4f | AngleDelta=%.2f deg",
            item.Path,
            item.Position,
            item.Angle
        ))
    end
    if #changed == 0 then
        log("No significant Motor6D.Transform changes detected in the sampled frame.")
    end
end

local createdTracks = {}
local createdAnimations = {}

local function cleanup()
    for _, track in ipairs(createdTracks) do
        pcall(function()
            track:Stop(0.1)
            track:Destroy()
        end)
    end
    for _, animation in ipairs(createdAnimations) do
        pcall(function()
            animation:Destroy()
        end)
    end
end

log("========== UGC Animation Conflict and Rig Diagnostic V14 ==========")
log("Character: " .. character:GetFullName())
log("RigType: " .. tostring(humanoid.RigType))
log("Animator: " .. animator:GetFullName())
log("Motor6D count: " .. tostring(#getMotors()))
log("Baseline active tracks:")

for _, track in ipairs(getTracks()) do
    log(trackDescription(track))
end

local success, err = pcall(function()
    for _, test in ipairs(TESTS) do
        if localPlayer.Character ~= character or not character.Parent then
            log("Character changed; stopping test.")
            break
        end

        log("----- " .. test.Name .. " -----")
        local motors = getMotors()
        local before = snapshotTransforms(motors)

        local animation = Instance.new("Animation")
        animation.Name = "UGC_V14_" .. test.Name
        animation.AnimationId = test.Id
        animation.Parent = character
        createdAnimations[#createdAnimations + 1] = animation

        local track = animator:LoadAnimation(animation)
        createdTracks[#createdTracks + 1] = track
        track.Priority = Enum.AnimationPriority.Action4
        track.Looped = true
        track:Play(0.1, 1, 1)

        task.wait(0.35)
        log("Test track: " .. trackDescription(track))
        log("Active tracks during " .. test.Name .. ":")
        for _, activeTrack in ipairs(getTracks()) do
            log(trackDescription(activeTrack))
        end

        local elapsed = 0
        while elapsed < test.Duration do
            if localPlayer.Character ~= character or not character.Parent then
                break
            end
            task.wait(0.25)
            elapsed += 0.25
        end

        log(string.format(
            "%s final: IsPlaying=%s | Length=%.4f | TimePosition=%.4f | Weight=%.3f",
            test.Name,
            tostring(track.IsPlaying),
            track.Length,
            track.TimePosition,
            track.WeightCurrent
        ))
        reportChangedMotors(motors, before)

        track:Stop(0.1)
        task.wait(0.25)
    end
end)

cleanup()

if success then
    log("RESULT: Diagnostic completed. Only diagnostic tracks were removed.")
else
    log("RESULT: TEST ERROR: " .. tostring(err))
    log("Cleanup attempted.")
end

log("Animate AnimationIds were not modified.")
log("========== END V14 ==========")

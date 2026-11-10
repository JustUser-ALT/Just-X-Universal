-- UGC Animation Character Test V12
-- Applies R6 Think Idle, Walk and Run to the local character for 25 seconds.
-- Automatically restores the original AnimationIds and Animate state.
-- This is a local-character test; FE replication is not assumed.

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local IDS = {
    Idle1 = "rbxassetid://77943023928454",
    Idle2 = "rbxassetid://71374122142959",
    Walk = "rbxassetid://110376969855395",
    Run = "rbxassetid://130316627494431",
}

local TEST_DURATION = 25

local function log(message)
    print("[UGC V12] " .. tostring(message))
end

local function findAnimation(parent, name)
    if not parent then
        return nil
    end

    local direct = parent:FindFirstChild(name)
    if direct and direct:IsA("Animation") then
        return direct
    end

    for _, descendant in ipairs(parent:GetDescendants()) do
        if descendant.Name == name and descendant:IsA("Animation") then
            return descendant
        end
    end

    return nil
end

local function getTargets(character)
    local animate = character:FindFirstChild("Animate")
    if not animate then
        return nil, "Animate script not found"
    end

    local idleFolder = animate:FindFirstChild("idle")
    local walkFolder = animate:FindFirstChild("walk")
    local runFolder = animate:FindFirstChild("run")

    if not idleFolder or not walkFolder or not runFolder then
        return nil, "Expected idle/walk/run folders not found under Animate"
    end

    local targets = {
        {Name = "Idle1", Object = findAnimation(idleFolder, "Animation1"), NewId = IDS.Idle1},
        {Name = "Idle2", Object = findAnimation(idleFolder, "Animation2"), NewId = IDS.Idle2},
        {Name = "Walk", Object = findAnimation(walkFolder, "WalkAnim"), NewId = IDS.Walk},
        {Name = "Run", Object = findAnimation(runFolder, "RunAnim"), NewId = IDS.Run},
    }

    for _, target in ipairs(targets) do
        if not target.Object then
            return nil, target.Name .. " Animation object not found"
        end
    end

    return targets, animate
end

local character = localPlayer.Character
if not character then
    log("ERROR: LocalPlayer.Character not found.")
    return
end

local humanoid = character:FindFirstChildOfClass("Humanoid")
local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
if not humanoid or not animator then
    log("ERROR: Humanoid or existing Animator not found. No changes made.")
    return
end

local targets, animateOrError = getTargets(character)
if not targets then
    log("ERROR: " .. tostring(animateOrError) .. ". No changes made.")
    return
end

local animate = animateOrError
local originalEnabled = animate.Disabled
local originalIds = {}
local targetObjects = {}

for _, target in ipairs(targets) do
    originalIds[target.Name] = target.Object.AnimationId
    targetObjects[target.Object] = true
    log(target.Name .. " original: " .. tostring(target.Object.AnimationId))
end

local function restore()
    for _, target in ipairs(targets) do
        if target.Object and target.Object.Parent then
            target.Object.AnimationId = originalIds[target.Name]
        end
    end

    -- A single controlled restart after restoring the original IDs.
    animate.Disabled = true
    task.wait(0.1)
    animate.Disabled = originalEnabled

    log("Original animation IDs and Animate state restored.")
end

local applied = false
local ok, err = pcall(function()
    log("========== UGC Animation Character Test V12 ==========")
    log("Character: " .. character:GetFullName())
    log("RigType: " .. tostring(humanoid.RigType))
    log("Animator parent: " .. animator.Parent:GetFullName())

    -- Stop only tracks that belong to the four Animation objects being replaced.
    local stopped = 0
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local animation = track.Animation
        if animation and targetObjects[animation] then
            track:Stop(0.1)
            stopped += 1
        end
    end
    log("Stopped matching old locomotion tracks: " .. tostring(stopped))

    applied = true
    for _, target in ipairs(targets) do
        target.Object.AnimationId = target.NewId
        log(target.Name .. " applied: " .. target.Object.AnimationId)
    end

    -- One restart so the Animate script reloads the changed AnimationIds.
    animate.Disabled = true
    task.wait(0.1)
    animate.Disabled = originalEnabled

    log("Applied Idle (both variants), Walk and Run.")
    log("Keep moving/standing to trigger the states. Test window: " .. TEST_DURATION .. " seconds.")

    local startTime = os.clock()
    while os.clock() - startTime < TEST_DURATION do
        if localPlayer.Character ~= character or not character.Parent then
            log("Character changed or removed; ending test early.")
            break
        end
        task.wait(0.25)
    end

    log("Playback observation window finished.")
end)

if applied then
    local restoreOk, restoreErr = pcall(restore)
    if not restoreOk then
        log("RESTORE ERROR: " .. tostring(restoreErr))
    end
end

if not ok then
    log("TEST ERROR: " .. tostring(err))
    if applied then
        pcall(restore)
    end
end

log("Local character test finished. Check whether other players can see the animations.")
log("========== END V12 ==========")

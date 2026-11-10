-- UGC AnimationConstraint Diagnostic V18
-- Isolates generated UGC clips from the game's Animate tracks and measures
-- actual body-part CFrames relative to HumanoidRootPart.
-- Restores Animate after the test. This is diagnostic only; it does not edit pack data.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:FindFirstChildOfClass("Humanoid")
local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
local animate = character:FindFirstChild("Animate")

local function log(...)
    print("[UGC V18]", ...)
end

local function safe(fn)
    local ok, value = pcall(fn)
    return ok and tostring(value) or ("<ERROR: " .. tostring(value) .. ">")
end

if not humanoid or not animator then
    log("Missing Humanoid or Animator; aborting.")
    return
end

if not animate or not animate:IsA("LocalScript") then
    log("Animate LocalScript not found; aborting to avoid an uncontrolled test.")
    return
end

local tests = {
    {Name = "UGC Idle1", Id = "rbxassetid://77943023928454", Duration = 3},
    {Name = "UGC Walk", Id = "rbxassetid://110376969855395", Duration = 3},
    {Name = "UGC Run", Id = "rbxassetid://130316627494431", Duration = 3},
}

local bodyNames = {
    Head = true,
    UpperTorso = true,
    LowerTorso = true,
    LeftUpperArm = true,
    LeftLowerArm = true,
    LeftHand = true,
    RightUpperArm = true,
    RightLowerArm = true,
    RightHand = true,
    LeftUpperLeg = true,
    LeftLowerLeg = true,
    LeftFoot = true,
    RightUpperLeg = true,
    RightLowerLeg = true,
    RightFoot = true,
}

local root = character:FindFirstChild("HumanoidRootPart")
if not root then
    log("HumanoidRootPart not found; aborting.")
    return
end

local joints = {}
for _, item in ipairs(character:GetDescendants()) do
    if item:IsA("AnimationConstraint") then
        table.insert(joints, item)
    end
end

local function snapshotJoints()
    local result = {}
    for _, joint in ipairs(joints) do
        local ok, value = pcall(function() return joint.Transform end)
        if ok then result[joint] = value end
    end
    return result
end

local function snapshotBody()
    local result = {}
    local rootCFrame = root.CFrame
    for _, item in ipairs(character:GetDescendants()) do
        if item:IsA("BasePart") and bodyNames[item.Name] then
            result[item] = rootCFrame:ToObjectSpace(item.CFrame)
        end
    end
    return result
end

local function measure(before, after)
    local changed = {}
    local maxPosition = 0
    local maxAngle = 0
    local changedCount = 0

    for instance, first in pairs(before) do
        local last = after[instance]
        if last then
            local delta = first:ToObjectSpace(last)
            local _, angle = delta:ToAxisAngle()
            local position = delta.Position.Magnitude
            angle = math.abs(angle)

            if position > maxPosition then maxPosition = position end
            if angle > maxAngle then maxAngle = angle end

            if position > 0.005 or angle > math.rad(1) then
                changedCount += 1
                table.insert(changed, instance.Name)
            end
        end
    end

    return changedCount, maxPosition, math.deg(maxAngle), table.concat(changed, ", ")
end

log("========== UGC AnimationConstraint Diagnostic V18 ==========")
log("Character:", character:GetFullName(), "RigType:", humanoid.RigType)
log("Animate:", animate:GetFullName(), "Enabled:", animate.Enabled)
log("AnimationConstraints:", #joints)
log("Body parts monitored:", 0 + (function()
    local count = 0
    for _, item in ipairs(character:GetDescendants()) do
        if item:IsA("BasePart") and bodyNames[item.Name] then count += 1 end
    end
    return count
end)())

local originalAnimateEnabled = animate.Enabled
local originalTracks = animator:GetPlayingAnimationTracks()
log("Original playing tracks:", #originalTracks)

for _, track in ipairs(originalTracks) do
    log("SAVED TRACK",
        "AnimationId:", safe(function() return track.Animation and track.Animation.AnimationId or "nil" end),
        "Priority:", safe(function() return track.Priority end),
        "TimePosition:", safe(function() return track.TimePosition end),
        "Speed:", safe(function() return track.Speed end),
        "Weight:", safe(function() return track.WeightCurrent end))
end

local createdTracks = {}
local testOk, testError = xpcall(function()
    -- Disable the game's Animate controller so it cannot immediately restart
    -- its own tracks while the UGC-only measurements are running.
    animate.Enabled = false
    task.wait(0.2)

    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        pcall(function() track:Stop(0) end)
    end
    task.wait(0.2)

    for _, test in ipairs(tests) do
        local animation = Instance.new("Animation")
        animation.AnimationId = test.Id

        local ok, trackOrError = pcall(function()
            return animator:LoadAnimation(animation)
        end)

        if not ok then
            log("LOAD ERROR", test.Name, tostring(trackOrError))
            animation:Destroy()
            continue
        end

        local track = trackOrError
        table.insert(createdTracks, track)
        track.Priority = Enum.AnimationPriority.Action4
        track.Looped = true

        local playOk, playError = pcall(function()
            track:Play(0.1, 1, 1)
        end)

        if not playOk then
            log("PLAY ERROR", test.Name, tostring(playError))
            animation:Destroy()
            continue
        end

        task.wait(0.15)
        local baselineBody = snapshotBody()
        local baselineJoints = snapshotJoints()

        local maxBodyChanged = 0
        local maxBodyPosition = 0
        local maxBodyAngle = 0
        local maxBodyNames = ""
        local maxJointChanged = 0
        local maxJointPosition = 0
        local maxJointAngle = 0
        local maxJointNames = ""
        local started = os.clock()

        log("TEST START", test.Name,
            "Length:", safe(function() return track.Length end),
            "Priority:", track.Priority,
            "Playing:", safe(function() return track.IsPlaying end))

        while os.clock() - started < test.Duration do
            RunService.Heartbeat:Wait()

            local bodyChanged, bodyPosition, bodyAngle, bodyNamesChanged =
                measure(baselineBody, snapshotBody())

            if bodyChanged > maxBodyChanged then maxBodyChanged = bodyChanged end
            if bodyPosition > maxBodyPosition then maxBodyPosition = bodyPosition end
            if bodyAngle > maxBodyAngle then maxBodyAngle = bodyAngle end
            if bodyNamesChanged ~= "" then maxBodyNames = bodyNamesChanged end

            local jointChanged, jointPosition, jointAngle, jointNamesChanged =
                measure(baselineJoints, snapshotJoints())

            if jointChanged > maxJointChanged then maxJointChanged = jointChanged end
            if jointPosition > maxJointPosition then maxJointPosition = jointPosition end
            if jointAngle > maxJointAngle then maxJointAngle = jointAngle end
            if jointNamesChanged ~= "" then maxJointNames = jointNamesChanged end
        end

        log("TEST RESULT", test.Name,
            "IsPlaying:", safe(function() return track.IsPlaying end),
            "Length:", safe(function() return track.Length end),
            "WeightCurrent:", safe(function() return track.WeightCurrent end),
            "TimePosition:", safe(function() return track.TimePosition end),
            "BODY MaxChangedParts:", maxBodyChanged .. "/" .. tostring(#bodyNames),
            "BODY MaxPositionDelta:", maxBodyPosition,
            "BODY MaxAngleDeltaDegrees:", maxBodyAngle,
            "BODY ChangedPartNames:", maxBodyNames,
            "JOINT MaxChangedJoints:", maxJointChanged .. "/" .. tostring(#joints),
            "JOINT MaxPositionDelta:", maxJointPosition,
            "JOINT MaxAngleDeltaDegrees:", maxJointAngle,
            "JOINT ChangedJointNames:", maxJointNames)

        pcall(function() track:Stop(0.1) end)
        animation:Destroy()
        task.wait(0.25)
    end
end, debug.traceback)

-- Clean up only tracks created by this diagnostic.
for _, track in ipairs(createdTracks) do
    pcall(function() track:Stop(0) end)
end

-- Re-enable the original Animate LocalScript. It should rebuild its normal
-- tracks from the character's current state.
animate.Enabled = originalAnimateEnabled
task.wait(1)

local restoredTracks = animator:GetPlayingAnimationTracks()
log("RESTORE CHECK AnimateEnabled:", animate.Enabled,
    "PlayingTracksAfterRestore:", #restoredTracks)

if #restoredTracks == 0 then
    log("WARNING: Animate has not started tracks yet; wait a moment and check whether normal animations return.")
else
    for _, track in ipairs(restoredTracks) do
        log("RESTORED TRACK",
            "AnimationId:", safe(function() return track.Animation and track.Animation.AnimationId or "nil" end),
            "Priority:", safe(function() return track.Priority end),
            "IsPlaying:", safe(function() return track.IsPlaying end))
    end
end

if not testOk then
    log("TEST SCRIPT ERROR:", tostring(testError))
end

log("========== V18 COMPLETE ==========")

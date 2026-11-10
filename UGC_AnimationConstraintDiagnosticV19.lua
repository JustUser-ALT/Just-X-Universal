-- UGC AnimationConstraint Diagnostic V19
-- Repeats the V17 UGC playback test WITHOUT disabling Animate.
-- Measures both AnimationConstraint.Transform and body-part CFrames relative to HRP.
-- Diagnostic only: stops only tracks created by this script.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:FindFirstChildOfClass("Humanoid")
local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
local animate = character:FindFirstChild("Animate")
local root = character:FindFirstChild("HumanoidRootPart")

local function log(...)
    print("[UGC V19]", ...)
end

local function safe(fn)
    local ok, value = pcall(fn)
    return ok and tostring(value) or ("<ERROR: " .. tostring(value) .. ">")
end

if not humanoid or not animator or not root then
    log("Missing Humanoid, Animator or HumanoidRootPart; aborting.")
    return
end

local tests = {
    {Name = "UGC Idle1", Id = "rbxassetid://77943023928454", Duration = 3},
    {Name = "UGC Walk", Id = "rbxassetid://110376969855395", Duration = 3},
    {Name = "UGC Run", Id = "rbxassetid://130316627494431", Duration = 3},
}

local bodyNames = {
    Head = true, UpperTorso = true, LowerTorso = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    RightUpperArm = true, RightLowerArm = true, RightHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
    RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}

local joints = {}
for _, item in ipairs(character:GetDescendants()) do
    if item:IsA("AnimationConstraint") then
        table.insert(joints, item)
    end
end

local bodyParts = {}
for _, item in ipairs(character:GetDescendants()) do
    if item:IsA("BasePart") and bodyNames[item.Name] then
        table.insert(bodyParts, item)
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
    for _, part in ipairs(bodyParts) do
        local ok, value = pcall(function()
            return rootCFrame:ToObjectSpace(part.CFrame)
        end)
        if ok then result[part] = value end
    end
    return result
end

local function measure(before, after, positionThreshold, angleThreshold)
    local changedNames = {}
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

            if position > positionThreshold or angle > angleThreshold then
                changedCount += 1
                table.insert(changedNames, instance.Name)
            end
        end
    end

    return changedCount, maxPosition, math.deg(maxAngle), table.concat(changedNames, ", ")
end

log("========== UGC AnimationConstraint Diagnostic V19 ==========")
log("Character:", character:GetFullName(), "RigType:", humanoid.RigType)
log("Animate exists:", animate ~= nil, "Enabled:", safe(function() return animate.Enabled end))
log("AnimationConstraints:", #joints, "BodyParts:", #bodyParts)
log("Animator.EvaluationThrottled:", safe(function() return animator.EvaluationThrottled end))

local originalTracks = animator:GetPlayingAnimationTracks()
log("Original playing tracks:", #originalTracks)
for _, track in ipairs(originalTracks) do
    log("BASELINE TRACK",
        "AnimationId:", safe(function() return track.Animation and track.Animation.AnimationId or "nil" end),
        "Priority:", safe(function() return track.Priority end),
        "Weight:", safe(function() return track.WeightCurrent end),
        "IsPlaying:", safe(function() return track.IsPlaying end))
end

local createdTracks = {}

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
    local baselineJoints = snapshotJoints()
    local baselineBody = snapshotBody()

    local maxJointChanged, maxJointPosition, maxJointAngle, maxJointNames = 0, 0, 0, ""
    local maxBodyChanged, maxBodyPosition, maxBodyAngle, maxBodyNames = 0, 0, 0, ""
    local started = os.clock()

    log("TEST START", test.Name,
        "Length:", safe(function() return track.Length end),
        "Priority:", track.Priority,
        "Playing:", safe(function() return track.IsPlaying end),
        "AnimateEnabled:", safe(function() return animate.Enabled end))

    while os.clock() - started < test.Duration do
        RunService.Heartbeat:Wait()

        local jc, jp, ja, jn = measure(baselineJoints, snapshotJoints(), 0.0001, math.rad(0.05))
        if jc > maxJointChanged then maxJointChanged = jc end
        if jp > maxJointPosition then maxJointPosition = jp end
        if ja > maxJointAngle then maxJointAngle = ja end
        if jn ~= "" then maxJointNames = jn end

        local bc, bp, ba, bn = measure(baselineBody, snapshotBody(), 0.005, math.rad(1))
        if bc > maxBodyChanged then maxBodyChanged = bc end
        if bp > maxBodyPosition then maxBodyPosition = bp end
        if ba > maxBodyAngle then maxBodyAngle = ba end
        if bn ~= "" then maxBodyNames = bn end
    end

    log("TEST RESULT", test.Name,
        "IsPlaying:", safe(function() return track.IsPlaying end),
        "Length:", safe(function() return track.Length end),
        "WeightCurrent:", safe(function() return track.WeightCurrent end),
        "TimePosition:", safe(function() return track.TimePosition end),
        "JOINT MaxChanged:", maxJointChanged .. "/" .. #joints,
        "JOINT MaxPosition:", maxJointPosition,
        "JOINT MaxAngleDegrees:", maxJointAngle,
        "JOINT Names:", maxJointNames,
        "BODY MaxChanged:", maxBodyChanged .. "/" .. #bodyParts,
        "BODY MaxPosition:", maxBodyPosition,
        "BODY MaxAngleDegrees:", maxBodyAngle,
        "BODY Names:", maxBodyNames)

    pcall(function() track:Stop(0.1) end)
    animation:Destroy()
    task.wait(0.25)
end

for _, track in ipairs(createdTracks) do
    pcall(function() track:Stop(0.1) end)
end

task.wait(0.5)
log("FINAL CHECK AnimateEnabled:", safe(function() return animate.Enabled end),
    "PlayingTracks:", #animator:GetPlayingAnimationTracks())
log("========== V19 COMPLETE ==========")

-- UGC AnimationConstraint Diagnostic V17
-- Measures whether Animator updates the new R15 AnimationConstraint.Transform joints.
-- Plays the known generated UGC clips locally, then stops only tracks created by this script.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:FindFirstChildOfClass("Humanoid")
local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

local function log(...)
    print("[UGC V17]", ...)
end

local function safe(fn)
    local ok, value = pcall(fn)
    return ok and tostring(value) or ("<ERROR: " .. tostring(value) .. ">")
end

if not humanoid or not animator then
    log("Missing Humanoid or Animator; aborting.")
    return
end

local joints = {}
for _, item in ipairs(character:GetDescendants()) do
    if item:IsA("AnimationConstraint") then
        table.insert(joints, item)
    end
end

log("========== UGC AnimationConstraint Diagnostic V17 ==========")
log("Character:", character:GetFullName(), "RigType:", humanoid.RigType)
log("AnimationConstraints:", #joints)
log("Animator.EvaluationThrottled:", safe(function() return animator.EvaluationThrottled end))

for _, joint in ipairs(joints) do
    log("JOINT", joint:GetFullName(),
        "Active:", safe(function() return joint.Active end),
        "Enabled:", safe(function() return joint.Enabled end),
        "IsKinematic:", safe(function() return joint.IsKinematic end),
        "Attachment0:", safe(function() return joint.Attachment0 and joint.Attachment0:GetFullName() or "nil" end),
        "Attachment1:", safe(function() return joint.Attachment1 and joint.Attachment1:GetFullName() or "nil" end),
        "Transform:", safe(function() return joint.Transform end))
end

local tests = {
    {Name = "UGC Idle1", Id = "rbxassetid://77943023928454", Duration = 3},
    {Name = "UGC Walk", Id = "rbxassetid://110376969855395", Duration = 3},
    {Name = "UGC Run", Id = "rbxassetid://130316627494431", Duration = 3},
}

local function snapshot()
    local result = {}
    for _, joint in ipairs(joints) do
        local ok, transform = pcall(function() return joint.Transform end)
        if ok then
            result[joint] = transform
        end
    end
    return result
end

local function deltaText(before, after)
    local changed = {}
    local maxPosition = 0
    local maxAngle = 0
    local changedCount = 0

    for joint, first in pairs(before) do
        local last = after[joint]
        if last then
            local delta = first:ToObjectSpace(last)
            local _, angle = delta:ToAxisAngle()
            local position = delta.Position.Magnitude
            if position > maxPosition then maxPosition = position end
            if math.abs(angle) > maxAngle then maxAngle = math.abs(angle) end
            if position > 0.0001 or math.abs(angle) > math.rad(0.05) then
                changedCount += 1
                table.insert(changed, joint.Name)
            end
        end
    end

    return changedCount, maxPosition, math.deg(maxAngle), table.concat(changed, ", ")
end

local createdTracks = {}

local function playTest(test)
    local animation = Instance.new("Animation")
    animation.AnimationId = test.Id

    local ok, trackOrError = pcall(function()
        return animator:LoadAnimation(animation)
    end)
    if not ok then
        log(test.Name, "LoadAnimation ERROR:", tostring(trackOrError))
        animation:Destroy()
        return
    end

    local track = trackOrError
    table.insert(createdTracks, track)
    track.Priority = Enum.AnimationPriority.Action4
    track.Looped = true

    local playOk, playError = pcall(function()
        track:Play(0.1, 1, 1)
    end)
    if not playOk then
        log(test.Name, "Play ERROR:", tostring(playError))
        animation:Destroy()
        return
    end

    log("TEST START", test.Name,
        "Length:", safe(function() return track.Length end),
        "Priority:", track.Priority,
        "EvaluationThrottled:", safe(function() return animator.EvaluationThrottled end))

    local baseline = snapshot()
    local maxChanged = 0
    local maxPosition = 0
    local maxAngle = 0
    local maxNames = ""
    local started = os.clock()

    while os.clock() - started < test.Duration do
        RunService.Heartbeat:Wait()
        local current = snapshot()
        local changed, position, angle, names = deltaText(baseline, current)
        if changed > maxChanged or position > maxPosition or angle > maxAngle then
            if changed > maxChanged then maxChanged = changed end
            if position > maxPosition then maxPosition = position end
            if angle > maxAngle then maxAngle = angle end
            if names ~= "" then maxNames = names end
        end
    end

    log("TEST RESULT", test.Name,
        "IsPlaying:", safe(function() return track.IsPlaying end),
        "Length:", safe(function() return track.Length end),
        "WeightCurrent:", safe(function() return track.WeightCurrent end),
        "TimePosition:", safe(function() return track.TimePosition end),
        "MaxChangedJoints:", maxChanged .. "/" .. #joints,
        "MaxPositionDelta:", maxPosition,
        "MaxAngleDeltaDegrees:", maxAngle,
        "ChangedJointNames:", maxNames)

    pcall(function() track:Stop(0.1) end)
    animation:Destroy()
    task.wait(0.25)
end

for _, test in ipairs(tests) do
    playTest(test)
end

for _, track in ipairs(createdTracks) do
    pcall(function() track:Stop(0.1) end)
end

log("========== V17 COMPLETE ==========")

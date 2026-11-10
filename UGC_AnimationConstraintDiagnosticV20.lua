-- UGC AnimationConstraint Diagnostic V20
-- Compares the standing Modern R6 idle pose against the generated R6 Think Idle1 pose.
-- Does not disable Animate, stop existing tracks, move/anchor parts, or alter the character.
-- Keep the character standing still during the test.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:FindFirstChildOfClass("Humanoid")
local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
local animate = character:FindFirstChild("Animate")
local root = character:FindFirstChild("HumanoidRootPart")

local function log(...)
    print("[UGC V20]", ...)
end

local function safe(fn)
    local ok, value = pcall(fn)
    return ok and tostring(value) or ("<ERROR: " .. tostring(value) .. ">")
end

if not humanoid or not animator or not root then
    log("Missing Humanoid, Animator or HumanoidRootPart; aborting.")
    return
end

local UGC_IDLE_ID = "rbxassetid://77943023928454"
local BASELINE_SECONDS = 3
local TEST_SECONDS = 5
local SAMPLE_INTERVAL = 0.1

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

local function getRelativeBodyPose()
    local result = {}
    local rootCFrame = root.CFrame
    for _, part in ipairs(bodyParts) do
        local ok, value = pcall(function()
            return rootCFrame:ToObjectSpace(part.CFrame)
        end)
        if ok then
            result[part.Name] = value
        end
    end
    return result
end

local function getJointPose()
    local result = {}
    for _, joint in ipairs(joints) do
        local ok, value = pcall(function()
            return joint.Transform
        end)
        if ok then
            result[joint.Name] = value
        end
    end
    return result
end

local function getTrackSummary()
    local result = {}
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        table.insert(result, {
            Id = safe(function()
                return track.Animation and track.Animation.AnimationId or "nil"
            end),
            Priority = safe(function() return track.Priority end),
            Weight = safe(function() return track.WeightCurrent end),
            Time = safe(function() return track.TimePosition end),
            Playing = safe(function() return track.IsPlaying end),
        })
    end
    return result
end

local function poseDelta(reference, current)
    local rows = {}
    local maxPosition = 0
    local maxAngle = 0
    local changed = 0

    for name, first in pairs(reference) do
        local last = current[name]
        if last then
            local delta = first:ToObjectSpace(last)
            local _, angle = delta:ToAxisAngle()
            local position = delta.Position.Magnitude
            angle = math.deg(math.abs(angle))

            if position > maxPosition then maxPosition = position end
            if angle > maxAngle then maxAngle = angle end

            if position > 0.015 or angle > 2 then
                changed += 1
                table.insert(rows, string.format("%s(pos=%.4f, angle=%.2f)", name, position, angle))
            end
        end
    end

    table.sort(rows)
    return changed, maxPosition, maxAngle, table.concat(rows, "; ")
end

local function averagePose(samples, key)
    local sums = {}
    local counts = {}

    for _, sample in ipairs(samples) do
        local pose = sample[key]
        for name, cf in pairs(pose) do
            local entry = sums[name]
            if not entry then
                entry = {x = 0, y = 0, z = 0}
                sums[name] = entry
                counts[name] = 0
            end
            local p = cf.Position
            entry.x += p.X
            entry.y += p.Y
            entry.z += p.Z
            counts[name] += 1
        end
    end

    local result = {}
    for name, entry in pairs(sums) do
        local count = counts[name]
        result[name] = Vector3.new(entry.x / count, entry.y / count, entry.z / count)
    end
    return result
end

local function compareAveragePositions(first, second)
    local rows = {}
    local maxDistance = 0
    local changed = 0

    for name, a in pairs(first) do
        local b = second[name]
        if b then
            local distance = (a - b).Magnitude
            if distance > maxDistance then maxDistance = distance end
            if distance > 0.015 then
                changed += 1
                table.insert(rows, string.format("%s=%.4f", name, distance))
            end
        end
    end

    table.sort(rows)
    return changed, maxDistance, table.concat(rows, ", ")
end

local function sampleWindow(label, duration)
    local bodySamples = {}
    local jointSamples = {}
    local startTime = os.clock()
    local nextSample = startTime

    while os.clock() - startTime < duration do
        RunService.Heartbeat:Wait()
        if os.clock() >= nextSample then
            table.insert(bodySamples, {Pose = getRelativeBodyPose()})
            table.insert(jointSamples, {Pose = getJointPose()})
            nextSample += SAMPLE_INTERVAL
        end
    end

    local bodyPosition = averagePose(bodySamples, "Pose")
    local jointPosition = averagePose(jointSamples, "Pose")

    log(label, "Samples:", #bodySamples, "BodyParts:", #bodyPosition, "Joints:", #jointPosition)
    return bodyPosition, jointPosition
end

log("========== UGC AnimationConstraint Diagnostic V20 ==========")
log("Character:", character:GetFullName(), "RigType:", humanoid.RigType)
log("Animate:", animate ~= nil, "Enabled:", safe(function() return animate.Enabled end))
log("Constraints:", #joints, "BodyParts:", #bodyParts)
log("Instruction: stand still and do not move camera controls/character during the test.")
log("Baseline tracks:")
for _, item in ipairs(getTrackSummary()) do
    log("TRACK", item.Id, item.Priority, "Weight:", item.Weight, "Time:", item.Time, "Playing:", item.Playing)
end

log("BASELINE START: collecting current equipped Modern R6 idle pose for", BASELINE_SECONDS, "seconds.")
local baselineBody, baselineJoints = sampleWindow("BASELINE", BASELINE_SECONDS)

local animation = Instance.new("Animation")
animation.AnimationId = UGC_IDLE_ID

local loadOk, trackOrError = pcall(function()
    return animator:LoadAnimation(animation)
end)

if not loadOk then
    log("LOAD ERROR:", tostring(trackOrError))
    animation:Destroy()
    return
end

local ugcTrack = trackOrError
ugcTrack.Priority = Enum.AnimationPriority.Action4
ugcTrack.Looped = true

local playOk, playError = pcall(function()
    ugcTrack:Play(0.15, 1, 1)
end)

if not playOk then
    log("PLAY ERROR:", tostring(playError))
    animation:Destroy()
    return
end

task.wait(0.5)
log("UGC START: R6 Think Idle1",
    "Length:", safe(function() return ugcTrack.Length end),
    "Weight:", safe(function() return ugcTrack.WeightCurrent end),
    "AnimateEnabled:", safe(function() return animate.Enabled end))

local ugcBody, ugcJoints = sampleWindow("UGC THINK", TEST_SECONDS)

local bodyChanged, bodyMax, bodyNamesChanged = compareAveragePositions(baselineBody, ugcBody)
local jointChanged, jointMax, jointNamesChanged = compareAveragePositions(baselineJoints, ugcJoints)

log("========== AVERAGE POSE COMPARISON ==========")
log("BODY POSITION DELTA:", bodyChanged .. "/" .. #bodyParts,
    "MaxDistance:", bodyMax,
    "ChangedParts:", bodyNamesChanged)
log("JOINT TRANSFORM POSITION DELTA:", jointChanged .. "/" .. #joints,
    "MaxDistance:", jointMax,
    "ChangedJoints:", jointNamesChanged)

log("UGC TRACK FINAL:",
    "Playing:", safe(function() return ugcTrack.IsPlaying end),
    "Length:", safe(function() return ugcTrack.Length end),
    "Weight:", safe(function() return ugcTrack.WeightCurrent end),
    "TimePosition:", safe(function() return ugcTrack.TimePosition end))

log("Tracks during UGC:")
for _, item in ipairs(getTrackSummary()) do
    log("TRACK", item.Id, item.Priority, "Weight:", item.Weight, "Time:", item.Time, "Playing:", item.Playing)
end

pcall(function() ugcTrack:Stop(0.15) end)
animation:Destroy()

task.wait(0.5)
log("RESTORE CHECK AnimateEnabled:", safe(function() return animate.Enabled end))
log("RESTORE TRACKS:")
for _, item in ipairs(getTrackSummary()) do
    log("TRACK", item.Id, item.Priority, "Weight:", item.Weight, "Time:", item.Time, "Playing:", item.Playing)
end

log("========== V20 COMPLETE ==========")

-- UGC AnimationConstraint Diagnostic V21 FIXED
-- PATCH: removed malformed nested count expression; collect() uses explicit counters.
-- Compares baseline Modern R6 idle against R6 Think Idle1 using both position AND rotation.
-- Does not disable Animate, stop existing tracks, or modify the character.
-- Keep the character standing still throughout the test.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:FindFirstChildOfClass("Humanoid")
local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
local animate = character:FindFirstChild("Animate")
local root = character:FindFirstChild("HumanoidRootPart")

local function log(...)
    print("[UGC V21]", ...)
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
local SAMPLE_INTERVAL = 0.1
local BASELINE_SECONDS = 3
local UGC_SECONDS = 5

local bodyNames = {
    Head = true, UpperTorso = true, LowerTorso = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    RightUpperArm = true, RightLowerArm = true, RightHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
    RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}

local bodyParts = {}
local joints = {}
for _, item in ipairs(character:GetDescendants()) do
    if item:IsA("BasePart") and bodyNames[item.Name] then
        table.insert(bodyParts, item)
    elseif item:IsA("AnimationConstraint") then
        table.insert(joints, item)
    end
end

local function snapshotBody()
    local result = {}
    local rootCFrame = root.CFrame
    for _, part in ipairs(bodyParts) do
        local ok, cf = pcall(function()
            return rootCFrame:ToObjectSpace(part.CFrame)
        end)
        if ok then result[part.Name] = cf end
    end
    return result
end

local function snapshotJoints()
    local result = {}
    for _, joint in ipairs(joints) do
        local ok, cf = pcall(function() return joint.Transform end)
        if ok then result[joint.Name] = cf end
    end
    return result
end

local function collect(label, duration)
    local samples = {}
    local started = os.clock()
    local nextSample = started

    while os.clock() - started < duration do
        RunService.Heartbeat:Wait()
        if os.clock() >= nextSample then
            table.insert(samples, {
                Body = snapshotBody(),
                Joints = snapshotJoints(),
            })
            nextSample += SAMPLE_INTERVAL
        end
    end

    local bodySampleCount = 0
    local jointSampleCount = 0
    for _, sample in ipairs(samples) do
        if next(sample.Body) then
            bodySampleCount += 1
        end
        if next(sample.Joints) then
            jointSampleCount += 1
        end
    end

    log(label, "Samples:", #samples,
        "Body samples with data:", bodySampleCount,
        "Joint samples with data:", jointSampleCount
    )
    return samples
end

local function delta(a, b)
    local relative = a:ToObjectSpace(b)
    local _, angle = relative:ToAxisAngle()
    return relative.Position.Magnitude, math.deg(math.abs(angle))
end

local function compareSets(baseline, test, field, label)
    local names = {}
    for _, sample in ipairs(baseline) do
        for name in pairs(sample[field]) do names[name] = true end
    end

    local rows = {}
    local changed = 0
    local valid = 0
    local overallMaxPosition = 0
    local overallMaxAngle = 0

    for name in pairs(names) do
        local totalNearestPosition = 0
        local totalNearestAngle = 0
        local maxNearestPosition = 0
        local maxNearestAngle = 0
        local sampleCount = 0

        -- For every UGC sample, find the closest baseline idle sample.
        -- Then average those nearest differences, so one matching animation
        -- frame cannot hide the rest of the UGC pose.
        for _, testSample in ipairs(test) do
            local testCf = testSample[field][name]
            if testCf then
                local nearestPosition = math.huge
                local nearestAngle = math.huge
                local nearestScore = math.huge

                for _, baseSample in ipairs(baseline) do
                    local baseCf = baseSample[field][name]
                    if baseCf then
                        local position, angle = delta(baseCf, testCf)
                        local score = position + angle / 180
                        if score < nearestScore then
                            nearestScore = score
                            nearestPosition = position
                            nearestAngle = angle
                        end
                    end
                end

                if nearestScore < math.huge then
                    sampleCount += 1
                    totalNearestPosition += nearestPosition
                    totalNearestAngle += nearestAngle
                    if nearestPosition > maxNearestPosition then maxNearestPosition = nearestPosition end
                    if nearestAngle > maxNearestAngle then maxNearestAngle = nearestAngle end
                end
            end
        end

        if sampleCount > 0 then
            valid += 1
            local averagePosition = totalNearestPosition / sampleCount
            local averageAngle = totalNearestAngle / sampleCount
            if maxNearestPosition > overallMaxPosition then overallMaxPosition = maxNearestPosition end
            if maxNearestAngle > overallMaxAngle then overallMaxAngle = maxNearestAngle end

            if averagePosition > 0.015 or averageAngle > 2 then
                changed += 1
                table.insert(rows, string.format(
                    "%s(avgPos=%.4f, avgRot=%.2fdeg, maxRot=%.2fdeg)",
                    name, averagePosition, averageAngle, maxNearestAngle
                ))
            end
        end
    end

    table.sort(rows)
    log(label, "Changed:", changed .. "/" .. valid,
        "MaxNearestPosition:", overallMaxPosition,
        "MaxNearestRotationDegrees:", overallMaxAngle,
        "Details:", table.concat(rows, "; "))
end

log("========== UGC AnimationConstraint Diagnostic V21 ==========")
log("Character:", character:GetFullName(), "RigType:", humanoid.RigType)
log("AnimateEnabled:", safe(function() return animate.Enabled end),
    "AnimationConstraints:", #joints, "BodyParts:", #bodyParts)
log("Stand still. Baseline Modern R6 idle will be sampled first.")

local baseline = collect("MODERN IDLE BASELINE", BASELINE_SECONDS)

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

local track = trackOrError
track.Priority = Enum.AnimationPriority.Action4
track.Looped = true

local playOk, playError = pcall(function()
    track:Play(0.15, 1, 1)
end)
if not playOk then
    log("PLAY ERROR:", tostring(playError))
    animation:Destroy()
    return
end

task.wait(0.5)
log("R6 THINK IDLE START",
    "Length:", safe(function() return track.Length end),
    "Weight:", safe(function() return track.WeightCurrent end),
    "Playing:", safe(function() return track.IsPlaying end),
    "AnimateEnabled:", safe(function() return animate.Enabled end))

local ugc = collect("R6 THINK IDLE", UGC_SECONDS)

log("========== BASELINE VS THINK: POSITION + ROTATION ==========")
compareSets(baseline, ugc, "Body", "BODY CFRAME")
compareSets(baseline, ugc, "Joints", "ANIMATIONCONSTRAINT TRANSFORM")

log("Track final:", "Playing:", safe(function() return track.IsPlaying end),
    "Weight:", safe(function() return track.WeightCurrent end),
    "TimePosition:", safe(function() return track.TimePosition end))

pcall(function() track:Stop(0.15) end)
animation:Destroy()
task.wait(0.5)

log("Restore check AnimateEnabled:", safe(function() return animate.Enabled end))
log("========== V21 COMPLETE ==========")

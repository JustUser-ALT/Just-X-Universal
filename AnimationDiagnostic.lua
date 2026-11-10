-- Just X Universal - Animation Diagnostic
-- Run this while the character is spawned and the animation issue is present.
-- This test does not change Animate.AnimationId values or apply an animation pack.
-- It reports the current Animate IDs and Animator tracks, stops existing tracks,
-- then reports whether Animate starts creating tracks again.

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local PREFIX = "[Animation Diagnostic]"

local function log(...)
    print(PREFIX, ...)
end

local function getAnimationId(track)
    local animation = track and track.Animation
    return animation and animation.AnimationId or "<no Animation object>"
end

local function inspectTracks(animator, stage)
    local ok, tracks = pcall(function()
        return animator:GetPlayingAnimationTracks()
    end)

    if not ok then
        warn(PREFIX, stage .. ": GetPlayingAnimationTracks failed:", tracks)
        return nil
    end

    log(stage .. ": playing tracks =", #tracks)
    for index, track in ipairs(tracks) do
        local animationId = getAnimationId(track)
        local name = track.Name
        local priority = tostring(track.Priority)
        log(string.format("TRACK %02d | Name=%s | Priority=%s | ID=%s | Playing=%s | Weight=%.2f",
            index,
            tostring(name),
            priority,
            tostring(animationId),
            tostring(track.IsPlaying),
            tonumber(track.WeightCurrent) or 0
        ))
    end

    return tracks
end

local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
if not humanoid then
    warn(PREFIX, "Humanoid not found")
    return
end

local animate = character:FindFirstChild("Animate") or character:WaitForChild("Animate", 10)
if not animate then
    warn(PREFIX, "Animate not found")
    return
end

local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
    warn(PREFIX, "Animator not found under Humanoid")
    return
end

log("========== CHARACTER ==========")
log("Character =", character:GetFullName())
log("RigType =", tostring(humanoid.RigType))
log("Animate class =", animate.ClassName)
log("Animate disabled =", tostring(animate:IsA("LocalScript") and animate.Disabled or "N/A"))
log("Animator =", animator:GetFullName())

log("========== ANIMATE IDS ==========")
local animationCount = 0
for _, object in ipairs(animate:GetDescendants()) do
    if object:IsA("Animation") then
        animationCount += 1
        log(string.format("ANIMATE %02d | %s | %s",
            animationCount,
            object:GetFullName(),
            object.AnimationId
        ))
    end
end
log("Total Animation objects =", animationCount)

log("========== TRACKS BEFORE CLEANUP ==========")
local beforeTracks = inspectTracks(animator, "BEFORE")

log("========== STOPPING TRACKS ==========")
local stopped = 0
if beforeTracks then
    for _, track in ipairs(beforeTracks) do
        local okStop, err = pcall(function()
            track:Stop(0.1)
        end)
        if okStop then
            stopped += 1
        else
            warn(PREFIX, "Could not stop track:", err)
        end
    end
end
log("Stop calls succeeded =", stopped)

task.wait(0.5)

log("========== TRACKS AFTER CLEANUP ==========")
inspectTracks(animator, "AFTER 0.5s")

log("========== END ==========")
log("Send the complete output beginning with [Animation Diagnostic].")

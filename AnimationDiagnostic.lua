-- Just X Universal - Animation Diagnostic
-- Reports Animate IDs and Animator tracks, then tests a clean Animate restart.
-- This does not change any Animation.AnimationId values or apply an animation pack.

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PREFIX = "[Animation Diagnostic]"

local function log(...)
    print(PREFIX, ...)
end

local function getTracks(animator, label)
    local ok, tracks = pcall(function()
        return animator:GetPlayingAnimationTracks()
    end)
    if not ok then
        warn(PREFIX, label .. ": GetPlayingAnimationTracks failed:", tracks)
        return nil
    end

    local playing = 0
    log(label .. ": returned tracks =", #tracks)
    for index, track in ipairs(tracks) do
        if track.IsPlaying then playing += 1 end
        local animation = track.Animation
        log(string.format(
            "%s TRACK %02d | Name=%s | ID=%s | Playing=%s | Weight=%.2f | Length=%.2f",
            label,
            index,
            tostring(track.Name),
            animation and animation.AnimationId or "<none>",
            tostring(track.IsPlaying),
            tonumber(track.WeightCurrent) or 0,
            tonumber(track.Length) or 0
        ))
    end
    log(label .. ": IsPlaying count =", playing)
    return tracks
end

local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
if not humanoid then warn(PREFIX, "Humanoid not found"); return end

local animate = character:FindFirstChild("Animate") or character:WaitForChild("Animate", 10)
if not animate then warn(PREFIX, "Animate not found"); return end

local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then warn(PREFIX, "Animator not found"); return end
if not animate:IsA("LocalScript") then
    warn(PREFIX, "Animate is not a LocalScript; aborting restart test")
    return
end

log("========== CHARACTER ==========")
log("Character =", character:GetFullName())
log("RigType =", tostring(humanoid.RigType))
log("Animate class =", animate.ClassName)
log("Animate disabled =", tostring(animate.Disabled))
log("Animator =", animator:GetFullName())

log("========== ANIMATE IDS ==========")
local count = 0
for _, object in ipairs(animate:GetDescendants()) do
    if object:IsA("Animation") then
        count += 1
        log(string.format("ANIMATE %02d | %s | %s", count, object:GetFullName(), object.AnimationId))
    end
end
log("Total Animation objects =", count)

log("========== TRACKS BEFORE CLEANUP ==========")
local tracks = getTracks(animator, "BEFORE")

log("========== CLEANUP TEST ==========")
local wasDisabled = animate.Disabled
animate.Disabled = true
task.wait(0.2)

local destroyed = 0
local destroyFailed = 0
if tracks then
    for _, track in ipairs(tracks) do
        pcall(function() track:Stop(0) end)
        local okDestroy, err = pcall(function() track:Destroy() end)
        if okDestroy then
            destroyed += 1
        else
            destroyFailed += 1
            warn(PREFIX, "Track Destroy failed:", err)
        end
    end
end

log("Tracks destroyed =", destroyed)
log("Destroy failures =", destroyFailed)
task.wait(0.2)

if animate.Parent then
    animate.Disabled = wasDisabled
end

task.wait(1.5)
log("========== TRACKS AFTER CLEAN RESTART ==========")
getTracks(animator, "AFTER RESTART")

log("Animate disabled after test =", tostring(animate.Parent and animate.Disabled))
log("========== END ==========")
log("Send the complete output beginning with [Animation Diagnostic].")

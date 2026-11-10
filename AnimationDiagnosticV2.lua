-- Just X Universal - Animation Diagnostic V2
-- Fresh-path cache bypass. Does not apply or modify animation IDs.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local P = "[Animation Diagnostic V2]"
local function log(...) print(P, ...) end

local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
local animate = character:FindFirstChild("Animate") or character:WaitForChild("Animate", 10)
if not humanoid or not animate then warn(P, "Humanoid or Animate missing"); return end
local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then warn(P, "Animator missing"); return end
if not animate:IsA("LocalScript") then warn(P, "Animate is not LocalScript; aborting"); return end

log("VERSION = V2 / NEW FILE PATH")
log("Character =", character:GetFullName())
log("RigType =", tostring(humanoid.RigType))
log("Animate.Disabled BEFORE =", tostring(animate.Disabled))
local ids = 0
for _, obj in ipairs(animate:GetDescendants()) do
    if obj:IsA("Animation") then
        ids += 1
        log(string.format("ANIMATION %02d | %s | %s", ids, obj:GetFullName(), obj.AnimationId))
    end
end
log("Animation objects =", ids)

local function report(label)
    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if not ok then warn(P, label, "GetPlayingAnimationTracks failed", tracks); return {} end
    local playing = 0
    log(label, "returned tracks =", #tracks)
    for i, track in ipairs(tracks) do
        if track.IsPlaying then playing += 1 end
        local anim = track.Animation
        log(string.format("%s %02d | %s | %s | Playing=%s | Weight=%.2f", label, i, tostring(track.Name), anim and anim.AnimationId or "<none>", tostring(track.IsPlaying), tonumber(track.WeightCurrent) or 0))
    end
    log(label, "actually playing =", playing)
    return tracks
end

log("========== BEFORE ==========")
local tracks = report("BEFORE")
local wasDisabled = animate.Disabled
animate.Disabled = true
task.wait(0.25)
local destroyed, failed = 0, 0
for _, track in ipairs(tracks) do
    pcall(function() track:Stop(0) end)
    local ok = pcall(function() track:Destroy() end)
    if ok then destroyed += 1 else failed += 1 end
end
log("Tracks Destroy attempted =", #tracks)
log("Tracks Destroy succeeded =", destroyed)
log("Tracks Destroy failed =", failed)
task.wait(0.25)
if animate.Parent then animate.Disabled = wasDisabled end
task.wait(1.5)
log("========== AFTER RESTART ==========")
report("AFTER")
log("Animate.Disabled AFTER =", tostring(animate.Parent and animate.Disabled))
log("========== END V2 ==========")

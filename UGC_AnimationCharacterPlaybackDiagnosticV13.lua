-- UGC Animation Character Playback Diagnostic V13
-- Directly tests R6 Think Idle, Walk and Run on the existing local character Animator.
-- Bypasses Animate completely. Does not change AnimationIds in Animate.
-- Stops and destroys only tracks created by this diagnostic.

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local TESTS = {
    {Name = "Idle1", Id = "rbxassetid://77943023928454", Duration = 5},
    {Name = "Walk", Id = "rbxassetid://110376969855395", Duration = 5},
    {Name = "Run", Id = "rbxassetid://130316627494431", Duration = 5},
}

local function log(message)
    print("[UGC V13] " .. tostring(message))
end

local character = localPlayer.Character
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

if not character or not humanoid or not animator then
    log("ERROR: Character, Humanoid or existing Animator missing. No changes made.")
    return
end

if animator.Parent ~= humanoid then
    log("ERROR: Animator is not parented to this Humanoid. No changes made.")
    return
end

local createdTracks = {}
local createdAnimations = {}

local function cleanup()
    for _, track in ipairs(createdTracks) do
        pcall(function()
            track:Stop(0.15)
            track:Destroy()
        end)
    end

    for _, animation in ipairs(createdAnimations) do
        pcall(function()
            animation:Destroy()
        end)
    end
end

log("========== UGC Animation Character Playback V13 ==========")
log("Character: " .. character:GetFullName())
log("RigType: " .. tostring(humanoid.RigType))
log("Animator: " .. animator:GetFullName())
log("This test directly plays tracks; Animate IDs are untouched.")

local success, err = pcall(function()
    for _, test in ipairs(TESTS) do
        if localPlayer.Character ~= character or not character.Parent then
            log("Character changed; stopping test.")
            break
        end

        log("----- " .. test.Name .. " -----")
        log("Loading: " .. test.Id)

        local animation = Instance.new("Animation")
        animation.Name = "UGC_V13_" .. test.Name
        animation.AnimationId = test.Id
        animation.Parent = character
        createdAnimations[#createdAnimations + 1] = animation

        local track = animator:LoadAnimation(animation)
        createdTracks[#createdTracks + 1] = track
        track.Priority = Enum.AnimationPriority.Action
        track.Looped = true
        track:Play(0.15)

        local elapsed = 0
        while elapsed < 4 do
            if localPlayer.Character ~= character or not character.Parent then
                break
            end
            task.wait(0.25)
            elapsed += 0.25
        end

        log(string.format(
            "%s: IsPlaying=%s | Length=%.4f | TimePosition=%.4f | WeightCurrent=%.3f | WeightTarget=%.3f",
            test.Name,
            tostring(track.IsPlaying),
            track.Length,
            track.TimePosition,
            track.WeightCurrent,
            track.WeightTarget
        ))

        task.wait(0.75)
        track:Stop(0.15)
        task.wait(0.2)
    end
end)

cleanup()

if success then
    log("RESULT: Direct playback test completed. Test tracks removed.")
else
    log("RESULT: TEST ERROR: " .. tostring(err))
    log("Cleanup attempted.")
end

log("Animate AnimationIds were not modified.")
log("========== END V13 ==========")

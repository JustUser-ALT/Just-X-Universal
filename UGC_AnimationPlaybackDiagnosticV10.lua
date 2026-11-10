-- UGC Animation Playback Diagnostic V10
-- Builds a temporary R15 dummy from the R6 Think animation description,
-- extracts Roblox-resolved AnimationIds, and plays Walk/Run locally on that dummy.
-- Does NOT modify LocalPlayer.Character. The temporary dummy is removed at the end.

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local BUNDLE = {
    IdleAnimation = 137273817835971,
    WalkAnimation = 93952528577974,
    RunAnimation = 70841708593861,
    JumpAnimation = 79534551779955,
    FallAnimation = 93811344606236,
    ClimbAnimation = 114158755065309,
    SwimAnimation = 99559196758012,
}

local function log(message)
    print("[UGC V10] " .. tostring(message))
end

local function findAnimation(animate, folderName, animationName)
    local folder = animate and animate:FindFirstChild(folderName)
    if not folder then
        return nil
    end
    local named = folder:FindFirstChild(animationName)
    if named and named:IsA("Animation") then
        return named
    end
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Animation") then
            return child
        end
    end
    return nil
end

local dummy
local tracks = {}

local ok, err = pcall(function()
    log("========== UGC Animation Playback Diagnostic V10 ==========")
    log("PlaceId: " .. tostring(game.PlaceId))
    log("Creating temporary R15 dummy using R6 Think bundle IDs.")

    local description = Instance.new("HumanoidDescription")
    for property, assetId in pairs(BUNDLE) do
        description[property] = assetId
    end

    dummy = Players:CreateHumanoidModelFromDescription(
        description,
        Enum.HumanoidRigType.R15
    )
    description:Destroy()

    assert(dummy, "CreateHumanoidModelFromDescription returned nil")

    dummy.Name = "UGC_V10_TestDummy"
    local character = localPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local dummyRoot = dummy:FindFirstChild("HumanoidRootPart")

    if root and dummyRoot then
        dummy:PivotTo(root.CFrame * CFrame.new(5, 0, 0))
    end

    local humanoid = dummy:FindFirstChildOfClass("Humanoid")
    assert(humanoid, "Dummy Humanoid not found")

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    local animate = dummy:FindFirstChild("Animate")
    assert(animate, "Dummy Animate script not found")

    local tests = {
        {Name = "Walk", Folder = "walk", Object = "WalkAnim"},
        {Name = "Run", Folder = "run", Object = "RunAnim"},
    }

    for _, test in ipairs(tests) do
        local source = findAnimation(animate, test.Folder, test.Object)
        assert(source, test.Name .. " Animation object not found")

        local animation = Instance.new("Animation")
        animation.Name = "V10_" .. test.Name
        animation.AnimationId = source.AnimationId

        log(test.Name .. " resolved AnimationId: " .. source.AnimationId)

        local track = animator:LoadAnimation(animation)
        tracks[#tracks + 1] = track
        track.Priority = Enum.AnimationPriority.Movement
        track.Looped = true
        track:Play(0.15)

        task.wait(2)

        log(string.format(
            "%s playback: IsPlaying=%s | Length=%.4f | TimePosition=%.4f | Weight=%.2f",
            test.Name,
            tostring(track.IsPlaying),
            track.Length,
            track.TimePosition,
            track.WeightCurrent
        ))

        track:Stop(0.15)
        task.wait(0.25)
        animation:Destroy()
    end

    log("Walk and Run playback test finished.")
end)

for _, track in ipairs(tracks) do
    pcall(function()
        track:Stop(0)
        track:Destroy()
    end)
end

if dummy then
    pcall(function()
        dummy:Destroy()
    end)
end

if ok then
    log("RESULT: Test completed. Temporary dummy removed.")
else
    log("RESULT: TEST ERROR: " .. tostring(err))
    log("Temporary dummy cleanup attempted.")
end

log("LocalPlayer.Character was not modified.")
log("========== END V10 ==========")

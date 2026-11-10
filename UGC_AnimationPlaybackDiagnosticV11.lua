-- UGC Animation Playback Diagnostic V11
-- Repeats V10 with the temporary dummy parented to Workspace before loading tracks.
-- Waits for each track to receive a non-zero Length before evaluating playback.
-- Does NOT modify LocalPlayer.Character.

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
    print("[UGC V11] " .. tostring(message))
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
local animationObjects = {}

local ok, err = pcall(function()
    log("========== UGC Animation Playback Diagnostic V11 ==========")
    log("PlaceId: " .. tostring(game.PlaceId))
    log("Creating temporary R15 dummy from R6 Think IDs.")

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

    dummy.Name = "UGC_V11_TestDummy"

    local character = localPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root then
        dummy:PivotTo(root.CFrame * CFrame.new(5, 0, 0))
    end

    for _, descendant in ipairs(dummy:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.CanCollide = false
            descendant.Anchored = descendant.Name == "HumanoidRootPart"
        end
    end

    -- Animator loading is tested only after the model is in Workspace.
    dummy.Parent = workspace
    task.wait(0.25)

    local humanoid = dummy:FindFirstChildOfClass("Humanoid")
    assert(humanoid, "Dummy Humanoid not found")

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    log("Dummy parent: " .. dummy.Parent:GetFullName())
    log("Animator parent: " .. animator.Parent:GetFullName())

    local animate = dummy:FindFirstChild("Animate")
    assert(animate, "Dummy Animate script not found")

    local tests = {
        {Name = "Walk", Folder = "walk", Object = "WalkAnim"},
        {Name = "Run", Folder = "run", Object = "RunAnim"},
    }

    for _, test in ipairs(tests) do
        log("----- " .. test.Name .. " -----")

        local source = findAnimation(animate, test.Folder, test.Object)
        assert(source, test.Name .. " Animation object not found")

        local animation = Instance.new("Animation")
        animation.Name = "V11_" .. test.Name
        animation.AnimationId = source.AnimationId
        animation.Parent = dummy
        animationObjects[#animationObjects + 1] = animation

        log("Resolved AnimationId: " .. animation.AnimationId)

        local track = animator:LoadAnimation(animation)
        tracks[#tracks + 1] = track
        track.Priority = Enum.AnimationPriority.Action
        track.Looped = true
        track:Play(0.1)

        local elapsed = 0
        while elapsed < 8 and track.Length <= 0 do
            task.wait(0.25)
            elapsed += 0.25
        end

        task.wait(0.5)

        log(string.format(
            "%s result: IsPlaying=%s | Length=%.4f | TimePosition=%.4f | WeightCurrent=%.3f | WeightTarget=%.3f | Waited=%.2fs",
            test.Name,
            tostring(track.IsPlaying),
            track.Length,
            track.TimePosition,
            track.WeightCurrent,
            track.WeightTarget,
            elapsed
        ))

        track:Stop(0.15)
        task.wait(0.25)
    end

    log("Walk and Run tests finished.")
end)

for _, track in ipairs(tracks) do
    pcall(function()
        track:Stop(0)
        track:Destroy()
    end)
end

for _, animation in ipairs(animationObjects) do
    pcall(function()
        animation:Destroy()
    end)
end

if dummy then
    pcall(function()
        dummy:Destroy()
    end)
end

if ok then
    log("RESULT: Test completed. Temporary Workspace dummy removed.")
else
    log("RESULT: TEST ERROR: " .. tostring(err))
    log("Temporary dummy cleanup attempted.")
end

log("LocalPlayer.Character was not modified.")
log("========== END V11 ==========")

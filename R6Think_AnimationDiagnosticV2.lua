-- Just X Universal - UGC Animation Diagnostic V2
-- Compares R6 Think UGC animation assets with a known working catalog animation.
-- Does not modify Animate.AnimationId or apply any animation pack.

local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local player = Players.LocalPlayer
local PREFIX = "[UGC Animation Diagnostic V2]"

local function log(...)
    print(PREFIX, ...)
end

local tests = {
    {Name = "Cartoony Idle (known catalog control)", Id = 742637544, Slot = "idle"},
    {Name = "R6 Think Idle", Id = 137273817835971, Slot = "idle"},
    {Name = "R6 Think Walk", Id = 93952528577974, Slot = "walk"},
    {Name = "R6 Think Run", Id = 70841708593861, Slot = "run"},
    {Name = "R6 Think Jump", Id = 79534551779955, Slot = "jump"},
    {Name = "R6 Think Fall", Id = 93811344606236, Slot = "fall"},
    {Name = "R6 Think Climb", Id = 114158755065309, Slot = "climb"},
    {Name = "R6 Think Swim", Id = 99559196758012, Slot = "swim"}
}

local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
local animate = character:FindFirstChild("Animate")
local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

log("========== ENVIRONMENT ==========")
log("PlaceId =", game.PlaceId)
log("GameId =", game.GameId)
log("Character =", character:GetFullName())
log("RigType =", humanoid and tostring(humanoid.RigType) or "<no humanoid>")
log("Animate exists =", tostring(animate ~= nil))
log("Animator exists =", tostring(animator ~= nil))

if humanoid then
    local okDescription, description = pcall(function()
        return humanoid:GetAppliedDescription()
    end)
    if okDescription and description then
        log("========== APPLIED HUMANOID DESCRIPTION ==========")
        for _, property in ipairs({
            "IdleAnimation", "WalkAnimation", "RunAnimation",
            "JumpAnimation", "FallAnimation", "ClimbAnimation",
            "SwimAnimation"
        }) do
            local okValue, value = pcall(function()
                return description[property]
            end)
            log("DESCRIPTION", property, "=", okValue and tostring(value) or ("<read failed: " .. tostring(value) .. ">"))
        end
    else
        log("GetAppliedDescription unavailable/failed =", tostring(description))
    end
end

if animate then
    log("========== CURRENT ANIMATE IDS ==========")
    for _, object in ipairs(animate:GetDescendants()) do
        if object:IsA("Animation") then
            log(object:GetFullName(), "=", object.AnimationId)
        end
    end
end

log("========== ASSET FETCH COMPARISON ==========")
for _, test in ipairs(tests) do
    local animation = Instance.new("Animation")
    animation.Name = "JX_UGC_Diagnostic"
    animation.AnimationId = "rbxassetid://" .. tostring(test.Id)

    local callbackStatus = "callback not received"
    local ok, err = pcall(function()
        ContentProvider:PreloadAsync({animation}, function(contentId, status)
            callbackStatus = tostring(status)
            log("CALLBACK", test.Name, "|", contentId, "|", callbackStatus)
        end)
    end)

    log("RESULT", test.Name, "| ID=" .. tostring(test.Id),
        "| PreloadCall=" .. tostring(ok),
        "| Status=" .. callbackStatus,
        "| Error=" .. (ok and "<none>" or tostring(err)))

    animation:Destroy()
    task.wait(0.3)
end

log("========== END V2 ==========")
log("Send the complete output beginning with [UGC Animation Diagnostic V2].")

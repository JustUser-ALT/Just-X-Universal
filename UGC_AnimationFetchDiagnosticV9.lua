-- UGC Animation Fetch Diagnostic V9
-- Same tests as V8, but passes ContentId as an explicit rbxassetid:// string.
-- Does not modify LocalPlayer.Character.

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer
local provider = game:GetService("AnimationClipProvider")

local TESTS = {
    {Name = "Idle1", Source = "R6 Think Idle", Id = 77943023928454},
    {Name = "Idle2", Source = "R6 Think Idle", Id = 71374122142959},
    {Name = "Walk", Source = "R6 Think Walk", Id = 110376969855395},
    {Name = "Run", Source = "R6 Think Run", Id = 130316627494431},
    {Name = "Jump", Source = "R6 Think Jump", Id = 86602718468982},
    {Name = "Fall", Source = "R6 Think Fall", Id = 99778737832990},
    {Name = "Climb", Source = "R6 Think Climb", Id = 138285798677131},
    {Name = "Swim", Source = "R6 Think Swim", Id = 100764544474061},
    {Name = "SwimIdle", Source = "R6 Think Swim", Id = 128066363334013},
    {Name = "CartoonyControl", Source = "Known working control", Id = 742637544},
}

local function log(message)
    print("[UGC V9] " .. tostring(message))
end

log("========== UGC Animation Fetch Diagnostic V9 ==========")
log("PlaceId: " .. tostring(game.PlaceId))
log("GameId: " .. tostring(game.GameId))
log("Character: " .. (localPlayer.Character and localPlayer.Character:GetFullName() or "none"))
log("ContentId format: rbxassetid://<id>")
log("Player character will NOT be changed.")

local successCount = 0
local failCount = 0

for _, test in ipairs(TESTS) do
    local contentId = "rbxassetid://" .. tostring(test.Id)
    log(" ")
    log("----- " .. test.Name .. " | " .. test.Source .. " | " .. contentId .. " -----")

    local ok, result = pcall(function()
        local clip = provider:GetAnimationClipAsync(contentId)
        if not clip then
            error("GetAnimationClipAsync returned nil")
        end

        local length = clip.Length
        local descendants = #clip:GetDescendants()
        local className = clip.ClassName
        local looped = nil

        if clip:IsA("KeyframeSequence") or clip:IsA("CurveAnimation") then
            looped = clip.Loop
        end

        local output = string.format(
            "Class=%s | Length=%.4f | Loop=%s | Descendants=%d",
            tostring(className),
            tonumber(length) or 0,
            tostring(looped),
            descendants
        )

        clip:Destroy()
        return output
    end)

    if ok then
        successCount += 1
        log("FETCH SUCCESS: " .. result)
    else
        failCount += 1
        log("FETCH FAILED: " .. tostring(result))
    end
end

log(" ")
log("========== SUMMARY ==========")
log("Successful clip fetches: " .. tostring(successCount))
log("Failed clip fetches: " .. tostring(failCount))
log("No changes were made to LocalPlayer.Character.")
log("========== END V9 ==========")

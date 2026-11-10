-- Just X Universal - UGC Animation Bundle Diagnostic
-- Inspects bundle metadata and tests whether each bundled item can be loaded
-- as an Animation. Does NOT change Animate.AnimationId or apply any pack.
-- Test target: R6 Think (216379865265281)

local AssetService = game:GetService("AssetService")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")

local PLAYER = Players.LocalPlayer
local BUNDLE_ID = 216379865265281
local PREFIX = "[UGC Animation Diagnostic]"

local function log(...)
    print(PREFIX, ...)
end

local function safeString(value)
    if value == nil then return "<nil>" end
    return tostring(value)
end

local function classifyName(name)
    local normalized = tostring(name or ""):lower():gsub("[%s_%-]", "")
    if normalized:find("swimidle", 1, true) or normalized:find("swimmingidle", 1, true) then return "swimidle" end
    if normalized:find("idle", 1, true) then return "idle" end
    if normalized:find("walk", 1, true) then return "walk" end
    if normalized:find("run", 1, true) then return "run" end
    if normalized:find("jump", 1, true) then return "jump" end
    if normalized:find("fall", 1, true) then return "fall" end
    if normalized:find("climb", 1, true) then return "climb" end
    if normalized:find("swim", 1, true) then return "swim" end
    return "unknown"
end

log("========== BUNDLE REQUEST ==========")
log("Bundle ID =", BUNDLE_ID)

local okDetails, details = pcall(function()
    return AssetService:GetBundleDetailsAsync(BUNDLE_ID)
end)

if not okDetails then
    warn(PREFIX, "GetBundleDetailsAsync failed:", details)
    return
end

if type(details) ~= "table" or type(details.Items) ~= "table" then
    warn(PREFIX, "Bundle details have an unexpected format")
    return
end

log("Bundle name =", safeString(details.Name))
log("Bundle type =", safeString(details.BundleType))
log("Item count =", #details.Items)

local character = PLAYER.Character or PLAYER.CharacterAdded:Wait()
local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

if not animator and humanoid then
    animator = Instance.new("Animator")
    animator.Parent = humanoid
end

if not animator then
    warn(PREFIX, "Humanoid/Animator not found; metadata will be printed without playback tests")
end

log("========== ITEM METADATA + LOAD TEST ==========")

for index, item in ipairs(details.Items) do
    local itemId = tonumber(item.Id)
    local itemName = safeString(item.Name)
    local itemType = safeString(item.Type)
    local assetType = safeString(item.AssetType)
    local slot = classifyName(itemName)

    log(string.format(
        "ITEM %02d | Name=%s | ID=%s | Type=%s | AssetType=%s | SlotGuess=%s",
        index,
        itemName,
        safeString(item.Id),
        itemType,
        assetType,
        slot
    ))

    if itemId and animator then
        local animation = Instance.new("Animation")
        animation.Name = "UGC_Diagnostic_" .. tostring(index)
        animation.AnimationId = "rbxassetid://" .. tostring(itemId)

        local preloadStatus = "not tested"
        local okPreload, preloadError = pcall(function()
            ContentProvider:PreloadAsync({animation}, function(contentId, status)
                preloadStatus = tostring(status)
                log("PRELOAD CALLBACK |", contentId, "|", preloadStatus)
            end)
        end)

        if not okPreload then
            preloadStatus = "ERROR: " .. tostring(preloadError)
        end
        log("PRELOAD RESULT |", itemId, "|", preloadStatus)

        local okLoad, trackOrError = pcall(function()
            return animator:LoadAnimation(animation)
        end)

        if okLoad and trackOrError then
            local track = trackOrError
            local playStatus = "not played"
            local okPlay, playError = pcall(function()
                -- Zero weight prevents the diagnostic track from visibly posing the character.
                track:Play(0, 0, 1)
                task.wait(0.65)
                playStatus = "played at weight 0"
            end)

            if not okPlay then
                playStatus = "ERROR: " .. tostring(playError)
            end

            log(string.format(
                "LOAD RESULT | %s | SUCCESS | TrackLength=%.3f | PlayTest=%s",
                tostring(itemId),
                tonumber(track.Length) or 0,
                playStatus
            ))

            pcall(function() track:Stop(0) end)
            pcall(function() track:Destroy() end)
        else
            log("LOAD RESULT |", itemId, "| FAILED |", tostring(trackOrError))
        end

        animation:Destroy()
        task.wait(0.15)
    elseif not itemId then
        log("LOAD TEST SKIPPED | item has no numeric ID")
    else
        log("LOAD TEST SKIPPED | Animator unavailable")
    end
end

log("========== END ==========")
log("No Animate IDs were changed. Send the complete output beginning with [UGC Animation Diagnostic].")

-- R6 Think Animation Diagnostic V3
-- Compares three sources without changing the character:
-- 1) The equipped avatar pack reported by HumanoidDescription (Modern R6 per user)
-- 2) Locomotion IDs currently referenced by the game's Animate script
-- 3) R6 Think bundle animation assets
-- Also includes a known Cartoony catalog control asset.

local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")

local PREFIX = "[UGC Animation Diagnostic V3]"
local function log(...)
    print(PREFIX, ...)
end

local player = Players.LocalPlayer
if not player then
    log("ERROR: LocalPlayer is unavailable.")
    return
end

local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
if not humanoid then
    log("ERROR: Humanoid was not found.")
    return
end

log("========== ENVIRONMENT ==========")
log("PlaceId =", game.PlaceId)
log("GameId =", game.GameId)
log("Character =", character:GetFullName())
log("RigType =", tostring(humanoid.RigType))

local groups = {
    {
        name = "Equipped avatar pack - HumanoidDescription (Modern R6)",
        items = {
            {name = "Idle", id = 104406060298008},
            {name = "Walk", id = 124988819613327},
            {name = "Run", id = 99901926147031},
            {name = "Jump", id = 116343198036897},
            {name = "Fall", id = 129580654694779},
            {name = "Climb", id = 110907985002120},
            {name = "Swim", id = 99928806802401},
        },
    },
    {
        name = "Current game Animate locomotion IDs",
        items = {
            {name = "Idle 1", id = 101793141637116},
            {name = "Idle 2", id = 125921160688941},
            {name = "Walk", id = 77528393221674},
            {name = "Run", id = 86891955109302},
            {name = "Jump", id = 110846938084197},
            {name = "Fall", id = 73058134172796},
            {name = "Climb", id = 82533816982803},
            {name = "Swim", id = 91921965295268},
            {name = "Swim Idle", id = 116996856605537},
        },
    },
    {
        name = "R6 Think bundle",
        items = {
            {name = "Idle", id = 137273817835971},
            {name = "Walk", id = 93952528577974},
            {name = "Run", id = 70841708593861},
            {name = "Jump", id = 79534551779955},
            {name = "Fall", id = 93811344606236},
            {name = "Climb", id = 114158755065309},
            {name = "Swim", id = 99559196758012},
        },
    },
    {
        name = "Known catalog control",
        items = {
            {name = "Cartoony Idle", id = 742637544},
        },
    },
}

log("========== HUMANOID DESCRIPTION ==========")
local descriptionOK, description = pcall(function()
    return humanoid:GetAppliedDescription()
end)

if descriptionOK and description then
    for _, property in ipairs({
        "IdleAnimation",
        "WalkAnimation",
        "RunAnimation",
        "JumpAnimation",
        "FallAnimation",
        "ClimbAnimation",
        "SwimAnimation",
    }) do
        local ok, value = pcall(function()
            return description[property]
        end)
        log("DESCRIPTION", property, "=", ok and tostring(value) or ("ERROR: " .. tostring(value)))
    end
else
    log("GetAppliedDescription failed:", tostring(description))
end

log("========== CURRENT ANIMATE SCRIPT ==========")
local animate = character:FindFirstChild("Animate")
if animate then
    local found = 0
    for _, object in ipairs(animate:GetDescendants()) do
        if object:IsA("Animation") then
            local id = object.AnimationId
            if id and id ~= "" then
                found += 1
                log(object:GetFullName(), "=", id)
            end
        end
    end
    log("Animate Animation instances =", found)
else
    log("Animate script not found.")
end

log("========== ASSET FETCH COMPARISON ==========")
local results = {}

for _, group in ipairs(groups) do
    log("---------- GROUP:", group.name, "----------")

    for _, item in ipairs(group.items) do
        local assetId = "rbxassetid://" .. tostring(item.id)
        local status = "NO_CALLBACK"
        local callbackError = nil
        local callOK, callError = pcall(function()
            ContentProvider:PreloadAsync({assetId}, function(callbackAssetId, fetchStatus)
                status = tostring(fetchStatus)
                log("CALLBACK", group.name, "|", item.name, "|", callbackAssetId, "|", status)
            end)
        end)

        if not callOK then
            callbackError = tostring(callError)
        end

        local key = group.name .. " / " .. item.name
        results[#results + 1] = {
            group = group.name,
            name = item.name,
            id = item.id,
            status = status,
            callOK = callOK,
            error = callbackError,
        }

        log(
            "RESULT",
            key,
            "| ID=" .. tostring(item.id),
            "| PreloadCall=" .. tostring(callOK),
            "| Status=" .. status,
            "| Error=" .. (callbackError or "<none>")
        )
    end
end

log("========== SUMMARY ==========")
for _, result in ipairs(results) do
    log(
        result.group,
        "|",
        result.name,
        "|",
        tostring(result.id),
        "|",
        result.status,
        "| CallOK=" .. tostring(result.callOK)
    )
end

log("========== END V3 ==========")
log("No Animate IDs, HumanoidDescription values, or character properties were modified.")
log("Send the complete output beginning with [UGC Animation Diagnostic V3].")

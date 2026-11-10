-- UGC Animation Diagnostic V4
-- Uses AnimationClipProvider:GetAnimationClipAsync to inspect actual clip retrieval.
-- Does not modify the character, Animate script, or HumanoidDescription.

local PREFIX = "[UGC Animation Diagnostic V4]"
local function log(...)
    print(PREFIX, ...)
end

local Players = game:GetService("Players")
local player = Players.LocalPlayer
if not player then
    log("ERROR: LocalPlayer unavailable.")
    return
end

local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)

local okProvider, provider = pcall(function()
    return game:GetService("AnimationClipProvider")
end)

log("========== ENVIRONMENT ==========")
log("PlaceId =", game.PlaceId)
log("GameId =", game.GameId)
log("Character =", character:GetFullName())
log("RigType =", humanoid and tostring(humanoid.RigType) or "<no Humanoid>")
log("AnimationClipProvider available =", tostring(okProvider))
if not okProvider or not provider then
    log("ERROR: AnimationClipProvider unavailable:", tostring(provider))
    return
end

local groups = {
    {
        name = "Equipped avatar pack - Modern R6",
        items = {
            {"Idle", 104406060298008},
            {"Walk", 124988819613327},
            {"Run", 99901926147031},
            {"Jump", 116343198036897},
            {"Fall", 129580654694779},
            {"Climb", 110907985002120},
            {"Swim", 99928806802401},
        },
    },
    {
        name = "Current game Animate",
        items = {
            {"Idle 1", 101793141637116},
            {"Idle 2", 125921160688941},
            {"Walk", 77528393221674},
            {"Run", 86891955109302},
            {"Jump", 110846938084197},
            {"Fall", 73058134172796},
            {"Climb", 82533816982803},
            {"Swim", 91921965295268},
            {"Swim Idle", 116996856605537},
        },
    },
    {
        name = "R6 Think",
        items = {
            {"Idle", 137273817835971},
            {"Walk", 93952528577974},
            {"Run", 70841708593861},
            {"Jump", 79534551779955},
            {"Fall", 93811344606236},
            {"Climb", 114158755065309},
            {"Swim", 99559196758012},
        },
    },
    {
        name = "Known catalog control",
        items = {
            {"Cartoony Idle", 742637544},
        },
    },
}

local results = {}

log("========== DIRECT CLIP RETRIEVAL ==========")
for _, group in ipairs(groups) do
    log("---------- GROUP:", group.name, "----------")

    for _, item in ipairs(group.items) do
        local slot, id = item[1], item[2]
        local assetId = "rbxassetid://" .. tostring(id)
        local callOK, clipOrError = pcall(function()
            return provider:GetAnimationClipAsync(assetId)
        end)

        local className = "<none>"
        local length = "<unavailable>"
        local looped = "<unavailable>"
        local childCount = "<unavailable>"
        local errorText = "<none>"

        if callOK and typeof(clipOrError) == "Instance" then
            className = clipOrError.ClassName
            local lengthOK, lengthValue = pcall(function()
                return clipOrError.Length
            end)
            if lengthOK then
                length = tostring(lengthValue)
            end
            local loopOK, loopValue = pcall(function()
                return clipOrError.Loop
            end)
            if loopOK then
                looped = tostring(loopValue)
            end
            local childrenOK, children = pcall(function()
                return clipOrError:GetDescendants()
            end)
            if childrenOK then
                childCount = tostring(#children)
            end
        else
            errorText = tostring(clipOrError)
        end

        local result = {
            group = group.name,
            slot = slot,
            id = id,
            success = callOK,
            className = className,
            length = length,
            looped = looped,
            childCount = childCount,
            error = errorText,
        }
        results[#results + 1] = result

        log(
            "RESULT",
            group.name,
            "| Slot=" .. slot,
            "| ID=" .. tostring(id),
            "| CallOK=" .. tostring(callOK),
            "| Class=" .. className,
            "| Length=" .. length,
            "| Loop=" .. looped,
            "| Descendants=" .. childCount,
            "| Error=" .. errorText
        )
    end
end

log("========== SUMMARY ==========")
for _, result in ipairs(results) do
    log(
        result.group,
        "|",
        result.slot,
        "|",
        tostring(result.id),
        "|",
        result.success and result.className or "FAILED",
        "| Length=" .. result.length,
        "| Error=" .. result.error
    )
end

log("========== END V4 ==========")
log("No character or animation properties were modified.")
log("Send the complete output beginning with [UGC Animation Diagnostic V4].")

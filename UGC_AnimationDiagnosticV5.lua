-- UGC Animation Diagnostic V5
-- Observes animations that the Animator actually plays.
-- Does not modify the character, Animate script, HumanoidDescription, or tracks.

local PREFIX = "[UGC Animation Diagnostic V5]"
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
if not humanoid then
    log("ERROR: Humanoid unavailable.")
    return
end

local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 10)
if not animator then
    log("ERROR: Animator unavailable.")
    return
end

local DURATION = 30
local SAMPLE_INTERVAL = 1
local startedAt = os.clock()

local function extractId(value)
    if value == nil then
        return nil
    end
    local textValue = tostring(value)
    return tonumber(textValue:match("%d+"))
end

local knownIds = {
    [104406060298008] = "Modern R6 / Idle",
    [124988819613327] = "Modern R6 / Walk",
    [99901926147031] = "Modern R6 / Run",
    [116343198036897] = "Modern R6 / Jump",
    [129580654694779] = "Modern R6 / Fall",
    [110907985002120] = "Modern R6 / Climb",
    [99928806802401] = "Modern R6 / Swim",

    [137273817835971] = "R6 Think / Idle",
    [93952528577974] = "R6 Think / Walk",
    [70841708593861] = "R6 Think / Run",
    [79534551779955] = "R6 Think / Jump",
    [93811344606236] = "R6 Think / Fall",
    [114158755065309] = "R6 Think / Climb",
    [99559196758012] = "R6 Think / Swim",

    [742637544] = "Cartoony / Idle",
}

local function safeRead(callback, fallback)
    local ok, value = pcall(callback)
    if ok then
        return value
    end
    return fallback or "<error>"
end

local function describeTrack(track)
    local animation = safeRead(function()
        return track.Animation
    end, nil)
    local animationId = animation and safeRead(function()
        return animation.AnimationId
    end, "<unavailable>") or "<no Animation>"
    local numericId = extractId(animationId)
    local label = numericId and knownIds[numericId] or "Unknown / game animation"

    return {
        track = track,
        id = numericId,
        animationId = tostring(animationId),
        label = label,
        name = tostring(safeRead(function() return track.Name end, "<unknown>")),
        isPlaying = tostring(safeRead(function() return track.IsPlaying end, "<unknown>")),
        timePosition = tostring(safeRead(function() return track.TimePosition end, "<unknown>")),
        length = tostring(safeRead(function() return track.Length end, "<unknown>")),
        weightCurrent = tostring(safeRead(function() return track.WeightCurrent end, "<unknown>")),
        weightTarget = tostring(safeRead(function() return track.WeightTarget end, "<unknown>")),
        priority = tostring(safeRead(function() return track.Priority end, "<unknown>")),
        looped = tostring(safeRead(function() return track.Looped end, "<unknown>")),
    }
end

local function getDescriptionIds()
    local ok, description = pcall(function()
        return humanoid:GetAppliedDescription()
    end)
    if not ok or not description then
        log("HumanoidDescription unavailable:", tostring(description))
        return
    end

    local properties = {
        {"Idle", "IdleAnimation"},
        {"Walk", "WalkAnimation"},
        {"Run", "RunAnimation"},
        {"Jump", "JumpAnimation"},
        {"Fall", "FallAnimation"},
        {"Climb", "ClimbAnimation"},
        {"Swim", "SwimAnimation"},
    }

    log("---------- APPLIED HUMANOID DESCRIPTION ----------")
    for _, item in ipairs(properties) do
        local value = safeRead(function()
            return description[item[2]]
        end, "<unavailable>")
        log(item[1], "=", tostring(value), "| ID=", tostring(extractId(value)))
    end
end

local function scanAnimate()
    local animate = character:FindFirstChild("Animate")
    log("---------- CURRENT ANIMATE SCRIPT ----------")
    if not animate then
        log("Animate not found.")
        return
    end

    for _, object in ipairs(animate:GetDescendants()) do
        if object:IsA("Animation") then
            local id = extractId(object.AnimationId)
            log(
                "ANIMATE",
                "Name=" .. object.Name,
                "| ID=" .. tostring(id),
                "| AnimationId=" .. tostring(object.AnimationId),
                "| Match=" .. tostring(id and knownIds[id] or "none")
            )
        end
    end
end

log("========== ENVIRONMENT ==========")
log("PlaceId =", game.PlaceId)
log("GameId =", game.GameId)
log("Character =", character:GetFullName())
log("RigType =", tostring(humanoid.RigType))
log("Animator =", animator:GetFullName())
log("Observation duration =", DURATION, "seconds")
log("Sampling interval =", SAMPLE_INTERVAL, "second")
getDescriptionIds()
scanAnimate()

local observed = {}
local function recordTrack(track, reason)
    if not track then
        return
    end

    local info = describeTrack(track)
    local key = tostring(info.id or info.animationId) .. "|" .. info.name
    local firstSeen = not observed[key]
    observed[key] = true

    log(
        firstSeen and "TRACK FIRST SEEN" or "TRACK EVENT",
        "| Reason=" .. tostring(reason),
        "| Label=" .. info.label,
        "| Name=" .. info.name,
        "| ID=" .. tostring(info.id),
        "| AnimationId=" .. info.animationId,
        "| IsPlaying=" .. info.isPlaying,
        "| TimePosition=" .. info.timePosition,
        "| Length=" .. info.length,
        "| WeightCurrent=" .. info.weightCurrent,
        "| WeightTarget=" .. info.weightTarget,
        "| Priority=" .. info.priority,
        "| Looped=" .. info.looped
    )
end

local playedConnection = animator.AnimationPlayed:Connect(function(track)
    recordTrack(track, "AnimationPlayed")
end)

log("========== LIVE TRACK OBSERVATION ==========")
log("For the next 30 seconds, move around, walk, jump, and swim if possible.")
log("No controls or animation properties are changed.")

local lastSnapshot = {}
while os.clock() - startedAt < DURATION do
    local ok, tracks = pcall(function()
        return animator:GetPlayingAnimationTracks()
    end)

    if ok and tracks then
        local activeKeys = {}
        for _, track in ipairs(tracks) do
            local info = describeTrack(track)
            local key = tostring(info.id or info.animationId) .. "|" .. info.name
            activeKeys[key] = true

            if not lastSnapshot[key] then
                recordTrack(track, "SnapshotStarted")
            else
                log(
                    "TRACK SNAPSHOT",
                    "| Label=" .. info.label,
                    "| Name=" .. info.name,
                    "| ID=" .. tostring(info.id),
                    "| TimePosition=" .. info.timePosition,
                    "| Length=" .. info.length,
                    "| WeightCurrent=" .. info.weightCurrent,
                    "| WeightTarget=" .. info.weightTarget,
                    "| IsPlaying=" .. info.isPlaying
                )
            end
        end

        for key in pairs(lastSnapshot) do
            if not activeKeys[key] then
                log("TRACK STOPPED", "|", key)
            end
        end
        lastSnapshot = activeKeys
    else
        log("GetPlayingAnimationTracks failed:", tostring(tracks))
    end

    task.wait(SAMPLE_INTERVAL)
end

playedConnection:Disconnect()
log("========== SUMMARY ==========")
local count = 0
for key in pairs(observed) do
    count = count + 1
    log("OBSERVED", count, "|", key)
end
log("Unique observed tracks =", count)
log("========== END V5 ==========")
log("No character, Animate, HumanoidDescription, or animation track properties were modified.")
log("Send the complete output beginning with [UGC Animation Diagnostic V5].")

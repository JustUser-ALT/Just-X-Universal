-- UGC Animation Diagnostic V6
-- Temporarily tests the currently applied HumanoidDescription animation IDs
-- by substituting them into matching Animate Animation objects.
-- Every changed AnimationId is restored at the end, including after errors.
-- Does not disable/restart Animate or modify HumanoidDescription.

local PREFIX = "[UGC Animation Diagnostic V6]"
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

local animate = character:FindFirstChild("Animate")
if not animate then
    log("ERROR: Animate script not found.")
    return
end

local DURATION = 35
local SAMPLE_INTERVAL = 1

local function safeRead(callback, fallback)
    local ok, value = pcall(callback)
    if ok then
        return value
    end
    return fallback
end

local function numericId(value)
    if value == nil then
        return nil
    end
    return tonumber(tostring(value):match("%d+"))
end

local descriptionOK, description = pcall(function()
    return humanoid:GetAppliedDescription()
end)
if not descriptionOK or not description then
    log("ERROR: GetAppliedDescription failed:", tostring(description))
    return
end

local slots = {
    {
        label = "Idle",
        property = "IdleAnimation",
        folder = "idle",
        targetNames = {"Animation1", "Animation2"},
    },
    {
        label = "Walk",
        property = "WalkAnimation",
        folder = "walk",
        targetNames = {"WalkAnim"},
    },
    {
        label = "Run",
        property = "RunAnimation",
        folder = "run",
        targetNames = {"RunAnim"},
    },
    {
        label = "Jump",
        property = "JumpAnimation",
        folder = "jump",
        targetNames = {"JumpAnim"},
    },
    {
        label = "Fall",
        property = "FallAnimation",
        folder = "fall",
        targetNames = {"FallAnim"},
    },
    {
        label = "Climb",
        property = "ClimbAnimation",
        folder = "climb",
        targetNames = {"ClimbAnim"},
    },
    {
        label = "Swim",
        property = "SwimAnimation",
        folder = "swim",
        targetNames = {"Swim"},
    },
}

local function findDirectChildIgnoreCase(parent, wanted)
    local wantedLower = string.lower(wanted)
    for _, child in ipairs(parent:GetChildren()) do
        if string.lower(child.Name) == wantedLower then
            return child
        end
    end
    return nil
end

local function findAnimationCandidates(folder, wantedName)
    local found = {}
    local wantedLower = string.lower(wantedName)
    for _, object in ipairs(folder:GetDescendants()) do
        if object:IsA("Animation") and string.lower(object.Name) == wantedLower then
            found[#found + 1] = object
        end
    end
    return found
end

local function getPath(object)
    local ok, path = pcall(function()
        return object:GetFullName()
    end)
    return ok and path or object.Name
end

local changes = {}
local testedIds = {}
local preparedCount = 0

local function restoreAll()
    for index = #changes, 1, -1 do
        local item = changes[index]
        pcall(function()
            item.object.AnimationId = item.original
        end)
    end
end

log("========== ENVIRONMENT ==========")
log("PlaceId =", game.PlaceId)
log("GameId =", game.GameId)
log("Character =", character:GetFullName())
log("RigType =", tostring(humanoid.RigType))
log("Animate =", animate:GetFullName())
log("Observation duration =", DURATION, "seconds")
log("Source = Humanoid:GetAppliedDescription() (currently equipped avatar animation values)")
log("This is a temporary local test. Original AnimationIds will be restored.")

for _, slot in ipairs(slots) do
    local rawId = safeRead(function()
        return description[slot.property]
    end, nil)
    local id = numericId(rawId)
    slot.id = id
    log("DESCRIPTION", slot.label, "|", slot.property, "=", tostring(rawId), "| ID =", tostring(id))
end

log("========== TARGET DISCOVERY ==========")
for _, slot in ipairs(slots) do
    if not slot.id or slot.id <= 0 then
        log("SKIP", slot.label, "| No usable ID in HumanoidDescription.")
    else
        local folder = findDirectChildIgnoreCase(animate, slot.folder)
        if not folder then
            log("SKIP", slot.label, "| Animate folder not found:", slot.folder)
        else
            for _, targetName in ipairs(slot.targetNames) do
                local candidates = findAnimationCandidates(folder, targetName)
                if #candidates == 1 then
                    local object = candidates[1]
                    local original = safeRead(function()
                        return object.AnimationId
                    end, nil)
                    if original ~= nil then
                        changes[#changes + 1] = {
                            object = object,
                            original = original,
                            slot = slot.label,
                            id = slot.id,
                        }
                        log(
                            "TARGET",
                            slot.label,
                            "| Path=" .. getPath(object),
                            "| Before=" .. tostring(original),
                            "| Test=rbxassetid://" .. tostring(slot.id)
                        )
                    else
                        log("SKIP", slot.label, "| Could not read original AnimationId:", getPath(object))
                    end
                elseif #candidates == 0 then
                    log("SKIP", slot.label, "| Exact Animation child not found:", getPath(folder) .. "." .. targetName)
                else
                    log("SKIP", slot.label, "| Ambiguous exact-name matches:", targetName, "| Count=", #candidates)
                    for _, object in ipairs(candidates) do
                        log("AMBIGUOUS", getPath(object), "| Current=", tostring(object.AnimationId))
                    end
                end
            end
        end
    end
end

if #changes == 0 then
    log("ERROR: No safe Animate targets were found. Nothing was modified.")
    return
end

log("========== TEMPORARY SUBSTITUTION ==========")
local applyOK, applyError = pcall(function()
    for _, item in ipairs(changes) do
        item.object.AnimationId = "rbxassetid://" .. tostring(item.id)
        testedIds[item.id] = item.slot
        preparedCount = preparedCount + 1
        log("APPLIED", item.slot, "|", getPath(item.object), "| ID=", item.id)
    end
end)

if not applyOK then
    log("APPLY ERROR:", tostring(applyError))
    restoreAll()
    log("RESTORE COMPLETE. No observation was started.")
    return
end

local observed = {}
local connections = {}

local function describeTrack(track)
    local animation = safeRead(function()
        return track.Animation
    end, nil)
    local animationId = animation and safeRead(function()
        return animation.AnimationId
    end, "<unavailable>") or "<no Animation>"
    local id = numericId(animationId)

    return {
        id = id,
        animationId = tostring(animationId),
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

local function recordTrack(track, reason)
    local info = describeTrack(track)
    if not info.id or not testedIds[info.id] then
        return
    end

    observed[info.id] = true
    log(
        "TEST TRACK",
        "| Reason=" .. tostring(reason),
        "| Slot=" .. tostring(testedIds[info.id]),
        "| ID=" .. tostring(info.id),
        "| Name=" .. info.name,
        "| IsPlaying=" .. info.isPlaying,
        "| TimePosition=" .. info.timePosition,
        "| Length=" .. info.length,
        "| WeightCurrent=" .. info.weightCurrent,
        "| WeightTarget=" .. info.weightTarget,
        "| Priority=" .. info.priority,
        "| Looped=" .. info.looped
    )
end

local observationOK, observationError = xpcall(function()
    connections[#connections + 1] = animator.AnimationPlayed:Connect(function(track)
        recordTrack(track, "AnimationPlayed")
    end)

    log("========== LIVE OBSERVATION ==========")
    log("Move around now: stand still, walk, run, jump, and climb/swim if possible.")
    log("The test does not disable Animate or restart the Animator.")
    log("Observe whether the substituted IDs appear as tracks with Length > 0 and nonzero WeightCurrent.")

    local startedAt = os.clock()
    local lastSnapshot = {}

    while os.clock() - startedAt < DURATION do
        if player.Character ~= character or not character.Parent then
            log("STOP: Character changed or was removed. Restoring the original IDs.")
            break
        end

        local tracksOK, tracks = pcall(function()
            return animator:GetPlayingAnimationTracks()
        end)

        if tracksOK and tracks then
            local activeNow = {}
            for _, track in ipairs(tracks) do
                local info = describeTrack(track)
                if info.id and testedIds[info.id] then
                    local key = tostring(info.id) .. "|" .. info.name
                    activeNow[key] = true
                    if not lastSnapshot[key] then
                        recordTrack(track, "SnapshotStarted")
                    else
                        log(
                            "TEST SNAPSHOT",
                            "| Slot=" .. tostring(testedIds[info.id]),
                            "| ID=" .. tostring(info.id),
                            "| Name=" .. info.name,
                            "| Length=" .. info.length,
                            "| TimePosition=" .. info.timePosition,
                            "| WeightCurrent=" .. info.weightCurrent,
                            "| IsPlaying=" .. info.isPlaying
                        )
                    end
                end
            end

            for key in pairs(lastSnapshot) do
                if not activeNow[key] then
                    log("TEST TRACK STOPPED", "|", key)
                end
            end
            lastSnapshot = activeNow
        else
            log("GetPlayingAnimationTracks failed:", tostring(tracks))
        end

        task.wait(SAMPLE_INTERVAL)
    end
end, function(err)
    return tostring(err) .. "\n" .. debug.traceback()
end)

for _, connection in ipairs(connections) do
    pcall(function()
        connection:Disconnect()
    end)
end

log("========== RESTORING ORIGINAL ANIMATIONS ==========")
restoreAll()
log("RESTORE COMPLETE | Changed Animation objects =", preparedCount)

log("========== SUMMARY ==========")
for _, slot in ipairs(slots) do
    if slot.id then
        log(
            "RESULT",
            slot.label,
            "| ID=" .. tostring(slot.id),
            "| TrackObserved=" .. tostring(observed[slot.id] == true)
        )
    end
end

if not observationOK then
    log("OBSERVATION ERROR:", tostring(observationError))
end

log("========== END V6 ==========")
log("All captured original AnimationIds were restored.")
log("Send the complete output beginning with [UGC Animation Diagnostic V6].")

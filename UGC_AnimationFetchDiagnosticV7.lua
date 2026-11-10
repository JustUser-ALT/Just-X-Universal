-- UGC Animation Fetch Diagnostic V7
-- Tests the CreateHumanoidModelFromDescription method used by UGC Anim Studio.
-- Does NOT modify LocalPlayer.Character or its Animate script.

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local TESTS = {
    {Name = "Idle", Property = "IdleAnimation", Id = 137273817835971, Folders = {"idle"}},
    {Name = "Walk", Property = "WalkAnimation", Id = 93952528577974, Folders = {"walk"}},
    {Name = "Run", Property = "RunAnimation", Id = 70841708593861, Folders = {"run"}},
    {Name = "Jump", Property = "JumpAnimation", Id = 79534551779955, Folders = {"jump"}},
    {Name = "Fall", Property = "FallAnimation", Id = 93811344606236, Folders = {"fall"}},
    {Name = "Climb", Property = "ClimbAnimation", Id = 114158755065309, Folders = {"climb"}},
    {Name = "Swim", Property = "SwimAnimation", Id = 99559196758012, Folders = {"swim", "swimidle"}},
}

local function log(message)
    print("[UGC V7] " .. tostring(message))
end

local function readAnimations(animate, folderNames)
    local found = {}
    if not animate then
        return found
    end

    for _, folderName in ipairs(folderNames) do
        local folder = animate:FindFirstChild(folderName)
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("Animation") then
                    found[#found + 1] = {
                        Name = child.Name,
                        AnimationId = child.AnimationId,
                        Folder = folderName,
                    }
                end
            end
        end
    end

    return found
end

log("========== UGC Animation Fetch Diagnostic V7 ==========")
log("PlaceId: " .. tostring(game.PlaceId))
log("GameId: " .. tostring(game.GameId))
log("Character: " .. (localPlayer.Character and localPlayer.Character:GetFullName() or "none"))
log("Testing R6 Think bundle 216379865265281")
log("Method: Players:CreateHumanoidModelFromDescription(desc, R15)")
log("Player character will NOT be changed.")

local successCount = 0
local failCount = 0

for _, test in ipairs(TESTS) do
    log(" ")
    log("----- " .. test.Name .. " | requested ID: " .. tostring(test.Id) .. " -----")

    local ok, result = pcall(function()
        local description = Instance.new("HumanoidDescription")
        description[test.Property] = test.Id

        local dummy = Players:CreateHumanoidModelFromDescription(
            description,
            Enum.HumanoidRigType.R15
        )

        if not dummy then
            error("CreateHumanoidModelFromDescription returned nil")
        end

        local animate = dummy:FindFirstChild("Animate")
        local animations = readAnimations(animate, test.Folders)

        local appliedId
        local humanoid = dummy:FindFirstChildOfClass("Humanoid")
        if humanoid then
            local appliedOk, appliedDescription = pcall(function()
                return humanoid:GetAppliedDescription()
            end)
            if appliedOk and appliedDescription then
                appliedId = appliedDescription[test.Property]
                appliedDescription:Destroy()
            end
        end

        local lines = {
            "Animate found: " .. tostring(animate ~= nil),
            "Generated Animation objects: " .. tostring(#animations),
            "AppliedDescription ID: " .. tostring(appliedId or "unavailable"),
        }

        for _, animation in ipairs(animations) do
            lines[#lines + 1] = string.format(
                "  Folder=%s | Name=%s | AnimationId=%s",
                animation.Folder,
                animation.Name,
                animation.AnimationId
            )
        end

        dummy:Destroy()
        description:Destroy()

        return table.concat(lines, "\n")
    end)

    if ok then
        successCount += 1
        log("CREATE SUCCESS")
        for line in string.gmatch(result, "[^\n]+") do
            log(line)
        end
    else
        failCount += 1
        log("CREATE FAILED: " .. tostring(result))
    end
end

log(" ")
log("========== SUMMARY ==========")
log("Successful model creations: " .. tostring(successCount))
log("Failed model creations: " .. tostring(failCount))
log("No changes were made to LocalPlayer.Character.")
log("========== END V7 ==========")

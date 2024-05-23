-- This version adds the function of quitting the game after earning points and then automatically rejoining the game.

-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
CRED = "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc"
Game = "-vsAs0-3xQw6QUAYbUuonTbXAnFNJtzqhriKKOymQ9w"

InAction = InAction or false -- Prevents the agent from taking multiple actions at once.

Logs = Logs or {}

colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
    Logs[msg] = Logs[msg] or {}
    table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.

function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Function to get direction towards a target position
function towardsDirection(player, target)
    local towardsDirection = ""

    local dx = target.x - player.x
    local dy = target.y - player.y

    if dy > 0 then
        towardsDirection = towardsDirection .. "Down"
    elseif dy < 0 then
        towardsDirection = towardsDirection .. "Up"
    end

    if dx > 0 then
        towardsDirection = towardsDirection .. "Right"
    elseif dx < 0 then
        towardsDirection = towardsDirection .. "Left"
    end

    return towardsDirection
end

function calculateDifference(player, target)
    return player.energy - target.health
end

function selectTargetToAttack()
    local player = LatestGameState.Players[ao.id]
    local bestTarget = nil
    local maxDifference = -math.huge

    --
    for targetId, state in pairs(LatestGameState.Players) do
        if targetId ~= ao.id then
            if state.health < player.energy then
                local difference = calculateDifference(player, state)
                if difference > maxDifference then
                    maxDifference = difference
                    bestTarget = targetId
                end
            end
        end
    end

    return bestTarget
end

function decideNextAction()
    local player = LatestGameState.Players[ao.id]
    local targetId = selectTargetToAttack()
    local targetPlayer = LatestGameState.Players[targetId]
    if targetId then
        if inRange(player.x, player.x, targetPlayer.x, targetPlayer.y, 1) then
            print(colors.red .. "Attacking player with maximum difference." .. colors.reset)
            ao.send({
                Target = Game,
                Action = "PlayerAttack",
                Player = ao.id,
                TargetPlayer = targetId,
                AttackEnergy = tostring(player.energy)
            })
        else
            local direction = towardsDirection(player, targetPlayer)
            ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Direction = direction })
        end
    else
        print(colors.red .. "No suitable target found. Moving randomly." .. colors.reset)
        local directionMap = { "Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft" }
        local randomIndex = math.random(#directionMap)
        ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Direction = directionMap[randomIndex] })
    end

    InAction = false --
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add("PrintAnnouncements", Handlers.utils.hasMatchingTag("Action", "Announcement"), handleAnnouncement)

-- Handler to trigger game state updates.
Handlers.add("GetGameStateOnTick", Handlers.utils.hasMatchingTag("Action", "Tick"), handleTick)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add("AutoPay", Handlers.utils.hasMatchingTag("Action", "AutoPay"), handleAutoPay)

-- Handler to update the game state upon receiving game state information.
Handlers.add("UpdateGameState", Handlers.utils.hasMatchingTag("Action", "GameState"), handleGameState)

-- Handler to decide the next best action.
Handlers.add("decideNextAction", Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"), handleUpdatedGameState)

-- Handler to automatically attack when hit by another player.
Handlers.add("ReturnAttack", Handlers.utils.hasMatchingTag("Action", "Hit"), handleHit)

Handlers.add("CreditNotice", Handlers.utils.hasMatchingTag("Action", "Credit-Notice"), handleCreditNotice)


-- This Handler will refresh after payment confirmation is received
Handlers.add("Payment-refresh", Handlers.utils.hasMatchingTag("Action", "Payment-Received"),
    handleAnnouncementPaymentReceived)

function handleAnnouncement(msg)
    if msg.Event == "Started-Waiting-Period" then
        ao.send({ Target = ao.id, Action = "AutoPay" })
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
        InAction = true  -- InAction logic added
        ao.send({ Target = Game, Action = "GetGameState" })
    elseif InAction then -- InAction logic added
        print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
end

function handleTick()
    if not InAction then -- InAction logic added
        InAction = true  -- InAction logic added
        print(colors.gray .. "Getting game state..." .. colors.reset)
        ao.send({ Target = Game, Action = "GetGameState" })
    else
        print("Previous action still in progress. Skipping.")
    end
end

function handleAutoPay(msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000" })
end

function handleGameState(msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({ Target = ao.id, Action = "UpdatedGameState" })
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
end

function handleUpdatedGameState()
    if LatestGameState.GameMode ~= "Playing" then
        InAction = false -- InAction logic added
        return
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({ Target = ao.id, Action = "Tick" })
end

function handleHit(msg)
    if not InAction then -- InAction logic added
        InAction = true  -- InAction logic added
        local playerEnergy = LatestGameState.Players[ao.id].energy
        if playerEnergy == undefined then
            print(colors.red .. "Unable to read energy." .. colors.reset)
            ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy." })
        elseif playerEnergy == 0 then
            print(colors.red .. "Player has insufficient energy." .. colors.reset)
            ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Player has no energy." })
        else
            print(colors.red .. "Returning attack." .. colors.reset)
            ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy) })
        end
        InAction = false -- InAction logic added
        ao.send({ Target = ao.id, Action = "Tick" })
    else
        print("Previous action still in progress. Skipping.")
    end
end

function handleAnnouncementPaymentReceived(msg)
    print(colors.green .. "refresh" .. colors.reset)
    InAction = false
    Send({ Target = Game, Action = "GetGameState", Name = Name, Owner = Owner })
end

function handleCreditNotice(msg)
    Send({ Target = Game, Action = "Withdraw" })
    print(colors.gray .. "------Do Withdraw ------ " .. colors.reset)
end

Send({ Target = Game, Action = "Register" })
Prompt = function() return Name .. "> " end

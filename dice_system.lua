-- dice_system.lua (SERVER)
-- D&D-style dice rolling with stat modifiers

outputServerLog("===== DICE_SYSTEM.LUA LOADING =====")

--------------------------------------------------------------------------------
-- DICE ROLLING FUNCTIONS
--------------------------------------------------------------------------------

-- Roll a single die (d4, d6, d8, d10, d12, d20, d100)
function rollDie(sides)
    return math.random(1, sides)
end

-- Roll multiple dice and sum (e.g., "3d6" = roll 3 six-sided dice)
function rollDice(count, sides)
    local total = 0
    local rolls = {}
    
    for i = 1, count do
        local roll = rollDie(sides)
        table.insert(rolls, roll)
        total = total + roll
    end
    
    return total, rolls
end

-- Roll with advantage (roll twice, take higher)
function rollWithAdvantage(sides)
    local roll1 = rollDie(sides)
    local roll2 = rollDie(sides)
    return math.max(roll1, roll2), {roll1, roll2}
end

-- Roll with disadvantage (roll twice, take lower)
function rollWithDisadvantage(sides)
    local roll1 = rollDie(sides)
    local roll2 = rollDie(sides)
    return math.min(roll1, roll2), {roll1, roll2}
end

-- Calculate stat modifier from stat value
function getStatModifier(statValue)
    return math.floor((statValue - 10) / 2)
end

--------------------------------------------------------------------------------
-- SKILL CHECKS
--------------------------------------------------------------------------------

-- Perform a skill check (d20 + stat modifier vs DC)
function performSkillCheck(player, stat, dc)
    if not AccountManager then return false, "System error" end
    
    local char = AccountManager:getActiveCharacter(player)
    if not char then return false, "No active character" end
    
    -- Get stat value
    local statValue = char.stats[stat] or 10
    local modifier = getStatModifier(statValue)
    
    -- Get equipment bonuses
    local bonuses = getElementData(player, "equipment.bonuses") or {}
    local equipBonus = bonuses[stat] or 0
    
    -- Total modifier
    local totalModifier = modifier + equipBonus
    
    -- Roll d20
    local roll = rollDie(20)
    local total = roll + totalModifier
    
    -- Determine success
    local success = total >= dc
    local critSuccess = (roll == 20)
    local critFail = (roll == 1)
    
    return success, {
        roll = roll,
        modifier = totalModifier,
        total = total,
        dc = dc,
        critSuccess = critSuccess,
        critFail = critFail,
        stat = stat
    }
end

--------------------------------------------------------------------------------
-- COMBAT ROLLS
--------------------------------------------------------------------------------

-- Attack roll (d20 + STR/DEX modifier)
function performAttackRoll(player, targetAC, useDex)
    if not AccountManager then return false, "System error" end
    
    local char = AccountManager:getActiveCharacter(player)
    if not char then return false, "No active character" end
    
    -- Determine which stat to use
    local stat = useDex and "DEX" or "STR"
    local statValue = char.stats[stat] or 10
    local modifier = getStatModifier(statValue)
    
    -- Get equipment bonuses
    local bonuses = getElementData(player, "equipment.bonuses") or {}
    local equipBonus = bonuses[stat] or 0
    
    -- Roll d20
    local roll = rollDie(20)
    local total = roll + modifier + equipBonus
    
    -- Check hit
    local hit = total >= targetAC
    local critHit = (roll == 20)
    local critMiss = (roll == 1)
    
    return hit, {
        roll = roll,
        modifier = modifier + equipBonus,
        total = total,
        ac = targetAC,
        critHit = critHit,
        critMiss = critMiss,
        stat = stat
    }
end

-- Damage roll (e.g., 1d8 + STR modifier)
function performDamageRoll(player, diceCount, diceSides, useDex)
    if not AccountManager then return 0, "System error" end
    
    local char = AccountManager:getActiveCharacter(player)
    if not char then return 0, "No active character" end
    
    -- Determine stat modifier
    local stat = useDex and "DEX" or "STR"
    local statValue = char.stats[stat] or 10
    local modifier = getStatModifier(statValue)
    
    -- Get equipment bonuses
    local bonuses = getElementData(player, "equipment.bonuses") or {}
    local equipBonus = bonuses[stat] or 0
    
    -- Roll damage dice
    local total, rolls = rollDice(diceCount, diceSides)
    local finalDamage = total + modifier + equipBonus
    
    return math.max(1, finalDamage), {
        rolls = rolls,
        diceTotal = total,
        modifier = modifier + equipBonus,
        finalDamage = finalDamage,
        stat = stat
    }
end

-- Saving throw (d20 + stat modifier vs DC)
function performSavingThrow(player, stat, dc)
    return performSkillCheck(player, stat, dc)
end

--------------------------------------------------------------------------------
-- PROXIMITY DICE ROLLS (for RP)
--------------------------------------------------------------------------------

function sendProximityDiceRoll(player, message, range)
    range = range or 20
    
    local charName = getElementData(player, "character.name") or getPlayerName(player)
    local px, py, pz = getElementPosition(player)
    local dimension = getElementDimension(player)
    local interior = getElementInterior(player)
    
    -- Send to self
    outputChatBox(message, player, 255, 200, 0)
    
    -- Send to nearby players
    for _, p in ipairs(getElementsByType("player")) do
        if p ~= player then
            local tx, ty, tz = getElementPosition(p)
            local tDim = getElementDimension(p)
            local tInt = getElementInterior(p)
            
            if tDim == dimension and tInt == interior then
                local distance = getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz)
                if distance <= range then
                    outputChatBox(message, p, 255, 200, 0)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- COMMANDS
--------------------------------------------------------------------------------

-- /roll [dice notation] - Roll dice (e.g., /roll 3d6, /roll d20)
addCommandHandler("roll", function(player, cmd, diceNotation)
    if not diceNotation then
        outputChatBox("Usage: /roll [dice notation] - e.g., /roll d20, /roll 3d6, /roll 2d8+5", player, 255, 255, 0)
        return
    end
    
    local charName = getElementData(player, "character.name") or getPlayerName(player)
    
    -- Parse dice notation (e.g., "3d6", "d20", "2d8+5")
    local count, sides, bonus = string.match(diceNotation, "(%d*)d(%d+)([%+%-]?%d*)")
    
    count = tonumber(count) or 1
    sides = tonumber(sides)
    bonus = tonumber(bonus) or 0
    
    if not sides or sides < 2 then
        outputChatBox("Invalid dice notation", player, 255, 0, 0)
        return
    end
    
    -- Roll the dice
    local total, rolls = rollDice(count, sides)
    total = total + bonus
    
    -- Format rolls string
    local rollsStr = table.concat(rolls, ", ")
    local bonusStr = (bonus ~= 0) and (" " .. (bonus >= 0 and "+" or "") .. bonus) or ""
    
    local message = string.format("* %s rolls %dd%d%s: [%s]%s = %d",
        charName, count, sides, bonusStr, rollsStr, bonusStr, total)
    
    sendProximityDiceRoll(player, message, 20)
    outputServerLog("[DICE] " .. charName .. ": " .. diceNotation .. " = " .. total)
end)

-- /rollstat [stat] [DC] - Perform a stat check
addCommandHandler("rollstat", function(player, cmd, stat, dc)
    if not stat then
        outputChatBox("Usage: /rollstat [STR/DEX/CON/INT/WIS/CHA] [DC (optional)]", player, 255, 255, 0)
        return
    end
    
    stat = string.upper(stat)
    dc = tonumber(dc) or 10
    
    local validStats = {STR = true, DEX = true, CON = true, INT = true, WIS = true, CHA = true}
    if not validStats[stat] then
        outputChatBox("Invalid stat. Use: STR, DEX, CON, INT, WIS, or CHA", player, 255, 0, 0)
        return
    end
    
    local success, result = performSkillCheck(player, stat, dc)
    if not result then
        outputChatBox("Error: " .. tostring(success), player, 255, 0, 0)
        return
    end
    
    local charName = getElementData(player, "character.name") or getPlayerName(player)
    local modStr = (result.modifier >= 0) and ("+" .. result.modifier) or tostring(result.modifier)
    
    local message
    if result.critSuccess then
        message = string.format("* %s rolls %s check: [NATURAL 20] %s = 20 %s DC %d - CRITICAL SUCCESS!",
            charName, stat, modStr, success and ">=" or "<", dc)
    elseif result.critFail then
        message = string.format("* %s rolls %s check: [NATURAL 1] %s = 1 %s DC %d - CRITICAL FAILURE!",
            charName, stat, modStr, success and ">=" or "<", dc)
    else
        message = string.format("* %s rolls %s check: [%d] %s = %d %s DC %d - %s",
            charName, stat, result.roll, modStr, result.total,
            success and ">=" or "<", dc, success and "SUCCESS" or "FAILURE")
    end
    
    sendProximityDiceRoll(player, message, 20)
end)

-- /save [stat] [DC] - Saving throw
addCommandHandler("save", function(player, cmd, stat, dc)
    if not stat then
        outputChatBox("Usage: /save [STR/DEX/CON/INT/WIS/CHA] [DC]", player, 255, 255, 0)
        return
    end
    
    stat = string.upper(stat)
    dc = tonumber(dc) or 15
    
    local validStats = {STR = true, DEX = true, CON = true, INT = true, WIS = true, CHA = true}
    if not validStats[stat] then
        outputChatBox("Invalid stat. Use: STR, DEX, CON, INT, WIS, or CHA", player, 255, 0, 0)
        return
    end
    
    local success, result = performSavingThrow(player, stat, dc)
    if not result then
        outputChatBox("Error: " .. tostring(success), player, 255, 0, 0)
        return
    end
    
    local charName = getElementData(player, "character.name") or getPlayerName(player)
    local modStr = (result.modifier >= 0) and ("+" .. result.modifier) or tostring(result.modifier)
    
    local message = string.format("* %s makes a %s saving throw: [%d] %s = %d vs DC %d - %s",
        charName, stat, result.roll, modStr, result.total, dc, 
        success and "SUCCESS!" or "FAILURE!")
    
    sendProximityDiceRoll(player, message, 20)
end)

-- /attack [target player name] [AC] - Perform attack roll
addCommandHandler("attack", function(player, cmd, targetName, ac)
    if not targetName or not ac then
        outputChatBox("Usage: /attack [target name] [AC]", player, 255, 255, 0)
        return
    end
    
    ac = tonumber(ac) or 15
    
    -- Find target player
    local targetPlayer = nil
    for _, p in ipairs(getElementsByType("player")) do
        local pName = getElementData(p, "character.name") or getPlayerName(p)
        if string.lower(pName):find(string.lower(targetName)) then
            targetPlayer = p
            break
        end
    end
    
    if not targetPlayer then
        outputChatBox("Target player not found", player, 255, 0, 0)
        return
    end
    
    local charName = getElementData(player, "character.name") or getPlayerName(player)
    local targetCharName = getElementData(targetPlayer, "character.name") or getPlayerName(targetPlayer)
    
    -- Perform attack roll
    local hit, result = performAttackRoll(player, ac, false) -- Using STR
    if not result then
        outputChatBox("Error: " .. tostring(hit), player, 255, 0, 0)
        return
    end
    
    local modStr = (result.modifier >= 0) and ("+" .. result.modifier) or tostring(result.modifier)
    
    local message
    if result.critHit then
        message = string.format("* %s attacks %s: [NATURAL 20] %s vs AC %d - CRITICAL HIT!",
            charName, targetCharName, modStr, ac)
    elseif result.critMiss then
        message = string.format("* %s attacks %s: [NATURAL 1] %s vs AC %d - CRITICAL MISS!",
            charName, targetCharName, modStr, ac)
    else
        message = string.format("* %s attacks %s: [%d] %s = %d vs AC %d - %s",
            charName, targetCharName, result.roll, modStr, result.total, ac,
            hit and "HIT!" or "MISS!")
    end
    
    sendProximityDiceRoll(player, message, 30)
    
    -- If hit, prompt for damage
    if hit then
        outputChatBox("Hit! Use /damage [dice notation] to roll damage (e.g., /damage 1d8)", player, 0, 255, 0)
    end
end)

-- /damage [dice notation] - Roll damage
addCommandHandler("damage", function(player, cmd, diceNotation)
    if not diceNotation then
        outputChatBox("Usage: /damage [dice notation] - e.g., /damage 1d8, /damage 2d6", player, 255, 255, 0)
        return
    end
    
    local charName = getElementData(player, "character.name") or getPlayerName(player)
    
    -- Parse dice notation
    local count, sides = string.match(diceNotation, "(%d*)d(%d+)")
    
    count = tonumber(count) or 1
    sides = tonumber(sides)
    
    if not sides or sides < 2 then
        outputChatBox("Invalid dice notation", player, 255, 0, 0)
        return
    end
    
    -- Roll damage with STR modifier
    local damage, result = performDamageRoll(player, count, sides, false)
    
    local rollsStr = table.concat(result.rolls, ", ")
    local modStr = (result.modifier >= 0) and ("+" .. result.modifier) or tostring(result.modifier)
    
    local message = string.format("* %s deals damage: [%s] %s = %d damage",
        charName, rollsStr, modStr, damage)
    
    sendProximityDiceRoll(player, message, 30)
end)

-- /d20, /d6, /d8, /d10, /d12, /d100 - Quick roll shortcuts
local quickRolls = {20, 6, 8, 10, 12, 100}
for _, sides in ipairs(quickRolls) do
    addCommandHandler("d" .. sides, function(player)
        local charName = getElementData(player, "character.name") or getPlayerName(player)
        local roll = rollDie(sides)
        local message = string.format("* %s rolls d%d: %d", charName, sides, roll)
        sendProximityDiceRoll(player, message, 20)
    end)
end

outputServerLog("===== DICE_SYSTEM.LUA LOADED =====")

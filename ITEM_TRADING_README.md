# Item Dropping & Trading System
## Installation Guide

This adds two major features to your MTA:SA roleplay server:
1. **World Items** - Drop and pick up physical items in the game world
2. **Player Trading** - Secure trade window between players

---

## Installation

### 1. Add Files to Your Server

Copy these three files to your resource folder (next to `inventory_system.lua`):

- `world_items.lua` (server)
- `player_trading.lua` (server)
- `client_trading.lua` (client)

### 2. Update meta.xml

Add these lines to your `meta.xml`:

```xml
<!-- World Items System -->
<script src="world_items.lua" type="server" />

<!-- Player Trading System -->
<script src="player_trading.lua" type="server" />
<script src="client_trading.lua" type="client" />
```

**Important**: Add them AFTER `inventory_system.lua` since they depend on it.

### 3. Remove Old /drop Command

The `world_items.lua` file overrides the existing `/drop` command in `inventory_system.lua`.

You can either:
- **Option A**: Comment out lines 779-787 in `inventory_system.lua` (the old drop command)
- **Option B**: Let the new command override it (MTA will use the last one loaded)

### 4. Restart Your Server

Type in server console:
```
restart yourresourcename
```

---

## Features

### World Items (Dropping/Picking Up)

**Commands:**

- `/drop [slot] [quantity]` - Drop an item from your inventory
  - Example: `/drop 3 5` - Drop 5 of the item in slot 3
  - Creates a physical object in the world

- `/pickup` - Pick up the nearest item (within 3 meters)
  - Automatically adds to inventory

- `/nearby` - List items within 10 meters
  - Shows distance, name, and quantity

**How It Works:**
- Dropped items become physical objects (model based on category)
- Items persist in database (survive server restarts)
- Players can walk around and see items on the ground
- Pickup range: 3 meters
- Items can only be picked up in same dimension/interior

**Item Models:**
- Weapons: Ammo pickup (1240)
- Armor: Armor pickup (1242)
- Consumables: Health pickup (1241)
- Materials: Box/crate (1265)
- Tools: Briefcase (1279)
- Quest items: Suitcase (1210)
- Misc: Generic item (1254)

### Player Trading

**Commands:**

- `/trade [player name]` - Start a trade with another player
  - Example: `/trade John` (partial names work)
  
- `/trademoney [amount]` - Set money to offer in trade
  - Example: `/trademoney 500`

**How It Works:**

1. **Initiate**: One player types `/trade [name]`
   - Must be within 5 meters
   - Both players get trade window

2. **Add Offer**: 
   - Type in money amount box or use `/trademoney`
   - Add items (via inventory integration - see below)

3. **Lock Offer**: Click "Lock Offer" button
   - Prevents changes to your offer
   - Shows partner you're ready

4. **Accept**: When both locked, click "Accept Trade"
   - Items and money instantly transferred
   - Characters auto-saved

5. **Cancel**: Click "Cancel Trade" anytime
   - No items/money transferred
   - Both players returned to normal

**Safety Features:**
- Both players must lock before accepting
- All items/money verified before transfer
- Atomic transaction (all or nothing)
- Can't trade equipped items
- Distance checked throughout trade
- Auto-cancels if player disconnects

---

## Database Tables Created

### world_items
```sql
CREATE TABLE world_items (
    id INTEGER PRIMARY KEY,
    item_id TEXT,
    quantity INTEGER,
    instance_id TEXT UNIQUE,
    pos_x REAL,
    pos_y REAL,
    pos_z REAL,
    dimension INTEGER,
    interior INTEGER,
    dropped_by TEXT,
    dropped_time INTEGER
);
```

---

## Configuration

### Customize Item Models

Edit `ITEM_MODELS` table in `world_items.lua` (line 13):

```lua
local ITEM_MODELS = {
    weapon = 1240,      -- Change to your preferred model
    armor = 1242,
    -- etc...
}
```

### Adjust Pickup Range

Edit line 224 in `world_items.lua`:
```lua
local closestDist = 3.0  -- Change this number (meters)
```

### Adjust Trade Distance

Edit line 40 in `player_trading.lua`:
```lua
if dist > 5.0 then  -- Change this number (meters)
```

---

## Known Limitations

### Trading Items

The current trade GUI shows a basic interface but **adding items requires inventory integration**.

**Two options to fix this:**

#### Option 1: Quick Fix (Command-Based)
Add this to `player_trading.lua`:

```lua
addCommandHandler("tradeitem", function(player, cmd, slot, qty)
    local trade = ActiveTrades[player]
    if not trade then
        outputChatBox("Not in a trade", player, 255, 0, 0)
        return
    end
    
    local inv = getPlayerInventory(player)
    if not inv then return end
    
    local slotNum = tonumber(slot)
    if not slotNum or slotNum < 1 or slotNum > #inv.items then
        outputChatBox("Invalid slot", player, 255, 0, 0)
        return
    end
    
    local item = inv.items[slotNum]
    local quantity = tonumber(qty) or item.quantity
    
    addTradeItem(player, item.instanceID, quantity)
end)
```

Then players use: `/tradeitem [slot] [quantity]`

#### Option 2: Full GUI (Recommended)
Enhance `client_trading.lua` to:
1. Show your inventory in the trade window
2. Click items to add them
3. Right-click to remove items

This requires creating an inventory list widget and hooking it into the existing trade window.

---

## Testing Checklist

### World Items
- [ ] Drop an item - object appears on ground
- [ ] Pick up item - added to inventory
- [ ] Server restart - items still exist
- [ ] Different dimensions - can't see items in other dimension
- [ ] Stackable items - quantity preserved
- [ ] `/nearby` shows correct items

### Trading
- [ ] Start trade with nearby player
- [ ] Trade window appears for both
- [ ] Set money - number updates
- [ ] Lock offer - button changes
- [ ] Both lock - accept button enables
- [ ] Accept trade - items transferred
- [ ] Cancel trade - nothing transferred
- [ ] Disconnect during trade - auto-cancels
- [ ] Trade equipped item - prevented
- [ ] Trade without enough money - prevented

---

## Troubleshooting

### "Could not access database"
- Make sure `world_items.lua` loads AFTER `server.lua` in meta.xml
- Check that `database` variable is global in `server.lua`

### Items not appearing when dropped
- Check server console for errors
- Verify ItemRegistry is loaded
- Make sure item ID exists in database
- Check player's dimension/interior

### Trade window not opening
- Verify `client_trading.lua` is in meta.xml as `type="client"`
- Check if players are within 5 meters
- Check console (F8) for errors
- Make sure both players have active characters

### Items disappear after pickup
- This is normal - items are destroyed when picked up
- Check inventory with `/inv` to confirm

### Trade items not showing
- Currently requires manual integration (see Limitations above)
- Use `/trademoney` for money-only trades in the meantime

---

## Future Enhancements

Possible improvements:

1. **Auto-pickup** - Walk over items to collect automatically
2. **Item durability** - Dropped items decay over time
3. **Theft** - Steal from dropped items (criminal mechanic)
4. **Containers** - Drop multiple items in a "bag" or "crate"
5. **Trade history** - Log all trades to database
6. **Trade tax** - State collects % of traded money (economic mechanic)
7. **Black market** - Special trade locations for contraband
8. **Inventory GUI in trade** - Click items to add them (not just commands)

---

## Support

If you encounter issues:
1. Check server console for errors
2. Check client console (F8) for errors
3. Verify all files are in meta.xml in correct order
4. Make sure you restarted the resource after adding files

---

## Credits

**World Items System**
- Physical item drops with persistence
- Database-backed world item storage
- Automatic cleanup on pickup

**Player Trading System**
- Secure two-player trade window
- Atomic transactions (all or nothing)
- Money and item transfer support

Both systems integrate seamlessly with your existing `inventory_system.lua` and `AccountManager`.

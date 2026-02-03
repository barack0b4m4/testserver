# D&D RP Gamemode for MTA:SA

## Commands Reference

### Character Commands
| Command | Description |
|---------|-------------|
| `/stats` | View your D&D character stats (STR, DEX, CON, INT, WIS, CHA) |
| `/savechar` | Manually save your character |

### Inventory Commands (inventory_system.lua)

**Item Management (DM only):**
| Command | Description |
|---------|-------------|
| `/createitem "Name" category [options]` | Create a new item definition |
| `/edititem itemID [options]` | Modify an existing item |
| `/deleteitem itemID` | Remove an item definition |
| `/listitems [category] [search]` | List all items or filter by category/name |
| `/iteminfo itemID` | View detailed item information |

**Create Item Options:**
- `-w weight` - Item weight in kg (default: 1.0)
- `-v value` - Item value in dollars (default: 1)
- `-d durability` - Item durability (optional)
- `-q quality` - common/uncommon/rare/epic/legendary
- `-a armorValue` - Armor protection value (makes item equippable)
- `-wpn weaponID` - MTA weapon ID (makes item equippable)
- `-stack maxStack` - Make item stackable with max stack size
- `-use effect` - Make item usable with effect (heal:50, armor:25, buff_stat:STR:2:60000)
- `-stat STAT:value` - Add stat bonus (e.g., -stat STR:2 -stat DEX:1)

**Examples:**
```
/createitem "Kevlar Vest" armor -a 100 -w 5 -q uncommon
/createitem "Health Potion" consumable -use heal:50 -stack 10 -q common
/createitem "Dragon Sword" weapon -wpn 8 -stat STR:5 -d 200 -q legendary
/createitem "Iron Ore" material -w 2 -stack 30
```

**Player Inventory:**
| Command | Description |
|---------|-------------|
| `/inv` | View your inventory with item quality colors |
| `/use [slot]` | Use a consumable item from inventory slot |
| `/equip [slot]` | Equip a weapon or armor from inventory slot |
| `/unequip [slot]` | Unequip from slot (weapon/armor/accessory1/accessory2) |
| `/drop [slot] [qty]` | Drop item(s) from inventory |
| `/equipped` | Show currently equipped items |
| `/giveitem itemID [qty] [player]` | Give item (DM can give to others) |

### Dice Commands (dice_system.lua)
| Command | Description |
|---------|-------------|
| `/roll [notation]` | Roll dice (e.g., `/roll d20`, `/roll 3d6`, `/roll 2d8+5`) |
| `/d20`, `/d6`, `/d8`, `/d10`, `/d12`, `/d100` | Quick roll shortcuts |
| `/rollstat [stat] [DC]` | Perform a stat check (e.g., `/rollstat STR 15`) |
| `/save [stat] [DC]` | Make a saving throw |
| `/attack [target] [AC]` | Perform an attack roll against target's AC |
| `/damage [notation]` | Roll damage (e.g., `/damage 1d8`) |

### Chat Commands (proximity_chat.lua)
| Command | Description | Range |
|---------|-------------|-------|
| Normal chat | Just type and press Enter | 30m |
| `/s` or `/shout` | Shout a message | 100m |
| `/w` or `/whisper` | Whisper a message | 5m |
| `/me [action]` | Roleplay action (e.g., `/me waves`) | 20m |
| `/do [description]` | Environment/narration description | 20m |
| `/ame [action]` | Action with overhead text | 20m |
| `/try [action]` | 50/50 chance action | 20m |
| `/b [text]` | Local out-of-character chat | 20m |
| `/ooc [text]` | Global out-of-character chat | All |
| `/helpme` | Show chat command help | - |

### Dungeon Master Commands (dungeon_master.lua)
*Requires DM permissions*

| Command | Description |
|---------|-------------|
| `/dm` | Toggle DM mode |
| `/spawnnpc [name] [skinID]` | Spawn an NPC at your position |
| `/despawnnpc [npcID]` | Remove an NPC |
| `/npcsay [npcID] [message]` | Make NPC speak |
| `/npcme [npcID] [action]` | Make NPC perform action |
| `/npcroll [npcID] [stat] [DC]` | Make NPC roll a stat check |
| `/forceroll [player] [stat] [DC]` | Force a player to roll |
| `/listnpcs` | List all active NPCs |
| `/adddm [username]` | Grant DM permissions |
| `/removedm [username]` | Remove DM permissions |

### Crafting Commands (crafting_system.lua)

**Player Commands:**
| Command | Description |
|---------|-------------|
| `/craft` | Open the crafting GUI (or press F5) |
| `/craft itemID [qty]` | Craft an item directly by ID |
| `/craftable` | List items you have materials to craft |

**DM Recipe Management:**
| Command | Description |
|---------|-------------|
| `/recipegui` | **Open the visual Recipe Editor GUI** |
| `/createrecipe itemID [resultQty]` | Create a new recipe for an item |
| `/addingredient recipeID materialID [qty]` | Add a required material to a recipe |
| `/removeingredient recipeID materialID` | Remove a material from a recipe |
| `/setrecipetool recipeID [toolID]` | Set required tool (blank to remove) |
| `/deleterecipe itemID` | Delete a recipe |
| `/listrecipes [search]` | List all recipes |
| `/recipeinfo itemID` | View detailed recipe information |

**Recipe Editor GUI Features:**
- Browse all existing recipes with ingredient counts
- Create new recipes with visual item selection
- Edit existing recipes (ingredients, quantity, tool)
- Delete recipes with confirmation
- Dropdown menus for selecting items (filtered by category)
- Real-time ingredient list management

**Creating a Recipe Example:**
```
1. /createrecipe iron_sword 1           (create recipe shell)
2. /addingredient iron_sword iron_ingot 3  (add 3 iron ingots)
3. /addingredient iron_sword leather 1     (add 1 leather for handle)
4. /setrecipetool iron_sword blacksmith_hammer  (require hammer tool)
5. /recipeinfo iron_sword                  (verify recipe)
```

**Crafting Features:**
- Recipes require specific materials in specific quantities
- Optional tool requirement (tool must be in inventory, not consumed)
- Automatic weight calculation (materials consumed, result added)
- GUI shows what materials you have vs need
- Color-coded ingredients (green = have enough, red = need more)

### Shopkeeper Commands (shopkeeper_system.lua)
*Requires DM permissions*

| Command | Description |
|---------|-------------|
| `/createshop "Name" [skinID]` | Create a shopkeeper at your position |
| `/listshops` | List all shops |
| `/gotoshop [shopID]` | Teleport to a shop |
| `/moveshop [shopID]` | Move shop to your position |
| `/respawnshop [shopID]` | Respawn shop NPC |
| `/shopadditem [shopID] [itemID] [price] [stock]` | Quick-add item to shop |

**Shop GUI Features:**
- **Players**: Click shopkeeper to open shop, browse items, purchase
- **DMs**: Enable DM mode (`/dm`), then click shopkeeper to edit:
  - Change shop name and description
  - Add/remove items with custom prices
  - Set stock limits (-1 = unlimited)
  - Set markup multiplier for auto-pricing
  - Delete the entire shop

**Creating a Shop Workflow:**
```
1. /dm                              (enable DM mode)
2. /createshop "Bob's Weapons" 28   (create shopkeeper NPC)
3. Click the shopkeeper             (opens editor GUI)
4. Add items with prices and stock
5. /dm                              (disable DM mode to test as player)
```

## Stats & Mechanics

### D&D Stats and Their Effects

| Stat | Abbreviation | Effects |
|------|--------------|---------|
| **Strength** | STR | Melee damage, carry weight (+5kg per modifier) |
| **Dexterity** | DEX | Weapon accuracy, movement speed (±5% per modifier), stamina |
| **Constitution** | CON | Max health (+15 HP per modifier), muscle appearance |
| **Intelligence** | INT | XP gain bonus (+10% per modifier) |
| **Wisdom** | WIS | Luck bonus on rolls, driving skill |
| **Charisma** | CHA | Shop prices (-5% per modifier), NPC respect |

### Stat Modifiers
Calculated as: `floor((stat - 10) / 2)`

| Stat Value | Modifier | Example Effects |
|------------|----------|-----------------|
| 8-9 | -1 | 95 HP, 95% speed, 105% prices |
| 10-11 | +0 | 100 HP, 100% speed, 100% prices |
| 12-13 | +1 | 115 HP, 105% speed, 95% prices |
| 14-15 | +2 | 130 HP, 110% speed, 90% prices |
| 16-17 | +3 | 145 HP, 115% speed, 85% prices |
| 18-19 | +4 | 160 HP, 120% speed, 80% prices |

### Commands
- `/stats` - View your character's stats with equipment bonuses
- `/refreshstats` - Reapply stat modifiers (useful after equipment changes)

### Item Qualities
- **Common** (Gray)
- **Uncommon** (Green)
- **Rare** (Blue)
- **Epic** (Purple)
- **Legendary** (Orange)

## File Structure
```
├── server.lua              # Core server (database, accounts, characters)
├── inventory_system.lua    # Dynamic item creation & inventory management
├── crafting_system.lua     # Recipe-based crafting system
├── dice_system.lua         # Dice rolling and skill checks
├── dungeon_master.lua      # DM tools for NPCs and forced rolls
├── shopkeeper_system.lua   # Shopkeeper NPCs with persistent inventory
├── proximity_chat.lua      # RP chat with ranges
├── property_system.lua     # Property/interior system
├── client_login.lua        # Login/register GUI
├── client_char_select.lua  # Character selection GUI
├── client_char_create.lua  # Character creation with stat allocation
├── client_shop.lua         # Shop GUI for buying/editing
├── client_item_creator.lua # DM item creation GUI
├── client_crafting.lua     # Player crafting GUI
├── client_npc_names.lua    # NPC name display above heads
├── client_property.lua     # Property interaction client
├── client_dmfly.lua        # DM flying mode
├── serverdata.db           # SQLite database
├── mtaserver.conf          # Server configuration
└── meta.xml                # Resource definition
```

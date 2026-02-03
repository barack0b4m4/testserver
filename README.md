# D&D RP Gamemode for MTA:SA

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SERVER SCRIPTS                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────────┐                                                       │
│  │    server.lua    │  ◄── Core: Database, Accounts, Characters, Stats     │
│  │  (LOADS FIRST)   │                                                       │
│  └────────┬─────────┘                                                       │
│           │                                                                 │
│           ▼                                                                 │
│  ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐    │
│  │inventory_system  │────►│ crafting_system  │     │   dice_system    │    │
│  │  Items, Equip    │     │ Recipes, Craft   │     │  Rolls, Checks   │    │
│  └────────┬─────────┘     └──────────────────┘     └──────────────────┘    │
│           │                                                                 │
│           ▼                                                                 │
│  ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐    │
│  │ dungeon_master   │────►│shopkeeper_system │     │ proximity_chat   │    │
│  │  DM Perms, NPCs  │     │  Shops, Trading  │     │  RP Chat System  │    │
│  └────────┬─────────┘     └──────────────────┘     └──────────────────┘    │
│           │                                                                 │
│           ▼                                                                 │
│  ┌──────────────────┐     ┌──────────────────┐                             │
│  │ property_system  │────►│server_interaction│                             │
│  │  Properties      │     │  POIs, Examine   │                             │
│  └──────────────────┘     └──────────────────┘                             │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                           CLIENT SCRIPTS                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐          │
│  │  client_login    │  │client_char_select│  │client_char_create│          │
│  │  Login/Register  │  │  Char Selection  │  │  Point-Buy Stats │          │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘          │
│                                                                             │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐          │
│  │   client_shop    │  │client_item_create│  │ client_crafting  │          │
│  │  Shop GUI        │  │  Item Creator    │  │  Craft + Recipes │          │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘          │
│                                                                             │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐          │
│  │client_interaction│  │ client_property  │  │  client_dmfly    │          │
│  │Right-click Menus │  │  Enter/Exit      │  │  DM Flying Mode  │          │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Integration Points

| System | Depends On | Provides To |
|--------|------------|-------------|
| server.lua | - | database, AccountManager, Character stats |
| inventory_system | server.lua | ItemRegistry, PlayerInventories |
| dungeon_master | server.lua | isDungeonMaster(), NPCs |
| shopkeeper_system | inventory_system, dungeon_master | Shops, shop functions |
| crafting_system | inventory_system | CraftingRecipes |
| property_system | server.lua | Properties, createProperty() |
| server_interaction | property_system, dungeon_master | POIs, examineTarget() |

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

### Interaction System (client_interaction.lua / server_interaction.lua)

**Right-Click Context Menus:**
Players and DMs can right-click on objects, NPCs, players, and the world to get context-sensitive menus.

**Player Menu Options:**
| Target | Options |
|--------|---------|
| Shopkeeper | Talk/Shop, Examine |
| NPC | Talk, Examine |
| Player | Wave, Examine |
| Property Entrance | Enter Property, Examine |
| POI | Examine |
| Vehicle | Enter Vehicle, Examine |

**DM Menu Options (when in DM Mode via `/dm`):**
| Option | Description |
|--------|-------------|
| Set Property Entrance Here | Mark location for property entrance |
| Teleport Here | Instantly move to clicked location |
| Create POI Here | Open POI creation GUI at this object |
| Toggle Highlight | Highlight/unhighlight object (visual feedback) |
| Toggle Selection | Select/deselect object for batch operations |
| Set Description | Set examine text for NPCs/players/objects |
| Edit POI | Edit existing Point of Interest |
| Delete POI | Remove Point of Interest |
| Create Property Here | Open property creation GUI |

**Points of Interest (POIs):**
DMs can create examinable points in the world that players can interact with.
- Right-click object → "Create POI Here"
- Name and description visible when examined
- Optional highlight marker (glowing corona)
- Persists in database

**Property Creation GUI:**
DMs can right-click anywhere and select "Create Property Here" to open a visual property creator with:
- Property name input
- Interior type dropdown (40+ GTA:SA interiors)
- Price setting
- For sale toggle
- Description field
- Position display

**DM POI/Interaction Commands:**
| Command | Description |
|---------|-------------|
| `/setpropertyentrance [propID]` | Apply pending entrance position to property |
| `/listpois [search]` | List all Points of Interest |
| `/gotopoi [poiID]` | Teleport to a POI |
| `/clearselection` | Deselect all selected objects |

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

## Economic System

### Overview
A comprehensive economic simulation with:
- **Closed Economy**: All money originates from market pools
- **24-Hour Cycles**: Economic activities process daily
- **Player-Driven Markets**: NPC companies provide baseline infrastructure
- **Labor-Based Production**: All production requires employee labor power

### Market Tiers
| Tier | Initial Value | Purpose |
|------|---------------|---------|
| Global | $78 Trillion | International trade (100,000+ units) |
| National | $22 Trillion | Nationwide trade (1,000+ units) |
| State | $800 Billion | Local/retail (any quantity) |

### Company Types
| Type | Function | Employees Produce |
|------|----------|-------------------|
| Resource | Extract raw materials | Items from labor only |
| Manufacturing | Process materials with recipes | Items from inputs |
| Retail | Sell to state market | Revenue from sales |
| Tech | Generate points | Efficiency/Innovation |

### Employee Types
| Type | Wage Minimum | Labor Allocation |
|------|--------------|------------------|
| Unskilled | $100/cycle | Items or Logistics |
| Skilled | $250/cycle | Items or Logistics (1.25x efficiency) |
| Professional | $500/cycle | Efficiency or Innovation |

### Company Points
- **Money**: Cash for wages, purchases, deals
- **Efficiency**: Multiplies production output
- **Innovation**: Spent on company perks/upgrades
- **Logistics**: Required for deal execution

### Commands

**Player Commands:**
| Command | Description |
|---------|-------------|
| `F6` or `/company` | Open company management GUI |
| `/acceptjob` | Accept pending job offer |
| `/declinejob` | Decline pending job offer |

**DM Commands:**
| Command | Description |
|---------|-------------|
| `/forcecycle` | Force end-of-cycle processing |
| `/economystatus` | View market values and stats |
| `/createcompany "Name" type [capital]` | Create NPC company |
| `/listcompanies` | List all companies |

### 24-Hour Cycle Processing
1. **Labor Deposit**: Employees contribute 8 LP each
2. **Production**: Companies produce based on labor and recipes
3. **Deal Execution**: Inter-company trades process
4. **Retail Sales**: Retail companies sell 5-15% of stock to state market
5. **Wage Payment**: Employee wages paid (NPC wages return to market)
6. **Profit Return**: NPC company profits return to state market

### Deal System
- Companies can create recurring trade agreements
- Deals require logistics capacity to execute
- Both parties must have required resources
- Duration can be infinite or limited cycles

## File Structure
```
├── server.lua              # Core server (database, accounts, characters, D&D stats)
├── inventory_system.lua    # Dynamic item creation & inventory management
├── crafting_system.lua     # Recipe-based crafting system
├── dice_system.lua         # Dice rolling and skill checks
├── dungeon_master.lua      # DM tools for NPCs and forced rolls
├── shopkeeper_system.lua   # Shopkeeper NPCs with persistent inventory
├── proximity_chat.lua      # RP chat with ranges
├── property_system.lua     # Property/interior system with 85 presets
├── server_interaction.lua  # POI management, descriptions, interaction handlers
├── economic_system.lua     # Core economy: markets, companies, employees
├── economic_cycle.lua      # 24-hour cycle processing, deals, production
├── client_login.lua        # Login/register GUI
├── client_char_select.lua  # Character selection GUI
├── client_char_create.lua  # Character creation with stat allocation
├── client_shop.lua         # Shop GUI for buying/editing
├── client_item_creator.lua # DM item creation GUI
├── client_crafting.lua     # Player crafting + DM recipe editor GUI
├── client_interaction.lua  # Right-click menus, POI GUI, property creator GUI
├── client_economy.lua      # Company management GUI
├── client_npc_names.lua    # NPC name display above heads
├── client_property.lua     # Property interaction client
├── client_dmfly.lua        # DM flying mode
├── serverdata.db           # SQLite database
├── mtaserver.conf          # Server configuration
└── meta.xml                # Resource definition
```

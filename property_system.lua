--[[
================================================================================
    PROPERTY_SYSTEM.LUA - Property & Interior Management
================================================================================
    Manages purchasable/enterable properties with GTA:SA interior support.
    Each property has an entrance in the world and teleports to an interior.
    
    FEATURES:
    - 85 pre-configured GTA:SA interiors with correct coordinates
    - Property ownership (character OR company)
    - Unique dimension per property instance (no player collision)
    - Property markers and blips
    - Enter/exit system with position memory
    - For sale status and pricing
    - Lock/unlock system for owners
    - Custom descriptions set by owners
    - Transfer between characters and companies
    
    OWNERSHIP TYPES:
    - "character" - Owned by a player character (ownerID = character_id)
    - "company" - Owned by a company (ownerID = company_id)
    
    INTEGRATION POINTS:
    ┌─────────────────────────────────────────────────────────────────────────┐
    │ DEPENDS ON:                                                             │
    │   - server.lua: database, AccountManager                                │
    │   - dungeon_master.lua: isDungeonMaster() for property creation         │
    │   - economic_system.lua: Companies table for company ownership          │
    │                                                                         │
    │ PROVIDES TO:                                                            │
    │   - client_property.lua: Property entry/exit handling                   │
    │   - client_interaction.lua: Property creation via GUI                   │
    │   - server_interaction.lua: Property entrance positioning               │
    │   - vehicle_system.lua: Shared ownership patterns                       │
    │                                                                         │
    │ GLOBAL EXPORTS:                                                         │
    │   - Properties: Table of all properties keyed by ID                     │
    │   - PropertyMarkers: Entrance markers keyed by property ID              │
    │   - PropertyBlips: Map blips keyed by property ID                       │
    │   - INTERIOR_PRESETS: All 85 interior definitions                       │
    │   - createProperty(name, desc, price, interiorID, x, y, z, ...)         │
    │   - purchaseProperty(player, propertyID)                                │
    │   - teleportToPropertyInterior(player, propertyID)                      │
    │   - exitProperty(player)                                                │
    │   - lockProperty(propertyID) / unlockProperty(propertyID)               │
    │   - transferProperty(propertyID, newOwnerType, newOwnerID)              │
    │   - setPropertyDescription(propertyID, description)                     │
    │   - canAccessProperty(player, propertyID)                               │
    └─────────────────────────────────────────────────────────────────────────┘
    
    DM COMMANDS:
    - /createproperty "Name" interiorID price
    - /deleteproperty propertyID
    - /editproperty propertyID [options]
    - /listproperties [search]
    - /gotoproperty propertyID
    - /setpropertyentrance propertyID (uses pending position)
    - /setpropertyowner propertyID character/company ownerID
    
    PLAYER COMMANDS:
    - /buyproperty - Purchase property you're standing at
    - /sellproperty - Put your property up for sale
    - /myproperties - List owned properties
    - /lockproperty - Lock property you're in
    - /unlockproperty - Unlock property you're in
    - /propdesc "description" - Set property description
    - /transferproperty companyID - Transfer to your company
    
    INTERIOR CATEGORIES:
    - Houses & Apartments (1-12)
    - Safehouses (13-24)
    - Police Stations (25-27)
    - Hospitals (28-30)
    - Fast Food (31-33)
    - Bars & Clubs (34-37)
    - Gyms (38-40)
    - Shops (41-51)
    - Barber Shops (52-54)
    - Tattoo Parlors (55-57)
    - Casinos (58-60)
    - 24/7 Stores (61-66)
    - Special Locations (67-85)
================================================================================
]]

-- property_system.lua (SERVER)
-- Property management system with CORRECT GTA:SA interior coordinates

outputServerLog("===== PROPERTY_SYSTEM.LUA LOADING =====")

local db = nil

-- Global tables
Properties = Properties or {}
PropertyMarkers = PropertyMarkers or {}
PropertyBlips = PropertyBlips or {}
PropertyInstanceCounter = 0

-- Owner type constants
PROPERTY_OWNER_TYPE = {
    CHARACTER = "character",
    COMPANY = "company"
}

-- CORRECTED GTA:SA INTERIOR PRESETS
-- Format: {id = GTA Interior ID, name = "Name", x, y, z = spawn position inside}
local INTERIOR_PRESETS = {
    -- === HOUSES & APARTMENTS ===
    ["1"] = {id = 3, name = "CJ's House (Grove St)", x = 2496.05, y = -1695.17, z = 1014.74},
    ["2"] = {id = 2, name = "Ryder's House", x = 2451.77, y = -1699.80, z = 1013.51},
    ["3"] = {id = 1, name = "Sweet's House", x = 2527.02, y = -1679.21, z = 1015.50},
    ["4"] = {id = 5, name = "B Dup's Apartment", x = 1527.38, y = -11.02, z = 1002.10},
    ["5"] = {id = 3, name = "B Dup's Crack Palace", x = 1523.51, y = -47.82, z = 1002.27},
    ["6"] = {id = 8, name = "Colonel Fuhrberger's", x = 2807.62, y = -1171.90, z = 1025.57},
    ["7"] = {id = 9, name = "Denise's House", x = 245.23, y = 304.76, z = 999.15},
    ["8"] = {id = 10, name = "Helena's Barn", x = 290.62, y = 309.06, z = 999.15},
    ["9"] = {id = 4, name = "Barbara's House", x = 302.29, y = 300.52, z = 999.15},
    ["10"] = {id = 6, name = "Michelle's House", x = 306.10, y = 307.82, z = 1003.30},
    ["11"] = {id = 11, name = "Katie's House", x = 267.22, y = 305.73, z = 999.15},
    ["12"] = {id = 12, name = "Millie's House", x = 344.87, y = 307.09, z = 999.15},
    
    -- === SAFEHOUSES ===
    ["13"] = {id = 5, name = "Madd Dogg's Mansion", x = 1267.84, y = -776.96, z = 1091.91},
    ["14"] = {id = 1, name = "Verdant Bluffs Safehouse", x = 2365.10, y = -1131.85, z = 1050.88},
    ["15"] = {id = 2, name = "Jefferson Motel", x = 2217.28, y = -1150.54, z = 1025.80},
    ["16"] = {id = 3, name = "Willowfield Safehouse", x = 2233.69, y = -1112.27, z = 1050.88},
    ["17"] = {id = 6, name = "El Corona Safehouse", x = 2196.84, y = -1204.36, z = 1049.02},
    ["18"] = {id = 7, name = "Hashbury Safehouse", x = 2270.39, y = -1210.45, z = 1047.56},
    ["19"] = {id = 8, name = "Verona Beach Safehouse", x = 2324.33, y = -1145.12, z = 1050.71},
    ["20"] = {id = 10, name = "Santa Maria Safehouse", x = 2262.83, y = -1137.71, z = 1050.63},
    ["21"] = {id = 11, name = "Mulholland Safehouse", x = 2282.91, y = -1138.23, z = 1050.90},
    ["22"] = {id = 12, name = "Prickle Pine Safehouse", x = 2196.99, y = -1204.67, z = 1049.02},
    ["23"] = {id = 15, name = "Whitewood Safehouse", x = 2215.15, y = -1147.48, z = 1025.80},
    ["24"] = {id = 16, name = "Redsands West Safehouse", x = 2194.97, y = -1199.81, z = 1049.10},
    
    -- === POLICE STATIONS ===
    ["25"] = {id = 6, name = "Los Santos Police Dept", x = 246.40, y = 62.24, z = 1003.64},
    ["26"] = {id = 10, name = "San Fierro Police Dept", x = 246.40, y = 62.24, z = 1003.64},
    ["27"] = {id = 3, name = "Las Venturas Police Dept", x = 238.66, y = 139.43, z = 1003.02},
    
    -- === HOSPITALS ===
    ["28"] = {id = 1, name = "All Saints General (LS)", x = -35.32, y = -58.02, z = 1003.55},
    ["29"] = {id = 3, name = "SF Medical Center", x = -35.32, y = -58.02, z = 1003.55},
    ["30"] = {id = 2, name = "LV Hospital", x = -35.32, y = -58.02, z = 1003.55},
    
    -- === FAST FOOD ===
    ["31"] = {id = 9, name = "Cluckin' Bell", x = 365.77, y = -11.61, z = 1001.85},
    ["32"] = {id = 10, name = "Burger Shot", x = 362.86, y = -75.16, z = 1001.51},
    ["33"] = {id = 5, name = "Well Stacked Pizza", x = 372.35, y = -133.01, z = 1001.49},
    
    -- === BARS & CLUBS ===
    ["34"] = {id = 11, name = "Ten Green Bottles Bar", x = 501.96, y = -70.56, z = 998.76},
    ["35"] = {id = 18, name = "Lil' Probe Inn", x = -227.57, y = 1401.55, z = 27.77},
    ["36"] = {id = 3, name = "The Pig Pen (Strip Club)", x = 1204.67, y = -13.54, z = 1000.92},
    ["37"] = {id = 2, name = "Jizzy's Pleasure Domes", x = -2636.69, y = 1402.92, z = 906.46},
    
    -- === GYMS ===
    ["38"] = {id = 5, name = "Ganton Gym (LS)", x = 772.11, y = -5.71, z = 1000.73},
    ["39"] = {id = 6, name = "Cobra Martial Arts (SF)", x = 773.58, y = -48.92, z = 1000.59},
    ["40"] = {id = 7, name = "Below The Belt (LV)", x = 773.89, y = -77.09, z = 1000.66},
    
    -- === SHOPS ===
    ["41"] = {id = 6, name = "Ammu-Nation 1", x = 296.92, y = -111.97, z = 1001.52},
    ["42"] = {id = 7, name = "Ammu-Nation 2", x = 314.82, y = -143.64, z = 999.60},
    ["43"] = {id = 1, name = "Ammu-Nation 3", x = 285.80, y = -86.65, z = 1001.54},
    ["44"] = {id = 4, name = "Ammu-Nation 4 (Booth)", x = 285.37, y = -41.54, z = 1001.57},
    ["45"] = {id = 6, name = "Ammu-Nation 5 (Range)", x = 316.52, y = -170.08, z = 999.59},
    ["46"] = {id = 15, name = "Binco", x = 207.52, y = -111.70, z = 1005.13},
    ["47"] = {id = 14, name = "Didier Sachs", x = 204.11, y = -168.83, z = 1000.52},
    ["48"] = {id = 3, name = "Pro-Laps", x = 206.46, y = -140.09, z = 1003.51},
    ["49"] = {id = 1, name = "Sub Urban", x = 203.78, y = -50.65, z = 1001.80},
    ["50"] = {id = 5, name = "Victim", x = 225.03, y = -9.19, z = 1002.22},
    ["51"] = {id = 18, name = "ZIP", x = 161.39, y = -96.69, z = 1001.80},
    
    -- === BARBER SHOPS ===
    ["52"] = {id = 3, name = "Barber Shop (LS)", x = 411.63, y = -24.32, z = 1001.80},
    ["53"] = {id = 2, name = "Barber Shop (SF)", x = 411.63, y = -24.32, z = 1001.80},
    ["54"] = {id = 12, name = "Barber Shop (LV)", x = 411.63, y = -24.32, z = 1001.80},
    
    -- === TATTOO PARLORS ===
    ["55"] = {id = 16, name = "Tattoo Parlor (LS)", x = -204.44, y = -27.09, z = 1002.27},
    ["56"] = {id = 17, name = "Tattoo Parlor (SF)", x = -204.44, y = -27.09, z = 1002.27},
    ["57"] = {id = 3, name = "Tattoo Parlor (LV)", x = -204.44, y = -27.09, z = 1002.27},
    
    -- === CASINOS ===
    ["58"] = {id = 10, name = "Four Dragons Casino", x = 2016.11, y = 1017.15, z = 996.88},
    ["59"] = {id = 1, name = "Caligula's Casino", x = 2233.94, y = 1712.23, z = 1011.63},
    ["60"] = {id = 12, name = "Casino (Redsands)", x = 1133.35, y = -9.61, z = 1000.68},
    
    -- === 24/7 CONVENIENCE STORES ===
    ["61"] = {id = 17, name = "24/7 Store 1", x = -25.88, y = -188.49, z = 1003.55},
    ["62"] = {id = 10, name = "24/7 Store 2", x = 6.09, y = -28.84, z = 1003.55},
    ["63"] = {id = 18, name = "24/7 Store 3", x = -30.94, y = -92.01, z = 1003.55},
    ["64"] = {id = 16, name = "24/7 Store 4", x = -25.13, y = -139.07, z = 1003.55},
    ["65"] = {id = 4, name = "24/7 Store 5", x = -27.31, y = -29.27, z = 1003.56},
    ["66"] = {id = 6, name = "24/7 Store 6", x = -26.69, y = -55.71, z = 1003.55},
    
    -- === SPECIAL LOCATIONS ===
    ["67"] = {id = 1, name = "Warehouse 1", x = 1412.15, y = -1.79, z = 1000.92},
    ["68"] = {id = 18, name = "Warehouse 2 (RC Shop)", x = -2240.00, y = 128.52, z = 1035.41},
    ["69"] = {id = 1, name = "Diner", x = 449.02, y = -88.99, z = 999.55},
    ["70"] = {id = 2, name = "Diner 2", x = 454.97, y = -110.10, z = 1000.08},
    ["71"] = {id = 5, name = "Crack Den", x = 318.56, y = 1115.21, z = 1083.88},
    ["72"] = {id = 3, name = "Brothel", x = 940.65, y = -18.49, z = 1000.93},
    ["73"] = {id = 5, name = "Motel Room", x = 2233.00, y = -1115.26, z = 1050.88},
    
    -- === OFFICES & BUSINESS ===
    ["74"] = {id = 3, name = "Planning Dept", x = 386.53, y = 173.63, z = 1008.38},
    ["75"] = {id = 5, name = "Driving School", x = -2027.98, y = -105.40, z = 1035.17},
    ["76"] = {id = 3, name = "Bike School", x = 1494.86, y = 1305.50, z = 1093.29},
    ["77"] = {id = 10, name = "Boat School", x = -1402.66, y = 106.39, z = 1032.27},
    ["78"] = {id = 3, name = "Airport Ticket Hall", x = -1827.14, y = 7.20, z = 1061.14},
    
    -- === SEX SHOP / ADULT ===
    ["79"] = {id = 3, name = "Sex Shop", x = -106.71, y = -20.72, z = 1000.72},
    
    -- === MANSION / LARGE HOUSES ===
    ["80"] = {id = 5, name = "Mansion (Madd Dogg)", x = 1267.84, y = -776.96, z = 1091.91},
    ["81"] = {id = 2, name = "Ryders House Large", x = 2447.87, y = -1704.45, z = 1013.51},
    
    -- === MISC ===
    ["82"] = {id = 14, name = "Kickstart Stadium", x = -1464.51, y = 1557.54, z = 1052.53},
    ["83"] = {id = 7, name = "8 Track Stadium", x = -1399.25, y = -219.28, z = 1051.25},
    ["84"] = {id = 15, name = "Blood Bowl Stadium", x = -1394.20, y = 987.62, z = 1023.96},
    ["85"] = {id = 4, name = "Dirt Track Stadium", x = -1424.93, y = -664.59, z = 1059.86},
}

--------------------------------------------------------------------------------
-- DATABASE INITIALIZATION
--------------------------------------------------------------------------------

local function initializePropertyTables()
    if not db then return end
    
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS properties (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT DEFAULT '',
            price INTEGER DEFAULT 0,
            interior_id TEXT DEFAULT '1',
            instance_dimension INTEGER DEFAULT 0,
            entrance_world_x REAL NOT NULL,
            entrance_world_y REAL NOT NULL,
            entrance_world_z REAL NOT NULL,
            entrance_dimension INTEGER DEFAULT 0,
            entrance_interior INTEGER DEFAULT 0,
            owner_type TEXT DEFAULT 'character',
            owner_id TEXT,
            owner_name TEXT,
            is_locked INTEGER DEFAULT 0,
            created_date INTEGER,
            created_by TEXT,
            for_sale INTEGER DEFAULT 1
        )
    ]])
    
    -- Migration: Add new columns if they don't exist (SQLite ignores errors for existing columns)
    -- We need to check if columns exist first
    local query = dbQuery(db, "PRAGMA table_info(properties)")
    local columns = dbPoll(query, -1)
    
    local hasOwnerType = false
    local hasOwnerID = false
    local hasIsLocked = false
    local hasOwnerCharacterID = false
    
    if columns then
        for _, col in ipairs(columns) do
            if col.name == "owner_type" then hasOwnerType = true end
            if col.name == "owner_id" then hasOwnerID = true end
            if col.name == "is_locked" then hasIsLocked = true end
            if col.name == "owner_character_id" then hasOwnerCharacterID = true end
        end
    end
    
    -- Add missing columns
    if not hasOwnerType then
        dbExec(db, "ALTER TABLE properties ADD COLUMN owner_type TEXT DEFAULT 'character'")
        outputServerLog("Added owner_type column to properties")
    end
    
    if not hasOwnerID then
        dbExec(db, "ALTER TABLE properties ADD COLUMN owner_id TEXT")
        outputServerLog("Added owner_id column to properties")
    end
    
    if not hasIsLocked then
        dbExec(db, "ALTER TABLE properties ADD COLUMN is_locked INTEGER DEFAULT 0")
        outputServerLog("Added is_locked column to properties")
    end
    
    -- Migrate old owner_character_id to owner_id if needed
    if hasOwnerCharacterID then
        dbExec(db, "UPDATE properties SET owner_id = CAST(owner_character_id AS TEXT) WHERE owner_id IS NULL AND owner_character_id IS NOT NULL")
        outputServerLog("Migrated owner_character_id to owner_id")
    end
    
    outputServerLog("Property database tables initialized")
end

addEventHandler("onResourceStart", resourceRoot, function()
    db = database
    if not db then
        outputServerLog("ERROR: Could not access database for property system")
        return
    end
    
    outputServerLog("Property system connected to database")
    outputServerLog("Available interiors: " .. getTableLength(INTERIOR_PRESETS))
    initializePropertyTables()
    loadAllProperties()
end)

function getTableLength(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

function getNextInstanceDimension()
    PropertyInstanceCounter = PropertyInstanceCounter + 1
    return 300000 + PropertyInstanceCounter
end

--------------------------------------------------------------------------------
-- PROPERTY MANAGEMENT
--------------------------------------------------------------------------------

function loadAllProperties()
    if not db then return end
    
    local query = dbQuery(db, "SELECT * FROM properties")
    local result = dbPoll(query, -1)
    
    if not result then return end
    
    for _, row in ipairs(result) do
        local interiorPreset = INTERIOR_PRESETS[row.interior_id] or INTERIOR_PRESETS["1"]
        
        -- Handle both old (owner_character_id) and new (owner_id) column names
        local ownerID = row.owner_id
        if not ownerID and row.owner_character_id then
            ownerID = tostring(row.owner_character_id)
        end
        
        local property = {
            id = row.id,
            name = row.name,
            description = row.description,
            price = row.price,
            interiorID = row.interior_id,
            interiorGTAID = interiorPreset.id,
            interiorName = interiorPreset.name,
            interiorPos = {x = interiorPreset.x, y = interiorPreset.y, z = interiorPreset.z},
            entrancePos = {x = row.entrance_world_x, y = row.entrance_world_y, z = row.entrance_world_z},
            entranceDimension = row.entrance_dimension,
            entranceInterior = row.entrance_interior,
            instanceDimension = row.instance_dimension or getNextInstanceDimension(),
            ownerType = row.owner_type or PROPERTY_OWNER_TYPE.CHARACTER,
            ownerID = ownerID,
            ownerName = row.owner_name,
            isLocked = (row.is_locked and row.is_locked == 1) or false,
            forSale = (row.for_sale == 1),
            createdDate = row.created_date,
            createdBy = row.created_by
        }
        
        Properties[property.id] = property
        spawnPropertyMarker(property.id)
        spawnPropertyBlip(property.id)
        
        if row.instance_dimension == 0 then
            dbExec(db, "UPDATE properties SET instance_dimension = ? WHERE id = ?", 
                property.instanceDimension, property.id)
        end
    end
    
    outputServerLog("Loaded " .. #result .. " properties")
end

function spawnPropertyMarker(propertyID)
    local property = Properties[propertyID]
    if not property then return false end
    
    if PropertyMarkers[propertyID] and isElement(PropertyMarkers[propertyID]) then
        destroyElement(PropertyMarkers[propertyID])
    end
    
    -- Color: Green = for sale, Red = owned unlocked, Orange = owned locked
    local markerColor
    if property.forSale then
        markerColor = {100, 200, 100}  -- Green
    elseif property.isLocked then
        markerColor = {255, 150, 50}   -- Orange
    else
        markerColor = {200, 100, 100}  -- Red
    end
    
    local marker = createMarker(
        property.entrancePos.x,
        property.entrancePos.y,
        property.entrancePos.z - 1.0,
        "cylinder",
        1.5,
        markerColor[1],
        markerColor[2],
        markerColor[3],
        100
    )
    
    if marker then
        setElementDimension(marker, property.entranceDimension)
        setElementInterior(marker, property.entranceInterior)
        setElementData(marker, "property.id", propertyID)
        setElementData(marker, "property.name", property.name)
        setElementData(marker, "property.description", property.description or "")
        setElementData(marker, "property.price", property.price)
        setElementData(marker, "property.owner", property.ownerName or "For Sale")
        setElementData(marker, "property.owner_type", property.ownerType)
        setElementData(marker, "property.for_sale", property.forSale)
        setElementData(marker, "property.is_locked", property.isLocked)
        setElementData(marker, "property.interior", property.interiorGTAID)
        
        PropertyMarkers[propertyID] = marker
    end
    
    return true
end

function spawnPropertyBlip(propertyID)
    local property = Properties[propertyID]
    if not property then return false end
    
    if PropertyBlips[propertyID] and isElement(PropertyBlips[propertyID]) then
        destroyElement(PropertyBlips[propertyID])
    end
    
    local blipIcon = property.forSale and 31 or 32
    local blipColor = property.forSale and 2 or 1
    
    local blip = createBlip(
        property.entrancePos.x,
        property.entrancePos.y,
        property.entrancePos.z,
        blipIcon,
        2,
        blipColor
    )
    
    if blip then
        setElementData(blip, "property.id", propertyID)
        setBlipVisibleDistance(blip, 300)
        PropertyBlips[propertyID] = blip
    end
    
    return true
end

function createProperty(name, description, price, interiorID, entranceX, entranceY, entranceZ, entranceDim, entranceInt, createdBy)
    if not db then return nil, "Database not available" end
    
    if not INTERIOR_PRESETS[interiorID] then
        return nil, "Invalid interior ID"
    end
    
    local preset = INTERIOR_PRESETS[interiorID]
    local propertyID = "prop_" .. getRealTime().timestamp .. "_" .. math.random(1000, 9999)
    local instanceDim = getNextInstanceDimension()
    
    local success = dbExec(db, [[
        INSERT INTO properties (id, name, description, price, interior_id, 
                               instance_dimension, entrance_world_x, entrance_world_y, entrance_world_z, 
                               entrance_dimension, entrance_interior, for_sale, created_date, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
    ]], propertyID, name, description, price, interiorID, 
        instanceDim, entranceX, entranceY, entranceZ, entranceDim or 0, entranceInt or 0, 
        getRealTime().timestamp, createdBy)
    
    if not success then return nil, "Database error" end
    
    local property = {
        id = propertyID,
        name = name,
        description = description,
        price = price,
        interiorID = interiorID,
        interiorGTAID = preset.id,
        interiorName = preset.name,
        interiorPos = {x = preset.x, y = preset.y, z = preset.z},
        entrancePos = {x = entranceX, y = entranceY, z = entranceZ},
        entranceDimension = entranceDim or 0,
        entranceInterior = entranceInt or 0,
        instanceDimension = instanceDim,
        ownerCharacterID = nil,
        ownerName = nil,
        forSale = true,
        createdDate = getRealTime().timestamp,
        createdBy = createdBy
    }
    
    Properties[propertyID] = property
    spawnPropertyMarker(propertyID)
    spawnPropertyBlip(propertyID)
    outputServerLog("Property created: " .. name .. " (ID: " .. propertyID .. ", Interior: " .. interiorID .. ")")
    
    return propertyID
end

function purchaseProperty(player, propertyID)
    local property = Properties[propertyID]
    if not property then return false, "Property not found" end
    
    if not property.forSale then return false, "Property is not for sale" end
    if property.ownerID then return false, "Property is already owned" end
    
    local playerMoney = getPlayerMoney(player)
    if playerMoney < property.price then
        return false, "Not enough money (need $" .. property.price .. ", have $" .. playerMoney .. ")"
    end
    
    local char = AccountManager and AccountManager:getActiveCharacter(player)
    if not char then return false, "No active character" end
    
    takePlayerMoney(player, property.price)
    
    property.ownerType = PROPERTY_OWNER_TYPE.CHARACTER
    property.ownerID = tostring(char.id)
    property.ownerName = char.name
    property.forSale = false
    property.isLocked = false
    
    dbExec(db, [[
        UPDATE properties SET owner_type = ?, owner_id = ?, owner_name = ?, for_sale = 0, is_locked = 0 WHERE id = ?
    ]], PROPERTY_OWNER_TYPE.CHARACTER, tostring(char.id), char.name, propertyID)
    
    spawnPropertyMarker(propertyID)
    spawnPropertyBlip(propertyID)
    
    outputServerLog(char.name .. " purchased property: " .. property.name .. " for $" .. property.price)
    
    return true, "Property purchased: " .. property.name
end

function teleportToPropertyInterior(player, propertyID)
    local property = Properties[propertyID]
    if not property then return false, "Property not found" end
    
    -- Check if player can access this property
    if not canAccessProperty(player, propertyID) then
        return false, "This property is locked"
    end
    
    -- Store entrance position so player can return
    setElementData(player, "property.entrance.x", property.entrancePos.x)
    setElementData(player, "property.entrance.y", property.entrancePos.y)
    setElementData(player, "property.entrance.z", property.entrancePos.z)
    setElementData(player, "property.entrance.dim", property.entranceDimension)
    setElementData(player, "property.entrance.int", property.entranceInterior)
    setElementData(player, "property.current", propertyID)
    
    -- Teleport to interior
    setElementInterior(player, property.interiorGTAID)
    setElementDimension(player, property.instanceDimension)
    setElementPosition(player, property.interiorPos.x, property.interiorPos.y, property.interiorPos.z)
    
    -- Fix camera
    setTimer(function()
        if isElement(player) then
            setCameraTarget(player, player)
            fadeCamera(player, true, 0.5)
        end
    end, 100, 1)
    
    return true
end

function teleportToPropertyEntrance(player, propertyID)
    local property = Properties[propertyID]
    if not property then 
        -- Try to use stored entrance data
        local ex = getElementData(player, "property.entrance.x")
        local ey = getElementData(player, "property.entrance.y")
        local ez = getElementData(player, "property.entrance.z")
        local eDim = getElementData(player, "property.entrance.dim")
        local eInt = getElementData(player, "property.entrance.int")
        
        if ex and ey and ez then
            setElementPosition(player, ex, ey, ez)
            setElementInterior(player, eInt or 0)
            setElementDimension(player, eDim or 0)
            
            -- Clear stored data
            setElementData(player, "property.entrance.x", nil)
            setElementData(player, "property.entrance.y", nil)
            setElementData(player, "property.entrance.z", nil)
            setElementData(player, "property.entrance.dim", nil)
            setElementData(player, "property.entrance.int", nil)
            setElementData(player, "property.current", nil)
            
            setTimer(function()
                if isElement(player) then
                    setCameraTarget(player, player)
                    fadeCamera(player, true, 0.5)
                end
            end, 100, 1)
            
            return true
        end
        return false, "Property not found"
    end
    
    setElementPosition(player, property.entrancePos.x, property.entrancePos.y, property.entrancePos.z)
    setElementInterior(player, property.entranceInterior)
    setElementDimension(player, property.entranceDimension)
    
    -- Clear stored data
    setElementData(player, "property.current", nil)
    
    setTimer(function()
        if isElement(player) then
            setCameraTarget(player, player)
            fadeCamera(player, true, 0.5)
        end
    end, 100, 1)
    
    return true
end

function deleteProperty(propertyID)
    if not db then return false end
    if not Properties[propertyID] then return false end
    
    if PropertyMarkers[propertyID] and isElement(PropertyMarkers[propertyID]) then
        destroyElement(PropertyMarkers[propertyID])
        PropertyMarkers[propertyID] = nil
    end
    
    if PropertyBlips[propertyID] and isElement(PropertyBlips[propertyID]) then
        destroyElement(PropertyBlips[propertyID])
        PropertyBlips[propertyID] = nil
    end
    
    dbExec(db, "DELETE FROM properties WHERE id = ?", propertyID)
    Properties[propertyID] = nil
    
    outputServerLog("Property deleted: " .. propertyID)
    return true
end

--------------------------------------------------------------------------------
-- SERVER EVENTS
--------------------------------------------------------------------------------

addEvent("property:waypoint:clicked", true)
addEventHandler("property:waypoint:clicked", root, function(propertyID)
    local player = client
    local property = Properties[propertyID]
    
    if not property then
        outputChatBox("Property not found", player, 255, 0, 0)
        return
    end
    
    if property.ownerName and property.ownerName ~= getElementData(player, "character.name") then
        outputChatBox("This property is owned by " .. property.ownerName, player, 255, 0, 0)
        return
    end
    
    if property.forSale then
        outputChatBox("Property: " .. property.name, player, 0, 255, 0)
        outputChatBox("Interior: " .. property.interiorName, player, 0, 255, 0)
        outputChatBox("Price: $" .. property.price, player, 0, 255, 0)
        outputChatBox("Type /buyproperty to purchase", player, 255, 255, 0)
        setElementData(player, "currentProperty", propertyID)
        return
    end
    
    local success = teleportToPropertyInterior(player, propertyID)
    if success then
        outputChatBox("Entered: " .. property.name, player, 0, 255, 0)
        outputChatBox("Type /exitproperty to leave", player, 200, 200, 200)
    end
end)

addEvent("property:marker:interact", true)
addEventHandler("property:marker:interact", root, function(propertyID)
    local player = client
    local property = Properties[propertyID]
    
    if not property then
        outputChatBox("Property not found", player, 255, 0, 0)
        return
    end
    
    if property.ownerName and property.ownerName ~= getElementData(player, "character.name") then
        outputChatBox("This property is owned by " .. property.ownerName, player, 255, 0, 0)
        return
    end
    
    if property.forSale then
        outputChatBox("Property: " .. property.name, player, 0, 255, 0)
        outputChatBox("Interior: " .. property.interiorName, player, 0, 255, 0)
        outputChatBox("Price: $" .. property.price, player, 0, 255, 0)
        outputChatBox("Type /buyproperty to purchase", player, 255, 255, 0)
        setElementData(player, "currentProperty", propertyID)
        return
    end
    
    local success = teleportToPropertyInterior(player, propertyID)
    if success then
        outputChatBox("Entered: " .. property.name, player, 0, 255, 0)
        outputChatBox("Type /exitproperty to leave", player, 200, 200, 200)
    end
end)

--------------------------------------------------------------------------------
-- COMMANDS
--------------------------------------------------------------------------------

addCommandHandler("createproperty", function(player, cmd, name, price, interiorID)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not name or not price then
        outputChatBox("Usage: /createproperty \"Property Name\" price [InteriorID]", player, 255, 255, 0)
        outputChatBox("Type /listinteriors [search] for available interior IDs", player, 150, 150, 200)
        return
    end
    
    price = tonumber(price) or 0
    interiorID = interiorID or "1"
    
    if not INTERIOR_PRESETS[interiorID] then
        outputChatBox("Invalid interior ID. Type /listinteriors for list", player, 255, 0, 0)
        return
    end
    
    local x, y, z = getElementPosition(player)
    local dim = getElementDimension(player)
    local int = getElementInterior(player)
    local createdBy = getElementData(player, "character.name") or getPlayerName(player)
    
    local propertyID = createProperty(name, "", price, interiorID, x, y, z, dim, int, createdBy)
    
    if propertyID then
        local preset = INTERIOR_PRESETS[interiorID]
        outputChatBox("Property created: " .. name, player, 0, 255, 0)
        outputChatBox("ID: " .. propertyID .. " | Interior: " .. interiorID .. " (" .. preset.name .. ")", player, 0, 255, 0)
    else
        outputChatBox("Failed to create property", player, 255, 0, 0)
    end
end)

addCommandHandler("listinteriors", function(player, cmd, searchTerm)
    outputChatBox("=== Available Interior IDs ===", player, 255, 255, 0)
    
    local count = 0
    local sorted = {}
    
    for id, data in pairs(INTERIOR_PRESETS) do
        if not searchTerm or data.name:lower():find(searchTerm:lower(), 1, true) then
            table.insert(sorted, {id = id, data = data})
        end
    end
    
    table.sort(sorted, function(a, b) return tonumber(a.id) < tonumber(b.id) end)
    
    for _, item in ipairs(sorted) do
        outputChatBox(string.format("[%s] %s (GTA Int: %d)", item.id, item.data.name, item.data.id), player, 200, 200, 255)
        count = count + 1
        if count >= 20 then
            outputChatBox("... and more. Use /listinteriors [search] to filter.", player, 150, 150, 150)
            break
        end
    end
    
    if count == 0 then
        outputChatBox("No interiors found matching '" .. (searchTerm or "") .. "'", player, 255, 0, 0)
    end
end)

addCommandHandler("listproperties", function(player)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    outputChatBox("=== Properties ===", player, 255, 255, 0)
    
    local count = 0
    for id, property in pairs(Properties) do
        local status = property.forSale and "FOR SALE" or ("OWNED by " .. property.ownerName)
        outputChatBox(string.format("%s - $%d (%s)", property.name, property.price, status), player, 255, 255, 255)
        outputChatBox("  ID: " .. id .. " | Interior: " .. property.interiorID .. " (" .. property.interiorName .. ")", player, 180, 180, 180)
        count = count + 1
    end
    
    if count == 0 then
        outputChatBox("No properties created", player, 200, 200, 200)
    end
end)

addCommandHandler("buyproperty", function(player)
    local propertyID = getElementData(player, "currentProperty")
    if not propertyID then
        outputChatBox("You must be at a property entrance first", player, 255, 0, 0)
        return
    end
    
    local success, msg = purchaseProperty(player, propertyID)
    
    if success then
        outputChatBox(msg, player, 0, 255, 0)
        setElementData(player, "currentProperty", nil)
    else
        outputChatBox("Cannot purchase: " .. msg, player, 255, 0, 0)
    end
end)

addCommandHandler("exitproperty", function(player)
    local currentProp = getElementData(player, "property.current")
    
    if currentProp then
        teleportToPropertyEntrance(player, currentProp)
        outputChatBox("Exited property", player, 0, 255, 0)
        return
    end
    
    -- Fallback: check by dimension
    for id, property in pairs(Properties) do
        if getElementDimension(player) == property.instanceDimension then
            teleportToPropertyEntrance(player, id)
            outputChatBox("Exited property", player, 0, 255, 0)
            return
        end
    end
    
    outputChatBox("You are not inside a property", player, 255, 0, 0)
end)

addCommandHandler("deleteproperty", function(player, cmd, propertyID)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not propertyID then
        outputChatBox("Usage: /deleteproperty propertyID", player, 255, 255, 0)
        return
    end
    
    if deleteProperty(propertyID) then
        outputChatBox("Property deleted", player, 0, 255, 0)
    else
        outputChatBox("Property not found", player, 255, 0, 0)
    end
end)

addCommandHandler("gotoproperty", function(player, cmd, propertyID)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not propertyID then
        outputChatBox("Usage: /gotoproperty propertyID", player, 255, 255, 0)
        return
    end
    
    local property = Properties[propertyID]
    if not property then
        outputChatBox("Property not found", player, 255, 0, 0)
        return
    end
    
    setElementPosition(player, property.entrancePos.x, property.entrancePos.y, property.entrancePos.z)
    setElementInterior(player, property.entranceInterior)
    setElementDimension(player, property.entranceDimension)
    outputChatBox("Teleported to: " .. property.name, player, 0, 255, 0)
end)

addCommandHandler("enterinterior", function(player, cmd, interiorID)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not interiorID then
        outputChatBox("Usage: /enterinterior [interiorID]", player, 255, 255, 0)
        return
    end
    
    local preset = INTERIOR_PRESETS[interiorID]
    if not preset then
        outputChatBox("Invalid interior ID", player, 255, 0, 0)
        return
    end
    
    -- Store current position for return
    local x, y, z = getElementPosition(player)
    setElementData(player, "dm.return.x", x)
    setElementData(player, "dm.return.y", y)
    setElementData(player, "dm.return.z", z)
    setElementData(player, "dm.return.int", getElementInterior(player))
    setElementData(player, "dm.return.dim", getElementDimension(player))
    
    setElementInterior(player, preset.id)
    setElementDimension(player, 0)
    setElementPosition(player, preset.x, preset.y, preset.z)
    
    setTimer(function()
        if isElement(player) then
            setCameraTarget(player, player)
        end
    end, 100, 1)
    
    outputChatBox("Entered: " .. preset.name .. " (Interior ID: " .. preset.id .. ")", player, 0, 255, 0)
    outputChatBox("Type /exitinterior to return", player, 200, 200, 200)
end)

addCommandHandler("exitinterior", function(player)
    local x = getElementData(player, "dm.return.x")
    local y = getElementData(player, "dm.return.y")
    local z = getElementData(player, "dm.return.z")
    
    if not x then
        outputChatBox("No return position stored", player, 255, 0, 0)
        return
    end
    
    setElementPosition(player, x, y, z)
    setElementInterior(player, getElementData(player, "dm.return.int") or 0)
    setElementDimension(player, getElementData(player, "dm.return.dim") or 0)
    
    setElementData(player, "dm.return.x", nil)
    setElementData(player, "dm.return.y", nil)
    setElementData(player, "dm.return.z", nil)
    setElementData(player, "dm.return.int", nil)
    setElementData(player, "dm.return.dim", nil)
    
    outputChatBox("Returned to previous location", player, 0, 255, 0)
end)

--------------------------------------------------------------------------------
-- PROPERTY ACCESS & OWNERSHIP FUNCTIONS
--------------------------------------------------------------------------------

--- Check if a player can access a property
-- @param player element Player to check
-- @param propertyID string Property ID
-- @return boolean Can access
function canAccessProperty(player, propertyID)
    local property = Properties[propertyID]
    if not property then return false end
    
    -- For sale properties are always accessible
    if property.forSale then return true end
    
    -- Unlocked properties are accessible
    if not property.isLocked then return true end
    
    -- DMs can always access
    if isDungeonMaster and isDungeonMaster(player) then return true end
    
    -- Check ownership
    return isPropertyOwner(player, propertyID)
end

--- Check if a player owns a property
-- @param player element Player to check
-- @param propertyID string Property ID
-- @return boolean Is owner
function isPropertyOwner(player, propertyID)
    local property = Properties[propertyID]
    if not property then return false end
    if not property.ownerID then return false end
    
    if property.ownerType == PROPERTY_OWNER_TYPE.CHARACTER then
        -- Check character ownership
        local char = AccountManager and AccountManager:getActiveCharacter(player)
        if char and tostring(char.id) == tostring(property.ownerID) then
            return true
        end
    elseif property.ownerType == PROPERTY_OWNER_TYPE.COMPANY then
        -- Check if player owns the company
        if Companies then
            local company = Companies[property.ownerID]
            if company and company.ownerType == "player" then
                local char = AccountManager and AccountManager:getActiveCharacter(player)
                if char and tostring(char.id) == tostring(company.ownerID) then
                    return true
                end
            end
        end
    end
    
    return false
end

--- Lock a property
-- @param propertyID string Property ID
-- @return boolean Success
function lockProperty(propertyID)
    local property = Properties[propertyID]
    if not property then return false end
    
    property.isLocked = true
    dbExec(db, "UPDATE properties SET is_locked = 1 WHERE id = ?", propertyID)
    spawnPropertyMarker(propertyID)
    
    return true
end

--- Unlock a property
-- @param propertyID string Property ID
-- @return boolean Success
function unlockProperty(propertyID)
    local property = Properties[propertyID]
    if not property then return false end
    
    property.isLocked = false
    dbExec(db, "UPDATE properties SET is_locked = 0 WHERE id = ?", propertyID)
    spawnPropertyMarker(propertyID)
    
    return true
end

--- Set property description
-- @param propertyID string Property ID
-- @param description string New description
-- @return boolean Success
function setPropertyDescription(propertyID, description)
    local property = Properties[propertyID]
    if not property then return false end
    
    property.description = description
    dbExec(db, "UPDATE properties SET description = ? WHERE id = ?", description, propertyID)
    spawnPropertyMarker(propertyID)
    
    return true
end

--- Transfer property to new owner
-- @param propertyID string Property ID
-- @param newOwnerType string "character" or "company"
-- @param newOwnerID string Character ID or Company ID
-- @param newOwnerName string Display name for owner
-- @return boolean Success
-- @return string Message
function transferProperty(propertyID, newOwnerType, newOwnerID, newOwnerName)
    local property = Properties[propertyID]
    if not property then return false, "Property not found" end
    
    -- Validate owner type
    if newOwnerType ~= PROPERTY_OWNER_TYPE.CHARACTER and newOwnerType ~= PROPERTY_OWNER_TYPE.COMPANY then
        return false, "Invalid owner type"
    end
    
    -- Update property
    property.ownerType = newOwnerType
    property.ownerID = newOwnerID
    property.ownerName = newOwnerName
    property.forSale = false
    
    dbExec(db, [[
        UPDATE properties SET 
            owner_type = ?, owner_id = ?, owner_name = ?, for_sale = 0 
        WHERE id = ?
    ]], newOwnerType, newOwnerID, newOwnerName, propertyID)
    
    spawnPropertyMarker(propertyID)
    spawnPropertyBlip(propertyID)
    
    outputServerLog("Property " .. property.name .. " transferred to " .. newOwnerName .. " (" .. newOwnerType .. ")")
    
    return true, "Property transferred to " .. newOwnerName
end

--- Get properties owned by a character
-- @param characterID number Character ID
-- @return table Array of property IDs
function getCharacterProperties(characterID)
    local owned = {}
    for propID, property in pairs(Properties) do
        if property.ownerType == PROPERTY_OWNER_TYPE.CHARACTER and 
           tostring(property.ownerID) == tostring(characterID) then
            table.insert(owned, propID)
        end
    end
    return owned
end

--- Get properties owned by a company
-- @param companyID string Company ID
-- @return table Array of property IDs
function getCompanyProperties(companyID)
    local owned = {}
    for propID, property in pairs(Properties) do
        if property.ownerType == PROPERTY_OWNER_TYPE.COMPANY and 
           property.ownerID == companyID then
            table.insert(owned, propID)
        end
    end
    return owned
end

--------------------------------------------------------------------------------
-- PLAYER PROPERTY COMMANDS
--------------------------------------------------------------------------------

local PROPERTY_INTERACT_DISTANCE = 10.0

-- Helper: Find property player is in or near
function findPlayerProperty(player)
    -- First check if inside a property
    local insideID = getElementData(player, "property.current")
    if insideID then
        return insideID, true  -- propertyID, isInside
    end
    
    -- Check for nearby property entrance
    local px, py, pz = getElementPosition(player)
    local pDim = getElementDimension(player)
    local pInt = getElementInterior(player)
    
    local nearestID = nil
    local nearestDist = PROPERTY_INTERACT_DISTANCE
    
    for propID, marker in pairs(PropertyMarkers) do
        if isElement(marker) then
            if getElementDimension(marker) == pDim and getElementInterior(marker) == pInt then
                local mx, my, mz = getElementPosition(marker)
                local dist = getDistanceBetweenPoints3D(px, py, pz, mx, my, mz)
                if dist < nearestDist then
                    nearestDist = dist
                    nearestID = propID
                end
            end
        end
    end
    
    return nearestID, false  -- propertyID, isInside
end

-- Lock property
addCommandHandler("lockproperty", function(player)
    local propertyID, isInside = findPlayerProperty(player)
    if not propertyID then
        outputChatBox("No property nearby", player, 255, 100, 100)
        return
    end
    
    if not isPropertyOwner(player, propertyID) then
        outputChatBox("You don't own this property", player, 255, 100, 100)
        return
    end
    
    lockProperty(propertyID)
    local property = Properties[propertyID]
    outputChatBox(property.name .. " locked", player, 0, 255, 0)
end)

-- Unlock property
addCommandHandler("unlockproperty", function(player)
    local propertyID, isInside = findPlayerProperty(player)
    if not propertyID then
        outputChatBox("No property nearby", player, 255, 100, 100)
        return
    end
    
    if not isPropertyOwner(player, propertyID) then
        outputChatBox("You don't own this property", player, 255, 100, 100)
        return
    end
    
    unlockProperty(propertyID)
    local property = Properties[propertyID]
    outputChatBox(property.name .. " unlocked", player, 0, 255, 0)
end)

-- Set property description
addCommandHandler("propdesc", function(player, cmd, ...)
    local propertyID, isInside = findPlayerProperty(player)
    if not propertyID then
        outputChatBox("No property nearby", player, 255, 100, 100)
        return
    end
    
    if not isPropertyOwner(player, propertyID) then
        outputChatBox("You don't own this property", player, 255, 100, 100)
        return
    end
    
    local description = table.concat({...}, " ")
    if description == "" then
        outputChatBox("Usage: /propdesc <description>", player, 255, 255, 0)
        return
    end
    
    setPropertyDescription(propertyID, description)
    local property = Properties[propertyID]
    outputChatBox(property.name .. " description updated", player, 0, 255, 0)
end)

-- Transfer property to company
addCommandHandler("transferproperty", function(player, cmd, companyID)
    local propertyID, isInside = findPlayerProperty(player)
    if not propertyID then
        outputChatBox("No property nearby", player, 255, 100, 100)
        return
    end
    
    if not isPropertyOwner(player, propertyID) then
        outputChatBox("You don't own this property", player, 255, 100, 100)
        return
    end
    
    if not companyID then
        outputChatBox("Usage: /transferproperty <companyID or 'me'>", player, 255, 255, 0)
        return
    end
    
    local property = Properties[propertyID]
    
    if companyID == "me" then
        -- Transfer back to character
        local char = AccountManager and AccountManager:getActiveCharacter(player)
        if not char then
            outputChatBox("No active character", player, 255, 0, 0)
            return
        end
        
        local success, msg = transferProperty(propertyID, PROPERTY_OWNER_TYPE.CHARACTER, tostring(char.id), char.name)
        outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
    else
        -- Transfer to company
        if not Companies or not Companies[companyID] then
            outputChatBox("Company not found", player, 255, 0, 0)
            return
        end
        
        local company = Companies[companyID]
        
        -- Verify player owns the company
        local char = AccountManager and AccountManager:getActiveCharacter(player)
        if not char or company.ownerType ~= "player" or tostring(company.ownerID) ~= tostring(char.id) then
            outputChatBox("You don't own that company", player, 255, 0, 0)
            return
        end
        
        local success, msg = transferProperty(propertyID, PROPERTY_OWNER_TYPE.COMPANY, companyID, company.name)
        outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
    end
end)

--------------------------------------------------------------------------------
-- DM PROPERTY OWNER COMMAND
--------------------------------------------------------------------------------

addCommandHandler("setpropertyowner", function(player, cmd, propertyID, ownerType, ownerID)
    if isDungeonMaster and not isDungeonMaster(player) then
        outputChatBox("DM required", player, 255, 0, 0)
        return
    end
    
    if not propertyID or not ownerType then
        outputChatBox("Usage: /setpropertyowner propertyID character/company ownerID", player, 255, 255, 0)
        return
    end
    
    local property = Properties[propertyID]
    if not property then
        outputChatBox("Property not found", player, 255, 0, 0)
        return
    end
    
    local ownerName = "Unknown"
    
    if ownerType == "character" then
        -- Look up character name
        if AccountManager then
            local query = dbQuery(db, "SELECT name FROM characters WHERE id = ?", tonumber(ownerID))
            local result = dbPoll(query, -1)
            if result and result[1] then
                ownerName = result[1].name
            end
        end
    elseif ownerType == "company" then
        if Companies and Companies[ownerID] then
            ownerName = Companies[ownerID].name
        end
    else
        outputChatBox("Owner type must be 'character' or 'company'", player, 255, 0, 0)
        return
    end
    
    local success, msg = transferProperty(propertyID, ownerType, ownerID, ownerName)
    outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
end)

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

addEventHandler("onResourceStop", resourceRoot, function()
    for _, marker in pairs(PropertyMarkers) do
        if isElement(marker) then destroyElement(marker) end
    end
    
    for _, blip in pairs(PropertyBlips) do
        if isElement(blip) then destroyElement(blip) end
    end
end)

outputServerLog("===== PROPERTY_SYSTEM.LUA LOADED =====")

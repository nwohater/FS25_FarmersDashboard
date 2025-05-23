-- ✅ Enhanced DataExporter.lua with field growth details and special offers

print("✅ DataExporter.lua loaded!")

DataExporter = {}
DataExporter.timer = 0
DataExporter.brandCache = {}

addModEventListener(DataExporter)

local monthNames = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
}


local WEATHER_CONDITIONS = {
    [0] = "Clear",
    [1] = "Sunny",
    [2] = "Partly Cloudy",
    [3] = "Cloudy",
    [4] = "Storm",
    [5] = "Snow",
    [6] = "Fog",
    [7] = "Windy"
}

function DataExporter:loadMap(name)
    print("DataExporter: Mod loaded — writing JSON every 2 real minutes.")
end

function DataExporter:update(dt)
    self.timer = self.timer + dt
    if self.timer >= 120000 then
        self:writeJSON()
        self.timer = 0
    end
end

function DataExporter:escape(str)
    return str and tostring(str):gsub('"', '\\"') or ""
end


function DataExporter:getBrandTitle(brandRaw)
    if not brandRaw or brandRaw == "" then
        return "(Unknown Brand)"
    end

    local raw = brandRaw:lower():gsub("^%s*(.-)%s*$", "%1")  -- trim and lowercase

    if self.brandCache[raw] then
        return self.brandCache[raw]
    end

    for _, brandItem in pairs(g_brandManager.indexToBrand) do
        if brandItem and brandItem.name and brandItem.title then
            local candidate = brandItem.name:lower():gsub("^%s*(.-)%s*$", "%1")
            if candidate == raw then
                self.brandCache[raw] = brandItem.title
                return brandItem.title
            end
        end
    end

    self.brandCache[raw] = "(Unknown Brand)"
    return "(Unknown Brand)"
end

function DataExporter:getSpecialOffers()
    local offers = {}
    if not g_currentMission or not g_currentMission.vehicleSaleSystem then return offers end

    for _, saleItem in ipairs(g_currentMission.vehicleSaleSystem.items) do
        local xml = saleItem.xmlFilename
        local matchedStoreItem = nil

        -- Manually search for store item match (more reliable)
        for _, storeItem in pairs(g_storeManager.items) do
            if storeItem.xmlFilename == xml then
                matchedStoreItem = storeItem
                break
            end
        end

        if matchedStoreItem then
            local brandRaw = matchedStoreItem.brandNameRaw or ""
            local brand = self:getBrandTitle(brandRaw)
            local name = matchedStoreItem.name or "(Unknown Name)"
            local price = saleItem.price or 0
            local originalPrice = matchedStoreItem.price or price
            local percentOff = originalPrice > 0 and math.floor(((originalPrice - price) / originalPrice) * 100 + 0.5) or 0
            local age = saleItem.age or 0

            table.insert(offers, string.format([[{
      "brand": "%s",
      "name": "%s",
      "price": %.2f,
      "originalPrice": %.2f,
      "percentOff": %d,
      "age": %d
    }]], self:escape(brand), self:escape(name), price, originalPrice, percentOff, age))
        end
    end

    return table.concat(offers, ",\n    ")
end


-- function DataExporter:getFieldsFromXML()
--     local fields = {}
--     local saveIndex = g_currentMission.missionInfo.savegameIndex or 1
--     local fieldsFilePath = string.format("%ssavegame%d/fields.xml", getUserProfileAppPath(), saveIndex)
--     local xmlFile = loadXMLFile("fieldsXML", fieldsFilePath)

--     if xmlFile ~= nil then
--         local i = 0
--         while true do
--             local key = string.format("fields.field(%d)", i)
--             if not hasXMLProperty(xmlFile, key) then break end

--             local id = getXMLInt(xmlFile, key .. "#id") or -1
--             local fruitType = getXMLString(xmlFile, key .. "#fruitType") or "UNKNOWN"
--             local growthState = getXMLInt(xmlFile, key .. "#growthState") or 0
--             local weedState = getXMLInt(xmlFile, key .. "#weedState") or 0
--             local groundType = getXMLString(xmlFile, key .. "#groundType") or "UNKNOWN"

--             table.insert(fields, string.format([[{
--       "fieldId": %d,
--       "fruitType": "%s",
--       "growthState": %d,
--       "weedState": %d,
--       "groundType": "%s"
--     }]], id, self:escape(fruitType), growthState, weedState, self:escape(groundType)))

--             i = i + 1
--         end
--         delete(xmlFile)
--     else
--         print("❌ DataExporter: Could not read fields.xml from savegame.")
--     end

--     return table.concat(fields, ",\n    ")
-- end

function DataExporter:getFieldsFromXML()
    local fields = {}
    local saveIndex = g_currentMission.missionInfo.savegameIndex or 1
    local fieldsFilePath = string.format("%ssavegame%d/fields.xml", getUserProfileAppPath(), saveIndex)
    local farmlandsFilePath = string.format("%ssavegame%d/farmland.xml", getUserProfileAppPath(), saveIndex)

    -- Load farmlandId → farmId map
    local farmlandToFarmId = {}
    local farmlandXML = loadXMLFile("farmlandXML", farmlandsFilePath)
    if farmlandXML ~= nil then
        local i = 0
        while true do
            local key = string.format("farmlands.farmland(%d)", i)
            if not hasXMLProperty(farmlandXML, key) then break end
            local farmlandId = getXMLInt(farmlandXML, key .. "#id")
            local farmId = getXMLInt(farmlandXML, key .. "#farmId") or 0
            farmlandToFarmId[farmlandId] = farmId
            i = i + 1
        end
        delete(farmlandXML)
    else
        print("❌ DataExporter: Could not read farmland.xml")
    end

    -- Load fields and enrich with farm info
    local fieldsXML = loadXMLFile("fieldsXML", fieldsFilePath)
    if fieldsXML ~= nil then
        local i = 0
        while true do
            local key = string.format("fields.field(%d)", i)
            if not hasXMLProperty(fieldsXML, key) then break end

            local fieldId = getXMLInt(fieldsXML, key .. "#id") or -1
            local fruitType = getXMLString(fieldsXML, key .. "#fruitType") or "UNKNOWN"
            local growthState = getXMLInt(fieldsXML, key .. "#growthState") or 0
            local weedState = getXMLInt(fieldsXML, key .. "#weedState") or 0
            local groundType = getXMLString(fieldsXML, key .. "#groundType") or "UNKNOWN"
            local farmlandId = getXMLInt(fieldsXML, key .. "#farmlandId") or -1

            local farmId = farmlandToFarmId[farmlandId] or 0
            local farmName = "(Unowned)"
            if g_farmManager and g_farmManager.farms and g_farmManager.farms[farmId] then
                farmName = g_farmManager.farms[farmId].name or "(Unnamed)"
            end

            table.insert(fields, string.format([[{
      "fieldId": %d,
      "fruitType": "%s",
      "growthState": %d,
      "weedState": %d,
      "groundType": "%s",
      "farmId": %d,
      "farmName": "%s"
    }]], fieldId, self:escape(fruitType), growthState, weedState, self:escape(groundType), farmId, self:escape(farmName)))

            i = i + 1
        end
        delete(fieldsXML)
    else
        print("❌ DataExporter: Could not read fields.xml")
    end

    return table.concat(fields, ",\n    ")
end



-- Convert Celsius to Fahrenheit
local function celsiusToFahrenheit(c)
    return (c * 9 / 5) + 32
end


local function buildForecast(env)
    local forecastStrs = {}
    if not env or not env.weather or not env.weather.getNextWeatherType then
        return ""
    end

    local baseTime = env.dayTime
    local forecastStep = 3 * 60 * 60 * 1000  -- 3 in-game hours in ms

    for i = 1, 4 do
        local forecastTime = baseTime + (i * forecastStep)
        local day, timeOfDay = env:getDayAndDayTime(forecastTime, env.currentMonotonicDay)

        local nextWeather = env.weather:getNextWeatherType(forecastTime, day)
        if type(nextWeather) == "number" then
            local forecastHour = math.floor((timeOfDay / (60 * 60 * 1000)))
            local condition = WEATHER_CONDITIONS[nextWeather] or "Unknown"

            table.insert(forecastStrs, string.format([[{
      "hour": "%02d:00",
      "condition": "%s"
    }]], forecastHour, condition))
        end
    end

    return table.concat(forecastStrs, ",\n    ")
end





function DataExporter:writeJSON()
    local env = g_currentMission and g_currentMission.environment
    if not env then
        print("DataExporter: Environment not available.")
        return
    end

    local currentDay = env.currentDay or 1
    local hour = env.currentHour or 0
    local minute = env.currentMinute or 0
    local daysPerMonth = env.daysPerPeriod or 3

    local startMonth = env.startMonth
    if not startMonth or startMonth < 1 or startMonth > 12 then
        print("⚠️ DataExporter: Invalid or missing startMonth, defaulting to March (3)")
        startMonth = 3
    end

    local monthsPassed = math.floor((currentDay - 1) / daysPerMonth)
    local month = ((startMonth - 1 + monthsPassed) % 12) + 1
    local dayInMonth = ((currentDay - 1) % daysPerMonth) + 1
    local monthName = monthNames[month] or "Unknown"

    local weatherCondition = "Unknown"
    local temperatureC = 0
    local temperatureF = 0
    local forecastJSON = ""

    if env.weather then
        local currentWeatherType = env.weather:getCurrentWeatherType()
        local weatherId = nil

        if type(currentWeatherType) == "table" then
            weatherId = currentWeatherType.id
        elseif type(currentWeatherType) == "number" then
            weatherId = currentWeatherType
        end

        if weatherId ~= nil then
            weatherCondition = WEATHER_CONDITIONS[weatherId] or "Unknown"
        else
            print("⚠️ DataExporter: getCurrentWeatherType() returned invalid type:", type(currentWeatherType))
        end

        print(string.format("🧪 Weather ID: %s → %s", tostring(weatherId), weatherCondition))
        print("🧪 getCurrentWeatherType() returned:", currentWeatherType)

        temperatureC = env.weather:getCurrentTemperature() or 0
        temperatureF = celsiusToFahrenheit(temperatureC)
        forecastJSON = buildForecast(env)
    end


    local farmsJSON = ""
    if g_farmManager and g_farmManager.farms then
        local farmParts = {}
        for farmId, farm in pairs(g_farmManager.farms) do
            local name = self:escape(farm.name or ("Unnamed Farm"))
            local money = tonumber(farm.money or 0)
            local isPlayer = (g_currentMission:getFarmId() == farmId)
            table.insert(farmParts, string.format([[{
      "farmId": %d,
      "name": "%s",
      "money": %.2f,
      "isPlayerFarm": %s
    }]], farmId, name, money, tostring(isPlayer)))
        end
        farmsJSON = table.concat(farmParts, ",\n    ")
    end

    local offersJSON = self:getSpecialOffers()
    local fieldsJSON = self:getFieldsFromXML()


    local jsonString = string.format([[{
  "time": "%02d:%02d",
  "date": {
    "day": %d,
    "month": %d,
    "monthName": "%s"
  },
  "weather": {
    "condition": "%s",
    "temperatureF": %.1f,
    "forecast": [
  %s
    ]
  },
  "farms": [
    %s
  ],
  "fields": [
    %s
  ],
  "specialOffers": [
    %s
  ],
  "metadata": {
    "generatedBy": "DataExporterMod",
    "version": "1.0",
    "updatedAt": "Day %d, %02d:%02d"
  }
}]], hour, minute, dayInMonth, month, self:escape(monthName),
      self:escape(weatherCondition), temperatureF, forecastJSON, farmsJSON, fieldsJSON, offersJSON, currentDay, hour, minute)

    local filePath = getUserProfileAppPath() .. "farmersDB.json"
    local file = io.open(filePath, "w")
    if file then
        file:write(jsonString)
        file:close()
        print("✅ DataExporter: JSON written at in-game time " .. string.format("%02d:%02d", hour, minute))
    else
        print("❌ DataExporter: Failed to write file.")
    end
end

function DataExporter:deleteMap()
    print("DataExporter: Mod unloaded.")
end

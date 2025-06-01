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
    --if not g_currentMission:getIsServer() then
    --    print("DataExporter: Client instance detected - mod disabled.")
    --    DataExporter = nil
    --    return
    --end
    print("DataExporter: Mod loaded — writing JSON every 5 real minutes.")
    self:linkFarmlandsToFields()
    self:loadFarmInfo()
end

function DataExporter:linkFarmlandsToFields()
    local farmlandMap = {}
    for _, farmland in pairs(g_farmlandManager.farmlands) do
        farmlandMap[farmland.id] = farmland
    end

    for _, field in pairs(g_fieldManager.fields) do
        local farmlandId = field.farmlandId
        if farmlandMap[farmlandId] ~= nil then
            farmlandMap[farmlandId].field = field
        end
    end
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

function DataExporter:loadFarmInfo()
    local saveIndex = g_currentMission.missionInfo.savegameIndex or 1
    local farmsFilePath = string.format("%ssavegame%d/farms.xml", getUserProfileAppPath(), saveIndex)
    local farmInfoMap = {}
    local farmsXML = loadXMLFile("farmsXML", farmsFilePath)
    if farmsXML ~= nil then
        local i = 0
        while true do
            local key = string.format("farms.farm(%d)", i)
            if not hasXMLProperty(farmsXML, key) then break end

            local farmId = getXMLInt(farmsXML, key .. "#farmId") or 0
            local name = getXMLString(farmsXML, key .. "#name") or "(Unnamed)"
            local loan = getXMLFloat(farmsXML, key .. "#loan") or 0

            farmInfoMap[farmId] = { name = name, loan = loan }
            i = i + 1
        end
        delete(farmsXML)
    else
        print("❌ DataExporter: Could not read farms.xml")
    end

    self.farmInfoMap = farmInfoMap
end

function DataExporter:getSpecialOffers()
    local offers = {}
    if not g_currentMission or not g_currentMission.vehicleSaleSystem then return offers end
    for _, saleItem in ipairs(g_currentMission.vehicleSaleSystem.items) do
        local xml = saleItem.xmlFilename
        local matchedStoreItem = nil
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

function DataExporter:getBrandTitle(brandRaw)
    if not brandRaw or brandRaw == "" then
        return "(Unknown Brand)"
    end
    local raw = brandRaw:lower():gsub("^%s*(.-)%s*$", "%1")
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


function DataExporter:getFieldsExport()
    local fields = {}
    for _, farmland in pairs(g_farmlandManager.farmlands) do
        if farmland.showOnFarmlandsScreen and farmland.field ~= nil then
            local field = farmland.field
            local farmId = farmland.farmId or 0
            local farmName = "(Unknown)"
            if farmId ~= 0 then
                local farm = g_farmManager:getFarmById(farmId)
                if farm ~= nil then
                    farmName = farm.name
                end
            end

            local x, z = field:getCenterOfFieldWorldPosition()
            local fruitTypeIndex, growthState = FSDensityMapUtil.getFruitTypeIndexAtWorldPos(x, z)
            local fruitTypeName = "None"
            local growthStateLabel = "--"

            if fruitTypeIndex ~= nil then
                local fruitType = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
                if fruitType and fruitType.fillType then
                    fruitTypeName = fruitType.fillType.title
                end
                local minHarvest = fruitType.minHarvestingGrowthState
                local maxHarvest = fruitType.maxHarvestingGrowthState
                local maxGrowing = fruitType.minHarvestingGrowthState - 1
                local withered = fruitType.maxHarvestingGrowthState + 1
                if fruitType.minPreparingGrowthState >= 0 then
                    maxGrowing = math.min(maxGrowing, fruitType.minPreparingGrowthState - 1)
                end
                if fruitType.maxPreparingGrowthState >= 0 then
                    withered = fruitType.maxPreparingGrowthState + 1
                end
                if growthState == fruitType.cutState then
                    growthStateLabel = g_i18n:getText("ui_growthMapCut")
                elseif growthState == withered then
                    growthStateLabel = g_i18n:getText("ui_growthMapWithered")
                elseif growthState > 0 and growthState <= maxGrowing then
                    growthStateLabel = g_i18n:getText("ui_growthMapGrowing") .. string.format(" (%d/%d)", growthState, maxHarvest)
                elseif fruitType.minPreparingGrowthState >= 0 and growthState >= fruitType.minPreparingGrowthState and growthState <= fruitType.maxPreparingGrowthState then
                    growthStateLabel = g_i18n:getText("ui_growthMapReadyToPrepareForHarvest")
                elseif minHarvest <= growthState and growthState <= maxHarvest then
                    growthStateLabel = g_i18n:getText("ui_growthMapReadyToHarvest")
                end
            end

            table.insert(fields, string.format([[{
      "fieldId": %d,
      "fruitType": "%s",
      "growthState": %d,
      "growthStateLabel": "%s",
      "fieldAreaHa": %.2f,
      "farmId": %d,
      "farmName": "%s"
    }]], farmland.id or -1, self:escape(fruitTypeName), growthState or 0, self:escape(growthStateLabel), field.areaHa or 0, farmId, self:escape(farmName)))
        end
    end
    return table.concat(fields, ",\n    ")
end

local function celsiusToFahrenheit(c)
    return (c * 9 / 5) + 32
end

local function buildForecast(env)
    local forecastStrs = {}
    if not env or not env.weather or not env.weather.getNextWeatherType then
        return ""
    end
    local baseTime = env.dayTime
    local forecastStep = 3 * 60 * 60 * 1000
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
    if not env then return end
    self:loadFarmInfo()

    local currentDay = env.currentDay or 1
    local hour = env.currentHour or 0
    local minute = env.currentMinute or 0
    local daysPerMonth = g_currentMission.environment and g_currentMission.environment.daysPerPeriod or 3
    local startMonth = env.startMonth or 3
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
        local weatherId = type(currentWeatherType) == "table" and currentWeatherType.id or currentWeatherType
        if weatherId ~= nil then
            weatherCondition = WEATHER_CONDITIONS[weatherId] or "Unknown"
        end
        temperatureC = env.weather:getCurrentTemperature() or 0
        temperatureF = celsiusToFahrenheit(temperatureC)
        forecastJSON = buildForecast(env)
    end

-- ✅ Updated farm data logic with loan
local farmsJSON = ""
if g_farmManager and g_farmManager.farms then
    local farmParts = {}
    for farmId, farm in pairs(g_farmManager.farms) do
        local name = self:escape(farm.name or ("Unnamed Farm"))
        local money = tonumber(farm.money or 0)
        local isPlayer = (g_currentMission:getFarmId() == farmId)

        -- Lookup loan from farms.xml by farm name
        local loan = 0
        if self.farmInfoMap then
            for _, farmEntry in pairs(self.farmInfoMap) do
                if farmEntry.name == farm.name then
                    loan = tonumber(farmEntry.loan or 0)
                    break
                end
            end
        end

        table.insert(farmParts, string.format([[{
      "farmId": %d,
      "name": "%s",
      "money": %.2f,
      "loan": %.2f,
      "isPlayerFarm": %s
    }]], farmId, name, money, loan, tostring(isPlayer)))
    end
    farmsJSON = table.concat(farmParts, ",\n    ")
end


    local offersJSON = self:getSpecialOffers()
    local fieldsJSON = self:getFieldsExport()

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

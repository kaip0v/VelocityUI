script_name("VelocityUI")
local script_version = 1.1

local samp = require 'lib.samp.events'
local imgui = require 'mimgui'
local encoding = require 'encoding'
local memory = require 'memory'
local inicfg = require 'inicfg'
local lfs = require 'lfs'
local dlstatus = require('moonloader').download_status
local os = require 'os'
local io = require 'io'

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local processTextDraw 

local cfg = inicfg.load({
    main = {
        enabled = false,
        autoUpdate = true
    },
    speedo = {
        mode = 1,
        redlineColor = 1,
        posX = -1.0,
        posY = -1.0,
        colorOverSpeed = true,
        overSpeedThreshold = 2,
        warnLowFuel = true,
        lowFuelThreshold = 3,
        gearAsFirstDigit = false,
        showDecimals = false
    },
    zone = {
        minX = 0.0,
        maxX = 0.0,
        minY = 0.0,
        maxY = 0.0
    }
}, 'VelocityUI.ini')

local showSettings = imgui.new.bool(false)
local isSelectingZone = false
local selStartX, selStartY = 0, 0
local selEndX, selEndY = 0, 0
local forceSpeedoReset = false

local activeTempFiles = {}
local updateUrl = "https://raw.githubusercontent.com/kaip0v/VelocityUI/refs/heads/main/update.json"

local tempSysNotifText = nil
local tempSysNotifTimer = 0
local tempSysNotifType = 0

local function showSystemNotification(text, nType)
    tempSysNotifText = text
    tempSysNotifType = nType or 0
    tempSysNotifTimer = os.clock() + 3.0
end

local carData = {
    show = imgui.new.bool(false),
    eng = false,
    limit = false,
    light = false,
    lock = false,
    mile = "0",
    fuel = "0"
}

-- Эталонная таблица максимальных скоростей из PAWN
local maxSpeeds = {
    [400]=84, [401]=85, [402]=104, [403]=56, [404]=65, [405]=86, [406]=62, [407]=85, [408]=71, [409]=82,
    [410]=75, [411]=122, [412]=85, [413]=74, [414]=75, [415]=107, [416]=56, [417]=86, [418]=71, [419]=75,
    [420]=86, [421]=75, [422]=75, [423]=58, [424]=85, [425]=103, [426]=85, [427]=85, [428]=85, [429]=111,
    [430]=86, [431]=71, [432]=71, [433]=85, [434]=103, [435]=71, [436]=75, [437]=71, [438]=75, [439]=86,
    [440]=75, [441]=75, [442]=58, [443]=75, [444]=86, [445]=85, [446]=75, [447]=75, [448]=58, [449]=75,
    [450]=75, [451]=107, [452]=75, [453]=58, [454]=58, [455]=86, [456]=75, [457]=75, [458]=86, [459]=71,
    [460]=75, [461]=100, [462]=86, [463]=86, [464]=58, [465]=58, [466]=86, [467]=86, [468]=80, [469]=75,
    [470]=86, [471]=60, [472]=75, [473]=75, [474]=86, [475]=86, [476]=103, [477]=96, [478]=86, [479]=86,
    [480]=103, [481]=75, [482]=86, [483]=75, [484]=75, [485]=75, [486]=75, [487]=75, [488]=75, [489]=77,
    [490]=86, [491]=75, [492]=86, [493]=75, [494]=103, [495]=98, [496]=86, [497]=75, [498]=75, [499]=75,
    [500]=86, [501]=75, [502]=86, [503]=86, [504]=86, [505]=77, [506]=103, [507]=71, [508]=86, [509]=75,
    [510]=75, [511]=86, [512]=86, [513]=75, [514]=75, [515]=86, [516]=86, [517]=86, [518]=86, [519]=75,
    [520]=75, [521]=95, [522]=108, [523]=86, [524]=75, [525]=75, [526]=86, [527]=86, [528]=86, [529]=86,
    [530]=75, [531]=75, [532]=75, [533]=86, [534]=86, [535]=86, [536]=86, [537]=75, [538]=75, [539]=86,
    [540]=86, [541]=112, [542]=86, [543]=75, [544]=86, [545]=86, [546]=86, [547]=86, [548]=75, [549]=85,
    [550]=86, [551]=86, [552]=86, [553]=103, [554]=86, [555]=86, [556]=86, [557]=86, [558]=92, [559]=92,
    [560]=94, [561]=92, [562]=92, [563]=75, [564]=75, [565]=86, [566]=86, [567]=86, [568]=86, [569]=86,
    [570]=86, [571]=86, [572]=86, [573]=86, [574]=75, [575]=86, [576]=86, [577]=86, [578]=86, [579]=86,
    [580]=86, [581]=86, [582]=86, [583]=86, [584]=86, [585]=86, [586]=86, [587]=86, [588]=86, [589]=86,
    [590]=86, [591]=86, [592]=86, [593]=86, [594]=86, [595]=86, [596]=86, [597]=86, [598]=86, [599]=86,
    [600]=86, [601]=86, [602]=86, [603]=86, [604]=86, [605]=86, [606]=86, [607]=86, [608]=86, [609]=86,
    [610]=86, [611]=86
}

local speedTdId = -1
local hiddenTds = {}
local fontSpeed = nil
local fontLabels = nil
local fontGears = nil

local icons = {
    GAS_PUMP = "\xef\x94\xaf",
    ROAD = "\xef\x80\x98"
}

local globalWcharsNum = imgui.new.ImWchar[3](0x0020, 0x0039, 0)
local globalWcharsIcon = imgui.new.ImWchar[3](0xF000, 0xF8FF, 0)

-- Функция для всплывающих подсказок при наведении
local function Tooltip(text)
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.PushTextWrapPos(imgui.GetFontSize() * 25.0)
        imgui.TextUnformatted(text)
        imgui.PopTextWrapPos()
        imgui.EndTooltip()
    end
end

local function cleanupGhostFiles()
    local cfgPath = getWorkingDirectory() .. '\\config\\'
    pcall(function()
        for file in lfs.dir(cfgPath) do
            if type(file) == 'string' then
                if file:match("^vui_update_%d+%.json$") then
                    pcall(os.remove, cfgPath .. file)
                end
            end
        end
    end)
end

function checkUpdates()
    if not cfg.main.autoUpdate then return end
    local updateFile_tmp = getWorkingDirectory() .. '\\config\\vui_update_' .. tostring(math.random(100000, 999999)) .. '.json'
    activeTempFiles[updateFile_tmp] = true
    
    local url_no_cache = updateUrl .. "?t=" .. tostring(os.time())
    downloadUrlToFile(url_no_cache, updateFile_tmp, function(id, status)
        if status == dlstatus.STATUS_ENDDOWNLOADDATA then
            local f = io.open(updateFile_tmp, "rb")
            local content = nil
            if f then
                content = f:read("*a")
                f:close()
            end
            pcall(os.remove, updateFile_tmp)
            activeTempFiles[updateFile_tmp] = nil
            
            if content and content ~= "" then
                local data = nil
                local ok, res = pcall(decodeJson, content)
                if ok and type(res) == "table" then
                    data = res
                else
                    pcall(function()
                        local func = load("return " .. content)
                        if func then data = func() end
                    end)
                end
                
                if data and data.version and data.url then
                    if tonumber(data.version) > tonumber(script_version) then
                        showSystemNotification(u8"Найдено обновление! Загрузка...", 3)
                        lua_thread.create(function()
                            wait(100)
                            local scriptPath = thisScript().path
                            local tempPath = scriptPath .. tostring(math.random(10000, 99999)) .. ".tmp"
                            activeTempFiles[tempPath] = true
                            
                            local dl_url_no_cache = data.url .. "?t=" .. tostring(os.time())
                            downloadUrlToFile(dl_url_no_cache, tempPath, function(id2, status2)
                                if status2 == dlstatus.STATUS_ENDDOWNLOADDATA then
                                    local fTmp = io.open(tempPath, "rb")
                                    if fTmp then
                                        local newCode = fTmp:read("*a")
                                        fTmp:close()
                                        pcall(os.remove, tempPath)
                                        activeTempFiles[tempPath] = nil
                                        local fOut = io.open(scriptPath, "wb")
                                        if fOut then
                                            fOut:write(newCode)
                                            fOut:close()
                                            showSystemNotification(u8"Успешно обновлено! Перезапуск...", 1)
                                            lua_thread.create(function()
                                                wait(1500)
                                                thisScript():reload()
                                            end)
                                        end
                                    end
                                elseif status2 == dlstatus.STATUS_EX_ERROR then
                                    pcall(os.remove, tempPath)
                                    activeTempFiles[tempPath] = nil
                                    showSystemNotification(u8"Ошибка при скачивании обновления!", 2)
                                end
                            end)
                        end)
                    end
                end
            end
        elseif status == dlstatus.STATUS_EX_ERROR then
            pcall(os.remove, updateFile_tmp)
            activeTempFiles[updateFile_tmp] = nil
        end
    end)
end

local notif_frame = imgui.OnFrame(
    function() return tempSysNotifText ~= nil and os.clock() < tempSysNotifTimer end,
    function(player)
        local resX, resY = getScreenResolution()
        imgui.SetNextWindowPos(imgui.ImVec2(resX - 20, resY - 20), imgui.Cond.Always, imgui.ImVec2(1.0, 1.0))
        
        local borderColor = imgui.ImVec4(0.25, 0.25, 0.25, 1.0)
        if tempSysNotifType == 1 then borderColor = imgui.ImVec4(0.20, 0.80, 0.20, 0.80)
        elseif tempSysNotifType == 2 then borderColor = imgui.ImVec4(0.80, 0.20, 0.20, 0.80)
        elseif tempSysNotifType == 3 then borderColor = imgui.ImVec4(0.20, 0.60, 0.90, 0.80) end

        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.12, 0.12, 0.12, 0.95))
        imgui.PushStyleColor(imgui.Col.Border, borderColor)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.9, 0.9, 0.9, 1.0))
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 6.0)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 1.0)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(15, 10))

        local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoInputs
        if imgui.Begin("##SysIndicator", nil, flags) then
            imgui.Text(tempSysNotifText)
            imgui.End()
        end
        imgui.PopStyleVar(3)
        imgui.PopStyleColor(3)
    end
)

local settings_frame = imgui.OnFrame(
    function() return showSettings[0] or isSelectingZone end,
    function(player)
        local resX, resY = getScreenResolution()

        if isSelectingZone then
            local dlList = imgui.GetBackgroundDrawList()
            local io = imgui.GetIO()
            
            dlList:AddRectFilled(imgui.ImVec2(0, 0), imgui.ImVec2(resX, resY), 0x50000000)
            
            if imgui.IsMouseClicked(0) then
                selStartX, selStartY = io.MousePos.x, io.MousePos.y
                selEndX, selEndY = selStartX, selStartY
            elseif imgui.IsMouseDragging(0) then
                selEndX, selEndY = io.MousePos.x, io.MousePos.y
                local minX = math.min(selStartX, selEndX)
                local minY = math.min(selStartY, selEndY)
                local maxX = math.max(selStartX, selEndX)
                local maxY = math.max(selStartY, selEndY)
                dlList:AddRectFilled(imgui.ImVec2(minX, minY), imgui.ImVec2(maxX, maxY), 0x500000FF)
                dlList:AddRect(imgui.ImVec2(minX, minY), imgui.ImVec2(maxX, maxY), 0xFF0000FF, 0.0, 0, 2.0)
            elseif imgui.IsMouseReleased(0) then
                local convX = 640.0 / resX
                local convY = 480.0 / resY
                cfg.zone.minX = math.min(selStartX, selEndX) * convX
                cfg.zone.maxX = math.max(selStartX, selEndX) * convX
                cfg.zone.minY = math.min(selStartY, selEndY) * convY
                cfg.zone.maxY = math.max(selStartY, selEndY) * convY
                inicfg.save(cfg, 'VelocityUI.ini')
                isSelectingZone = false
                showSettings[0] = true

                for id = 0, 2304 do
                    if sampTextdrawIsExists(id) then
                        local text = sampTextdrawGetString(id)
                        local letX, letY, color = sampTextdrawGetLetterSizeAndColor(id)
                        local px, py = sampTextdrawGetPos(id)
                        if processTextDraw(id, text, {x = px, y = py}, letY or 0) then
                            sampTextdrawDelete(id)
                        end
                    end
                end
            end
            return
        end

        imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(500, 420), imgui.Cond.FirstUseEver)
        
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 6.0)
        imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 6.0)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 8.0)

        if imgui.Begin("VelocityUI Settings", showSettings, imgui.WindowFlags.NoCollapse) then
            local zoneSet = (cfg.zone.maxX > 0.0 and cfg.zone.maxY > 0.0)
            
            local bEnabled = imgui.new.bool(cfg.main.enabled)
            if imgui.Checkbox(u8"Включить спидометр", bEnabled) then
                cfg.main.enabled = bEnabled[0]
                inicfg.save(cfg, 'VelocityUI.ini')
            end
            Tooltip(u8"Включает или выключает отображение кастомного спидометра на экране.")
            
            imgui.Spacing()

            imgui.Text(u8"Зона скрытия текстдрава:")
            Tooltip(u8"Область на экране, где находится серверный спидометр. Скрипт будет автоматически скрывать всё, что попадает в эту зону.")
            
            imgui.SameLine()
            if zoneSet then
                imgui.TextColored(imgui.ImVec4(0.0, 1.0, 0.0, 1.0), u8"Выделена")
            else
                imgui.TextColored(imgui.ImVec4(1.0, 0.0, 0.0, 1.0), u8"Не выделена")
            end

            if imgui.Button(u8"Выделить зону мышью") then
                showSettings[0] = false
                isSelectingZone = true
            end
            Tooltip(u8"Позволяет вручную обвести серверный спидометр рамкой на экране, чтобы скрыть его.")
            
            imgui.SameLine()
            if imgui.Button(u8"Сбросить зону") then
                cfg.zone.minX = 0.0
                cfg.zone.maxX = 0.0
                cfg.zone.minY = 0.0
                cfg.zone.maxY = 0.0
                inicfg.save(cfg, 'VelocityUI.ini')
            end
            Tooltip(u8"Отменяет скрытие серверного спидометра (он снова появится).")

            if imgui.Button(u8"Сбросить позицию спидометра") then
                forceSpeedoReset = true
            end
            Tooltip(u8"Возвращает окно кастомного спидометра в стандартное положение (правый нижний угол экрана).")
            
            imgui.Spacing()

            imgui.Text(u8"Режим полосы:")
            local modes = {u8"Тахометр (Обороты)", u8"Состояние (ХП авто)"}
            imgui.PushItemWidth(250)
            if imgui.BeginCombo("##ModeCombo", modes[cfg.speedo.mode]) then
                for i, v in ipairs(modes) do
                    if imgui.Selectable(v, cfg.speedo.mode == i) then
                        cfg.speedo.mode = i
                        inicfg.save(cfg, 'VelocityUI.ini')
                    end
                end
                imgui.EndCombo()
            end
            imgui.PopItemWidth()
            Tooltip(u8"Определяет, что будет показывать нижняя шкала под спидометром: обороты двигателя (RPM) или целостность автомобиля (HP).")

            imgui.Spacing()

            local bWhite = imgui.new.bool(cfg.speedo.redlineColor == 2)
            if imgui.Checkbox(u8"Белые секции в конце шкалы", bWhite) then
                cfg.speedo.redlineColor = bWhite[0] and 2 or 1
                inicfg.save(cfg, 'VelocityUI.ini')
            end
            Tooltip(u8"Перекрашивает последние (красные) деления заполняющейся шкалы в белый цвет.")
            
            imgui.Spacing()

            local bOverSpeed = imgui.new.bool(cfg.speedo.colorOverSpeed)
            if imgui.Checkbox(u8"Красные цифры при превышении", bOverSpeed) then
                cfg.speedo.colorOverSpeed = bOverSpeed[0]
                inicfg.save(cfg, 'VelocityUI.ini')
            end
            Tooltip(u8"Окрашивает главные цифры скорости в красный цвет, когда вы превышаете предельную скорость автомобиля.")
            
            if cfg.speedo.colorOverSpeed then
                imgui.SameLine()
                imgui.Text(u8"(Порог: +")
                imgui.SameLine(0, 4)
                imgui.PushItemWidth(40)
                local iThresh = imgui.new.int(cfg.speedo.overSpeedThreshold or 2)
                if imgui.InputInt("##OverSpeedThresh", iThresh, 0, 0) then
                    if iThresh[0] < 0 then iThresh[0] = 0 end
                    cfg.speedo.overSpeedThreshold = iThresh[0]
                    inicfg.save(cfg, 'VelocityUI.ini')
                end
                imgui.PopItemWidth()
                Tooltip(u8"Допустимое превышение скорости (в милях/ч), после которого цвет изменится на красный.\nНе может быть меньше 0.\nСтандартное значение: 2")
                imgui.SameLine(0, 4)
                imgui.Text(u8"миль)")
            end
            
            imgui.Spacing()

            local bLowFuel = imgui.new.bool(cfg.speedo.warnLowFuel)
            if imgui.Checkbox(u8"Предупреждение о топливе", bLowFuel) then
                cfg.speedo.warnLowFuel = bLowFuel[0]
                inicfg.save(cfg, 'VelocityUI.ini')
            end
            Tooltip(u8"Иконка бензоколонки начнёт мигать красным цветом, если уровень топлива опустится до указанного значения или ниже.")
            
            imgui.SameLine()
            imgui.Text(u8"(при <=")
            imgui.SameLine(0, 4)
            imgui.PushItemWidth(40)
            local iFuel = imgui.new.int(cfg.speedo.lowFuelThreshold)
            if imgui.InputInt("##FuelLimit", iFuel, 0, 0) then
                if iFuel[0] < 0 then iFuel[0] = 0 end
                cfg.speedo.lowFuelThreshold = iFuel[0]
                inicfg.save(cfg, 'VelocityUI.ini')
            end
            imgui.PopItemWidth()
            Tooltip(u8"Порог уровня бензина в литрах для срабатывания мигания.")
            imgui.SameLine(0, 4)
            imgui.Text(u8"л.)")

            imgui.Spacing()

            local bGearDigit = imgui.new.bool(cfg.speedo.gearAsFirstDigit)
            if imgui.Checkbox(u8"Показывать передачу вместо 1-го нуля", bGearDigit) then
                cfg.speedo.gearAsFirstDigit = bGearDigit[0]
                inicfg.save(cfg, 'VelocityUI.ini')
            end
            Tooltip(u8"Если скорость меньше 100 миль/ч, первая (серая) цифра спидометра будет показывать текущую передачу.")
            
            imgui.Spacing()

            local bDecimals = imgui.new.bool(cfg.speedo.showDecimals)
            if imgui.Checkbox(u8"Десятые доли (пробег и бензин)", bDecimals) then
                cfg.speedo.showDecimals = bDecimals[0]
                inicfg.save(cfg, 'VelocityUI.ini')
            end
            Tooltip(u8"Отображает значения пробега и уровня топлива с точностью до одной десятой (например, 43.8).")

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            local bUpdate = imgui.new.bool(cfg.main.autoUpdate)
            if imgui.Checkbox(u8"Автообновление", bUpdate) then
                cfg.main.autoUpdate = bUpdate[0]
                inicfg.save(cfg, 'VelocityUI.ini')
            end
            Tooltip(u8"Скрипт будет автоматически проверять наличие новых версий и устанавливать их.")

            imgui.End()
        end
        imgui.PopStyleVar(3)
    end
)

local new_frame = imgui.OnFrame(
    function() return cfg.main.enabled and carData.show[0] and isCharInAnyCar(PLAYER_PED) end,
    function(player)
        player.HideCursor = not sampIsCursorActive()

        local resX, resY = getScreenResolution()
        
        local winW, winH = 480, 310

        if cfg.speedo.posX == -1.0 or forceSpeedoReset then
            cfg.speedo.posX = resX - winW - 30
            cfg.speedo.posY = resY - winH - 30
            imgui.SetNextWindowPos(imgui.ImVec2(cfg.speedo.posX, cfg.speedo.posY), imgui.Cond.Always)
            inicfg.save(cfg, 'VelocityUI.ini')
            forceSpeedoReset = false
        else
            imgui.SetNextWindowPos(imgui.ImVec2(cfg.speedo.posX, cfg.speedo.posY), imgui.Cond.FirstUseEver)
        end

        imgui.SetNextWindowSize(imgui.ImVec2(winW, winH), imgui.Cond.Always)

        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0.0)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
        
        local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoSavedSettings
        if not showSettings[0] then
            flags = flags + imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoInputs + imgui.WindowFlags.NoMove
            imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0, 0, 0, 0))
        else
            imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0, 0, 0, 0.3))
        end

        if imgui.Begin("VelocityUI", carData.show, flags) then
            if showSettings[0] then
                local p = imgui.GetWindowPos()
                cfg.speedo.posX = p.x
                cfg.speedo.posY = p.y
                inicfg.save(cfg, 'VelocityUI.ini')
            end

            local dl = imgui.GetWindowDrawList()
            local p = imgui.GetWindowPos()
            
            local currentSpeed = 0
            local maxSpeed = 120.0
            local rpm = 0.0
            local hpPct = 1.0
            local localSpeedFloat = 0.0
            local isOverSpeed = false

            local res, car = pcall(storeCarCharIsInNoSave, PLAYER_PED)
            if res and car then
                local existRes, exist = pcall(doesVehicleExist, car)
                if existRes and exist then
                    local modelRes, carModel = pcall(getCarModel, car)
                    if modelRes and carModel then
                        local vx, vy, vz = getCarSpeedVector(car)
                        localSpeedFloat = math.sqrt(vx^2 + vy^2) * 2.0
                        currentSpeed = math.floor(localSpeedFloat + 0.5)
                        
                        -- Берём эталонный лимит скорости из таблицы PAWN
                        local originalMaxSpeed = maxSpeeds[carModel] or 85.0
                        local overSpeedThreshold = cfg.speedo.overSpeedThreshold or 2
                        
                        -- Срабатывание красноты с учетом настраиваемого порога
                        if currentSpeed >= originalMaxSpeed + overSpeedThreshold then
                            isOverSpeed = true
                        end
                        
                        maxSpeed = originalMaxSpeed
                        if currentSpeed > maxSpeed then maxSpeed = currentSpeed end

                        local healthRes, health = pcall(getCarHealth, car)
                        if healthRes and health then
                            hpPct = (health - 250) / 750.0
                            if hpPct < 0 then hpPct = 0 elseif hpPct > 1.0 then hpPct = 1.0 end
                        end

                        if isCarEngineOn(car) then
                            local spd = getCarSpeed(car) * 2.0
                            local gear = getCarCurrentGear(car)
                            if gear > 0 then
                                rpm = (spd / gear) * 250.0
                            else
                                rpm = spd * 180.0
                            end
                            
                            if rpm < 650 then
                                rpm = math.random(650, 900)
                            elseif rpm >= 8000 then
                                rpm = 8000
                            end
                        end
                    end
                end
            end

            local speedScale = localSpeedFloat / maxSpeed
            if speedScale > 1.0 then speedScale = 1.0 end

            local rpmPct = rpm / 8000.0
            if rpmPct > 1.0 then rpmPct = 1.0 end
            if rpmPct < 0.0 then rpmPct = 0.0 end

            local speedStr = tostring(currentSpeed)
            local fullStr = string.format("%03d", currentSpeed)
            if #fullStr > 3 then fullStr = tostring(currentSpeed) end
            local zeroesCount = #fullStr - #speedStr
            
            local displayStr = fullStr
            if cfg.speedo.gearAsFirstDigit and currentSpeed < 100 then
                local gear = 0
                local ok, veh = pcall(storeCarCharIsInNoSave, PLAYER_PED)
                if ok and veh then gear = getCarCurrentGear(veh) end
                displayStr = tostring(gear) .. string.format("%02d", currentSpeed)
            end

            if fontSpeed then imgui.PushFont(fontSpeed) end
            local totalW = 0
            for i = 1, #displayStr do
                totalW = totalW + imgui.CalcTextSize(displayStr:sub(i, i)).x
            end

            local cx = p.x + (winW / 2)
            local startX = cx - totalW / 2
            local startY = p.y + 10
            local digitY = startY - 20

            local curX = startX
            for i = 1, #displayStr do
                local char = displayStr:sub(i, i)
                local col = 0xFFFFFFFF
                
                if cfg.speedo.colorOverSpeed and isOverSpeed then
                    col = (i <= zeroesCount) and 0x350000FF or 0xFF0000FF
                else
                    col = (i <= zeroesCount) and 0x35FFFFFF or 0xFFFFFFFF
                end
                
                dl:AddText(imgui.ImVec2(curX, digitY), col, char)
                curX = curX + imgui.CalcTextSize(char).x
            end
            if fontSpeed then imgui.PopFont() end

            local barW = totalW
            local barX = startX
            
            local segCount = 40
            local redZoneStart = 30
            local segGap = 4.0
            local segW = (barW - (segCount - 1) * segGap) / segCount

            local speedBarW = (redZoneStart * segW) + ((redZoneStart - 1) * segGap)
            local speedBarH = 8.0
            local barY = startY + 175

            dl:AddRectFilled(imgui.ImVec2(barX, barY), imgui.ImVec2(barX + speedBarW, barY + speedBarH), 0xFF404040, speedBarH / 2)
            
            if speedScale > 0.01 then
                local fillW = speedBarW * speedScale
                if fillW > speedBarW then fillW = speedBarW end
                dl:AddRectFilled(imgui.ImVec2(barX, barY), imgui.ImVec2(barX + fillW, barY + speedBarH), 0xFFFFFFFF, speedBarH / 2)
            end

            local segY = barY + 18
            local segH = 22
            
            local activeSegs = 0
            if cfg.speedo.mode == 1 then
                activeSegs = math.floor(rpmPct * segCount)
            else
                activeSegs = math.floor(hpPct * segCount)
            end

            for i = 0, segCount - 1 do
                local isRedZone = i >= redZoneStart
                local isActive = false
                
                if cfg.speedo.mode == 1 then
                    isActive = i < activeSegs
                else
                    local emptySegs = segCount - activeSegs
                    isActive = i >= emptySegs
                end

                local curSegH = isRedZone and (segH + 8) or segH
                local curSegY = isRedZone and (segY - 8) or segY

                local col = 0xFF404040
                
                if cfg.speedo.redlineColor == 1 then
                    if isRedZone then col = 0xFF202080 end
                    if isActive then
                        if isRedZone then
                            col = 0xFF3030D0
                        else
                            col = 0xFFFFFFFF
                        end
                    end
                else
                    if isActive then
                        col = 0xFFFFFFFF
                    else
                        col = 0xFF404040
                    end
                end

                local sx = barX + i * (segW + segGap)
                dl:AddRectFilled(imgui.ImVec2(sx, curSegY), imgui.ImVec2(sx + segW, curSegY + curSegH), col)
            end

            local labY = segY + segH + 16

            if fontGears then imgui.PushFont(fontGears) end
            local gearStr = "S E L D"
            local gSz = imgui.CalcTextSize(gearStr)
            local bW = gSz.x + 36
            local bH = gSz.y + 10
            local bX = p.x + (winW - bW) / 2
            local bY = labY
            if fontGears then imgui.PopFont() end

            local centerY = bY + bH / 2

            if fontLabels then imgui.PushFont(fontLabels) end
            
            local mileNum = tonumber(carData.mile) or 0
            local mileStr = cfg.speedo.showDecimals and string.format("%.1f", mileNum) or tostring(math.floor(mileNum))
            local mileSz = imgui.CalcTextSize(mileStr)
            local roadSz = imgui.CalcTextSize(icons.ROAD)
            
            local gap = 12
            local innerGap = 6
            local mileTotalW = mileSz.x + innerGap + roadSz.x
            local mileStartX = bX - gap - mileTotalW
            
            local textY = centerY - imgui.CalcTextSize("0").y / 2
            local roadIconY = centerY - roadSz.y / 2
            
            dl:AddText(imgui.ImVec2(mileStartX, textY), 0xFFFFFFFF, mileStr)
            dl:AddText(imgui.ImVec2(mileStartX + mileSz.x + innerGap, roadIconY), 0xFFAAAAAA, icons.ROAD)
            
            local fuelNum = tonumber(carData.fuel) or 0
            local fuelVal = math.floor(fuelNum)
            local fuelStr = (cfg.speedo.showDecimals and string.format("%.1f", fuelNum) or tostring(fuelVal)) .. " L"
            local fSz = imgui.CalcTextSize(fuelStr)
            local pumpSz = imgui.CalcTextSize(icons.GAS_PUMP)
            
            local fuelStartX = bX + bW + gap
            local pumpIconY = centerY - pumpSz.y / 2
            
            local pumpCol = 0xFFAAAAAA
            local fCol = 0xFFFFFFFF
            
            if cfg.speedo.warnLowFuel and fuelVal <= cfg.speedo.lowFuelThreshold then
                local t = math.floor(os.clock() * 1000)
                if t % 1000 < 500 then
                    pumpCol = 0xFF0000FF
                    fCol = 0xFF0000FF
                end
            end
            
            dl:AddText(imgui.ImVec2(fuelStartX, pumpIconY), pumpCol, icons.GAS_PUMP)
            dl:AddText(imgui.ImVec2(fuelStartX + pumpSz.x + innerGap, textY), fCol, fuelStr)
            
            if fontLabels then imgui.PopFont() end

            dl:AddRectFilled(imgui.ImVec2(bX, bY), imgui.ImVec2(bX + bW, bY + bH), 0x99000000, 15.0)
            dl:AddRect(imgui.ImVec2(bX, bY), imgui.ImVec2(bX + bW, bY + bH), 0xFF69C7C2, 15.0, 15, 2.0)

            if fontGears then imgui.PushFont(fontGears) end
            local sCol = carData.limit and 0xFF69C7C2 or 0xFF666666
            local eCol = carData.eng and 0xFF69C7C2 or 0xFF666666
            local lCol = carData.light and 0xFF69C7C2 or 0xFF666666
            local dCol = carData.lock and 0xFF69C7C2 or 0xFF666666

            local gearsW = imgui.CalcTextSize("S E L D").x
            local curX_seld = bX + (bW - gearsW) / 2
            local spaceSz = imgui.CalcTextSize(" ").x
            local gY_seld = centerY - imgui.CalcTextSize("S").y / 2
            
            dl:AddText(imgui.ImVec2(curX_seld, gY_seld), sCol, "S")
            curX_seld = curX_seld + imgui.CalcTextSize("S").x + spaceSz
            dl:AddText(imgui.ImVec2(curX_seld, gY_seld), eCol, "E")
            curX_seld = curX_seld + imgui.CalcTextSize("E").x + spaceSz
            dl:AddText(imgui.ImVec2(curX_seld, gY_seld), lCol, "L")
            curX_seld = curX_seld + imgui.CalcTextSize("L").x + spaceSz
            dl:AddText(imgui.ImVec2(curX_seld, gY_seld), dCol, "D")
            
            if fontGears then imgui.PopFont() end

            imgui.End()
        end
        imgui.PopStyleColor()
        imgui.PopStyleVar(2)
    end
)

imgui.OnInitialize(function()
    local fontPath = getWorkingDirectory() .. '\\cef\\MiSansLatin-Medium.ttf'
    local f = io.open(fontPath, "r")
    if not f then
        fontPath = 'C:\\Windows\\Fonts\\arialbd.ttf'
    else
        f:close()
    end

    local config = imgui.ImFontConfig()
    config.MergeMode = true
    
    fontSpeed = imgui.GetIO().Fonts:AddFontFromFileTTF(fontPath, 220.0, imgui.ImFontConfig(), globalWcharsNum)
    
    fontLabels = imgui.GetIO().Fonts:AddFontFromFileTTF(fontPath, 26.0, imgui.ImFontConfig(), imgui.GetIO().Fonts:GetGlyphRangesDefault())
    imgui.GetIO().Fonts:AddFontFromFileTTF(getWorkingDirectory() .. '/resource/fonts/fa-solid-900.ttf', 24.0, config, globalWcharsIcon)
    
    fontGears = imgui.GetIO().Fonts:AddFontFromFileTTF(fontPath, 30.0, imgui.ImFontConfig(), imgui.GetIO().Fonts:GetGlyphRangesDefault())
end)

processTextDraw = function(id, text, pos, letY)
    if not cfg.main.enabled then return false end
    if text == nil or pos == nil then return false end

    local inZone = false
    if pos.x >= cfg.zone.minX and pos.x <= cfg.zone.maxX and pos.y >= cfg.zone.minY and pos.y <= cfg.zone.maxY then
        inZone = true
    end

    if text:find("FUEL: ([%d%.]+)") then
        carData.fuel = text:match("FUEL: ([%d%.]+)")
        carData.show[0] = true
    end
    if text:find("MILE: ([%d%.]+)") then
        carData.mile = text:match("MILE: ([%d%.]+)")
    end
    if text:find("ENG") then
        carData.eng = text:find("~w~") ~= nil
    end
    if text:find("LIGHT") then
        carData.light = text:find("~w~") ~= nil
    end
    if text:find("LOCK") then
        carData.lock = text:find("~w~") ~= nil
    end
    if text:find("LIMIT") then
        carData.limit = text:find("~w~") ~= nil
    end

    if inZone then
        if text == "box" and letY > 4.5 and letY < 4.8 then hiddenTds[id] = true; return true end
        if text:find("LD_BEAT") and letY == 0.0 then hiddenTds[id] = true; return true end
        if text == "MP/H" and letY > 0.9 and letY < 1.1 then hiddenTds[id] = true; return true end
        if text:match("^%d+$") and letY > 2.5 and letY < 2.7 then
            speedTdId = id
            carData.show[0] = true
            hiddenTds[id] = true
            return true
        end
        if text:find("FUEL: ([%d%.]+)") then hiddenTds[id] = true; return true end
        if text:find("MILE: ([%d%.]+)") then hiddenTds[id] = true; return true end
        if text:find("ENG") then hiddenTds[id] = true; return true end
        if text:find("LIGHT") then hiddenTds[id] = true; return true end
        if text:find("LOCK") then hiddenTds[id] = true; return true end
        if text:find("LIMIT") then hiddenTds[id] = true; return true end
    end

    if hiddenTds[id] or id == speedTdId then
        return true
    end

    return false
end

function samp.onShowTextDraw(id, data)
    if processTextDraw(id, data.text, data.position, data.letterHeight or 0) then
        return false
    end
end

function samp.onTextDrawSetString(id, text)
    local letX, letY, color = sampTextdrawGetLetterSizeAndColor(id)
    local px, py = sampTextdrawGetPos(id)
    if processTextDraw(id, text, {x = px, y = py}, letY or 0) then
        return false
    end
end

function samp.onTextDrawHide(id)
    hiddenTds[id] = nil
    if id == speedTdId then
        carData.show[0] = false
        speedTdId = -1
    end
end

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end
    
    cleanupGhostFiles()
    checkUpdates()
    
    sampRegisterChatCommand("vui", function()
        showSettings[0] = not showSettings[0]
        if not showSettings[0] then
            isSelectingZone = false
        end
    end)
    
    for id = 0, 2304 do
        if sampTextdrawIsExists(id) then
            local text = sampTextdrawGetString(id)
            local letX, letY, color = sampTextdrawGetLetterSizeAndColor(id)
            local px, py = sampTextdrawGetPos(id)
            
            processTextDraw(id, text, {x = px, y = py}, letY or 0)
        end
    end
    
    wait(-1)
end

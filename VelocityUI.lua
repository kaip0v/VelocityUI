script_name("VelocityUI")
local script_version = 1.3
local samp = require 'samp.events'
local imgui = require 'mimgui'
local encoding = require 'encoding'
local memory = require 'memory'
local vkeys = require 'vkeys'
local lfs = require 'lfs'
local dlstatus = require('moonloader').download_status

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local processTextDraw

local configPath = getWorkingDirectory() .. '\\config\\VelocityUI.json'

local defaultCfg = {
    main = {
        enabled = false,
        autoUpdate = true,
        renderOptimization = true
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
        showDecimals = false,
        scale = 1.0,
        useDirectStates = false
    },
    zone = {
        minX = 0.0,
        maxX = 0.0,
        minY = 0.0,
        maxY = 0.0
    }
}

local cfg = {}

local function saveConfig()
    local f = io.open(configPath, "w")
    if f then
        f:write(encodeJson(cfg))
        f:close()
    end
end

local function loadConfig()
    for k, v in pairs(defaultCfg) do
        if type(v) == "table" then
            cfg[k] = {}
            for k2, v2 in pairs(v) do cfg[k][k2] = v2 end
        else
            cfg[k] = v
        end
    end

    local f = io.open(configPath, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local ok, parsed = pcall(decodeJson, content)
        if ok and type(parsed) == "table" then
            for k, v in pairs(parsed) do
                if type(v) == "table" and type(cfg[k]) == "table" then
                    for k2, v2 in pairs(v) do
                        cfg[k][k2] = v2
                    end
                elseif type(v) ~= "table" then
                    cfg[k] = v
                end
            end
            return
        end
    end
    saveConfig()
end

loadConfig()

local showSettings = imgui.new.bool(false)
local isSelectingZone = false
local selStartX, selStartY = 0, 0
local selEndX, selEndY = 0, 0
local forceSpeedoReset = false
local lastFuelBlinkState = false

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

local calcData = {
    currentSpeed = 0,
    maxSpeed = 120.0,
    rpm = 0.0,
    hpPct = 1.0,
    localSpeedFloat = 0.0,
    isOverSpeed = false,
    gear = 0
}

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

local smoothedSpeedScale = 0.0
local smoothedRpmPct = 0.0
local smoothedHpPct = 1.0

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

local wasTypingEscape = false

addEventHandler('onWindowMessage', function(msg, wparam, lparam)
    if msg == 0x0100 or msg == 0x0101 then 
        if wparam == vkeys.VK_ESCAPE and (showSettings[0] or isSelectingZone) then
            consumeWindowMessage(true, false)
            if msg == 0x0100 then
                wasTypingEscape = imgui.GetIO().WantCaptureKeyboard
            elseif msg == 0x0101 then
                if not wasTypingEscape then
                    showSettings[0] = false
                    isSelectingZone = false
                end
                wasTypingEscape = false
            end
        end
    end
end)

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
                        local is_silent = (data.silent == true)
                        if not is_silent then
                            showSystemNotification(u8"Найдено обновление! Загрузка...", 3)
                        end
                        
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
                                        
                                        if newCode:find("\208[\128-\191]") or newCode:find("\209[\128-\191]") then
                                            local decoded = u8:decode(newCode)
                                            if decoded then newCode = decoded end
                                        end
                                        
                                        local fOut = io.open(scriptPath, "wb")
                                        if fOut then
                                            fOut:write(newCode)
                                            fOut:close()
                                            if not is_silent then
                                                showSystemNotification(u8"Успешно обновлено! Перезапуск...", 1)
                                            end
                                            lua_thread.create(function()
                                                wait(1500)
                                                thisScript():reload()
                                            end)
                                        end
                                    end
                                elseif status2 == dlstatus.STATUS_EX_ERROR then
                                    pcall(os.remove, tempPath)
                                    activeTempFiles[tempPath] = nil
                                    if not is_silent then
                                        showSystemNotification(u8"Ошибка при скачивании обновления!", 2)
                                    end
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
                saveConfig()
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
        imgui.SetNextWindowSize(imgui.ImVec2(520, 480), imgui.Cond.FirstUseEver)
        
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 6.0)
        imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 6.0)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 8.0)

        if imgui.Begin("VelocityUI Settings", showSettings, imgui.WindowFlags.NoCollapse) then
            local zoneSet = (cfg.zone.maxX > 0.0 and cfg.zone.maxY > 0.0)
            
            local bEnabled = imgui.new.bool(cfg.main.enabled)
            if imgui.Checkbox(u8"Включить спидометр", bEnabled) then
                cfg.main.enabled = bEnabled[0]
                saveConfig()
                if cfg.main.enabled then
                    for id = 0, 2304 do
                        if sampTextdrawIsExists(id) then
                            local text = sampTextdrawGetString(id)
                            local letX, letY, color = sampTextdrawGetLetterSizeAndColor(id)
                            local px, py = sampTextdrawGetPos(id)
                            processTextDraw(id, text, {x = px, y = py}, letY or 0)
                        end
                    end
                end
            end
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Включает или отключает отображение кастомного спидометра на экране.") end
            
            imgui.Spacing()

            local fScale = imgui.new.float(cfg.speedo.scale)
            imgui.PushItemWidth(250)
            if imgui.SliderFloat(u8"Масштаб интерфейса", fScale, 0.5, 2.0, "%.2f") then
                cfg.speedo.scale = fScale[0]
                saveConfig()
            end
            imgui.PopItemWidth()
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Изменяет общий размер спидометра (от 0.5 до 2.0).") end

            imgui.Spacing()
            
            local bDirectStates = imgui.new.bool(cfg.speedo.useDirectStates)
            if imgui.Checkbox(u8"Моментальный отклик индикаторов (Память SA-MP)", bDirectStates) then
                cfg.speedo.useDirectStates = bDirectStates[0]
                saveConfig()
            end
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Читает данные фар, дверей и двигателя напрямую из памяти игры.\nДелает отклик мгновенным, в обход задержек (пинга) сервера.") end

            imgui.Spacing()

            imgui.Text(u8"Зона скрытия текстдрава:")
            
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
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Позволяет нарисовать прямоугольник там, где находится серверный спидометр,\nчтобы скрипт автоматически скрывал его.") end
            
            imgui.SameLine()
            if imgui.Button(u8"Сбросить зону") then
                cfg.zone.minX = 0.0
                cfg.zone.maxX = 0.0
                cfg.zone.minY = 0.0
                cfg.zone.maxY = 0.0
                saveConfig()
            end
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Очищает координаты выделенной зоны скрытия.") end

            if imgui.Button(u8"Сбросить позицию спидометра") then
                forceSpeedoReset = true
            end
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Возвращает окно спидометра в правый нижний угол экрана по умолчанию.") end
            
            imgui.Spacing()

            imgui.Text(u8"Режим полосы:")
            local modes = {u8"Тахометр (Обороты)", u8"Состояние (ХП авто)"}
            imgui.PushItemWidth(250)
            if imgui.BeginCombo("##ModeCombo", modes[cfg.speedo.mode]) then
                for i, v in ipairs(modes) do
                    if imgui.Selectable(v, cfg.speedo.mode == i) then
                        cfg.speedo.mode = i
                        saveConfig()
                    end
                end
                imgui.EndCombo()
            end
            imgui.PopItemWidth()
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Выбирает, что будет отображать главная шкала спидометра:\nОбороты двигателя (RPM) или показатель здоровья машины.") end

            imgui.Spacing()
			
            local bOpt = imgui.new.bool(cfg.main.renderOptimization)
            if imgui.Checkbox(u8"Оптимизация вычислений (Фоновый поток)", bOpt) then
                cfg.main.renderOptimization = bOpt[0]
                saveConfig()
            end
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Снижает нагрузку на процессор и повышает FPS за счет\nвыноса тяжелых расчетов из цикла отрисовки в отдельный поток.") end
			
            imgui.Spacing()
			
            local bWhite = imgui.new.bool(cfg.speedo.redlineColor == 2)
            if imgui.Checkbox(u8"Белые секции в конце шкалы", bWhite) then
                cfg.speedo.redlineColor = bWhite[0] and 2 or 1
                saveConfig()
            end
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Заменяет классический красный цвет последних делений\nшкалы тахометра на белый стиль.") end
            
            imgui.Spacing()

            local bOverSpeed = imgui.new.bool(cfg.speedo.colorOverSpeed)
            if imgui.Checkbox(u8"Красные цифры при превышении", bOverSpeed) then
                cfg.speedo.colorOverSpeed = bOverSpeed[0]
                saveConfig()
            end
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Окрашивает цифры скорости в красный цвет, если вы\nпревышаете максимальную скорость автомобиля.") end
            
            if cfg.speedo.colorOverSpeed then
                imgui.SameLine()
                imgui.Text(u8"(Порог: +")
                imgui.SameLine(0, 4)
                imgui.PushItemWidth(40)
                local iThresh = imgui.new.int(cfg.speedo.overSpeedThreshold or 2)
                if imgui.InputInt("##OverSpeedThresh", iThresh, 0, 0) then
                    if iThresh[0] < 0 then iThresh[0] = 0 end
                    cfg.speedo.overSpeedThreshold = iThresh[0]
                    saveConfig()
                end
                imgui.PopItemWidth()
                if imgui.IsItemHovered() then imgui.SetTooltip(u8"Запас скорости сверх максимума, после которого цифры станут красными.") end
                imgui.SameLine(0, 4)
                imgui.Text(u8"миль)")
            end
            
            imgui.Spacing()

            local bLowFuel = imgui.new.bool(cfg.speedo.warnLowFuel)
            if imgui.Checkbox(u8"Предупреждение о топливе", bLowFuel) then
                cfg.speedo.warnLowFuel = bLowFuel[0]
                saveConfig()
            end
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Иконка бензоколонки и значение топлива начнут\nмигать красным при низком уровне.") end
            
            imgui.SameLine()
            imgui.Text(u8"(при <=")
            imgui.SameLine(0, 4)
            imgui.PushItemWidth(40)
            local iFuel = imgui.new.int(cfg.speedo.lowFuelThreshold)
            if imgui.InputInt("##FuelLimit", iFuel, 0, 0) then
                if iFuel[0] < 0 then iFuel[0] = 0 end
                cfg.speedo.lowFuelThreshold = iFuel[0]
                saveConfig()
            end
            imgui.PopItemWidth()
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Количество литров, при котором сработает предупреждение.") end
            imgui.SameLine(0, 4)
            imgui.Text(u8"л.)")

            imgui.Spacing()

            local bGearDigit = imgui.new.bool(cfg.speedo.gearAsFirstDigit)
            if imgui.Checkbox(u8"Показывать передачу вместо 1-го нуля", bGearDigit) then
                cfg.speedo.gearAsFirstDigit = bGearDigit[0]
                saveConfig()
            end
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Заменяет ведущий неактивный ноль скорости на номер\nтекущей передачи (например: 105 км/ч, где 1 - передача).") end
            
            imgui.Spacing()

            local bDecimals = imgui.new.bool(cfg.speedo.showDecimals)
            if imgui.Checkbox(u8"Десятые доли (пробег и бензин)", bDecimals) then
                cfg.speedo.showDecimals = bDecimals[0]
                saveConfig()
            end
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Отображает значения пробега и топлива с точностью\nдо десятых (например: 15.5 L).") end

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            local bUpdate = imgui.new.bool(cfg.main.autoUpdate)
            if imgui.Checkbox(u8"Автообновление", bUpdate) then
                cfg.main.autoUpdate = bUpdate[0]
                saveConfig()
            end
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Скрипт будет автоматически проверять и скачивать\nновые версии с GitHub при запуске игры.") end

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
        
        local scale = cfg.speedo.scale or 1.0
        local winW, winH = 480 * scale, 310 * scale

        if cfg.speedo.posX == -1.0 or forceSpeedoReset then
            cfg.speedo.posX = resX - winW - 30
            cfg.speedo.posY = resY - winH - 30
            imgui.SetNextWindowPos(imgui.ImVec2(cfg.speedo.posX, cfg.speedo.posY), imgui.Cond.Always)
            saveConfig()
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
                saveConfig()
            end

            local dl = imgui.GetWindowDrawList()
            local p = imgui.GetWindowPos()
            
            imgui.SetWindowFontScale(scale)
            
            local currentSpeed = 0
            local maxSpeed = 120.0
            local rpm = 0.0
            local hpPct = 1.0
            local localSpeedFloat = 0.0
            local isOverSpeed = false
            local gear = 0

            if cfg.main.renderOptimization then
                currentSpeed = calcData.currentSpeed
                maxSpeed = calcData.maxSpeed
                rpm = calcData.rpm
                hpPct = calcData.hpPct
                localSpeedFloat = calcData.localSpeedFloat
                isOverSpeed = calcData.isOverSpeed
                gear = calcData.gear
            else
                local res, car = pcall(storeCarCharIsInNoSave, PLAYER_PED)
                if res and car then
                    local existRes, exist = pcall(doesVehicleExist, car)
                    if existRes and exist then
                        local modelRes, carModel = pcall(getCarModel, car)
                        if modelRes and carModel then
                            local vx, vy, vz = getCarSpeedVector(car)
                            localSpeedFloat = math.sqrt(vx^2 + vy^2) * 2.0
                            currentSpeed = math.floor(localSpeedFloat)
                            
                            local originalMaxSpeed = maxSpeeds[carModel] or 85.0
                            maxSpeed = originalMaxSpeed
                            if currentSpeed > maxSpeed then maxSpeed = currentSpeed end

                            local healthRes, health = pcall(getCarHealth, car)
                            if healthRes and health then
                                hpPct = (health - 250) / 750.0
                                if hpPct < 0 then hpPct = 0 elseif hpPct > 1.0 then hpPct = 1.0 end
                            end

                            if cfg.speedo.useDirectStates then
                                local pCar = getCarPointer(car)
                                if pCar ~= 0 then
                                    carData.eng = isCarEngineOn(car)
                                    carData.light = (bit.band(memory.getuint8(pCar + 0x428), 64) ~= 0)
                                    local lockStatus = memory.getuint32(pCar + 0x4F8)
                                    carData.lock = (lockStatus == 2 or lockStatus == 3)
                                end
                            end

                            if isCarEngineOn(car) then
                                local spd = getCarSpeed(car) * 2.0
                                gear = getCarCurrentGear(car)
                                if gear > 0 then
                                    rpm = (spd / gear) * 250.0
                                else
                                    rpm = spd * 180.0
                                end
                                
                                if rpm < 650 then rpm = math.random(650, 900)
                                elseif rpm >= 8000 then rpm = 8000 end
                            end
                            
                            local overThresh = cfg.speedo.overSpeedThreshold or 2
                            if currentSpeed >= originalMaxSpeed + overThresh then
                                isOverSpeed = true
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

            smoothedSpeedScale = smoothedSpeedScale + (speedScale - smoothedSpeedScale) * 0.15
            smoothedRpmPct = smoothedRpmPct + (rpmPct - smoothedRpmPct) * 0.15
            smoothedHpPct = smoothedHpPct + (hpPct - smoothedHpPct) * 0.10

            local isOverSpeed = false
            local checkModelRes, checkCarModel = pcall(getCarModel, storeCarCharIsInNoSave(PLAYER_PED))
            local origMax = 85.0
            if checkModelRes and checkCarModel and maxSpeeds[checkCarModel] then
                origMax = maxSpeeds[checkCarModel]
            end
            local overThresh = cfg.speedo.overSpeedThreshold or 2
            
            if currentSpeed >= origMax + overThresh then
                isOverSpeed = true
            end

            local speedStr = tostring(currentSpeed)
            local fullStr = string.format("%03d", currentSpeed)
            if #fullStr > 3 then fullStr = tostring(currentSpeed) end
            local zeroesCount = #fullStr - #speedStr
            
            local displayStr = fullStr
            if cfg.speedo.gearAsFirstDigit and currentSpeed < 100 then
                displayStr = tostring(gear) .. string.format("%02d", currentSpeed)
            end

            if fontSpeed then imgui.PushFont(fontSpeed) end
            local totalW = 0
            for i = 1, #displayStr do
                totalW = totalW + imgui.CalcTextSize(displayStr:sub(i, i)).x
            end

            local cx = p.x + (winW / 2)
            local startX = cx - totalW / 2
            local startY = p.y + 10 * scale
            local digitY = startY - 20 * scale

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
            local segGap = 4.0 * scale
            local segW = (barW - (segCount - 1) * segGap) / segCount

            local speedBarW = (redZoneStart * segW) + ((redZoneStart - 1) * segGap)
            local speedBarH = 8.0 * scale
            local barY = startY + 175 * scale

            dl:AddRectFilled(imgui.ImVec2(barX, barY), imgui.ImVec2(barX + speedBarW, barY + speedBarH), 0xFF404040, speedBarH / 2)
            
            if smoothedSpeedScale > 0.01 then
                local fillW = speedBarW * smoothedSpeedScale
                if fillW > speedBarW then fillW = speedBarW end
                dl:AddRectFilled(imgui.ImVec2(barX, barY), imgui.ImVec2(barX + fillW, barY + speedBarH), 0xFFFFFFFF, speedBarH / 2)
            end

            local segY = barY + 18 * scale
            local segH = 22 * scale
            
            local activeSegs = 0
            if cfg.speedo.mode == 1 then
                activeSegs = math.floor(smoothedRpmPct * segCount)
            else
                activeSegs = math.floor(smoothedHpPct * segCount)
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

                local curSegH = isRedZone and (segH + 8 * scale) or segH
                local curSegY = isRedZone and (segY - 8 * scale) or segY

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

            local labY = segY + segH + 16 * scale

            local charFirst = "S"

            if fontGears then imgui.PushFont(fontGears) end
            local gearStr = charFirst .. " E L D"
            local gSz = imgui.CalcTextSize(gearStr)
            local bW = gSz.x + 36 * scale
            local bH = gSz.y + 10 * scale
            local bX = p.x + (winW - bW) / 2
            local bY = labY
            if fontGears then imgui.PopFont() end

            local centerY = bY + bH / 2

            if fontLabels then imgui.PushFont(fontLabels) end
            
            local mileNum = tonumber(carData.mile) or 0
            local mileStr = cfg.speedo.showDecimals and string.format("%.1f", mileNum) or tostring(math.floor(mileNum))
            local mileSz = imgui.CalcTextSize(mileStr)
            local roadSz = imgui.CalcTextSize(icons.ROAD)
            
            local gap = 12 * scale
            local innerGap = 6 * scale
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
            local isRedPhase = false
            
            if cfg.speedo.warnLowFuel and fuelVal <= cfg.speedo.lowFuelThreshold then
                local t = math.floor(os.clock() * 1000)
                isRedPhase = (t % 1000 < 500)
                if isRedPhase then
                    pumpCol = 0xFF0000FF
                    fCol = 0xFF0000FF
                end
            end
            
            if isRedPhase and not lastFuelBlinkState then
                addOneOffSound(0.0, 0.0, 0.0, 1057)
            end
            lastFuelBlinkState = isRedPhase
            
            dl:AddText(imgui.ImVec2(fuelStartX, pumpIconY), pumpCol, icons.GAS_PUMP)
            dl:AddText(imgui.ImVec2(fuelStartX + pumpSz.x + innerGap, textY), fCol, fuelStr)
            
            if fontLabels then imgui.PopFont() end

            dl:AddRectFilled(imgui.ImVec2(bX, bY), imgui.ImVec2(bX + bW, bY + bH), 0x99000000, 15.0 * scale)
            dl:AddRect(imgui.ImVec2(bX, bY), imgui.ImVec2(bX + bW, bY + bH), 0xFF69C7C2, 15.0 * scale, 15, 2.0)

            if fontGears then imgui.PushFont(fontGears) end
            
            local sActive = carData.limit

            local sCol = sActive and 0xFF69C7C2 or 0xFF666666
            local eCol = carData.eng and 0xFF69C7C2 or 0xFF666666
            local lCol = carData.light and 0xFF69C7C2 or 0xFF666666
            local dCol = carData.lock and 0xFF69C7C2 or 0xFF666666

            local gearsW = imgui.CalcTextSize(gearStr).x
            local curX_seld = bX + (bW - gearsW) / 2
            local spaceSz = imgui.CalcTextSize(" ").x
            local gY_seld = centerY - imgui.CalcTextSize(charFirst).y / 2
            
            dl:AddText(imgui.ImVec2(curX_seld, gY_seld), sCol, charFirst)
            curX_seld = curX_seld + imgui.CalcTextSize(charFirst).x + spaceSz
            dl:AddText(imgui.ImVec2(curX_seld, gY_seld), eCol, "E")
            curX_seld = curX_seld + imgui.CalcTextSize("E").x + spaceSz
            dl:AddText(imgui.ImVec2(curX_seld, gY_seld), lCol, "L")
            curX_seld = curX_seld + imgui.CalcTextSize("L").x + spaceSz
            dl:AddText(imgui.ImVec2(curX_seld, gY_seld), dCol, "D")
            
            if fontGears then imgui.PopFont() end

            imgui.SetWindowFontScale(1.0)
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
	
    lua_thread.create(function()
        while true do
            wait(50)
            if cfg.main.enabled and carData.show[0] and cfg.main.renderOptimization and isCharInAnyCar(PLAYER_PED) then
                local car = storeCarCharIsInNoSave(PLAYER_PED)
                if doesVehicleExist(car) then
                    local carModel = getCarModel(car)
                    local vx, vy, vz = getCarSpeedVector(car)
                    calcData.localSpeedFloat = math.sqrt(vx^2 + vy^2) * 2.0
                    calcData.currentSpeed = math.floor(calcData.localSpeedFloat)

                    local originalMaxSpeed = maxSpeeds[carModel] or 85.0
                    calcData.maxSpeed = originalMaxSpeed
                    if calcData.currentSpeed > calcData.maxSpeed then calcData.maxSpeed = calcData.currentSpeed end

                    local health = getCarHealth(car)
                    calcData.hpPct = (health - 250) / 750.0
                    if calcData.hpPct < 0 then calcData.hpPct = 0 elseif calcData.hpPct > 1.0 then calcData.hpPct = 1.0 end

                    if cfg.speedo.useDirectStates then
                        local pCar = getCarPointer(car)
                        if pCar ~= 0 then
                            carData.eng = isCarEngineOn(car)
                            carData.light = (bit.band(memory.getuint8(pCar + 0x428), 64) ~= 0)
                            local lockStatus = memory.getuint32(pCar + 0x4F8)
                            carData.lock = (lockStatus == 2 or lockStatus == 3)
                        end
                    end

                    calcData.gear = getCarCurrentGear(car)
                    if isCarEngineOn(car) then
                        local spd = getCarSpeed(car) * 2.0
                        if calcData.gear > 0 then
                            calcData.rpm = (spd / calcData.gear) * 250.0
                        else
                            calcData.rpm = spd * 180.0
                        end

                        if calcData.rpm < 650 then calcData.rpm = math.random(650, 900)
                        elseif calcData.rpm >= 8000 then calcData.rpm = 8000 end
                    else
                        calcData.rpm = 0
                    end

                    local overThresh = cfg.speedo.overSpeedThreshold or 2
                    calcData.isOverSpeed = (calcData.currentSpeed >= originalMaxSpeed + overThresh)
                end
            end
        end
    end)
    
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

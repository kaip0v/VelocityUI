script_name("VelocityUI")
local script_version = 1.0

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

local cfg = inicfg.load({
    main = {
        enabled = true,
        autoUpdate = true
    },
    speedo = {
        mode = 1,
        redlineColor = 1,
        posX = -1.0,
        posY = -1.0
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

local activeTempFiles = {}
local updateUrl = "https://raw.githubusercontent.com/USER/REPO/main/update.json" 

local carData = {
    show = imgui.new.bool(false),
    eng = false,
    limit = false,
    light = false,
    lock = false,
    mile = "0",
    fuel = "0"
}

local maxSpeeds = {
    [400]=98, [401]=91, [402]=116, [403]=68, [404]=81, [405]=99, [406]=88, [407]=98, [408]=78, [409]=90, [410]=91, [411]=138, [412]=93, [413]=88, [414]=90, [415]=120, [416]=62, [417]=105, [418]=81, [419]=93, [420]=98, [421]=93, [422]=90, [423]=81, [424]=93, [425]=124, [426]=105, [427]=93, [428]=93, [429]=110, [430]=98, [431]=81, [432]=81, [433]=93, [434]=110, [435]=81, [436]=93, [437]=81, [438]=93, [439]=105, [440]=93, [441]=90, [442]=75, [443]=93, [444]=100, [445]=98, [446]=93, [447]=93, [448]=81, [449]=93, [450]=93, [451]=120, [452]=93, [453]=81, [454]=81, [455]=105, [456]=93, [457]=93, [458]=98, [459]=90, [460]=93, [461]=105, [462]=105, [463]=105, [464]=81, [465]=81, [466]=105, [467]=105, [468]=105, [469]=93, [470]=105, [471]=105, [472]=93, [473]=93, [474]=98, [475]=98, [476]=110, [477]=105, [478]=98, [479]=98, [480]=98, [481]=93, [482]=105, [483]=93, [484]=93, [485]=93, [486]=93, [487]=93, [488]=93, [489]=105, [490]=105, [491]=93, [492]=105, [493]=93, [494]=110, [495]=105, [496]=105, [497]=93, [498]=93, [499]=93, [500]=105, [501]=93, [502]=105, [503]=105, [504]=105, [505]=98, [506]=110, [507]=90, [508]=105, [509]=93, [510]=93, [511]=105, [512]=105, [513]=93, [514]=93, [515]=105, [516]=98, [517]=98, [518]=98, [519]=93, [520]=93, [521]=105, [522]=105, [523]=105, [524]=93, [525]=93, [526]=105, [527]=105, [528]=105, [529]=105, [530]=93, [531]=93, [532]=93, [533]=105, [534]=105, [535]=105, [536]=105, [537]=93, [538]=93, [539]=105, [540]=105, [541]=126, [542]=105, [543]=93, [544]=98, [545]=105, [546]=105, [547]=105, [548]=93, [549]=105, [550]=105, [551]=105, [552]=105, [553]=130, [554]=105, [555]=105, [556]=105, [557]=105, [558]=105, [559]=105, [560]=94, [561]=105, [562]=105, [563]=93, [564]=93, [565]=105, [566]=105, [567]=105, [568]=105, [569]=105, [570]=105, [571]=105, [572]=105, [573]=105, [574]=93, [575]=105, [576]=105, [577]=105, [578]=105, [579]=105, [580]=105, [581]=105, [582]=105, [583]=105, [584]=105, [585]=105, [586]=105, [587]=105, [588]=105, [589]=105, [590]=105, [591]=105, [592]=105, [593]=105, [594]=105, [595]=105, [596]=105, [597]=105, [598]=105, [599]=105, [600]=105, [601]=105, [602]=105, [603]=105, [604]=105, [605]=105, [606]=105, [607]=105, [608]=105, [609]=105, [610]=105, [611]=105
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
                pcall(function()
                    local func = load("return " .. content)
                    if func then data = func() end
                end)
                if data and data.version and data.url then
                    if tonumber(data.version) > tonumber(script_version) then
                        sampAddChatMessage("{00FF00}[VelocityUI] {FFFFFF}Найдено обновление! Загрузка...", -1)
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
                                            sampAddChatMessage("{00FF00}[VelocityUI] {FFFFFF}Успешно обновлено! Перезапуск...", -1)
                                            lua_thread.create(function()
                                                wait(1500)
                                                thisScript():reload()
                                            end)
                                        end
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
                cfg.zone.minX = math.min(selStartX, selEndX)
                cfg.zone.maxX = math.max(selStartX, selEndX)
                cfg.zone.minY = math.min(selStartY, selEndY)
                cfg.zone.maxY = math.max(selStartY, selEndY)
                inicfg.save(cfg, 'VelocityUI.ini')
                isSelectingZone = false
                showSettings[0] = true
            end
            return
        end

        imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(500, 350), imgui.Cond.FirstUseEver)
        
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 6.0)
        imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 6.0)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 8.0)

        if imgui.Begin("VelocityUI Settings", showSettings, imgui.WindowFlags.NoCollapse) then
            if imgui.BeginTabBar("SettingsTabs") then
                
                if imgui.BeginTabItem(u8"Спидометр") then
                    imgui.Spacing()
                    
                    local bEnabled = imgui.new.bool(cfg.main.enabled)
                    if imgui.Checkbox(u8"Включить кастомный спидометр", bEnabled) then
                        cfg.main.enabled = bEnabled[0]
                        inicfg.save(cfg, 'VelocityUI.ini')
                    end
                    
                    imgui.Spacing()
                    imgui.Separator()
                    imgui.Spacing()

                    imgui.Text(u8"Режим полосы:")
                    local rMode1 = imgui.new.bool(cfg.speedo.mode == 1)
                    local rMode2 = imgui.new.bool(cfg.speedo.mode == 2)
                    if imgui.RadioButton(u8"Тахометр (Обороты)", rMode1) then
                        cfg.speedo.mode = 1
                        inicfg.save(cfg, 'VelocityUI.ini')
                    end
                    imgui.SameLine()
                    if imgui.RadioButton(u8"Состояние (ХП авто)", rMode2) then
                        cfg.speedo.mode = 2
                        inicfg.save(cfg, 'VelocityUI.ini')
                    end

                    imgui.Spacing()

                    imgui.Text(u8"Цвет активных делений:")
                    local rCol1 = imgui.new.bool(cfg.speedo.redlineColor == 1)
                    local rCol2 = imgui.new.bool(cfg.speedo.redlineColor == 2)
                    if imgui.RadioButton(u8"Красный", rCol1) then
                        cfg.speedo.redlineColor = 1
                        inicfg.save(cfg, 'VelocityUI.ini')
                    end
                    imgui.SameLine()
                    if imgui.RadioButton(u8"Белый", rCol2) then
                        cfg.speedo.redlineColor = 2
                        inicfg.save(cfg, 'VelocityUI.ini')
                    end

                    imgui.Spacing()
                    imgui.Separator()
                    imgui.Spacing()

                    imgui.Text(u8"Удаление серверного спидометра:")
                    if imgui.Button(u8"Выделить зону мышью", imgui.ImVec2(0, 0)) then
                        showSettings[0] = false
                        isSelectingZone = true
                    end
                    
                    imgui.Spacing()
                    imgui.Separator()
                    imgui.Spacing()
                    
                    local bUpdate = imgui.new.bool(cfg.main.autoUpdate)
                    if imgui.Checkbox(u8"Автообновление скрипта", bUpdate) then
                        cfg.main.autoUpdate = bUpdate[0]
                        inicfg.save(cfg, 'VelocityUI.ini')
                    end

                    imgui.EndTabItem()
                end

                if imgui.BeginTabItem(u8"HUD") then
                    imgui.Spacing()
                    imgui.Text(u8"В разработке...")
                    imgui.EndTabItem()
                end

                imgui.EndTabBar()
            end
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

        if cfg.speedo.posX == -1.0 then
            cfg.speedo.posX = resX - winW - 30
            cfg.speedo.posY = resY - winH - 30
            inicfg.save(cfg, 'VelocityUI.ini')
        end

        imgui.SetNextWindowPos(imgui.ImVec2(cfg.speedo.posX, cfg.speedo.posY), imgui.Cond.FirstUseEver)
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

            local res, car = pcall(storeCarCharIsInNoSave, PLAYER_PED)
            if res and car then
                local existRes, exist = pcall(doesVehicleExist, car)
                if existRes and exist then
                    local modelRes, carModel = pcall(getCarModel, car)
                    if modelRes and carModel then
                        local vx, vy, vz = getCarSpeedVector(car)
                        localSpeedFloat = math.sqrt(vx^2 + vy^2) * 2.0
                        currentSpeed = math.floor(localSpeedFloat)
                        
                        maxSpeed = maxSpeeds[carModel] or 120.0
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

            if fontSpeed then imgui.PushFont(fontSpeed) end
            local totalW = 0
            for i = 1, #fullStr do
                totalW = totalW + imgui.CalcTextSize(fullStr:sub(i, i)).x
            end

            local cx = p.x + (winW / 2)
            local startX = cx - totalW / 2
            local startY = p.y + 10
            local digitY = startY - 20

            local curX = startX
            for i = 1, #fullStr do
                local char = fullStr:sub(i, i)
                local col = (i <= zeroesCount) and 0x35FFFFFF or 0xFFFFFFFF
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
            
            local mileStr = tostring(math.floor(tonumber(carData.mile) or 0))
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
            
            local fuelStr = tostring(math.floor(tonumber(carData.fuel) or 0)) .. " L"
            local fSz = imgui.CalcTextSize(fuelStr)
            local pumpSz = imgui.CalcTextSize(icons.GAS_PUMP)
            
            local fuelStartX = bX + bW + gap
            local pumpIconY = centerY - pumpSz.y / 2
            
            dl:AddText(imgui.ImVec2(fuelStartX, pumpIconY), 0xFFAAAAAA, icons.GAS_PUMP)
            dl:AddText(imgui.ImVec2(fuelStartX + pumpSz.x + innerGap, textY), 0xFFFFFFFF, fuelStr)
            
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

local function processTextDraw(id, text, pos, letY)
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

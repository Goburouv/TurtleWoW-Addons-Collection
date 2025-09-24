setfenv(1, VoiceOver)

---@class QuestPlayButton : Button
---@field soundData SoundData

QuestOverlayUI = {
    ---@type table<number, QuestPlayButton>
    questPlayButtons = {},
    ---@type QuestPlayButton[]
    displayedButtons = {},
    ---@type table<number, table> Caché para misiones similares
    similarityCache = {},
}

function QuestOverlayUI:CreatePlayButton(questID)
    local playButton = CreateFrame("Button", nil, QuestLogFrame)
    playButton:SetWidth(20)
    playButton:SetHeight(20)
    playButton:SetHitRectInsets(2, 2, 2, 2)
    playButton:SetNormalTexture([[Interface\AddOns\AI_VoiceOver\Textures\QuestLogPlayButton]])
    playButton:SetDisabledTexture([[Interface\AddOns\AI_VoiceOver\Textures\QuestLogPlayButton]])
    playButton:GetDisabledTexture():SetDesaturated(true)
    playButton:GetDisabledTexture():SetAlpha(0.33)
    playButton:SetHighlightTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Highlight")
    ---@cast playButton QuestPlayButton
    self.questPlayButtons[questID] = playButton
end

local prefix
function QuestOverlayUI:UpdateQuestTitle(questLogTitleFrame, playButton, normalText, questCheck)
    if not prefix then
        local text = normalText:GetText()
        for i = 1, 20 do
            normalText:SetText(string.rep(" ", i))
            if normalText:GetStringWidth() >= 24 then
                prefix = normalText:GetText()
                break
            end
        end
        prefix = prefix or "  "
        normalText:SetText(text)
    end

    -- Comprobar si PfQuest está instalado
    local isPfQuestLoaded = IsAddOnLoaded("pfQuest") or IsAddOnLoaded("pfQuest-tbc") or IsAddOnLoaded("pfQuest-wotlk")
    
    if isPfQuestLoaded then
        -- Posicionamiento alternativo cuando PfQuest está activo
        playButton:ClearAllPoints()
        playButton:SetPoint("LEFT", normalText, "LEFT", -16, 0)
    else
        -- Posicionamiento normal
        playButton:ClearAllPoints()
        playButton:SetPoint("LEFT", normalText, "LEFT", 4, 0)
    end

    local formatedText = prefix .. string.trim(normalText:GetText() or "")

    normalText:SetText(formatedText)
    QuestLogDummyText:SetText(formatedText)

    -- Actualizar la posición del check también según si PfQuest está cargado
    if not isPfQuestLoaded then
        questCheck:SetPoint("LEFT", normalText, "LEFT", normalText:GetStringWidth(), 0)
    end
end

function QuestOverlayUI:UpdatePlayButtonTexture(questID)
    local button = self.questPlayButtons[questID]
    if button then
        local isPlaying = button.soundData and SoundQueue:Contains(button.soundData)
        local texturePath = isPlaying and [[Interface\AddOns\AI_VoiceOver\Textures\QuestLogStopButton]] or [[Interface\AddOns\AI_VoiceOver\Textures\QuestLogPlayButton]]
        button:SetNormalTexture(texturePath)
    end
end

-- Verificar caché para misiones similares
function QuestOverlayUI:GetCachedSimilarQuest(questID, eventCategory)
    if self.similarityCache[questID] and self.similarityCache[questID][eventCategory] then
        return self.similarityCache[questID][eventCategory]
    end
    return nil
end

-- Guardar en caché el resultado de la búsqueda
function QuestOverlayUI:CacheSimilarQuest(questID, eventCategory, similarData)
    if not self.similarityCache[questID] then
        self.similarityCache[questID] = {}
    end
    self.similarityCache[questID][eventCategory] = similarData
end

function QuestOverlayUI:UpdatePlayButton(soundTitle, questID, questLogTitleFrame, normalText, questCheck)
    self.questPlayButtons[questID]:SetParent(questLogTitleFrame:GetParent())
    self.questPlayButtons[questID]:SetFrameLevel(questLogTitleFrame:GetFrameLevel() + 2)

    QuestOverlayUI:UpdateQuestTitle(questLogTitleFrame, self.questPlayButtons[questID], normalText, questCheck)

    self.questPlayButtons[questID]:SetScript("OnClick", function(self)
        if not QuestOverlayUI.questPlayButtons[questID].soundData then
            local type, id = DataModules:GetQuestLogQuestGiverTypeAndID(questID)
            QuestOverlayUI.questPlayButtons[questID].soundData = {
                event = Enums.SoundEvent.QuestAccept,
                questID = questID,
                name = id and DataModules:GetObjectName(type, id) or "Unknown Name",
                title = soundTitle,
                unitGUID = id and Enums.GUID:CanHaveID(type) and Utils:MakeGUID(type, id) or nil
            }
        end

        local soundData = self.soundData
        local questID = soundData.questID
        local isPlaying = SoundQueue:Contains(soundData)

        if not isPlaying then
            -- Intentar preparar el sonido directamente primero
            local soundFound = DataModules:PrepareSound(soundData)
            
            -- Si no se encuentra el sonido exacto, buscar una misión similar
            if not soundFound and Addon and Addon.GetSimilarQuestID then
                local eventCategory = "accept" -- Para búsqueda de similitud
                
                -- Verificar si tenemos un resultado en caché primero
                local cachedResult = QuestOverlayUI:GetCachedSimilarQuest(questID, eventCategory)
                
                if cachedResult then
                    if cachedResult.similarQuestID then
                        -- Usar los datos en caché para crear el soundData similar
                        local similarSoundData = {
                            event = Enums.SoundEvent.QuestAccept,
                            questID = cachedResult.similarQuestID,
                            name = cachedResult.npcName,
                            title = soundData.title,
                            unitGUID = cachedResult.unitGUID
                        }
                        
                        -- Intentar preparar con el ID similar
                        soundFound = DataModules:PrepareSound(similarSoundData)
                        
                        if soundFound then
                            -- Reemplazar el soundData original con el similar
                            self.soundData = similarSoundData
                            soundData = similarSoundData
                            
                            -- Mostrar mensaje detallado sobre la misión similar incluyendo información del NPC
                            DebugPrint("|cFF9900FF[VoiceOver]|r Reproduciendo audio de misión similar - ID:" .. cachedResult.similarQuestID .. " - NPC: " .. cachedResult.npcName .. " (ID:" .. cachedResult.npcID .. ") [Caché]")
                        end
                    end
                else
                    -- No hay caché, realizar la búsqueda normal
                    -- Buscar el índice de la misión manualmente en Vanilla WoW
                    local questText = ""
                    local questIndex = nil
                    
                    -- Recorrer todas las misiones en el registro para encontrar la que coincide con nuestro questID
                    local numEntries = GetNumQuestLogEntries()
                    for i = 1, numEntries do
                        local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, qID = GetQuestLogTitle(i)
                        if not isHeader and qID == questID then
                            questIndex = i
                            break
                        end
                    end
                    
                    -- Si encontramos el índice, obtener el texto de la misión
                    if questIndex then
                        -- Guardar la selección actual
                        local oldSelection = GetQuestLogSelection()
                        -- Seleccionar la misión que queremos
                        SelectQuestLogEntry(questIndex)
                        -- Obtener el texto
                        questText = GetQuestLogQuestText()
                        -- Restaurar la selección anterior
                        if oldSelection > 0 then
                            SelectQuestLogEntry(oldSelection)
                        end
                    end
                    
                    local npcName = soundData.name
                    
                    local similarQuestID = Addon:GetSimilarQuestID(questText, eventCategory, soundData.title, npcName)
                    
                    if similarQuestID then
                        -- Obtener información del NPC de la misión similar
                        local similarType, similarNpcID = DataModules:GetQuestLogQuestGiverTypeAndID(similarQuestID)
                        local similarNpcName = similarNpcID and DataModules:GetObjectName(similarType, similarNpcID) or "NPC Desconocido"
                        local similarGUID = similarNpcID and Enums.GUID:CanHaveID(similarType) and Utils:MakeGUID(similarType, similarNpcID) or soundData.unitGUID
                        
                        -- Guardar en caché
                        QuestOverlayUI:CacheSimilarQuest(questID, eventCategory, {
                            similarQuestID = similarQuestID,
                            npcName = similarNpcName,
                            npcID = similarNpcID,
                            unitGUID = similarGUID
                        })
                        
                        -- Crear nuevo soundData con el questID similar
                        local similarSoundData = {
                            event = Enums.SoundEvent.QuestAccept,
                            questID = similarQuestID,
                            name = similarNpcName or soundData.name, -- Usar el nombre del NPC similar si está disponible
                            title = soundData.title,
                            unitGUID = similarGUID
                        }
                        
                        -- Intentar preparar con el ID similar
                        soundFound = DataModules:PrepareSound(similarSoundData)
                        
                        if soundFound then
                            -- Reemplazar el soundData original con el similar
                            self.soundData = similarSoundData
                            soundData = similarSoundData
                            
                            -- Mostrar mensaje detallado sobre la misión similar incluyendo información del NPC
                            local npcInfo = ""
                            if similarNpcID then
                                npcInfo = " - NPC: " .. similarNpcName .. " (ID:" .. similarNpcID .. ")"
                            end
                            
                            DebugPrint("|cFF9900FF[VoiceOver]|r Reproduciendo audio de misión similar - ID:" .. similarQuestID .. npcInfo)
                        end
                    else
                        -- Guardar un resultado negativo en caché también
                        QuestOverlayUI:CacheSimilarQuest(questID, eventCategory, { similarQuestID = nil })
                    end
                end
            end
            
            -- Si se encontró el sonido (original o similar), reproducirlo
            if soundData.filePath then
                SoundQueue:AddSoundToQueue(soundData)
                QuestOverlayUI:UpdatePlayButtonTexture(questID)

                soundData.stopCallback = function()
                    QuestOverlayUI:UpdatePlayButtonTexture(questID)
                    self.soundData = nil
                end
            else
                -- Informar que no se encontró ningún audio con más detalle sobre la misión actual
                local currentNpcInfo = ""
                local type, id = DataModules:GetQuestLogQuestGiverTypeAndID(questID)
                local npcName = id and DataModules:GetObjectName(type, id) or "NPC Desconocido"
                
                if id then
                    currentNpcInfo = " (NPC: " .. npcName .. ", ID:" .. id .. ")"
                end
                
                DebugPrint("|cFFFF0000[VoiceOver]|r No se encontró audio para esta misión" .. currentNpcInfo .. " ni misiones similares.")
            end
        else
            SoundQueue:RemoveSoundFromQueue(soundData)
        end
    end)
end

function QuestOverlayUI:Update()
    if not QuestLogFrame:IsShown() then
        return
    end

    local numEntries, numQuests = GetNumQuestLogEntries()

    -- Hide all buttons in displayedButtons
    for _, button in pairs(self.displayedButtons) do
        button:Hide()
    end

    if numEntries == 0 then
        return
    end

    -- Clear displayedButtons
    table.wipe(self.displayedButtons)

    -- Traverse through the quests displayed in the UI
    for i = 1, QUESTS_DISPLAYED do
        local questIndex = i + Utils:GetQuestLogScrollOffset();
        if questIndex > numEntries then
            break
        end

        -- Get quest title
        local questLogTitleFrame = Utils:GetQuestLogTitleFrame(i)
        local normalText = Utils:GetQuestLogTitleNormalText(i)
        local questCheck = Utils:GetQuestLogTitleCheck(i)
        local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID = GetQuestLogTitle(
            questIndex)

        if not isHeader then
            if not self.questPlayButtons[questID] then
                self:CreatePlayButton(questID)
            end

            -- Siempre actualizar y habilitar el botón, ya que ahora usamos similitud
            self:UpdatePlayButton(title, questID, questLogTitleFrame, normalText, questCheck)
            self.questPlayButtons[questID]:Enable()
            
            self.questPlayButtons[questID]:Show()
            self:UpdatePlayButtonTexture(questID)

            -- Add the button to displayedButtons
            table.insert(self.displayedButtons, self.questPlayButtons[questID])
        end
    end
end

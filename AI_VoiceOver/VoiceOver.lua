setfenv(1, VoiceOver)

-- Función para depuración controlada
function DebugPrint(message)
    if Addon and Addon.db and Addon.db.profile and Addon.db.profile.DebugEnabled then
        print(message)
    end
end

---@class Addon : AceAddon, AceAddon-3.0, AceEvent-3.0, AceTimer-3.0
---@field db VoiceOverConfig|AceDBObject-3.0
Addon = LibStub("AceAddon-3.0"):NewAddon("VoiceOver", "AceEvent-3.0", "AceTimer-3.0")

Addon.OnAddonLoad = {}

---@class VoiceOverConfig
local defaults = {
    profile = {
        SoundQueueUI = {
            LockFrame = false,
            FrameScale = 0.7,
            FrameStrata = "HIGH",
            HidePortrait = false,
            HideFrame = false,
        },
        Audio = {
            GossipFrequency = Enums.GossipFrequency.OncePerQuestNPC,
            SoundChannel = Enums.SoundChannel.Master,
            AutoToggleDialog = Version.IsLegacyVanilla or Version:IsRetailOrAboveLegacyVersion(60100),
            StopAudioOnDisengage = false,
        },
        MinimapButton = {
            LibDBIcon = {}, -- Table used by LibDBIcon to store position (minimapPos), dragging lock (lock) and hidden state (hide)
            Commands = {
                -- References keys from Options.table.args.SlashCommands.args table
                LeftButton = "Options",
                MiddleButton = "PlayPause",
                RightButton = "Clear",
            }
        },
        LegacyWrath = (Version.IsLegacyWrath or Version.IsLegacyBurningCrusade or nil) and {
            PlayOnMusicChannel = {
                Enabled = true,
                Volume = 1,
                FadeOutMusic = 0.5,
            },
            HDModels = false,
        },
        DebugEnabled = false,
    },
    char = {
        IsPaused = false,
        hasSeenGossipForNPC = {},
        RecentQuestTitleToID = Version:IsBelowLegacyVersion(30300) and {},
    }
}

local lastGossipOptions
local selectedGossipOption
local currentQuestSoundData
local currentGossipSoundData

function Addon:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("VoiceOverDB", defaults)
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

    StaticPopupDialogs["VOICEOVER_ERROR"] =
    {
        text = "VoiceOver|n|n%s",
        button1 = OKAY,
        timeout = 0,
        whileDead = 1,
    }

    SoundQueueUI:Initialize()
    DataModules:EnumerateAddons()
    Options:Initialize()

    self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("QUEST_DETAIL")
    -- self:RegisterEvent("QUEST_PROGRESS")
    self:RegisterEvent("QUEST_COMPLETE")
    self:RegisterEvent("QUEST_GREETING")
    self:RegisterEvent("QUEST_FINISHED")
    self:RegisterEvent("GOSSIP_SHOW")
    self:RegisterEvent("GOSSIP_CLOSED")

    if select(5, GetAddOnInfo("VoiceOver")) ~= "MISSING" then
        DisableAddOn("VoiceOver")
        if not self.db.profile.SeenDuplicateDialog then
            StaticPopupDialogs["VOICEOVER_DUPLICATE_ADDON"] =
            {
                text = [[VoiceOver|n|nTo fix the quest autoaccept bugs we had to rename the addon folder. If you're seeing this popup, it means the old one wasn't automatically removed.|n|nYou can safely delete "VoiceOver" from your Addons folder. "AI_VoiceOver" is the new folder.]],
                button1 = OKAY,
                timeout = 0,
                whileDead = 1,
                OnAccept = function()
                    self.db.profile.SeenDuplicateDialog = true
                end,
            }
            StaticPopup_Show("VOICEOVER_DUPLICATE_ADDON")
        end
    end

    if select(5, GetAddOnInfo("AI_VoiceOver_112")) ~= "MISSING" then
        DisableAddOn("AI_VoiceOver_112")
        if not self.db.profile.SeenDuplicateDialog112 then
            StaticPopupDialogs["VOICEOVER_DUPLICATE_ADDON_112"] =
            {
                text = [[VoiceOver|n|nVoiceOver port for 1.12 has been merged together with other versions and is no longer distributed as a separate addon.|n|nYou can safely delete "AI_VoiceOver_112" from your Addons folder. "AI_VoiceOver" is the new folder.]],
                button1 = OKAY,
                timeout = 0,
                whileDead = 1,
                OnAccept = function()
                    self.db.profile.SeenDuplicateDialog112 = true
                end,
            }
            StaticPopup_Show("VOICEOVER_DUPLICATE_ADDON_112")
        end
    end

    if not DataModules:HasRegisteredModules() then
        StaticPopupDialogs["VOICEOVER_NO_REGISTERED_DATA_MODULES"] =
        {
            text = [[VoiceOver|n|nNo sound packs were found.|n|nUse the "/vo options" command, (or Interface Options in newer clients) and go to the DataModules tab for information on where to download sound packs.]],
            button1 = OKAY,
            timeout = 0,
            whileDead = 1,
        }
        StaticPopup_Show("VOICEOVER_NO_REGISTERED_DATA_MODULES")
    end

    local function MakeAbandonQuestHook(field, getFieldData)
        return function()
            local data = getFieldData()
            local soundsToRemove = {}
            for _, soundData in pairs(SoundQueue.sounds) do
                if Enums.SoundEvent:IsQuestEvent(soundData.event) and soundData[field] == data then
                    table.insert(soundsToRemove, soundData)
                end
            end

            for _, soundData in pairs(soundsToRemove) do
                SoundQueue:RemoveSoundFromQueue(soundData)
            end
        end
    end
    if C_QuestLog and C_QuestLog.AbandonQuest then
        hooksecurefunc(C_QuestLog, "AbandonQuest", MakeAbandonQuestHook("questID", function() return C_QuestLog.GetAbandonQuest() end))
    elseif AbandonQuest then
        hooksecurefunc("AbandonQuest", MakeAbandonQuestHook("questName", function() return GetAbandonQuestName() end))
    end

    if QuestLog_Update then
        hooksecurefunc("QuestLog_Update", function()
            QuestOverlayUI:Update()
        end)
    end

    if C_GossipInfo and C_GossipInfo.SelectOption then
        hooksecurefunc(C_GossipInfo, "SelectOption", function(optionID)
            if lastGossipOptions then
                for _, info in ipairs(lastGossipOptions) do
                    if info.gossipOptionID == optionID then
                        selectedGossipOption = info.name
                        break
                    end
                end
                lastGossipOptions = nil
            end
        end)
    elseif SelectGossipOption then
        hooksecurefunc("SelectGossipOption", function(index)
            if lastGossipOptions then
                selectedGossipOption = lastGossipOptions[1 + (index - 1) * 2]
                lastGossipOptions = nil
            end
        end)
    end
end

function Addon:RefreshConfig()
    SoundQueueUI:RefreshConfig()
end

function Addon:ADDON_LOADED(event, addon)
    addon = addon or arg1 -- Thanks, Ace3v...
    local hook = self.OnAddonLoad[addon]
    if hook then
        hook()
    end
end

local function GossipSoundDataAdded(soundData)
    Utils:CreateNPCModelFrame(soundData)

    -- Save current gossip sound data for dialog/frame sync option
    currentGossipSoundData = soundData
end

local function QuestSoundDataAdded(soundData)
    Utils:CreateNPCModelFrame(soundData)

    -- Save current quest sound data for dialog/frame sync option
    currentQuestSoundData = soundData
end

local GetTitleText = GetTitleText -- Store original function before EQL3 (Extended Quest Log 3) overrides it and starts prepending quest level
function Addon:QUEST_DETAIL()
    local questID = GetQuestID()
    local questTitle = GetTitleText()
    local questText = GetQuestText()
    local guid = Utils:GetNPCGUID()
    local targetName = Utils:GetNPCName()
    
    -- Calcular el ID del NPC si es posible
    local npcId = "N/A"
    if guid then
        local type = Utils:GetGUIDType(guid)
        if type and Enums.GUID:CanHaveID(type) then
            npcId = Utils:GetIDFromGUID(guid)
        end
    end

    DebugPrint("|cFF00FF00[QUEST_DETAIL] Misión detectada: " .. (questTitle or "Sin título") .. " (ID: " .. (questID or "desconocido") .. ")|r")
    DebugPrint("|cFF00FF00[QUEST_DETAIL] NPC: " .. (targetName or "Desconocido") .. " (ID: " .. npcId .. ")|r")
    
    -- Can happen if the player interacted with an NPC while having main menu or options opened
    if not guid and not targetName then
        DebugPrint("|cFF00FF00[QUEST_DETAIL] No se encontró GUID o nombre del NPC, saliendo|r")
        return
    end

    if Addon.db.char.RecentQuestTitleToID and questID ~= 0 then
        Addon.db.char.RecentQuestTitleToID[questTitle] = questID
    end

    local type = guid and Utils:GetGUIDType(guid)
    if type == Enums.GUID.Item then
        -- Allow quests started from items to have VO, book icon will be displayed for them
        DebugPrint("|cFF00FF00[QUEST_DETAIL] Misión iniciada por un item|r")
    elseif not type or not Enums.GUID:CanHaveID(type) then
        -- If the quest is started by something that we cannot extract the ID of (e.g. Player, when sharing a quest) - try to fallback to a questgiver from a module's database
        DebugPrint("|cFF00FF00[QUEST_DETAIL] No se pudo extraer ID del GUID, intentando fallback a base de datos|r")
        local id
        type, id = DataModules:GetQuestLogQuestGiverTypeAndID(questID)
        guid = id and Enums.GUID:CanHaveID(type) and Utils:MakeGUID(type, id) or guid
        targetName = id and DataModules:GetObjectName(type, id) or targetName or "Unknown Name"
    end

    -- Match quest text with similarity database even if questID is 0 or invalid
    DebugPrint("|cFF00FF00[QUEST_DETAIL] Buscando similitud de texto de misión...|r")
    local similarQuestID = self:GetSimilarQuestID(questText, Enums.SoundEvent.QuestAccept, questTitle, targetName)
    if similarQuestID then
        DebugPrint("|cFF00FF00[QUEST_DETAIL] Se encontró similar questID: " .. similarQuestID .. (questID and questID ~= 0 and " (original: " .. questID .. ")" or "") .. "|r")
        questID = similarQuestID
    else
        DebugPrint("|cFF00FF00[QUEST_DETAIL] No se encontró texto similar|r")
        -- Si el questID es 0 o inválido y no encontramos similitud, no podemos reproducir audio
        if not questID or questID == 0 then
            DebugPrint("|cFF00FF00[QUEST_DETAIL] Sin ID válido y sin coincidencia de texto, no se puede reproducir audio|r")
            return
        end
    end

    -- print("QUEST_DETAIL", questID, questTitle);
    ---@type SoundData
    local soundData = {
        event = Enums.SoundEvent.QuestAccept,
        questID = questID,
        name = targetName,
        title = questTitle,
        text = questText,
        unitGUID = guid,
        unitIsObjectOrItem = Utils:IsNPCObjectOrItem(),
        addedCallback = QuestSoundDataAdded,
    }
    DebugPrint("|cFF00FF00[QUEST_DETAIL] Añadiendo sonido a la cola - QuestID: " .. questID .. ", Título: " .. (questTitle or "Sin título") .. "|r")
    SoundQueue:AddSoundToQueue(soundData)
end

function Addon:QUEST_COMPLETE()
    local questID = GetQuestID()
    local questTitle = GetTitleText()
    local questText = GetRewardText()
    local guid = Utils:GetNPCGUID()
    local targetName = Utils:GetNPCName()
    
    -- Calcular el ID del NPC si es posible
    local npcId = "N/A"
    if guid then
        local type = Utils:GetGUIDType(guid)
        if type and Enums.GUID:CanHaveID(type) then
            npcId = Utils:GetIDFromGUID(guid)
        end
    end

    DebugPrint("|cFF00FF00[QUEST_COMPLETE] Misión completada: " .. (questTitle or "Sin título") .. " (ID: " .. (questID or "desconocido") .. ")|r")
    DebugPrint("|cFF00FF00[QUEST_COMPLETE] NPC: " .. (targetName or "Desconocido") .. " (ID: " .. npcId .. ")|r")
    
    -- Can happen if the player interacted with an NPC while having main menu or options opened
    if not guid and not targetName then
        DebugPrint("|cFF00FF00[QUEST_COMPLETE] No se encontró GUID o nombre del NPC, saliendo|r")
        return
    end

    if Addon.db.char.RecentQuestTitleToID and questID ~= 0 then
        Addon.db.char.RecentQuestTitleToID[questTitle] = questID
    end

    -- Match quest text with similarity database even if questID is 0 or invalid
    DebugPrint("|cFF00FF00[QUEST_COMPLETE] Buscando similitud de texto de misión...|r")
    local similarQuestID = self:GetSimilarQuestID(questText, Enums.SoundEvent.QuestComplete, questTitle, targetName)
    if similarQuestID then
        DebugPrint("|cFF00FF00[QUEST_COMPLETE] Se encontró similar questID: " .. similarQuestID .. (questID and questID ~= 0 and " (original: " .. questID .. ")" or "") .. "|r")
        questID = similarQuestID
    else
        DebugPrint("|cFF00FF00[QUEST_COMPLETE] No se encontró texto similar|r")
        -- Si el questID es 0 o inválido y no encontramos similitud, no podemos reproducir audio
        if not questID or questID == 0 then
            DebugPrint("|cFF00FF00[QUEST_COMPLETE] Sin ID válido y sin coincidencia de texto, no se puede reproducir audio|r")
            return
        end
    end

    -- print("QUEST_COMPLETE", questID, questTitle);
    ---@type SoundData
    local soundData = {
        event = Enums.SoundEvent.QuestComplete,
        questID = questID,
        name = targetName,
        title = questTitle,
        text = questText,
        unitGUID = guid,
        unitIsObjectOrItem = Utils:IsNPCObjectOrItem(),
        addedCallback = QuestSoundDataAdded,
    }
    DebugPrint("|cFF00FF00[QUEST_COMPLETE] Añadiendo sonido a la cola - QuestID: " .. questID .. ", Título: " .. (questTitle or "Sin título") .. "|r")
    SoundQueue:AddSoundToQueue(soundData)
end

-- Función para encontrar una misión similar basada en texto
function Addon:GetSimilarQuestID(text, event, questTitle, npcName)
    -- Asegúrate de que el texto es válido
    if not text or text == "" then
        DebugPrint("|cFF00FF00[QuestSimilarity] No hay texto para comparar|r")
        return nil
    end
    
    -- Determinar el tipo de evento para buscar en la categoría correcta
    local eventCategory = "accept"
    if event == Enums.SoundEvent.QuestComplete then
        eventCategory = "complete"
    end
    
    DebugPrint("|cFF00FF00[QuestSimilarity] Buscando coincidencias para evento: " .. eventCategory .. "|r")
    DebugPrint("|cFF00FF00[QuestSimilarity] NPC: " .. (npcName or "Desconocido") .. ", Título: " .. (questTitle or "Desconocido") .. "|r")
    
    -- Imprimir el texto original de la misión para verificarlo
    DebugPrint("|cFF00FF00[QuestSimilarity] ------- TEXTO ORIGINAL DE LA MISIÓN --------")
    DebugPrint("|cFF00FF00" .. tostring(text) .. "|r")
    DebugPrint("|cFF00FF00[QuestSimilarity] --------------------------------------------|r")
    
    local bestMatch = nil            -- ID de la mejor misión encontrada
    local highestTextSim = 0.15      -- Similitud del texto (umbral mínimo 15%)
    local highestTitleSim = 0        -- Similitud del título
    local highestNpcSim = 0          -- Similitud del NPC
    local bestCombinedSim = 0.15     -- Similitud combinada ponderada
    local totalQuestsAnalyzed = 0
    
    -- Recorre todos los módulos de datos para buscar similitudes
    for _, module in DataModules:GetModules() do
        local moduleAddonName = module.METADATA and module.METADATA.AddonName or "Desconocido"
        local questIDs = {}  -- Conjunto de QuestIDs encontrados
        
        DebugPrint("|cFFFF9900[QuestSimilarity] Analizando módulo: " .. moduleAddonName .. "|r")
        
        -- 1. COMPARANDO TEXTOS DE MISIÓN
        if module.QuestTextSimilarity and module.QuestTextSimilarity[eventCategory] then
            DebugPrint("|cFFFF9900[QuestSimilarity] Analizando textos de misión...|r")
            
            local questCount = 0
            for questID, questText in pairs(module.QuestTextSimilarity[eventCategory]) do
                if type(questID) == "number" and type(questText) == "string" then
                    questCount = questCount + 1
                    totalQuestsAnalyzed = totalQuestsAnalyzed + 1
                    questIDs[questID] = true
                    
                    -- Calcular similitud del texto
                    local textSim = textSimilarity(text, questText)
                    
                    -- Si mejora la mejor similitud de texto actual
                    if textSim > highestTextSim then
                        highestTextSim = textSim
                        
                        -- Mostrar coincidencias altas
                        if textSim >= 0.3 then
                            local colorCode = "|cFFFF0000" -- Rojo para similitud > 30%
                            if textSim > 0.6 then
                                colorCode = "|cFF9900FF" -- Morado para similitud > 60%
                            elseif textSim > 0.5 then
                                colorCode = "|cFFFFFF00" -- Amarillo para similitud > 50%
                            end
                            DebugPrint(colorCode .. "[QuestSimilarity] Alta similitud de texto para QuestID: " .. questID .. 
                                  " - Sim: " .. math.floor(textSim * 100) .. "%|r")
                        end
                    end
                end
            end
            
            DebugPrint("|cFFFFFF00[QuestSimilarity] Analizados " .. questCount .. " textos de misión.|r")
        end
        
        -- 2. COMPARANDO TÍTULOS DE MISIÓN
        if module.QuestTitleSimilarity and module.QuestTitleSimilarity[eventCategory] and questTitle then
            DebugPrint("|cFFFF9900[QuestSimilarity] Analizando títulos de misión...|r")
            
            local questCount = 0
            for questID, title in pairs(module.QuestTitleSimilarity[eventCategory]) do
                if type(questID) == "number" and type(title) == "string" then
                    questCount = questCount + 1
                    totalQuestsAnalyzed = totalQuestsAnalyzed + 1
                    questIDs[questID] = true
                    
                    -- Calcular similitud del título
                    local titleSim = textSimilarity(questTitle, title)
                    
                    -- Si mejora la mejor similitud de título actual
                    if titleSim > highestTitleSim then
                        highestTitleSim = titleSim
                        
                        -- Mostrar coincidencias altas
                        if titleSim >= 0.5 then
                            local colorCode = "|cFFFF0000" -- Rojo para similitud > 30%
                            if titleSim > 0.8 then
                                colorCode = "|cFF9900FF" -- Morado para similitud > 80%
                            elseif titleSim > 0.6 then
                                colorCode = "|cFFFFFF00" -- Amarillo para similitud > 60%
                            end
                            DebugPrint(colorCode .. "[QuestSimilarity] Alta similitud de título para QuestID: " .. questID .. 
                                  " - Sim: " .. math.floor(titleSim * 100) .. "%|r")
                        end
                    end
                end
            end
            
            DebugPrint("|cFFFFFF00[QuestSimilarity] Analizados " .. questCount .. " títulos de misión.|r")
        end
        
        -- 3. COMPARANDO NOMBRES DE NPC
        if module.NPCNameSimilarity and module.NPCNameSimilarity[eventCategory] and npcName then
            DebugPrint("|cFFFF9900[QuestSimilarity] Analizando nombres de NPC...|r")
            
            local questCount = 0
            for questID, NPCname in pairs(module.NPCNameSimilarity[eventCategory]) do
                if type(questID) == "number" and type(NPCname) == "string" then
                    questCount = questCount + 1
                    totalQuestsAnalyzed = totalQuestsAnalyzed + 1
                    questIDs[questID] = true
                    
                    -- Calcular similitud del NPC
                    local npcSim = textSimilarity(npcName, NPCname)
                    
                    -- Si mejora la mejor similitud de NPC actual
                    if npcSim > highestNpcSim then
                        highestNpcSim = npcSim
                        
                        -- Mostrar coincidencias altas
                        if npcSim >= 0.6 then
                            local colorCode = "|cFFFF0000" -- Rojo para similitud > 60%
                            if npcSim > 0.9 then
                                colorCode = "|cFF9900FF" -- Morado para similitud > 90%
                            elseif npcSim > 0.8 then
                                colorCode = "|cFFFFFF00" -- Amarillo para similitud > 80%
                            end
                            DebugPrint(colorCode .. "[QuestSimilarity] Alta similitud de NPC para QuestID: " .. questID .. 
                                  " - Sim: " .. math.floor(npcSim * 100) .. "%|r")
                        end
                    end
                end
            end
            
            DebugPrint("|cFFFFFF00[QuestSimilarity] Analizados " .. questCount .. " nombres de NPC.|r")
        end
        
        -- 4. EVALUAR COINCIDENCIAS COMBINADAS
        DebugPrint("|cFFFF9900[QuestSimilarity] Calculando similitudes combinadas...|r")
        local combinedCount = 0
        
        -- Recorrer todos los QuestIDs encontrados para calcular puntuaciones combinadas
        for questID in pairs(questIDs) do
            combinedCount = combinedCount + 1
            
            -- Obtener valores de similitud para este questID
            local textSim = 0
            local titleSim = 0
            local npcSim = 0
            
            -- Texto
            if module.QuestTextSimilarity and module.QuestTextSimilarity[eventCategory] and 
               module.QuestTextSimilarity[eventCategory][questID] then
                textSim = textSimilarity(text, module.QuestTextSimilarity[eventCategory][questID])
            end
            
            -- Título
            if questTitle and module.QuestTitleSimilarity and module.QuestTitleSimilarity[eventCategory] and 
               module.QuestTitleSimilarity[eventCategory][questID] then
                titleSim = textSimilarity(questTitle, module.QuestTitleSimilarity[eventCategory][questID])
            end
            
            -- NPC
            if npcName and module.NPCNameSimilarity and module.NPCNameSimilarity[eventCategory] and 
               module.NPCNameSimilarity[eventCategory][questID] then
                npcSim = textSimilarity(npcName, module.NPCNameSimilarity[eventCategory][questID])
            end
            
            -- Calcular similitud combinada ponderada
            local combinedSim = (textSim * 0.7) + (titleSim * 0.2) + (npcSim * 0.1)
            
            -- Si mejora la mejor similitud combinada actual
            if combinedSim > bestCombinedSim then
                bestMatch = questID
                bestCombinedSim = combinedSim
                
                -- Mostrar nueva mejor coincidencia
                local colorCode = "|cFFFF0000" -- Rojo para similitud > 30%
                if combinedSim > 0.6 then
                    colorCode = "|cFF9900FF" -- Morado para similitud > 60%
                elseif combinedSim > 0.5 then
                    colorCode = "|cFFFFFF00" -- Amarillo para similitud > 50%
                end
                
                DebugPrint(colorCode .. "[QuestSimilarity] ¡Nueva mejor coincidencia! QuestID: " .. questID .. 
                      " - Texto: " .. math.floor(textSim * 100) .. "%" ..
                      ", Título: " .. math.floor(titleSim * 100) .. "%" ..
                      ", NPC: " .. math.floor(npcSim * 100) .. "%" ..
                      ", Combinada: " .. math.floor(combinedSim * 100) .. "%|r")
            end
        end
        
        DebugPrint("|cFFFFFF00[QuestSimilarity] Evaluados " .. combinedCount .. " misiones para similitud combinada.|r")
        
        -- 5. Intentar también con QuestIDLookup si está disponible
        if module.QuestIDLookup and module.QuestIDLookup[eventCategory] then
            DebugPrint("|cFFFFFF00[QuestSimilarity] Analizando QuestIDLookup...|r")
            
            local questCount = 0
            for questID, questText in pairs(module.QuestIDLookup[eventCategory]) do
                questCount = questCount + 1
                totalQuestsAnalyzed = totalQuestsAnalyzed + 1
                
                -- Aquí tenemos acceso directo al texto
                local textSim = textSimilarity(text, questText)
                
                -- Si la similitud es mejor que la actual, actualizar
                if textSim > highestTextSim and textSim > 0.15 then
                    bestMatch = questID
                    highestTextSim = textSim
                    bestCombinedSim = textSim
                    
                    local colorCode = "|cFFFF0000" -- Rojo para similitud > 30%
                    if textSim > 0.6 then
                        colorCode = "|cFF9900FF" -- Morado para similitud > 60%
                    elseif textSim > 0.5 then
                        colorCode = "|cFFFFFF00" -- Amarillo para similitud > 50%
                    end
                    DebugPrint(colorCode .. "[QuestSimilarity] ¡Nueva mejor coincidencia (QuestIDLookup)! QuestID: " .. questID .. 
                          " - Similitud texto: " .. math.floor(textSim * 100) .. "%|r")
                end
            end
            
            DebugPrint("|cFFFFFF00[QuestSimilarity] Analizadas " .. questCount .. " misiones en QuestIDLookup.|r")
        end
    end
    
    -- Imprimir resumen
    DebugPrint("|cFF00FF00[QuestSimilarity] Total misiones analizadas: " .. totalQuestsAnalyzed .. "|r")
    
    -- Si encontramos una coincidencia, devolverla
    if bestMatch then
        local colorCode = "|cFF888888" -- Gris para similitud baja (15-30%)
        if bestCombinedSim > 0.6 then
            colorCode = "|cFF9900FF" -- Morado para similitud alta (>60%)
        elseif bestCombinedSim > 0.5 then
            colorCode = "|cFFFFFF00" -- Amarillo para similitud media (50-60%)
        elseif bestCombinedSim > 0.3 then
            colorCode = "|cFFFF0000" -- Rojo para similitud regular (30-50%)
        end
        
        DebugPrint(colorCode .. "[QuestSimilarity] MEJOR COINCIDENCIA: QuestID " .. bestMatch .. " - Similitud combinada: " .. 
              math.floor(bestCombinedSim * 100) .. "%|r")
        
        return bestMatch
    else
        DebugPrint("|cFFFF0000[QuestSimilarity] No se encontró ninguna coincidencia por encima del umbral mínimo (15%).|r")
        return nil
    end
end

-- Función simple para comparar dos textos
function textSimilarity(text1, text2)
    -- Validar entradas
    if not text1 or not text2 then
        return 0
    end
    
    -- Asegurar que ambos son strings
    if type(text1) ~= "string" then
        text1 = tostring(text1 or "")
    end
    
    if type(text2) ~= "string" then
        text2 = tostring(text2 or "")
    end
    
    -- Si alguno está vacío, no hay similitud
    if text1 == "" or text2 == "" then
        return 0
    end
    
    -- Convertir a minúsculas
    text1 = string.lower(text1)
    text2 = string.lower(text2)
    
    -- Si son idénticos, coincidencia perfecta
    if text1 == text2 then
        return 1.0
    end
    
    -- Implementación simplificada de Jaccard
    local set1, set2 = {}, {}
    
    -- Extraer palabras
    for word in string.gmatch(text1, "%S+") do
        set1[word] = true
    end
    
    for word in string.gmatch(text2, "%S+") do
        set2[word] = true
    end
    
    -- Calcular intersección y unión
    local intersectionSize = 0
    local unionSize = 0
    
    for word in pairs(set1) do
        if set2[word] then
            intersectionSize = intersectionSize + 1
        end
        unionSize = unionSize + 1
    end
    
    for word in pairs(set2) do
        if not set1[word] then
            unionSize = unionSize + 1
        end
    end
    
    -- Evitar división por cero
    if unionSize == 0 then
        return 0
    end
    
    return intersectionSize / unionSize
end

-- Redirigir simpleSimilarity a textSimilarity para mantener compatibilidad
function simpleSimilarity(text1, text2)
    return textSimilarity(text1, text2)
end

function Addon:ShouldPlayGossip(guid, text)
    local npcKey = guid or "unknown"

    local gossipSeenForNPC = self.db.char.hasSeenGossipForNPC[npcKey]

    if self.db.profile.Audio.GossipFrequency == Enums.GossipFrequency.OncePerQuestNPC then
        local numActiveQuests = GetNumGossipActiveQuests()
        local numAvailableQuests = GetNumGossipAvailableQuests()
        local npcHasQuests = (numActiveQuests > 0 or numAvailableQuests > 0)
        if npcHasQuests and gossipSeenForNPC then
            return
        end
    elseif self.db.profile.Audio.GossipFrequency == Enums.GossipFrequency.OncePerNPC then
        if gossipSeenForNPC then
            return
        end
    elseif self.db.profile.Audio.GossipFrequency == Enums.GossipFrequency.Never then
        return
    end

    return true, npcKey
end

function Addon:QUEST_GREETING()
    local guid = Utils:GetNPCGUID()
    local targetName = Utils:GetNPCName()
    local greetingText = GetGreetingText()

    -- Can happen if the player interacted with an NPC while having main menu or options opened
    if not guid and not targetName then
        return
    end

    local play, npcKey = self:ShouldPlayGossip(guid, greetingText)
    if not play then
        return
    end

    -- Play the gossip sound
    ---@type SoundData
    local soundData = {
        event = Enums.SoundEvent.QuestGreeting,
        name = targetName,
        text = greetingText,
        unitGUID = guid,
        unitIsObjectOrItem = Utils:IsNPCObjectOrItem(),
        addedCallback = GossipSoundDataAdded,
        startCallback = function()
            self.db.char.hasSeenGossipForNPC[npcKey] = true
        end
    }
    SoundQueue:AddSoundToQueue(soundData)
end

function Addon:GOSSIP_SHOW()
    local guid = Utils:GetNPCGUID()
    local targetName = Utils:GetNPCName()
    local gossipText = GetGossipText()

    -- Can happen if the player interacted with an NPC while having main menu or options opened
    if not guid and not targetName then
        return
    end

    local play, npcKey = self:ShouldPlayGossip(guid, gossipText)
    if not play then
        return
    end

    -- Play the gossip sound
    ---@type SoundData
    local soundData = {
        event = Enums.SoundEvent.Gossip,
        name = targetName,
        title = selectedGossipOption and format([["%s"]], selectedGossipOption),
        text = gossipText,
        unitGUID = guid,
        unitIsObjectOrItem = Utils:IsNPCObjectOrItem(),
        addedCallback = GossipSoundDataAdded,
        startCallback = function()
            self.db.char.hasSeenGossipForNPC[npcKey] = true
        end
    }
    SoundQueue:AddSoundToQueue(soundData)

    selectedGossipOption = nil
    lastGossipOptions = nil
    if C_GossipInfo and C_GossipInfo.GetOptions then
        lastGossipOptions = C_GossipInfo.GetOptions()
    elseif GetGossipOptions then
        lastGossipOptions = { GetGossipOptions() }
    end
end

function Addon:QUEST_FINISHED()
    if Addon.db.profile.Audio.StopAudioOnDisengage and currentQuestSoundData then
        SoundQueue:RemoveSoundFromQueue(currentQuestSoundData)
    end
    currentQuestSoundData = nil
end

function Addon:GOSSIP_CLOSED()
    if Addon.db.profile.Audio.StopAudioOnDisengage and currentGossipSoundData then
        SoundQueue:RemoveSoundFromQueue(currentGossipSoundData)
    end
    currentGossipSoundData = nil

    selectedGossipOption = nil
end


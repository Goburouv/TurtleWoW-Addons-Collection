setfenv(1, VoiceOver)
Debug = {}

function Debug:Print(msg, header)
    if Addon.db.profile.DebugEnabled then
        if header then
            print(Utils:ColorizeText("VoiceOver", NORMAL_FONT_COLOR_CODE) ..
                Utils:ColorizeText(" (" .. header .. ")", GRAY_FONT_COLOR_CODE) ..
                " - " .. msg)
        else
            print(Utils:ColorizeText("VoiceOver", NORMAL_FONT_COLOR_CODE) ..
                " - " .. msg)
        end
    end
end

function Debug:QuestTextSimilarity(text, questID)
    if not Addon.db.profile.DebugEnabled then
        return
    end
    
    self:Print("QuestTextSimilarity: Texto: " .. (text or "nil"))
    self:Print("QuestTextSimilarity: QuestID: " .. (questID or "nil"))
    
    -- Si hay un ID de misión, también muestra el texto almacenado para esa misión
    if questID then
        for _, module in DataModules:GetModules() do
            if module.QuestTextSimilarity and module.QuestTextSimilarity[questID] then
                self:Print("QuestTextSimilarity: Texto almacenado: " .. module.QuestTextSimilarity[questID]:sub(1, 100) .. "...")
                break
            end
        end
    end
end

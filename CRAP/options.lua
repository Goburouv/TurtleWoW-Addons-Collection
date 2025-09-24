local _G = getfenv()

local options = {
   ['BORDER_COLOR'] = {
      ['R'] = 1.0,
      ['G'] = 1.0,
      ['B'] = 1.0,
      ['A'] = 1.0,
   },
   ['CLASS_COLORS'] = true,
   ['GROUP_HEADERS'] = true,
   ['GROUP_LAYOUT'] = false,
   ['GROUP_POSITION'] = {
      ['X'] = 24,
      ['Y'] = -192,
   },
   ['MANA_ONLY'] = false,
   ['UNIT_SIZE'] = {
      ['W'] = 64,
      ['H'] = 42,
   },
   ['UPPERCASE_NAMES'] = false,
}

local function ShowColorPicker(r, g, b, a, callback)
   ColorPickerFrame.previousValues = {r, g, b, 1 - a}
   ColorPickerFrame.hasOpacity = true
   ColorPickerFrame.func, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc = callback, callback, callback
   ColorPickerFrame.opacity = 1 - a
   ColorPickerFrame:SetColorRGB(r, g, b)
   ColorPickerFrame:Hide()
   ColorPickerFrame:Show()
end

local function ColorPickerCallback(restore)
   local r, g, b = ColorPickerFrame:GetColorRGB()
   local a = OpacitySliderFrame:GetValue()
   if restore then
      r, g, b, a = unpack(restore)
   end

   CRAP_Config['BORDER_COLOR']['R'] = r
   CRAP_Config['BORDER_COLOR']['G'] = g
   CRAP_Config['BORDER_COLOR']['B'] = b
   CRAP_Config['BORDER_COLOR']['A'] = 1 - a

   GroupFrame:SetBackdropBorderColor(r, g, b, 1 - a)
end

function CRAP:InitOptions()
   CRAP_Config = CRAP_Config or options
end

SLASH_CRAP1 = '/crap'
SlashCmdList['CRAP'] = function(msg)
   local args = {}
	local i = 1
	for arg in string.gfind(msg, '%S+') do
		args[i] = arg
		i = i + 1
	end

	if not args[1] then
      if GroupFrame:IsMouseEnabled() then
         GroupFrame:EnableMouse(false)

         CRAP:Update()

         DEFAULT_CHAT_FRAME:AddMessage('The group frame has been locked.')
      else
         GroupFrame:EnableMouse(true)

         CRAP:Update(true)

         local commands = 'border-color'
         for k, v in pairs(options) do
            if type(v) == 'boolean' then
               commands = commands .. ', ' .. string.gsub(strlower(k), '_', '-')
            end
         end

         DEFAULT_CHAT_FRAME:AddMessage('Available |cffcecece/crap |cffffffffsub-commands:')
         DEFAULT_CHAT_FRAME:AddMessage(commands)
         DEFAULT_CHAT_FRAME:AddMessage(' ')
         DEFAULT_CHAT_FRAME:AddMessage('The group frame has been unlocked. Drag around to move. To resize, hold down shift and drag.')
      end
   elseif args[1] == 'border-color' then
      ShowColorPicker(CRAP_Config['BORDER_COLOR']['R'], CRAP_Config['BORDER_COLOR']['G'], CRAP_Config['BORDER_COLOR']['B'], CRAP_Config['BORDER_COLOR']['A'], ColorPickerCallback)

      DEFAULT_CHAT_FRAME:AddMessage('Select a new color and click \'Okay\' to save. To restore previous color, click \'Cancel\'.')

      CRAP:Update(true)
   else
      for k in pairs(options) do
         if string.gsub(strupper(args[1]), '-', '_') == k then
            CRAP_Config[k] = not CRAP_Config[k]
         end
      end

      CRAP:Update(true)
   end
end
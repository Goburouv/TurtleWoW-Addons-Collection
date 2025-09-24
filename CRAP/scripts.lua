local _G = getfenv(0)

-- Group frame scripts
function GroupFrame_OnDragStart()
	if IsShiftKeyDown() then
		this:StartSizing()
	else
   	this:StartMoving()
	end
end

function GroupFrame_OnDragStop()
   this:StopMovingOrSizing()
   this:SetUserPlaced(false)

   local _, _, _, x, y = this:GetPoint()
   CRAP_Config['GROUP_POSITION']['X'] = x
   CRAP_Config['GROUP_POSITION']['Y'] = y
end

function GroupFrame_OnEvent()
	if CRAP.target then
		CRAP.target:Hide()
	end
end

function GroupFrame_OnLoad()
	this:RegisterEvent('PLAYER_TARGET_CHANGED')

   this:RegisterForDrag('LeftButton')
	this:EnableMouse(false)
end

function GroupFrame_OnSizeChanged()
	local header = CRAP_Config['GROUP_HEADERS']
	local layout = CRAP_Config['GROUP_LAYOUT']
   local baseWidth = 64
   local baseHeight = 42

   if this:IsMouseEnabled() and IsShiftKeyDown() then
		local col = layout and 8 or 4
		local row = layout and 5 or 10
		local width = baseWidth + (this:GetWidth() - (baseWidth * col + 10)) / col
		local height = baseHeight + (this:GetHeight() - (baseHeight * row + ((header and not layout) and 40 or 10))) / row
		for _, frame in pairs({ this:GetChildren() }) do
			frame:SetWidth(width)
			frame:SetHeight(height)
		end

		CRAP_Config['UNIT_SIZE']['W'] = width
		CRAP_Config['UNIT_SIZE']['H'] = height
	else
		this:SetMinResize(baseWidth * (layout and 8 or 4) + 10, baseHeight * (layout and 5 or 10) + ((header and not layout) and 40 or 10))
		this:SetMaxResize(baseWidth * (layout and 8 or 4) * 2, baseHeight * (layout and 5 or 10) * 2)
   end
end

-- Member frame scripts
function GroupMemberFrame_OnEnter()
   GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
   GameTooltip:SetUnit(this.unit)
   GameTooltip:Show()
end

function GroupMemberFrame_OnEvent()
   if this.unit and arg1 == this.unit then
      if event == 'UNIT_AURA' then
         CRAP:UpdateMemberAuras(this)
      elseif event == 'UNIT_DISPLAYPOWER' then
         CRAP:UpdateMember(this)
      elseif event == 'UNIT_HEALTH' then
         CRAP:UpdateMemberHealth(this)
      else
         CRAP:UpdateMemberPower(this)
      end
   end
end

function GroupMemberFrame_OnLeave()
   GameTooltip:Hide()
end

function GroupMemberFrame_OnLoad()
   this:RegisterEvent('UNIT_AURA')
   this:RegisterEvent('UNIT_DISPLAYPOWER')
   this:RegisterEvent('UNIT_HEALTH')

   this:RegisterForClicks('LeftButtonUp', 'RightButtonUp', 'MiddleButtonUp', 'Button4Up', 'Button5Up')
end

function GroupMemberFrame_OnClick(frame)
   frame = frame or this

   if arg1 == 'LeftButton' then
      TargetUnit(frame.unit)

      local highlight = _G[frame:GetName() .. 'Highlight']
      highlight:Show()

      CRAP.target = highlight
   elseif arg1 == 'RightButton' then
      local id = this:GetID()
      if GetNumPartyMembers() > 0 and id > 0 then
         ToggleDropDownMenu(1, nil, _G['PartyMemberFrame' .. id .. 'DropDown'], this:GetName(), 100, 25)
      end
   end
end

function GroupMemberFrame_OnUpdate()
	this.elapsed = this.elapsed or 0
	if this.elapsed >= 0.1 then
		this.elapsed = 0

      if this.unit then
         local healthbar = _G[this:GetName() .. 'HealthBar']
         if CheckInteractDistance(this.unit, 4) or librange:UnitInSpellRange(this.unit) == 1 then
            healthbar:SetAlpha(1)
            healthbar:SetAlpha(1)
         else
            healthbar:SetAlpha(0.5)
            healthbar:SetAlpha(0.5)
         end
      end

		CRAP:UpdateMemberIncomingHeal(this)
	end

	this.elapsed = this.elapsed + arg1
end

-- Member frame aura button scripts
function GroupMemberFrameAuraButton_OnClick()
   local script = this:GetParent():GetScript('OnClick')
   script()
end

function GroupMemberFrameAuraButton_OnEnter()
   GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
   GameTooltip:SetUnitBuff(this:GetParent().unit, this:GetID())
   GameTooltip:Show()
end

function GroupMemberFrameAuraButton_OnLeave()
   GameTooltip:Hide()
end

function GroupMemberFrameAuraButton_OnLoad()
   this:RegisterForClicks('LeftButtonUp', 'RightButtonUp', 'MiddleButtonUp', 'Button4Up', 'Button5Up')
end
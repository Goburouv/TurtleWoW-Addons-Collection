if not Clique then return end

-- Create a new plugin for Clique, with the shortname 'CRAP'
local Plugin = Clique:NewModule('CRAP')
Plugin.fullname = 'Compact Raid and Party'

-- Plugin:OnEnable() is called if Plugin:Test() is true, and the mod hasn't been explicitly
-- disabled. This is where you should handle all your hooks, etc.
function Plugin:OnEnable()
   for _, frame in pairs({GroupFrame:GetChildren()}) do
      self:HookScript(frame, 'OnClick')
   end
end

function Plugin:OnClick()
   if not Clique:OnClick(arg1, this.unit) then
      if not self.hooks[this] then
         this = this:GetParent()
      end
      self.hooks[this].OnClick.orig(this)
   end
end
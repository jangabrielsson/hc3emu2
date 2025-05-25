if require and not QuickApp then require("hc3emu") end

--%%name=Timers
--%%type=com.fibaro.multilevelSwitch
--%%time=10:45

function QuickApp:onInit()
    self:debug("onInit",self.name,self.id)

    for i=1,100 do
        setTimeout(function()
            self:debug("setTimeout",i)
        end, (i*0.5+10)*1000)
    end

    self:debug("All timers set")
end
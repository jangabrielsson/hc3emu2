--%%name=Timers
--%%type=com.fibaro.multilevelSwitch
--%%time=10:45

function QuickApp:onInit()
    self:debug("onInit",self.name,self.id)

    function fibaro.noTimersLeft() print("DONE!") end

    for i=1,100 do
        setTimeout(function()
            self:debug("setTimeout",i)
        end, (i*0.25+2)*1000)
    end

    self:debug("All timers set")
end
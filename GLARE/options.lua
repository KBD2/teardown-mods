--[[
#include "registry.lua"
#include "libs/Automatic.lua"
]]

registryInit()

function draw()
    UiFont("regular.ttf", 30)
    UiAlign("center middle")
    UiPush()
        UiTranslate(UiCenter(), UiMiddle() - 80)
        UiText("Debris doesn't disappear")
        UiTranslate(0, 30)
        UiColor(1, 0.4, 0.4)
        UiFont("regular.ttf", 20)
        UiText("WARNING: Can get very laggy")
        UiColor(1, 1, 1, 1)
        UiTranslate(0, 30)
        UiFont("regular.ttf", 30)
        UiPush()
            local qualityDebris = GetBool("savegame.mod.qualitydebris")
            local text = ""
            if qualityDebris then
                text = "Enabled"
                UiColor(0, 1, 0)
            else
                text = "Disabled"
                UiColor(1, 0, 0)
            end
            if UiTextButton(text) then
                SetBool("savegame.mod.qualitydebris", not qualityDebris)
            end
        UiPop()

        if qualityDebris then

            UiTranslate(0, 40)
            UiPush()
                UiTranslate(-20, 0)
                UiFont("regular.ttf", 18)
                UiText("Merge cold debris (improves performance,\nmay rarely cause shape alignment issues)")
                UiTranslate(165, 0)
                local doMerge = GetBool("savegame.mod.domerge")
                local path
                if doMerge then
                    path = "MOD/img/box_checked.png"
                else
                    path = "MOD/img/box.png"
                end
                if UiImageButton(path) then
                    SetBool("savegame.mod.doMerge", not doMerge)
                end
            UiPop()
        end

        UiPush()
            UiColor(0.7, 0.7, 0.7)
            AutoUiLine({-100, 40}, {100, 40})
        UiPop()
        
        UiTranslate(0, 75)
        UiText("Drop weapon after overcharge")
        UiTranslate(0, 30)
        UiPush()
            local dropWeapon = GetBool("savegame.mod.dropweapon")
            local text = ""
            if dropWeapon then
                text = "Enabled"
                UiColor(0, 1, 0)
            else
                text = "Disabled"
                UiColor(1, 0, 0)
            end
            if UiTextButton(text) then
                SetBool("savegame.mod.dropweapon", not dropWeapon)
            end
        UiPop()

        UiPush()
            UiColor(0.7, 0.7, 0.7)
            AutoUiLine({-100, 40}, {100, 40})
        UiPop()
        
        UiTranslate(0, 75)
        UiColor(1, 1, 1, 1)
        UiText("FPS mode (less glowing debris)")
        UiTranslate(0, 30)
        UiPush()
            local fpsGlow = GetBool("savegame.mod.fpsglow")
            local text = ""
            if fpsGlow then
                text = "Enabled"
                UiColor(0, 1, 0)
            else
                text = "Disabled"
                UiColor(1, 0, 0)
            end
            if UiTextButton(text) then
                SetBool("savegame.mod.fpsglow", not fpsGlow)
            end
        UiPop()
    UiPop()
    UiColor(1, 1, 1)
    UiTranslate(100, 100)
	if UiTextButton("Close", 200, 40) then
		Menu()
	end
end
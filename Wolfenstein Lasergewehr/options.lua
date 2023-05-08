#include "registry.lua"

registryInit()

function draw()
    UiFont("regular.ttf", 30)
    UiAlign("center middle")
    UiPush()
        UiTranslate(UiCenter(), UiMiddle() - 30)
        UiText("Infinite ammo on non-sandbox levels")
        UiTranslate(0, 30)
        UiPush()
            local infiniteAmmo = GetBool("savegame.mod.infiniteammo")
            local text = ""
            if infiniteAmmo then
                text = "Enabled"
                UiColor(0, 1, 0)
            else
                text = "Disabled"
                UiColor(1, 0, 0)
            end
            if UiTextButton(text) then
                SetBool("savegame.mod.infiniteammo", not infiniteAmmo)
            end
        UiPop()
        UiTranslate(0, 50)
        UiText("Laser makes fires")
        UiTranslate(0, 30)
        UiPush()
            local makeFire = GetBool("savegame.mod.makefire")
            local text = ""
            if makeFire then
                text = "Enabled"
                UiColor(0, 1, 0)
            else
                text = "Disabled"
                UiColor(1, 0, 0)
            end
            if UiTextButton(text) then
                SetBool("savegame.mod.makefire", not makeFire)
            end
        UiPop()
        UiTranslate(0, 50)
        UiText("Limit melting to a reasonable radius (TURNING OFF CAN BE LAGGY)")
        UiTranslate(0, 30)
        UiPush()
            local limitSize = GetBool("savegame.mod.limitsize")
            local text = ""
            if limitSize then
                text = "Enabled"
                UiColor(0, 1, 0)
            else
                text = "Disabled"
                UiColor(1, 0, 0)
            end
            if UiTextButton(text) then
                SetBool("savegame.mod.limitsize", not limitSize)
            end
        UiPop()
    UiPop()
    UiColor(1, 1, 1)
    UiTranslate(100, 100)
	if UiTextButton("Close", 200, 40) then
		Menu()
	end
end
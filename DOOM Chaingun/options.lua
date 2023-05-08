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
        UiText("Turret mode overheating")
        UiTranslate(0, 30)
        UiPush()
            local infiniteAmmo = GetBool("savegame.mod.turretoverheat")
            local text = ""
            if infiniteAmmo then
                text = "Enabled"
                UiColor(0, 1, 0)
            else
                text = "Disabled"
                UiColor(1, 0, 0)
            end
            if UiTextButton(text) then
                SetBool("savegame.mod.turretoverheat", not infiniteAmmo)
            end
        UiPop()
    UiPop()
    UiColor(1, 1, 1)
    UiTranslate(100, 100)
	if UiTextButton("Close", 200, 40) then
		Menu()
	end
end
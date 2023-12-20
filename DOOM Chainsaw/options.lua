#include "registry.lua"

registryInit()

function round(num, decimals)
    local mult = 10^(decimals or 0)
    return math.floor(num * mult + 0.5) / mult
end

function draw()
    local weak = GetFloat("savegame.mod.doomchainsaw.holeweak") * 1000
    local med = GetFloat("savegame.mod.doomchainsaw.holemed") * 1000
    local strong = GetFloat("savegame.mod.doomchainsaw.holestrong") * 1000

    UiFont("regular.ttf", 30)

    UiPush()

    local x0, y0, x1, y1 = UiSafeMargins()
	UiTranslate(x0, y0)
	UiWindow(x1-x0, y1-y0, true)

    UiButtonImageBox("ui/common/box-outline-6.png", 6, 6)

    UiTranslate(UiCenter(), UiMiddle() - 300)
    UiAlign("center middle")

    UiText("CUTTING POWER")

    UiTranslate(0, 100)
    UiText("Soft materials (glass, grass, dirt, plastic, wood, plaster)")
    UiTranslate(0, 50)
    UiText(tostring(round(weak / 100, 1)))
    UiTranslate(0, 30)
    UiColor(1,1,1)
    UiAlign("center middle")
    UiRect(500, 3)
    UiTranslate(-250, 0)
    weak = UiSlider("ui/common/dot.png", "x", weak, 0, 500)
    SetFloat("savegame.mod.doomchainsaw.holeweak", weak / 1000)

    UiTranslate(250, 100)
    UiText("Medium materials (concrete, brick, weak metal)")
    UiTranslate(0, 50)
    UiText(tostring(round(med / 100, 1)))
    UiTranslate(0, 30)
    UiColor(1,1,1)
    UiAlign("center middle")
    UiRect(500, 3)
    UiTranslate(-250, 0)
    med = UiSlider("ui/common/dot.png", "x", med, 0, 500)
    SetFloat("savegame.mod.doomchainsaw.holemed", med / 1000)

    UiTranslate(250, 100)
    UiText("Hard materials (hard metal, hard masonry)")
    UiTranslate(0, 50)
    UiText(tostring(round(strong / 100, 1)))
    UiTranslate(0, 30)
    UiColor(1,1,1)
    UiAlign("center middle")
    UiRect(500, 3)
    UiTranslate(-250, 0)
    strong = UiSlider("ui/common/dot.png", "x", strong, 0, 500)
    SetFloat("savegame.mod.doomchainsaw.holestrong", strong / 1000)

    UiTranslate(250, 100)
    if UiTextButton("Reset to defaults", 200, 40) then
		restoreDefaults()
	end

    UiPop()

    UiColor(1, 1, 1)
    UiTranslate(100, 100)
	if UiTextButton("Close", 200, 40) then
		Menu()
	end
end
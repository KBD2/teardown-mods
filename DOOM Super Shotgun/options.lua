function bool_to_number(value)
    return value and 1 or 0
  end

function draw()
    local recoilDisabled = GetBool("savegame.mod.doombigshotty.disablerecoil")

	UiFont("regular.ttf", 30)
    UiPush()
    UiTranslate(UiCenter() - 100, UiMiddle())
    w, h = UiText("Shotgun recoil: ")
    UiTranslate(w, 0)
    UiColor(bool_to_number(recoilDisabled), bool_to_number(not recoilDisabled), 0)
    local pressed = false
    if recoilDisabled then
        pressed = UiTextButton("Disabled")
    else
        pressed = UiTextButton("Enabled")
    end
    if pressed then
        recoilDisabled = not recoilDisabled
        SetBool("savegame.mod.doombigshotty.disablerecoil", recoilDisabled)
    end
    UiPop()

    UiPush()
        UiAlign("center middle")
        UiTranslate(UiCenter(), UiMiddle() + 30)
        UiText("Infinite ammo on non-sandbox levels")
        UiTranslate(0, 30)
        UiPush()
            local infiniteAmmo = GetBool("savegame.mod.doombigshotty.infiniteammo")
            local text = ""
            if infiniteAmmo then
                text = "Enabled"
                UiColor(0, 1, 0)
            else
                text = "Disabled"
                UiColor(1, 0, 0)
            end
            if UiTextButton(text) then
                SetBool("savegame.mod.doombigshotty.infiniteammo", not infiniteAmmo)
            end
        UiPop()
    UiPop()

    UiColor(1, 1, 1)
    UiTranslate(100, 100)
	if UiTextButton("Close", 200, 40) then
		Menu()
	end
end
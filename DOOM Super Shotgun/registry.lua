-- Replace with mods's options
local modDefaults = {
    infiniteammo = false,
    recoilDisabled = false
}

function setValue(k, v)
    local typ = type(v)
    if typ == "boolean" then
        SetBool("savegame.mod.doombigshotty." .. k, v)
    elseif typ == "number" then
        SetFloat("savegame.mod.doombigshotty." .. k, v)
    end
end

function registryInit()
    for k, v in pairs(modDefaults) do
        if not HasKey("savegame.mod.doombigshotty." .. k) then
            setValue(k, v)
        end
    end
end

function restoreDefaults()
    for k, v in pairs(modDefaults) do
        setValue(k, v)
    end
end
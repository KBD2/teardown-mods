-- Replace with mods's options
local modDefaults = {
    holeweak = 0.3,
    holemed = 0.3,
    holestrong = 0.2
}

function setValue(k, v)
    local typ = type(v)
    if typ == "boolean" then
        SetBool("savegame.mod.doomchainsaw." .. k, v)
    elseif typ == "number" then
        SetFloat("savegame.mod.doomchainsaw." .. k, v)
    end
end

function registryInit()
    for k, v in pairs(modDefaults) do
        if not HasKey("savegame.mod.doomchainsaw." .. k) then
            setValue(k, v)
        end
    end
end

function restoreDefaults()
    for k, v in pairs(modDefaults) do
        setValue(k, v)
    end
end
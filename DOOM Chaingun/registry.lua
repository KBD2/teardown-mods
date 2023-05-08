-- Replace with mods's options
local modDefaults = {
    infiniteammo = false,
    turretoverheat = true
}

function setValue(k, v)
    local typ = type(v)
    if typ == "boolean" then
        SetBool("savegame.mod." .. k, v)
    elseif typ == "number" then
        SetFloat("savegame.mod." .. k, v)
    end
end

function registryInit()
    for k, v in pairs(modDefaults) do
        if not HasKey("savegame.mod." .. k) then
            setValue(k, v)
        end
    end
end

function restoreDefaults()
    for k, v in pairs(modDefaults) do
        setValue(k, v)
    end
end
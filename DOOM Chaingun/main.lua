#include "umf_tool.lua"
#include "prefab.lua"
#include "registry.lua"

local TOOL = {}

TOOL.model = {
    prefab = CHAINGUN_PREFAB,
    objects = CHAINGUN_OBJECTS
}
TOOL.printname = "DOOM Chaingun"
TOOL.group = 3

local INITIAL_TRANSFORM = Transform(Vec(0.5, -1, -2), QuatEuler(2, 5, 2))
local INITIAL_TRANSFORM_TURRET = Transform(Vec(0, -0.8, -1.8), QuatEuler(0, 0, 0))

local SPIN_ACCEL = 900
local SPIN_VEL_MAX = 1800 -- 900RPM / 60s * 360deg / 3 barrels
local SPIN_VEL_MIN = 240
local SPIN_VEL_MIN_TURRET = 720
local INACCURACY_DEGREES = 3

local CAMERA_SHAKE_DEGREES = 0.5

local HOLE_SIZE_WEAK = 0.7
local HOLE_SIZE_MEDIUM = 1
local HOLE_SIZE_STRONG = 0.3

local HOLE_SIZE_TUR_WEAK = 1.5
local HOLE_SIZE_TUR_MEDIUM = 2.5
local HOLE_SIZE_TUR_STRONG  = 0.7

local BODY_PUSH_RADIUS = 1
local BODY_PUSH_TUR_RADIUS = 2.5
local BODY_PUSH_SCALE = 15
local BODY_PUSH_TUR_SCALE = 45

local IMPACT_PARTICLE_CHANCE = 0.7
local NUM_IMPACT_PARTICLES_ERUPTION = 30
local NUM_IMPACT_PARTICLES_SHOCKWAVE = 60

-- All in degrees celsius
local BARREL_ROOM_TEMP = 20
local BARREL_COOLDOWN_PER_SEC = 500
local BARREL_MAX_TEMP = 1500 -- Near the melting point of steel
local BARREL_GLOW_TEMP = 460 -- Glow point of steel
local BARREL_HEAT_PER_SEC = 800

local NUM_DEBRIS_ATTEMPTS = 100

local STATE = {
    spin = 0,
    spinVel = 0,
    state = "READY",
    shot = 0,
    isTurret = false,
    transformTimer = 0,
    flip = false,
    barrelTemp = BARREL_ROOM_TEMP,
    cooling = false,
    isIncendiary = false,
    infiniteAmmo = false,
    doOverheat = true
}

local HANDLE_SPRITE_MUZFLASH

local FLASH_R = 0.4
local FLASH_G = 0.6
local FLASH_B = 1

function init()
    registryInit()

    HANDLE_SOUND_SHOOT = LoadSound("MOD/sounds/shoot/shoot0.ogg")
    HANDLE_SOUND_SMALLSPINUP = LoadSound("MOD/sounds/smallspinup.ogg")
    HANDLE_LOOP_SMALLSHOOT = LoadLoop("MOD/sounds/smallshoot.ogg")
    HANDLE_SOUND_TRANSFORM = LoadSound("MOD/sounds/transform.ogg")
    HANDLE_SOUND_COOLDOWN = LoadSound("MOD/sounds/cooldown.ogg")
    HANDLE_SOUND_UNTRANSFORM = LoadSound("MOD/sounds/untransform.ogg")

    HANDLE_SOUND_SPINUP = LoadSound("MOD/sounds/spinup.ogg")
    HANDLE_SOUND_SPINDOWN = LoadSound("MOD/sounds/spindown.ogg")
    HANDLE_SOUND_CLICK = LoadSound("MOD/sounds/click.ogg")
    HANDLE_LOOP_SPIN = LoadLoop("MOD/sounds/spin.ogg")

    HANDLE_SPRITE_MUZFLASH = LoadSprite("MOD/sprite/muzflash.png")

    STATE.infiniteAmmo = GetBool("savegame.mod.infiniteammo")
    STATE.doOverheat = GetBool("savegame.mod.turretoverheat")

    SetInt("game.tool.doomchaingun.ammo", 500)

    if STATE.infiniteAmmo then
        SetString("game.tool.doomchaingun.ammo.display", "")
    end
end

function shoot()
    STATE.flip = not STATE.flip
    local playerTransform = GetPlayerCameraTransform()
    local forward = TransformToParentVec(playerTransform, Vec(0, 0, -1))
    local inaccuracy = randQuat(-INACCURACY_DEGREES, INACCURACY_DEGREES)
    if not STATE.isTurret then
        QueryRejectBody(GetToolBody())
        local hit, dist, normal, shape = QueryRaycast(playerTransform.pos, forward, 250)
        if STATE.isTurret or not hit then
            dist = 100
        end
        local aimPoint = VecAdd(playerTransform.pos, VecScale(forward, dist))
        local barrelEnd = TOOL:GetBoneGlobalTransform("mainbarrelend")
        local aimVec = QuatRotateVec(QuatRotateQuat(QuatLookAt(barrelEnd.pos, aimPoint), inaccuracy), Vec(0, 0, -1))
        fireBullet(barrelEnd.pos, aimVec)
        PlaySound(HANDLE_SOUND_SHOOT)
        DrawSprite(
            HANDLE_SPRITE_MUZFLASH,
            Transform(barrelEnd.pos, QuatRotateQuat(barrelEnd.rot, QuatAxisAngle(Vec(0, 0, 1), randBetween(-180, 180)))),
            0.8, 0.8, 1, 1, 1, 0.6, true
        )
        particleGunFlash(0.5)
        SpawnParticle(TransformToParentPoint(barrelEnd, Vec(0, 0, -0.3)), Vec(0, 0, 0), 0.05)
        particleGunSmoke()
        SpawnParticle(barrelEnd.pos, TransformToParentVec(barrelEnd, Vec(0, 0, -1)), randBetween(0.5, 1))
        if STATE.flip then
            PointLight(barrelEnd.pos, FLASH_R, FLASH_G, FLASH_B, 0.5)
        end
        if not STATE.infiniteAmmo then
            SetInt("game.tool.doomchaingun.ammo", GetInt("game.tool.doomchaingun.ammo") - 1)
        end
    else
        local barrelEnd = TOOL:GetBoneGlobalTransform("bottombarrelend")
        turretMuzFlash(barrelEnd)

        barrelEnd = TOOL:GetBoneGlobalTransform("leftbarrelend")
        turretMuzFlash(barrelEnd)

        barrelEnd = TOOL:GetBoneGlobalTransform("rightbarrelend")
        turretMuzFlash(barrelEnd)

        local aimVec = QuatRotateVec(QuatRotateQuat(playerTransform.rot, inaccuracy), Vec(0, 0, -1))
        fireBullet(playerTransform.pos, aimVec)
        if not STATE.infiniteAmmo then
            SetInt("game.tool.doomchaingun.ammo", GetInt("game.tool.doomchaingun.ammo") - 3)
        end
    end
end

function turretMuzFlash(transform)
    DrawSprite(
        HANDLE_SPRITE_MUZFLASH,
        Transform(transform.pos, QuatRotateQuat(transform.rot,QuatAxisAngle(Vec(0, 0, 1), randBetween(-180, 180)))),
        0.4, 0.4, 1, 1, 1, 0.6, true
    )
    particleGunFlash(0.25)
    SpawnParticle(transform.pos, Vec(0, 0, 0), 0.05)
    particleGunSmoke()
    SpawnParticle(transform.pos, TransformToParentVec(transform, Vec(0, 0, -1)), randBetween(0.5, 1))
    if STATE.flip then
        PointLight(transform.pos, FLASH_R, FLASH_G, FLASH_B, 0.5)
    end
end

function fireBullet(orig, dir)
    QueryRejectBody(GetToolBody())
    local hit, dist, normal, shape = QueryRaycast(orig, dir, 250)
    if hit then
        local hitPoint = VecAdd(orig, VecScale(dir, dist))

        local radius = 0
        if not STATE.isTurret then
            radius = HOLE_SIZE_WEAK
        else
            radius = HOLE_SIZE_TUR_WEAK
        end

        local vec = VecScale(Vec(1, 1, 1), radius)
        local shapes = QueryAabbShapes(VecSub(hitPoint, vec), VecAdd(hitPoint, vec))
        for i = 1, NUM_DEBRIS_ATTEMPTS do
            local testPoint = VecAdd(hitPoint, randVec(-radius, radius))
            for j = 1, #shapes do
                local typ, r, g, b, a = GetShapeMaterialAtPosition(shapes[j], testPoint)
                if typ ~= "" and typ ~= "heavymetal" and typ ~= "rock" and typ ~= "none" then
                    particleDebris(r, g, b, a)
                    SpawnParticle(testPoint, QuatRotateVec(randQuat(-1, 1), VecScale(dir, 10)), randBetween(2, 4))
                    particleDebrisSmoke(r, g, b)
                    SpawnParticle(testPoint, normal, randBetween(0.5, 1))
                end
            end
        end

        local num = 0
        if not STATE.isTurret then
            destructiblerobots(shape, 5, 3)
            num = MakeHole(hitPoint, HOLE_SIZE_WEAK, HOLE_SIZE_MEDIUM, HOLE_SIZE_STRONG)
            pushBodies(hitPoint, dir, BODY_PUSH_RADIUS, BODY_PUSH_SCALE)
        else
            destructiblerobots(shape, 15, 10)
            num = MakeHole(hitPoint, HOLE_SIZE_TUR_WEAK, HOLE_SIZE_TUR_MEDIUM, HOLE_SIZE_TUR_STRONG)
            pushBodies(hitPoint, dir, BODY_PUSH_TUR_RADIUS, BODY_PUSH_TUR_SCALE)
        end

        local typ, r, g, b, a = GetShapeMaterialAtPosition(shape, hitPoint)
        if typ == "heavymetal" or typ == "rock" or typ == "none" then
            particleImpact()
            for i = 0, NUM_IMPACT_PARTICLES_ERUPTION do
                SpawnParticle(hitPoint, QuatRotateVec(randQuat(-10, 10), VecScale(normal, randBetween(0, 6))), randBetween(0.01, 0.15))
            end
            for i = 0, NUM_IMPACT_PARTICLES_ERUPTION do
                local velocity = QuatRotateVec(QuatEuler(0, randBetween(0, 360), 85), VecScale(normal, randBetween(0, 3)))
                SpawnParticle(hitPoint, velocity, randBetween(0.01, 0.15))
            end
        end
    end
end

function pushBodies(hitPos, dir, radius, scale)
    local pushRadius = VecScale(Vec(1, 1, 1), radius)
    local bodies = QueryAabbBodies(VecSub(hitPos, pushRadius), VecAdd(hitPos, pushRadius))
    for i = 1, #bodies do
        local hit, point, normal, shape = GetBodyClosestPoint(bodies[i], hitPos)
        local dist = VecLength(VecSub(point, hitPos))
        local vec = QuatRotateVec(randQuat(-45, 45), dir)
        ApplyBodyImpulse(bodies[i], point, VecScale(vec, math.min(10000, scale * (GetBodyMass(bodies[i]) / 10))))
        if STATE.isIncendiary then
            SpawnFire(point)
        end
    end
end

function destructiblerobots(shape, damage, hitcounter)
	if HasTag(shape, "shapeHealth") then
		if tonumber(GetTagValue(shape,"shapeHealth")) - damage < 0 and not HasTag(shape, "body") then 
			RemoveTag(shape,"unbreakable")
		end
	end
    SetFloat('level.destructible-bot.hitCounter', hitcounter)
    SetInt('level.destructible-bot.hitShape', shape)
    SetString('level.destructible-bot.weapon',"DOOM Chaingun")
    SetFloat('level.destructible-bot.damage', damage)
end

function TOOL:Tick(dt)
    local hasAmmo = (STATE.isTurret and GetInt("game.tool.doomchaingun.ammo") > 2) or (not STATE.isTurret and GetInt("game.tool.doomchaingun.ammo") > 0)

    local barrelEnd = TOOL:GetBoneGlobalTransform("mainbarrelend")
    STATE.spin = STATE.spin + STATE.spinVel * dt
    if STATE.spin > 360 then
        STATE.spin = STATE.spin - 360
        if STATE.state == "SPINDOWN" then
            if (STATE.isTurret and STATE.spinVel == SPIN_VEL_MIN_TURRET) or (not STATE.isTurret and STATE.spinVel == SPIN_VEL_MIN) then
                STATE.spin = 0
                STATE.spinVel = 0
                STATE.shot = 0
                STATE.state = "READY"
                if not STATE.isTurret then
                    PlaySound(HANDLE_SOUND_CLICK)
                end
            end
        end
    end

    local shootThisFrame = false
    if (STATE.spin >= 60 and STATE.spin < 180 and STATE.shot == 0)
    or (STATE.spin >= 180 and STATE.spin < 300 and STATE.shot == 1)
    or (STATE.spin >= 300 and STATE.shot == 2) then
        if hasAmmo then
            STATE.shot = (STATE.shot + 1) % 3
            shootThisFrame = true
        end
    end

    if InputDown("usetool") and STATE.transformTimer == 0 and not STATE.cooling and GetPlayerVehicle() == 0 then
        if not STATE.isTurret then
            PlayLoop(HANDLE_LOOP_SPIN)
            STATE.spinVel = math.min(STATE.spinVel + SPIN_ACCEL * dt, SPIN_VEL_MAX)
        else
            if hasAmmo then
                if STATE.spinVel < SPIN_VEL_MAX then
                    PlaySound(HANDLE_SOUND_SMALLSPINUP)
                end
                STATE.spinVel = SPIN_VEL_MAX
                PlayLoop(HANDLE_LOOP_SMALLSHOOT)
                SetPlayerCameraOffsetTransform(Transform(Vec(), randQuat(-CAMERA_SHAKE_DEGREES, CAMERA_SHAKE_DEGREES)))
                
                STATE.barrelTemp = math.min(STATE.barrelTemp + BARREL_HEAT_PER_SEC * dt, BARREL_MAX_TEMP)
            else
                STATE.isTurret = false
                STATE.spin = 0
                STATE.spinVel = 0
                STATE.shot = 0
                STATE.state = "READY"
                STATE.transformTimer = 0.5
                PlaySound(HANDLE_SOUND_UNTRANSFORM)
            end
        end
        STATE.state = "SPINUP"
        if shootThisFrame then
            shoot()
            SetPlayerCameraOffsetTransform(Transform(Vec(), randQuat(-CAMERA_SHAKE_DEGREES, CAMERA_SHAKE_DEGREES)))
        end
    end
    STATE.transformTimer = math.max(0, STATE.transformTimer - dt)

    if InputPressed("usetool") and not STATE.isTurret and not STATE.cooling and GetPlayerVehicle() == 0 then
        PlaySound(HANDLE_SOUND_SPINUP)
    end

    if InputReleased("usetool") and not STATE.isTurret and not STATE.cooling and GetPlayerVehicle() == 0 then
        PlaySound(HANDLE_SOUND_SPINDOWN)
    end

    if STATE.isTurret then
        local vel = GetPlayerVelocity()
        local offset = VecScale(vel, 5 * dt)
        offset[2] = 0
        SetPlayerVelocity(VecSub(vel, offset))
    end

    if STATE.cooling and STATE.barrelTemp == BARREL_ROOM_TEMP then
        STATE.cooling = false
    end

    if not STATE.cooling and STATE.barrelTemp >= BARREL_MAX_TEMP and STATE.doOverheat then
        STATE.cooling = true
        PlaySound(HANDLE_SOUND_COOLDOWN)
    end

    local coolDegrees = BARREL_COOLDOWN_PER_SEC * dt
    if IsPointInWater(TOOL:GetBoneGlobalTransform("barrelbottom").pos) then
        coolDegrees = coolDegrees * 5 -- Watercooled :D
    end
    if STATE.cooling then
        particleCooldownSmoke()
        SpawnParticle(TOOL:GetBoneGlobalTransform("cooldownsmoke").pos, Vec(0, 0, 0), randBetween(0.5, 0.75))
    end
    STATE.barrelTemp = math.max(BARREL_ROOM_TEMP, STATE.barrelTemp - coolDegrees)

    if InputPressed("c") then
        STATE.isIncendiary = not STATE.isIncendiary
    end

    if InputPressed("grab") then
        if GetInt("game.tool.doomchaingun.ammo") > 2 then
            STATE.isTurret = true
            STATE.spin = 0
            STATE.spinVel = 0
            STATE.shot = 0
            STATE.state = "READY"
            STATE.transformTimer = 0.5
            PlaySound(HANDLE_SOUND_TRANSFORM)
        end
    end

    if InputReleased("grab") then
        if GetInt("game.tool.doomchaingun.ammo") > 2 then
            STATE.isTurret = false
            STATE.spin = 0
            STATE.spinVel = 0
            STATE.shot = 0
            STATE.state = "READY"
            STATE.transformTimer = 0.5
            PlaySound(HANDLE_SOUND_UNTRANSFORM)
        end
    end
end

function TOOL:Update(dt)
    if STATE.cooling or not InputDown("usetool") then
        if STATE.state == "SPINDOWN" then
            if not STATE.isTurret then
                STATE.spinVel = math.max(STATE.spinVel * 0.98, SPIN_VEL_MIN)
            else
                STATE.spinVel = math.max(STATE.spinVel * 0.9, SPIN_VEL_MIN_TURRET)
            end
        end
        if STATE.state == "SPINUP" then
            STATE.state = "SPINDOWN"
        end
    end
end

function TOOL:Animate(body, shapes)
    local targetTransform
    if not STATE.isTurret then
        targetTransform = TransformLerp(
            INITIAL_TRANSFORM_TURRET, 
            INITIAL_TRANSFORM, 
            math.min(1, 1 - ((STATE.transformTimer - 0.4) / 0.1))
        )
    else
        targetTransform = TransformLerp(
            INITIAL_TRANSFORM, 
            INITIAL_TRANSFORM_TURRET, 
            math.min(1, 1 - ((STATE.transformTimer - 0.4) / 0.1))
        )
    end

    SetToolTransform(targetTransform, 1)

    local barrels = {
        shapes[1].handle,
        shapes[7].handle,
        shapes[8].handle
    }
    local barrelsHot = {
        shapes[12].handle,
        shapes[13].handle,
        shapes[14].handle
    }

    if STATE.barrelTemp < BARREL_GLOW_TEMP and not HasTag(barrelsHot[1], "invisible") then
        SetTag(barrelsHot[1], "invisible")
        SetTag(barrelsHot[2], "invisible")
        SetTag(barrelsHot[3], "invisible")
        RemoveTag(barrels[1], "invisible")
        RemoveTag(barrels[2], "invisible")
        RemoveTag(barrels[3], "invisible")
    end

    if STATE.barrelTemp >= BARREL_GLOW_TEMP then
        if not HasTag(barrels[1], "invisible") then
            SetTag(barrels[1], "invisible")
            SetTag(barrels[2], "invisible")
            SetTag(barrels[3], "invisible")
            RemoveTag(barrelsHot[1], "invisible")
            RemoveTag(barrelsHot[2], "invisible")
            RemoveTag(barrelsHot[3], "invisible")
        end

        local scale = (STATE.barrelTemp - BARREL_GLOW_TEMP) / (BARREL_MAX_TEMP - BARREL_GLOW_TEMP)

        SetShapeEmissiveScale(barrelsHot[1], scale)
        SetShapeEmissiveScale(barrelsHot[2], scale)
        SetShapeEmissiveScale(barrelsHot[3], scale)
    end


    local armature = self.armature
    armature:SetBoneTransform("front", Transform(Vec(), QuatEuler()))
    armature:SetBoneTransform("leftbarrel", Transform(Vec(), QuatEuler()))
    armature:SetBoneTransform("rightbarrel", Transform(Vec(), QuatEuler()))
    armature:SetBoneTransform("bottombarrel", Transform(Vec(), QuatEuler()))
    armature:SetBoneTransform("ammofeedright", Transform(Vec(), QuatEuler()))
    armature:SetBoneTransform("ammofeedleft", Transform(Vec(), QuatEuler()))
    armature:SetBoneTransform("handle", Transform(Vec(), QuatEuler()))
    armature:SetBoneTransform("handleside", Transform(Vec(), QuatEuler()))
    if not STATE.isTurret then
        armature:SetBoneTransform("front", Transform(Vec(), QuatEuler(0, 0, -STATE.spin)))

        armature:SetBoneTransform("handle", Transform(
            Vec(), 
            QuatSlerp(QuatEuler(60, 0, 0), QuatEuler(), math.min(1, 1 - ((STATE.transformTimer - 0.4) / 0.1)))
        ))
        armature:SetBoneTransform("handleside", Transform(
            Vec(), 
            QuatSlerp(QuatEuler(0, 0, 90), QuatEuler(), math.min(1, 1 - ((STATE.transformTimer - 0.4) / 0.1)))
        ))
        armature:SetBoneTransform("left", Transform(
            VecLerp(Vec(-0.3, 0, 0.2), Vec(-0.3, 0, 0), math.min(1, 1 - ((STATE.transformTimer - 0.4) / 0.1))),
            QuatEuler()
        ))
        armature:SetBoneTransform("right", Transform(
            VecLerp(Vec(0.3, 0, 0.2), Vec(0.3, 0, 0), math.min(1, 1 - ((STATE.transformTimer - 0.4) / 0.1))),
            QuatEuler()
        ))
        armature:SetBoneTransform("ammofeedright", Transform(Vec(0, 0, 0.2),QuatEuler()))
        armature:SetBoneTransform("ammofeedleft", Transform(Vec(0, 0, 0.2), QuatEuler()))

        if STATE.transformTimer < 0.1 then
            armature:SetBoneTransform("left", Transform(
                VecLerp(Vec(-0.3, 0, 0), Vec(), 1 - (STATE.transformTimer / 0.1)),
                QuatEuler()
            ))
            armature:SetBoneTransform("right", Transform(
                VecLerp(Vec(0.3, 0, 0), Vec(), 1 - (STATE.transformTimer / 0.1)),
                QuatEuler()
            ))
            armature:SetBoneTransform("ammofeedright", Transform(
                VecLerp(Vec(0, 0, 0.2), Vec(), 1 - (STATE.transformTimer / 0.1)),
                QuatEuler()
            ))
            armature:SetBoneTransform("ammofeedleft", Transform(
                VecLerp(Vec(0, 0, 0.2), Vec(), 1 - (STATE.transformTimer / 0.1)),
                QuatEuler()
            ))
        end
    else
        armature:SetBoneTransform("leftbarrel", Transform(Vec(), QuatEuler(0, 0, -STATE.spin)))
        armature:SetBoneTransform("rightbarrel", Transform(Vec(), QuatEuler(0, 0, STATE.spin)))
        armature:SetBoneTransform("bottombarrel", Transform(Vec(), QuatEuler(0, 0, -STATE.spin)))
        
        armature:SetBoneTransform("handle", Transform(
            Vec(), 
            QuatSlerp(QuatEuler(), QuatEuler(60, 0, 0), math.min(1, 1 - ((STATE.transformTimer - 0.4) / 0.1)))
        ))
        armature:SetBoneTransform("handleside", Transform(
            Vec(), 
            QuatSlerp(QuatEuler(), QuatEuler(0, 0, 90), math.min(1, 1 - ((STATE.transformTimer - 0.4) / 0.1)))
        ))
        armature:SetBoneTransform("left", Transform(
            VecLerp(Vec(), Vec(-0.3, 0, 0), math.min(1, 1 - ((STATE.transformTimer - 0.4) / 0.1))),
            QuatEuler()
        ))
        armature:SetBoneTransform("right", Transform(
            VecLerp(Vec(), Vec(0.3, 0, 0), math.min(1, 1 - ((STATE.transformTimer - 0.4) / 0.1))),
            QuatEuler()
        ))
        if STATE.transformTimer < 0.1 then
            armature:SetBoneTransform("left", Transform(
                VecLerp(Vec(-0.3, 0, 0), Vec(-0.3, 0, 0.2), 1 - (STATE.transformTimer / 0.1)),
                QuatEuler()
            ))
            armature:SetBoneTransform("right", Transform(
                VecLerp(Vec(0.3, 0, 0), Vec(0.3, 0, 0.2), 1 - (STATE.transformTimer / 0.1)),
                QuatEuler()
            ))
            armature:SetBoneTransform("ammofeedright", Transform(
                VecLerp(Vec(), Vec(0, 0, 0.2), 1 - (STATE.transformTimer / 0.1)),
                QuatEuler()
            ))
            armature:SetBoneTransform("ammofeedleft", Transform(
                VecLerp(Vec(), Vec(0, 0, 0.2), 1 - (STATE.transformTimer / 0.1)),
                QuatEuler()
            ))
        end
    end
end

--[[
function TOOL:RightClick()
    if GetInt("game.tool.doomchaingun.ammo") > 2 then
        STATE.isTurret = true
        STATE.spin = 0
        STATE.spinVel = 0
        STATE.shot = 0
        STATE.state = "READY"
        STATE.transformTimer = 0.5
        PlaySound(HANDLE_SOUND_TRANSFORM)
    end
end
--]]

--[[
function TOOL:RightClickReleased()
    if GetInt("game.tool.doomchaingun.ammo") > 2 then
        STATE.isTurret = false
        STATE.spin = 0
        STATE.spinVel = 0
        STATE.shot = 0
        STATE.state = "READY"
        STATE.transformTimer = 0.5
        PlaySound(HANDLE_SOUND_UNTRANSFORM)
    end
end
--]]

function TOOL:Holster()
    SetBool("hud.aimdot", true)
    STATE.state = "ready"
    STATE.spin = 0
    STATE.shot = 0
    STATE.spinVel = 0
    STATE.isTurret = false
    STATE.transformTimer = 0
    STATE.barrelTemp = 0
end

function TOOL:Draw(dt)
    SetBool("hud.aimdot", false)
    UiPush()
    UiAlign("center middle")
    UiTranslate(UiCenter(), UiMiddle())
    UiImage("MOD/ui/crosshair.png")

    if STATE.barrelTemp > BARREL_ROOM_TEMP then
        local target = math.floor(STATE.barrelTemp / (BARREL_MAX_TEMP - BARREL_ROOM_TEMP) * 256)
        local remaining = target
        while remaining > 0 do
            local toDraw = 1
            local idx = 0
            while true do
                if toDraw * 2 > remaining then
                    break
                end
                toDraw = toDraw * 2
                idx = idx + 1
            end
            local rotation = (target - remaining) / 256 * 360
            UiPush()
            UiRotate(-rotation)
            UiImage("MOD/ui/heat.png", 146 * idx, 0, 146 * idx + 146, 146)
            UiPop()
            remaining = remaining - toDraw
        end
        UiPush()
        UiRotate(-target / 256 * 360)
        UiImage("MOD/ui/heat.png", 1315, 0, 1460, 146)
        UiPop()
    end

    if STATE.isIncendiary then
        UiAlign("bottom left")
        UiTranslate(-950, 530)
		UiFont("bold.ttf", 24)	
		UiColor(1, 1, 1)
		UiText("INCENDIARY SELECTED")
    end
    UiPop()
end

RegisterToolUMF("doomchaingun", TOOL)

function randBetween(min, max)
	return math.random() * (max - min) + min
end

function randVec(min, max)
    return Vec(randBetween(min, max), randBetween(min, max), randBetween(min, max))
end

function randQuat(min, max)
    return QuatEuler(randBetween(min, max), randBetween(min, max), randBetween(min, max))
end

function TransformLerp(a, b, x)
    return Transform(
        VecLerp(a.pos, b.pos, x),
        QuatSlerp(a.rot, b.rot, x)
    )
end

function particleGunFlash(radius)
    ParticleReset()
    ParticleType("plain")
    ParticleTile(3)
    ParticleColor(FLASH_R, FLASH_G, FLASH_B)
    ParticleRadius(radius)
    ParticleAlpha(0.8)
    ParticleGravity(0)
    ParticleEmissive(2)
    ParticleCollide(0)
end

function particleGunSmoke()
    ParticleReset()
    ParticleType("smoke")
    ParticleTile(3)
    ParticleColor(0.3, 0.3, 0.3)
    ParticleRadius(0.1, 0.2)
    ParticleAlpha(0.3, 0)
    ParticleGravity(-0.4)
    ParticleEmissive(0)
    ParticleCollide(1)
end

function particleDebrisSmoke(r, g, b)
    ParticleReset()
    ParticleType("plain")
    ParticleTile(3)
    ParticleColor(r, g, b)
    ParticleRadius(0.3, 0.5)
    ParticleAlpha(0.8, 0)
    ParticleGravity(-0.4)
    ParticleEmissive(0)
    ParticleCollide(0)
end

function particleDebris(r, g, b, a)
    ParticleReset()
    ParticleType("plain")
    ParticleTile(6)
    ParticleColor(r, g, b)
    ParticleAlpha(a)
    ParticleRadius(randBetween(0.01, 0.05))
    ParticleGravity(-10)
    ParticleSticky(0.1)
    ParticleCollide(1)
    ParticleStretch(0)
end

function particleCooldownSmoke()
    ParticleReset()
    ParticleType("plain")
    ParticleTile(0)
    ParticleColor(0.7, 0.7, 0.7)
    ParticleAlpha(0.05)
    ParticleRadius(0.5, 0.8)
    ParticleGravity(7)
    ParticleCollide(0)
    ParticleStretch(0)
end

function particleImpact()
    ParticleReset()
    ParticleType("plain")
    ParticleTile(6)
    ParticleEmissive(5)
    ParticleColor(1, 0.32, 0)
    ParticleAlpha(1, 0)
    ParticleRadius(0.01)
    ParticleGravity(0)
    ParticleSticky(0.1)
    ParticleCollide(1)
    ParticleStretch(0)
end
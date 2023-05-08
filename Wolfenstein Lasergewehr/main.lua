#include "umf_tool.lua"
#include "prefab.lua"

local TOOL = {}
TOOL.model = {
    prefab = LASERGEWEHR_PREFAB,
    objects = LASERGEWEHR_OBJECTS
}
TOOL.printname = "Wolfenstein Lasergewehr"
TOOL.group = 6

local INITIAL_TRANSFORM = Transform(Vec(1, -1.0, 0.2), QuatEuler())
local DIST_BETWEEN_BEAM_PARTICLES = 0.25
local BEAM_R = 1
local BEAM_G = 0.1
local BEAM_B = 0

local SPIN_ACCEL = 360 * 3.2
local SPIN_DECEL = 360
local SPIN_VEL_MAX = 360 * 4

local SOUND_COOLDOWN = 0.5
local LASER_LOOP_OFFSET_TIME = 1

local LASER_HOLE_RADIUS = 0.5

local AMMO_DRAIN_RATE = 20

local LIGHTNING_NUM_POINTS = 15

local STATE = {
    melting = {},
    spinVel = 0,
    spin = 0,
    startTime = -1,
    soundTimer = -1
}

function destructibleRobots(shape, damage, hitcounter)
	if HasTag(shape, "shapeHealth") then
		if tonumber(GetTagValue(shape, "shapeHealth"))-damage < 0 and not HasTag(shape, "body") then 
			RemoveTag(shape,"unbreakable")
		end
	end

    SetFloat('level.destructible-bot.hitCounter', hitcounter)
    SetInt('level.destructible-bot.hitShape', shape)
    SetString('level.destructible-bot.weapon', "wolflgewehr")
    SetFloat('level.destructible-bot.damage', damage)
end

function init()
    HANDLE_SPRITE_WOLFLGEWEHR_BEAM = LoadSprite("MOD/sprite/beam.png")
    HANDLE_SPRITE_WOLFLGEWEHR_MUZFLASH = LoadSprite("MOD/sprite/muzflash.png")
    HANDLE_SPRITE_WOLFLGEWEHR_MUZBLOOM = LoadSprite("MOD/sprite/muzbloom.png")
    HANDLE_SPRITE_WOLFLGEWEHR_GLARE = LoadSprite("MOD/sprite/glare.png")

    HANDLE_SOUND_WOLFLGEWEHR_SPINUP = LoadSound("MOD/sound/spinup.ogg")
    HANDLE_SOUND_WOLFLGEWEHR_SPINDOWN = LoadSound("MOD/sound/spindown.ogg")
    HANDLE_SOUND_WOLFLGEWEHR_LASERSTART = LoadSound("MOD/sound/laserstart.ogg")
    HANDLE_LOOP_WOLFLGEWEHR_SPIN = LoadLoop("MOD/sound/spin.ogg")
    HANDLE_LOOP_WOLFLGEWEHR_LASER = LoadLoop("MOD/sound/laser.ogg")

    SetFloat("game.tool.wolflgewehr.ammo", 400)

    STATE.infiniteAmmo = GetBool("savegame.mod.infiniteammo")
    STATE.makeFire = GetBool("savegame.mod.makefire")
    STATE.limitSize = GetBool("savegame.mod.limitsize")

    if STATE.infiniteAmmo then
        SetString("game.tool.wolflgewehr.ammo.display", "")
    end
end

function TOOL:Tick(dt)
    if STATE.soundTimer > -1 then
        STATE.soundTimer = STATE.soundTimer + dt
        if STATE.soundTimer >= SOUND_COOLDOWN then
            STATE.soundTimer = -1
        end
    end
    if GetString("game.player.tool") == "wolflgewehr" and GetPlayerVehicle() == 0 then
        local toolFinalTransform = INITIAL_TRANSFORM
        local playerTransform = GetPlayerCameraTransform()
        local dir = TransformToParentVec(playerTransform, Vec(0, 0, -1))
        QueryRejectBody(GetToolBody())
        local hit, dist, normal, shape = QueryRaycast(playerTransform.pos, dir, 300, 0, true)
        if not hit then
            dist = 300
        end
        local point = VecAdd(playerTransform.pos, VecScale(dir, dist))

        local barrelEndTransform = TOOL:GetBoneGlobalTransform("barrelend")
        local lookRot = QuatLookAt(barrelEndTransform.pos, point)
        local deltaRot = TransformToLocalTransform(barrelEndTransform, Transform(barrelEndTransform.pos, lookRot)).rot
        toolFinalTransform.rot = QuatRotateQuat(QuatSlerp(Quat(), deltaRot, 2 * dt), toolFinalTransform.rot)

        STATE.spin = STATE.spin + STATE.spinVel * dt
        if STATE.spin > 360 then
            STATE.spin = STATE.spin - 360
        end

        local lightPos = TOOL:GetBoneGlobalTransform("shaftlight").pos
        PointLight(lightPos, BEAM_R, BEAM_G, BEAM_B, math.max(0, (STATE.spinVel - (SPIN_VEL_MAX / 2)) / (SPIN_VEL_MAX / 2)))

        if STATE.spinVel > SPIN_VEL_MAX / 2 then
            drawLightning(dt)
        end

        local ammo = GetFloat("game.tool.wolflgewehr.ammo")

        if InputDown("lmb") and ammo > 0 then
            
            if STATE.spinVel < SPIN_VEL_MAX and STATE.spinVel + SPIN_ACCEL * dt >= SPIN_VEL_MAX then
                PlaySound(HANDLE_SOUND_WOLFLGEWEHR_LASERSTART)
                STATE.startTime = GetTime()
            end
            STATE.spinVel = math.min(SPIN_VEL_MAX, STATE.spinVel + SPIN_ACCEL * dt)


            if STATE.spinVel == SPIN_VEL_MAX then
                dir = TransformToParentVec(barrelEndTransform, Vec(0, 0, -1))
                QueryRejectBody(GetToolBody())
                hit, dist, normal, shape = QueryRaycast(barrelEndTransform.pos, dir, 300, 0, true)
                if not hit then
                    dist = 300
                end
                point = VecAdd(barrelEndTransform.pos, VecScale(dir, dist))

                if hit then
                    local body = GetShapeBody(shape)
                    if IsBodyDynamic(body) then
                        meltBody(body, point)
                    else
                        destructibleRobots(shape, 10, 1)
                        Paint(point, LASER_HOLE_RADIUS + 0.2, "explosion")
                        local num = MakeHole(point, LASER_HOLE_RADIUS, LASER_HOLE_RADIUS, LASER_HOLE_RADIUS, true)
                        particleLava()
                        if num > 0 then
                            for i = 0, math.sqrt(num) do
                                SpawnParticle(VecAdd(point, randVec(-LASER_HOLE_RADIUS, LASER_HOLE_RADIUS)), randVec(-0.2, 0.2), randBetween(1, 2))
                            end
                        end
                        if STATE.makeFire then
                            SpawnFire(point)
                        end
                    end
                end

                drawBeam(dt)

                particleSmoke()
                SpawnParticle(barrelEndTransform.pos, randVec(-0.2, 0.2), randBetween(0.3, 0.5))

                local volume = 1
                if STATE.startTime > -1 then
                    local deltaTime = GetTime() - STATE.startTime
                    volume = deltaTime /  LASER_LOOP_OFFSET_TIME
                    if deltaTime > LASER_LOOP_OFFSET_TIME then
                        STATE.startTime = -1
                    end
                end
                PlayLoop(HANDLE_LOOP_WOLFLGEWEHR_LASER, playerTransform.pos, volume)

                if not STATE.infiniteAmmo then
                    SetFloat("game.tool.wolflgewehr.ammo", math.max(0, ammo - AMMO_DRAIN_RATE * dt))
                end

            end
        elseif InputDown("rmb") and ammo > 0 then
            STATE.spinVel = math.min(SPIN_VEL_MAX, STATE.spinVel + SPIN_ACCEL * dt)
            if STATE.spinVel == SPIN_VEL_MAX then
                PlayLoop(HANDLE_LOOP_WOLFLGEWEHR_SPIN)
            end
        else
            if ammo == 0 and STATE.spinVel == SPIN_VEL_MAX then
                PlaySound(HANDLE_SOUND_WOLFLGEWEHR_SPINDOWN)
            end
            STATE.spinVel = math.max(0, STATE.spinVel - SPIN_DECEL * dt)
        end
        SetToolTransform(toolFinalTransform)

        if InputPressed("lmb") and STATE.spinVel == SPIN_VEL_MAX then
            PlaySound(HANDLE_SOUND_WOLFLGEWEHR_LASERSTART)
            STATE.startTime = GetTime()
        end

        local canDoSound = STATE.soundTimer == -1 and ammo > 0
        if canDoSound and ((InputPressed("lmb") and not InputDown("rmb")) or (InputPressed("rmb") and not InputDown("lmb"))) then
            PlaySound(HANDLE_SOUND_WOLFLGEWEHR_SPINUP)
            STATE.soundTimer = 0
        elseif canDoSound and ((InputReleased("lmb") and not InputDown("rmb")) or (InputReleased("rmb") and not InputDown("lmb"))) then
            PlaySound(HANDLE_SOUND_WOLFLGEWEHR_SPINDOWN)
            STATE.soundTimer = 0
        end
    end
end

function drawBeam(dt)
    local origin = TOOL:GetBoneGlobalTransform("barrelend")

    local muzBloomTransform = TransformToParentTransform(origin, Transform(Vec(0, -0.02, -1), QuatEuler(-90, 0, 0)))
    DrawSprite(HANDLE_SPRITE_WOLFLGEWEHR_MUZBLOOM, muzBloomTransform, 0.3, 2, 1, 1, 1, 1, true, true)

    local playerTransform = GetPlayerCameraTransform()
    local dir = TransformToParentVec(origin, Vec(0, 0, -1))
    QueryRejectBody(GetToolBody())
    local hit, dist = QueryRaycast(origin.pos, dir, 300, 0, true)
    if not hit then
        dist = 300
    end
    local point = VecAdd(origin.pos, VecScale(dir, dist))
    local length = VecLength(VecSub(point, origin.pos)) + 0.2
    local halfway = VecLerp(origin.pos, point, 0.5)
    local rotation = QuatRotateQuat(QuatLookAt(origin.pos, point), QuatEuler(90, 0, 0))
    DrawSprite(HANDLE_SPRITE_WOLFLGEWEHR_BEAM, Transform(halfway, rotation), 0.1, length, 1, 1, 1, 1, true, true)
    PointLight(point, BEAM_R, BEAM_G, BEAM_B, 0.3)

    local muzFlashTransform = TransformToParentTransform(origin, Transform(Vec(), QuatEuler(0, 0, randBetween(0, 360))))
    local size = randBetween(0.5, 1.2)
    DrawSprite(HANDLE_SPRITE_WOLFLGEWEHR_MUZFLASH, muzFlashTransform, size, size, 1, 1, 1, 1, true)
end

function meltBody(body, point)
    SetBodyDynamic(body, false)
    local min, max = GetBodyBounds(body)
    -- 8 corners
    local points = {
        Vec(max[1], min[2], min[3]),
        Vec(min[1], max[2], min[3]),
        Vec(min[1], min[2], max[3]),
        Vec(max[1], min[2], max[3]),
        Vec(max[1], max[2], min[3]),
        Vec(min[1], max[2], max[3]),
        max
    }
    local furthest = min
    local furthestDist = VecLength(VecSub(min, point))
    for i = 1, 7 do
        local dist = VecLength(VecSub(points[i], point))
        if dist > furthestDist then
            furthest = points[i]
            furthestDist = dist
        end
    end
    local radius = VecLength(VecSub(furthest, point))
    local maxRadius
    if STATE.limitSize then
        maxRadius = 3
    else
        maxRadius = math.huge
    end
    table.insert(STATE.melting, {
        body = body,
        origin = TransformToLocalPoint(GetBodyTransform(body), point),
        radius = 0,
        maxRadius = math.min(maxRadius, radius * 1.5)
    })
end

function drawLightning(dt)
    local lightningTransform = TOOL:GetBoneGlobalTransform("lightning")
    particleLightning()
    ParticleAlpha((STATE.spinVel - SPIN_VEL_MAX / 2) / (SPIN_VEL_MAX / 2))

    for i = 1, randBetween(1, 3) do
        local direction = randBetween(0, 1) < 0.5
        local z = randBetween(-0.1, 0.3)
        local radius = randBetween(0.08, 0.12) - z * 0.05
        local startAngle = math.rad(randBetween(-140, 140))
        local point = Vec(radius * math.sin(startAngle), radius * math.cos(startAngle), z)
        local spiralling = false
        local arc = randBetween(60, 160)
        for i = 2, LIGHTNING_NUM_POINTS do
            if randBetween(0, 100) < 5 then
                spiralling = true
            end
            local angleDelta = math.rad(arc * (i / LIGHTNING_NUM_POINTS))
            local newPoint = Vec(radius * math.sin(startAngle + angleDelta), radius * math.cos(startAngle + angleDelta), z)
            newPoint = VecAdd(newPoint, randVec(-0.01, 0.01))

            local oldPointWorld = TransformToParentPoint(lightningTransform, point)
            local newPointWorld = TransformToParentPoint(lightningTransform, newPoint)

            local delta = VecSub(newPointWorld, oldPointWorld)
            SpawnParticle(oldPointWorld, VecScale(delta, 1 / dt), 1.5 * dt)

            point = newPoint
            if spiralling then
                radius = radius - 0.01
            end
            if direction then
                z = z + 0.002
            else
                z = z - 0.002
            end
        end
    end
end

function TOOL:Update(dt)
    updateMeltingBodies(dt)
end

function updateMeltingBodies(dt)
    particleLava()
    for i = #STATE.melting, 1, -1 do
        local toMelt = STATE.melting[i]
        if IsHandleValid(toMelt.body) then
            local min, max = GetBodyBounds(toMelt.body)
            local diff = VecSub(max, min)
            toMelt.radius = toMelt.radius + (toMelt.maxRadius / 2) * dt
            if toMelt.radius >= toMelt.maxRadius then
                SetBodyDynamic(toMelt.body, true)
                SetBodyVelocity(toMelt.body, Vec(0, 0, 0))
                toMelt.body = -1
            end
            for j = 1, 10 do
                if IsHandleValid(toMelt.body) then
                    local shapes = GetBodyShapes(toMelt.body)
                    local closestDist = math.huge
                    local closestPoint = Vec()
                    local closestShape = -1
                    local originWorld = TransformToParentPoint(GetBodyTransform(toMelt.body), toMelt.origin)
                    for i = 1, #shapes do
                        local shape = shapes[i]
                        local hit, point = GetShapeClosestPoint(shape, VecAdd(originWorld, randVec(-toMelt.radius, toMelt.radius)))
                        if hit then
                            local typ = GetShapeMaterialAtPosition(shape, point)
                            if (not HasTag(shape, "unbreakable")) and (typ ~= "heavymetal") then
                                local dist = VecLength(VecSub(point, originWorld))
                                if dist < closestDist then
                                    closestDist = dist
                                    closestPoint = point
                                    closestShape = shape
                                end
                            end
                        end
                    end
                    if VecLength(closestPoint) > 0 then
                        destructibleRobots(closestShape, 10, 1)
                        local size = math.sqrt(toMelt.radius, 10) / 3
                        local num = MakeHole(closestPoint, size, size, size, true)
                        for k = 1, math.sqrt(num) do
                            SpawnParticle(VecAdd(closestPoint, randVec(-size / 2, size / 2)), randVec(-0.2, 0.2), randBetween(1, 2))
                        end
                    end
                else
                    table.remove(STATE.melting, i)
                    break
                end
            end
        end
    end
end

function TOOL:Animate()
    local armature = self.armature
    armature:SetBoneTransform("Shaft", Transform(Vec(), QuatEuler(0, 0, STATE.spin)))
end

function TOOL:Draw(dt)
end

function TOOL:Holster()
    STATE.spinVel = 0
    STATE.spin = 0
end

RegisterToolUMF("wolflgewehr", TOOL)

function randBetween(min, max)
	return math.random() * (max - min) + min
end

function randVec(min, max)
    return Vec(randBetween(min, max), randBetween(min, max), randBetween(min, max))
end

function randQuat(min, max)
    return QuatEuler(randBetween(min, max), randBetween(min, max), randBetween(min, max))
end

function particleLava()
    ParticleReset()
    ParticleTile(6)
    ParticleRadius(0.05)
    ParticleType("plain")
    ParticleCollide(1)
    ParticleGravity(-10)
    ParticleSticky(1)
    ParticleAlpha(1)
    ParticleEmissive(3, 0)
    ParticleColor(1, 0.315, 0)
end

function particleBeam()
    ParticleReset()
    ParticleTile(3)
    ParticleRadius(1.5)
    ParticleType("plain")
    ParticleCollide(0)
    ParticleGravity(0)
    ParticleAlpha(0.05)
    ParticleEmissive(0.2)
    ParticleColor(1, 0.1, 0)
end

function particleSmoke()
    ParticleReset()
    ParticleType("plain")
    ParticleRadius(0.1)
    ParticleAlpha(0.15)
    ParticleColor(0.8, 0.8, 0.8)
    ParticleGravity(5)
end

function particleLightning()
    ParticleReset()
    ParticleTile(4)
    ParticleRadius(0.003)
    ParticleType("plain")
    ParticleCollide(0)
    ParticleGravity(0)
    ParticleRotation(0)
    ParticleSticky(0)
    ParticleAlpha(1)
    ParticleEmissive(5)
    ParticleColor(1, 0.8, 0.8)
    ParticleStretch(2)
end
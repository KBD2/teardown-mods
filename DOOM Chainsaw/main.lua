#include "registry.lua"

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
    RegisterTool("doomchainsaw", "DOOM Chainsaw", "MOD/vox/Chainsaw.vox", 1)
    SetBool("game.tool.doomchainsaw.enabled", true)

    SetString("game.tool.doomchainsaw.ammo.display", "")

    registryInit()

    PI = 3.14159265

    TOOL_BASE_TRANSFORM = Transform(Vec(1.0, -0.95, -0.4), QuatEuler(15, 40, 25))
    TOOL_HELD_TRANSFORM = Transform(Vec(0.3, -1.2, -0.1), QuatEuler(40, -20, 45))
    TOOL_EXHAUST_OFFSET = Vec(0.5, 0, -1.1)

    TOOL_HELD_ANGLE_MIN = -140
    TOOL_HELD_ANGLE_MAX = 0

    TOOL_NUM_TEETH = 30

    TOOL_TRANSFORM_TIME = 0.2

    TOOL_TOOTH_VELOCITY_MIN = 0.05
    TOOL_TOOTH_VELOCITY_MAX = 5
    TOOL_TOOTH_MAX_DECELERATION = -0.2
    TOOL_TOOTH_IMPULSE = 0.5

    TOOTH_WEAK_HOLE_SIZE = GetFloat("savegame.mod.doomchainsaw.holeweak")
    TOOTH_MEDIUM_HOLE_SIZE = GetFloat("savegame.mod.doomchainsaw.holemed")
    TOOTH_STRONG_HOLE_SIZE = GetFloat("savegame.mod.doomchainsaw.holestrong")

    ANIM_BASE_OFFSET = Vec(0.15, -0.3, -1.4)
    ANIM_PATH_HEIGHT = 0.5
    ANIM_PATH_LENGTH = 1.55

    HANDLE_SOUND_REVUP = LoadSound("MOD/sounds/revup.ogg")
    HANDLE_SOUND_REVDOWN = LoadSound("MOD/sounds/revdown.ogg")
    HANDLE_LOOP_IDLE = LoadLoop("MOD/sounds/idle.ogg")
    HANDLE_LOOP_RUN = LoadLoop("MOD/sounds/doomguyishere.ogg")
    HANDLE_LOOP_METAL = LoadLoop("MOD/sounds/metal.ogg")
    HANDLE_SOUND_PUTAWAY = LoadSound("MOD/sounds/putaway.ogg")

    glob = {}
    glob.t = 0
    glob.dt = 0
    glob.ddt = 0
    glob.transformTime = 0
    glob.state = "READY"
    glob.timeSinceLastRevUp = 0
    glob.hittingMetal = false
    glob.putAway = true
    glob.heldRot = 0
end

function tick(dt)
    if GetString("game.player.tool") == "doomchainsaw" and GetPlayerVehicle() == 0 then
        glob.putAway = false
        if animReady() then
            local shapes = GetBodyShapes(GetToolBody())
            glob.hittingMetal = false
            for i = 3, TOOL_NUM_TEETH + 2 do

                local offset = (i - 1) * ((2 * ANIM_PATH_LENGTH + PI / 4) / TOOL_NUM_TEETH)
                local t = (glob.t + offset) % (2 * ANIM_PATH_LENGTH + PI / 4)

                local x, y = getShapeOffset(t)
                local transform = Transform(VecAdd(ANIM_BASE_OFFSET, Vec(0, y, -x)), QuatEuler(0, 0, 0))

                SetShapeLocalTransform(shapes[i], transform)
                if glob.state == "CUTTING" and math.random() < math.min(0.2, 12 * dt) then
                    local worldPoint = TransformToParentPoint(GetBodyTransform(GetToolBody()), transform.pos)
                    local hit, point, normal, shape = QueryClosestPoint(worldPoint, 0.5)
                    if hit then
                        local typ, r, g, b, a = GetShapeMaterialAtPosition(shape, point)
                        local body = GetShapeBody(shape)
                        local isGore = false
                        if HasTag(body, "bodypart") then
                            isGore = true
                        end

                        destructibleRobots(shape, 10, 1)

                        local num = MakeHole(
                            worldPoint, 
                            TOOTH_WEAK_HOLE_SIZE,
                            TOOTH_MEDIUM_HOLE_SIZE,
                            TOOTH_STRONG_HOLE_SIZE,
                            true
                        )

                        local flingDir = Vec(0, 0, 0)
                        if t < ANIM_PATH_LENGTH then
                            flingDir = Vec(randBetween(-3, 3), randBetween(1, 2), -randBetween(1, 10))
                        end
                        if t > ANIM_PATH_LENGTH and t < ANIM_PATH_LENGTH + PI / 4 then
                            local y = -randBetween(1, 10) * math.sin(4 * (t - ANIM_PATH_LENGTH))
                            local x = -randBetween(1, 10) * math.cos(4 * (t - ANIM_PATH_LENGTH))
                            flingDir = Vec(randBetween(-3, 3), y, x)
                        end
                        if t >= ANIM_PATH_LENGTH + PI / 4 then
                            flingDir = Vec(randBetween(-3, 3), -randBetween(1, 2), randBetween(1, 10))
                        end

                        local flingVec = TransformToParentVec(GetBodyTransform(GetToolBody()), flingDir)

                        if num > 0 then
                            if not isGore then
                                particleDebris(r, g, b, a)
                            else
                                particleDebris(0.6, 0, 0.1, a)
                            end
                            for i = 1, 2 * num do
                                SpawnParticle(VecAdd(worldPoint, randVec(-0.1, 0.1)), VecScale(flingVec, 3), randBetween(2, 4))
                            end
                            if typ == "wood" or typ == "dirt" or typ == "plaster" or typ == "masonry" then
                                particleSmoke(r, g, b)
                                SpawnParticle(worldPoint, randVec(-0.1, 0.1), randBetween(1, 2))
                            end
                        end

                        if typ == "metal" or typ == "heavymetal" or typ == "rock" or typ == "unphysical" or typ == "none" then
                            glob.hittingMetal = true
                            particleSpark()
                            for i = 1, math.min(24, 1440 * dt) do
                                SpawnParticle(
                                    worldPoint,
                                    flingVec,
                                    randBetween(0.05, 0.6)
                                )
                            end
                        end
                    end
                end
            end
        end

        local playerPos = GetPlayerCameraTransform().pos

        if InputDown("usetool") and GetBool("game.player.canusetool") and GetPlayerGrabShape() == 0 then
            glob.ddt = 0.1
            glob.transformTime = math.min(glob.transformTime + dt, TOOL_TRANSFORM_TIME)
            glob.state = "CUTTING"
            particleExhaust()
            SpawnParticle(TransformToParentPoint(GetBodyTransform(GetToolBody()), TOOL_EXHAUST_OFFSET), randVec(-1, 1), 1)
            PlayLoop(HANDLE_LOOP_RUN, playerPos, 1)
            if glob.hittingMetal == true then
                PlayLoop(HANDLE_LOOP_METAL, playerPos, 1)
            end
        else
            if math.random() < 2 * dt then
                glob.ddt = 0.06
            end
            PlayLoop(HANDLE_LOOP_IDLE, playerPos, 1)
        end

        if InputDown("grab") and GetPlayerGrabShape() == 0 then
            if not InputDown("usetool") then
                glob.state = "READY"
            end
            glob.transformTime = math.min(glob.transformTime + dt, TOOL_TRANSFORM_TIME)
            SetBool("game.player.disableinput", true)
            glob.heldRot = math.max(math.min(glob.heldRot - InputValue("mousedx") / 10, TOOL_HELD_ANGLE_MAX), TOOL_HELD_ANGLE_MIN)
        else
            SetBool("game.player.disableinput", false)
        end

        if not InputDown("usetool") and not InputDown("grab") then
            glob.state = "READY"
            glob.transformTime = math.max(glob.transformTime - dt, 0)
        end

        local rotation = QuatRotateQuat(TOOL_HELD_TRANSFORM.rot, QuatAxisAngle(Vec(0, 0, 1), glob.heldRot))
        local toolFinalTrans = Transform(
            VecLerp(TOOL_BASE_TRANSFORM.pos, TOOL_HELD_TRANSFORM.pos, glob.transformTime / TOOL_TRANSFORM_TIME),
            QuatSlerp(TOOL_BASE_TRANSFORM.rot, rotation, glob.transformTime / TOOL_TRANSFORM_TIME)
        )

        toolFinalTrans.rot = QuatRotateQuat(toolFinalTrans.rot, randQuat(-1, 1))

        if glob.timeSinceLastRevUp > 0.5 then
            if InputPressed("usetool") and not InputPressed("grab") then
                PlaySound(HANDLE_SOUND_REVUP, playerPos, 1)
                glob.timeSinceLastRevUp = 0
            end
            if InputReleased("usetool") and not InputPressed("grab") then
                PlaySound(HANDLE_SOUND_REVDOWN, playerPos, 1)
            end
        end

        SetToolTransform(toolFinalTrans, 1)
        SetPlayerCameraOffsetTransform(Transform(Vec(0, 0, 0), randQuat(-0.1, 0.1)))
    else
        if glob.putAway == false then
            glob.putAway = true
            PlaySound(HANDLE_SOUND_PUTAWAY)
        end
    end

    glob.t = glob.t + glob.dt * dt
    glob.timeSinceLastRevUp = glob.timeSinceLastRevUp + dt
    glob.dt = math.min(math.max(glob.dt + glob.ddt, TOOL_TOOTH_VELOCITY_MIN), TOOL_TOOTH_VELOCITY_MAX)
    glob.ddt = math.max(glob.ddt - TOOL_TOOTH_IMPULSE * dt, TOOL_TOOTH_MAX_DECELERATION)
end

function getShapeOffset(t)
    local x = 0
    local y = 0
    if t >= 0 and t <= ANIM_PATH_LENGTH then
        return t, ANIM_PATH_HEIGHT
    end
    if t > ANIM_PATH_LENGTH and t <= (ANIM_PATH_LENGTH + PI / 4) then
        return 
            (ANIM_PATH_HEIGHT / 2) * math.sin(4 * (t - ANIM_PATH_LENGTH)) + ANIM_PATH_LENGTH,
            (ANIM_PATH_HEIGHT / 2) * math.cos(4 * (t - ANIM_PATH_LENGTH)) + ANIM_PATH_HEIGHT / 2
    end
    if t > (ANIM_PATH_LENGTH + PI / 4) then
        return ANIM_PATH_LENGTH - (t - (ANIM_PATH_LENGTH + PI / 4)), 0
    end
end

function animReady()
    return #GetBodyShapes(GetToolBody()) > 1
end

function update(dt)
end

function draw(dt)
end

function particleDebug()
    ParticleReset()
    ParticleRadius(0.05)
    ParticleColor(1, 0, 0)
    ParticleEmissive(1)
    ParticleTile(6)
    ParticleAlpha(1)
end

function particleDebris(r, g, b, a)
    ParticleReset()
    ParticleType("plain")
    ParticleTile(6)
    ParticleColor(r, g, b)
    ParticleRadius(randBetween(0.01, 0.02))
    ParticleAlpha(a)
    ParticleGravity(-10)
    ParticleSticky(0.4)
    ParticleCollide(1)
    ParticleStretch(0)
end

function particleSmoke(r, g, b)
    ParticleReset()
    ParticleType("smoke")
    ParticleTile(3)
    ParticleColor(r, g, b)
    ParticleRadius(0.3)
    ParticleAlpha(0.4, 0)
end

function particleExhaust()
    ParticleReset()
    ParticleType("smoke")
    ParticleTile(3)
    ParticleRadius(0.1)
    ParticleAlpha(0.2, 0)
    ParticleGravity(1)
end

function particleSpark()
    ParticleReset()
    ParticleType("plain")
    ParticleTile(6)
    ParticleRadius(0.005)
    ParticleColor(1, 0.25, 0.12)
    ParticleEmissive(5)
    ParticleGravity(-10)
    ParticleCollide(1)
    ParticleStretch(1.5)
    ParticleDrag(0.2)
end

function randBetween(min, max)
	return math.random() * (max - min) + min
end

function randVec(min, max)
    return Vec(randBetween(min, max), randBetween(min, max), randBetween(min, max))
end

function randQuat(min, max)
    return QuatEuler(randBetween(min, max), randBetween(min, max), randBetween(min, max))
end
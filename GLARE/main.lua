--[[
#include "libs/Automatic.lua"
#include "libs/LnL.lua"
#include "registry.lua"
]]

RANGE = 80
HEAT_RANGE = 20
HEAT_ANGLE = 20

DELTA_PER_SECOND = 10
HOLE_RADIUS_INITIAL = 1
HOLE_RADIUS_PER_SECOND = 0.2
CHARGE_MAX_TIME = 10
MAX_SHOOT_STEPS_PER_FRAME = 30

KNOCKBACK_COEFFICIENT = -2

TRIGGER_RELEASE_TIMER = 0.1

DEATH_TIMER = 7

CHARGE_SHAKE_MAX_ANGLE = 2

COOLDOWN = 1.5
WARMUP = 0.464
CUFF_MULTIPLIER = 5

LAVA_DRIP_ATTEMPTS_MAX = 3000
INITIAL_DRIPS_PER_UPDATE = 30
DRIP_TIME = 10
MAX_LIGHTS_PER_SHOOT = 100

SLAG_COOL_TIME = 20

DEBRIS_CULL_DISAPPEAR_TIME = 5
DEBRIS_FORCED_DISAPPEAR_TIME = 45

LIGHTNING_PART_LENGTH = 0.06
LIGHTNING_PART_MAX_PARTICLES = 3

PLASMA_GLOW_IDLE = Vec(0.7, 0.14, 0.48)
PLASMA_GLOW_ACTIVE = Vec(0.8, 1, 0)

VOX_SIZE = 0.1

SWAP_TOOL_COOLDOWN = 0.5

POSE_KEYFRAMES = {
    DEFAULT = Transform(Vec(0.5, -1.0, -1), QuatEuler(2, 8, 15));
    HEAT = Transform(Vec(0.3, -1.3, -1.4), QuatEuler(3, 5, -8));
}
POSE_TRANSITION_TIME = 0.5

SM_POS_K_VALUES = Vec(2, 0.9, 1.25)
SM_ROT_K_VALUES = Vec(1.5, 0.5, 1)

SM_ROT_CLAMP_ANGLE = 20

LIGHT_COLOUR = Vec(0.8, 1, 0)

HEAT_LIGHT_PREFAB = '<light pos="0 0 0" rot="0 180 0" type="cone" static="true" scale="10" angle="' .. math.sqrt(2) * HEAT_ANGLE .. '" penumbra="0" fogscale="10" color="' 
.. LIGHT_COLOUR[1] .. ' '  
.. LIGHT_COLOUR[2] .. ' '
.. LIGHT_COLOUR[3] ..'"/>'

FLASH_LIGHT_PREFAB = '<light pos="0 0 0" rot="0 180 0" type="area" static="true" scale="30" penumbra="0" size="0.2 0.2" fogscale="10" color="'
.. LIGHT_COLOUR[1] .. ' '  
.. LIGHT_COLOUR[2] .. ' '
.. LIGHT_COLOUR[3] ..'"/>'
FLASH_LIGHT_MAX_TIME = 0.05

CUFFS_KEYFRAME = {
    QuatEuler(0, 0, 0),
    QuatEuler(90, 0, 0),
    QuatEuler(0, 90, 0)
}

BODY_FREEZE_TIME = 0.3

function init()
    registryInit()

    DELETE_COLD = not GetBool("savegame.mod.qualitydebris")
    DO_MERGE = GetBool("savegame.mod.domerge")
    DROP_WEAPON = GetBool("savegame.mod.dropweapon")
    FPS_GLOW = GetBool("savegame.mod.fpsglow")

    STATE = {
        coroutines = {};
        debugCrosses = {};

        warmup = -1;
        cooldown = -1;
        timeHeld = 0;
        whooshTimer = 0;
        lastTimeHeld = 0;
        triggerReleaseTimer = -1;

        lightning = {};

        plasmaGlowT = 0;
        plasmaGlowIntensity = 0.3;
        plasmaParticleSize = 0.06;

        shootFlash = {
            id = -1;
            timeLeft = 0;
        };

        heatLight = {
            id = -1;
            timeLeft = 0;
        };

        slag = {};

        sm = nil;
        lastToolTransform = nil;

        cuffRotations = {
            QuatEuler(0, 0, 0),
            QuatEuler(0, 0, 0),
            QuatEuler(0, 0, 0)
        };

        savedCuffRotations = {};

        pose = {
            state = "DEFAULT";
            transitionTime = 0;
        };

        frozenBodies = {};

        displayWarning = 0;

        deathTimer = 0;
        deathPos = nil;
        droppedBody = nil;

        setAimDot = false;

        swapToolCooldown = 0;
    }

    for _ = 0, 20 do
        table.insert(STATE.lightning, {
            rot = AutoRandomQuat(180);
            av = AutoRandomQuat(30)
        })
    end

    SPRITE_LASER = LoadSprite("MOD/img/sprite/beam.png")

    SOUND_SHOOT = LoadSound("MOD/snd/shoot.ogg")
    LOOP_BEAM = LoadLoop("MOD/snd/heatbeam.ogg")
    LOOP_PIPE = LoadLoop("MOD/snd/pipe.ogg")

    LOOP_HUM = LoadLoop("MOD/snd/hum.ogg")

    SOUND_WHOOSH = LoadSound("MOD/snd/whoosh.ogg")
    LOOP_CHARGE = LoadLoop("MOD/snd/shepard.ogg")
    SOUND_COOLDOWN = LoadSound("MOD/snd/cooldown.ogg")
    LOOP_COOLDOWN = LoadLoop("MOD/snd/shepard_down.ogg")

    SOUND_TRIGGER_PULL = LoadSound("MOD/snd/trigger_pull.ogg")
    SOUND_TRIGGER_RELEASE = LoadSound("MOD/snd/trigger_release.ogg")

    SOUND_CLICK = LoadSound("MOD/snd/click.ogg")

    SOUND_WARNING = LoadSound("warning-beep.ogg")
    LOOP_SPARKS = LoadLoop("MOD/snd/sparks.ogg")

    LOOP_NUKED = LoadLoop("MOD/snd/tinnitus.ogg")
    LOOP_GEIGER = LoadLoop("MOD/snd/geigercounter.ogg")

    TOOL = LnLInitializeTool("glarebeam", "MOD/xml/tool.xml", "GLARE", 5)
end

function tick(dt)
    local baseTransform
    if STATE.pose.state == "DEFAULT" or STATE.pose.state == "HEAT" then
        baseTransform = POSE_KEYFRAMES[STATE.pose.state]
    else
        local t = 1 - STATE.pose.transitionTime / POSE_TRANSITION_TIME
        local curveVal = math.cos(math.pi / 2 * t - math.pi / 2)
        if STATE.pose.state == "HEAT_WARMUP" then
            baseTransform = AutoTransformLerp(POSE_KEYFRAMES.DEFAULT, POSE_KEYFRAMES.HEAT, curveVal)
        else 
            baseTransform = AutoTransformLerp(POSE_KEYFRAMES.HEAT, POSE_KEYFRAMES.DEFAULT, curveVal)
        end
    end

    local camera = GetPlayerCameraTransform()

    if STATE.sm == nil then
        STATE.sm = {
            pos = AutoSM_Define(POSE_KEYFRAMES.DEFAULT.pos, unpack(SM_POS_K_VALUES));
            rot = AutoSM_DefineQuat(POSE_KEYFRAMES.DEFAULT.rot, unpack(SM_ROT_K_VALUES))
        }
        STATE.lastToolTransform = LnLGetBoneWorldTransform(TOOL, "body")
    end

    if LnLSelected(TOOL) and GetPlayerGrabShape() == 0 and GetPlayerVehicle() == 0 then
        STATE.swapToolCooldown = math.max(0, STATE.swapToolCooldown - dt)

        STATE.setAimDot = true
        SetBool("hud.aimdot", false)

        local toolPos = TransformToParentTransform(camera, baseTransform).pos

        if STATE.pose.state ~= "HEAT" and STATE.timeHeld == 0 then
            local humCoefficient = 1
            if STATE.cooldown > 0 then
                humCoefficient = ((COOLDOWN - STATE.cooldown) / COOLDOWN)
            end
            if STATE.pose.state == "HEAT_WARMUP" then
                humCoefficient = STATE.pose.transitionTime / POSE_TRANSITION_TIME
            end
            if STATE.pose.state == "HEAT_COOLDOWN" then
                humCoefficient = (COOLDOWN - STATE.pose.transitionTime) / POSE_TRANSITION_TIME
            end
            PlayLoop(LOOP_HUM, toolPos, humCoefficient)
        end

        -- Pose transitions

        if (InputDown("usetool") and STATE.cooldown == -1 and STATE.pose.state == "DEFAULT" and STATE.swapToolCooldown == 0) or STATE.triggerReleaseTimer > 0 then

            if STATE.timeHeld == 0 then
                STATE.whooshTimer = 0.3
                PlaySound(SOUND_TRIGGER_RELEASE, toolPos, 0.1)
            end
            if STATE.triggerReleaseTimer == -1 then
                STATE.timeHeld = STATE.timeHeld + dt
            end
            if STATE.timeHeld > CHARGE_MAX_TIME then
                SetPlayerHealth(0)
                STATE.timeHeld = 0
                STATE.displayWarning = 0
                STATE.deathTimer = DEATH_TIMER
                Explosion(camera.pos, 4)
                MakeHole(camera.pos, 100, 100, 100, true)
                STATE.deathPos = camera.pos
                STATE.triggerReleaseTimer = -1
                if DROP_WEAPON then
                    local body = LnLDropTool(true, true, 1)
                    STATE.droppedBody = body
                    SetBodyDynamic(body, false)
                    STATE.frozenBodies[body] = 4
                    SetBodyTransform(body, TransformToParentTransform(camera, Transform(Vec(0, 5, 0), QuatEuler(0, 0, 180))))
                end
            end
            local normalised = STATE.timeHeld / CHARGE_MAX_TIME
            if normalised > 0.85 then
                STATE.displayWarning = 2
            else
                if normalised > 0.7 then
                    STATE.displayWarning = 1
                end
            end

            if normalised > 0.7 then
                PlayLoop(LOOP_SPARKS, toolPos, 1)
            end

            STATE.whooshTimer = math.max(0, STATE.whooshTimer - dt)
            if STATE.whooshTimer == 0 then
                UiSound("MOD/snd/whoosh.ogg", normalised + 0.3, 0.7 + 0.4 * (STATE.timeHeld / CHARGE_MAX_TIME), 0.4)
                STATE.whooshTimer = math.max(0.12, -STATE.timeHeld / 10.5 + 0.9)
            end
            PlayLoop(LOOP_CHARGE, toolPos, normalised)

            SetPlayerCameraOffsetTransform(Transform(Vec(), AutoRandomQuat(CHARGE_SHAKE_MAX_ANGLE * STATE.timeHeld / CHARGE_MAX_TIME)))

            STATE.plasmaGlowT = math.min(1, STATE.timeHeld / (CHARGE_MAX_TIME - 6))
            STATE.plasmaGlowIntensity = math.min(1, STATE.timeHeld / CHARGE_MAX_TIME) * 5 + 0.3
            STATE.plasmaParticleSize = math.min(0.4, ((STATE.timeHeld + 3) / CHARGE_MAX_TIME)) * 0.5 + 0.06
        end

        if InputDown("grab") and STATE.cooldown == -1 and STATE.timeHeld == 0 and STATE.pose.state == "DEFAULT" then
            STATE.savedCuffRotations = STATE.cuffRotations
            STATE.pose.state = "HEAT_WARMUP"
            STATE.pose.transitionTime = POSE_TRANSITION_TIME
        else
            if InputDown("grab") and STATE.pose.state == "HEAT_COOLDOWN" then
                STATE.pose.state = "HEAT_WARMUP"
                STATE.pose.transitionTime = POSE_TRANSITION_TIME
            end
        end

        if not InputDown("grab") and STATE.pose.state == "HEAT" then
            STATE.pose.state = "HEAT_COOLDOWN"
            STATE.pose.transitionTime = POSE_TRANSITION_TIME
            Delete(STATE.heatLight.id)
            STATE.heatLight.id = nil
        else
            if not InputDown("grab") and STATE.pose.state == "HEAT_WARMUP" then
                STATE.pose.state = "HEAT_COOLDOWN"
                STATE.pose.transitionTime = POSE_TRANSITION_TIME - STATE.pose.transitionTime
            end
        end

        if STATE.pose.state == "HEAT_WARMUP" or STATE.pose.state == "HEAT_COOLDOWN" then
            if STATE.pose.state == "HEAT_WARMUP" and STATE.pose.transitionTime > POSE_TRANSITION_TIME / 2 and STATE.pose.transitionTime - dt < POSE_TRANSITION_TIME / 2 then
                PlaySound(SOUND_CLICK, toolPos, 0.05)
            end

            STATE.pose.transitionTime = math.max(0, STATE.pose.transitionTime - dt)

            if STATE.pose.transitionTime == 0 then
                if STATE.pose.state == "HEAT_WARMUP" then
                    STATE.pose.state = "HEAT"
                else
                    STATE.pose.state = "DEFAULT"
                end
            end
        end

        -- Main pose shoot
        if STATE.timeHeld > 0 and not InputDown("usetool") then
            if STATE.triggerReleaseTimer > 0 then
                STATE.triggerReleaseTimer = math.max(0, STATE.triggerReleaseTimer - dt)
                if STATE.triggerReleaseTimer == 0 then
                    STATE.triggerReleaseTimer = -1
                    fireWeapon()
                end
            else 
                if STATE.triggerReleaseTimer == -1 then
                    STATE.triggerReleaseTimer = TRIGGER_RELEASE_TIMER
                    PlaySound(SOUND_TRIGGER_PULL, TransformToParentTransform(camera, baseTransform).pos, 0.2)
                end
            end
        end

        -- HEAT pose
        if STATE.pose.state == "HEAT" then
            local orig = LnLGetBoneWorldTransform(TOOL, "body.barrelend")
            STATE.heatLight.timeLeft = math.max(0, STATE.heatLight.timeLeft - dt)
            if STATE.heatLight.timeLeft == 0 then
                Delete(STATE.heatLight.id)
                STATE.heatLight.id = nil
                if math.random() > 0.05 then
                    STATE.heatLight.id = Spawn(HEAT_LIGHT_PREFAB, LnLGetBoneWorldTransform(TOOL, "body.barrelend"), true)[1]
                end
                STATE.heatLight.timeLeft = 2 * dt
            end

            SetPlayerCameraOffsetTransform(Transform(Vec(), AutoRandomQuat(0.3)))

            PlayLoop(LOOP_BEAM, orig.pos, 1)
        end

        if STATE.pose.state == "HEAT" or STATE.pose.state == "HEAT_COOLDOWN" or STATE.cooldown > 0 then
            local coefficient = 1
            if STATE.cooldown > 0 then
                coefficient = STATE.cooldown / COOLDOWN
            end
            if STATE.pose.state == "HEAT_COOLDOWN" then
                coefficient = STATE.pose.transitionTime / POSE_TRANSITION_TIME
            end

            particleCooling()
            local spawnLoc = LnLGetBoneWorldTransform(TOOL, "body.tank.outlet")
            SpawnParticle(spawnLoc.pos, VecScale(QuatRotateVec(spawnLoc.rot, Vec(0, 0, -1)), randBetween(0.5, 1)), randBetween(0.3, 0.6))
            PlayLoop(LOOP_PIPE, toolPos, 0.2 * coefficient)
        end

        -- Cuff spin coefficient and LN2 tank shake

        local ballcuffDtCoefficient = 1

        if STATE.cooldown > 0 then
            STATE.cooldown = math.max(0, STATE.cooldown - dt)
            if STATE.cooldown == 0 then
                STATE.cooldown = -1
            end
            if STATE.warmup == -1 then
                local mul = math.max(0, (STATE.cooldown / 2) - 0.5)
                SetPlayerCameraOffsetTransform(Transform(Vec(), AutoRandomQuat(2 * mul)))
                LnLSetTransformation(TOOL, "body.tank", Transform(VecScale(randVec(-0.01, 0.01), STATE.cooldown / 3), Quat()))
            end

            -- https://www.desmos.com/calculator/85rbblon9x
            local invC = COOLDOWN - STATE.cooldown
            ballcuffDtCoefficient = CUFF_MULTIPLIER * (-math.abs(invC - WARMUP) / (COOLDOWN - WARMUP) + 1) + 1

            if STATE.cooldown > 0.3 * COOLDOWN then
                STATE.whooshTimer = math.max(0, STATE.whooshTimer - dt)
                if STATE.whooshTimer == 0 then
                    UiSound("MOD/snd/whoosh.ogg", math.max(0.1, 0.3 - 0.2 * STATE.cooldown), math.max(0.7, 0.9 - 0.2 * ((COOLDOWN - STATE.cooldown) / COOLDOWN)), 0.4)
                    STATE.whooshTimer = (0.5 + (math.random() * 0.1 - 0.05)) * (COOLDOWN - STATE.cooldown)
                end
            end
            if STATE.cooldown < COOLDOWN - 0.2 then
                local pos = TransformToParentTransform(camera, baseTransform).pos
                PlayLoop(LOOP_COOLDOWN, pos, math.max(0, (STATE.cooldown / COOLDOWN) * (STATE.lastTimeHeld / CHARGE_MAX_TIME) * 0.2))
            end
            
            STATE.plasmaGlowT = math.max(0, 1 - (COOLDOWN - STATE.cooldown) / COOLDOWN)
            STATE.plasmaGlowIntensity = math.max(0.3, 1.3 - 1 * ((COOLDOWN - STATE.cooldown) / COOLDOWN))
            STATE.plasmaParticleSize = math.max(0.06, 0.36 - 0.3 * ((COOLDOWN - STATE.cooldown) / COOLDOWN))

        end

        if STATE.timeHeld > 0 then
            ballcuffDtCoefficient = CUFF_MULTIPLIER * (-math.abs(STATE.timeHeld - CHARGE_MAX_TIME) / CHARGE_MAX_TIME + 1) + 1
        end

        -- Update ball lightning
        updateLightning(dt)
        local glowColour = PLASMA_GLOW_IDLE
        if STATE.plasmaGlowT > 0 then
            glowColour = VecLerp(PLASMA_GLOW_IDLE, PLASMA_GLOW_ACTIVE, STATE.plasmaGlowT)
        else 
            if STATE.pose.state == "HEAT_WARMUP" then
                glowColour = VecLerp(PLASMA_GLOW_ACTIVE, PLASMA_GLOW_IDLE, STATE.pose.transitionTime)
            else
                if STATE.pose.state == "HEAT_COOLDOWN" then
                    glowColour = VecLerp(PLASMA_GLOW_IDLE, PLASMA_GLOW_ACTIVE, STATE.pose.transitionTime)
                else
                    if STATE.pose.state == "HEAT" then
                        glowColour = PLASMA_GLOW_ACTIVE
                    end
                end
            end
        end
        local orig = LnLGetBoneWorldTransform(TOOL, "body.ball").pos
        PointLight(orig, glowColour[1], glowColour[2], glowColour[3], STATE.plasmaGlowIntensity)
        PointLight(VecAdd(orig, Vec(0, -0.4, 0)), glowColour[1], glowColour[2], glowColour[3], STATE.plasmaGlowIntensity)

        -- Second Order System motion tick
        -- Thaks to Autumn's Procket for having code I can follow

        local camDir = TransformToParentVec(camera, Vec(0, 0, -1))
        local hit, dist = QueryRaycast(camera.pos, camDir, 50)
        if not hit then
            dist = 50
        end
        local bodyTransform = TransformToParentTransform(camera, baseTransform)
        local targetPos = VecAdd(camera.pos, VecScale(camDir, math.max(5, dist)))
        local targetRot = QuatLookAt(LnLGetBoneWorldTransform(TOOL, "body.barrelend").pos, targetPos)
        local targetLocalRot = TransformToLocalTransform(bodyTransform, Transform(Vec(), targetRot)).rot

        local playerVel = GetPlayerVelocity()

        local p_delta = Vec(InputValue("camerax"), InputValue("cameray"))
        local r_delta = Vec(InputValue("cameray"), InputValue("camerax"))
        AutoSM_AddVelocity(STATE.sm.pos, VecScale(p_delta, -75 * dt))
        AutoSM_AddVelocity(STATE.sm.rot, QuatEuler(unpack(VecScale(r_delta, 750 * dt))))

        local p_vel_rel = AutoSwizzle(TransformToLocalVec(cam, playerVel), 'yx') -- Removes the z axis and swaps the x and y
		local modded = VecCompensation(baseTransform.rot, AutoVecMulti(VecScale(p_vel_rel, 3 * dt), Vec(-1, -1, 1)))
		AutoSM_AddVelocity(STATE.sm.rot, QuatEuler(modded[1], modded[2], modded[3]))

        
		QueryRejectBody(GetToolBody())
		local hit = QueryRaycast(GetPlayerTransform(false).pos, Vec(0, -1, 0), 0.1)
        if hit then
            local waveT = GetTime() * 11
            local p_speed = math.min(VecLength(playerVel), 7.5) / 7.5 -- Player Velocity Length scaled from 0 to 1, with 1 being the default movement speed
            local bob_vel = Vec(0, math.max(0, math.sin(waveT) * p_speed * 20 * dt) + math.min(0, math.sin(waveT) * p_speed * 5 * dt))
            local bob_rot = VecCompensation(baseTransform.rot, Vec(math.cos(waveT) * p_speed * 4 * dt))
            AutoSM_AddVelocity(STATE.sm.pos, bob_vel)
            AutoSM_AddVelocity(STATE.sm.rot, QuatEuler(unpack(bob_rot)))
        end

        AutoSM_Update(STATE.sm.pos, baseTransform.pos)
        AutoSM_Update(STATE.sm.rot, baseTransform.rot)

        local qx, qy, qz = GetQuatEuler(AutoSM_Get(STATE.sm.rot))
        qx = math.min(math.max(-SM_ROT_CLAMP_ANGLE, qx), SM_ROT_CLAMP_ANGLE)
        qy = math.min(math.max(-SM_ROT_CLAMP_ANGLE, qy), SM_ROT_CLAMP_ANGLE)
        qz = math.min(math.max(-SM_ROT_CLAMP_ANGLE, qz), SM_ROT_CLAMP_ANGLE)
        AutoSM_Set(STATE.sm.rot, QuatEuler(qx, qy, qz), true, true)

        local toolTransform = Transform(AutoSM_Get(STATE.sm.pos), AutoSM_Get(STATE.sm.rot))
        local lerped = AutoTransformLerp(STATE.lastToolTransform, toolTransform, 0.1)

        STATE.lastToolTransform = TransformCopy(toolTransform)

        LnLSetTransformation(TOOL, "body", lerped)

        -- Cuff transforms

        if STATE.pose.state ~= "HEAT_WARMUP" and STATE.pose.state ~= "HEAT" then
            STATE.cuffRotations = {
                QuatRotateQuat(STATE.cuffRotations[1], QuatEuler(0, 0, -145 * dt * math.max(1, ballcuffDtCoefficient))),
                QuatRotateQuat(STATE.cuffRotations[2], QuatEuler(225 * dt * math.max(1, ballcuffDtCoefficient), 0, 0)),
                QuatRotateQuat(STATE.cuffRotations[3], QuatEuler(0, -300 * dt * math.max(1, ballcuffDtCoefficient), 0))
            }
        else
            STATE.cuffRotations = {
                QuatSlerp(STATE.savedCuffRotations[1], CUFFS_KEYFRAME[1], math.min(1, (POSE_TRANSITION_TIME - STATE.pose.transitionTime) / (POSE_TRANSITION_TIME / 2))),
                QuatSlerp(STATE.savedCuffRotations[2], CUFFS_KEYFRAME[2], math.min(1, (POSE_TRANSITION_TIME - STATE.pose.transitionTime) / (POSE_TRANSITION_TIME / 2))),
                QuatSlerp(STATE.savedCuffRotations[3], CUFFS_KEYFRAME[3], math.min(1, (POSE_TRANSITION_TIME - STATE.pose.transitionTime) / (POSE_TRANSITION_TIME / 2)))
            }
        end

        LnLSetTransformation(TOOL, "body.cuffhoriz", Transform(Vec(), STATE.cuffRotations[1]))
        LnLSetTransformation(TOOL, "body.cuffhoriz.cuffvert", Transform(Vec(), STATE.cuffRotations[2]))
        LnLSetTransformation(TOOL, "body.cuffhoriz.cuffvert.cuffinner", Transform(Vec(), STATE.cuffRotations[3]))
    
        LnLApplyRig(TOOL)
    else
        STATE.lastToolTransform = TransformToParentTransform(camera, baseTransform)

        if not STATE.setAimDot then
            SetBool("hud.aimdot", true)
            STATE.setAimDot = true
        end

        if STATE.swapToolCooldown < SWAP_TOOL_COOLDOWN then
            STATE.swapToolCooldown = SWAP_TOOL_COOLDOWN
        end
    end

    -- Draw debug crosses
    for i = #STATE.debugCrosses, 1, -1 do
        local cross = STATE.debugCrosses[i]
        DebugCross(cross.pos, 1, 1, 1, math.min(1,cross.t))
        cross.t = cross.t - dt
        if cross.t <= 0 then
            table.remove(STATE.debugCrosses, i)
        end
    end

    -- Update muzzle flash
    if STATE.shootFlash.id ~= -1 then
        SetLightIntensity(STATE.shootFlash.id, 50 * STATE.shootFlash.timeLeft / FLASH_LIGHT_MAX_TIME)
        STATE.shootFlash.timeLeft = math.max(0, STATE.shootFlash.timeLeft - dt)
        if STATE.shootFlash.timeLeft == 0 then
            Delete(STATE.shootFlash.id)
            STATE.shootFlash.id = -1
        end
    end

    if STATE.deathTimer > 0 then
        STATE.deathTimer = math.max(0, STATE.deathTimer - dt)
        if STATE.deathTimer > 5 then
            PlayLoop(LOOP_NUKED, camera.pos, math.min(0.7, STATE.deathTimer - 5))
        end
        PlayLoop(LOOP_GEIGER, camera.pos, math.min(0.7, STATE.deathTimer))
    end

    -- Update glowing slag
    updateSlag(dt)

    --DebugWatch("num coroutines", #STATE.coroutines)
end

function fireWeapon()
    local orig = GetPlayerCameraTransform()
    local barrelEnd = LnLGetBoneWorldTransform(TOOL, "body.barrelend");

    local co = coroutine.create(shootCoroutine)
    table.insert(STATE.coroutines, co)
    local dirVec = TransformToParentVec(orig, Vec(0, 0, -1))
    coroutine.resume(co, orig.pos, dirVec, HOLE_RADIUS_INITIAL + HOLE_RADIUS_PER_SECOND * STATE.timeHeld)

    co = coroutine.create(lavaDripCoroutine)
    table.insert(STATE.coroutines, co)
    coroutine.resume(co, orig.pos, dirVec, HOLE_RADIUS_INITIAL + HOLE_RADIUS_PER_SECOND * STATE.timeHeld, RANGE)

    SetPlayerVelocity(VecAdd(GetPlayerVelocity(), VecScale(dirVec, KNOCKBACK_COEFFICIENT * STATE.timeHeld)))

    STATE.shootFlash.id = Spawn(FLASH_LIGHT_PREFAB, TransformToParentTransform(barrelEnd, Transform(Vec(0, 0, -0.4), Quat())), true)[1]
    STATE.shootFlash.timeLeft = FLASH_LIGHT_MAX_TIME

    AutoSM_AddVelocity(STATE.sm.pos, Vec(randBetween(-3, 3), 1, 7))
    AutoSM_AddVelocity(STATE.sm.rot, QuatEuler(5, 0, 0))

    STATE.lastTimeHeld = STATE.timeHeld
    STATE.timeHeld = 0
    STATE.displayWarning = 0

    PlaySound(SOUND_SHOOT, barrelEnd.pos, 1)

    STATE.whooshTimer = 0
    STATE.cooldown = COOLDOWN
end

function updateSlag(dt)
    local camera = GetPlayerCameraTransform()
    local toRemove = {}
    local toAdd = {}
    local num = 0
    for id, time in pairs(STATE.slag) do
        num = num + 1

        local newTime

        if DELETE_COLD then
            newTime = time - dt
        else
            newTime = math.max(0, time - dt)
        end

        if newTime < -DEBRIS_CULL_DISAPPEAR_TIME then
            local dot = VecDot(VecSub(GetShapeWorldTransform(id).pos, camera.pos), TransformToParentVec(camera, Vec(0, 0, -1)))
            if dot < 0 or newTime < -DEBRIS_FORCED_DISAPPEAR_TIME then
                Delete(id)
                table.insert(toRemove, id)
            else
                STATE.slag[id] = newTime
            end
        else 
            if (newTime <= 0 and not HasTag(id, "slagCold")) or not IsHandleValid(id) then
                debrisPalette = CreateShape(GetShapeBody(id), GetShapeLocalTransform(id), "MOD/vox/cold_debris_palette.vox")
                CopyShapePalette(debrisPalette, id)
                Delete(debrisPalette)
                if DELETE_COLD then
                    SetTag(id, "slagCold")
                else
                    RemoveTag(id, "unbreakable")
                    table.insert(toRemove, id)
                    if DO_MERGE then
                        id = MergeShape(id)
                    end
                    SplitShape(id)
                end
            else
                if newTime < SLAG_COOL_TIME / 5 then
                    local warmPalette
                    if HasTag(id, "slagGlow") then
                        warmPalette = CreateShape(GetShapeBody(id), GetShapeLocalTransform(id), "MOD/vox/warm_debris_palette.vox")
                        CopyShapePalette(warmPalette, id)
                        Delete(warmPalette)
                        RemoveTag(id, "slagGlow")
                    else
                        warmPalette = id
                    end
                    SetShapeEmissiveScale(warmPalette, newTime / (SLAG_COOL_TIME / 5))
                else
                    SetShapeEmissiveScale(id, newTime / SLAG_COOL_TIME)
                end
            end
            STATE.slag[id] = newTime
        end
    end
    for i = 1, #toRemove do
        STATE.slag[toRemove[i]] = nil
    end
    for k, v in pairs(toAdd) do
        STATE.slag[k] = v
    end

    --DebugWatch("num slag", num)
end

function updateLightning(dt)
    local orig = LnLGetBoneWorldTransform(TOOL, "body.ball").pos
    particlePlasmaCentre()
    SpawnParticle(orig, Vec(), 3 * dt)
    if STATE.plasmaGlowT > 0 then
        return
    end
    for i = 1, #STATE.lightning do
        local goal = VecAdd(orig, VecScale(QuatRotateVec(STATE.lightning[i].rot, Vec(0, 0, -1)), 0.12))
        drawLightning(orig, goal)
        local ax, ay, az = GetQuatEuler(STATE.lightning[i].av)
        ax = ax * dt;
        ay = ay * dt;
        az = az * dt;
        STATE.lightning[i].rot = QuatRotateQuat(STATE.lightning[i].rot, QuatEuler(ax, ay, az))
    end
end

function update(dt)
    if STATE.pose.state == "HEAT" then
        local orig = LnLGetBoneWorldTransform(TOOL, "body.barrelend")
        for _ = 1, 5 do
            local dir = QuatRotateVec(AutoRandomQuat(HEAT_ANGLE), TransformToParentVec(orig, Vec(0, 0, -1)))
            QueryRejectBody(GetToolBody())
            local hit, dist, normal, shape = QueryRaycast(orig.pos, dir, HEAT_RANGE)
            if hit then
                local pos = VecAdd(orig.pos, VecScale(dir, dist))
                local mat, r, g, b = GetShapeMaterialAtPosition(shape, pos)
                if mat == "foliage" or mat == "plastic" or mat == "" then -- "" is snow
                    MakeHole(pos, 0.2, 0, 0, true)
                    if mat == "plastic" then
                        particleMoltenPlastic()
                        ParticleColor(r, g, b)
                        for _ = 1, 5 do
                            SpawnParticle(VecAdd(pos, randVec(-0.2, 0.2)), Vec(), randBetween(2, 4))
                        end
                    end
                else
                    if HasTag(shape, "explosive") and math.random() < 0.005 then
                        MakeHole(pos, 0.1, 0.1, 0.1)
                    end
                end
                particleSteam()
                SpawnParticle(pos, Vec(0, 0.5, 0), randBetween(3, 5))
                SpawnFire(pos)
            end
        end
    end

    local toRemove = {}
    for body, time in pairs(STATE.frozenBodies) do
        local newTime = math.max(0, time - dt)
        if newTime == 0 then
            table.insert(toRemove, body)
        else
            STATE.frozenBodies[body] = newTime
        end
    end
    for i = 1, #toRemove do
        SetBodyDynamic(toRemove[i], true)
        STATE.frozenBodies[toRemove[i]] = nil
    end

    -- Run coroutines
    for i = #STATE.coroutines, 1, -1 do
        if coroutine.status(STATE.coroutines[i]) == "dead" then
            table.remove(STATE.coroutines, i)
        else
            coroutine.resume(STATE.coroutines[i])
        end
    end

    if STATE.deathTimer > 4 then
        particleDebrisLava()
        
        local num
        if FPS_GLOW then
            num = 250
        else
            num = 750
        end
        for _ = 1, num do
            QueryRejectBody(GetToolBody())
            if IsHandleValid(STATE.droppedBody) then
                QueryRejectBody(STATE.droppedBody)
            end
            for id, time in pairs(STATE.slag) do
                QueryRejectShape(id)
            end
            local randDir = VecNormalize(randVec(-1, 1))
            local hit, dist, normal, shape = QueryRaycast(STATE.deathPos, randDir, 10)
            if hit then
                local pos = VecAdd(STATE.deathPos, VecScale(randDir, dist))
                if hit then
                    doGlowingShapeVoxel(shape, pos, normal)
                end
                if math.random() < 0.1 then
                    SpawnParticle(VecAdd(pos, randVec(-0.2, 0.2)), Vec(), randBetween(2, 4))
                end
            end
        end
    end

    local normalised = STATE.timeHeld / CHARGE_MAX_TIME
    if normalised > 0.7 then
        if math.random() then
            local toolPos = TransformToParentTransform(GetPlayerCameraTransform(), baseTransform).pos
            particleSpark()
            local randDir = VecNormalize(randVec(-1, 1))
            local hit, point = GetBodyClosestPoint(GetToolBody(), VecAdd(toolPos, VecScale(randDir, 10)))
            if hit then
                SpawnParticle(VecAdd(point, VecScale(randDir, 0.1)), randDir, randBetween(1, 2))
            end
        end
    end
end

function draw(dt)
    if LnLSelected(TOOL) and GetPlayerGrabShape() == 0 and GetPlayerVehicle() == 0 then
        if STATE.displayWarning > 0 then
            local whole, frac = math.modf(GetTime())
            if math.floor(frac * 10) % 2 == 0 then
                UiPush()
                    UiTranslate(20, 1060)
                    UiAlign("left bottom")
                    if STATE.displayWarning == 1 then
                        UiImage("MOD/ui/warning.png")
                    else
                        UiImage("MOD/ui/danger.png")
                        PlaySound(SOUND_WARNING, GetPlayerCameraTransform().pos, 0.3)
                        --UiSound("warning-beep.ogg", 0.3)
                    end
                UiPop()
            end
        end
        UiPush()
            UiTranslate(UiCenter(), UiMiddle())
            UiAlign("left bottom")
            UiScale(0.3)
            for i = 1, 4 do
                if i % 2 == 0 then
                    UiRotate(STATE.timeHeld * 2)
                else
                    UiRotate(-STATE.timeHeld * 2)
                end

                UiTranslate(STATE.timeHeld * 10, -STATE.timeHeld * 10)
                UiImage("MOD/ui/crosshair.png")
                UiTranslate(-STATE.timeHeld * 10, STATE.timeHeld * 10)

                if i % 2 == 0 then
                    UiRotate(-STATE.timeHeld * 2)
                else
                    UiRotate(STATE.timeHeld * 2)
                end
                UiRotate(90)
            end
        UiPop()
    end
end

function shootCoroutine(orig, dir, radius)
    local pos = orig
    local dist = 0
    local steps = 0

    while dist < RANGE do
        local normalisedDist = ((RANGE - dist) / RANGE)
        local coefficient = math.pow(-normalisedDist + 1, 1 / 3)
        --local coefficient = normalisedDist
        local adjustedRadius = radius * coefficient

        -- Tracers
        --table.insert(STATE.debugCrosses, {pos=pos;t=5})


        QueryRejectBody(GetToolBody())
        local hit, testDist, _, shape = QueryRaycast(pos, dir, math.max(0.1, DELTA_PER_SECOND * GetTimeStep()))
        if hit then
            mat = GetShapeMaterialAtPosition(shape, VecAdd(pos, VecScale(dir, testDist)))

            destructiblerobots(shape, (1 - normalisedDist) * 500 * adjustedRadius, 1)
            if mat == "rock" or mat == "heavymetal" then
                for _ = 1, 30 do
                    local num
                    if FPS_GLOW then
                        num = 500
                    else
                        num = 1000
                    end
                    for _ = 1, num do
                        local randPos = VecAdd(orig, VecScale(dir, math.random() * dist))
                        local randDir = VecNormalize(randVec(-1, 1))
                        QueryRejectBody(GetToolBody())
                        if IsHandleValid(STATE.droppedBody) then
                            QueryRejectBody(STATE.droppedBody)
                        end
                        for id, time in pairs(STATE.slag) do
                            QueryRejectShape(id)
                        end
                        local randDist = math.random() * adjustedRadius * 0.75
                        local glowRadius
                        if FPS_GLOW then
                            glowRadius = (adjustedRadius * 0.75) - randDist
                        else
                            glowRadius = (adjustedRadius * 0.75)
                        end
                        local hit, point, normal, shape = QueryClosestPoint(VecAdd(randPos, VecScale(randDir, randDist)), glowRadius)
                        if hit then
                            doGlowingShapeVoxel(shape, point, normal)
                        end
                    end
                    coroutine.yield()
                end
                return
            end
        end

        local num = MakeHole(pos, adjustedRadius * 0.75, adjustedRadius, adjustedRadius * 0.75, true)

        for _ = 1, math.sqrt(num) do
            particleDebrisLava()
            SpawnParticle(
                VecAdd(pos, randVec(-adjustedRadius / 2, adjustedRadius / 2)), 
                VecScale(QuatRotateVec(AutoRandomQuat(20), dir), randBetween(10, 20)),
                randBetween(2, 4)
            )
        end
        if dist > 2 then
            if FPS_GLOW then
                Paint(pos, adjustedRadius * 1.4, "explosion", 0.1)
            else
                Paint(pos, adjustedRadius * 1.75, "explosion", 0.1)
            end
        end
        pos = VecAdd(pos, VecScale(dir, DELTA_PER_SECOND * GetTimeStep()))
        dist = dist + DELTA_PER_SECOND * GetTimeStep()
        steps = steps + 1
        if steps == MAX_SHOOT_STEPS_PER_FRAME then
            local num
            if FPS_GLOW then
                num = 500
            else
                num = 1000
            end
            for _ = 1, num do
                --local curvedDist = (-math.pow(math.random() - 1, 2) + 1) * dist
                local randPos = VecAdd(orig, VecScale(dir, math.max(2, math.random() * dist)))
                local randDir = VecNormalize(randVec(-1, 1))
                QueryRejectBody(GetToolBody())
                if IsHandleValid(STATE.droppedBody) then
                    QueryRejectBody(STATE.droppedBody)
                end
                for id, time in pairs(STATE.slag) do
                    QueryRejectShape(id)
                end
                --[[
                local hit, glowDist, normal, shape = QueryRaycast(randPos, randDir, adjustedRadius * 1.1)
                if hit then
                    doGlowingShapeVoxel(shape, VecAdd(randPos, VecScale(randDir, glowDist)), normal)
                end
                --]]
                ---[[
                local randDist = math.random() * adjustedRadius * 0.75
                local glowRadius
                if FPS_GLOW then
                    glowRadius = (adjustedRadius * 0.75) - randDist
                else
                    glowRadius = (adjustedRadius * 0.75)
                end
                local hit, point, normal, shape = QueryClosestPoint(VecAdd(randPos, VecScale(randDir, randDist)), glowRadius)
                if hit then
                    doGlowingShapeVoxel(shape, point, normal)
                end
                --]]
            end

            coroutine.yield()
            steps = 0
        end
    end
end

function destructiblerobots(shape, damage, hitcounter)
	if HasTag(shape, "shapeHealth") then
		if tonumber(GetTagValue(shape,"shapeHealth")) - damage < 0 and not HasTag(shape, "body") then 
            RemoveTag(shape,"unbreakable")
		end
	end

    SetFloat('level.destructible-bot.hitCounter',hitcounter)
    SetInt('level.destructible-bot.hitShape',shape)
    SetString('level.destructible-bot.weapon',"glarebeam")
    SetFloat('level.destructible-bot.damage',damage)
end

function lavaDripCoroutine(orig, dir, radius, dist)
    local timeStart = GetTime()

    while GetTime() - timeStart < 10 do
        local dripAttempts = 0
        while dripAttempts < INITIAL_DRIPS_PER_UPDATE * ((DRIP_TIME - (GetTime() - timeStart)) / DRIP_TIME) do
            local randPos = VecAdd(VecLerp(orig, VecAdd(orig, VecScale(dir, dist)), math.random()), randVec(-0.3, 0.3))
            local hit, point, normal, shape = QueryClosestPoint(randPos, radius)
            if hit and GetShapeBody(shape) ~= GetToolBody() and HasTag(shape, "slagGlow") then
                particleLavaDrip()
                SpawnParticle(VecLerp(randPos, point, 0.9), Vec(), randBetween(2, 4))
                if math.random() < 0.02 then
                    SpawnFire(point)
                end
            end
            dripAttempts = dripAttempts + 1
        end
        coroutine.yield()
    end
end

-- Thanks to micro for the Spray mod
function doGlowingShapeVoxel(shape, pos, normal)
    local mat = GetShapeMaterialAtPosition(shape, pos)
    if mat == "foliage" or ((mat == "wood" or mat == "plastic") and math.random() > 0.02) then
        SpawnFire(pos)
        return
    end
    if mat == "rock" or mat == "heavymetal" or mat == "unphysical" or mat == "none" then
        return
    end
    local sx, sy, sz, scale = GetShapeSize(shape)
    if math.abs(scale - 0.1) > 0.0001 or HasTag(shape, "invisible") then
        return
    end
    if HasTag(shape, "slagGlow") or HasTag(shape, "slagWarm") or HasTag(shape, "slagCold") or HasTag(shape, "unbreakable") then
        return
    end

    local body = GetShapeBody(shape)

    if IsBodyDynamic(body) then
        SetBodyDynamic(body, false)
        STATE.frozenBodies[body] = BODY_FREEZE_TIME
    end

    local glowShape = nil
    if HasTag(shape, "slagHasGlow") then
        glowShape = GetTagValue(shape, "slagHasGlow")
        if not IsHandleValid(glowShape) or STATE.slag[glowShape] == nil or STATE.slag[glowShape] < SLAG_COOL_TIME * 0.9 then
            glowShape = nil
            RemoveTag(shape, "slagHasGlow")
        end
        local gx, gy, gz = GetShapeSize(glowShape)
        if gx ~= sx or gy ~= sy or gz ~= sz then
            glowShape = nil
            RemoveTag(shape, "slagHasGlow")
        end
    end

    if glowShape == nil then
        glowShape = CreateShape(GetShapeBody(shape), GetShapeLocalTransform(shape), "MOD/vox/glowing_debris_palette.vox")
        SetTag(glowShape, "slagGlow")
        SetTag(glowShape, "unbreakable")
        SetTag(shape, "slagHasGlow", tostring(glowShape))
        ResizeShape(glowShape, 0, 0, 0, sx - 1, sy - 1, sz - 1)
        SetShapeEmissiveScale(glowShape, 1)
    end

    STATE.slag[tostring(glowShape)] = SLAG_COOL_TIME

    pos = TransformToLocalPoint(GetShapeWorldTransform(glowShape), VecAdd(pos, VecScale(normal, -0.05)))
    pos[1] = math.floor(pos[1] / VOX_SIZE)
    pos[2] = math.floor(pos[2] / VOX_SIZE)
    pos[3] = math.floor(pos[3] / VOX_SIZE)

    SetBrush('sphere', 1, 0)
    DrawShapeLine(shape, pos[1], pos[2], pos[3], pos[1], pos[2], pos[3])

    SetBrush('sphere', 1, math.random(4))
    DrawShapeLine(glowShape, pos[1], pos[2], pos[3], pos[1], pos[2], pos[3])
end

function drawLightning(origin, goal)

    local direction = VecNormalize(VecSub(goal, origin))
    local dist = math.abs(VecLength(VecSub(goal, origin)))
    local numParts = dist / LIGHTNING_PART_LENGTH

    local start = origin
    local startActual = origin
    for _ = 1, numParts do
        local vec = VecScale(direction, LIGHTNING_PART_LENGTH)
        vec = QuatRotateVec(AutoRandomQuat(30), vec)
        point = VecAdd(startActual, vec)
        DrawLine(start, point, 0.45, 0.48, 0.9)
        start = point
        startActual = VecAdd(startActual, VecScale(direction, LIGHTNING_PART_LENGTH))
    end

    particlePlasma()
    SpawnParticle(goal, Vec(), 3 * GetTimeStep())
end

function particleDebrisLava()
    ParticleReset()
    ParticleTile(6)
    ParticleRadius(0.05)
    ParticleType("plain")
    ParticleCollide(0, 1, "linear")
    ParticleGravity(-10)
    ParticleSticky(0.9)
    ParticleAlpha(1)
    ParticleEmissive(3, 0)

    local randFactor = math.random() * 0.5 + 0.5
    ParticleColor(1 * randFactor, 0.315 * randFactor, 0)
end

function particleStickyLava()
    ParticleReset()
    ParticleTile(6)
    ParticleRadius(0.06)
    ParticleType("plain")
    ParticleCollide(1)
    ParticleGravity(-10)
    ParticleSticky(2)
    ParticleAlpha(1)
    ParticleEmissive(3, 0)

    local randFactor = math.random() * 0.5 + 0.5
    ParticleColor(1 * randFactor, 0.315 * randFactor, 0)
end

function particleLavaDrip()
    ParticleReset()
    ParticleTile(4)
    ParticleRadius(0.02)
    ParticleType("plain")
    ParticleCollide(1)
    ParticleGravity(-10)
    ParticleSticky(0.9)
    ParticleAlpha(1)
    ParticleEmissive(3, 0)
    ParticleStretch(5)

    local randFactor = math.random() * 0.5 + 0.5
    ParticleColor(1 * randFactor, 0.315 * randFactor, 0)
end

function particlePlasma()

    ParticleReset()
    ParticleTile(3)
    ParticleRadius(0.01)
    ParticleType("plain")
    ParticleCollide(0)
    ParticleGravity(-10)
    ParticleSticky(0.9)
    ParticleAlpha(0.5)
    ParticleEmissive(3)
    ParticleStretch(5)

    ParticleColor(0.7, 0.14, 0.48)
end

function particlePlasmaCentre()
    ParticleReset()
    ParticleTile(3)
    ParticleRadius(STATE.plasmaParticleSize)
    ParticleType("plain")
    ParticleCollide(0)
    ParticleGravity(-10)
    ParticleSticky(0.9)
    ParticleAlpha(STATE.plasmaGlowIntensity + 0.2)
    ParticleEmissive(3)
    ParticleStretch(5)

    local lerped = VecLerp(PLASMA_GLOW_IDLE, PLASMA_GLOW_ACTIVE, STATE.plasmaGlowT)
    ParticleColor(lerped[1], lerped[2], lerped[3])
end

function particleSteam()
    ParticleReset()
    ParticleTile(3)
    ParticleRadius(0.5)
    ParticleType("plain")
    ParticleCollide(1)
    ParticleGravity(0.5)
    ParticleAlpha(0.05)
    ParticleColor(0.8, 0.8, 0.8)
end

function particleCooling()
    ParticleReset()
    ParticleTile(3)
    ParticleRadius(randBetween(0.05, 0.1))
    ParticleType("plain")
    ParticleCollide(1)
    ParticleGravity(-5)
    ParticleAlpha(0.2, 0)
    ParticleColor(1, 1, 1)
end

function particleSpark()
    ParticleReset()
    ParticleTile(3)
    ParticleRadius(0.005)
    ParticleType("plain")
    ParticleCollide(1)
    ParticleGravity(-10)
    ParticleSticky(0)
    ParticleAlpha(1)
    ParticleEmissive(3)
    ParticleStretch(3)
    ParticleColor(1, 0.4, 0)
end

function particleMoltenPlastic()
    ParticleReset()
    ParticleTile(4)
    ParticleRadius(0.02)
    ParticleType("plain")
    ParticleCollide(1)
    ParticleGravity(-10)
    ParticleSticky(0.9)
    ParticleAlpha(1)
    ParticleEmissive(0)
    ParticleStretch(5)
end

function randBetween(min, max)
	return math.random() * (max - min) + min
end

function randVec(min, max)
    return Vec(randBetween(min, max), randBetween(min, max), randBetween(min, max))
end

function VecCompensation(tool_rot, V)
    return QuatRotateVec(AutoQuatInverse(tool_rot), V)
end
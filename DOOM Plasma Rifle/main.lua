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
    RegisterTool("doomplasmagun", "DOOM Plasma Rifle", "MOD/vox/rifle.vox", 3)
    SetBool("game.tool.doomplasmagun.enabled", true)
    SetInt("game.tool.doomplasmagun.ammo", 350)

    PI = 3.1415926

    TOOL_BASE_TRANSFORM = Transform(Vec(0.8, -1.5, -1.2), QuatEuler(3, 4, 0))
    TOOL_END_OFFSET = Vec(-0.16, 0.91, -1.4)
    TOOL_EXHAUST_OFFSET = Vec(-0.38, 0.8, -1.05)

    COOLDOWN = 0.08

    PROJECTILE_SPEED = 35
    PROJECTILE_SPREAD = 0.8

    PROJECTILE_RADIUS = 0.2
    PROJECTILE_MAX_LIFE = 10

    PROJECTILE_FADE_LIFE = 1
    PROJECTILE_FADE_INTENSITY = 0.3

    PROJECTILE_IMPULSE_SCALE = 10
    PROJECTILE_HOLE_RADIUS_WEAK = 1
    PROJECTILE_HOLE_RADIUS_MEDIUM = 0.8
    PROJECTILE_HOLE_RADIUS_STRONG = 0.4

    PROJECTILE_PAINT_RADIUS = 1.2

    PROJECTILE_NUM_PLASMA = 6
    PROJECTILE_NUM_SMOKE = 5

    ANIM_MAX_TIME = 0.05

    PROJ_R = 0.5
    PROJ_G = 1
    PROJ_B = 1

    BLAST_RADIUS = 7
    BLAST_POWER = 50
    BLAST_BREAK_RADIUS_WEAK = 2.5
    BLAST_BREAK_RADIUS_MEDIUM = 2
    BLAST_BREAK_RADIUS_STRONG = 1
    BLAST_RING_TIME = 0.5
    BLAST_RING_PARTICLE_RADIUS = 0.5
    BLAST_RING_FIRE_COOLDOWN = 1

    registryInit()

    glob = {}
    glob.projectiles = {}
    glob.cooldown = 0
    glob.state = "READY"
    glob.animFrac = 0
    glob.charge = 0
    glob.blastRingTimer = 0
    glob.blastFireCooldown = 0
    glob.infiniteAmmo = GetBool("savegame.mod.infiniteammo")

    if glob.infiniteAmmo then
        SetString("game.tool.doomplasmagun.ammo.display", "")
    end

    handleSoundFiring = LoadSound("MOD/sounds/firing0.ogg")
    handleSoundBlastReady = LoadSound("MOD/sounds/blastready.ogg")
    handleSoundBlast = LoadSound("MOD/sounds/blast0.ogg")

    setAimDot = false
end

function tick(dt)
    if GetString("game.player.tool") == "doomplasmagun" and GetPlayerVehicle() == 0 then
        SetBool("hud.aimdot", false)
        setAimDot = false
        local toolFinalTrans = TOOL_BASE_TRANSFORM

        local toolTrans = GetBodyTransform(GetToolBody())
        local toolEndPos = TransformToParentPoint(toolTrans, TOOL_END_OFFSET)

        local playerTrans = GetPlayerCameraTransform()
        local forward = TransformToParentVec(playerTrans, Vec(0, 0, -1))

        if InputDown("usetool") 
        and glob.state == "READY" 
        and GetBool("game.player.canusetool") 
        and GetPlayerGrabShape() == 0 
        and glob.blastFireCooldown == 0
        and GetInt("game.tool.doomplasmagun.ammo") > 0
        then
            QueryRejectBody(GetToolBody())
            local hit, dist = QueryRaycast(playerTrans.pos, forward, 100)
            if not hit then
                dist = 100
            end
            local aimPoint = VecAdd(playerTrans.pos, VecScale(forward, dist))
            local orientation = QuatRotateQuat(QuatLookAt(toolEndPos, aimPoint), randQuat(-PROJECTILE_SPREAD, PROJECTILE_SPREAD))
            local direction = QuatRotateVec(orientation, Vec(0, 0, -1))
            fireWeapon(toolEndPos, direction)
            glob.state = "COOLDOWN"
            glob.cooldown = COOLDOWN
            if glob.charge == 29 then
                PlaySound(handleSoundBlastReady, playerTrans.pos, 3)
            end
            glob.charge = math.min(30, glob.charge + 1)
            PlaySound(handleSoundFiring, playerTrans.pos, 3)
            particleMuzzleFlash()
            SpawnParticle(toolEndPos, Vec(0, 0, 0), 0.02)
        end

        if InputDown("usetool")
        and GetBool("game.player.canusetool")
        and GetPlayerGrabShape() == 0
        and glob.blastFireCooldown == 0 
        and GetInt("game.tool.doomplasmagun.ammo") > 0 then
            glob.animFrac = math.min(ANIM_MAX_TIME, glob.animFrac + 1.5 * dt)
        end
        glob.animFrac = math.max(0, glob.animFrac - 1.2 * dt)

        if InputPressed("grab") and glob.charge == 30 then
            glob.charge = 0
            for i = 1, 16 do
                local offset = Vec(2 * math.sin(math.rad(360 * (i / 16))), 0, 2 * math.cos(math.rad(360 * (i / 16))))
                MakeHole(VecAdd(playerTrans.pos, offset), BLAST_BREAK_RADIUS_WEAK, BLAST_BREAK_RADIUS_MEDIUM, BLAST_BREAK_RADIUS_STRONG)
            end
            
            QueryRejectBody(GetToolBody())
            local bodies = QueryAabbBodies(
                VecSub(playerTrans.pos, VecScale(Vec(1, 0.5, 1), BLAST_RADIUS)),
                VecAdd(playerTrans.pos, VecScale(Vec(1, 0.2, 1), BLAST_RADIUS))
            )
            for i = 1, #bodies do
                local body = bodies[i]
                if IsBodyDynamic(body) then
                    local hit, point = GetBodyClosestPoint(body, playerTrans.pos)
                    local delta = VecSub(point, playerTrans.pos)
                    delta[2] = 0
                    local direction = VecNormalize(delta)
                    ApplyBodyImpulse(body, point, VecScale(direction, math.min(100000, BLAST_POWER * GetBodyMass(body))))
                end
            end
            PlaySound(handleSoundBlast, playerTrans.pos, 3)
            glob.blastRingTimer = BLAST_RING_TIME
            glob.blastFireCooldown = BLAST_RING_FIRE_COOLDOWN
        end

        if glob.state == "COOLDOWN" then
            if glob.cooldown == 0 then
                glob.state = "READY"
            end
        end

        if glob.charge == 30 then
            if randBetween(0, 2) < 1 then
                particleExhaustCube()
                SpawnParticle(
                    TransformToParentPoint(GetBodyTransform(GetToolBody()), VecAdd(TOOL_EXHAUST_OFFSET, Vec(0, 0, randBetween(-0.2, 0.2)))),
                    TransformToParentVec(
                        GetBodyTransform(GetToolBody()),
                        VecAdd(Vec(-0.5, -0.5, 0), Vec(randBetween(-0.1, 0.1), randBetween(-0.1, 0.1), 0))
                    ),
                    randBetween(0.25, 0.35)
                )
            end
            if randBetween(0, 4) < 1 then
                particleExhaustSmoke()
                SpawnParticle(
                    TransformToParentPoint(GetBodyTransform(GetToolBody()), VecAdd(TOOL_EXHAUST_OFFSET, Vec(0, 0, randBetween(-0.2, 0.2)))),
                    TransformToParentVec(
                        GetBodyTransform(GetToolBody()),
                        VecAdd(Vec(-0.3, -0.3, 0), Vec(randBetween(-0.1, 0.1), randBetween(-0.1, 0.1), 0))
                    ),
                    randBetween(0.3, 0.5)
                )
            end
        end

        local animFraction = glob.animFrac / ANIM_MAX_TIME
        local offsetPos = VecLerp(Vec(0, 0, 0), Vec(0, 0, 0.1), animFraction)
        local offsetRot = QuatSlerp(QuatEuler(0, 0, 0), QuatAxisAngle(Vec(1, 0, 0), 2), animFraction)
        toolFinalTrans = TransformToParentTransform(toolFinalTrans, Transform(offsetPos, offsetRot))

        SetToolTransform(toolFinalTrans, 1)

        glob.cooldown = math.max(0, glob.cooldown - dt)
    else
		if not setAimDot then
        	SetBool("hud.aimdot", true)
			setAimDot = true
		end
        glob.state = "READY"
        glob.cooldown = 0
        glob.animFrac = 0
    end

    if glob.blastRingTimer > 0 then
        glob.blastRingTimer = math.max(0, glob.blastRingTimer - dt)
        local fraction = (BLAST_RING_TIME - glob.blastRingTimer) / BLAST_RING_TIME
        local circumference = 2 * PI * (BLAST_RADIUS * fraction)
        local numParticles = (circumference / BLAST_RING_PARTICLE_RADIUS)
        local playerTrans = GetPlayerCameraTransform()
        particleBlastRing(1 - fraction)
        for i = 1, numParticles do
            local offset = Vec(
                fraction * BLAST_RADIUS * math.sin(math.rad(360 * (i / numParticles))),
                -1.3,
                fraction * BLAST_RADIUS * math.cos(math.rad(360 * (i / numParticles)))
            )
            SpawnParticle(VecAdd(playerTrans.pos, offset), Vec(0, 0, 0), 3 * dt)
        end
    end

    if glob.blastFireCooldown > 0 then
        glob.blastFireCooldown = math.max(0, glob.blastFireCooldown - dt)
    end

    tickFadingProjectiles(dt) -- smooth lighting fade, needs to be in tick
end

function tickFadingProjectiles(dt)
    for i = #glob.projectiles, 1, -1 do
        local projectile = glob.projectiles[i]
        if projectile.mode == "FADE" then
            if IsHandleValid(projectile.body) then
                projectile.pos = TransformToParentPoint(GetBodyTransform(projectile.body), projectile.localPos)
            end
            PointLight(
                projectile.pos,
                PROJ_R,
                PROJ_G, 
                PROJ_B, 
                PROJECTILE_FADE_INTENSITY * (PROJECTILE_FADE_LIFE - projectile.life) / PROJECTILE_FADE_LIFE
            )
            projectile.life = projectile.life + dt
            if projectile.life > PROJECTILE_FADE_LIFE then
                table.remove(glob.projectiles, i)
            end
        end
    end
end

function update(dt)
    tickFlyingProjectiles(dt) -- needs to be in update to avoid ghosting
end

function tickFlyingProjectiles(dt)
    for i = #glob.projectiles, 1, -1 do
        local projectile = glob.projectiles[i]

        if projectile.mode == "FLY" then
            projectile.pos = VecAdd(projectile.pos, VecScale(projectile.dir, PROJECTILE_SPEED * dt))

            particleProjectile()
            SpawnParticle(projectile.pos, Vec(0, 0, 0), 2.8 * dt)
            particleProjectileCentre()
            SpawnParticle(VecAdd(projectile.pos, randVec(-PROJECTILE_RADIUS / 5, PROJECTILE_RADIUS / 5)), Vec(0, 0, 0), 2.8 * dt)

            QueryRejectBody(GetToolBody())
            local hit, point, normal, shape = QueryClosestPoint(projectile.pos, PROJECTILE_RADIUS)
            if hit then
                projectile.life = 0
                projectile.mode = "FADE"
                projectile.body = GetShapeBody(shape)
                projectile.localPos = TransformToLocalPoint(GetBodyTransform(projectile.body), point)

                if IsBodyDynamic(projectile.body) then
                    ApplyBodyImpulse(point.body, point, VecScale(
                        projectile.dir, 
                        math.min(10000, PROJECTILE_IMPULSE_SCALE * (GetBodyMass(projectile.body) / 10))
                    ))
                end

                Paint(projectile.pos, PROJECTILE_PAINT_RADIUS, "explosion")

                destructibleRobots(shape, 10, 1)

                MakeHole(
                    point, 
                    PROJECTILE_HOLE_RADIUS_WEAK, 
                    PROJECTILE_HOLE_RADIUS_MEDIUM, 
                    PROJECTILE_HOLE_RADIUS_STRONG
                )

                local bodies = QueryAabbBodies(
                    VecSub(point, VecScale(Vec(1, 1, 1), PROJECTILE_HOLE_RADIUS_WEAK)),
                    VecAdd(point, VecScale(Vec(1, 1, 1), PROJECTILE_HOLE_RADIUS_WEAK))
                )
                for j = 1, #bodies do
                    local body = bodies[j]
                    if IsBodyDynamic(body) and body ~= projectile.body then
                        local hitBody, pointBody = GetBodyClosestPoint(body, point)
                        local delta = VecSub(pointBody, point)
                        local direction = VecNormalize(delta)
                        local dist = math.abs(VecLength(delta))
                        ApplyBodyImpulse(body, pointBody, VecScale(
                            VecAdd(projectile.dir, direction),
                            math.min(10000, PROJECTILE_IMPULSE_SCALE * (GetBodyMass(body) / 10))
                        ))
                    end
                end
                
                particlePlasma()
                for i = 1, PROJECTILE_NUM_PLASMA do
                    SpawnParticle(
                        VecAdd(point, randVec(-PROJECTILE_HOLE_RADIUS_STRONG, PROJECTILE_HOLE_RADIUS_STRONG)),
                        VecAdd(normal, randVec(-1, 1)),
                        0.3
                    )
                end
                particleSmoke()
                for i = 1, PROJECTILE_NUM_SMOKE do
                    SpawnParticle(
                        VecAdd(point, randVec(-PROJECTILE_HOLE_RADIUS_STRONG, PROJECTILE_HOLE_RADIUS_STRONG)),
                        VecAdd(normal, randVec(-1, 1)),
                        0.3
                    )
                end
            else
                projectile.life = projectile.life + dt
                if projectile.life > PROJECTILE_MAX_LIFE then
                    table.remove(glob.projectiles, i)
                end
            end
        end
    end
end

function fireWeapon(origin, direction)
    local projectile = {}
    projectile.pos = origin
    projectile.dir = direction
    projectile.life = 0
    projectile.mode = "FLY"
    table.insert(glob.projectiles, projectile)
    if not glob.infiniteAmmo then
        SetInt("game.tool.doomplasmagun.ammo", GetInt("game.tool.doomplasmagun.ammo") - 1)
    end
end

function draw(dt)
    if GetString("game.player.tool") == "doomplasmagun" and GetPlayerVehicle() == 0 then
        UiTranslate(UiCenter(), UiMiddle())
        UiAlign("center middle")
        if glob.blastFireCooldown > 0 then
            UiImage("MOD/ui/crosshaircool" .. tostring(math.ceil(glob.blastFireCooldown / BLAST_RING_FIRE_COOLDOWN * 10)) .. ".png")
        else
            UiImage("MOD/ui/crosshair" .. tostring(math.floor(glob.charge / 3)) .. ".png")
        end
    end
end

function particleMuzzleFlash()
    ParticleReset()
    ParticleTile(3)
    ParticleRadius(0.5)
    ParticleType("smoke")
    ParticleCollide(0)
    ParticleGravity(0)
    ParticleAlpha(1)
    ParticleEmissive(0.5)
    ParticleColor(PROJ_R, PROJ_G, PROJ_B)
end

function particleBlastRing(alpha)
    ParticleReset()
    ParticleTile(3)
    ParticleRadius(BLAST_RING_PARTICLE_RADIUS)
    ParticleType("plain")
    ParticleCollide(0)
    ParticleGravity(0)
    ParticleAlpha(alpha)
    ParticleEmissive(0.4)
    ParticleColor(PROJ_R, PROJ_G, PROJ_B)
end

function particleExhaustCube()
    ParticleReset()
    ParticleTile(6)
    ParticleRadius(0.005)
    ParticleType("plain")
    ParticleCollide(0)
    ParticleGravity(0)
    ParticleAlpha(1)
    ParticleEmissive(1)
    ParticleColor(PROJ_R, PROJ_G, PROJ_B)
end

function particleExhaustSmoke()
    ParticleReset()
    ParticleTile(5)
    ParticleRadius(0.05)
    ParticleType("plain")
    ParticleCollide(0)
    ParticleGravity(0)
    ParticleAlpha(0.4)
    ParticleEmissive(0.2)
    ParticleColor(PROJ_R, PROJ_G, PROJ_B)
end

function particleProjectile()
    ParticleReset()
    ParticleTile(4)
    ParticleRadius(PROJECTILE_RADIUS)
    ParticleType("plain")
    ParticleCollide(0)
    ParticleGravity(0)
    ParticleAlpha(0.4)
    ParticleEmissive(0.5)
    ParticleColor(PROJ_R, PROJ_G, PROJ_B)
end

function particleProjectileCentre()
    ParticleReset()
    ParticleTile(4)
    ParticleRadius(PROJECTILE_RADIUS / 3)
    ParticleType("plain")
    ParticleCollide(0)
    ParticleGravity(0)
    ParticleAlpha(0.6)
    ParticleEmissive(0.5)
    ParticleColor(1, 1, 1)
end

function particlePlasma()
    ParticleReset()
    ParticleTile(6)
    ParticleRadius(0.05)
    ParticleType("plain")
    ParticleCollide(1)
    ParticleGravity(0)
    ParticleAlpha(1, 0)
    ParticleEmissive(1)
    ParticleColor(PROJ_R, PROJ_G, PROJ_B)
end

function particleSmoke()
    ParticleReset()
    ParticleTile(5)
    ParticleRadius(0.1)
    ParticleType("plain")
    ParticleCollide(0)
    ParticleGravity(0)
    ParticleAlpha(1, 0)
    ParticleEmissive(1)
    ParticleColor(PROJ_R, PROJ_G, PROJ_B)
end

function particleDebug()
    ParticleReset()
    ParticleRadius(0.05)
    ParticleColor(1, 0, 0)
    ParticleEmissive(1)
    ParticleTile(6)
    ParticleAlpha(1)
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
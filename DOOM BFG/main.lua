#include "registry.lua"

function init()
    RegisterTool("doombfg", "DOOM BFG 9000", "MOD/vox/BFG.vox", 6)
    SetBool("game.tool.doombfg.enabled", true)
    SetInt("game.tool.doombfg.ammo", 3)

    TOOL_BASE_OFFSET = Vec(0.5, -2.5, -1.4)
    TOOL_END_OFFSET = Vec(-0.35, 2.05, -0.1)
    DRIVE_LOCAL_TRANS = Transform(Vec(-0.4, 2.15, 1.0), Quat(-0.70711, 0, 0, 0.70711))
    TOOL_COOLDOWN = 1
    PROJECTILE_SPEED = 15
    PROJ_R = 0.29
    PROJ_G = 1
    PROJ_B = 0
    PROJECTILE_MAX_LIFE = 6
    PROJECTILE_RADIUS = 0.5
    LIGHTNING_SPAWN_ATTEMPTS = 15
    LAVA_PER_LIGHTNING = 100
    MAX_NUM_LIGHTNING = 30
    LIGHTNING_MAX_DIST = 30
    LIGHTNING_MIN_SPACING = 0.5
    PLAYER_SAFE_DIST = 7
    LIGHTNING_MAX_LIFE = 0.2
    LIGHTNING_HOLE_RADIUS = 4.2
    LIGH_R = 0.7
    LIGH_G = 1
    LIGH_B = 0.5
    LIGHTNING_PART_LENGTH = 2
    LIGHTNING_THROW_RADIUS = 20
    LIGHTNING_THROW_POWER = 500
    LIGHTNING_DELETE_MASS_THRESHOLD = 300
    LIGHTNING_PART_MAX_PARTICLES = 5
    NUM_LAVA_ATTEMPTS = 100

    CHARGE_TIME = 0.75
    RECOIL_TIME = 0.35
    WAIT_TIME = 1

    registryInit()

    glob = {}
    glob.cooldown = 0
    glob.state = "READY"
    glob.driveInitTrans = nil
    glob.driveAnimFrac = 0
    glob.infiniteAmmo = GetBool("savegame.mod.infiniteammo")

    if glob.infiniteAmmo then
        SetString("game.tool.doombfg.ammo.display", "")
    end

    projectiles = {}

    handleSpriteProjectile = LoadSprite("MOD/sprites/projectile.png")
    handleSpriteHalo = LoadSprite("MOD/sprites/halo.png")
    handleSpriteCharge = LoadSprite("MOD/sprites/charge.png")

    handleSoundFiring = LoadSound("MOD/sounds/firing.ogg")

    setAimDot = false
end

function tick(dt)
    if GetString("game.player.tool") == "doombfg"
        and GetPlayerVehicle() == 0
    then
        SetBool("hud.aimdot", false)
        setAimDot = false
        local playerTransform = GetPlayerCameraTransform()
        local toolTrans = GetBodyTransform(GetToolBody())
        local toolSetTrans = Transform(TOOL_BASE_OFFSET, QuatEuler(0, 0, 0))
        local toolEndTrans = Transform(TransformToParentPoint(toolTrans, TOOL_END_OFFSET), toolTrans.rot)

        if InputPressed("usetool") and glob.state == "READY" and GetBool("game.player.canusetool") and GetPlayerGrabShape() == 0 and GetInt("game.tool.doombfg.ammo") > 0 then
            PlaySound(handleSoundFiring, playerTransform.pos, 3.0)
            glob.state = "CHARGING"
            glob.cooldown = CHARGE_TIME
        end

        if glob.state == "CHARGING" then
            glob.cooldown = math.max(0, glob.cooldown - dt)
            if glob.cooldown == 0 then
                local forward = TransformToParentVec(playerTransform, Vec(0, 0, -1))
                local lookPoint = VecAdd(playerTransform.pos, VecScale(forward, 100))
                fireWeapon(toolEndTrans.pos, QuatLookAt(toolEndTrans.pos, lookPoint))
                glob.state = "RECOIL"
                glob.cooldown = RECOIL_TIME
            end
            local fraction = (CHARGE_TIME - glob.cooldown) / CHARGE_TIME
            local transform = TransformToParentTransform(toolEndTrans, Transform(Vec(0, 0, 0), QuatAxisAngle(Vec(0, 0, -1), fraction * 360)))
            DrawSprite(
                handleSpriteCharge,
                transform,
                1.5 - fraction * 1.5, 1.5 - fraction * 1.5,
                1, 1, 1, 1,
                true
            )
            PointLight(toolEndTrans.pos, PROJ_R, PROJ_G, PROJ_B, (1 - fraction) * 3)
        end

        if glob.state == "RECOIL" then
            glob.cooldown = math.max(0, glob.cooldown - dt)
            local fraction = (RECOIL_TIME - glob.cooldown) / RECOIL_TIME
            toolSetTrans = TransformToParentTransform(toolSetTrans, Transform(
                Vec(0, 0.1 * math.sin(math.rad(180 * fraction)), 0.1 * math.sin(math.rad(180 * fraction))),
                QuatAxisAngle(Vec(1, 0, 0), 3 * math.sin(math.rad(180 * fraction)))
            ))
            if glob.cooldown == 0 then
                glob.state = "WAIT"
                glob.cooldown = WAIT_TIME
            end
        end

        if glob.state == "WAIT" then
            glob.cooldown = math.max(0, glob.cooldown - dt)
            if glob.cooldown == 0 then
                glob.state = "READY"
            end
        end

        if glob.state == "RECOIL" or glob.state == "WAIT" then
            particleGunSmoke()
            local pointLocal = VecAdd(TOOL_END_OFFSET, Vec(0, 0.2, 0.8))
            local point = TransformToParentPoint(toolTrans, pointLocal)
            SpawnParticle(VecAdd(point, randVec(-0.02, 0.02)), Vec(0, 0, 0), 0.1)
        end
    
        SetToolTransform(toolSetTrans, 1.0)

        if canGetShapes() then
            animateDrive(dt)
        end

    else
		if not setAimDot then
        	SetBool("hud.aimdot", true)
			setAimDot = true
		end
        glob.state = "WAIT"
    end

    tickProjectiles(dt)

end

function tickProjectiles(dt)
    local toolTrans = GetBodyTransform(GetToolBody())
    local toolEndTrans = Transform(TransformToParentPoint(toolTrans, TOOL_END_OFFSET), toolTrans.rot)
    for i = #projectiles, 1, -1 do
        local projectile = projectiles[i]

        projectile.pos = VecAdd(projectile.pos, VecScale(projectile.dir, PROJECTILE_SPEED * dt))

        if #projectile.lightning < MAX_NUM_LIGHTNING then
            for i = 1, LIGHTNING_SPAWN_ATTEMPTS do
                if createLightning(projectile) then
                    break
                end
            end
        end

        for i = #projectile.lightning, 1, -1 do
            local lightning = projectile.lightning[i]
            drawLightning(projectile.pos, lightning.goal)
            local fraction = lightning.life / LIGHTNING_MAX_LIFE
            local holeSize = LIGHTNING_HOLE_RADIUS * fraction
            local edge = VecScale(VecNormalize(Vec(randBetween(-1, 1), randBetween(-1, 1), randBetween(-1, 1))), LIGHTNING_HOLE_RADIUS * (lightning.life / LIGHTNING_MAX_LIFE))
            local hit, point = QueryClosestPoint(VecAdd(lightning.goal, edge), LIGHTNING_HOLE_RADIUS)
            if hit then
                particleLava()
                local vec = VecScale(Vec(1, 1, 1), holeSize)
                local shapes = QueryAabbShapes(VecSub(point, vec), VecAdd(point, vec))
                for j = 1, NUM_LAVA_ATTEMPTS do
                    local testPoint = VecAdd(point, randVec(-holeSize, holeSize))
                    for k = 1, #shapes do
                        local typ = GetShapeMaterialAtPosition(shapes[k], testPoint)
                        if typ ~= "" and typ ~= "heavymetal" and typ ~= "rock" and typ ~= "none" then
                            SpawnParticle(testPoint, randVec(-0.2, 0.2), randBetween(1, 2))
                        end
                    end
                end
            end
            Paint(lightning.goal, LIGHTNING_HOLE_RADIUS * (lightning.life / LIGHTNING_MAX_LIFE) * 1.1, "explosion")
            PointLight(lightning.goal, PROJ_R, PROJ_G, PROJ_B, 3)
            lightning.life = lightning.life + dt
            lightning.holeTime = lightning.holeTime + dt
            if lightning.holeTime > LIGHTNING_MAX_LIFE / 5 then
                lightning.holeTime = 0
                
                MakeHole(lightning.goal, holeSize, holeSize, holeSize)
            end
            if lightning.life > LIGHTNING_MAX_LIFE then
                throwBodies(lightning.goal)
                PointLight(lightning.goal, PROJ_R, PROJ_G, PROJ_B, 10)
                Explosion(lightning.goal, 0.25)
                table.remove(projectile.lightning, i)
            end
        end
        
        local num = MakeHole(projectile.pos, 0.6, 0.6, 0.6)

        for i = 1, math.sqrt(num) do
            local hit, point = QueryClosestPoint(VecAdd(projectile.pos, randVec(-0.3, 0.3)), 0.6)
            if hit then
                particleLava()
                SpawnParticle(point, Vec(0, 0, 0), randBetween(2, 4))
            end
        end

        DrawSprite(
            handleSpriteProjectile,
            Transform(projectile.pos, GetPlayerCameraTransform().rot), 
            PROJECTILE_RADIUS * 2, PROJECTILE_RADIUS * 2,
            1, 1, 1, 1, true
        )

        DrawSprite(
            handleSpriteHalo,
            Transform(projectile.pos, GetPlayerCameraTransform().rot), 
            PROJECTILE_RADIUS * 2.8, PROJECTILE_RADIUS * 2.8,
            1, 1, 1, 0.1, true
        )

        particleProjectileSpark()
        for i = 1, 4 do
            SpawnParticle(VecAdd(projectile.pos, randVec(-(PROJECTILE_RADIUS / 8), (PROJECTILE_RADIUS / 8))), Vec(0, 0, 0), 0.02)
        end

        PointLight(projectile.pos, PROJ_R, PROJ_G, PROJ_B, randBetween(10, 12))

        particleProjectileCentre()
        SpawnParticle(projectile.pos, Vec(0, 0, 0), 0.02)

        projectile.life = projectile.life + dt
        if projectile.life >= PROJECTILE_MAX_LIFE then
            Explosion(projectile.pos, 5)
            table.remove(projectiles, i)
        else
            local forward = VecAdd(projectile.pos, VecScale(projectile.dir, PROJECTILE_SPEED * dt))
            local hit, point, normal, shape = QueryClosestPoint(forward, PROJECTILE_RADIUS)
            if hit then
                local material = GetShapeMaterialAtPosition(shape, point)
                if material == "heavymetal" or material == "rock" or material == "none" or material == "unphysical" then
                    Explosion(projectile.pos, 5)
                    table.remove(projectiles, i)
                end
            end
        end
    end
end

function createLightning(projectile)
    QueryRejectBody(GetToolBody())
    local direction = VecNormalize(Vec(randBetween(-1, 1), randBetween(-1, 1), randBetween(-1, 1)))
    local hit, dist, normal, shape = QueryRaycast(projectile.pos, direction, LIGHTNING_MAX_DIST)
    if not hit then
        return false
    end

    local point = VecAdd(projectile.pos, VecScale(direction, dist))
    local material = GetShapeMaterialAtPosition(shape, point)
    if material == "heavymetal" or material == "rock" or material == "none" or material == "unphysical" then
        return false
    end

    local tooClose = false
    for i = 1, #projectile.lightning do
        local dist = math.abs(VecLength(VecSub(projectile.lightning[i].goal, point)))
        if dist < LIGHTNING_MIN_SPACING then
            tooClose = true
            break
        end
    end

    local dist = math.abs(VecLength(VecSub(point, GetPlayerTransform(false).pos)))
    if dist < PLAYER_SAFE_DIST then
        tooClose = true
    end

    if not tooClose then
        local lightning = {}
        lightning.goal = point
        lightning.life = 0
        lightning.holeTime = 0
        table.insert(projectile.lightning, lightning)
        return true
    end
    return false
end

function drawLightning(origin, goal)
    particleLightning()

    local direction = VecNormalize(VecSub(goal, origin))
    origin = VecAdd(origin, VecScale(direction, PROJECTILE_RADIUS))
    local dist = math.abs(VecLength(VecSub(goal, origin)))
    local numParts = dist / LIGHTNING_PART_LENGTH

    local start = origin
    local startActual = origin
    for i = 1, numParts do
        local vec = VecScale(direction, LIGHTNING_PART_LENGTH)
        vec = QuatRotateVec(randQuat(-15, 15), vec)
        point = VecAdd(startActual, vec)
        DrawLine(start, point, LIGH_R, LIGH_G, LIGH_B)
        local particleVec = VecScale(VecSub(point, start), 1 / LIGHTNING_PART_MAX_PARTICLES * 0.79)
        for j = 1, LIGHTNING_PART_MAX_PARTICLES + 1 do
            local particleStart = VecAdd(start, VecScale(particleVec, j - 1))
            SpawnParticle(
                particleStart,
                VecScale(particleVec, 1 / GetTimeStep()),
                1.5 * GetTimeStep()
            )
        end
        start = point
        startActual = VecAdd(startActual, VecScale(direction, LIGHTNING_PART_LENGTH))
    end
end

function fireWeapon(origin, orientation)
    glob.cooldown = TOOL_COOLDOWN

    local projectile = {}
    projectile.pos = origin
    projectile.dir = TransformToParentVec(Transform(Vec(0, 0, 0), orientation), Vec(0, 0, -1))
    projectile.life = 0
    projectile.lightning = {}

    table.insert(projectiles, projectile)

    if not glob.infiniteAmmo then
        SetInt("game.tool.doombfg.ammo", GetInt("game.tool.doombfg.ammo") - 1)
    end
end

function animateDrive(dt)
    glob.driveAnimFrac = glob.driveAnimFrac + dt / 2
    if glob.driveAnimFrac > 1 then
        glob.driveAnimFrac = 0
    end
    local shape, shapeGlow = getDriveShapes()
    local unusedTrans = Transform(Vec(0, 0.5, -0.5), QuatEuler(0, 0, 0))
    if glob.state == "CHARGING" then
        local offset = Vec(
            0.05 + 0.070711 * math.sin(math.rad(-1080 * glob.driveAnimFrac - 45)),
            0,
            0.05 + 0.070711 * -math.cos(math.rad(-1080 * glob.driveAnimFrac - 45))
        )
        local rotation = QuatAxisAngle(Vec(0, 1, 0), 1080 * glob.driveAnimFrac)
        SetShapeLocalTransform(shape, TransformToParentTransform(DRIVE_LOCAL_TRANS, unusedTrans))
        SetShapeLocalTransform(shapeGlow, TransformToParentTransform(DRIVE_LOCAL_TRANS, Transform(offset, rotation)))
    else
        local offset = Vec(
            0.05 + 0.070711 * math.sin(math.rad(-360 * glob.driveAnimFrac - 45)),
            0,
            0.05 + 0.070711 * -math.cos(math.rad(-360 * glob.driveAnimFrac - 45))
        )
        local rotation = QuatAxisAngle(Vec(0, 1, 0), 360 * glob.driveAnimFrac)
        SetShapeLocalTransform(shape, TransformToParentTransform(DRIVE_LOCAL_TRANS, Transform(offset, rotation)))
        SetShapeLocalTransform(shapeGlow, TransformToParentTransform(DRIVE_LOCAL_TRANS, unusedTrans))
    end
end

function throwBodies(origin)
    QueryRejectBody(GetToolBody)
    local bodies = QueryAabbBodies(
        VecAdd(origin, Vec(-LIGHTNING_THROW_RADIUS, -LIGHTNING_THROW_RADIUS, -LIGHTNING_THROW_RADIUS)),
        VecAdd(origin, Vec(LIGHTNING_THROW_RADIUS, LIGHTNING_THROW_RADIUS, LIGHTNING_THROW_RADIUS))
    )
    for i = #bodies, 1, -1 do
        if IsBodyDynamic(bodies[i]) then
            body = bodies[i]
            if GetBodyMass(body) < LIGHTNING_DELETE_MASS_THRESHOLD and IsBodyBroken(body) then
                Delete(body)
            else
                local hit, point = GetBodyClosestPoint(bodies[i], hitPos)
                local dist = math.abs(VecLength(VecSub(point, origin)))
                local direction = VecNormalize(VecSub(point, origin))
                if hit then
                    ApplyBodyImpulse(bodies[i], point, VecScale(direction, math.max(0, LIGHTNING_THROW_POWER - dist * 5)))
                end
            end
        end
    end
end

function update(dt)
end

function draw(dt)
    if GetString("game.player.tool") == "doombfg" and GetPlayerVehicle() == 0 and GetPlayerGrabShape() == 0 and GetBool("game.player.canusetool") then
        UiTranslate(UiCenter() - 50, UiMiddle() - 50)
        UiImage("MOD/ui/crosshair.png")
    end
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

function particleProjectileSpark()
    ParticleReset()
    ParticleType("plain")
    ParticleAlpha(0.7)
    ParticleEmissive(5)
    ParticleTile(5)
    ParticleRadius(0.3)
    ParticleCollide(0)
    ParticleColor(PROJ_R, PROJ_G, PROJ_B)
end

function particleProjectileCentre()
    ParticleReset()
    ParticleType("plain")
    ParticleAlpha(1)
    ParticleTile(4)
    ParticleEmissive(5)
    ParticleRadius(0.3)
    ParticleCollide(0)
    ParticleColor(1, 1, 1)
end

function particleGunSmoke()
    ParticleReset()
    ParticleType("smoke")
    ParticleAlpha(0.4)
    ParticleRadius(0.03)
    ParticleTile(3)
    ParticleEmissive(2)
    ParticleCollide(0)
    ParticleColor(PROJ_R, PROJ_G, PROJ_B)
    ParticleGravity(0.5)
end

function particleLightning()
    ParticleReset()
    ParticleTile(4)
    ParticleRadius(0.05)
    ParticleType("plain")
    ParticleCollide(0)
    ParticleGravity(0)
    ParticleRotation(0)
    ParticleSticky(0)
    ParticleAlpha(1)
    ParticleEmissive(5)
    ParticleColor(PROJ_R, PROJ_G, PROJ_B)
    ParticleStretch(2.6)
end

function canGetShapes()
    return #GetBodyShapes(GetToolBody()) > 1
end

function getDriveShapes()
    return GetBodyShapes(GetToolBody())[2], GetBodyShapes(GetToolBody())[3]
end
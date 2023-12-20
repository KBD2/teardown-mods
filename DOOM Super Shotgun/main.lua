#include "registry.lua"

local infiniteAmmo = GetBool("savegame.mod.doombigshotty.infiniteammo")

function init()
    RegisterTool("doombigshotty", "DOOM Super Shotgun", "MOD/vox/SuperShotgun_shortened.vox", 3)
    SetBool("game.tool.doombigshotty.enabled", true)
    SetInt("game.tool.doombigshotty.ammo", 60)

    spreadCoefficientHorizontal = 21
    spreadCoefficientVertical = 7

    firing = false
    triggerPullTime = 0
    recoilTime = 0
    reloadTime = 0

    ejectedShells = false
    shells = {}

    firingSoundHandle = LoadSound("MOD/sounds/firing.ogg")
    zoomInSoundHandle = LoadSound("MOD/sounds/zoomin.ogg")
    zoomOutSoundHandle = LoadSound("MOD/sounds/zoomout.ogg")

    barrelShape = 0
    barrelInitialRot = nil
    barrelOpenedRot = nil

    numBulletsPerBarrel = 8

    manualFov = GetInt("options.gfx.fov")

    registryInit()

    disableRecoil = GetBool("savegame.mod.doombigshotty.disablerecoil")

    if infiniteAmmo then
        SetString("game.tool.doombigshotty.ammo.display", "")
    end

    setAimDot = false

end

function tick(dt)
    SetShapeCollisionFilter(barrelShape, 0, 0)
    if GetString("game.player.tool") == "doombigshotty" and GetPlayerVehicle() == 0 and GetPlayerGrabShape() == 0 and GetBool("game.player.canusetool") then
        SetBool("hud.aimdot", false)
        setAimDot = false
        if barrelShape == 0 then
            findBarrel()
        end

        local playerTransform = GetPlayerCameraTransform()
        local forward = TransformToParentVec(playerTransform, Vec(0, 0, -1))

        local toolTransform = GetBodyTransform(GetToolBody())
        local barrelTransform = GetShapeLocalTransform(barrelShape)

        local toolRenderOffset = Vec(0.2, -1.05, -2.3)

        local toolEndOffsetOne = TransformToParentPoint(playerTransform, Vec(0.1, -0.4, -2.8))
        local toolEndOffsetTwo = TransformToParentPoint(playerTransform, Vec(0.35, -0.4, -2.8))

        local firingDirection = nil
        QueryRejectBody(GetToolBody())
        hit, dist, normal, shape = QueryRaycast(playerTransform.pos, forward, 100)
        if not hit then
            dist = 100
        end
        

        if InputPressed("usetool") and not firing and GetInt("game.tool.doombigshotty.ammo") > 0 then
            PlaySound(firingSoundHandle, GetPlayerTransform().pos, 3.0)
            triggerPullTime = 0.1
            firing = true
        end

        if InputPressed("grab") then
            PlaySound(zoomInSoundHandle)
        end
        if InputReleased("grab") then
            PlaySound(zoomOutSoundHandle)
        end
        local maxFov = GetInt("options.gfx.fov")
        if InputDown("grab") then
            manualFov = math.max(maxFov - 20, manualFov - 120 * dt)
        else
            manualFov = math.min(maxFov, manualFov + 120 * dt)
        end
        if manualFov < maxFov then
            SetCameraFov(manualFov)
        end

        if triggerPullTime > 0 then
            triggerPullTime = triggerPullTime - dt
            -- Actually fire the weapon
            if triggerPullTime <= 0 then
                local firingOrientation = QuatLookAt(toolEndOffsetOne, VecAdd(playerTransform.pos, VecScale(forward, dist)))
                local firingDirection = TransformToParentVec(toolTransform, Vec(0, 0, -1))

                for i = 1, numBulletsPerBarrel do
                    firePellet(toolEndOffsetOne, firingOrientation)
                    firePellet(toolEndOffsetTwo, firingOrientation)
                    Shoot(toolEndOffsetOne, firingDirection, "shotgun", 1, 5)
                    Shoot(toolEndOffsetTwo, firingDirection, "shotgun", 1, 5)
                end
                flashParticle(toolEndOffsetOne)
                flashParticle(toolEndOffsetTwo)
                
                recoilTime = 0.35

                -- Shotgun jumping ;)
                if not disableRecoil then
                    SetPlayerVelocity(VecAdd(GetPlayerVelocity(), VecScale(firingDirection, -7)))
                end

                if not infiniteAmmo then
                    SetInt("game.tool.doombigshotty.ammo", GetInt("game.tool.doombigshotty.ammo") - 2)
                end

            end
            
        end

        local toolRenderRotation = QuatEuler(0, 0, 0)

        if recoilTime > 0 then
            local fraction = 0
            if recoilTime > 0.1 then
                fraction = math.sin(math.rad((0.35 - recoilTime) / 0.25 * 90))
                toolRenderRotation = QuatSlerp(QuatEuler(0, 0, 0), QuatEuler(10, -10, 0), fraction)
                toolRenderOffset = VecAdd(toolRenderOffset, Vec(0.3 * fraction, 0.3 * fraction, 0.2 * fraction))
            else
                fraction = -math.sin(math.rad(180 + (0.1 - recoilTime) / 0.1 * 90))
                toolRenderRotation = QuatSlerp(QuatEuler(10, -10, 0), QuatEuler(0, 0, 0), fraction)
                toolRenderOffset = VecAdd(toolRenderOffset, Vec(0.3 * (1 - fraction), 0.3 * (1 - fraction), 0.2 * (1 - fraction)))
            end
            recoilTime = recoilTime - dt

            if recoilTime <= 0 and GetInt("game.tool.doombigshotty.ammo") > 0 then
                reloadTime = 0.8
            end
        end

        if reloadTime > 0 then
            local fraction = 0
            if reloadTime > 0.6 then
                fraction = (0.8 - reloadTime) / 0.2
                toolRenderRotation = QuatSlerp(QuatEuler(0, 0, 0), QuatAxisAngle(Vec(1, 0, 0.6), 20), fraction)
                toolRenderOffset = VecAdd(toolRenderOffset, VecLerp(Vec(0, 0, 0), Vec(0, 0.5, 0), fraction))
                SetShapeLocalTransform(barrelShape, Transform(barrelTransform.pos, QuatSlerp(barrelInitialRot, barrelOpenedRot, fraction)))
            else
                if reloadTime < 0.2 then
                    fraction = (0.2 - reloadTime) / 0.2
                    toolRenderRotation = QuatSlerp(QuatAxisAngle(Vec(1, 0, 0.6), 20), QuatEuler(0, 0, 0), fraction)
                    toolRenderOffset = VecAdd(toolRenderOffset, VecLerp(Vec(0, 0.5, 0), Vec(0, 0, 0), fraction))
                    SetShapeLocalTransform(barrelShape, Transform(barrelTransform.pos, QuatSlerp(barrelOpenedRot, barrelInitialRot, fraction)))
                else
                    toolRenderRotation = QuatAxisAngle(Vec(1, 0, 0.6), 20)
                    toolRenderOffset = VecAdd(toolRenderOffset, Vec(0, 0.5, 0))
                end
            end
        end
        
        SetToolTransform(Transform(toolRenderOffset, toolRenderRotation))
        
        if triggerPullTime <= 0 and recoilTime <= 0 and reloadTime <= 0 then
            SetShapeLocalTransform(barrelShape, Transform(barrelTransform.pos, barrelInitialRot))
            firing = false
            ejectedShells = false
        end

        if reloadTime > 0 and reloadTime <= 0.6 and not ejectedShells then
            local toolTransform = GetBodyTransform(GetToolBody())
            local ejectPositionOne = TransformToParentPoint(toolTransform, Vec(-0.2, 0.55, 1.2))
            local ejectPositionTwo = TransformToParentPoint(toolTransform, Vec(0.15, 0.55, 1.2))
            local orientation = QuatRotateQuat(toolTransform.rot, QuatEuler(-60, 0, 0))
            ejectedShells = true
            spawnShell(ejectPositionOne, orientation)
            spawnShell(ejectPositionTwo, orientation)
        end

    else
		if not setAimDot then
        	SetBool("hud.aimdot", true)
			setAimDot = true
		end
        firing = false
        triggerPullTime = 0
        recoilTime = 0
        barrelShape = 0
    end
    if reloadTime > 0 then
        reloadTime = reloadTime - dt
    end

    for i = #shells, 1, -1 do
        shells[i].time = shells[i].time + dt
        local shellTransform = GetBodyTransform(shells[i].body)
        shells[i].vel = VecAdd(shells[i].vel, VecScale(Vec(0, -10, 0), dt))
        shellTransform.pos = VecAdd(shellTransform.pos, VecScale(shells[i].vel, dt))
        shellTransform.rot = QuatRotateQuat(shellTransform.rot, QuatAxisAngle(Vec(1, 0, 0), 360 * dt))
        local dAngVel = VecScale(shells[i].angVel, dt)
        shellTransform.rot = QuatRotateQuat(shellTransform.rot, QuatEuler(dAngVel[1], dAngVel[2], dAngVel[3]))
        SetBodyTransform(shells[i].body, shellTransform)
        if shells[i].time >= 3 then
            Delete(shells[i].body)
            table.remove(shells, i)
        end
    end
end


function update(dt)
end


function draw(dt)
    if GetString("game.player.tool") == "doombigshotty" and GetPlayerVehicle() == 0 and GetPlayerGrabShape() == 0 and GetBool("game.player.canusetool") then
        UiTranslate(UiCenter() - 76, UiMiddle() - 48)
        UiImage("MOD/ui/crosshair.png")
    end
end

function spawnShell(origin, orientation)
    local entities = Spawn("MOD/prefabs/Shell.xml", Transform(origin, orientation))
    for i = 1, #entities do
        if GetEntityType(entities[i]) == "body" then
            local body = entities[i]
            local direction = TransformToParentVec(Transform(Vec(0, 0, 0), orientation), Vec(2, 0, 5))
            local shellTimer = {}
            shellTimer.body = body
            shellTimer.time = 0
            shellTimer.vel = VecAdd(GetPlayerVelocity(), direction)
            shellTimer.angVel = randVec(-120, 120)
            table.insert(shells, 1, shellTimer)
        end
    end
end

function randBetween(min, max)
	return math.random() * (max - min) + min
end

function randVec(min, max)
    return Vec(randBetween(min, max), randBetween(min, max), randBetween(min, max))
end

function round(num, decimals)
    local mult = 10^(decimals or 0)
    return math.floor(num * mult + 0.5) / mult
end

function findBarrel()
    local toolShapes = GetBodyShapes(GetToolBody())
    for i=1, #toolShapes do
        local shapePos = GetShapeLocalTransform(toolShapes[i]).pos
        if round(shapePos[1], 2) == -0.25 and round(shapePos[2], 2) == 0.3 and round(shapePos[3], 2) == 1.2 then
            barrelShape = toolShapes[i]
            if barrelInitialRot == nil then
                barrelInitialRot = GetShapeLocalTransform(barrelShape).rot
                barrelOpenedRot = QuatRotateQuat(barrelInitialRot, QuatAxisAngle(Vec(1, 0, 0), 320))
            end
            break
        end
    end
end

function firePellet(origin, forward)
    local bulletRotOffset = QuatRotateQuat(forward, QuatEuler(
        randBetween(-spreadCoefficientVertical, spreadCoefficientVertical),
        randBetween(-spreadCoefficientHorizontal, spreadCoefficientHorizontal),
        0
    ))
    local forwardDirection = TransformToParentVec(Transform(Vec(0, 0, 0), bulletRotOffset), Vec(0, 0, -1))
    QueryRejectBody(GetToolBody())
    local hit, dist, normal, shape = QueryRaycast(origin, forwardDirection, 100)
    if hit then
        local hitPos = VecAdd(origin, VecScale(forwardDirection, dist))
        local scaling = math.max(0.05, 1.5 - (dist / 25))
        local typ, r, g, b, a = GetShapeMaterialAtPosition(shape, hitPos)
        count = MakeHole(hitPos, 0.8 * scaling, 0.6 * scaling, 0.3 * scaling)
        hitSmoke(hitPos)
        for i = 1, math.max(2, math.sqrt(count)) do
            debrisParticle(hitPos, VecScale(forwardDirection, math.max(1, math.min(5, 5 / dist))), r, g, b, a)
        end
        local bodies = QueryAabbBodies(VecAdd(hitPos, Vec(-2, -2, -2)), VecAdd(hitPos, Vec(2, 2, 2)))
        for i = 1, #bodies do
            if IsBodyDynamic(bodies[i]) then
                local hitBody, point, normal, shape = GetBodyClosestPoint(bodies[i], hitPos)
                if hitBody then
                    ApplyBodyImpulse(bodies[i], point, VecScale(forwardDirection, math.max(1, math.min(100, 100 / dist))))
                end
            end
        end
    end
end

function flashParticle(origin)
    ParticleReset()
    ParticleType("plain")
    ParticleTile(3)
    ParticleColor(1, 0.25, 0.12)
    ParticleRadius(0.65)
    ParticleGravity(0)
    ParticleDrag(0)
    ParticleEmissive(10)
    ParticleCollide(0)
    ParticleAlpha(1)
    SpawnParticle(origin, Vec(0, 0, 0), 0.05)
    ParticleTile(8)
    SpawnParticle(origin, Vec(0, 0, 0), 0.05)
    
    PointLight(origin, 1, 0.25, 0.12)
end

function hitSmoke(origin)
    ParticleReset()
    ParticleType("smoke")
    ParticleTile(0)
    ParticleColor(0.4, 0.4, 0.4)
    ParticleRadius(randBetween(0.3, 0.5))
    ParticleDrag(0.1)
    ParticleEmissive(0)
    ParticleCollide(1)
    ParticleGravity(-3)
    ParticleAlpha(0.3, 0)
    for i = 1, 3 do
        SpawnParticle(VecAdd(origin, randVec(-1, 1)), VecScale(randBetween(-1, 1), 0, randBetween(-1, 1)), 1)
    end
end

function debrisParticle(origin, direction, r, g, b, a)
    ParticleReset()
    ParticleType("plain")
    ParticleTile(6)
    ParticleColor(r, g, b)
    ParticleAlpha(1)
    ParticleRadius(0.05, 0)
    ParticleCollide(1)
    ParticleGravity(-10)
    ParticleDrag(0.2)
    SpawnParticle(
        VecAdd(origin, randVec(-0.3, 0.3)),
        VecAdd(direction, randVec(-1, 1)),
        randBetween(1, 4)
    )
end
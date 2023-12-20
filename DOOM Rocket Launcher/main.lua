---@diagnostic disable: lowercase-global

#include "registry.lua"

NUM_SHRAPNEL = 250
SHRAPNEL_HOLE_WEAK = 0.4
SHRAPNEL_HOLE_MED = 0.3
SHRAPNEL_HOLE_STRONG = 0.2

function init()
	RegisterTool("doomrocket", "DOOM Rocket Launcher", "MOD/vox/Launcher.vox", 4)
	SetBool("game.tool.doomrocket.enabled", true)
	SetInt("game.tool.doomrocket.ammo", 35)

	---@type { pos: table, aliveTime: number, toExplode: boolean, rot: table, body: body_handle }[]
	rockets = {}

	firingAnimation = 0
	firingCooldown = 0

	exploding = false

	firingSoundHandle = LoadSound("MOD/sounds/firing.ogg")

	breechCover1InitialPos = nil
	breechCover2InitialPos = nil

	setAimDot = false

	infiniteAmmo = GetBool("savegame.mod.infiniteammo")

	if infiniteAmmo then
        SetString("game.tool.doomrocket.ammo.display", "")
    end
end

function tick(dt)
	if exploding then
		if #rockets == 0 then
			exploding = false
		else
			local rocket = rockets[#rockets]
			Explosion(rocket.pos, 4)
			ParticleReset()
			ParticleType("plain")
			ParticleTile(6)
			ParticleGravity(-20)
			ParticleSticky(0.5)
			ParticleCollide(1)
			ParticleEmissive(0)
			for i = 1, NUM_SHRAPNEL do
				local randDir = VecNormalize(Vec(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5))
				local hit, dist, normal, shape = QueryRaycast(rocket.pos, randDir, 20)
				if hit then
					local point = VecAdd(rocket.pos, VecScale(randDir, dist))
					local type, r, g, b, a = GetShapeMaterialAtPosition(shape, point)
					ParticleColor(r, g, b)
					ParticleAlpha(a)
					local n = MakeHole(point,
						randBetween(SHRAPNEL_HOLE_WEAK - 0.1, SHRAPNEL_HOLE_WEAK + 0.1),
						randBetween(SHRAPNEL_HOLE_MED - 0.1, SHRAPNEL_HOLE_MED + 0.1),
						randBetween(SHRAPNEL_HOLE_STRONG - 0.1, SHRAPNEL_HOLE_STRONG + 0.1)
					)
					for j = 1, math.sqrt(n) do
						ParticleRadius(randBetween(0.005, 0.04))
						local vel = VecAdd(VecScale(normal, 4), Vec(randBetween(-4, 4), randBetween(-4, 4), randBetween(-4, 4)))
						SpawnParticle(point, vel, randBetween(0.5, 2))
					end
				end
			end
			Delete(rocket.body)
			rockets[#rockets] = nil
		end
	end
	if GetString("game.player.tool") == "doomrocket" and GetPlayerVehicle() == 0 and GetPlayerGrabShape() == 0 and GetBool("game.player.canusetool") and GetInt("game.tool.doomrocket.ammo") > 0 then
        SetBool("hud.aimdot", false)
		setAimDot = false
		if InputPressed("usetool") and firingCooldown <= 0 then
			local playerTransform = GetPlayerCameraTransform()
			local forwards = TransformToParentVec(playerTransform, Vec(0, 0, -1))
			local launcherEndOffset = TransformToParentVec(playerTransform, Vec(0.75, 0.2, -3.5))
			local spawnPosition = VecAdd(TransformToParentPoint(playerTransform, Vec(0, -0.5, 0)), launcherEndOffset)

			-- This bit makes the rocket face whatever the player's aiming at, instead of just forwards.
			hit, dist, normal, shape = QueryRaycast(playerTransform.pos, forwards, 500)
			if not hit then
				dist = 90
			end
			local toLookAt = VecAdd(playerTransform.pos, VecScale(forwards, dist))
			local rot = QuatLookAt(spawnPosition, toLookAt)
			--

			local entities = Spawn("MOD/prefabs/Rocket.xml", Transform(spawnPosition, rot));

			local rocket = {}
			rocket.pos = spawnPosition
			rocket.aliveTime = 0
			rocket.toExplode = false
			rocket.rot = rot
			for i = 1, #entities do
				if GetEntityType(entities[i]) == "body" then
					rocket.body = entities[i]
					break
				end
			end
			table.insert(rockets, rocket)

			firingAnimation = 0.6
			firingCooldown = 1.2

			PlaySound(firingSoundHandle)
			if not infiniteAmmo then
				SetInt("game.tool.doomrocket.ammo", GetInt("game.tool.doomrocket.ammo") - 1)
			end

		end
		if InputPressed("grab") then
			exploding = true
		end


		local offset = Vec(0, 0, 0)
		if firingAnimation > 0 then
			local breechCover1, breechCover2 = getMovingShapes()
			local breechCover1Transform = GetShapeLocalTransform(breechCover1)
			local breechCover2Transform = GetShapeLocalTransform(breechCover2)
			if firingAnimation > 0.5 then
				local fraction = 1 - ((firingAnimation - 0.5) / 0.1)
				offset = VecLerp(Vec(0, 0, 0), Vec(0, 0, 0.8), 1 + math.sin(math.rad(180 + (firingAnimation - 0.5) / 0.1 * 90)))
				SetShapeLocalTransform(breechCover1, Transform(
					VecAdd(breechCover1InitialPos, Vec(0.001, 0, -0.2 * fraction)),
					breechCover1Transform.rot
				))
				SetShapeLocalTransform(breechCover2, Transform(
					VecAdd(breechCover2InitialPos, Vec(0.001, 0, 0.2 * fraction)),
					breechCover2Transform.rot
				))
			else
				local fraction = math.sin(math.rad(firingAnimation / 0.5 * 90))
				offset = VecLerp(Vec(0, 0, 0), Vec(0, 0, 0.8), math.sin(math.rad(firingAnimation / 0.5 * 90)))
				SetShapeLocalTransform(breechCover1, Transform(
					VecAdd(breechCover1InitialPos, Vec(0.001, 0, -0.2 * fraction)),
					breechCover1Transform.rot
				))
				SetShapeLocalTransform(breechCover2, Transform(
					VecAdd(breechCover2InitialPos, Vec(0.001, 0, 0.2 * fraction)),
					breechCover2Transform.rot
				))
			end
			firingAnimation = firingAnimation - dt
			if firingAnimation <= 0 then
				SetShapeLocalTransform(breechCover1, Transform(breechCover1InitialPos, breechCover1Transform.rot))
				SetShapeLocalTransform(breechCover2, Transform(breechCover2InitialPos, breechCover2Transform.rot))
			end
		end

		SetToolTransform(Transform(offset, QuatAxisAngle(Vec(0, 1, 0), 2)), 1.0)
	else
		if not setAimDot then
        	SetBool("hud.aimdot", true)
			setAimDot = true
		end
		firingAnimation = 0
	end

	for i = #rockets, 1, -1 do
		local rocket = rockets[i]
		PointLight(VecSub(rocket.pos, TransformToParentVec(Transform(rocket.pos, rocket.rot), Vec(0, 0, -0.2))), 1, 0.25, 0.12, 1)
	end
	if firingCooldown > 0 then
		firingCooldown = firingCooldown - dt
	end
end


function update(dt)
	for i = #rockets, 1, -1 do
		local rocket = rockets[i]
		rocket.aliveTime = rocket.aliveTime + dt
		local deltaPosition = VecScale(TransformToParentVec(Transform(rocket.pos, rocket.rot), Vec(0, 0, -30)), 1 * dt)
		rocket.pos = VecAdd(rocket.pos, deltaPosition);

		SetBodyTransform(rocket.body, Transform(rocket.pos, rocket.rot))

		QueryRejectBody(GetToolBody())
		QueryRejectBody(rocket.body)
		hit, point, normal, shape = QueryClosestPoint(rocket.pos, 0.3)
		if hit or rocket.aliveTime > 10 then
			Explosion(rocket.pos, 1.4)
			Delete(rocket.body)
			table.remove(rockets, i)
		else
			createParticles(rocket)
		end
	end
end

function draw(dt)
	if #rockets > 0 then
		UiPush()
			UiAlign("center middle")
			UiTranslate(UiCenter(), UiMiddle() + 75)
			UiFont("bold.ttf", 15)	
			UiColor(1, 1, 0)
			UiText("RMB: DETONATE")
		UiPop()
	end
	if GetString("game.player.tool") == "doomrocket" and GetPlayerVehicle() == 0 and GetPlayerGrabShape() == 0 and GetBool("game.player.canusetool") then
		UiTranslate(UiCenter() - 56, UiMiddle() - 55)
		UiImage("MOD/ui/crosshair.png")
	end
end

function randBetween(min, max)
	return math.random() * (max - min) + min
end

function getMovingShapes()
	local body = GetToolBody()
	local breechCover1 = GetBodyShapes(body)[2]
	local breechCover2 = GetBodyShapes(body)[3]
	if breechCover1 > 0 and breechCover1InitialPos == nil then
		breechCover1InitialPos = GetShapeLocalTransform(breechCover1).pos
		breechCover2InitialPos = GetShapeLocalTransform(breechCover2).pos
	end
	return breechCover1, breechCover2
end

function createParticles(rocket)
	local spawnPoint = TransformToParentPoint(Transform(rocket.pos, rocket.rot), Vec(0.05, 0.05, -0.1))
	ParticleReset()
	ParticleType("plain")
	ParticleTile(3)
	ParticleColor(1, randBetween(0.1, 0.3), randBetween(0.05, 0.15))
	ParticleRadius(0.3)
	ParticleAlpha(0.7, 0.0)
	ParticleGravity(0)
	ParticleDrag(0)
	ParticleEmissive(10, 0, "easeout")
	ParticleCollide(0, 1, "constant", 0.1)
	SpawnParticle(spawnPoint, Vec(0, 0, 0), 0.1)
	ParticleEmissive(0)
	ParticleRadius(0.3, 0.5)
	ParticleColor(0.4, 0.4, 0.4)
	SpawnParticle(spawnPoint, Vec(randBetween(-0.2, 0.2), randBetween(-0.2, 0.2), randBetween(-0.2, 0.2)), 1.0)
end
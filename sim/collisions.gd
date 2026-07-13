class_name Collisions
extends RefCounted
## Train-vs-train collision resolution. Trains occupy per-edge intervals (see
## Consist.occupied_intervals); overlapping intervals on a shared edge mean the
## trains have hit each other.
##
## On impact both trains stop, the faster one is pushed back so they sit bumper
## to bumper, and every car takes damage proportional to the closing speed —
## but cars never die (health floors at Car.MIN_HEALTH). Damage applies only on
## first contact (a touching pair must separate before it can be damaged again),
## and gentle bumps under DAMAGE_MIN_SPEED are free.

const DAMAGE_MIN_SPEED := 1.0    # m/s, bumps softer than this do no damage
const DAMAGE_PER_MS := 3.0       # health lost per m/s of closing speed
const SEPARATION := 0.05         # meters of daylight restored after impact

static func resolve(world: World) -> void:
	var ivs := []
	for c in world.consists:
		ivs.append(c.occupied_intervals())
	var touching_now := {}
	for i in range(world.consists.size()):
		for j in range(i + 1, world.consists.size()):
			var overlap := TrainBuilder.overlap_len(ivs[i], ivs[j])
			if overlap <= 0.001:
				continue
			var a := world.consists[i]
			var b := world.consists[j]
			var key := _pair_key(a, b)
			touching_now[key] = true
			var impact := absf(a.velocity) + absf(b.velocity)
			if not world.colliding_pairs.has(key) and impact >= DAMAGE_MIN_SPEED:
				var dmg := impact * DAMAGE_PER_MS
				for car in a.cars:
					car.apply_damage(dmg)
				for car in b.cars:
					car.apply_damage(dmg)
			# Push the faster train back along its own path to undo the overlap.
			var pushed := a if absf(a.velocity) >= absf(b.velocity) else b
			pushed.distance -= overlap + SEPARATION
			# The crash stops both trains dead; the player restarts them with Run.
			a.velocity = 0.0
			b.velocity = 0.0
			a.target_speed = 0.0
			b.target_speed = 0.0
	world.colliding_pairs = touching_now

static func _pair_key(a: Consist, b: Consist) -> String:
	var ia := a.get_instance_id()
	var ib := b.get_instance_id()
	return "%d:%d" % [mini(ia, ib), maxi(ia, ib)]

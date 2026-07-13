extends Node
## Autoloaded singleton. Owns the live simulation World and runs the fixed-timestep
## tick loop. This is the ONLY place the simulation is advanced; the 2D editor and
## (later) the 3D view read from GameState.world and never mutate game rules directly.

const TICK_HZ := 60.0

var world: World

var _accum := 0.0

func _ready() -> void:
	world = World.new()

func _physics_process(delta: float) -> void:
	# Accumulate real time and advance the sim in fixed discrete steps so behavior
	# is independent of frame rate (deterministic-ready for possible future MP).
	_accum += delta
	var step := 1.0 / TICK_HZ
	# Clamp to avoid a spiral of death after a long stall.
	var max_steps := 8
	while _accum >= step and max_steps > 0:
		world.tick(step)
		_accum -= step
		max_steps -= 1

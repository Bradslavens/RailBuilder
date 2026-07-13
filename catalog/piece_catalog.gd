class_name PieceCatalog
extends RefCounted
## The palette of track pieces, mimicking a physical rail set: straights and
## partial-circle curves (left/right at several angles). Data-driven so the UI can
## render a grid and new pieces are just new entries.
##
## A piece def is a Dictionary:
##   {id, label, type:"straight", len}                       -> StraightEdge
##   {id, label, type:"arc", radius, deg}  (deg>0 = left)    -> ArcEdge

const RADIUS := 6.0

## Base pieces: a straight plus circle arcs. Left/right direction is chosen at
## placement time by flipping (mirroring) the piece, so one curve serves both ways.
const PIECES := [
	{"id": "straight", "label": "Straight", "type": "straight", "len": 6.0},
	{"id": "curve30", "label": "30°", "type": "arc", "radius": RADIUS, "deg": 30.0},
	{"id": "curve45", "label": "45°", "type": "arc", "radius": RADIUS, "deg": 45.0},
	{"id": "curve90", "label": "90°", "type": "arc", "radius": RADIUS, "deg": 90.0},
]

## Instantiate the concrete TrackEdge for a piece def at a placement pose.
static func make_def(def: Dictionary, origin: Transform2D) -> TrackEdge:
	if def.get("type", "straight") == "arc":
		return ArcEdge.new(origin, def.get("radius", RADIUS), deg_to_rad(def.get("deg", 90.0)))
	return StraightEdge.new(origin, def.get("len", 4.0))

## Sampled local-space points for drawing a small preview of the piece.
static func preview_points(def: Dictionary, steps: int) -> PackedVector2Array:
	var e := make_def(def, Transform2D.IDENTITY)
	var pts := PackedVector2Array()
	var n := maxi(2, steps)
	for i in range(n + 1):
		pts.append(e.pose_at(e.length() * float(i) / float(n)).origin)
	return pts

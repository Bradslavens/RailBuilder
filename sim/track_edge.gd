class_name TrackEdge
extends RefCounted
## Base class for a single piece of track.
##
## An edge is a parametric curve on the 2D top-down plane (meters). Everything the
## rest of the game needs — train motion, mesh generation, snapping — is built on
## three primitives: length(), pose_at(s), and the two endpoint poses.
##
## A "pose" is a Transform2D whose origin is the position (meters) and whose
## rotation is the heading (radians, +x = 0, CCW positive). The basis is unit-scaled.

var id: int = -1

## Total arc length of the piece, in meters.
func length() -> float:
	return 0.0

## Pose at arc-length s in [0, length()].
func pose_at(_s: float) -> Transform2D:
	return Transform2D.IDENTITY

## Outgoing pose at the "start" endpoint (s = 0).
func start_pose() -> Transform2D:
	return pose_at(0.0)

## Outgoing pose at the "end" endpoint (s = length()).
func end_pose() -> Transform2D:
	return pose_at(length())

## Serialize to a plain Dictionary (see Serializer for the inverse).
func to_dict() -> Dictionary:
	return {}

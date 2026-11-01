extends RefCounted

## Town block layout in world metres (shared by the builder, the actor controllers and
## Tools/probe_town.gd). Rect2 = (x, z, width, depth) on the ground plane.
##
## The iso camera looks from +X/+Z toward -X/-Z (yaw 45, pitch 40), so every facade faces
## +Z (north row) or +X (west column) and low things (park, market, plaza) sit in front.
##
##        north row (facades at z = -6, facing +Z)
##   corner | CAFE | SHELTER | ALLEY | garden lot
##   -------+------------------------------------  north sidewalk z[-6,-4]
##   APART- |  main road z[-4,0] (crosswalk at x 0.2..2)
##   MENT   +------------------------------------  south sidewalk z[0,2]
##   (x -10 | cross | east | PARK         | PLAZA (market, bus stop)
##   facing | road  | walk |              |
##   +X)    |       |      |              |
##   PET SHOP

const GROUND := Rect2(-17.0, -13.0, 32.0, 25.0)

## Surfaces. Sidewalks / plaza / park / alley sit at y = 0 (actor feet), roads below.
const ROAD_Y: float = -0.1
const GROUND_Y: float = 0.0

const ROAD_MAIN := Rect2(-8.0, -4.0, 23.0, 4.0)
const ROAD_CROSS := Rect2(-8.0, 0.0, 4.0, 12.0)

const WALK_NORTH := Rect2(-10.0, -6.0, 25.0, 2.0)
const WALK_WEST := Rect2(-10.0, -4.0, 2.0, 16.0)
const WALK_SOUTH := Rect2(-4.0, 0.0, 19.0, 2.0)
const WALK_EAST := Rect2(-4.0, 2.0, 2.0, 10.0)

const CROSSWALK_MAIN := Rect2(0.2, -4.0, 1.8, 4.0)
const CROSSWALK_CROSS := Rect2(-8.0, 3.0, 4.0, 1.8)

const PLAZA := Rect2(8.0, 2.0, 7.0, 10.0)
const PARK := Rect2(-2.0, 2.0, 10.0, 10.0)

## Building footprints.
const CORNER_HOUSE := Rect2(-16.5, -12.5, 6.5, 6.5)
const CAFE := Rect2(-9.6, -12.0, 7.6, 6.0)
const SHELTER := Rect2(-1.6, -12.0, 7.2, 6.0)
const ALLEY := Rect2(5.6, -11.6, 4.9, 5.6)
const GARDEN_LOT := Rect2(10.5, -12.0, 4.5, 6.0)
const APARTMENT := Rect2(-16.0, -5.6, 6.0, 8.4)
const PET_SHOP := Rect2(-15.5, 3.4, 5.5, 6.4)

## Where alley strays may roam (inside the alley, clear of the bins and the dumpster).
const STRAY_AREA := Rect2(6.1, -10.8, 3.9, 4.5)

## Walkable rects for townsfolk (sidewalks, crosswalks, plaza, park path).
const PARK_PATH := Rect2(2.2, 2.0, 1.4, 7.4)

static func walk_rects() -> Array[Rect2]:
	return [WALK_NORTH, WALK_WEST, WALK_SOUTH, WALK_EAST, CROSSWALK_MAIN, CROSSWALK_CROSS, PLAZA, PARK_PATH]

static func is_walkable(p: Vector3, margin: float = 0.0) -> bool:
	var q := Vector2(p.x, p.z)
	for r in walk_rects():
		if r.grow(margin).has_point(q):
			return true
	return false

static func is_in_stray_area(p: Vector3, margin: float = 0.05) -> bool:
	return STRAY_AREA.grow(margin).has_point(Vector2(p.x, p.z))

static func on_road(x: float, z: float) -> bool:
	var q := Vector2(x, z)
	return ROAD_MAIN.has_point(q) or ROAD_CROSS.has_point(q)

## Feet height for an actor standing at (x, z).
static func surface_y(x: float, z: float) -> float:
	return ROAD_Y if on_road(x, z) else GROUND_Y

## Townsfolk routes (ping-pong between waypoints). Every segment stays inside walk_rects().
static func walker_routes() -> Array:
	return [
		[Vector3(-9.3, 0, -4.9), Vector3(-5.8, 0, -5.0), Vector3(14.3, 0, -4.9)],
		[Vector3(-9.0, 0, -4.6), Vector3(-9.0, 0, 11.4)],
		[Vector3(-3.0, 0, 11.4), Vector3(-3.0, 0, 1.0), Vector3(14.3, 0, 1.0)],
		[Vector3(-7.6, 0, -5.2), Vector3(1.1, 0, -5.2), Vector3(1.1, 0, 1.0), Vector3(2.9, 0, 1.0), Vector3(2.9, 0, 8.6)],
		[Vector3(9.0, 0, 11.2), Vector3(9.0, 0, 1.2), Vector3(-3.2, 0, 1.2)],
	]

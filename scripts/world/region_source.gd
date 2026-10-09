class_name RegionSource
extends Resource

## Region-level (L0) data that every chunk may read (world bible 03 §1, §3).
##
## A chunk generator must never read another chunk's generated output. Anything that has
## to agree across a chunk border (highways, county roads, rail, rivers, zones, heights)
## comes from here instead: it is loaded once on the main thread (`prepare`) and is then
## READ-ONLY, so `generate()` on worker threads can query it without locks.
##
## This base class is the "no region data" source (everything empty, flat at y 0). See
## RegionMacroSource for the reader of data/region_macro.json.

## Load / index the data. Main thread, once, before any generate() call.
func prepare() -> void:
	pass


## Polyline pieces (in world metres) that touch `area`. Each item:
## {id: String, kind: String ("freeway", "highway", "rail", "river", ...), points: PackedVector2Array}
func features_in(_area: Rect2) -> Array[Dictionary]:
	return []


## Where regional features cross one side of a chunk (ChunkGenerator.SIDE_*), sorted by t.
## Both chunks sharing that edge get identical answers: this is the border-anchor source.
## Each item: {t: float (m along the edge from its low end), id, kind, heading: float (rad)}
func border_crossings(_coord: Vector2i, _side: int) -> Array[Dictionary]:
	return []


## Ground height in Godot metres (y). Flat until the DEM lands.
func height_at(_x: float, _z: float) -> float:
	return 0.0


## Zone tag at a point ("core", "town", "farmland", ...). Empty = unknown.
func zone_at(_x: float, _z: float) -> String:
	return ""

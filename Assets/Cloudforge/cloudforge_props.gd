@tool
class_name CloudforgeProps
extends RefCounted

## The props brought over from Cloudforge, and how big each one stands in this
## game. The source models come in every scale imaginable (a griffon 0.07 units
## tall, a table 3,500 long), so nothing is placed raw: build_props.gd fits each
## model to the size given here and saves it as a ready-to-place scene under
## props/, which the Level Editor's Objects palette then lists.
##
## Sizes are in world units and read as metres: cells are 2 across, walls 3 high
## and the party's eyes are about 1.6 up, so a barrel is waist high and a torch
## stand shoulder high. The caps below keep every prop inside one cell.

const MODELS := "res://Assets/Cloudforge/models/"
const SCENES := "res://Assets/Cloudforge/props/"

const SCALE := 1.0            # one knob to grow or shrink every prop together
const MAX_FOOTPRINT := 1.7    # widest a prop may be, so it stays inside its cell
const MAX_HEIGHT := 2.8       # tallest a prop may be, clear of the 3-unit ceiling
const CEILING := 3.0

## How `size` is measured:
##   height     the model's height
##   footprint  the wider of its width / depth
##   cell       its largest side
##   scale      a plain scale factor on a model already in metres
##   pillar     exactly floor to ceiling (ignores the height cap)
## Optional keys:
##   solid  blocks the party (a box collider); small clutter leaves it off
##   hang   hangs from the ceiling instead of standing on the floor
##   wall   placed against the wall behind it, facing into the room; `mount` is
##          its height up the wall (left out for furniture that stands on the floor)
##   light  [energy, range] of a warm, flickering light
##   flame  where its fire burns, and `flame_size` how big each flame is:
##            "top"    one flame in the middle of the model's top (a bowl, a cup)
##            "wicks"  one on every hair-thin part of the model (candle wicks)
##          The light sits at the flames.
const PROPS := [
	# --- Furniture & statues ---
	{ "id": "cf_table", "label": "Trestle Table", "file": "decor/table/table.gltf", "fit": "height", "size": 0.8, "solid": true },
	{ "id": "cf_bookshelf", "label": "Bookshelf", "file": "decor/bookshelf/bookshelf.gltf", "fit": "height", "size": 2.2,
		"solid": true, "wall": true },   # stands with its back to the wall, books facing the room
	{ "id": "cf_fountain", "label": "Water Fountain", "file": "decor/fountain/fountain.gltf", "fit": "footprint", "size": 1.7, "solid": true },
	{ "id": "cf_griffon", "label": "Griffon Statue", "file": "decor/griffon/griffon.gltf", "fit": "height", "size": 1.8, "solid": true },
	{ "id": "cf_minotaur", "label": "Minotaur Statue", "file": "decor/minotaur/minotaur.gltf", "fit": "height", "size": 2.3, "solid": true },
	{ "id": "cf_snake", "label": "Snake Statue", "file": "decor/snake/snake.gltf", "fit": "footprint", "size": 1.3, "solid": true },
	# --- Pillars ---
	{ "id": "cf_pillar_stone", "label": "Stone Pillar", "file": "pillars/stone/stone.gltf", "fit": "pillar", "solid": true },
	{ "id": "cf_pillar_medieval", "label": "Medieval Pillar", "file": "pillars/medieval/medieval.gltf", "fit": "pillar", "solid": true },
	{ "id": "cf_pillar_dwarven", "label": "Dwarven Pillar", "file": "pillars/dwarven/dwarven.gltf", "fit": "pillar", "solid": true },
	{ "id": "cf_pillar_decorative", "label": "Decorative Pillar", "file": "pillars/decorative/decorative.gltf", "fit": "pillar", "solid": true },
	{ "id": "cf_pillar_temple", "label": "Temple Pillar", "file": "pillars/temple/temple.gltf", "fit": "pillar", "solid": true },
	{ "id": "cf_pillar_temple_tall", "label": "Tall Temple Pillar", "file": "pillars/temple_tall/temple_tall.gltf", "fit": "pillar", "solid": true },
	# --- Lights ---
	{ "id": "cf_torch_stand", "label": "Torch Stand", "file": "dungeon/torch/BP_Torch_Stand.gltf", "fit": "height", "size": 1.5,
		"solid": true, "light": [1.6, 7.0], "flame": "top", "flame_size": 1.9 },
	{ "id": "cf_wall_sconce", "label": "Wall Sconce", "file": "dungeon/wall_torch/wall_torch.glb", "fit": "height", "size": 0.6,
		"wall": true, "mount": 1.5, "light": [1.3, 6.0], "flame": "top", "flame_size": 1.1 },
	{ "id": "cf_chandelier", "label": "Candle Chandelier", "file": "decor/chandelier/chandelier.gltf", "fit": "footprint", "size": 0.85,
		"hang": true, "light": [1.7, 8.0], "flame": "wicks", "flame_size": 0.7 },
	# --- Clutter ---
	{ "id": "cf_crate", "label": "Wooden Crate", "file": "decor/crate/crate.gltf", "fit": "cell", "size": 0.9, "solid": true },
	{ "id": "cf_crate_broken", "label": "Broken Crate", "file": "decor/barrel/crate_broken.gltf", "fit": "footprint", "size": 0.9, "solid": true },
	{ "id": "cf_barrel", "label": "Barrel", "file": "decor/barrel/barrel.gltf", "fit": "height", "size": 1.0, "solid": true },
	{ "id": "cf_barrel_broken", "label": "Broken Barrel", "file": "decor/barrel/barrel_broken.gltf", "fit": "footprint", "size": 0.85, "solid": true },
	{ "id": "cf_gold_bag", "label": "Bag of Gold", "file": "decor/goldbag/goldbag.gltf", "fit": "height", "size": 0.4 },
	{ "id": "cf_chest_small", "label": "Small Chest (prop)", "file": "dungeon/chest/small.gltf", "fit": "scale", "size": 1.5, "solid": true },
	{ "id": "cf_chest_medium", "label": "Chest (prop)", "file": "dungeon/chest/medium.gltf", "fit": "scale", "size": 1.5, "solid": true },
	{ "id": "cf_chest_large", "label": "Large Chest (prop)", "file": "dungeon/chest/large.gltf", "fit": "scale", "size": 1.5, "solid": true },
	{ "id": "cf_chest_epic", "label": "Epic Chest (prop)", "file": "dungeon/chest/epic.gltf", "fit": "scale", "size": 1.5, "solid": true },
	{ "id": "cf_dwarf_bowl", "label": "Dwarven Bowl", "file": "decor/vessels/bowl.gltf", "fit": "footprint", "size": 0.35 },
	{ "id": "cf_dwarf_cup", "label": "Dwarven Cup", "file": "decor/vessels/cup.gltf", "fit": "height", "size": 0.18 },
	{ "id": "cf_runic_vase", "label": "Runic Vase", "file": "decor/vessels/vase.gltf", "fit": "height", "size": 0.5 },
	{ "id": "cf_runic_plate", "label": "Runic Plate", "file": "decor/vessels/plate.gltf", "fit": "footprint", "size": 0.32 },
	# --- Pottery (source models are already in metres) ---
	{ "id": "cf_round_pot", "label": "Round Pot", "file": "decor/pottery/round_pot.gltf", "fit": "scale", "size": 1.2 },
	{ "id": "cf_tall_jar", "label": "Tall Jar", "file": "decor/pottery/tall_jar.gltf", "fit": "scale", "size": 1.2 },
	{ "id": "cf_jug", "label": "Jug", "file": "decor/pottery/jug.gltf", "fit": "scale", "size": 1.2 },
	{ "id": "cf_bottle", "label": "Bottle", "file": "decor/pottery/bottle.gltf", "fit": "scale", "size": 1.2 },
	{ "id": "cf_crock", "label": "Crock", "file": "decor/pottery/crock.gltf", "fit": "scale", "size": 1.2 },
	{ "id": "cf_lidded_pot", "label": "Lidded Pot", "file": "decor/pottery/lidded_pot.gltf", "fit": "scale", "size": 1.2 },
	{ "id": "cf_bowl", "label": "Handled Bowl", "file": "decor/pottery/bowl.gltf", "fit": "scale", "size": 1.2 },
	{ "id": "cf_cup", "label": "Cup", "file": "decor/pottery/cup.gltf", "fit": "scale", "size": 1.2 },
	{ "id": "cf_plate", "label": "Plate", "file": "decor/pottery/plate.gltf", "fit": "scale", "size": 1.2 },
	{ "id": "cf_mortar", "label": "Mortar & Pestle", "file": "decor/pottery/mortar.gltf", "fit": "scale", "size": 1.2 },
]

static func scene_path(prop: Dictionary) -> String:
	return SCENES + String(prop["id"]) + ".tscn"

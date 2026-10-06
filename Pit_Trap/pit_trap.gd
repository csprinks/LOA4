extends Node3D
class_name PitTrap

## A trap door set flush into the floor: two flaps hinged on opposite edges of the
## cell. It wears the floor texture around it, so only its seams give it away. When
## the party comes to rest on it the flaps swing down, the party drops into the
## shaft with a scream, the screen fades, the target level loads and every hero
## takes the fall damage on landing.
##
## A push block slid onto it sets it off too (`opened_by_blocks`): the block drops
## through to the cell below on the target level, and a moment later the flaps
## swing shut again, leaving the trap hidden and armed as before.
##
## The Level Painter builds this INSTEAD of the cell's floor tile and hands it the
## surrounding floor texture (`wall_texture`). A trap that leads nowhere stays shut
## and is just floor.

## Name of a WallTextures set ("" = the plain floor material). Set by the painter.
@export var wall_texture: String = ""
@export_file("*.tscn") var target_scene_path: String = ""
## Marker the party arrives at on the target level. "" = the cell directly below
## this trap (floors of a painted dungeon share one grid).
@export var target_spawn_marker_name: String = ""
@export var message: String = "The floor gives way beneath you!"
## Hit points a hero loses on landing: rolled between these two for each hero
## (both 0 = no damage). A fall never kills: it leaves a hero on at least 1 HP
## (there is no death outside combat).
@export var fall_damage_min: int = 10
@export var fall_damage_max: int = 30
## A push block resting on the trap opens it and falls to the level below.
@export var opened_by_blocks: bool = true
## Played together as the party drops. Left empty, DEFAULT_SCREAMS are used.
@export var fall_sounds: Array[AudioStream] = []
@export var open_angle: float = 84.0    # degrees each flap swings down
@export var open_time: float = 0.3
## How long the flaps hang open after a block has gone through before they close.
@export var reclose_delay: float = 1.5
@export var close_time: float = 0.6
## How long the party falls before the screen starts to fade.
@export var fall_time: float = 0.35

const DEFAULT_SCREAMS := [
	"res://Audio/Sound_Effects/Fall_Scream_Male.mp3",
	"res://Audio/Sound_Effects/Fall_Scream_Female.mp3",
]
const STAND_HEIGHT := 0.5    # the player's origin above a floor (matches PlayerSpawn)
const BLOCK_HEIGHT := 1.0    # a push block's origin above the floor it rests on
const CENTER_SLACK := 0.3    # how near the cell centre something must be to spring it
const SHAFT_DEPTH := 8.0

@onready var _hinge_a: Node3D = $HingeA
@onready var _hinge_b: Node3D = $HingeB
@onready var _floor_shape: CollisionShape3D = $Floor/CollisionShape3D
@onready var _trigger: Area3D = $Trigger

var _open := false       # the flaps are down
var _dropping := false   # the party is falling; the level is about to change

func _ready() -> void:
	# Flat variant: the same material the floor tiles around it wear (world-space
	# triplanar, so the pattern runs straight across the flaps).
	var mat := WallTextures.material(wall_texture, true)
	if mat:
		for flap: MeshInstance3D in [$HingeA/Flap, $HingeB/Flap]:
			flap.material_override = mat
	if fall_sounds.is_empty():
		for path: String in DEFAULT_SCREAMS:
			if ResourceLoader.exists(path):
				fall_sounds.append(load(path))

func _physics_process(_delta: float) -> void:
	if _dropping or target_scene_path.is_empty() or LevelManager.is_loading_level:
		return
	for body in _trigger.get_overlapping_bodies():
		if not body.is_in_group("player"):
			continue
		# Wait until the step onto the trap has finished, so the party drops from
		# the middle of the cell rather than clipping its edge.
		var movement = body.get_movement_system() if body.has_method("get_movement_system") else null
		if movement and movement.get_is_moving():
			continue
		if not _over_centre(body):
			continue
		_drop_party(body)
		return
	if opened_by_blocks and not _open:
		for block in get_tree().get_nodes_in_group("pushable_blocks"):
			if block is PushBlock and not block.is_moving and _over_centre(block) \
					and absf(block.global_position.y - global_position.y - BLOCK_HEIGHT) < 0.5:
				_drop_block(block)
				return

func _over_centre(node: Node3D) -> bool:
	var offset := node.global_position - global_position
	return Vector2(offset.x, offset.z).length() <= CENTER_SLACK

func _swing_open() -> void:
	_open = true
	# With nothing left underfoot the player's ground check lets go and they fall.
	_floor_shape.set_deferred("disabled", true)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_hinge_a, "rotation:z", -deg_to_rad(open_angle), open_time)
	tween.tween_property(_hinge_b, "rotation:z", deg_to_rad(open_angle), open_time)

func _drop_party(player: Node3D) -> void:
	_dropping = true
	var movement = player.get_movement_system() if player.has_method("get_movement_system") else null
	if movement:
		movement.set_can_move(false)   # LevelManager hands control back on arrival
	if message != "":
		GameTextBox.display_text(message)

	# Where the party lands if no marker is named: the same cell one floor down,
	# facing the way they were.
	var landing = null
	if target_spawn_marker_name == "":
		landing = Transform3D(Basis(Vector3.UP, player.global_rotation.y),
			Vector3(global_position.x, global_position.y + STAND_HEIGHT, global_position.z))

	if not _open:
		_swing_open()
	_scream()
	# The landing happens on the floor below. This level (and this trap) is gone
	# by then, so it is a static call.
	LevelManager.player_loaded.connect(PitTrap._on_landed.bind(fall_damage_min, fall_damage_max), CONNECT_ONE_SHOT)

	await get_tree().create_timer(fall_time).timeout
	# The load fades out first (the party is still falling), then frees this level.
	LevelManager.load_level(target_scene_path, target_spawn_marker_name, landing)

# The block falls out of this level and is waiting on the cell below when the
# target level next loads (WorldState carries it across).
func _drop_block(block: PushBlock) -> void:
	_swing_open()
	WorldState.add_arrival(target_scene_path, block.scene_file_path,
		Vector3(global_position.x, global_position.y + BLOCK_HEIGHT, global_position.z))
	block.fall_away(SHAFT_DEPTH)
	# Once the block is clear the flaps swing back up and the trap is floor again
	# (unless the party went in after it: then the level is about to change).
	await get_tree().create_timer(reclose_delay).timeout
	if _dropping:
		return
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_hinge_a, "rotation:z", 0.0, close_time)
	tween.tween_property(_hinge_b, "rotation:z", 0.0, close_time)
	await tween.finished
	if _dropping:
		return
	_floor_shape.set_deferred("disabled", false)
	_open = false

# The screams outlive this level: each plays from the scene root and frees itself.
func _scream() -> void:
	for sound in fall_sounds:
		if sound == null:
			continue
		var voice := AudioStreamPlayer.new()
		voice.stream = sound
		get_tree().root.add_child(voice)
		voice.finished.connect(voice.queue_free)
		voice.play()

static func _on_landed(player: Node, damage_min: int, damage_max: int) -> void:
	var low := maxi(0, mini(damage_min, damage_max))
	var high := maxi(damage_min, damage_max)
	var hurt := false
	for hero in PartyManager.party:
		if hero == null or hero.hit_points.current <= 1:
			continue
		var damage: int = RandomNumberManager.GetRandomNumber(low, high)
		if damage > 0:
			hero.hit_points.set_current(maxi(1, hero.hit_points.current - damage))
			GameTextBox.display_text("%s lands hard and takes %d damage." % [hero.character_name, damage])
			hurt = true
	if hurt:
		PartyManager.party_updated.emit()
	# A block that fell down the same hole is lying where the party lands: it gets
	# knocked a cell aside. Wait for it to settle into place first.
	var tree := player.get_tree()
	await tree.physics_frame
	await tree.physics_frame
	if not is_instance_valid(player):
		return
	var body := player as Node3D
	for block in tree.get_nodes_in_group("pushable_blocks"):
		var offset: Vector3 = block.global_position - body.global_position
		if block is PushBlock and Vector2(offset.x, offset.z).length() < 1.0 and absf(offset.y) < 2.0:
			block.knock_aside(-body.global_transform.basis.z)

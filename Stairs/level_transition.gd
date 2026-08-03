extends Area3D
class_name AnimatedStairs

## Walk-in stairs that ANIMATE the player up/down to a destination, adding real
## verticality (movement is locked during the climb, so it reads as a climb rather
## than an instant warp).
##
## Configurable:
##   - destination: a Marker3D the player is tweened to (required). Put it where
##     the player should end up — the top of a flight, an upper platform, etc.
##   - target_scene_path: OPTIONAL. Leave empty for pure in-level verticality.
##     If set, the level loads via LevelManager once the climb finishes, so the
##     same mechanic covers "climb to a higher floor" and "climb then change level".

@export var destination: Node3D                         # Marker/node the player climbs to
@export var climb_duration: float = 1.2                 # seconds for the climb
@export_file("*.tscn") var target_scene_path: String = ""   # optional level to load after the climb
@export var target_spawn_marker_name: String = "PlayerSpawn"
@export var prompt_text: String = ""

var _busy: bool = false

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _busy or not body.is_in_group("player"):
		return
	if LevelManager.is_loading_level:
		return
	# Only climb when the player walks INTO the stairs (facing them). A sideways
	# brush past the trigger shouldn't grab them and yank them up sideways.
	if not _facing_stairs(body):
		return
	_climb(body)

# True when the player's grid facing points at the stairs (within ~60 degrees).
func _facing_stairs(player: Node3D) -> bool:
	var to_stairs := global_position - player.global_position
	to_stairs.y = 0.0
	if to_stairs.length() < 0.05:
		return true
	var facing := -player.global_transform.basis.z
	facing.y = 0.0
	if facing.length() < 0.05:
		return true
	return facing.normalized().dot(to_stairs.normalized()) >= 0.5

func _climb(player: Node3D) -> void:
	if destination == null:
		push_warning("AnimatedStairs '%s' has no destination marker set." % name)
		return

	_busy = true
	if prompt_text != "":
		GameTextBox.display_text(prompt_text)

	# Take the body off physics/grid input so the tween can drive it cleanly.
	var movement = player.get_movement_system() if player.has_method("get_movement_system") else null
	if movement and movement.has_method("begin_scripted_move"):
		movement.begin_scripted_move()

	# Climb UP and FORWARD along the player's facing, so it never yanks sideways.
	# The destination marker only sets how high (its height above the player) and
	# how far (its horizontal distance); the direction follows the way you walked in.
	var offset := destination.global_position - player.global_position
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.05 else Vector3.FORWARD
	var horizontal_dist := Vector2(offset.x, offset.z).length()
	var target := player.global_position + forward * horizontal_dist + Vector3.UP * offset.y

	var tween := player.create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(player, "global_position", target, climb_duration)
	await tween.finished

	if target_scene_path.is_empty():
		# In-level verticality: the stairs live on, so hand control back here.
		if movement and movement.has_method("end_scripted_move"):
			movement.end_scripted_move()
		_busy = false
	else:
		# Change level. LevelManager frees THIS level (and this node) during the
		# load, so we must not touch the player afterwards — LevelManager clears
		# the scripted-move lock itself when it positions the player at the spawn.
		LevelManager.load_level(target_scene_path, target_spawn_marker_name)

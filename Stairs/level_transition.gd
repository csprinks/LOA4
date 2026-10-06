extends Area3D
class_name AnimatedStairs

## Walk-in stairs that ANIMATE the player up/down to a destination, adding real
## verticality (movement is locked during the climb, so it reads as a climb rather
## than an instant warp).
##
## The scene's Blockers body walls off both flanks and the tall end of the flight
## (the mesh ascends toward local -X), so the grid step raycast only lets the player
## in from the foot of the stairs.
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

# Where a climb ends when no destination marker is set but a target level is: one
# step along the flight and up to its top (matches the Stairs mesh). Only used for
# level-changing stairs, where the level swap takes over as soon as the climb ends.
const DEFAULT_RUN := 1.0
const DEFAULT_RISE := 1.1

var _busy: bool = false

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	_try_climb(body)

# Also poll while the player stands in the trigger, so stepping in sideways and
# then turning to face up the flight still starts the climb.
func _physics_process(_delta: float) -> void:
	if _busy:
		return
	for body in get_overlapping_bodies():
		if not body.is_in_group("player"):
			continue
		var movement = body.get_movement_system() if body.has_method("get_movement_system") else null
		if movement and (movement.get_is_moving() or movement.get_is_turning()):
			continue
		_try_climb(body)

func _try_climb(body: Node) -> void:
	if _busy or not body.is_in_group("player"):
		return
	if LevelManager.is_loading_level:
		return
	# Only climb when the player faces UP the flight. Entering from the side (or
	# from the top) must not start a climb: it would carry them off the stairs and
	# leave them hanging in mid-air.
	if not _facing_stairs(body):
		return
	# Already at the top (in-level stairs whose trigger still overlaps the landing).
	if (body as Node3D).global_position.distance_to(_climb_target()) < 0.5:
		return
	_climb(body)

# Horizontal unit direction the flight runs in: toward the destination marker, or
# along the Stairs mesh (which ascends toward local -X) when there is no marker or
# it sits directly overhead.
func _climb_direction() -> Vector3:
	if destination != null:
		var to_dest := destination.global_position - global_position
		to_dest.y = 0.0
		if to_dest.length() > 0.05:
			return to_dest.normalized()
	var along := -global_transform.basis.x
	along.y = 0.0
	return along.normalized() if along.length() > 0.05 else Vector3.FORWARD

# The top of the flight: the destination marker, or the default landing.
func _climb_target() -> Vector3:
	if destination != null:
		return destination.global_position
	return global_position + _climb_direction() * DEFAULT_RUN + Vector3.UP * DEFAULT_RISE

# True when the player's grid facing points up the flight (within ~45 degrees).
func _facing_stairs(player: Node3D) -> bool:
	var facing := -player.global_transform.basis.z
	facing.y = 0.0
	if facing.length() < 0.05:
		return false
	return facing.normalized().dot(_climb_direction()) >= 0.7

func _climb(player: Node3D) -> void:
	if destination == null and target_scene_path.is_empty():
		push_warning("AnimatedStairs '%s' has no destination marker and no target scene set." % name)
		return

	_busy = true
	if prompt_text != "":
		GameTextBox.display_text(prompt_text)

	# Take the body off physics/grid input so the tween can drive it cleanly.
	var movement = player.get_movement_system() if player.has_method("get_movement_system") else null
	if movement and movement.has_method("begin_scripted_move"):
		movement.begin_scripted_move()

	# Climb to the top of the flight. _facing_stairs already guaranteed the player
	# is heading up it, so going straight to the marker never yanks them sideways.
	var target := _climb_target()

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

extends RayCast3D

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if is_colliding():
		var hitObj = get_collider()
		# get_collider() can be null even when is_colliding() is true if the
		# collider was freed this frame (e.g. the old level during a teleport).
		if hitObj and hitObj.has_method("interact") && Input.is_action_just_pressed("interact"):
			hitObj.interact()

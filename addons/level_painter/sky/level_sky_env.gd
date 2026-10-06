extends WorldEnvironment

## A built level's environment when its floor has a sky. The build stores the
## floor's sky settings here; on load they become the Sky, the ambient light and
## the angle of the sibling "Sun" light (see LevelSky).

@export var sky_settings: Dictionary = {}

func _ready() -> void:
	LevelSky.apply(environment, get_node_or_null("../Sun") as DirectionalLight3D, LevelSky.settings_for(sky_settings))

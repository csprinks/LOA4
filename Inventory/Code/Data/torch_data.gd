class_name TorchData
extends InventoryData

## A torch. Held in a hero's hand it lights the party's way and burns down while it
## does (see PlayerTorchLight); the seconds it has left are the item's `charges`.

## How long a fresh torch burns, in seconds of exploring.
@export var burn_seconds: int = 300

## What is left in the hand once it has burnt out.
@export var burnt_out: InventoryData

@export_group("Light at full strength")
@export var light_color: Color = Color(1.0, 0.72, 0.42)
@export var light_energy: float = 1.6
@export var light_range: float = 9.0

class_name SkillDefinition
extends Resource

## One skill in an attribute's skill tree. Authored as a .tres under
## Character/Skills/Definitions/ named "<attribute>_<position>.tres" for path 1
## and "<attribute>_b<position>.tres" for path 2 (SkillTree loads them by that
## path). Currently a placeholder: owning it only raises the attribute; real
## gameplay effects come later.

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Which of Character.STAT_NAMES this skill belongs to.
@export var attribute: String = "Might"
## Which of the attribute's two paths it sits on. The paths cross: owning either
## skill at one position unlocks both skills at the next.
@export_range(1, 2) var path: int = 1
## 1-based slot along the path. Skills cost more the deeper they sit, and grant
## +position to the attribute per rank.
@export_range(1, 5) var position: int = 1
## Optional; the sheet draws the position numeral when unset.
@export var icon: Texture2D

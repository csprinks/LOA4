class_name SkillDefinition
extends Resource

## One skill in an attribute's skill line. Authored as a .tres under
## Character/Skills/Definitions/ named "<attribute>_<position>.tres" (SkillTree
## loads them by that path). Currently a placeholder: owning it only raises the
## line's attribute; real gameplay effects come later.

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Which of Character.STAT_NAMES this skill's line belongs to.
@export var attribute: String = "Might"
## 1-based slot along the line. Skills are bought left to right, cost more the
## deeper they sit, and grant +position to the attribute per rank.
@export_range(1, 5) var position: int = 1
## Optional; the sheet draws the position numeral when unset.
@export var icon: Texture2D

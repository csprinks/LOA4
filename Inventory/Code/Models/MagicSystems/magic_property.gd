class_name MagicProperty
extends RefCounted

var _randomNumberManager: Node

# these are used for the randomizers below always adjust this if you add/remove suffix/prefixes
const NUMSUFFIX = 11
const NUMPREFIX = 4

enum MagicSuffix {
	NONE,
	STAMINA,
	STRENGTH,
	DEXTERITY,
	INTELLIGENCE,
	SPIRIT,
	FIRE,
	EARTH,
	WATER,
	AIR,
	POSITIVE,
	NEGATIVE,
}

enum MagicPrefix {
	NONE,
	VAMPIRIC,
	HEALING,
	DAMAGEBOOST,
}

var magicPrefix: int
var magicSuffix: int

var prefixpower: int
var suffixpower: int

func _init(level: int, difficultyLevel: int, eliteMonster: bool, boss: bool) -> void:
	# TODO make this a better random algorithm with scaling of power properly
	magicPrefix = _getRandomPrefix()
	magicSuffix = _getRandomSuffix()
	prefixpower = level
	suffixpower = level

func SetRandomNumberManager(randomNumberManager: Node) -> void:
	_randomNumberManager = randomNumberManager

func _getRandomSuffix() -> int:
	var result = _randomNumberManager.GetRandomNumber(0, NUMSUFFIX + 1)

	match result:
		0: return MagicSuffix.NONE
		1: return MagicSuffix.STAMINA
		2: return MagicSuffix.STRENGTH
		3: return MagicSuffix.DEXTERITY
		4: return MagicSuffix.INTELLIGENCE
		5: return MagicSuffix.SPIRIT
		6: return MagicSuffix.FIRE
		7: return MagicSuffix.EARTH
		8: return MagicSuffix.WATER
		9: return MagicSuffix.AIR
		10: return MagicSuffix.POSITIVE
		11: return MagicSuffix.NEGATIVE
		_: return MagicSuffix.NONE

func _getRandomPrefix() -> int:
	var result = _randomNumberManager.GetRandomNumber(0, NUMPREFIX + 1)

	match result:
		0: return MagicPrefix.NONE
		1: return MagicPrefix.VAMPIRIC
		2: return MagicPrefix.HEALING
		3: return MagicPrefix.DAMAGEBOOST
		_: return MagicPrefix.NONE

func getPrefixName() -> String:
	match magicPrefix:
		MagicPrefix.NONE: return ""
		MagicPrefix.VAMPIRIC: return "Leeching "
		MagicPrefix.HEALING: return "Restoring "
		MagicPrefix.DAMAGEBOOST: return "Deadly "
		_: return ""

func getSuffixName() -> String:
	match magicSuffix:
		MagicSuffix.NONE: return ""
		MagicSuffix.STAMINA: return " of the Bear"
		MagicSuffix.STRENGTH: return " of the Giant"
		MagicSuffix.DEXTERITY: return " of the Fox"
		MagicSuffix.SPIRIT: return " of the Owl"
		MagicSuffix.FIRE: return " of the Inferno"
		MagicSuffix.EARTH: return " of Stone"
		MagicSuffix.WATER: return " of Life"
		MagicSuffix.AIR: return " of the Winds"
		MagicSuffix.POSITIVE: return " of Light"
		MagicSuffix.NEGATIVE: return " of Darkness"
		_: return ""

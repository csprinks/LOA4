class_name Attributes
extends Node

enum AttributeTypes {
	ATTRIBUTE_1,
	ATTRIBUTE_2,
	ATTRIBUTE_3,
}

@export_group("Attribute Names and Max Ranges")
@export var attribute_1_name: String = "Intelligence"
@export_range(1, 20, 1) var attribute_1_max: int = 1

@export var attribute_2_name: String = "Strength"
@export_range(1, 20, 1) var attribute_2_max: int = 1

@export var attribute_3_name: String = "Stamina"
@export_range(1, 20, 1) var attribute_3_max: int = 1

@export_group("Max Attribute Per Item")
@export_range(1, 3, 1) var MAX_NUM_ATTRIBUTES: int = 1

@export_group("Attribute Values Max Ranges")
@export var attribute_1_max_value: int = 3
@export var attribute_2_max_value: int = 5
@export var attribute_3_max_value: int = 8

var attributeValue: int
var attribute: int = AttributeTypes.ATTRIBUTE_1

var _randomNumberManager: Node

func _ready() -> void:
	_randomNumberManager = get_node("/root/RandomNumberManager")

func GetAttributeName(attrib: int) -> String:
	match attrib:
		AttributeTypes.ATTRIBUTE_1:
			return attribute_1_name
		AttributeTypes.ATTRIBUTE_2:
			return attribute_2_name
		AttributeTypes.ATTRIBUTE_3:
			return attribute_3_name
		_:
			return ""

func GetMaxAttributeValueForQualityLevel(quality: int) -> int:
	match quality:
		ItemQuality.COMMON:
			return 0
		ItemQuality.RARE:
			return attribute_1_max_value
		ItemQuality.SUPERIOR:
			return 4
		ItemQuality.ELITE:
			return 8
		_:
			return 0

static func GetNumAttributesForQualityLevel(quality: int) -> int:
	match quality:
		ItemQuality.COMMON:
			return 0
		ItemQuality.RARE:
			return 1
		ItemQuality.SUPERIOR:
			return 2
		ItemQuality.ELITE:
			return 3
		_:
			return 0

func GetNewRandomAttributes(numberOfAttributes: int, quality: int = ItemQuality.COMMON) -> Array[Attributes]:
	var numAttrs = numberOfAttributes
	if numAttrs > MAX_NUM_ATTRIBUTES:
		numAttrs = MAX_NUM_ATTRIBUTES

	if numAttrs < 1:
		return []

	var newAttributesTypes: Array[int] = []
	newAttributesTypes.resize(numAttrs)
	var count = 0

	while count < numAttrs - 1:
		var randomAttribute = GetRandomAttribute()

		if newAttributesTypes.has(randomAttribute):
			continue

		newAttributesTypes[count] = randomAttribute
		count += 1

	var newAttributes: Array[Attributes] = []

	for i in range(numAttrs):
		var newAttribute := Attributes.new()
		newAttribute.attributeValue = _randomNumberManager.GetRandomNumber(1, GetMaxAttributeValueForQualityLevel(quality))
		newAttribute.attribute = newAttributesTypes[i]
		newAttributes.append(newAttribute)

	return newAttributes

func GetRandomAttribute() -> int:
	var values = AttributeTypes.values()
	return values[_randomNumberManager.GetRandomNumber(0, values.size() - 1)]

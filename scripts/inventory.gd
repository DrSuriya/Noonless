extends RefCounted
## The player's item slots. The starting size is D11's placeholder; the
## prototype has only bandages and hospital kits (Section 6.2). A full
## inventory leaves new items where they lie.

const BANDAGE := "bandage"
const HOSPITAL_KIT := "hospital_kit"

## One entry per slot: an item kind, or "" for an empty slot.
var slots: Array[String] = []


func _init(cfg: ConfigFile) -> void:
	var count: int = cfg.get_value("inventory", "starting_slots")
	slots.resize(count)
	slots.fill("")


## Puts an item in the first free slot. Returns false if every slot is full.
func add(kind: String) -> bool:
	var free := slots.find("")
	if free < 0:
		return false
	slots[free] = kind
	return true


## Empties a slot and returns what was in it ("" if it was empty).
func take(slot: int) -> String:
	if slot < 0 or slot >= slots.size():
		return ""
	var kind := slots[slot]
	slots[slot] = ""
	return kind

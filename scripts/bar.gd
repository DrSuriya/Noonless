extends RefCounted
## The unified health and stamina bar (Section 2.6), built as the
## fill-and-ceiling model Section 6.2 asks to test. All values are percent of
## the maximum bar (0 to 100).
##
## - The fill acts as stamina: sprinting and hits drain it, and it slowly
##   regenerates up to the ceiling. If a hit takes it to zero, the player dies.
## - The ceiling acts as health: heavy hits and the escape toll lower it, and
##   only items (or clearing a map) bring it back.
## - Sprinting alone can't kill: it stops at a floor (D17's suggested lean).

const MAX := 100.0

var fill := MAX
var ceiling := MAX

var _regen_per_second: float
var _sprint_drain_per_second: float
## Sprinting can't take the fill below this.
var sprint_floor: float
var _hit_fill_loss: float
var _heavy_hit_ceiling_loss: float
var _bandage_gain: float
var _kit_gain: float
var _kit_refills: bool


## Reads its values from config/tuning.cfg, already loaded into `cfg`.
func _init(cfg: ConfigFile) -> void:
	_regen_per_second = MAX / cfg.get_value("bar", "regen_seconds_to_ceiling")
	_sprint_drain_per_second = MAX / cfg.get_value("bar", "sprint_seconds_to_empty_full_bar")
	sprint_floor = cfg.get_value("bar", "sprint_floor_percent_of_max")
	_hit_fill_loss = cfg.get_value("bar", "monster_hit_fill_loss_percent")
	_heavy_hit_ceiling_loss = cfg.get_value("bar", "heavy_hit_extra_ceiling_loss_percent")
	_bandage_gain = cfg.get_value("items", "bandage_ceiling_gain_percent")
	_kit_gain = cfg.get_value("items", "hospital_kit_ceiling_gain_percent")
	_kit_refills = cfg.get_value("items", "hospital_kit_full_refill")


func is_dead() -> bool:
	return fill <= 0.0


func can_sprint() -> bool:
	return fill > sprint_floor


## Drains the fill for `delta` seconds of sprinting, stopping at the floor.
## Returns false once the floor is reached.
func drain_sprint(delta: float) -> bool:
	fill = maxf(fill - _sprint_drain_per_second * delta, minf(sprint_floor, fill))
	return can_sprint()


func regenerate(delta: float) -> void:
	if fill < ceiling:
		fill = minf(fill + _regen_per_second * delta, ceiling)


## A monster hit. A heavy hit also lowers the ceiling.
func hit(heavy: bool) -> void:
	fill = maxf(fill - _hit_fill_loss, 0.0)
	if heavy:
		lower_ceiling(_heavy_hit_ceiling_loss)


## Lowers the ceiling (wounds and the escape toll), pulling the fill down
## with it.
func lower_ceiling(amount: float) -> void:
	ceiling = maxf(ceiling - amount, 0.0)
	fill = minf(fill, ceiling)


func use_bandage() -> void:
	ceiling = minf(ceiling + _bandage_gain, MAX)


func use_hospital_kit() -> void:
	ceiling = minf(ceiling + _kit_gain, MAX)
	if _kit_refills:
		fill = ceiling


## Clearing a map heals earlier wounds (D17's suggested lean: before the
## escape toll applies).
func heal_wounds() -> void:
	ceiling = MAX

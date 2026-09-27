extends Node
## Autoload "Tuning": reads config/tuning.cfg, which holds every undecided
## number and rule. A missing file or key is an error, never a silent
## default, so no tuning value ends up hard-coded.

const PATH := "res://config/tuning.cfg"

var _config := ConfigFile.new()


func _init() -> void:
	var err := _config.load(PATH)
	if err != OK:
		push_error("Tuning: could not load %s (%s)" % [PATH, error_string(err)])


## Returns the value of [param key] in [param section] of tuning.cfg.
func get_value(section: String, key: String) -> Variant:
	if not _config.has_section_key(section, key):
		push_error("Tuning: %s has no [%s] %s" % [PATH, section, key])
		return null
	return _config.get_value(section, key)

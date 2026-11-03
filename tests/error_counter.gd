extends Logger
## Counts errors while a test runs. A GDScript function that hits a runtime
## error just returns, so the checks after it never run; without this, a
## broken test could still finish with no failures. Tests add one with
## OS.add_logger() and fail if it caught anything.

var count := 0
var first := ""
var _mutex := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	_mutex.lock()
	count += 1
	if first.is_empty():
		first = "%s (%s:%d in %s)" % [rationale if not rationale.is_empty() else code, file, line, function]
	_mutex.unlock()

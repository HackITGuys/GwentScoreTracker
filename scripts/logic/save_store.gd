class_name SaveStore
extends RefCounted
## Persists the match state as plain JSON in the per-user data directory:
##   Windows: %APPDATA%\GwentScoreTracker\   Linux: ~/.local/share/GwentScoreTracker/
##   Web:     the browser's IndexedDB for this site
##
## Security rules (see SECURITY.md):
##  - data only: JSON text, never ResourceLoader / .tres / str_to_var / packs,
##    so a tampered file can't run code;
##  - size-capped read, parsed defensively and rebuilt by InputSanitizer;
##  - atomic write (temp file + rename) so a crash can't leave half a file;
##  - owner-only permissions (0600) on Linux/macOS.

const MAX_BYTES := 64 * 1024

## Tests switch this off so they never touch the real save file.
static var persist := true
static var path := "user://match_state.json"


static func load_state() -> Dictionary:
	if not persist or not FileAccess.file_exists(path):
		return GwentRules.new_state()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_BYTES:
		return GwentRules.new_state()
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return GwentRules.new_state()
	return InputSanitizer.normalize_state(json.data)


static func save_state(state: Dictionary) -> bool:
	if not persist:
		return false
	var text := JSON.stringify(state)
	if text.length() > MAX_BYTES:
		return false
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if OS.has_feature("linuxbsd") or OS.has_feature("macos"):
		FileAccess.set_unix_permissions(tmp, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK

# Security

Gwent Score Tracker is an offline score keeper. It has no accounts, no server-side code and no network traffic. The realistic threats are:

1. **Hostile input** in the one free-text field: the player name.
2. **Tampered or corrupt saved state**, from someone else using the device or a broken file.
3. **Tampering with the files the desktop app loads**: swapped data packs, settings overrides, or files in user-writable folders.
4. **Supply chain**: the engine and CI tooling used to build the release.

## Reporting

Please report vulnerabilities privately through GitHub's *Security → Report a vulnerability* on this repository, not in a public issue.

## Input handling

- **Few inputs.** Every action is a button, toggle or a fixed list (factions). The only free text is the player name.
- **Single entry point.** Every UI request goes through `do_action()` in [scenes/main.gd](scenes/main.gd), which matches it against an allowlist. The rules in [scripts/logic/rules.gd](scripts/logic/rules.gd) check the arguments again:
  - player must be 0 or 1;
  - row must be `close`, `ranged` or `siege`;
  - card values must come from the fixed unit and hero lists;
  - adjustments must be exactly ±1;
  - rows are capped at 40 units and 20 heroes.
- **Player names** ([scripts/logic/sanitize.gd](scripts/logic/sanitize.gd)):
  - the input field is limited to 20 characters;
  - the raw text is cut at 200 characters before any regex runs;
  - whitespace becomes a single space;
  - everything except letters, combining marks, digits, space and `. ' - _` is removed. This also removes control characters, bidi overrides and zero-width characters;
  - the result is trimmed and capped at 20 characters, with "Player N" as the fallback.
- **Rendering.** Names and messages are shown in plain `Label`s, never in BBCode or rich text, so markup in a name can't do anything.

## Saved state

- **Plain JSON only** (`user://match_state.json`). The app never loads saves through `ResourceLoader`, `.tres` or `.res` files, `str_to_var` or `load_resource_pack`. Those formats can carry scripts; JSON can't.
- **Strict validation.** A save is read only if it is ≤ 64 KB and parses as JSON. It is then **rebuilt from scratch** by `InputSanitizer.normalize_state()`:
  - each field is type-checked and clamped to its allowed values;
  - unknown keys are dropped;
  - anything invalid falls back to its default.
  
  A corrupt or tampered file can't crash the app or inject anything. You just get a fresh match. Undo snapshots go through the same validation.
- **Atomic writes.** The app writes a temporary file and then renames it over the save.
- **Permissions.** On Linux the save is owner-only (0600).
- **Location.** Saves live only in the per-user data folder:
  - Windows: `%APPDATA%\GwentScoreTracker`
  - Linux: `~/.local/share/GwentScoreTracker`
  - Web: the browser's IndexedDB for the site

  Nothing is read from or written to the executable's folder or the current working directory.

## Desktop executables

- **Embedded data.** The game data (PCK) is embedded in the executable (`binary_format/embed_pck`). There is no separate `.pck` next to it that could be replaced.
- **No settings overrides.** Exported builds set `application/config/disable_project_settings_override` (through the `.template` feature tag). An `override.cfg` dropped next to the executable is ignored. Tested: a planted `override.cfg` that changes the main scene stops a build without this setting from starting, and has no effect on the release build.
  - The setting is limited to exported builds because Godot 4.7.2 hangs at startup when it is set and the editor binary runs a `--script`, which is how the tests run.
- **No outside code or fonts.** Only the built-in font is used (no `SystemFont`). There is no GDExtension, plugin, mod or script loading, and the app makes no network calls. All visuals (emblems, themes) are drawn in code.
- **Release builds only.** CI exports with `--export-release`, without the console wrapper.

### Recommendations for distribution

- **Install location.** Put the executable in a folder only administrators can write to, for example `C:\Program Files\GwentScoreTracker\` or `/opt/gwent-score-tracker/`. Anyone who can write to the executable's folder can replace the executable itself, and no in-app check can prevent that.
- **Verify downloads** against the `SHA256SUMS` file attached to each GitHub Release.
- **Code signing** isn't set up yet. Signing the Windows executable (Authenticode) and enabling `codesign/enable` in `export_presets.cfg` would let Windows verify the publisher and reduce SmartScreen and antivirus warnings, which embedded-PCK executables sometimes trigger.

## Web build

- **Static files only.** The web build is HTML, JS, WASM and a PCK, served from DigitalOcean App Platform.
- **No special headers.** The build is single-threaded, so it doesn't need cross-origin isolation headers (COOP/COEP).
- **No third-party requests.** No fonts, analytics or CDNs.
- **Local-only state.** The match is stored in the visitor's own browser and never leaves the device.

## Build pipeline

- **Godot binaries** are downloaded from the official `godotengine/godot-builds` releases at the version pinned in `.godot-version`. Updates arrive as pull requests from `godot-update.yml`.
- **Third-party actions** in the workflows are kept up to date by Dependabot (weekly, grouped).
- **Least privilege.** Only the deploy and release jobs get `contents: write`. `web-deploy` is a generated branch that is rebuilt as a single commit on each deploy.
- **Protected `main`.** `main` only changes through release pull requests.

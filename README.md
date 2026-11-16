# Gwent Score Tracker

A score tracker for playing **Gwent, the card game from *The Witcher 3: Wild Hunt***, with physical cards. It's built with Godot 4 and runs:

- **in the browser** at <https://gwent.hackitguys.com>. The layout is designed for tablets but also works on phones.
- **as a desktop app** on Windows and Linux: one self-contained executable, with no installer and no network access.

> Fan-made. Not affiliated with or endorsed by CD PROJEKT. *The Witcher* and *Gwent* are trademarks of CD PROJEKT S.A. The faction colours and emblems in this app are original designs.

---

## Using it

Put a tablet between the two players. Each player gets a column in their faction's colours. On a portrait tablet or a phone, the columns stack.

| Area | What it does |
|---|---|
| **Top bar** | Round number and round history (`R1 41 - 37 Geralt`), weather (**Frost**, **Fog**, **Rain**, **Clear sky**), **Scorch**, **End round**, **Undo**, **Settings** |
| **Player header** | Name, faction, life gems, **Pass round**, total strength (*Leading* / *Passed*) |
| **Rows** | Close Combat, Ranged Combat and Siege, each with its score, status badges, **Horn x2** and **Clear** |
| **Keypad** | Adds a card to the *active* row (highlighted). Tap a row to make it active. `0`–`15` are unit cards; `H 0`–`H 15` are hero cards. |
| **Card tokens** | Tap a card to select it. An action bar appears: **-1**, **+1**, **Bond**, **Morale**, **Remove**. Tap the card again to deselect it. |

Everything is buttons, toggles or a fixed faction list. The only text you can type is the player name.

### Scoring rules (Witcher 3)

For each **unit** card the strength is calculated in this order:

1. **Base** strength (the keypad value).
2. **Weather** on that row (Biting Frost / Impenetrable Fog / Torrential Rain) sets the base to **1**. Weather affects both players' rows.
3. **Tight Bond**: tag identical cards with **Bond**. Each one is multiplied by the number of bond-tagged cards in the row *with the same base strength*. Three bonded 4s count 12 each.
4. **Morale Boost**: a card tagged **Morale** gives +1 to every *other* unit in its row.
5. **Commander's Horn** doubles the result.
6. **Manual adjustment** (**-1**/**+1**) is added last, for leader abilities and other edge cases. A card never goes below 0.

**Hero** cards (`H`) ignore weather, bond, morale, horn and Scorch.

### Battlefield actions

- **Scorch** destroys every unit card that shares the highest current strength on the battlefield, on both sides. It only works in 2-player mode.
- **Clear sky** removes all weather.
- **Undo** reverts the last change, up to 50 steps, including End round and New match. On desktop you can also press Ctrl+Z.

### Rounds and the match

- **Pass round** marks a player as passed. When **both** players have passed, the round ends automatically. You can also press **End round**.
- At the end of a round, the higher total wins. The loser loses a life gem; in a draw, both players do.
- The result goes into the round history. Rows, weather, horns and passes are then cleared.
- When a player runs out of life gems, a banner names the match winner and **End round** is disabled. **New match** starts over and keeps names and factions.
- Tapping a life gem corrects lives by hand: tapping a lit gem turns it off, tapping a dark gem turns it on.

### Factions

Pick a faction for each player to theme their column. Factions that affect scoring are applied automatically; the others show a reminder.

| Faction | Theme | Perk | In the tracker |
|---|---|---|---|
| Neutral | gold / oak, crossed swords | none | — |
| Northern Realms | blue, crown | draws a card after winning a round | reminder when they win a round |
| Nilfgaardian Empire | black / gold, sun | wins rounds that end in a draw | **automatic**; if both players are Nilfgaard, a draw stays a draw |
| Scoia'tael | green, leaf | decides who goes first | reminder at New match |
| Monsters | crimson, claw marks | keeps one random unit card after each round | **automatic**: one random card stays on the board, and the message says which |
| Skellige | teal, round shield | two random discarded cards return at the start of round 3 | reminder when round 3 starts |

### Settings

- **1 player / 2 players**: in 1-player mode the app tracks one board, for example with one tablet per player. Rounds never end automatically, End round doesn't change lives, and Scorch is disabled.
- **Life gems**: turn off to play without lives or a match end.
- **Pass and End round controls**: hide them if you only want a calculator.
- **New match**, plus an about/disclaimer section.

The match is saved automatically on the device:
- **Web:** the browser's storage for the site.
- **Windows:** `%APPDATA%\GwentScoreTracker\`
- **Linux:** `~/.local/share/GwentScoreTracker/`

---

## Development

Requires **Godot 4.7.2**. The exact version CI uses is pinned in [.godot-version](.godot-version). Open the repo folder in the Godot editor; the project is at the root.

```
project.godot, export_presets.cfg, icon.svg
scenes/          main.tscn + main.gd (state, undo, action dispatch, layout),
                 player_column.gd, row_panel.gd, emblem.gd (UI built in code)
scripts/logic/   rules.gd (scoring and rounds), sanitize.gd (input and save validation),
                 save_store.gd (JSON persistence), factions.gd, faction_theme.gd
tests/           run_tests.gd (unit), smoke_game.gd (UI play-through), screenshot.gd (dev)
tools/           serve_web.py (local web server)
docs/REVIEW.md   review of the previous HTML version
SECURITY.md      threat model and hardening
```

**Design:**
- The match state is one JSON-shaped `Dictionary`.
- `GwentRules` holds pure static functions that validate their arguments and return whether anything changed.
- UI widgets only *emit* action requests. `main.gd::do_action()` is the single allowlisted entry point; it validates the request, then applies it, records undo, saves and refreshes.

### Tests

```sh
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd                    # logic, sanitizing, saves
godot --headless --path . --fixed-fps 60 --script res://tests/smoke_game.gd -- 2   # versus, through the UI
godot --headless --path . --fixed-fps 60 --script res://tests/smoke_game.gd -- 1   # solo
godot --path . --script res://tests/screenshot.gd -- 1280 800 shot.png northern nilfgaard
```

### Exports

```sh
mkdir -p build && touch build/.gdignore
godot --headless --path . --export-release "Web" build/web/index.html
godot --headless --path . --export-release "Windows Desktop" build/windows/GwentScoreTracker.exe
godot --headless --path . --export-release "Linux" build/linux/GwentScoreTracker.x86_64
python tools/serve_web.py          # http://localhost:8060
python tools/serve_web.py --lan    # test on a real tablet on the same Wi-Fi
```

The web export is single-threaded, so it needs no special headers: any static web server works, including `python -m http.server`. The desktop exports embed the game data, so each one is a single file.

---

## Branches, releases and deployment

The setup matches the Spell-Tower project:

- **`develop`**: day-to-day work. Every push and pull request runs [build.yml](.github/workflows/build.yml): tests, a smoke play-through, and Web, Windows and Linux exports, uploaded as artifacts.
- **`main`**: protected. It only changes through release pull requests.
- **Release:** publish a GitHub Release (for example `v2.0.0`):
  - [release-pr.yml](.github/workflows/release-pr.yml) opens a *Release* PR from `develop` to `main`.
  - [desktop-release.yml](.github/workflows/desktop-release.yml) attaches `GwentScoreTracker-<tag>-windows-x86_64.zip`, `…-linux-x86_64.tar.gz` and `SHA256SUMS` to the release.
- **Deploy:** merging the release PR runs `build.yml` on `main`, which force-pushes the web export to the **`web-deploy`** branch under `public/`. DigitalOcean App Platform ([.do/app.yaml](.do/app.yaml)) redeploys gwent.hackitguys.com from that branch.
- **Upkeep:** [godot-update.yml](.github/workflows/godot-update.yml) opens a PR when a Godot patch release is out (and an issue for a new minor version). [Dependabot](.github/dependabot.yml) keeps the actions up to date.

**One-time DigitalOcean switch:** the app used to serve `index.html` from `main`. After the first `web-deploy` push, point the existing app at branch `web-deploy` with output directory `public`. Use the control panel or `doctl apps update <app-id> --spec .do/app.yaml`. Until then, the site keeps serving whatever `main` had at its last deploy.

**Repository settings needed:** under *Actions → General*, allow GitHub Actions to create and approve pull requests (for release-pr and godot-update).

---

## Security summary

Details are in [SECURITY.md](SECURITY.md).

- **Player names:** the only free text. Limited to 20 characters; control, bidi and zero-width characters are removed; only letters, digits, spaces and `. ' - _` are allowed.
- **Saves are data only.** They are JSON, size-capped, and rebuilt field by field against allowlists. They are never loaded as resources or code, and a tampered or corrupt save falls back to a fresh match.
- **Desktop builds** embed their data, ignore `override.cfg`, store saves only in the per-user data folder (owner-only permissions on Linux), use only the built-in font, and make no network connections.

## License

[MIT](LICENSE) © HackITGuys.

class_name Factions
extends RefCounted
## Faction catalogue: display name, faction perk (Witcher 3 Gwent rules) and
## the colour palette used to theme a player's column. The palettes and the
## emblems drawn by scenes/emblem.gd are original designs for this tracker.
##
## IDS is the allowlist: anything not in it (from the UI or a save file) is
## rejected and replaced with "neutral".

const DEFAULT := "neutral"
const IDS: Array[String] = ["neutral", "northern", "nilfgaard", "scoiatael", "monsters", "skellige"]

const DATA := {
	"neutral": {
		"name": "Neutral",
		"perk": "No faction ability.",
		"bg": Color("1a110a"), "panel": Color("2a1c11"), "row": Color("21160d"),
		"accent": Color("d4af37"), "accent_dark": Color("8c6d1f"),
		"text": Color("f2e6d0"), "muted": Color("b8a68e"),
	},
	"northern": {
		"name": "Northern Realms",
		"perk": "Draws a card from the deck after winning a round.",
		"bg": Color("0b1526"), "panel": Color("14243d"), "row": Color("0f1c31"),
		"accent": Color("74a9ff"), "accent_dark": Color("2f5ea8"),
		"text": Color("e8eef8"), "muted": Color("9fb1cc"),
	},
	"nilfgaard": {
		"name": "Nilfgaardian Empire",
		"perk": "Wins any round that ends in a draw.",
		"bg": Color("0b0b0d"), "panel": Color("1a181c"), "row": Color("121114"),
		"accent": Color("e8b923"), "accent_dark": Color("8a6a10"),
		"text": Color("f1eadb"), "muted": Color("aaa395"),
	},
	"scoiatael": {
		"name": "Scoia'tael",
		"perk": "Decides who takes the first turn.",
		"bg": Color("0c1c11"), "panel": Color("15301d"), "row": Color("102518"),
		"accent": Color("8fd14f"), "accent_dark": Color("4a7d24"),
		"text": Color("e9f3e1"), "muted": Color("a3bb98"),
	},
	"monsters": {
		"name": "Monsters",
		"perk": "Keeps one random unit card on the battlefield after each round.",
		"bg": Color("1c0909"), "panel": Color("2e0f0f"), "row": Color("240c0c"),
		"accent": Color("e5574e"), "accent_dark": Color("8e2620"),
		"text": Color("f6e3e0"), "muted": Color("c49d98"),
	},
	"skellige": {
		"name": "Skellige",
		"perk": "At the start of round 3, two random cards from the discard pile return to the battlefield.",
		"bg": Color("091c21"), "panel": Color("103038"), "row": Color("0c262d"),
		"accent": Color("4fd1c5"), "accent_dark": Color("1f7a73"),
		"text": Color("e2f4f3"), "muted": Color("95b9b6"),
	},
}


static func is_valid(id: Variant) -> bool:
	return id is String and IDS.has(id)


static func get_data(id: String) -> Dictionary:
	return DATA[id] if is_valid(id) else DATA[DEFAULT]


# --- hidden looks ----------------------------------------------------------------
# A couple of player names unlock a joke emblem and palette for their column.
# This is cosmetic only: the selected faction (and its perk) is unchanged, and
# these ids are not in IDS, so they can't be selected or stored in a save.

## Lower-cased player name -> hidden look id.
const NAME_LOOKS := {
	"øystein": "egg_poo",
	"babbustaman": "egg_gold",
}

const HIDDEN := {
	"egg_poo": {
		"name": "Brown",
		"bg": Color("1f1309"), "panel": Color("3b2414"), "row": Color("2e1c10"),
		"accent": Color("d0935a"), "accent_dark": Color("7a4a22"),
		"text": Color("f3e3d0"), "muted": Color("c4a586"),
	},
	"egg_gold": {
		"name": "Black and gold",
		"bg": Color("050505"), "panel": Color("121008"), "row": Color("0b0a06"),
		"accent": Color("ffd24a"), "accent_dark": Color("a07c18"),
		"text": Color("fff4d6"), "muted": Color("c9b98a"),
	},
}


## True for faction ids and hidden look ids (anything with a palette).
static func has_palette(id: Variant) -> bool:
	return is_valid(id) or (id is String and HIDDEN.has(id))


static func palette(id: String) -> Dictionary:
	return HIDDEN[id] if id is String and HIDDEN.has(id) else get_data(id)


## The look (palette + emblem) for a player: a hidden look when the name
## matches, otherwise the player's faction.
static func look_for(player_name: String, faction: String) -> String:
	return NAME_LOOKS.get(player_name.strip_edges().to_lower(), faction if is_valid(faction) else DEFAULT)


static func display_name(id: String) -> String:
	return get_data(id)["name"]

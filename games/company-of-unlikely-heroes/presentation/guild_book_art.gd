extends RefCounted
## Packaged guild-book art, keyed by explicitly disclosed presentation IDs.

const ROOT := "res://assets/guild-book"
const CLASS_LABELS := {
	"bard": "Bad Bard",
	"wizard": "Enthusiastic Caster",
	"healer": "Unimpressed Healer",
	"rogue": "Daft Dodger",
	"knight": "Anxious Knight",
	"necromancer": "Friendly Crypter",
	"alchemist": "Mixologist",
	"blacksmith": "Hobby Smith",
}

static var _textures: Dictionary = {}


## The caller must supply the character's explicit guild_portrait opt-in.
static func class_portrait(portrait_id: String) -> Texture2D:
	return _open("classes", portrait_id)


static func destination(mission_id: String) -> Texture2D:
	return _open("destinations", mission_id)


## Only the immediate disclosed mission belongs here, never a future route ID.
static func report(mission_id: String) -> Texture2D:
	return _open("reports", mission_id)


static func upgrade(upgrade_id: String) -> Texture2D:
	return _open("upgrades", upgrade_id)


## A petition's illustrated action plate is independent of its canonical hero portrait.
static func petition(art_id: String) -> Texture2D:
	return _open("petitions", art_id)


## For explicitly authored class identities only; does not rename characters.
static func class_label(identity: String) -> String:
	return CLASS_LABELS.get(identity, "")


static func _open(directory: String, id: String) -> Texture2D:
	if not id.is_valid_identifier():
		return null
	var path := ROOT.path_join(directory).path_join(id + ".png")
	if _textures.has(path):
		return _textures[path]
	var texture: Texture2D
	# Raw PNGs work in fresh checkouts before the Godot editor imports assets.
	if FileAccess.file_exists(path):
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			texture = ImageTexture.create_from_image(image)
	elif ResourceLoader.exists(path, "Texture2D"):
		texture = load(path) as Texture2D
	if texture != null:
		_textures[path] = texture
		print_verbose("Loaded guild-book illustration: " + path)
	return texture

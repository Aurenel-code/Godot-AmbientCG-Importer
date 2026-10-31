@tool
# AmbientMaterialMaker
# Writes StandardMaterial3D resources for ambientCG texture sets.

const Writer = preload("res://addons/ambientcg/handlers/ambient_resource_writer.gd")

# Last "_"-separated part of an ambientCG texture name -> texture role.
# NormalDX is deliberately absent: Godot expects OpenGL-style normal maps.
const TEXTURE_ROLES = {
	"color": "albedo",
	"normalgl": "normal",
	"roughness": "roughness",
	"metalness": "metallic",
	"ambientocclusion": "ao",
	"displacement": "height",
	"opacity": "opacity",
	"emission": "emission",
}
const IMAGE_EXTENSIONS = ["jpg", "jpeg", "png"]


## Maps texture roles ("albedo", "normal", ...) to the matching file paths.
static func classify_textures(files: PackedStringArray) -> Dictionary:
	var maps := {}
	for file in files:
		if not file.get_extension().to_lower() in IMAGE_EXTENSIONS:
			continue
		var base_name := file.get_file().get_basename()
		var suffix := base_name.get_slice("_", base_name.get_slice_count("_") - 1).to_lower()
		var role = TEXTURE_ROLES.get(suffix, "")
		if not role.is_empty() and not maps.has(role):
			maps[role] = file
	return maps


## Returns StandardMaterial3D properties for the given texture maps,
## registering each texture with the writer.
static func build_material_properties(
	writer: Writer, maps: Dictionary, options: Dictionary
) -> Dictionary:
	var triplanar: bool = options.get("use_triplanar_uv", false)
	var props := {}
	if triplanar:
		props["uv1_triplanar"] = true
	if maps.has("albedo"):
		props["albedo_texture"] = writer.ext("Texture2D", maps["albedo"])
	if maps.has("metallic"):
		# The texture is multiplied by `metallic`, which defaults to 0.
		props["metallic"] = 1.0
		props["metallic_texture"] = writer.ext("Texture2D", maps["metallic"])
	if maps.has("roughness"):
		props["roughness_texture"] = writer.ext("Texture2D", maps["roughness"])
	if maps.has("emission"):
		props["emission_enabled"] = true
		props["emission_texture"] = writer.ext("Texture2D", maps["emission"])
	if maps.has("normal"):
		props["normal_enabled"] = true
		props["normal_texture"] = writer.ext("Texture2D", maps["normal"])
	if maps.has("ao"):
		props["ao_enabled"] = true
		props["ao_texture"] = writer.ext("Texture2D", maps["ao"])
	if maps.has("height") and not triplanar:
		props["heightmap_enabled"] = true
		props["heightmap_texture"] = writer.ext("Texture2D", maps["height"])
	return props


static func write_standard_material(
	path: String, files: PackedStringArray, options: Dictionary
) -> Error:
	var writer := Writer.new()
	var props := build_material_properties(writer, classify_textures(files), options)
	return Writer.save_text(path, writer.build_resource("StandardMaterial3D", props))

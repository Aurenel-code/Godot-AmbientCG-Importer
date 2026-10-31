@tool
# AmbientMaterialMaker
# Writes StandardMaterial3D resources for ambientCG texture sets.
# Godot reads transparency from the albedo alpha, so sets with a separate
# opacity map get it baked into a PNG copy of the color map.

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
	# Every ambientCG atlas is a set of cut-outs on a transparent background.
	if maps.has("opacity") or options.get("asset_type", "") == "atlas":
		props["transparency"] = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		props["cull_mode"] = BaseMaterial3D.CULL_DISABLED
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
	var maps := classify_textures(files)
	if maps.has("albedo") and maps.has("opacity"):
		var albedo := Image.load_from_file(maps["albedo"])
		if not albedo or albedo.is_empty():
			return ERR_CANT_OPEN
		var baked_path: String = maps["albedo"].get_basename() + "Alpha.png"
		var albedo_path := prepare_transparent_albedo(albedo, maps, baked_path)
		if albedo_path.is_empty():
			return ERR_CANT_CREATE
		maps["albedo"] = albedo_path

	var writer := Writer.new()
	var props := build_material_properties(writer, maps, options)
	return Writer.save_text(path, writer.build_resource("StandardMaterial3D", props))


## Returns the albedo texture for a set with an opacity map: the color map
## itself when it already carries alpha (PNG sets), otherwise out_path with
## the opacity baked in. Returns an empty string on failure.
static func prepare_transparent_albedo(albedo: Image, maps: Dictionary, out_path: String) -> String:
	if not maps.has("opacity") or albedo.detect_alpha() != Image.ALPHA_NONE:
		return maps["albedo"]
	if bake_albedo_with_opacity(albedo, maps["opacity"], out_path) != OK:
		return ""
	return out_path


## Copies the opacity map into the alpha channel of the albedo image.
static func bake_albedo_with_opacity(
	albedo: Image, opacity_path: String, out_path: String
) -> Error:
	var opacity := Image.load_from_file(opacity_path)
	if not opacity or opacity.is_empty():
		return ERR_CANT_OPEN

	var color := albedo.duplicate() as Image
	color.convert(Image.FORMAT_RGBA8)
	opacity.convert(Image.FORMAT_L8)
	if opacity.get_size() != color.get_size():
		opacity.resize(color.get_width(), color.get_height())

	var rgba := color.get_data()
	var alpha := opacity.get_data()
	for i in alpha.size():
		rgba[i * 4 + 3] = alpha[i]

	var out := Image.create_from_data(
		color.get_width(), color.get_height(), false, Image.FORMAT_RGBA8, rgba
	)
	return out.save_png(out_path)

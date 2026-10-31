@tool
# AmbientDecalMaker
# Writes Decal scenes for ambientCG decal texture sets.
# Godot decals read transparency from the albedo alpha and roughness/metal/AO
# from a packed ORM texture, so those are baked from ambientCG's separate maps.

const Writer = preload("res://addons/ambientcg/handlers/ambient_resource_writer.gd")
const MaterialMaker = preload("res://addons/ambientcg/handlers/ambient_material_maker.gd")

const DECAL_DEPTH := 1.0


## Writes a scene with a Decal root node. Baked textures are saved into
## bake_dir next to the extracted ones.
static func write_decal_scene(
	path: String, node_name: String, files: PackedStringArray, bake_dir: String
) -> Error:
	var maps := MaterialMaker.classify_textures(files)
	if not maps.has("albedo"):
		return ERR_FILE_NOT_FOUND

	var albedo := Image.load_from_file(maps["albedo"])
	if not albedo or albedo.is_empty():
		return ERR_CANT_OPEN
	var size := albedo.get_size()

	var albedo_path: String = maps["albedo"]
	if maps.has("opacity"):
		albedo_path = bake_dir.path_join(node_name + "_DecalAlbedo.png")
		var err := bake_albedo_with_opacity(albedo, maps["opacity"], albedo_path)
		if err != OK:
			return err

	var writer := Writer.new()
	var props := {
		"size": _get_decal_size(size),
		"texture_albedo": writer.ext("Texture2D", albedo_path),
	}
	if maps.has("normal"):
		props["texture_normal"] = writer.ext("Texture2D", maps["normal"])
	if maps.has("ao") or maps.has("roughness") or maps.has("metallic"):
		var orm_path := bake_dir.path_join(node_name + "_DecalORM.png")
		var err := bake_orm(maps, size, orm_path)
		if err != OK:
			return err
		props["texture_orm"] = writer.ext("Texture2D", orm_path)

	return Writer.save_text(path, writer.build_scene(node_name, "Decal", props))


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


## Packs AO (R), roughness (G) and metalness (B) into one texture.
## Missing maps get Godot's neutral values (no occlusion, rough, non-metal).
static func bake_orm(maps: Dictionary, size: Vector2i, out_path: String) -> Error:
	var ao := _load_channel(maps.get("ao", ""), size, 255)
	var rough := _load_channel(maps.get("roughness", ""), size, 255)
	var metal := _load_channel(maps.get("metallic", ""), size, 0)

	var pixel_count := size.x * size.y
	var data := PackedByteArray()
	data.resize(pixel_count * 3)
	for i in pixel_count:
		data[i * 3] = ao[i]
		data[i * 3 + 1] = rough[i]
		data[i * 3 + 2] = metal[i]

	var out := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGB8, data)
	return out.save_png(out_path)


static func _load_channel(path: String, size: Vector2i, fallback: int) -> PackedByteArray:
	if not path.is_empty():
		var img := Image.load_from_file(path)
		if img and not img.is_empty():
			img.convert(Image.FORMAT_L8)
			if img.get_size() != size:
				img.resize(size.x, size.y)
			return img.get_data()

	var data := PackedByteArray()
	data.resize(size.x * size.y)
	data.fill(fallback)
	return data


# Longest side is 1 m; the decal projects along its local -Y axis.
static func _get_decal_size(image_size: Vector2i) -> Vector3:
	var longest := float(max(image_size.x, image_size.y))
	return Vector3(image_size.x / longest, DECAL_DEPTH, image_size.y / longest)

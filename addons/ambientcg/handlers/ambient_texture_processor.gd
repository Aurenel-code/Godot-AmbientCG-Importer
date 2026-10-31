@tool
# AmbientTextureProcessor
# Prepares an extracted texture set before resources are made from it:
# - merges the opacity map into the alpha of the color map (Godot reads
#   transparency from the albedo alpha),
# - downscales each channel to the resolution chosen for it,
# - converts them to WEBP,
# - drops the DirectX normal map (Godot uses the OpenGL one),
# - renames the files after the chosen set ("_1K-PNG_" -> "_512-WEBP-LOSSLESS_").

const MaterialMaker = preload("res://addons/ambientcg/handlers/ambient_material_maker.gd")
const Options = preload("res://addons/ambientcg/core/ambient_download_options.gd")

const IMAGE_EXTENSIONS = ["jpg", "jpeg", "png"]
const NORMAL_SUFFIXES = ["normalgl", "normaldx"]
const JPG_QUALITY := 0.95
# Lossy WEBP quality that is hard to tell apart from the original. Normal
# maps get more, since compression shows up sooner in the lighting.
const WEBP_LOSSY_QUALITY := 0.9
const WEBP_LOSSY_NORMAL_QUALITY := 0.95
# Upper limit for the roughness added for normal detail lost in downscaling
# (the same default as Godot's screen space roughness limiter).
const MAX_NORMAL_VARIANCE := 0.18


## Processes the files in place and returns the resulting file paths.
## Options: "channel_sizes" (channel -> pixels), "target_size" (pixels for
## files of other channels, 0 keeps the size), "convert_to" ("webp_lossless",
## "webp_lossy" or ""), "source_attributes" and
## "target_attributes" (for renaming).
static func process_set(files: PackedStringArray, options: Dictionary) -> PackedStringArray:
	var target_size: int = options.get("target_size", 0)
	var channel_sizes: Dictionary = options.get("channel_sizes", {})
	var convert_to: String = options.get("convert_to", "")
	var rename_from: String = options.get("source_attributes", "")
	var rename_to: String = options.get("target_attributes", "")
	var maps := MaterialMaker.classify_textures(files)
	var opacity_path: String = maps.get("opacity", "") if maps.has("albedo") else ""

	var result := PackedStringArray()
	# Old file name -> new file name, for the references in OBJ .mtl files.
	var renamed := {}
	# Detail the normal map lost while downscaling (a FORMAT_RF image of
	# normal lengths), used to adjust roughness.
	var normal_lengths: Image = null
	for path in _processing_order(files):
		if not path.get_extension().to_lower() in IMAGE_EXTENSIONS:
			result.append(path)
			continue
		if path == opacity_path:
			continue  # Merged into the color map below.
		if _suffix(path) == "normaldx":
			DirAccess.remove_absolute(path)
			continue

		var image := Image.load_from_file(path)
		if not image or image.is_empty():
			result.append(path)
			continue

		var suffix := _suffix(path)
		var changed := false
		var size := fit_size(
			image.get_size(), channel_sizes.get(Options.channel_of(path), target_size)
		)
		if size != image.get_size():
			changed = true
			if suffix in NORMAL_SUFFIXES:
				var lengths := downscale_normal_map(image, size)
				if suffix == "normalgl":
					normal_lengths = Image.create_from_data(
						size.x, size.y, false, Image.FORMAT_RF, lengths.to_byte_array()
					)
			else:
				image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		if suffix == "roughness" and normal_lengths:
			add_normal_variance(image, normal_lengths)
			changed = true

		if path == maps.get("albedo", "") and not opacity_path.is_empty():
			var opacity := Image.load_from_file(opacity_path)
			if opacity and not opacity.is_empty() and image.detect_alpha() == Image.ALPHA_NONE:
				image = MaterialMaker.merge_opacity(image, opacity)
				changed = true

		var has_alpha := image.detect_alpha() != Image.ALPHA_NONE
		var out_path := output_path(path, rename_from, rename_to, convert_to, has_alpha)
		if changed or out_path.get_extension() != path.get_extension():
			if _save(image, out_path, convert_to, suffix in NORMAL_SUFFIXES) != OK:
				result.append(path)
				continue
			if out_path != path:
				DirAccess.remove_absolute(path)
		elif out_path != path:
			DirAccess.rename_absolute(path, out_path)
		if out_path != path:
			renamed[path.get_file()] = out_path.get_file()
		result.append(out_path)

	if not opacity_path.is_empty():
		DirAccess.remove_absolute(opacity_path)
	for path in result:
		if path.get_extension().to_lower() == "mtl":
			update_mtl_references(path, renamed)
	return result


## Points the texture references of an OBJ material file at the processed
## textures, since Godot's OBJ importer loads them.
static func update_mtl_references(path: String, renamed: Dictionary) -> void:
	if renamed.is_empty():
		return
	var text := FileAccess.get_file_as_string(path)
	for old_name in renamed:
		text = text.replace(old_name, renamed[old_name])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(text)


## Scales size so its longer side is target_size (never upscales).
static func fit_size(size: Vector2i, target_size: int) -> Vector2i:
	var longest := maxi(size.x, size.y)
	if target_size <= 0 or longest <= target_size:
		return size
	var scale := float(target_size) / float(longest)
	return Vector2i(maxi(1, roundi(size.x * scale)), maxi(1, roundi(size.y * scale)))


## Downscales a normal map by averaging the normals, then renormalizes them.
## Returns how long each averaged normal was (1 = flat, shorter = bumpy
## detail that no longer fits in the smaller texture).
static func downscale_normal_map(image: Image, size: Vector2i) -> PackedFloat32Array:
	image.convert(Image.FORMAT_RGB8)
	var level := _mipmap_level(image.get_size(), size)
	if level > 0:
		# Mipmaps are plain 2x2 averages, exactly what is needed here.
		image.generate_mipmaps(false)
		var offset := image.get_mipmap_offset(level)
		var data := image.get_data().slice(offset, offset + size.x * size.y * 3)
		image.set_data(size.x, size.y, false, Image.FORMAT_RGB8, data)
	else:
		image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)

	var data := image.get_data()
	var lengths := PackedFloat32Array()
	lengths.resize(data.size() / 3)
	for i in lengths.size():
		var x := data[i * 3] / 127.5 - 1.0
		var y := data[i * 3 + 1] / 127.5 - 1.0
		var z := data[i * 3 + 2] / 127.5 - 1.0
		var length := sqrt(x * x + y * y + z * z)
		lengths[i] = minf(length, 1.0)
		if length > 0.0001:
			data[i * 3] = clampi(roundi((x / length + 1.0) * 127.5), 0, 255)
			data[i * 3 + 1] = clampi(roundi((y / length + 1.0) * 127.5), 0, 255)
			data[i * 3 + 2] = clampi(roundi((z / length + 1.0) * 127.5), 0, 255)
	image.set_data(size.x, size.y, false, Image.FORMAT_RGB8, data)
	return lengths


## Raises roughness where the downscaled normal map lost detail, so small
## bumps that can no longer be drawn still scatter light (Toksvig-style
## specular anti-aliasing, as in Filament and Godot's roughness import).
## normal_lengths is a FORMAT_RF image of averaged normal lengths; it is resampled
## when the roughness map has another resolution.
static func add_normal_variance(roughness: Image, normal_lengths: Image) -> void:
	var lengths_image := normal_lengths
	if lengths_image.get_size() != roughness.get_size():
		lengths_image = normal_lengths.duplicate() as Image
		lengths_image.resize(
			roughness.get_width(), roughness.get_height(), Image.INTERPOLATE_TRILINEAR
		)
	var lengths := lengths_image.get_data().to_float32_array()
	roughness.convert(Image.FORMAT_L8)
	var data := roughness.get_data()
	for i in data.size():
		var r := clampf(lengths[i], 0.0, 1.0)
		if r >= 0.9999:
			continue
		# Fits a von Mises-Fisher lobe to the averaged normal.
		var r2 := r * r
		var kappa := maxf((3.0 * r - r * r2) / (1.0 - r2), 0.0001)
		var variance := 1.0 / (2.0 * kappa)
		# Roughness maps store perceptual roughness; GGX alpha is its square.
		var alpha2 := pow(data[i] / 255.0, 4.0)
		alpha2 = minf(alpha2 + minf(2.0 * variance, MAX_NORMAL_VARIANCE), 1.0)
		data[i] = clampi(roundi(pow(alpha2, 0.25) * 255.0), 0, 255)
	roughness.set_data(roughness.get_width(), roughness.get_height(), false, Image.FORMAT_L8, data)


## The path a processed texture is saved to: renamed after the chosen set,
## as WEBP when converting, and as PNG when alpha was added to a JPG.
static func output_path(
	path: String, rename_from: String, rename_to: String, convert_to: String, has_alpha: bool
) -> String:
	var file_name := path.get_file().get_basename()
	if not rename_from.is_empty() and not rename_to.is_empty():
		file_name = file_name.replace("_%s_" % rename_from, "_%s_" % rename_to)
	var extension := path.get_extension().to_lower()
	if convert_to.begins_with("webp"):
		extension = "webp"
	elif has_alpha and extension in ["jpg", "jpeg"]:
		extension = "png"
	return path.get_base_dir().path_join(file_name + "." + extension)


static func _save(image: Image, path: String, convert_to: String, is_normal: bool) -> Error:
	match path.get_extension():
		"webp":
			var lossy := convert_to == "webp_lossy"
			var quality := WEBP_LOSSY_NORMAL_QUALITY if is_normal else WEBP_LOSSY_QUALITY
			return image.save_webp(path, lossy, quality if lossy else 0.75)
		"png":
			return image.save_png(path)
		_:
			return image.save_jpg(path, JPG_QUALITY)


# The mipmap level that has the given size, or 0 if none matches exactly.
static func _mipmap_level(from: Vector2i, to: Vector2i) -> int:
	var level := 0
	var size := from
	while size.x > to.x and size.y > to.y and size.x % 2 == 0 and size.y % 2 == 0:
		size /= 2
		level += 1
	return level if size == to else 0


# Normal maps go first, since the roughness map uses what they lost.
static func _processing_order(files: PackedStringArray) -> PackedStringArray:
	var normals := PackedStringArray()
	var others := PackedStringArray()
	for file in files:
		if _suffix(file) in NORMAL_SUFFIXES:
			normals.append(file)
		else:
			others.append(file)
	return normals + others


static func _suffix(path: String) -> String:
	var base_name := path.get_file().get_basename()
	return base_name.get_slice("_", base_name.get_slice_count("_") - 1).to_lower()

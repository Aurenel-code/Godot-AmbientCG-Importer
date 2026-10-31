@tool
# AmbientDownloadOptions
# Turns an asset's ambientCG downloads into the choices offered in the import
# panel (file format, a resolution per texture channel, model quality) and
# builds the download for a choice. The set that covers the largest chosen
# resolution is downloaded; WEBP is made from the PNG set and channels set
# to a smaller resolution are downscaled while importing.

const FORMATS = ["png", "jpg", "webp_lossless", "webp_lossy"]
const FORMAT_LABELS = {
	"png": "PNG",
	"jpg": "JPG",
	"webp_lossless": "WEBP Lossless",
	"webp_lossy": "WEBP Lossy",
}
# The ambientCG set each format is made from.
const FORMAT_SOURCES = {
	"png": "PNG",
	"jpg": "JPG",
	"webp_lossless": "PNG",
	"webp_lossy": "PNG",
}
# Used in file names, e.g. "Bricks113A_2K-WEBP-LOSSLESS".
const FORMAT_TAGS = {
	"png": "PNG",
	"jpg": "JPG",
	"webp_lossless": "WEBP-LOSSLESS",
	"webp_lossy": "WEBP-LOSSY",
}

# Sizes (in pixels) a texture can be downscaled to.
const DOWNSCALE_SIZES = [256, 512, 1024, 2048, 4096, 8192]

# Texture channels, named as the API lists an asset's maps.
const CHANNELS = [
	"color", "normal", "roughness", "metalness", "ambient-occlusion", "displacement", "emission"
]
const CHANNEL_LABELS = {
	"color": "Color",
	"normal": "Normal",
	"roughness": "Roughness",
	"metalness": "Metalness",
	"ambient-occlusion": "Ambient Occlusion",
	"displacement": "Displacement",
	"emission": "Emission",
}
# Shown when the API does not list an asset's maps.
const COMMON_CHANNELS = ["color", "normal", "roughness", "ambient-occlusion", "displacement"]
# Last "_"-separated part of a texture file name -> its channel. The opacity
# map is merged into the color map, so it shares its resolution.
const FILE_SUFFIX_CHANNELS = {
	"color": "color",
	"opacity": "color",
	"normalgl": "normal",
	"normaldx": "normal",
	"roughness": "roughness",
	"metalness": "metalness",
	"ambientocclusion": "ambient-occlusion",
	"displacement": "displacement",
	"emission": "emission",
}

# 3D model levels of detail, from fewest to most polygons.
const LODS = ["LQ", "SQ", "HQ"]
const LOD_LABELS = {
	"LQ": "LQ (Low Poly)",
	"SQ": "SQ (Medium Poly)",
	"HQ": "HQ (High Poly)",
}


## Splits ambientCG download attributes into their parts:
## "HQ-2K-PNG" -> {"lod": "HQ", "size": 2048, "format": "PNG"},
## "4K" (HDRIs) -> {"lod": "", "size": 4096, "format": ""}.
static func parse_attributes(attributes: String) -> Dictionary:
	var parts := {"lod": "", "size": 0, "format": ""}
	for part in attributes.to_upper().split("-"):
		if part in LODS:
			parts["lod"] = part
		elif part.ends_with("K") and part.trim_suffix("K").is_valid_int():
			parts["size"] = part.trim_suffix("K").to_int() * 1024
		elif part in ["JPG", "PNG"]:
			parts["format"] = part
	return parts


## Formats that can be offered for the downloads (none for HDRIs).
static func get_formats(downloads: Array) -> Array:
	var sources := {}
	for download in downloads:
		sources[parse_attributes(download.get("attributes", ""))["format"]] = true
	return FORMATS.filter(func(f): return sources.has(FORMAT_SOURCES[f]))


## Model levels of detail present in the downloads, fewest polygons first.
static func get_lods(downloads: Array) -> Array:
	var found := {}
	for download in downloads:
		found[parse_attributes(download.get("attributes", ""))["lod"]] = true
	return LODS.filter(func(lod): return found.has(lod))


## Resolutions (in pixels, ascending) offered for a format and model quality.
## With allow_downscale, smaller standard sizes are added below the largest
## available set.
static func get_sizes(
	downloads: Array, format: String, lod: String, allow_downscale: bool
) -> Array:
	var sizes := {}
	var largest := 0
	for download in _matching(downloads, format, lod):
		var size: int = parse_attributes(download["attributes"])["size"]
		sizes[size] = true
		largest = maxi(largest, size)
	if allow_downscale:
		for size in DOWNSCALE_SIZES:
			if size < largest:
				sizes[size] = true
	var result := sizes.keys()
	result.sort()
	return result


## The texture channels to offer resolutions for, from the asset's map list.
static func get_channels(asset_maps: Array) -> Array:
	var channels := CHANNELS.filter(func(c): return c in asset_maps)
	return channels if not channels.is_empty() else COMMON_CHANNELS.duplicate()


## The channel a texture file belongs to ("" if unknown).
static func channel_of(file_path: String) -> String:
	var base_name := file_path.get_file().get_basename()
	var suffix := base_name.get_slice("_", base_name.get_slice_count("_") - 1).to_lower()
	return FILE_SUFFIX_CHANNELS.get(suffix, "")


## The preferred size when offered, otherwise the largest smaller size,
## otherwise the smallest larger one.
static func pick_default_size(sizes: Array, preferred: int) -> int:
	var best := 0
	for size in sizes:
		if size <= preferred and size > best:
			best = size
	if best == 0 and not sizes.is_empty():
		best = sizes.min()
	return best


## The smallest download of the format and model quality that is at least
## size pixels; empty if there is none.
static func find_source(downloads: Array, format: String, lod: String, size: int) -> Dictionary:
	var best := {}
	var best_size := 0
	for download in _matching(downloads, format, lod):
		var download_size: int = parse_attributes(download["attributes"])["size"]
		if download_size >= size and (best.is_empty() or download_size < best_size):
			best = download
			best_size = download_size
	return best


## Builds the download for a choice: the source download plus the name the
## result is imported under and the import steps (downscale, conversion).
## channel_sizes maps channels to their resolution; the set that covers the
## largest one is downloaded, and size is used when it is empty (HDRIs).
## Returns an empty dictionary if the choice cannot be downloaded.
static func build_download(
	downloads: Array, format: String, lod: String, size: int, channel_sizes: Dictionary = {}
) -> Dictionary:
	if not channel_sizes.is_empty():
		size = channel_sizes.values().max()
	var source := find_source(downloads, format, lod, size)
	if source.is_empty():
		return {}

	var source_attributes: String = source["attributes"]
	var source_size: int = parse_attributes(source_attributes)["size"]
	var target_parts := PackedStringArray()
	if not lod.is_empty():
		target_parts.append(lod)
	target_parts.append(size_label(size))
	if not FORMAT_TAGS.get(format, "").is_empty():
		target_parts.append(FORMAT_TAGS[format])
	var target_attributes := "-".join(target_parts)

	var download := source.duplicate()
	download["attributes"] = target_attributes
	download["local_file_name"] = (
		"%s_%s.%s" % [source.get("asset_id", ""), target_attributes, source.get("extension", "")]
	)
	download["import_options"] = {
		"source_attributes": source_attributes,
		"target_attributes": target_attributes,
		"target_size": size if size < source_size else 0,
		"channel_sizes": channel_sizes.duplicate(),
		"convert_to": format if format.begins_with("webp") else "",
		"has_transparency": source.get("has_transparency", false),
	}
	return download


## "1K", "2K", ... for 1024 pixels and up, otherwise the pixel count.
static func size_label(size: int) -> String:
	if size >= 1024:
		return "%dK" % (size / 1024)
	return str(size)


static func _matching(downloads: Array, format: String, lod: String) -> Array:
	var source_format: String = FORMAT_SOURCES.get(format, "")
	return downloads.filter(
		func(download):
			var parts := parse_attributes(download.get("attributes", ""))
			return parts["format"] == source_format and parts["lod"] == lod and parts["size"] > 0
	)

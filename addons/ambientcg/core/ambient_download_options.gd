@tool
# AmbientDownloadOptions
# Turns an asset's ambientCG downloads into the choices offered in the import
# panel (file format, resolution, model quality) and builds the download for
# a choice. WEBP sets are made from the PNG set while importing, and sizes
# ambientCG does not offer are downscaled from the next larger set.

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
const DEFAULT_FORMAT = "webp_lossless"

# Sizes (in pixels) a texture set can be downscaled to.
const DOWNSCALE_SIZES = [256, 512, 1024, 2048, 4096, 8192]
const DEFAULT_SIZE = 2048

# 3D model levels of detail, from fewest to most polygons.
const LODS = ["LQ", "SQ", "HQ"]
const LOD_LABELS = {
	"LQ": "LQ (Low Poly)",
	"SQ": "SQ (Medium Poly)",
	"HQ": "HQ (High Poly)",
}
const DEFAULT_LOD = "LQ"


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


## 2K when offered, otherwise the largest smaller size, otherwise the
## smallest larger one.
static func pick_default_size(sizes: Array) -> int:
	var best := 0
	for size in sizes:
		if size <= DEFAULT_SIZE and size > best:
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
## Returns an empty dictionary if the choice cannot be downloaded.
static func build_download(downloads: Array, format: String, lod: String, size: int) -> Dictionary:
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

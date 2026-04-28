import SwiftUI
import ImageIO

// MARK: - Data models

private struct MetadataSection: Identifiable {
	let id = UUID()
	let title: String
	let items: [MetadataRow]
}

private struct MetadataRow: Identifiable {
	let id = UUID()
	let key: String
	let value: String      // empty when subItems is non-empty
	let subItems: [String] // non-empty when the raw value was an array
}

// MARK: - Sheet view

struct MetadataPanelView: View {
	let metadata: [String: Any]
	var imageURL: URL? = nil
	@EnvironmentObject var state: AppState

	@State private var parsedWorkflow: ComfyUIWorkflow? = nil
	@State private var workflowLoading = true

	private var sections: [MetadataSection] { buildSections() }

	var body: some View {
		VStack(spacing: 0) {
			sheetHeader
			Divider()
			if sections.isEmpty && !workflowLoading {
				emptyState
			} else {
				metadataList
			}
		}
		.frame(minWidth: 520, idealWidth: 600, minHeight: 480, idealHeight: 720)
		.background(Color(nsColor: .windowBackgroundColor))
		.preferredColorScheme(.dark)
		.task {
			let meta = metadata
			let url = imageURL
			let wf = await Task.detached(priority: .userInitiated) {
				MetadataPanelView.findWorkflow(metadata: meta, imageURL: url)
			}.value
			parsedWorkflow = wf
			workflowLoading = false
		}
	}

	// MARK: - Subviews

	private var sheetHeader: some View {
		HStack {
			Text("Image Metadata")
				.font(.system(size: 14, weight: .semibold))
			Spacer()
			Button {
				state.showMetadataPanel = false
			} label: {
				Image(systemName: "xmark.circle.fill")
					.font(.system(size: 16))
					.foregroundStyle(.secondary)
			}
			.buttonStyle(.plain)
			.help("Close")
			.accessibilityLabel("Close metadata panel")
		}
		.padding(.horizontal, 20)
		.padding(.vertical, 14)
	}

	private var emptyState: some View {
		VStack(spacing: 10) {
			Image(systemName: "doc.text.magnifyingglass")
				.font(.system(size: 36))
				.foregroundStyle(.secondary)
			Text("No metadata available")
				.font(.system(size: 13))
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private var metadataList: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 0) {
				ForEach(sections) { section in
					sectionHeader(section.title)
					ForEach(section.items) { row in
						MetadataRowView(row: row)
					}
				}
			}
			.padding(.bottom, 24)
		}
	}

	@ViewBuilder
	private func sectionHeader(_ title: String) -> some View {
		Text(title)
			.font(.system(size: 10, weight: .semibold))
			.foregroundStyle(.secondary)
			.kerning(0.8)
			.textCase(.uppercase)
			.padding(.horizontal, 20)
			.padding(.top, 16)
			.padding(.bottom, 5)
	}

	// MARK: - Metadata parsing

	private func buildSections() -> [MetadataSection] {
		var result: [MetadataSection] = []

		// ComfyUI workflow JSON — parsed async, shown first
		buildComfyUISections(workflow: parsedWorkflow, loading: workflowLoading, to: &result)

		addSection(
			title: "General",
			items: extractItems(from: metadata, keyMap: Self.generalKeyMap),
			to: &result
		)
		addSection(
			title: "TIFF",
			dict: metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
			keyMap: Self.tiffKeyMap,
			to: &result
		)
		addSection(
			title: "EXIF",
			dict: metadata[kCGImagePropertyExifDictionary as String] as? [String: Any],
			keyMap: Self.exifKeyMap,
			to: &result
		)
		addSection(title: "GPS", items: extractGPS(), to: &result)
		addSection(
			title: "IPTC",
			dict: metadata[kCGImagePropertyIPTCDictionary as String] as? [String: Any],
			keyMap: Self.iptcKeyMap,
			to: &result
		)
		addSection(title: "PNG", items: extractPNG(), to: &result)

		return result
	}

	private func addSection(title: String, items: [MetadataRow], to sections: inout [MetadataSection]) {
		guard !items.isEmpty else { return }
		sections.append(MetadataSection(title: title, items: items))
	}

	private func addSection(
		title: String,
		dict: [String: Any]?,
		keyMap: [String: String],
		to sections: inout [MetadataSection]
	) {
		guard let dict else { return }
		addSection(title: title, items: extractItems(from: dict, keyMap: keyMap), to: &sections)
	}

	// MARK: - ComfyUI workflow detection

	private nonisolated static func findWorkflow(metadata: [String: Any], imageURL: URL?) -> ComfyUIWorkflow? {
		// 1. IPTC caption — the normal path for most formats
		if let iptcDict = metadata[kCGImagePropertyIPTCDictionary as String] as? [String: Any],
		   let captionRaw = iptcDict[kCGImagePropertyIPTCCaptionAbstract as String] {
			let str: String?
			if let s = captionRaw as? String {
				str = s.trimmingCharacters(in: .whitespacesAndNewlines)
			} else if let arr = captionRaw as? [Any], let first = arr.first as? String {
				str = first.trimmingCharacters(in: .whitespacesAndNewlines)
			} else {
				str = nil
			}
			if let s = str, s.hasPrefix("{"), let wf = ComfyUIWorkflowParser.parse(from: s) {
				return wf
			}
		}
		// 2. Raw file bytes — bypasses the system XMP parser that truncates at `&`
		if let url = imageURL,
		   let raw = ComfyUIWorkflowParser.extractWorkflowJSON(from: url),
		   let wf = ComfyUIWorkflowParser.parse(from: raw) {
			return wf
		}
		return nil
	}

	private func buildComfyUISections(workflow: ComfyUIWorkflow?, loading: Bool, to sections: inout [MetadataSection]) {
		if loading {
			sections.append(MetadataSection(title: "ComfyUI", items: [
				MetadataRow(key: "Status", value: "Parsing workflow…", subItems: []),
			]))
			return
		}
		guard let wf = workflow else { return }

		// Model section
		var modelRows: [MetadataRow] = []
		if let v = wf.checkpointName {
			modelRows.append(MetadataRow(key: "Checkpoint", value: v, subItems: []))
		}
		if !wf.clipNames.isEmpty {
			if wf.clipNames.count == 1 {
				modelRows.append(MetadataRow(key: "CLIP", value: wf.clipNames[0], subItems: []))
			} else {
				modelRows.append(MetadataRow(key: "CLIP", value: "", subItems: wf.clipNames))
			}
		}
		if let v = wf.vae {
			modelRows.append(MetadataRow(key: "VAE", value: v, subItems: []))
		}
		if let v = wf.upscaleModel {
			modelRows.append(MetadataRow(key: "Upscale Model", value: v, subItems: []))
		}
		if !wf.controlNets.isEmpty {
			if wf.controlNets.count == 1 {
				modelRows.append(MetadataRow(key: "ControlNet", value: wf.controlNets[0], subItems: []))
			} else {
				modelRows.append(MetadataRow(key: "ControlNet", value: "", subItems: wf.controlNets))
			}
		}
		if !wf.ipAdapters.isEmpty {
			if wf.ipAdapters.count == 1 {
				modelRows.append(MetadataRow(key: "IP-Adapter", value: wf.ipAdapters[0], subItems: []))
			} else {
				modelRows.append(MetadataRow(key: "IP-Adapter", value: "", subItems: wf.ipAdapters))
			}
		}
		if let v = wf.ollamaModel {
			modelRows.append(MetadataRow(key: "Ollama Model", value: v, subItems: []))
		}
		if !wf.loras.isEmpty {
			let loraLines = wf.loras.map { lora -> String in
				let name = lora.name.hasSuffix(".safetensors")
					? String(lora.name.dropLast(12))
					: lora.name
				if let s = lora.strengthModel {
					return "\(name)  (\(String(format: "%.2f", s)))"
				}
				return name
			}
			modelRows.append(MetadataRow(key: "LoRAs", value: "", subItems: loraLines))
		}
		addSection(title: "ComfyUI: Model", items: modelRows, to: &sections)

		// Generation section
		var genRows: [MetadataRow] = []
		if let (w, h) = wf.generationSize {
			genRows.append(MetadataRow(key: "Target Size", value: "\(w) × \(h)", subItems: []))
		}
		let multiPass = wf.ksamplers.count > 1
		for (i, ks) in wf.ksamplers.enumerated() {
			let p = multiPass ? "[\(i + 1)] " : ""
			if let v = ks.seed { genRows.append(MetadataRow(key: "\(p)Seed", value: "\(v)", subItems: [])) }
			if let v = ks.steps {
				genRows.append(MetadataRow(key: "\(p)Steps", value: "\(v)", subItems: []))
			} else if let r = ks.stepsRange {
				genRows.append(MetadataRow(key: "\(p)Steps", value: "\(r) (random)", subItems: []))
			}
			if let v = ks.cfg { genRows.append(MetadataRow(key: "\(p)CFG", value: String(format: "%.2f", v), subItems: [])) }
			if let v = ks.samplerName { genRows.append(MetadataRow(key: "\(p)Sampler", value: v, subItems: [])) }
			if let v = ks.scheduler { genRows.append(MetadataRow(key: "\(p)Scheduler", value: v, subItems: [])) }
			if let v = ks.denoise {
				genRows.append(MetadataRow(key: "\(p)Denoise", value: String(format: "%.4f", v), subItems: []))
			} else if let r = ks.denoiseRange {
				genRows.append(MetadataRow(key: "\(p)Denoise", value: "\(r) (random)", subItems: []))
			}
		}
		addSection(title: "ComfyUI: Generation", items: genRows, to: &sections)

		// Prompts section
		var promptRows: [MetadataRow] = []
		if let v = wf.positivePrompt {
			promptRows.append(MetadataRow(key: "Prompt", value: v, subItems: []))
		}
		if let v = wf.ollamaEnhancedPrompt {
			promptRows.append(MetadataRow(key: "Enhanced", value: v, subItems: []))
		}
		if let v = wf.negativePrompt {
			promptRows.append(MetadataRow(key: "Negative", value: v, subItems: []))
		}
		if !wf.randomPrompts.isEmpty {
			promptRows.append(MetadataRow(key: "Source Prompts", value: "", subItems: wf.randomPrompts))
		}
		if let v = wf.appendText {
			promptRows.append(MetadataRow(key: "Append Text", value: v, subItems: []))
		}
		addSection(title: "ComfyUI: Prompts", items: promptRows, to: &sections)

		// File section
		var fileRows: [MetadataRow] = []
		if let v = wf.sourceFilename {
			fileRows.append(MetadataRow(key: "Source File", value: v, subItems: []))
		}
		if let v = wf.outputDirectory {
			fileRows.append(MetadataRow(key: "Output Dir", value: v, subItems: []))
		}
		addSection(title: "ComfyUI: File", items: fileRows, to: &sections)

		// Notes section
		if !wf.workflowNotes.isEmpty {
			let noteRows = wf.workflowNotes.enumerated().map { i, note in
				MetadataRow(
					key: wf.workflowNotes.count > 1 ? "Note \(i + 1)" : "Note",
					value: note,
					subItems: []
				)
			}
			addSection(title: "ComfyUI: Notes", items: noteRows, to: &sections)
		}
	}

	private func extractItems(from dict: [String: Any], keyMap: [String: String]) -> [MetadataRow] {
		keyMap
			.sorted { $0.value < $1.value }
			.compactMap { cfKey, label -> MetadataRow? in
				guard let raw = dict[cfKey] else { return nil }
				return makeRow(key: label, raw: raw, cfKey: cfKey)
			}
	}

	private func makeRow(key: String, raw: Any, cfKey: String) -> MetadataRow {
		if let arr = raw as? [Any], !arr.isEmpty {
			let strs = arr.map { formatValue($0, forKey: cfKey) }
			if strs.count == 1 {
				return MetadataRow(key: key, value: strs[0], subItems: [])
			}
			return MetadataRow(key: key, value: "", subItems: strs)
		}
		return MetadataRow(key: key, value: formatValue(raw, forKey: cfKey), subItems: [])
	}

	private func extractGPS() -> [MetadataRow] {
		guard let gps = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any] else { return [] }
		var rows: [MetadataRow] = []

		if let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
		   let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double {
			let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String ?? ""
			let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String ?? ""
			rows.append(MetadataRow(key: "Latitude",  value: String(format: "%.6f° %@", lat, latRef), subItems: []))
			rows.append(MetadataRow(key: "Longitude", value: String(format: "%.6f° %@", lon, lonRef), subItems: []))
		}
		if let alt = gps[kCGImagePropertyGPSAltitude as String] as? Double {
			let ref = gps[kCGImagePropertyGPSAltitudeRef as String] as? Int ?? 0
			let dir = ref == 0 ? "above sea level" : "below sea level"
			rows.append(MetadataRow(key: "Altitude", value: String(format: "%.1f m %@", alt, dir), subItems: []))
		}
		if let speed = gps[kCGImagePropertyGPSSpeed as String] as? Double {
			let unit = gps[kCGImagePropertyGPSSpeedRef as String] as? String ?? "km/h"
			rows.append(MetadataRow(key: "Speed", value: String(format: "%.2f %@", speed, unit), subItems: []))
		}
		if let imgDir = gps[kCGImagePropertyGPSImgDirection as String] as? Double {
			rows.append(MetadataRow(key: "Direction", value: String(format: "%.1f°", imgDir), subItems: []))
		}
		if let dateStamp = gps[kCGImagePropertyGPSDateStamp as String] as? String {
			rows.append(MetadataRow(key: "GPS Date", value: dateStamp, subItems: []))
		}
		return rows
	}

	private func extractPNG() -> [MetadataRow] {
		guard let png = metadata[kCGImagePropertyPNGDictionary as String] as? [String: Any] else { return [] }

		let knownKeys: [String: String] = [
			kCGImagePropertyPNGAuthor as String: "Author",
			kCGImagePropertyPNGComment as String: "Comment",
			kCGImagePropertyPNGCopyright as String: "Copyright",
			kCGImagePropertyPNGCreationTime as String: "Creation Time",
			kCGImagePropertyPNGDescription as String: "Description",
			kCGImagePropertyPNGGamma as String: "Gamma",
			kCGImagePropertyPNGInterlaceType as String: "Interlace Type",
			kCGImagePropertyPNGModificationTime as String: "Modification Time",
			kCGImagePropertyPNGSoftware as String: "Software",
			kCGImagePropertyPNGsRGBIntent as String: "sRGB Intent",
			kCGImagePropertyPNGTitle as String: "Title",
		]

		var rows = extractItems(from: png, keyMap: knownKeys)

		let knownKeySet = Set(knownKeys.keys)
		for key in png.keys.sorted() where !knownKeySet.contains(key) {
			guard let raw = png[key] else { continue }
			rows.append(makeRow(key: key, raw: raw, cfKey: key))
		}
		return rows
	}

	// MARK: - Value formatting

	private func formatValue(_ value: Any, forKey key: String) -> String {
		switch value {
		case let str as String:
			return str.trimmingCharacters(in: .whitespacesAndNewlines)
		case let arr as [Any]:
			return arr.map { formatValue($0, forKey: key) }.joined(separator: ", ")
		case let data as Data:
			return "[\(data.count) bytes]"
		case let num as NSNumber:
			return formatNumber(num, forKey: key)
		default:
			return "\(value)"
		}
	}

	private func formatNumber(_ num: NSNumber, forKey key: String) -> String {
		if key == kCGImagePropertyExifExposureTime as String {
			let s = num.doubleValue
			if s > 0 && s < 1 { return "1/\(Int(round(1.0 / s))) sec" }
			return String(format: "%.1f sec", s)
		}
		if key == kCGImagePropertyExifFNumber as String {
			return String(format: "f/%.1f", num.doubleValue)
		}
		if key == kCGImagePropertyExifFocalLength as String
			|| key == kCGImagePropertyExifFocalLenIn35mmFilm as String {
			return String(format: "%.0f mm", num.doubleValue)
		}
		if key == kCGImagePropertyExifWhiteBalance as String {
			return num.intValue == 0 ? "Auto" : "Manual"
		}
		if key == kCGImagePropertyExifFlash as String {
			return flashLabel(num.intValue)
		}
		if key == kCGImagePropertyExifMeteringMode as String {
			return meteringModeLabel(num.intValue)
		}
		if key == kCGImagePropertyExifExposureProgram as String {
			return exposureProgramLabel(num.intValue)
		}
		if key == kCGImagePropertyExifColorSpace as String {
			switch num.intValue {
			case 1:     return "sRGB"
			case 65535: return "Uncalibrated"
			default:    return "\(num.intValue)"
			}
		}
		if key == kCGImagePropertyTIFFOrientation as String
			|| key == kCGImagePropertyOrientation as String {
			return orientationLabel(num.intValue)
		}
		if key == kCGImagePropertyTIFFResolutionUnit as String {
			return num.intValue == 2 ? "pixels/inch" : "pixels/cm"
		}

		let d = num.doubleValue
		if d == floor(d) && abs(d) < 1_000_000 { return "\(num.intValue)" }
		return String(format: "%.4g", d)
	}

	private func flashLabel(_ v: Int) -> String {
		switch v {
		case 0:  return "No flash"
		case 1:  return "Fired"
		case 5:  return "Fired, no strobe return"
		case 7:  return "Fired, strobe return"
		case 8:  return "Did not fire"
		case 9:  return "Fired, auto"
		case 16: return "Did not fire, auto"
		case 24: return "Did not fire, no flash"
		case 25: return "Fired, auto, return detected"
		default: return "\(v)"
		}
	}

	private func meteringModeLabel(_ v: Int) -> String {
		switch v {
		case 0: return "Unknown"
		case 1: return "Average"
		case 2: return "Center-weighted"
		case 3: return "Spot"
		case 4: return "Multi-spot"
		case 5: return "Pattern"
		case 6: return "Partial"
		default: return "\(v)"
		}
	}

	private func exposureProgramLabel(_ v: Int) -> String {
		switch v {
		case 0: return "Not defined"
		case 1: return "Manual"
		case 2: return "Normal"
		case 3: return "Aperture priority"
		case 4: return "Shutter priority"
		case 5: return "Creative"
		case 6: return "Action"
		case 7: return "Portrait"
		case 8: return "Landscape"
		default: return "\(v)"
		}
	}

	private func orientationLabel(_ v: Int) -> String {
		switch v {
		case 1: return "Normal"
		case 2: return "Mirrored horizontal"
		case 3: return "Rotated 180°"
		case 4: return "Mirrored vertical"
		case 5: return "Mirrored H, rotated 90° CCW"
		case 6: return "Rotated 90° CW"
		case 7: return "Mirrored H, rotated 90° CW"
		case 8: return "Rotated 90° CCW"
		default: return "\(v)"
		}
	}

	// MARK: - Key maps

	private static let generalKeyMap: [String: String] = [
		kCGImagePropertyColorModel as String: "Color Model",
		kCGImagePropertyDepth as String: "Bit Depth",
		kCGImagePropertyDPIHeight as String: "DPI (Vertical)",
		kCGImagePropertyDPIWidth as String: "DPI (Horizontal)",
		kCGImagePropertyOrientation as String: "Orientation",
		kCGImagePropertyPixelHeight as String: "Height",
		kCGImagePropertyPixelWidth as String: "Width",
		kCGImagePropertyProfileName as String: "Color Profile",
	]

	private static let tiffKeyMap: [String: String] = [
		kCGImagePropertyTIFFArtist as String: "Artist",
		kCGImagePropertyTIFFCopyright as String: "Copyright",
		kCGImagePropertyTIFFDateTime as String: "Date/Time",
		kCGImagePropertyTIFFHostComputer as String: "Host Computer",
		kCGImagePropertyTIFFImageDescription as String: "Description",
		kCGImagePropertyTIFFMake as String: "Make",
		kCGImagePropertyTIFFModel as String: "Model",
		kCGImagePropertyTIFFOrientation as String: "Orientation",
		kCGImagePropertyTIFFResolutionUnit as String: "Resolution Unit",
		kCGImagePropertyTIFFSoftware as String: "Software",
		kCGImagePropertyTIFFXResolution as String: "X Resolution",
		kCGImagePropertyTIFFYResolution as String: "Y Resolution",
	]

	private static let exifKeyMap: [String: String] = [
		kCGImagePropertyExifApertureValue as String: "Aperture Value",
		kCGImagePropertyExifBodySerialNumber as String: "Camera Serial",
		kCGImagePropertyExifBrightnessValue as String: "Brightness",
		kCGImagePropertyExifColorSpace as String: "Color Space",
		kCGImagePropertyExifContrast as String: "Contrast",
		kCGImagePropertyExifCustomRendered as String: "Custom Rendered",
		kCGImagePropertyExifDateTimeDigitized as String: "Date Digitized",
		kCGImagePropertyExifDateTimeOriginal as String: "Date Taken",
		kCGImagePropertyExifDigitalZoomRatio as String: "Digital Zoom",
		kCGImagePropertyExifExposureBiasValue as String: "Exposure Bias",
		kCGImagePropertyExifExposureProgram as String: "Exposure Program",
		kCGImagePropertyExifExposureTime as String: "Exposure Time",
		kCGImagePropertyExifFNumber as String: "F-Number",
		kCGImagePropertyExifFlash as String: "Flash",
		kCGImagePropertyExifFlashPixVersion as String: "FlashPix Version",
		kCGImagePropertyExifFocalLength as String: "Focal Length",
		kCGImagePropertyExifFocalLenIn35mmFilm as String: "Focal Length (35mm)",
		kCGImagePropertyExifGainControl as String: "Gain Control",
		kCGImagePropertyExifISOSpeedRatings as String: "ISO Speed",
		kCGImagePropertyExifLensMake as String: "Lens Make",
		kCGImagePropertyExifLensModel as String: "Lens Model",
		kCGImagePropertyExifLightSource as String: "Light Source",
		kCGImagePropertyExifMaxApertureValue as String: "Max Aperture",
		kCGImagePropertyExifMeteringMode as String: "Metering Mode",
		kCGImagePropertyExifPixelXDimension as String: "Pixel Width",
		kCGImagePropertyExifPixelYDimension as String: "Pixel Height",
		kCGImagePropertyExifSaturation as String: "Saturation",
		kCGImagePropertyExifSceneCaptureType as String: "Scene Capture Type",
		kCGImagePropertyExifSensingMethod as String: "Sensing Method",
		kCGImagePropertyExifSharpness as String: "Sharpness",
		kCGImagePropertyExifShutterSpeedValue as String: "Shutter Speed Value",
		kCGImagePropertyExifSubjectDistance as String: "Subject Distance",
		kCGImagePropertyExifWhiteBalance as String: "White Balance",
	]

	private static let iptcKeyMap: [String: String] = [
		kCGImagePropertyIPTCByline as String: "Author",
		kCGImagePropertyIPTCCaptionAbstract as String: "Caption",
		kCGImagePropertyIPTCCategory as String: "Category",
		kCGImagePropertyIPTCCity as String: "City",
		kCGImagePropertyIPTCCopyrightNotice as String: "Copyright",
		kCGImagePropertyIPTCCountryPrimaryLocationName as String: "Country",
		kCGImagePropertyIPTCCredit as String: "Credit",
		kCGImagePropertyIPTCDateCreated as String: "Date Created",
		kCGImagePropertyIPTCHeadline as String: "Headline",
		kCGImagePropertyIPTCKeywords as String: "Keywords",
		kCGImagePropertyIPTCObjectName as String: "Title",
		kCGImagePropertyIPTCProvinceState as String: "State/Province",
		kCGImagePropertyIPTCSource as String: "Source",
		kCGImagePropertyIPTCSpecialInstructions as String: "Instructions",
		kCGImagePropertyIPTCSupplementalCategory as String: "Supplemental Categories",
		kCGImagePropertyIPTCTimeCreated as String: "Time Created",
	]
}

// MARK: - Row view

private struct MetadataRowView: View {
	let row: MetadataRow

	var body: some View {
		if row.subItems.isEmpty {
			SimpleMetadataRow(key: row.key, value: row.value)
		} else {
			ExpandedMetadataRow(key: row.key, items: row.subItems)
		}
	}
}

// Single key → single value row
private struct SimpleMetadataRow: View {
	let key: String
	let value: String
	@State private var copied = false
	@State private var expanded = false

	private static let truncationLimit = 400

	private var isTruncatable: Bool { value.count > Self.truncationLimit }
	private var displayValue: String {
		guard isTruncatable && !expanded else { return value }
		return String(value.prefix(Self.truncationLimit)) + "…"
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .top, spacing: 8) {
				Text(key)
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
					.frame(width: 130, alignment: .leading)
					.lineLimit(2)
					.fixedSize(horizontal: false, vertical: true)

				Text(displayValue)
					.font(.system(size: 12))
					.frame(maxWidth: .infinity, alignment: .leading)
					.textSelection(.enabled)
					.fixedSize(horizontal: false, vertical: true)

				copyButton(value: value, copied: $copied)
			}
			.padding(.horizontal, 20)
			.padding(.top, 5)
			.padding(.bottom, isTruncatable ? 2 : 5)

			if isTruncatable {
				Button {
					withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
				} label: {
					Text(expanded ? "Show less" : "Show more")
						.font(.system(size: 11))
						.foregroundStyle(.blue)
				}
				.buttonStyle(.plain)
				.padding(.leading, 158)
				.padding(.bottom, 5)
				.accessibilityLabel(expanded ? "Collapse \(key)" : "Expand \(key)")
			}
		}
		.contentShape(Rectangle())
	}
}

// Single key → multiple values, each on its own line with its own copy button
private struct ExpandedMetadataRow: View {
	let key: String
	let items: [String]
	@State private var copiedAll = false

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(spacing: 8) {
				Text(key)
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
					.frame(width: 130, alignment: .leading)
				Spacer()
				Button {
					let joined = items.joined(separator: "\n")
					NSPasteboard.general.clearContents()
					NSPasteboard.general.setString(joined, forType: .string)
					withAnimation(.easeInOut(duration: 0.15)) { copiedAll = true }
					Task {
						try? await Task.sleep(nanoseconds: 1_500_000_000)
						withAnimation(.easeInOut(duration: 0.15)) { copiedAll = false }
					}
				} label: {
					Image(systemName: copiedAll ? "checkmark" : "doc.on.doc")
						.font(.system(size: 10))
						.foregroundStyle(copiedAll ? .green : .secondary)
						.frame(width: 20, height: 20)
				}
				.buttonStyle(.plain)
				.help("Copy all to clipboard")
				.accessibilityLabel("Copy all \(key) values to clipboard")
			}
			.padding(.horizontal, 20)
			.padding(.top, 5)
			.padding(.bottom, 2)

			ForEach(Array(items.enumerated()), id: \.offset) { _, item in
				SubItemRow(value: item, parentKey: key)
			}
		}
		.contentShape(Rectangle())
	}
}

private struct SubItemRow: View {
	let value: String
	let parentKey: String
	@State private var copied = false

	var body: some View {
		HStack(alignment: .top, spacing: 8) {
			Image(systemName: "circle.fill")
				.font(.system(size: 4))
				.foregroundStyle(.secondary)
				.padding(.top, 4)
				.frame(width: 10, alignment: .center)

			Text(value)
				.font(.system(size: 12))
				.frame(maxWidth: .infinity, alignment: .leading)
				.textSelection(.enabled)
				.fixedSize(horizontal: false, vertical: true)

			copyButton(value: value, copied: $copied)
		}
		.padding(.leading, 30)
		.padding(.trailing, 20)
		.padding(.vertical, 3)
	}
}

// Shared copy button used by both row types
private func copyButton(value: String, copied: Binding<Bool>) -> some View {
	Button {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(value, forType: .string)
		withAnimation(.easeInOut(duration: 0.15)) { copied.wrappedValue = true }
		Task {
			try? await Task.sleep(nanoseconds: 1_500_000_000)
			withAnimation(.easeInOut(duration: 0.15)) { copied.wrappedValue = false }
		}
	} label: {
		Image(systemName: copied.wrappedValue ? "checkmark" : "doc.on.doc")
			.font(.system(size: 10))
			.foregroundStyle(copied.wrappedValue ? .green : .secondary)
			.frame(width: 20, height: 20)
	}
	.buttonStyle(.plain)
	.help("Copy to clipboard")
}

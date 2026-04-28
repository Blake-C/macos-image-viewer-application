import Foundation

// MARK: - Data model

struct ComfyUIWorkflow {
	struct LoRA {
		let name: String
		let strengthModel: Double?
		let strengthClip: Double?
	}

	struct KSamplerInfo {
		let seed: Int64?
		let steps: Int?
		let stepsRange: String?    // "7–20" when linked to RandomInt with no runtime value
		let cfg: Double?
		let samplerName: String?
		let scheduler: String?
		let denoise: Double?
		let denoiseRange: String?  // "0.6–1.0" when linked to RandomFloat with no runtime value
	}

	let checkpointName: String?
	let vae: String?
	let loras: [LoRA]
	let upscaleModel: String?
	let clipNames: [String]       // DualCLIPLoader (FLUX)
	let controlNets: [String]     // ControlNetLoader
	let ipAdapters: [String]      // IPAdapterModelLoader / IPAdapterUnifiedLoader
	let ollamaModel: String?
	let ollamaEnhancedPrompt: String?
	let randomPrompts: [String]
	let appendText: String?
	let positivePrompt: String?
	let negativePrompt: String?
	let ksamplers: [KSamplerInfo]
	let generationSize: (Int, Int)?  // EmptyLatentImage width × height
	let sourceFilename: String?
	let outputDirectory: String?
	let workflowNotes: [String]   // MarkdownNote content
}

// MARK: - Parser

enum ComfyUIWorkflowParser {
	/// Returns nil if the string is not valid ComfyUI workflow JSON.
	static func parse(from jsonString: String) -> ComfyUIWorkflow? {
		// Unescape XML/HTML entities that XMP-stored JSON may contain.
		// WebP uses XMP (XML), so bare `&` in the JSON gets written as `&amp;`.
		// Must run before NaN replacement so we don't double-process anything.
		let entityDecoded = jsonString
			.replacingOccurrences(of: "&amp;",  with: "&")
			.replacingOccurrences(of: "&lt;",   with: "<")
			.replacingOccurrences(of: "&gt;",   with: ">")
			.replacingOccurrences(of: "&quot;", with: "\"")
			.replacingOccurrences(of: "&apos;", with: "'")
			.replacingOccurrences(of: "&#39;",  with: "'")

		// ComfyUI emits bare NaN tokens (invalid JSON); replace before parsing.
		let sanitized = entityDecoded
			.replacingOccurrences(of: ": NaN", with: ": null")
			.replacingOccurrences(of: ":NaN",  with: ":null")
			.replacingOccurrences(of: "[NaN]", with: "[null]")

		guard let data = sanitized.data(using: .utf8),
		      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return nil }

		// Support both top-level {"prompt":…} and wrapped {"params":{"prompt":…, "workflow":…}}
		let container = (root["params"] as? [String: Any]) ?? root
		guard let prompt = container["prompt"] as? [String: Any] else { return nil }

		let runtime       = container["_runtime_values"] as? [String: Any] ?? [:]
		let workflowNodes = (container["workflow"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []

		return ComfyUIWorkflow(
			checkpointName:  extractCheckpoint(prompt: prompt, runtime: runtime),
			vae:             extractVAE(prompt: prompt),
			loras:           extractLoRAs(prompt: prompt, runtime: runtime, workflowNodes: workflowNodes),
			upscaleModel:    extractUpscaleModel(prompt: prompt),
			clipNames:       extractClipNames(prompt: prompt),
			controlNets:     extractControlNets(prompt: prompt),
			ipAdapters:      extractIPAdapters(prompt: prompt),
			ollamaModel:     extractOllamaModel(prompt: prompt),
			ollamaEnhancedPrompt: extractOllamaOutput(prompt: prompt, runtime: runtime),
			randomPrompts:   extractRandomPrompts(prompt: prompt),
			appendText:      extractAppendText(prompt: prompt),
			positivePrompt:  extractPositivePrompt(prompt: prompt, runtime: runtime),
			negativePrompt:  extractNegativePrompt(prompt: prompt, runtime: runtime),
			ksamplers:       extractKSamplers(prompt: prompt, runtime: runtime),
			generationSize:  extractGenerationSize(prompt: prompt),
			sourceFilename:  extractSourceFilename(prompt: prompt, runtime: runtime),
			outputDirectory: extractOutputDirectory(prompt: prompt),
			workflowNotes:   extractWorkflowNotes(from: workflowNodes)
		)
	}

	// MARK: - Field extractors

	private static func extractCheckpoint(prompt: [String: Any], runtime: [String: Any]) -> String? {
		let loaderTypes: Set<String> = ["CheckpointLoaderByName", "CheckpointLoaderSimple"]
		for (_, node) in prompt {
			guard let n = node as? [String: Any],
			      let classType = n["class_type"] as? String,
			      let inputs = n["inputs"] as? [String: Any]
			else { continue }
			if loaderTypes.contains(classType), let raw = inputs["ckpt_name"] {
				if let str = raw as? String { return str }
				if let ref = raw as? [Any],
				   let nodeId = ref.first as? String,
				   let resolved = runtime[nodeId] as? String { return resolved }
			}
			// FLUX: model and CLIP are split; UNETLoader carries the diffusion model name
			if classType == "UNETLoader", let name = inputs["unet_name"] as? String {
				return name
			}
		}
		return nil
	}

	private static func extractVAE(prompt: [String: Any]) -> String? {
		for (_, node) in prompt {
			guard let n = node as? [String: Any],
			      n["class_type"] as? String == "VAELoader",
			      let inputs = n["inputs"] as? [String: Any]
			else { continue }
			return inputs["vae_name"] as? String
		}
		return nil
	}

	private static func extractLoRAs(
		prompt: [String: Any],
		runtime: [String: Any],
		workflowNodes: [[String: Any]]
	) -> [ComfyUIWorkflow.LoRA] {
		let loraTypes: Set<String> = ["LoraLoader", "LoraLoaderModelOnly"]
		let fromPrompt = prompt.keys
			.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
			.compactMap { key -> ComfyUIWorkflow.LoRA? in
				guard let n = prompt[key] as? [String: Any],
				      let classType = n["class_type"] as? String,
				      loraTypes.contains(classType),
				      let inputs = n["inputs"] as? [String: Any],
				      let name = inputs["lora_name"] as? String
				else { return nil }
				return ComfyUIWorkflow.LoRA(
					name: name,
					strengthModel: resolveDouble(inputs["strength_model"], runtime: runtime),
					strengthClip:  resolveDouble(inputs["strength_clip"],  runtime: runtime)
				)
			}
		if !fromPrompt.isEmpty { return fromPrompt }

		// Bypassed LoRA nodes are absent from the API prompt but present in workflow.nodes
		let workflowLoraTypes: Set<String> = ["LoraLoader", "LoraLoaderModelOnly"]
		return workflowNodes
			.filter { workflowLoraTypes.contains($0["type"] as? String ?? "") }
			.sorted { ($0["id"] as? Int ?? 0) < ($1["id"] as? Int ?? 0) }
			.compactMap { node -> ComfyUIWorkflow.LoRA? in
				guard let values = node["widgets_values"] as? [Any],
				      let name = values.first as? String
				else { return nil }
				let sm = values.count > 1 ? (values[1] as? NSNumber)?.doubleValue : nil
				let sc = values.count > 2 ? (values[2] as? NSNumber)?.doubleValue : nil
				return ComfyUIWorkflow.LoRA(name: name, strengthModel: sm, strengthClip: sc)
			}
	}

	private static func extractClipNames(prompt: [String: Any]) -> [String] {
		for (_, node) in prompt {
			guard let n = node as? [String: Any],
			      n["class_type"] as? String == "DualCLIPLoader",
			      let inputs = n["inputs"] as? [String: Any]
			else { continue }
			return [inputs["clip_name1"], inputs["clip_name2"]]
				.compactMap { $0 as? String }
		}
		return []
	}

	private static func extractControlNets(prompt: [String: Any]) -> [String] {
		prompt.values.compactMap { node -> String? in
			guard let n = node as? [String: Any],
			      n["class_type"] as? String == "ControlNetLoader",
			      let inputs = n["inputs"] as? [String: Any]
			else { return nil }
			return inputs["control_net_name"] as? String
		}
	}

	private static func extractIPAdapters(prompt: [String: Any]) -> [String] {
		let types: Set<String> = ["IPAdapterModelLoader", "IPAdapterUnifiedLoader"]
		return prompt.values.compactMap { node -> String? in
			guard let n = node as? [String: Any],
			      let classType = n["class_type"] as? String,
			      types.contains(classType),
			      let inputs = n["inputs"] as? [String: Any]
			else { return nil }
			return (inputs["ipadapter_file"] ?? inputs["preset"]) as? String
		}
	}

	private static func extractOllamaModel(prompt: [String: Any]) -> String? {
		for (_, node) in prompt {
			guard let n = node as? [String: Any],
			      n["class_type"] as? String == "OllamaPromptEnhancer",
			      let inputs = n["inputs"] as? [String: Any]
			else { continue }
			return inputs["ollama_model"] as? String
		}
		return nil
	}

	private static func extractOllamaOutput(prompt: [String: Any], runtime: [String: Any]) -> String? {
		for (nodeId, node) in prompt {
			guard let n = node as? [String: Any],
			      n["class_type"] as? String == "OllamaPromptEnhancer"
			else { continue }
			return runtime[nodeId] as? String
		}
		return nil
	}

	private static func extractRandomPrompts(prompt: [String: Any]) -> [String] {
		for (_, node) in prompt {
			guard let n = node as? [String: Any],
			      n["class_type"] as? String == "RandomTextPrompt",
			      let inputs = n["inputs"] as? [String: Any]
			else { continue }
			var result: [String] = []
			var i = 1
			while let p = inputs["prompt_\(i)"] as? String {
				result.append(p)
				i += 1
			}
			return result
		}
		return []
	}

	private static func extractAppendText(prompt: [String: Any]) -> String? {
		for (_, node) in prompt {
			guard let n = node as? [String: Any],
			      n["class_type"] as? String == "RandomTextPrompt",
			      let inputs = n["inputs"] as? [String: Any]
			else { continue }
			return inputs["append_text"] as? String
		}
		return nil
	}

	private static func extractPositivePrompt(prompt: [String: Any], runtime: [String: Any]) -> String? {
		for (_, node) in prompt {
			guard let n = node as? [String: Any],
			      let classType = n["class_type"] as? String,
			      let inputs = n["inputs"] as? [String: Any]
			else { continue }
			switch classType {
			case "KSampler", "KSamplerAdvanced":
				guard let ref = inputs["positive"] as? [Any],
				      let nodeId = ref.first as? String
				else { continue }
				return resolveConditioningText(nodeId: nodeId, prompt: prompt, runtime: runtime)
			case "KSamplerByName":
				return resolveString(inputs["positive_text"], runtime: runtime)
			case "SamplerCustomAdvanced":
				return extractSamplerCustomPositive(from: inputs, prompt: prompt, runtime: runtime)
			default:
				continue
			}
		}
		return nil
	}

	private static func extractNegativePrompt(prompt: [String: Any], runtime: [String: Any]) -> String? {
		for (_, node) in prompt {
			guard let n = node as? [String: Any],
			      let classType = n["class_type"] as? String,
			      let inputs = n["inputs"] as? [String: Any]
			else { continue }
			switch classType {
			case "KSampler", "KSamplerAdvanced":
				guard let ref = inputs["negative"] as? [Any],
				      let nodeId = ref.first as? String
				else { continue }
				return resolveConditioningText(nodeId: nodeId, prompt: prompt, runtime: runtime)
			case "KSamplerByName":
				return resolveString(inputs["negative_text"], runtime: runtime)
			case "SamplerCustomAdvanced":
				return extractSamplerCustomNegative(from: inputs, prompt: prompt, runtime: runtime)
			default:
				continue
			}
		}
		return nil
	}

	// Traces SamplerCustomAdvanced → guider → conditioning for the positive prompt
	private static func extractSamplerCustomPositive(
		from inputs: [String: Any],
		prompt: [String: Any],
		runtime: [String: Any]
	) -> String? {
		guard let guiderRef = inputs["guider"] as? [Any],
		      let guiderId = guiderRef.first as? String,
		      let guiderNode = prompt[guiderId] as? [String: Any],
		      let guiderInputs = guiderNode["inputs"] as? [String: Any]
		else { return nil }
		let condKey = (guiderNode["class_type"] as? String) == "CFGGuider" ? "positive" : "conditioning"
		guard let condRef = guiderInputs[condKey] as? [Any],
		      let condId = condRef.first as? String
		else { return nil }
		return resolveConditioningText(nodeId: condId, prompt: prompt, runtime: runtime)
	}

	// CFGGuider carries a separate negative input; BasicGuider (FLUX) does not
	private static func extractSamplerCustomNegative(
		from inputs: [String: Any],
		prompt: [String: Any],
		runtime: [String: Any]
	) -> String? {
		guard let guiderRef = inputs["guider"] as? [Any],
		      let guiderId = guiderRef.first as? String,
		      let guiderNode = prompt[guiderId] as? [String: Any],
		      guiderNode["class_type"] as? String == "CFGGuider",
		      let guiderInputs = guiderNode["inputs"] as? [String: Any],
		      let negRef = guiderInputs["negative"] as? [Any],
		      let negId = negRef.first as? String
		else { return nil }
		return resolveConditioningText(nodeId: negId, prompt: prompt, runtime: runtime)
	}

	/// Follows conditioning references to their text source, handling pass-through
	/// nodes (FluxGuidance, BasicGuider, CFGGuider) and FLUX text encoders.
	private static func resolveConditioningText(
		nodeId: String,
		prompt: [String: Any],
		runtime: [String: Any],
		depth: Int = 0
	) -> String? {
		guard depth < 8,
		      let node = prompt[nodeId] as? [String: Any],
		      let inputs = node["inputs"] as? [String: Any]
		else { return nil }

		switch node["class_type"] as? String {
		case "CLIPTextEncode":
			return inputs["text"] as? String

		case "CLIPTextEncodeFlux", "CLIPTextEncodeSD3":
			// t5xxl carries the full detailed prompt; clip_l/clip_g are shorter alternatives
			for key in ["t5xxl", "clip_l", "clip_g"] {
				if let t = inputs[key] as? String,
				   !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
			}
			return nil

		// Pass-through nodes: follow their single conditioning input
		case "FluxGuidance", "BasicGuider":
			guard let ref = inputs["conditioning"] as? [Any],
			      let refId = ref.first as? String
			else { return nil }
			return resolveConditioningText(nodeId: refId, prompt: prompt, runtime: runtime, depth: depth + 1)

		case "CFGGuider":
			guard let ref = inputs["positive"] as? [Any],
			      let refId = ref.first as? String
			else { return nil }
			return resolveConditioningText(nodeId: refId, prompt: prompt, runtime: runtime, depth: depth + 1)

		case "RandomConditioning":
			// Runtime value is a 1-based index into the conditioning_N inputs
			let idx = (runtime[nodeId] as? NSNumber)?.intValue ?? 1
			let key = "conditioning_\(idx)"
			let ref = (inputs[key] as? [Any]) ?? (inputs["conditioning_1"] as? [Any])
			guard let refId = ref?.first as? String else { return nil }
			return resolveConditioningText(nodeId: refId, prompt: prompt, runtime: runtime, depth: depth + 1)

		default:
			return nil
		}
	}

	private static func extractKSamplers(
		prompt: [String: Any],
		runtime: [String: Any]
	) -> [ComfyUIWorkflow.KSamplerInfo] {
		let samplerTypes: Set<String> = ["KSampler", "KSamplerByName", "KSamplerAdvanced"]
		var results = prompt.keys
			.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
			.compactMap { key -> ComfyUIWorkflow.KSamplerInfo? in
				guard let n = prompt[key] as? [String: Any],
				      let classType = n["class_type"] as? String,
				      samplerTypes.contains(classType),
				      let inputs = n["inputs"] as? [String: Any]
				else { return nil }
				let steps   = resolveInt(inputs["steps"],   runtime: runtime)
				let denoise = resolveDouble(inputs["denoise"], runtime: runtime)
				return ComfyUIWorkflow.KSamplerInfo(
					seed:         (inputs["seed"] as? NSNumber)?.int64Value,
					steps:        steps,
					stepsRange:   steps   == nil ? resolveIntRangeString(inputs["steps"],   prompt: prompt) : nil,
					cfg:          resolveDouble(inputs["cfg"],          runtime: runtime),
					samplerName:  resolveString(inputs["sampler_name"], runtime: runtime),
					scheduler:    resolveString(inputs["scheduler"],    runtime: runtime),
					denoise:      denoise,
					denoiseRange: denoise == nil ? resolveDoubleRangeString(inputs["denoise"], prompt: prompt) : nil
				)
			}
		// SamplerCustomAdvanced (newer ComfyUI sampler API used by many FLUX workflows)
		if let custom = extractSamplerCustomAdvanced(prompt: prompt, runtime: runtime) {
			results.append(custom)
		}
		return results
	}

	// Traces SamplerCustomAdvanced's noise/sampler/sigmas/guider subgraph
	private static func extractSamplerCustomAdvanced(
		prompt: [String: Any],
		runtime: [String: Any]
	) -> ComfyUIWorkflow.KSamplerInfo? {
		for (_, node) in prompt {
			guard let n = node as? [String: Any],
			      n["class_type"] as? String == "SamplerCustomAdvanced",
			      let inputs = n["inputs"] as? [String: Any]
			else { continue }

			// Seed: noise → RandomNoise.noise_seed
			var seed: Int64?
			if let ref = inputs["noise"] as? [Any],
			   let nId = ref.first as? String,
			   let nn = prompt[nId] as? [String: Any],
			   nn["class_type"] as? String == "RandomNoise",
			   let ni = nn["inputs"] as? [String: Any] {
				seed = (ni["noise_seed"] as? NSNumber)?.int64Value
			}

			// Sampler name: sampler → KSamplerSelect.sampler_name
			var samplerName: String?
			if let ref = inputs["sampler"] as? [Any],
			   let sId = ref.first as? String,
			   let sn = prompt[sId] as? [String: Any],
			   sn["class_type"] as? String == "KSamplerSelect",
			   let si = sn["inputs"] as? [String: Any] {
				samplerName = si["sampler_name"] as? String
			}

			// Steps, scheduler, denoise: sigmas → BasicScheduler / KarrasScheduler
			var steps: Int?;       var stepsRange: String?
			var scheduler: String?
			var denoise: Double?;  var denoiseRange: String?
			let schedTypes: Set<String> = ["BasicScheduler", "KarrasScheduler", "ExponentialScheduler"]
			if let ref = inputs["sigmas"] as? [Any],
			   let scId = ref.first as? String,
			   let scNode = prompt[scId] as? [String: Any],
			   let scClass = scNode["class_type"] as? String,
			   schedTypes.contains(scClass),
			   let scIn = scNode["inputs"] as? [String: Any] {
				steps       = resolveInt(scIn["steps"],   runtime: runtime)
				stepsRange  = steps   == nil ? resolveIntRangeString(scIn["steps"],   prompt: prompt) : nil
				scheduler   = resolveString(scIn["scheduler"], runtime: runtime) ?? scClass
				denoise     = resolveDouble(scIn["denoise"], runtime: runtime)
				denoiseRange = denoise == nil ? resolveDoubleRangeString(scIn["denoise"], prompt: prompt) : nil
			}

			// CFG: guider → CFGGuider.cfg (BasicGuider has no cfg)
			var cfg: Double?
			if let ref = inputs["guider"] as? [Any],
			   let gId = ref.first as? String,
			   let gNode = prompt[gId] as? [String: Any],
			   gNode["class_type"] as? String == "CFGGuider",
			   let gIn = gNode["inputs"] as? [String: Any] {
				cfg = resolveDouble(gIn["cfg"], runtime: runtime)
			}

			return ComfyUIWorkflow.KSamplerInfo(
				seed: seed, steps: steps, stepsRange: stepsRange,
				cfg: cfg, samplerName: samplerName, scheduler: scheduler,
				denoise: denoise, denoiseRange: denoiseRange
			)
		}
		return nil
	}

	private static func extractGenerationSize(prompt: [String: Any]) -> (Int, Int)? {
		for (_, node) in prompt {
			guard let n = node as? [String: Any],
			      n["class_type"] as? String == "EmptyLatentImage",
			      let inputs = n["inputs"] as? [String: Any],
			      let w = (inputs["width"]  as? NSNumber)?.intValue,
			      let h = (inputs["height"] as? NSNumber)?.intValue,
			      w > 0, h > 0
			else { continue }
			return (w, h)
		}
		return nil
	}

	private static func extractSourceFilename(prompt: [String: Any], runtime: [String: Any]) -> String? {
		let fileLoaderTypes: Set<String> = ["LoadImageWithFilename", "WorkflowFromImage"]
		for (nodeId, node) in prompt {
			guard let n = node as? [String: Any],
			      let classType = n["class_type"] as? String
			else { continue }
			if classType == "RandomImageFromDirectory" {
				return runtime[nodeId] as? String
			}
			if fileLoaderTypes.contains(classType),
			   let inputs = n["inputs"] as? [String: Any],
			   let image = inputs["image"] as? String {
				if let dir = inputs["directory"] as? String {
					let slash = dir.hasSuffix("/") ? "" : "/"
					return "\(dir)\(slash)\(image)"
				}
				return image
			}
		}
		return nil
	}

	private static func extractUpscaleModel(prompt: [String: Any]) -> String? {
		for (_, node) in prompt {
			guard let n = node as? [String: Any],
			      n["class_type"] as? String == "UpscaleModelLoader",
			      let inputs = n["inputs"] as? [String: Any]
			else { continue }
			return inputs["model_name"] as? String
		}
		return nil
	}

	private static func extractOutputDirectory(prompt: [String: Any]) -> String? {
		for (_, node) in prompt {
			guard let n = node as? [String: Any],
			      n["class_type"] as? String == "SaveImageAs",
			      let inputs = n["inputs"] as? [String: Any],
			      let dir = inputs["directory"] as? String
			else { continue }
			return dir
		}
		return nil
	}

	private static func extractWorkflowNotes(from nodes: [[String: Any]]) -> [String] {
		nodes
			.filter { ($0["type"] as? String) == "MarkdownNote" }
			.compactMap { node -> String? in
				guard let values = node["widgets_values"] as? [Any],
				      let text = values.first as? String
				else { return nil }
				let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
				return trimmed.count > 5 ? trimmed : nil
			}
	}

	// MARK: - Raw file XMP reader

	/// Reads workflow JSON directly from raw file bytes, bypassing the system
	/// XMP/IPTC parser that truncates strings at unescaped `&` characters.
	static func extractWorkflowJSON(from url: URL) -> String? {
		guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
		let ext = url.pathExtension.lowercased()
		let xmp: String?
		switch ext {
		case "webp":         xmp = extractWebPXMP(from: data)
		case "jpg", "jpeg":  xmp = extractJPEGXMP(from: data)
		default:             xmp = nil
		}
		guard let xmpString = xmp else { return nil }
		return extractJSONFromXMP(xmpString)
	}

	private static func extractWebPXMP(from data: Data) -> String? {
		guard data.count > 12,
		      data[0..<4] == Data("RIFF".utf8),
		      data[8..<12] == Data("WEBP".utf8)
		else { return nil }
		let xmpFourCC = Data("XMP ".utf8)
		var offset = 12
		while offset + 8 <= data.count {
			let fourCC = data[offset..<offset+4]
			let size   = Int(data[offset+4])
			             | Int(data[offset+5]) << 8
			             | Int(data[offset+6]) << 16
			             | Int(data[offset+7]) << 24
			let start = offset + 8
			let end   = min(start + size, data.count)
			if fourCC == xmpFourCC {
				return String(data: data[start..<end], encoding: .utf8)
			}
			offset = start + size + (size & 1)
		}
		return nil
	}

	private static func extractJPEGXMP(from data: Data) -> String? {
		guard let headerData = "http://ns.adobe.com/xap/1.0/\0".data(using: .ascii) else { return nil }
		var offset = 2
		while offset + 4 <= data.count {
			guard data[offset] == 0xFF else { break }
			let marker      = data[offset + 1]
			let segLen      = Int(data[offset+2]) << 8 | Int(data[offset+3])
			let contentStart = offset + 4
			let contentEnd   = min(offset + 2 + segLen, data.count)
			if marker == 0xE1,
			   contentStart + headerData.count <= contentEnd,
			   data[contentStart..<contentStart + headerData.count] == headerData {
				return String(data: data[contentStart + headerData.count..<contentEnd], encoding: .utf8)
			}
			offset += 2 + segLen
		}
		return nil
	}

	private static func extractJSONFromXMP(_ xmp: String) -> String? {
		let decoded = xmp
			.replacingOccurrences(of: "&amp;",  with: "&")
			.replacingOccurrences(of: "&lt;",   with: "<")
			.replacingOccurrences(of: "&gt;",   with: ">")
			.replacingOccurrences(of: "&quot;", with: "\"")
			.replacingOccurrences(of: "&apos;", with: "'")
			.replacingOccurrences(of: "&#39;",  with: "'")
		let markers = ["{\"prompt\":", "{\"params\":", "{\"file\":"]
		guard let startIdx = markers.compactMap({ decoded.range(of: $0)?.lowerBound }).min()
		else { return nil }
		var depth = 0; var inStr = false; var escaped = false; var endIdx: String.Index?
		for idx in decoded[startIdx...].indices {
			let c = decoded[idx]
			if escaped            { escaped = false; continue }
			if c == "\\" && inStr { escaped = true;  continue }
			if c == "\""          { inStr.toggle();  continue }
			if inStr              { continue }
			if c == "{"           { depth += 1 }
			else if c == "}"      { depth -= 1; if depth == 0 { endIdx = idx; break } }
		}
		guard let end = endIdx else { return nil }
		return String(decoded[startIdx...end])
	}

	// MARK: - Value resolution helpers

	private static func resolveString(_ value: Any?, runtime: [String: Any]) -> String? {
		guard let value else { return nil }
		if let str = value as? String { return str }
		if let ref = value as? [Any],
		   let nodeId = ref.first as? String,
		   let resolved = runtime[nodeId] as? String { return resolved }
		return nil
	}

	private static func resolveDouble(_ value: Any?, runtime: [String: Any]) -> Double? {
		guard let value else { return nil }
		if let n = value as? NSNumber { return n.doubleValue }
		if let ref = value as? [Any],
		   let nodeId = ref.first as? String,
		   let resolved = runtime[nodeId] as? NSNumber { return resolved.doubleValue }
		return nil
	}

	private static func resolveInt(_ value: Any?, runtime: [String: Any]) -> Int? {
		guard let value else { return nil }
		if let n = value as? NSNumber { return n.intValue }
		if let ref = value as? [Any],
		   let nodeId = ref.first as? String,
		   let resolved = runtime[nodeId] as? NSNumber { return resolved.intValue }
		return nil
	}

	// When a value is a ref to a RandomInt/RandomFloat with no runtime capture,
	// return a formatted range string ("7–20") instead of nil.
	private static func resolveIntRangeString(_ value: Any?, prompt: [String: Any]) -> String? {
		guard let ref = value as? [Any],
		      let nodeId = ref.first as? String,
		      let node = prompt[nodeId] as? [String: Any],
		      node["class_type"] as? String == "RandomInt",
		      let inputs = node["inputs"] as? [String: Any],
		      let lo = (inputs["min_value"] as? NSNumber)?.intValue,
		      let hi = (inputs["max_value"] as? NSNumber)?.intValue
		else { return nil }
		return "\(lo)–\(hi)"
	}

	private static func resolveDoubleRangeString(_ value: Any?, prompt: [String: Any]) -> String? {
		guard let ref = value as? [Any],
		      let nodeId = ref.first as? String,
		      let node = prompt[nodeId] as? [String: Any],
		      node["class_type"] as? String == "RandomFloat",
		      let inputs = node["inputs"] as? [String: Any],
		      let lo = (inputs["min_value"] as? NSNumber)?.doubleValue,
		      let hi = (inputs["max_value"] as? NSNumber)?.doubleValue
		else { return nil }
		return "\(String(format: "%.2g", lo))–\(String(format: "%.2g", hi))"
	}
}

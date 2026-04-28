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
		let cfg: Double?
		let samplerName: String?
		let scheduler: String?
		let denoise: Double?
	}

	let checkpointName: String?
	let vae: String?
	let loras: [LoRA]
	let upscaleModel: String?
	let ollamaModel: String?
	let ollamaEnhancedPrompt: String?
	let randomPrompts: [String]
	let appendText: String?
	let positivePrompt: String?
	let negativePrompt: String?
	let ksamplers: [KSamplerInfo]
	let sourceFilename: String?
	let outputDirectory: String?
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
			.replacingOccurrences(of: ":NaN", with: ":null")
			.replacingOccurrences(of: "[NaN]", with: "[null]")

		guard let data = sanitized.data(using: .utf8),
		      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return nil }

		// Support both top-level {"prompt":…} and wrapped {"params":{"prompt":…, "workflow":…}}
		let container = (root["params"] as? [String: Any]) ?? root
		guard let prompt = container["prompt"] as? [String: Any] else { return nil }

		let runtime = container["_runtime_values"] as? [String: Any] ?? [:]
		let workflowNodes = (container["workflow"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []

		return ComfyUIWorkflow(
			checkpointName: extractCheckpoint(prompt: prompt, runtime: runtime),
			vae: extractVAE(prompt: prompt),
			loras: extractLoRAs(prompt: prompt, runtime: runtime, workflowNodes: workflowNodes),
			upscaleModel: extractUpscaleModel(prompt: prompt),
			ollamaModel: extractOllamaModel(prompt: prompt),
			ollamaEnhancedPrompt: extractOllamaOutput(prompt: prompt, runtime: runtime),
			randomPrompts: extractRandomPrompts(prompt: prompt),
			appendText: extractAppendText(prompt: prompt),
			positivePrompt: extractPositivePrompt(prompt: prompt, runtime: runtime),
			negativePrompt: extractNegativePrompt(prompt: prompt, runtime: runtime),
			ksamplers: extractKSamplers(prompt: prompt, runtime: runtime),
			sourceFilename: extractSourceFilename(prompt: prompt, runtime: runtime),
			outputDirectory: extractOutputDirectory(prompt: prompt)
		)
	}

	// MARK: - Field extractors

	private static func extractCheckpoint(prompt: [String: Any], runtime: [String: Any]) -> String? {
		let loaderTypes: Set<String> = ["CheckpointLoaderByName", "CheckpointLoaderSimple"]
		for (_, node) in prompt {
			guard let n = node as? [String: Any],
			      let classType = n["class_type"] as? String,
			      loaderTypes.contains(classType),
			      let inputs = n["inputs"] as? [String: Any],
			      let raw = inputs["ckpt_name"]
			else { continue }
			if let str = raw as? String { return str }
			if let ref = raw as? [Any],
			   let nodeId = ref.first as? String,
			   let resolved = runtime[nodeId] as? String { return resolved }
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
		let fromPrompt = prompt.keys
			.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
			.compactMap { key -> ComfyUIWorkflow.LoRA? in
				guard let n = prompt[key] as? [String: Any],
				      n["class_type"] as? String == "LoraLoader",
				      let inputs = n["inputs"] as? [String: Any],
				      let name = inputs["lora_name"] as? String
				else { return nil }
				return ComfyUIWorkflow.LoRA(
					name: name,
					strengthModel: resolveDouble(inputs["strength_model"], runtime: runtime),
					strengthClip: resolveDouble(inputs["strength_clip"], runtime: runtime)
				)
			}
		if !fromPrompt.isEmpty { return fromPrompt }

		// Bypassed LoRA nodes are absent from the API prompt but present in workflow.nodes
		return workflowNodes
			.filter { ($0["type"] as? String) == "LoraLoader" }
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
			case "KSampler":
				guard let posRef = inputs["positive"] as? [Any],
				      let posNodeId = posRef.first as? String
				else { continue }
				return resolveConditioningText(nodeId: posNodeId, prompt: prompt, runtime: runtime)
			case "KSamplerByName":
				return resolveString(inputs["positive_text"], runtime: runtime)
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
			case "KSampler":
				guard let negRef = inputs["negative"] as? [Any],
				      let negNodeId = negRef.first as? String
				else { continue }
				return resolveConditioningText(nodeId: negNodeId, prompt: prompt, runtime: runtime)
			case "KSamplerByName":
				return resolveString(inputs["negative_text"], runtime: runtime)
			default:
				continue
			}
		}
		return nil
	}

	/// Follows conditioning references to their CLIPTextEncode source.
	/// Handles RandomConditioning by using the runtime-captured selection index.
	private static func resolveConditioningText(
		nodeId: String,
		prompt: [String: Any],
		runtime: [String: Any],
		depth: Int = 0
	) -> String? {
		guard depth < 5,
		      let node = prompt[nodeId] as? [String: Any],
		      let inputs = node["inputs"] as? [String: Any]
		else { return nil }

		switch node["class_type"] as? String {
		case "CLIPTextEncode":
			return inputs["text"] as? String

		case "RandomConditioning":
			// Runtime value is a 1-based index into the conditioning_N inputs
			let idx = (runtime[nodeId] as? NSNumber)?.intValue ?? 1
			let key = "conditioning_\(idx)"
			let ref = (inputs[key] as? [Any]) ?? (inputs["conditioning_1"] as? [Any])
			guard let refNodeId = ref?.first as? String else { return nil }
			return resolveConditioningText(nodeId: refNodeId, prompt: prompt, runtime: runtime, depth: depth + 1)

		default:
			return nil
		}
	}

	private static func extractKSamplers(
		prompt: [String: Any],
		runtime: [String: Any]
	) -> [ComfyUIWorkflow.KSamplerInfo] {
		let samplerTypes: Set<String> = ["KSampler", "KSamplerByName"]
		return prompt.keys
			.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
			.compactMap { key -> ComfyUIWorkflow.KSamplerInfo? in
				guard let n = prompt[key] as? [String: Any],
				      let classType = n["class_type"] as? String,
				      samplerTypes.contains(classType),
				      let inputs = n["inputs"] as? [String: Any]
				else { return nil }
				return ComfyUIWorkflow.KSamplerInfo(
					seed: (inputs["seed"] as? NSNumber)?.int64Value,
					steps: resolveInt(inputs["steps"], runtime: runtime),
					cfg: resolveDouble(inputs["cfg"], runtime: runtime),
					samplerName: resolveString(inputs["sampler_name"], runtime: runtime),
					scheduler: resolveString(inputs["scheduler"], runtime: runtime),
					denoise: resolveDouble(inputs["denoise"], runtime: runtime)
				)
			}
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
		// RIFF header: "RIFF" (4) + LE size (4) + "WEBP" (4), then chunks
		guard data.count > 12,
		      data[0..<4] == Data("RIFF".utf8),
		      data[8..<12] == Data("WEBP".utf8)
		else { return nil }
		let xmpFourCC = Data("XMP ".utf8)
		var offset = 12
		while offset + 8 <= data.count {
			let fourCC = data[offset..<offset+4]
			let size = Int(data[offset+4])
			             | Int(data[offset+5]) << 8
			             | Int(data[offset+6]) << 16
			             | Int(data[offset+7]) << 24
			let start = offset + 8
			let end   = min(start + size, data.count)
			if fourCC == xmpFourCC {
				return String(data: data[start..<end], encoding: .utf8)
			}
			offset = start + size + (size & 1) // chunks pad to even boundary
		}
		return nil
	}

	private static func extractJPEGXMP(from data: Data) -> String? {
		// XMP is in an APP1 (0xFFE1) segment prefixed with the XMP namespace URI + NUL
		guard let headerData = "http://ns.adobe.com/xap/1.0/\0".data(using: .ascii) else { return nil }
		var offset = 2 // skip SOI
		while offset + 4 <= data.count {
			guard data[offset] == 0xFF else { break }
			let marker = data[offset + 1]
			let segLen  = Int(data[offset+2]) << 8 | Int(data[offset+3])
			let contentStart = offset + 4
			let contentEnd   = min(offset + 2 + segLen, data.count)
			if marker == 0xE1,
			   contentStart + headerData.count <= contentEnd,
			   data[contentStart..<contentStart + headerData.count] == headerData {
				let xmpStart = contentStart + headerData.count
				return String(data: data[xmpStart..<contentEnd], encoding: .utf8)
			}
			offset += 2 + segLen
		}
		return nil
	}

	private static func extractJSONFromXMP(_ xmp: String) -> String? {
		// Entity-decode so raw `&` (or `&amp;`) both survive to JSON
		let decoded = xmp
			.replacingOccurrences(of: "&amp;",  with: "&")
			.replacingOccurrences(of: "&lt;",   with: "<")
			.replacingOccurrences(of: "&gt;",   with: ">")
			.replacingOccurrences(of: "&quot;", with: "\"")
			.replacingOccurrences(of: "&apos;", with: "'")
			.replacingOccurrences(of: "&#39;",  with: "'")
		// Find the first ComfyUI JSON root object
		let markers = ["{\"prompt\":", "{\"params\":", "{\"file\":"]
		guard let startIdx = markers.compactMap({ decoded.range(of: $0)?.lowerBound }).min()
		else { return nil }
		// Walk forward counting brace depth to find the matching close
		var depth   = 0
		var inStr   = false
		var escaped = false
		var endIdx: String.Index?
		for idx in decoded[startIdx...].indices {
			let c = decoded[idx]
			if escaped          { escaped = false; continue }
			if c == "\\" && inStr { escaped = true;  continue }
			if c == "\""        { inStr.toggle();    continue }
			if inStr            { continue }
			if      c == "{"    { depth += 1 }
			else if c == "}"    { depth -= 1; if depth == 0 { endIdx = idx; break } }
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
		   let resolved = runtime[nodeId] as? NSNumber {
			return resolved.doubleValue
		}
		return nil
	}

	private static func resolveInt(_ value: Any?, runtime: [String: Any]) -> Int? {
		guard let value else { return nil }
		if let n = value as? NSNumber { return n.intValue }
		if let ref = value as? [Any],
		   let nodeId = ref.first as? String,
		   let resolved = runtime[nodeId] as? NSNumber {
			return resolved.intValue
		}
		return nil
	}
}

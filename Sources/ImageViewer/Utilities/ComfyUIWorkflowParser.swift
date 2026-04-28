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
	let ollamaModel: String?
	let ollamaEnhancedPrompt: String?
	let randomPrompts: [String]
	let appendText: String?
	let negativePrompt: String?
	let ksamplers: [KSamplerInfo]
	let sourceFilename: String?
	let outputDirectory: String?
}

// MARK: - Parser

enum ComfyUIWorkflowParser {
	/// Returns nil if the string is not valid ComfyUI workflow JSON.
	static func parse(from jsonString: String) -> ComfyUIWorkflow? {
		// ComfyUI emits bare NaN tokens (invalid JSON); replace before parsing.
		let sanitized = jsonString
			.replacingOccurrences(of: ": NaN", with: ": null")
			.replacingOccurrences(of: ":NaN", with: ":null")
			.replacingOccurrences(of: "[NaN]", with: "[null]")

		guard let data = sanitized.data(using: .utf8),
		      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let prompt = root["prompt"] as? [String: Any]
		else { return nil }

		let runtime = root["_runtime_values"] as? [String: Any] ?? [:]

		return ComfyUIWorkflow(
			checkpointName: extractCheckpoint(prompt: prompt, runtime: runtime),
			vae: extractVAE(prompt: prompt),
			loras: extractLoRAs(prompt: prompt, runtime: runtime),
			ollamaModel: extractOllamaModel(prompt: prompt),
			ollamaEnhancedPrompt: extractOllamaOutput(prompt: prompt, runtime: runtime),
			randomPrompts: extractRandomPrompts(prompt: prompt),
			appendText: extractAppendText(prompt: prompt),
			negativePrompt: extractNegativePrompt(prompt: prompt),
			ksamplers: extractKSamplers(prompt: prompt, runtime: runtime),
			sourceFilename: extractSourceFilename(prompt: prompt, runtime: runtime),
			outputDirectory: extractOutputDirectory(prompt: prompt)
		)
	}

	// MARK: - Field extractors

	private static func extractCheckpoint(prompt: [String: Any], runtime: [String: Any]) -> String? {
		for (_, node) in prompt {
			guard let n = node as? [String: Any],
			      n["class_type"] as? String == "CheckpointLoaderByName",
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

	private static func extractLoRAs(prompt: [String: Any], runtime: [String: Any]) -> [ComfyUIWorkflow.LoRA] {
		prompt.keys
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

	private static func extractNegativePrompt(prompt: [String: Any]) -> String? {
		// Find KSampler's "negative" input, then read that node's text
		for (_, node) in prompt {
			guard let n = node as? [String: Any],
			      n["class_type"] as? String == "KSampler",
			      let inputs = n["inputs"] as? [String: Any],
			      let negRef = inputs["negative"] as? [Any],
			      let negNodeId = negRef.first as? String,
			      let negNode = prompt[negNodeId] as? [String: Any],
			      let negInputs = negNode["inputs"] as? [String: Any],
			      let text = negInputs["text"] as? String
			else { continue }
			return text
		}
		return nil
	}

	private static func extractKSamplers(
		prompt: [String: Any],
		runtime: [String: Any]
	) -> [ComfyUIWorkflow.KSamplerInfo] {
		prompt.keys
			.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
			.compactMap { key -> ComfyUIWorkflow.KSamplerInfo? in
				guard let n = prompt[key] as? [String: Any],
				      n["class_type"] as? String == "KSampler",
				      let inputs = n["inputs"] as? [String: Any]
				else { return nil }
				return ComfyUIWorkflow.KSamplerInfo(
					seed: (inputs["seed"] as? NSNumber)?.int64Value,
					steps: resolveInt(inputs["steps"], runtime: runtime),
					cfg: resolveDouble(inputs["cfg"], runtime: runtime),
					samplerName: inputs["sampler_name"] as? String,
					scheduler: inputs["scheduler"] as? String,
					denoise: resolveDouble(inputs["denoise"], runtime: runtime)
				)
			}
	}

	private static func extractSourceFilename(prompt: [String: Any], runtime: [String: Any]) -> String? {
		for (nodeId, node) in prompt {
			guard let n = node as? [String: Any],
			      n["class_type"] as? String == "RandomImageFromDirectory"
			else { continue }
			return runtime[nodeId] as? String
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

	// MARK: - Value resolution helpers

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

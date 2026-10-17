import Foundation
import CoreGraphics
import ImageIO
import FoundationModels

/// Apple's on-device language model (with vision on iOS 27). Nothing leaves the
/// phone. Every call returns nil when the model isn't there — older phones,
/// Apple Intelligence off, model still downloading — and callers fall back to
/// keyword logic.
enum Intelligence {
    static var available: Bool {
        if #available(iOS 26.0, macOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        return false
    }

    static var canSee: Bool {
        if #available(iOS 27.0, macOS 27.0, *) {
            let model = SystemLanguageModel.default
            return imageAttachmentsShipped && model.isAvailable && model.capabilities.contains(.vision)
        }
        return false
    }

    /// Early iOS 27 builds report `.vision` but ship without the image `Attachment`
    /// initializer, and calling it would crash. Check that the symbol really exists.
    private static let imageAttachmentsShipped: Bool =
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), // RTLD_DEFAULT
              "$s16FoundationModels10AttachmentVA2A05ImageC7ContentVRszrlE_11orientationACyAEGSo10CGImageRefa_So0G19PropertyOrientationVSgtcfC") != nil

    static var status: String {
        canSee ? "On-device AI · vision" : available ? "On-device AI" : "Keyword mode"
    }

    /// One plain sentence describing a camera frame, for the search index.
    static func caption(jpeg: Data) async -> String? {
        guard canSee, let image = cgImage(jpeg) else { return nil }
        if #available(iOS 27.0, macOS 27.0, *) {
            let session = LanguageModelSession(instructions: """
                You describe frames from a home security camera for a search index. \
                Reply with one short sentence in plain words naming animals, people, \
                vehicles and what they are doing. If nothing is happening, describe the scene.
                """)
            do {
                let response: LanguageModelSession.Response<String> = try await session.respond {
                    "Describe this frame."
                    Attachment<ImageAttachmentContent>(image)
                }
                return tidy(response.content)
            } catch {
                return nil
            }
        }
        return nil
    }

    /// Extra search words for a plain-language query, e.g. "birds on the railing" → bird, pigeon, gull.
    static func keywords(for query: String) async -> [String]? {
        guard available else { return nil }
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
                You turn questions about home security camera footage into search keywords. \
                Use single lowercase words for things a camera could see: fox, pigeon, bird, gull, \
                rat, squirrel, person, cat, dog, hedgehog, car, rain, light, movement. Include synonyms.
                """)
            guard let r = try? await session.respond(to: query, generating: KeywordDraft.self) else { return nil }
            return r.content.keywords.map { $0.lowercased() }.filter { !$0.isEmpty }
        }
        return nil
    }

    /// Answers a question from the activity log (and a couple of key frames if the model can see).
    static func answer(_ question: String, log: String, frames: [Data]) async -> String? {
        guard available else { return nil }
        if #available(iOS 26.0, macOS 26.0, *) {
            let instructions = """
                You are SHOO, a phone on a windowsill watching for pests. Answer the user's question \
                using only the activity log. Two or three short sentences. Mention times. \
                If the log shows nothing relevant, say you saw nothing.
                """
            let session = LanguageModelSession(instructions: instructions)
            do {
                if #available(iOS 27.0, macOS 27.0, *), canSee {
                    let images = frames.compactMap(cgImage).prefix(2)
                    let response: LanguageModelSession.Response<String> = try await session.respond {
                        "Activity log:\n\(log)"
                        for image in images { Attachment<ImageAttachmentContent>(image) }
                        "Question: \(question)"
                    }
                    return tidy(response.content)
                }
                let response = try await session.respond(to: "Activity log:\n\(log)\n\nQuestion: \(question)")
                return tidy(response.content)
            } catch {
                return nil
            }
        }
        return nil
    }

    /// Turns "if a fox shows up at night, flash the lamp and tell me" into a rule.
    static func rule(from text: String) async -> RuleDraftResult? {
        guard available else { return nil }
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
                You turn a sentence into a home camera automation rule. Triggers: pest (an animal \
                like fox, pigeon, gull, rat, squirrel), person, friend (cat, dog, hedgehog), motion, \
                keyword (something described in the scene). Actions: deter (play a scare sound), \
                lamp (flash the light), notify (send a notification), webhook (call a URL). \
                Hours are 0-23; use -1 when no time is given.
                """)
            guard let r = try? await session.respond(to: text, generating: RuleDraft.self) else { return nil }
            let d = r.content
            return RuleDraftResult(trigger: d.trigger, species: d.species, keyword: d.keyword,
                                   fromHour: d.fromHour, toHour: d.toHour, actions: d.actions)
        }
        return nil
    }

    // MARK: - Helpers

    static func cgImage(_ jpeg: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func tidy(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n\n", with: "\n")
    }
}

/// Plain values so callers needn't know about FoundationModels types.
struct RuleDraftResult {
    var trigger: String
    var species: [String]
    var keyword: String
    var fromHour: Int
    var toHour: Int
    var actions: [String]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct KeywordDraft {
    @Guide(description: "Single lowercase words to search for", .count(1...8))
    var keywords: [String]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct RuleDraft {
    @Guide(description: "What starts the rule", .anyOf(["pest", "person", "friend", "motion", "keyword"]))
    var trigger: String
    @Guide(description: "Pest species named, from: pigeon, gull, fox, rat, squirrel. Empty means any pest.")
    var species: [String]
    @Guide(description: "For keyword triggers, the word to look for in the scene. Otherwise empty.")
    var keyword: String
    @Guide(description: "Hour the rule starts being active, 0-23, or -1 for all day", .range(-1...23))
    var fromHour: Int
    @Guide(description: "Hour the rule stops being active, 0-23, or -1 for all day", .range(-1...23))
    var toHour: Int
    @Guide(description: "What to do", .count(1...4))
    var actions: [String]
}

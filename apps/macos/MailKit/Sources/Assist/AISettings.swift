import Foundation
import MailCore
import Observation

/// A model and how hard it thinks, for one feature.
public struct ModelChoice: Codable, Equatable, Sendable {
    public var model: String
    public var reasoning: Reasoning

    public init(model: String, reasoning: Reasoning) {
        self.model = model
        self.reasoning = reasoning
    }
}

/// Your AI setup on this device: the provider, its key and what each feature uses. The key lives in the keychain, one per
/// provider so switching back keeps it; the rest in UserDefaults. Model choices are per provider too, since every
/// provider names models its own way.
@MainActor
@Observable
public final class AISettings {
    public enum Feature: String, Sendable { case completion, labelling }

    public var provider: AIProvider {
        didSet {
            guard provider != oldValue else { return }
            defaults.set(provider.rawValue, forKey: "ai.provider")
            key = Keychain.read(Self.keyName(provider)) ?? ""
            completion = Self.choice(.completion, for: provider)
            labelling = Self.choice(.labelling, for: provider)
        }
    }

    public var key: String {
        didSet {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { Keychain.delete(Self.keyName(provider)) } else { Keychain.write(trimmed, for: Self.keyName(provider)) }
        }
    }

    public var isCompletionOn: Bool {
        didSet { defaults.set(isCompletionOn, forKey: "ai.completion.on") }
    }

    public var isLabellingOn: Bool {
        didSet {
            defaults.set(isLabellingOn, forKey: "ai.labelling.on")
            // Labelling starts with mail that arrives from now on. Older mail was triaged already.
            if isLabellingOn, !oldValue { labellingSince = .now }
        }
    }

    /// When auto labelling was last turned on. Only conversations newer than this get labelled.
    public private(set) var labellingSince: Date? {
        didSet { defaults.set(labellingSince, forKey: "ai.labelling.since") }
    }

    public var completion: ModelChoice {
        didSet { save(completion, .completion) }
    }

    public var labelling: ModelChoice {
        didSet { save(labelling, .labelling) }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    public init() {
        let provider = UserDefaults.standard.string(forKey: "ai.provider").flatMap(AIProvider.init(rawValue:)) ?? .anthropic
        self.provider = provider
        key = Keychain.read(Self.keyName(provider)) ?? ""
        isCompletionOn = UserDefaults.standard.bool(forKey: "ai.completion.on")
        isLabellingOn = UserDefaults.standard.bool(forKey: "ai.labelling.on")
        labellingSince = UserDefaults.standard.object(forKey: "ai.labelling.since") as? Date
        completion = Self.choice(.completion, for: provider)
        labelling = Self.choice(.labelling, for: provider)
    }

    /// A client for the provider, once there's a key.
    public var client: AIClient? {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : AIClient(provider: provider, key: key)
    }

    /// Forgets every key, for signing out: the next person to sign in on this device shouldn't spend yours.
    public func forget() {
        for provider in AIProvider.allCases { Keychain.delete(Self.keyName(provider)) }
        key = ""
        isCompletionOn = false
        isLabellingOn = false
    }

    // MARK: - Storage

    private static func keyName(_ provider: AIProvider) -> String { "ai.key.\(provider.rawValue)" }

    private static func choice(_ feature: Feature, for provider: AIProvider) -> ModelChoice {
        if let data = UserDefaults.standard.data(forKey: "ai.\(provider.rawValue).\(feature.rawValue)"),
            let choice = try? JSONDecoder().decode(ModelChoice.self, from: data) {
            return choice
        }
        // Completion has to keep up with your typing, so it doesn't think. Labelling happens in the background and
        // gets it right more often when it does.
        return ModelChoice(model: provider.defaultModel, reasoning: feature == .completion ? .off : .xhigh)
    }

    private func save(_ choice: ModelChoice, _ feature: Feature) {
        defaults.set(try? JSONEncoder().encode(choice), forKey: "ai.\(provider.rawValue).\(feature.rawValue)")
    }
}

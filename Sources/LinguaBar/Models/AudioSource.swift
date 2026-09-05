// AI-Author: Codex (OpenAI gpt-5.6-sol)
import Foundation

struct AudioSource: Identifiable, Hashable, Sendable {
    enum Target: Hashable, Sendable {
        case system
        case process(pid_t)
        case unavailable
    }

    let id: String
    let label: String
    let bundleIdentifier: String?
    let isActive: Bool
    let target: Target

    static let system = AudioSource(
        id: "system",
        label: "所有系统音频",
        bundleIdentifier: nil,
        isActive: true,
        target: .system
    )

    static let googleChromeID = "app:google-chrome"
    static let googleMeetID = "app:google-meet"
    static let microsoftTeamsID = "app:microsoft-teams"

    var isAvailable: Bool {
        target != .unavailable
    }

    var persistenceIdentifier: String {
        if id == Self.system.id { return Self.system.id }
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier)"
        }
        return "label:\(label)"
    }

    static func restoredSource(
        matching persistenceIdentifier: String,
        in sources: [AudioSource]
    ) -> AudioSource? {
        sources.first {
            $0.persistenceIdentifier == persistenceIdentifier && $0.isAvailable
        }
    }

    static func menuCandidates(from detectedSources: [AudioSource]) -> [AudioSource] {
        let applications = detectedSources.filter { $0.id != system.id }
        let chrome = applications.first(where: isGoogleChrome)
        let meet = applications.first(where: isGoogleMeet)
        let teams = applications.first(where: isMicrosoftTeams)

        let fixedCandidates = [
            candidate(
                id: googleChromeID,
                label: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                backing: chrome
            ),
            candidate(
                id: googleMeetID,
                label: "Google Meet",
                bundleIdentifier: "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan",
                backing: meet ?? chrome
            ),
            candidate(
                id: microsoftTeamsID,
                label: "Microsoft Teams",
                bundleIdentifier: "com.microsoft.teams2",
                backing: teams
            ),
        ]

        let additionalApplications = applications.filter {
            !isGoogleChrome($0) && !isGoogleMeet($0) && !isMicrosoftTeams($0)
        }
        .sorted {
            if $0.isActive != $1.isActive { return $0.isActive }
            return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }

        return fixedCandidates + additionalApplications + [.system]
    }

    static func isMeetingApp(label: String, bundleIdentifier: String?) -> Bool {
        let haystack = ([label, bundleIdentifier ?? ""])
            .joined(separator: " ")
            .lowercased()
        return ["google chrome", "google meet", "microsoft teams", "teams", "zoom", "webex"]
            .contains { haystack.contains($0) }
    }

    static func preferredDefault(in sources: [AudioSource]) -> AudioSource {
        func matches(_ source: AudioSource, terms: [String]) -> Bool {
            let haystack = ([source.label, source.bundleIdentifier ?? ""])
                .joined(separator: " ")
                .lowercased()
            return terms.contains { haystack.contains($0) }
        }

        if let meet = sources.first(where: {
            $0.isAvailable &&
            matches($0, terms: ["google meet", "kjgfgldnnfoeklkmfkjfagphfepbbdan"])
        }) {
            return meet
        }
        if let chrome = sources.first(where: {
            $0.isAvailable &&
            matches($0, terms: ["google chrome", "com.google.chrome"])
        }) {
            return chrome
        }
        return sources.first(where: { $0.id == system.id }) ?? system
    }

    private static func candidate(
        id: String,
        label: String,
        bundleIdentifier: String,
        backing: AudioSource?
    ) -> AudioSource {
        AudioSource(
            id: id,
            label: label,
            bundleIdentifier: bundleIdentifier,
            isActive: backing?.isActive ?? false,
            target: backing?.target ?? .unavailable
        )
    }

    private static func isGoogleChrome(_ source: AudioSource) -> Bool {
        source.bundleIdentifier == "com.google.Chrome" ||
            source.label.localizedCaseInsensitiveCompare("Google Chrome") == .orderedSame
    }

    private static func isGoogleMeet(_ source: AudioSource) -> Bool {
        let haystack = ([source.label, source.bundleIdentifier ?? ""])
            .joined(separator: " ")
            .lowercased()
        return haystack.contains("google meet") ||
            haystack.contains("kjgfgldnnfoeklkmfkjfagphfepbbdan")
    }

    private static func isMicrosoftTeams(_ source: AudioSource) -> Bool {
        let haystack = ([source.label, source.bundleIdentifier ?? ""])
            .joined(separator: " ")
            .lowercased()
        return haystack.contains("microsoft teams") ||
            haystack.contains("com.microsoft.teams")
    }
}

/// The wizard's steps for a given choice of features. Pure, so the order is
/// pinned by tests rather than by reading a view.
enum OnboardingFlow {
    enum Step: Equatable, CaseIterable {
        case welcome, features, permissions, speechModel, typingModel, screenText, tryIt, pill, more, finish
    }

    /// `typingSeen`: the Type page was reached. It stays in the list even if
    /// Type is switched off there — that page is where you try it and decide.
    static func steps(dictation: Bool, type: Bool, typingSeen: Bool = false) -> [Step] {
        let typing = type || typingSeen
        // Nothing chosen: the wizard cannot continue past the choice.
        guard dictation || typing else { return [.welcome, .features] }
        var s: [Step] = [.welcome, .features, .permissions]
        if dictation { s.append(.speechModel) }
        if typing { s.append(.typingModel) }
        // Screen Recording is optional and only Type uses it, so it gets its
        // own page, where there is room to say why (user, 2026-10-12).
        if type { s.append(.screenText) }
        s.append(.tryIt)
        if dictation { s.append(.pill) }
        s += [.more, .finish]
        return s
    }

    static func needsMicrophone(dictation: Bool) -> Bool { dictation }
}

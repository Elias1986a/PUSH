/// The wizard's steps for a given choice of features. Pure, so the order is
/// pinned by tests rather than by reading a view.
enum OnboardingFlow {
    enum Step: Equatable {
        case welcome, features, permissions, speechModel, typingModel, tryIt, pill, more, finish
    }

    static func steps(dictation: Bool, type: Bool) -> [Step] {
        // Nothing chosen: the wizard cannot continue past the choice.
        guard dictation || type else { return [.welcome, .features] }
        var s: [Step] = [.welcome, .features, .permissions]
        if dictation { s.append(.speechModel) }
        if type { s.append(.typingModel) }
        s.append(.tryIt)
        if dictation { s.append(.pill) }
        s += [.more, .finish]
        return s
    }

    static func needsMicrophone(dictation: Bool) -> Bool { dictation }
}

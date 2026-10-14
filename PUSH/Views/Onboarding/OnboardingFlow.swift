/// The wizard's steps for a given choice of features. Pure, so the order is
/// pinned by tests rather than by reading a view.
enum OnboardingFlow {
    enum Step: Equatable, CaseIterable {
        case otherMac, welcome, licence, features, permissions, speechModel, typingModel, personal, screenText, tryIt, finish
    }

    /// `typingSeen`: the Type page was reached. It stays in the list even if
    /// Type is switched off there — that page is where you try it and decide.
    /// `licence`: the store is open, so the licence page comes right after the
    /// welcome (already done when the thank-you page's Activate was clicked).
    /// `otherMac`: iCloud has something from another Mac, so the wizard opens by
    /// asking whether to copy it. `copied`: the answer was yes, which makes the
    /// welcome and the "make it sound like you" page redundant (both are in
    /// what was copied); permissions and downloads still happen on this Mac.
    static func steps(dictation: Bool, type: Bool, typingSeen: Bool = false, licence: Bool = false,
                      otherMac: Bool = false, copied: Bool = false) -> [Step] {
        let typing = type || typingSeen
        var start: [Step] = otherMac ? [.otherMac] : []
        if !(otherMac && copied) { start.append(.welcome) }
        if licence { start.append(.licence) }
        // Nothing chosen: the wizard cannot continue past the choice.
        guard dictation || typing else { return start + [.features] }
        var s: [Step] = start + [.features, .permissions]
        if dictation { s.append(.speechModel) }
        if typing { s.append(.typingModel) }
        // Who you are and whether it learns: Type's biggest difference from a
        // plain autocomplete, so it gets a page rather than a Settings pane
        // nobody opens. Skipped when it was copied from another Mac.
        if type && !copied { s.append(.personal) }
        // Screen Recording is optional and only Type uses it, so it gets its
        // own page, where there is room to say why (user, 2026-10-12).
        if type { s.append(.screenText) }
        // The pill's position sits on Try it, and the wake word and teleprompter
        // on the last page: two pages fewer (user, 2026-10-12).
        s += [.tryIt, .finish]
        return s
    }

    static func needsMicrophone(dictation: Bool) -> Bool { dictation }
}

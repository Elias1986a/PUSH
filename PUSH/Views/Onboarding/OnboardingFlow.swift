/// The wizard's steps for a given choice of features. Pure, so the order is
/// pinned by tests rather than by reading a view.
enum OnboardingFlow {
    enum Step: Equatable, CaseIterable {
        case otherMac, welcome, licence, features, permissions, speechModel, typingModel, personal, tryIt, finish
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
        // The welcome carries the Talk and TYPE switches (user, 2026-10-14:
        // ten pages down to eight). Copying from another Mac skips the welcome,
        // so then the switches get their own page, since they are per Mac.
        let welcome = !(otherMac && copied)
        if welcome { start.append(.welcome) }
        if licence { start.append(.licence) }
        if !welcome { start.append(.features) }
        // Nothing chosen: the wizard cannot continue past the choice.
        guard dictation || typing else { return start }
        var s: [Step] = start + [.permissions]
        if dictation { s.append(.speechModel) }
        if typing { s.append(.typingModel) }
        // "Make it yours": who you are, whether it learns, and whether it may
        // read the screen. TYPE's biggest difference from a plain autocomplete,
        // so a page rather than a Settings pane nobody opens. One page since
        // 2026-10-14 (was two: personal, then screen text).
        if type { s.append(.personal) }
        // The pill's position sits on Try it, and the wake word and teleprompter
        // on the last page: two pages fewer (user, 2026-10-12).
        s += [.tryIt, .finish]
        return s
    }

    static func needsMicrophone(dictation: Bool) -> Bool { dictation }
}

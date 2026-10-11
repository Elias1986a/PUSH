/// Where the text sent to the model starts, for a field longer than the window.
///
/// Taking simply the last N characters moves the window's start on every
/// keystroke once a field is longer than N, so the prompt's beginning changes,
/// the KV cache no longer matches and the whole window is processed again on
/// every key. The start instead moves in fixed steps from the field's
/// beginning: between steps every keystroke only appends.
public enum PromptWindow {
    public static let step = 512

    /// Character offset to start from; `length - start` is at most `maximum`.
    public static func start(length: Int, maximum: Int, step: Int = step) -> Int {
        guard length > maximum else { return 0 }
        let excess = length - maximum
        return (excess + step - 1) / step * step
    }
}

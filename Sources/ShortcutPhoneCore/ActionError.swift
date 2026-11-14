/// Why a press did nothing.
public enum ActionError: Error, Equatable, Sendable {
    case wrongApp(expected: String, actual: String?)
    case noAccessibility
    case launchFailed(bundleId: String)
    /// The page couldn't be opened (no such browser, or the browser refused the URL).
    case openFailed(url: String)
    case unknownButton(id: String)

    /// The code sent to the phone.
    public var pressError: PressError {
        switch self {
        case .wrongApp: .wrongApp
        case .noAccessibility: .noAccessibility
        case .launchFailed, .openFailed: .launchFailed
        case .unknownButton: .unknownButton
        }
    }
}

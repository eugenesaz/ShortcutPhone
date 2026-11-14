/// The app that currently has focus on the Mac.
public protocol FrontmostAppProvider: Sendable {
    func current() async -> AppRef?
}

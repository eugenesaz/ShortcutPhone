import Foundation
import HummingbirdTesting
import HummingbirdWSTesting
import ShortcutPhoneCore
import Testing

@testable import ShortcutPhoneServer

extension LiveServerTests {
    @Suite(.timeLimit(.minutes(1))) struct StatePushTests {
        @Test func sendsStateAfterAuth() async throws {
            let agent = try TestAgent(frontmost: slack)
            let token = try await agent.pair().token
            try await agent.server.application().test(.live) { client in
                try await client.authedWS(token: token) { messages, _ in
                    guard case .state(let state) = try await messages.nextServerMessage() else {
                        Issue.record("expected state")
                        return
                    }
                    #expect(state.frontmost == slack)
                    #expect(state.page?.bundleId == slack.bundleId)
                    #expect(state.global.count == 2)
                }
            }
        }

        @Test func recordsFocusToStateForFocusPushesOnly() async throws {
            let timing = ServerRecordingTiming()
            let agent = try TestAgent(frontmost: slack, timing: timing)
            let token = try await agent.pair().token
            let hub = agent.hub
            try await agent.server.application().test(.live) { client in
                try await client.authedWS(token: token) { messages, _ in
                    _ = try await messages.nextServerMessage()  // state on auth: not timed
                    await hub.setFrontmost(finder, changedAt: .now)
                    _ = try await messages.nextServerMessage()
                }
            }
            #expect(timing.events == [.focusToState])
        }

        @Test func pushesStateWhenFrontmostChanges() async throws {
            let agent = try TestAgent(frontmost: slack)
            let token = try await agent.pair().token
            let hub = agent.hub
            try await agent.server.application().test(.live) { client in
                try await client.authedWS(token: token) { messages, _ in
                    _ = try await messages.nextServerMessage()

                    await hub.setFrontmost(finder)
                    guard case .state(let toFinder) = try await messages.nextServerMessage() else {
                        Issue.record("expected state")
                        return
                    }
                    #expect(toFinder.frontmost == finder)
                    #expect(toFinder.page == nil)

                    await hub.setFrontmost(slack)
                    guard case .state(let toSlack) = try await messages.nextServerMessage() else {
                        Issue.record("expected state")
                        return
                    }
                    #expect(toSlack.page?.buttons.count == 2)
                }
            }
        }

        @Test func pushesStateWhenConfigChanges() async throws {
            let agent = try TestAgent(frontmost: slack)
            let token = try await agent.pair().token
            let hub = agent.hub
            try await agent.server.application().test(.live) { client in
                try await client.authedWS(token: token) { messages, _ in
                    _ = try await messages.nextServerMessage()
                    await hub.setConfig(.empty)
                    guard case .state(let state) = try await messages.nextServerMessage() else {
                        Issue.record("expected state")
                        return
                    }
                    #expect(state.global.isEmpty)
                    #expect(state.page == nil)
                }
            }
        }

        @Test func pushesStateToEveryPhone() async throws {
            let agent = try TestAgent()
            let one = try await agent.pair().token
            let two = try await agent.pair().token
            let hub = agent.hub
            try await agent.server.application().test(.live) { client in
                async let first = client.firstPushedFrontmost(token: one)
                async let second = client.firstPushedFrontmost(token: two)
                while await hub.connectionCount < 2 { await Task.yield() }
                await hub.setFrontmost(finder)
                let (a, b) = try await (first, second)
                #expect(a == finder)
                #expect(b == finder)
            }
        }

        @Test func connectionCountDropsWhenPhoneLeaves() async throws {
            let agent = try TestAgent()
            let token = try await agent.pair().token
            let hub = agent.hub
            try await agent.server.application().test(.live) { client in
                try await client.authedWS(token: token) { messages, _ in
                    _ = try await messages.nextServerMessage()
                    #expect(await hub.connectionCount == 1)
                }
                try await waitUntil { await hub.connectionCount == 0 }
            }
        }
    }
}

extension TestClientProtocol {
    /// Connects, skips the initial state, and returns the frontmost app from the next push.
    func firstPushedFrontmost(token: String) async throws -> AppRef? {
        let result = Box<AppRef?>(nil)
        try await authedWS(token: token) { messages, _ in
            _ = try await messages.nextServerMessage()
            if case .state(let state) = try await messages.nextServerMessage() {
                await result.set(state.frontmost)
            }
        }
        return await result.value
    }
}

/// Polls `condition` for up to 2 s.
func waitUntil(_ condition: @Sendable () async -> Bool) async throws {
    for _ in 0..<400 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("condition not met within 2 s")
}

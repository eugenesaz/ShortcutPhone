import Foundation
import HummingbirdWebSocket
import ShortcutPhoneCore

/// One phone socket: the first message must be a valid `auth` within the timeout, or the
/// socket is closed with 4401. After that, `state` pushes flow out.
struct WebSocketSession {
    let hub: WebSocketHub
    let pairing: PairingService
    let dispatcher: PressDispatcher
    let authTimeout: Duration
    let timing: any TimingLog

    func run(inbound: WebSocketInboundStream, outbound: WebSocketOutboundWriter) async throws {
        let (id, outputs) = await hub.open()
        let timeout = Task { [hub, authTimeout] in
            try await Task.sleep(for: authTimeout)
            await hub.closeIfUnauthenticated(id)
        }
        defer { timeout.cancel() }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await write(outputs, to: outbound) }
                group.addTask { try await read(inbound, id: id) }
                // Whichever side finishes first (usually the phone leaving) ends both.
                try await group.next()
                group.cancelAll()
            }
        } catch {
            await hub.disconnect(id)
            throw error
        }
        await hub.disconnect(id)
    }

    private func write(
        _ outputs: AsyncStream<WebSocketHub.Output>, to outbound: WebSocketOutboundWriter
    ) async throws {
        let encoder = JSONEncoder()
        for await output in outputs {
            switch output {
            case .message(let message, let focusChangedAt):
                try await outbound.write(
                    .text(String(decoding: try encoder.encode(message), as: UTF8.self)))
                if let focusChangedAt { timing.record(.focusToState, .now - focusChangedAt) }
            case .close(let code):
                try await outbound.close(.unknown(code), reason: "unauthorized")
                return
            }
        }
    }

    private func read(_ inbound: WebSocketInboundStream, id: UUID) async throws {
        let decoder = JSONDecoder()
        var deviceId: String?
        for try await frame in inbound.messages(maxSize: AgentServer.maxMessageSize) {
            let receivedAt = ContinuousClock.now
            let message: ClientMessage? =
                if case .text(let text) = frame {
                    try? decoder.decode(ClientMessage.self, from: Data(text.utf8))
                } else { nil }

            guard let deviceId else {
                guard case .auth(let token)? = message, let verified = await pairing.verify(token)
                else {
                    await hub.close(id, code: WebSocketHub.unauthorizedCode)
                    continue
                }
                deviceId = verified
                await hub.authenticate(id, deviceId: verified)
                // A revoke that raced with this login must still win.
                if await pairing.verify(token) == nil {
                    await hub.close(id, code: WebSocketHub.unauthorizedCode)
                }
                continue
            }
            switch message {
            case .press(let pressId, let buttonId)?:
                // Handled inline, so one phone's presses run in the order they were tapped.
                let error = await press(buttonId, receivedAt: receivedAt)
                await hub.send(.result(pressId: pressId, error: error), to: id)
            case .viewport(let viewport)?:
                // Kept for capacity checks. A failed write only loses this report.
                if viewport.isPlausible { try? await pairing.setViewport(viewport, for: deviceId) }
            case .auth?, nil:
                break  // repeated auth and junk are ignored
            }
        }
    }

    private func press(_ buttonId: String, receivedAt: ContinuousClock.Instant) async -> PressError?
    {
        do {
            try await dispatcher.handle(
                buttonId: buttonId, config: await hub.currentConfig, receivedAt: receivedAt)
            return nil
        } catch {
            return error.pressError
        }
    }
}

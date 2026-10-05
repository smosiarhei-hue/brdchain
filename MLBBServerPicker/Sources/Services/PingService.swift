import Foundation
import Network

/// Measures TCP connect latency from the device to a host.
///
/// We time the three-way handshake (state -> .ready) rather than issuing an
/// HTTP request, so a gateway that only answers on its game port still yields
/// a meaningful number instead of a misleading 404.
enum PingService {

    struct Measurement: Sendable {
        let latencyMS: Double?
        let error: String?

        var summary: String {
            if let latencyMS { return String(format: "%.0f ms", latencyMS) }
            return error ?? "—"
        }
    }

    /// Resumes a continuation at most once. NWConnection can report `failed`
    /// and then `cancelled`, so without this the continuation would resume
    /// twice and trap.
    private final class OneShot: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Measurement, Never>?

        init(_ continuation: CheckedContinuation<Measurement, Never>) {
            self.continuation = continuation
        }

        func fire(_ measurement: Measurement) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: measurement)
        }
    }

    static func measure(host: String,
                        port: UInt16 = 443,
                        timeout: TimeInterval = 4.0) async -> Measurement {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            return Measurement(latencyMS: nil, error: "bad port")
        }

        let start = DispatchTime.now().uptimeNanoseconds
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: endpointPort,
                                      using: .tcp)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Measurement, Never>) in
                let shot = OneShot(continuation)

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        let elapsed = DispatchTime.now().uptimeNanoseconds - start
                        connection.cancel()
                        shot.fire(Measurement(latencyMS: Double(elapsed) / 1_000_000,
                                              error: nil))
                    case .failed(let error):
                        connection.cancel()
                        shot.fire(Measurement(latencyMS: nil,
                                              error: error.localizedDescription))
                    case .cancelled, .preparing, .waiting, .setup:
                        break
                    @unknown default:
                        break
                    }
                }

                connection.start(queue: .global(qos: .userInitiated))

                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                    connection.cancel()
                    shot.fire(Measurement(latencyMS: nil, error: "timeout"))
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }
}
import Dispatch
import Foundation
import Synchronization
import dnssd

nonisolated struct ServerAddress: Hashable, Sendable {
    let host: String
    let port: UInt16
}

/// Applies the `_minecraft._tcp.<host>` SRV record to server addresses that use the default port.
nonisolated enum ServerAddressResolver {
    static let defaultPort: UInt16 = 25565

    /// The SRV target and port with the lowest priority, then the highest weight.
    /// Without a record, or for another port or an IP address, the address stays unchanged.
    static func resolve(_ address: ServerAddress) async -> ServerAddress {
        guard address.port == defaultPort, !isIPAddress(address.host) else {
            return address
        }
        let records = await SRVLookup.records(for: "_minecraft._tcp.\(address.host)")
        guard let record = preferredRecord(records) else {
            return address
        }
        return ServerAddress(host: record.target, port: record.port)
    }

    static func preferredRecord(_ records: [SRVRecord]) -> SRVRecord? {
        records.min { first, second in
            if first.priority != second.priority {
                return first.priority < second.priority
            }
            return first.weight > second.weight
        }
    }

    private static func isIPAddress(_ host: String) -> Bool {
        host.contains(":") || host.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
    }
}

nonisolated struct SRVRecord: Hashable, Sendable {
    let priority: UInt16
    let weight: UInt16
    let port: UInt16
    /// The host name without the trailing dot.
    let target: String

    /// Parses SRV record data: priority, weight and port as big-endian 16-bit numbers, then the target as DNS labels.
    /// Nil for damaged data and for the `.` target, which means the service is not available.
    init?(recordData: Data) {
        let bytes = [UInt8](recordData)
        guard bytes.count > 6 else {
            return nil
        }
        func number(at index: Int) -> UInt16 {
            UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
        }
        var labels: [String] = []
        var index = 6
        while index < bytes.count, bytes[index] != 0 {
            let length = Int(bytes[index])
            index += 1
            guard length < 64, index + length <= bytes.count else {
                return nil
            }
            labels.append(String(decoding: bytes[index..<(index + length)], as: UTF8.self))
            index += length
        }
        guard !labels.isEmpty else {
            return nil
        }
        priority = number(at: 0)
        weight = number(at: 2)
        port = number(at: 4)
        target = labels.joined(separator: ".")
    }
}

/// Looks up SRV records with `DNSServiceQueryRecord`.
nonisolated enum SRVLookup {
    /// The records for `name`. Empty when none exist, the lookup fails, or no answer comes within `timeout`.
    static func records(for name: String, timeout: Duration = .seconds(3)) async -> [SRVRecord] {
        let query = SRVQuery()
        return await withCheckedContinuation { continuation in
            query.start(name: name, timeout: timeout, continuation: continuation)
        }
    }
}

/// One DNS-SD query. All work runs on `queue`, the dispatch queue that DNS-SD delivers answers on.
nonisolated private final class SRVQuery: Sendable {
    private struct State {
        var continuation: CheckedContinuation<[SRVRecord], Never>?
        var reference: DNSServiceRef?
        var records: [SRVRecord] = []
    }

    private let queue = DispatchQueue(label: "GoldenApple SRV lookup")
    private let state = Mutex(State())

    func start(name: String, timeout: Duration, continuation: CheckedContinuation<[SRVRecord], Never>) {
        queue.async {
            self.state.withLock { $0.continuation = continuation }
            var reference: DNSServiceRef?
            let status = DNSServiceQueryRecord(
                &reference,
                DNSServiceFlags(kDNSServiceFlagsReturnIntermediates),
                0,
                name,
                UInt16(kDNSServiceType_SRV),
                UInt16(kDNSServiceClass_IN),
                { _, flags, _, errorCode, _, recordType, _, length, data, _, context in
                    guard let context else {
                        return
                    }
                    let recordData = data.map { Data(bytes: $0, count: Int(length)) }
                    Unmanaged<SRVQuery>.fromOpaque(context).takeUnretainedValue()
                        .receive(flags: flags, errorCode: errorCode, recordType: recordType, recordData: recordData)
                },
                Unmanaged.passUnretained(self).toOpaque()
            )
            guard status == kDNSServiceErr_NoError, let reference else {
                self.finish()
                return
            }
            self.state.withLock { $0.reference = reference }
            DNSServiceSetDispatchQueue(reference, self.queue)
            // This closure also keeps the query alive while DNS-SD holds the unretained pointer.
            self.queue.asyncAfter(deadline: .now() + Self.seconds(timeout)) {
                self.finish()
            }
        }
    }

    private func receive(flags: DNSServiceFlags, errorCode: DNSServiceErrorType, recordType: UInt16, recordData: Data?) {
        guard errorCode == kDNSServiceErr_NoError else {
            finish()
            return
        }
        guard recordType == kDNSServiceType_SRV else {
            return
        }
        if flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0, let record = recordData.flatMap(SRVRecord.init(recordData:)) {
            state.withLock { $0.records.append(record) }
        }
        if flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) == 0 {
            finish()
        }
    }

    /// Ends the query once and returns the records found so far.
    private func finish() {
        let (continuation, reference, records) = state.withLock { state in
            defer {
                state.continuation = nil
                state.reference = nil
            }
            return (state.continuation, state.reference, state.records)
        }
        if let reference {
            DNSServiceRefDeallocate(reference)
        }
        continuation?.resume(returning: records)
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

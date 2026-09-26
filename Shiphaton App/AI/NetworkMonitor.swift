//
//  NetworkMonitor.swift
//  Shiphaton App
//
//  One answer to "are we online?", so an AI surface can say so up front
//  instead of leaving someone on a spinner until a request times out.
//

import Foundation
import Network

@MainActor
@Observable
final class NetworkMonitor {

    static let shared = NetworkMonitor()

    /// False only once the system has said so. Starts optimistic, so a
    /// cold launch never flashes an offline notice before the first path
    /// update has landed.
    private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "network-monitor", qos: .utility))
    }

    /// Call once at launch so the first answer is in hand before any
    /// screen needs it.
    func start() {}
}

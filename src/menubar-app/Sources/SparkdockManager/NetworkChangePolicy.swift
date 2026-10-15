import Network

/// The parts of a network path that decide whether update checks should rerun.
///
/// `NWPathMonitor` re-emits paths that differ only in details such as VPN tunnels,
/// gateways or DNS. On machines with Tailscale, a VPN or Docker networks that
/// happens every few seconds, so only connectivity and the physical interface
/// types are compared.
struct NetworkFingerprint: Equatable {
    let isSatisfied: Bool
    let interfaceTypes: Set<NWInterface.InterfaceType>

    static let physicalInterfaceTypes: Set<NWInterface.InterfaceType> = [.wifi, .wiredEthernet, .cellular]

    init(isSatisfied: Bool, interfaceTypes: Set<NWInterface.InterfaceType>) {
        self.isSatisfied = isSatisfied
        self.interfaceTypes = interfaceTypes.intersection(Self.physicalInterfaceTypes)
    }

    init(path: NWPath) {
        self.init(
            isSatisfied: path.status == .satisfied,
            interfaceTypes: Set(path.availableInterfaces.map(\.type))
        )
    }
}

/// Decides whether a network path update should trigger update checks.
enum NetworkChangePolicy {
    /// The first path only records a baseline: the app already checks at launch.
    /// After that, a check runs when the network is connected and either was not
    /// before or now goes through a different kind of interface.
    static func shouldCheck(previous: NetworkFingerprint?, current: NetworkFingerprint) -> Bool {
        guard let previous = previous else { return false }
        return current.isSatisfied && current != previous
    }
}

import 'dart:io';

import 'ipv4.dart';

/// One IPv4 address of a network adapter on this computer.
typedef HostAddress = ({String adapter, Ipv4 ip});

/// Lists this computer's IPv4 addresses. A boundary interface for fakes.
abstract interface class NetworkInterfaces {
  Future<List<HostAddress>> list();
}

/// Reads the real adapters with `dart:io`.
final class LocalNetworkInterfaces implements NetworkInterfaces {
  const LocalNetworkInterfaces({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  @override
  Future<List<HostAddress>> list() async {
    final adapters = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    ).timeout(timeout, onTimeout: () => const []);
    return [
      for (final adapter in adapters)
        for (final address in adapter.addresses)
          if (Ipv4.tryParse(address.address) case final ip?)
            (adapter: adapter.name, ip: ip),
    ];
  }
}

/// The addresses that can reach an Android device on the same Wi-Fi or
/// LAN: private IPv4 on a real adapter, sorted by adapter name.
///
/// Dropped: loopback, link-local (169.254, no DHCP answer), public and
/// CGNAT (100.64/10, used by Tailscale) addresses, and virtual adapters.
List<HostAddress> lanAddresses(Iterable<HostAddress> all) {
  final kept = [
    for (final a in all)
      if (a.ip.isPrivate && !isVirtualAdapter(a.adapter)) a,
  ]..sort((x, y) => x.adapter.compareTo(y.adapter));
  return kept;
}

/// True for VPN, container and virtual-machine adapters. Their addresses
/// never reach a tablet on the Wi-Fi, and choosing one breaks the subnet
/// check and the scan.
bool isVirtualAdapter(String adapter) {
  final name = adapter.toLowerCase();
  return _virtualPrefixes.any(name.startsWith) ||
      _virtualWords.any(name.contains);
}

/// Short names, matched only at the start ("tun0", "zt3abc", "br-12ab").
const _virtualPrefixes = {
  'utun', 'awdl', 'llw', 'bridge', 'br-', 'docker', 'veth', 'vmnet', //
  'vboxnet', 'tun', 'tap', 'zt', 'wg', 'ppp', 'ipsec', 'gif', 'stf', 'anpi',
  'virbr',
};

/// Longer words, matched anywhere (Windows uses long friendly names such
/// as "vEthernet (WSL)" or "VMware Network Adapter VMnet8").
const _virtualWords = {
  'vethernet', 'hyper-v', 'virtualbox', 'vmware', 'tailscale', 'zerotier', //
  'wireguard', 'vpn', 'loopback', 'pseudo',
};

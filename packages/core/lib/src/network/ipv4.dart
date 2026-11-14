/// An IPv4 address, stored as one 32-bit number.
final class Ipv4 implements Comparable<Ipv4> {
  const Ipv4._(this.value);

  /// Builds an address from its four parts, each 0 to 255.
  factory Ipv4.fromParts(int a, int b, int c, int d) {
    for (final part in [a, b, c, d]) {
      if (part < 0 || part > 255) {
        throw RangeError.range(part, 0, 255, 'part');
      }
    }
    return Ipv4._((a << 24) | (b << 16) | (c << 8) | d);
  }

  /// Reads `192.168.1.202`. Null for anything else: no leading zeros
  /// (`01` can mean octal), no spaces, no ports.
  static Ipv4? tryParse(String text) {
    final parts = text.split('.');
    if (parts.length != 4) return null;
    var value = 0;
    for (final part in parts) {
      if (!_part.hasMatch(part)) return null;
      final n = int.parse(part);
      if (n > 255) return null;
      value = (value << 8) | n;
    }
    return Ipv4._(value);
  }

  static final _part = RegExp(r'^(0|[1-9][0-9]{0,2})$');

  final int value;

  List<int> get parts => [
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];

  /// A private (RFC 1918) address: 10/8, 172.16/12 or 192.168/16. Only
  /// these are ever scanned, so a scan cannot leave the local network.
  bool get isPrivate {
    final [a, b, _, _] = parts;
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  /// The /24 network this address is in, as its `.0` address.
  Ipv4 get network24 => Ipv4._(value & 0xFFFFFF00);

  /// True when both are in the same /24 (`a.b.c.*`). Dart does not give
  /// the netmask, so adbwifi assumes /24, the usual home and office size.
  bool sameSubnet24(Ipv4 other) => network24 == other.network24;

  /// The address `.host` in this /24 network.
  Ipv4 withHost(int host) {
    if (host < 0 || host > 255) throw RangeError.range(host, 0, 255, 'host');
    return Ipv4._(network24.value | host);
  }

  /// The subnet as people write it, e.g. `192.168.1.0/24`.
  String get subnet24 => '$network24/24';

  @override
  bool operator ==(Object other) => other is Ipv4 && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  int compareTo(Ipv4 other) => value.compareTo(other.value);

  @override
  String toString() => parts.join('.');
}

/// Where a network device listens: an IPv4 address and a TCP port.
final class NetworkAddress {
  const NetworkAddress(this.ip, [this.port = defaultAdbPort]);

  static const defaultAdbPort = 5555;

  /// Reads `192.168.1.202` or `192.168.1.202:5555`. Null otherwise.
  static NetworkAddress? tryParse(String text) {
    final colon = text.lastIndexOf(':');
    final ipText = colon < 0 ? text : text.substring(0, colon);
    final ip = Ipv4.tryParse(ipText);
    if (ip == null) return null;
    if (colon < 0) return NetworkAddress(ip);
    final port = int.tryParse(text.substring(colon + 1));
    if (port == null || port < 1 || port > 65535) return null;
    return NetworkAddress(ip, port);
  }

  final Ipv4 ip;
  final int port;

  /// The serial adb gives a network device: `ip:port`.
  String get serial => '$ip:$port';

  @override
  bool operator ==(Object other) =>
      other is NetworkAddress && other.ip == ip && other.port == port;

  @override
  int get hashCode => Object.hash(ip, port);

  @override
  String toString() => serial;
}

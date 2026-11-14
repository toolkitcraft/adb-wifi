import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:test/test.dart';

Ipv4 ip(String text) => Ipv4.tryParse(text)!;

void main() {
  group('Ipv4', () {
    test('parses dotted addresses and prints them back', () {
      expect(ip('192.168.1.202').toString(), '192.168.1.202');
      expect(ip('0.0.0.0').value, 0);
      expect(ip('255.255.255.255').parts, [255, 255, 255, 255]);
    });

    test('rejects anything that is not a plain IPv4 address', () {
      for (final bad in [
        '', '1.2.3', '1.2.3.4.5', '256.1.1.1', '01.2.3.4', ' 1.2.3.4', //
        '1.2.3.4:5555', 'a.b.c.d', '-1.2.3.4', 'tablet',
      ]) {
        expect(Ipv4.tryParse(bad), isNull, reason: bad);
      }
    });

    test('knows the private ranges', () {
      for (final private in [
        '10.0.0.1',
        '172.16.0.1',
        '172.31.255.1',
        '192.168.1.5',
      ]) {
        expect(ip(private).isPrivate, isTrue, reason: private);
      }
      for (final public in [
        '8.8.8.8',
        '172.15.0.1',
        '172.32.0.1',
        '100.64.0.1',
        '169.254.1.1',
        '127.0.0.1',
      ]) {
        expect(ip(public).isPrivate, isFalse, reason: public);
      }
    });

    test('compares /24 subnets', () {
      expect(ip('192.168.1.5').sameSubnet24(ip('192.168.1.202')), isTrue);
      expect(ip('192.168.1.5').sameSubnet24(ip('192.168.0.202')), isFalse);
      expect(ip('192.168.1.5').subnet24, '192.168.1.0/24');
      expect(ip('192.168.1.5').withHost(254), ip('192.168.1.254'));
    });
  });

  group('NetworkAddress', () {
    test('defaults to port 5555 and reads ip:port', () {
      expect(
        NetworkAddress.tryParse('192.168.1.202')?.serial,
        '192.168.1.202:5555',
      );
      expect(NetworkAddress.tryParse('192.168.1.202:5556')?.port, 5556);
    });

    test('rejects bad ports and names', () {
      for (final bad in [
        '1.2.3.4:0',
        '1.2.3.4:70000',
        '1.2.3.4:',
        'tablet:5555',
        'emulator-5554',
      ]) {
        expect(NetworkAddress.tryParse(bad), isNull, reason: bad);
      }
    });
  });

  group('lanAddresses', () {
    test('keeps private addresses on real adapters, sorted by name', () {
      final kept = lanAddresses([
        (adapter: 'en1', ip: ip('10.0.0.8')),
        (adapter: 'utun3', ip: ip('10.8.0.2')),
        (adapter: 'bridge100', ip: ip('192.168.2.1')),
        (adapter: 'en0', ip: ip('192.168.1.5')),
        (adapter: 'vEthernet (WSL)', ip: ip('172.20.0.1')),
        (adapter: 'docker0', ip: ip('172.17.0.1')),
        (adapter: 'Tailscale', ip: ip('100.101.1.1')),
        (adapter: 'Wi-Fi', ip: ip('169.254.3.4')),
        (adapter: 'Ethernet', ip: ip('192.168.0.9')),
        (adapter: 'lo0', ip: ip('127.0.0.1')),
      ]);
      expect([for (final a in kept) a.adapter], ['Ethernet', 'en0', 'en1']);
    });

    test('knows virtual adapters from all three OSes', () {
      for (final name in [
        'utun0', 'awdl0', 'llw0', 'bridge0', 'docker0', 'br-1a2b', 'veth12', //
        'vboxnet0', 'vmnet8', 'tun0', 'tap0', 'wg0', 'ztabc123', 'virbr0',
        'vEthernet (Default Switch)', 'VirtualBox Host-Only Network',
        'VMware Network Adapter VMnet1', 'Tailscale', 'ZeroTier One',
        'Cisco AnyConnect VPN', 'tailscale0',
      ]) {
        expect(isVirtualAdapter(name), isTrue, reason: name);
      }
      for (final name in [
        'en0',
        'en7',
        'eth0',
        'wlan0',
        'wlp2s0',
        'Wi-Fi',
        'Ethernet',
        'Local Area Connection',
      ]) {
        expect(isVirtualAdapter(name), isFalse, reason: name);
      }
    });
  });

  group('classifySocketError', () {
    test('connection refused on macOS, Linux and Windows', () {
      for (final code in [61, 111, 10061]) {
        expect(
          classifySocketError(code, 'Connection refused'),
          isA<PortRefused>(),
        );
      }
    });

    test('timeouts and unreachable hosts are "no answer"', () {
      expect(
        classifySocketError(null, 'Connection timed out'),
        isA<PortNoAnswer>(),
      );
      for (final code in [60, 110, 10060]) {
        expect(classifySocketError(code, 'timed out'), isA<PortNoAnswer>());
      }
      for (final code in [65, 113, 10065, 51, 101, 10051]) {
        final state = classifySocketError(code, 'No route to host');
        expect((state as PortNoAnswer).unreachable, isTrue);
      }
    });

    test('anything else is an error with its message', () {
      final state = classifySocketError(13, 'Permission denied');
      expect((state as PortError).message, 'Permission denied (error 13)');
    });
  });
}

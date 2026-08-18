import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/services/lan_scan.dart';

void main() {
  group('Ipv4Sweep.hosts', () {
    test(
      'starts after the current IP, wraps, skips this device, current last',
      () {
        final hosts = Ipv4Sweep.hosts(
          localIpv4: '192.168.2.15',
          afterIp: '192.168.2.10',
        );

        expect(hosts.first, '192.168.2.11');
        expect(hosts.last, '192.168.2.10');
        expect(hosts, isNot(contains('192.168.2.15')));
        expect(hosts, isNot(contains('192.168.2.0')));
        expect(hosts, isNot(contains('192.168.2.255')));
        expect(hosts.length, 253);
        expect(hosts.toSet().length, 253);
      },
    );

    test('wraps from .254 to .1', () {
      final hosts = Ipv4Sweep.hosts(
        localIpv4: '192.168.2.15',
        afterIp: '192.168.2.254',
      );

      expect(hosts.first, '192.168.2.1');
      expect(hosts.last, '192.168.2.254');
      expect(hosts, isNot(contains('192.168.2.15')));
    });

    test('empty or foreign afterIp starts at .1', () {
      final hosts = Ipv4Sweep.hosts(localIpv4: '192.168.2.15', afterIp: '');

      expect(hosts.first, '192.168.2.1');
      expect(hosts.last, '192.168.2.254');
      expect(hosts, isNot(contains('192.168.2.15')));

      final foreign = Ipv4Sweep.hosts(
        localIpv4: '192.168.2.15',
        afterIp: '192.168.1.10',
      );
      expect(foreign.first, '192.168.2.1');
    });

    test('skips this device when it is also the current IP', () {
      final hosts = Ipv4Sweep.hosts(
        localIpv4: '192.168.2.15',
        afterIp: '192.168.2.15',
      );

      expect(hosts.first, '192.168.2.16');
      expect(hosts, isNot(contains('192.168.2.15')));
      expect(hosts.length, 253);
    });
  });

  group('Ipv4Sweep.nextAmong', () {
    test('picks the next IP then wraps', () {
      expect(
        Ipv4Sweep.nextAmong(['192.168.2.8', '192.168.2.2'], '192.168.2.2'),
        '192.168.2.8',
      );
      expect(
        Ipv4Sweep.nextAmong(['192.168.2.8', '192.168.2.2'], '192.168.2.8'),
        '192.168.2.2',
      );
    });

    test('empty afterIp yields the lowest', () {
      expect(
        Ipv4Sweep.nextAmong(['192.168.2.8', '192.168.2.2'], ''),
        '192.168.2.2',
      );
    });
  });

  group('LanScan.firstSuccessInOrder', () {
    test(
      'returns the earliest host in list order, not the first to finish',
      () async {
        final found = await LanScan.firstSuccessInOrder(
          hosts: ['10.0.0.1', '10.0.0.2'],
          concurrency: 2,
          probe: (host) async {
            if (host == '10.0.0.2') {
              await Future<void>.delayed(const Duration(milliseconds: 1));
              return true;
            }
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return true;
          },
        );
        expect(found, '10.0.0.1');
      },
    );

    test('stops after a successful batch and skips later hosts', () async {
      final probed = <String>[];
      final found = await LanScan.firstSuccessInOrder(
        hosts: ['10.0.0.1', '10.0.0.2', '10.0.0.3'],
        concurrency: 2,
        probe: (host) async {
          probed.add(host);
          return host == '10.0.0.2';
        },
      );
      expect(found, '10.0.0.2');
      expect(probed, isNot(contains('10.0.0.3')));
    });

    test('returns null when nothing answers', () async {
      expect(
        await LanScan.firstSuccessInOrder(
          hosts: ['10.0.0.1', '10.0.0.2'],
          concurrency: 2,
          probe: (_) async => false,
        ),
        isNull,
      );
    });
  });
}

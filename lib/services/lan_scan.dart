import 'dart:async';

/// /24 host order and bounded parallel probes for LAN find.
abstract final class Ipv4Sweep {
  static const int concurrency = 32;

  static const Duration probeTimeout = Duration(milliseconds: 400);

  /// True for four decimal octets in `0..255`.
  static bool isIpv4(String raw) => parse(raw.trim()) != null;

  /// `a.b.c` prefix and host octet `d`, or `null` if [raw] is not IPv4.
  static ({String prefix, int host})? parse(String raw) {
    final parts = raw.split('.');
    if (parts.length != 4) {
      return null;
    }
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) {
        return null;
      }
      octets.add(value);
    }
    return (prefix: '${octets[0]}.${octets[1]}.${octets[2]}', host: octets[3]);
  }

  /// Hosts `1..254` on [localIpv4]'s /24. When [afterIp] is on that subnet,
  /// starts after it and wraps so it is last. Otherwise starts at `.1`.
  /// Skips this device.
  static List<String> hosts({
    required String localIpv4,
    required String afterIp,
  }) {
    final local = parse(localIpv4.trim());
    if (local == null) {
      return const [];
    }

    final after = parse(afterIp.trim());
    final afterOnSubnet =
        after != null &&
        after.prefix == local.prefix &&
        after.host >= 1 &&
        after.host <= 254;
    final startAfter = afterOnSubnet ? after.host : 0;

    final out = <String>[];
    for (var step = 1; step <= 254; step++) {
      final host = _wrapHost(startAfter + step);
      if (host == local.host) {
        continue;
      }
      out.add('${local.prefix}.$host');
    }
    return out;
  }

  /// First address after [afterIp] in dotted-quad order, wrapping to the
  /// lowest. [afterIp] that is missing or not in [ips] yields the lowest.
  static String? nextAmong(Iterable<String> ips, String afterIp) {
    final unique = <String>{};
    for (final ip in ips) {
      final trimmed = ip.trim();
      if (isIpv4(trimmed)) {
        unique.add(trimmed);
      }
    }
    if (unique.isEmpty) {
      return null;
    }

    final list = unique.toList()
      ..sort((a, b) {
        final pa = parse(a)!;
        final pb = parse(b)!;
        final prefix = pa.prefix.compareTo(pb.prefix);
        if (prefix != 0) {
          return prefix;
        }
        return pa.host.compareTo(pb.host);
      });

    final after = parse(afterIp.trim());
    if (after == null) {
      return list.first;
    }
    for (final ip in list) {
      final parsed = parse(ip)!;
      if (parsed.prefix.compareTo(after.prefix) > 0) {
        return ip;
      }
      if (parsed.prefix == after.prefix && parsed.host > after.host) {
        return ip;
      }
    }
    return list.first;
  }

  /// Maps any integer onto host ids `1..254`.
  static int _wrapHost(int n) {
    var x = (n - 1) % 254;
    if (x < 0) {
      x += 254;
    }
    return x + 1;
  }
}

/// Runs [probe] in batches; within a batch the earliest list index that
/// succeeds wins, even if a later host answers first.
abstract final class LanScan {
  static Future<String?> firstSuccessInOrder({
    required List<String> hosts,
    required Future<bool> Function(String host) probe,
    int concurrency = Ipv4Sweep.concurrency,
  }) async {
    if (hosts.isEmpty || concurrency < 1) {
      return null;
    }
    for (var offset = 0; offset < hosts.length; offset += concurrency) {
      final end = offset + concurrency;
      final batch = hosts.sublist(
        offset,
        end > hosts.length ? hosts.length : end,
      );
      final found = await _firstInBatch(batch, probe);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  static Future<String?> _firstInBatch(
    List<String> batch,
    Future<bool> Function(String host) probe,
  ) {
    final results = List<bool?>.filled(batch.length, null);
    final done = Completer<String?>();

    void consider() {
      if (done.isCompleted) {
        return;
      }
      for (var i = 0; i < batch.length; i++) {
        final result = results[i];
        if (result == null) {
          return;
        }
        if (result) {
          done.complete(batch[i]);
          return;
        }
      }
      done.complete(null);
    }

    for (var i = 0; i < batch.length; i++) {
      final index = i;
      unawaited(() async {
        var ok = false;
        try {
          ok = await probe(batch[index]);
        } on Object {
          ok = false;
        }
        results[index] = ok;
        consider();
      }());
    }

    return done.future;
  }
}

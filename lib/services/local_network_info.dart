import 'dart:io';

/// Resolves this device's LAN IPv4 address for display.
class LocalNetworkInfo {
  /// Prefers `192.168.*` / Wi‑Fi-style private addresses, else another private IPv4.
  static Future<String> localIpv4() async {
    try {
      String? fallback;
      for (final interface in await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      )) {
        for (final addr in interface.addresses) {
          if (addr.isLoopback) {
            continue;
          }
          final ip = addr.address;
          if (!_isPrivateIpv4(ip)) {
            continue;
          }
          if (ip.startsWith('192.168.') ||
              interface.name.toLowerCase().contains('wlan') ||
              interface.name.toLowerCase().contains('wifi')) {
            return ip;
          }
          fallback ??= ip;
        }
      }
      return fallback ?? 'No IP';
    } on Object {
      return 'IP unavailable';
    }
  }

  static bool _isPrivateIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) {
      return false;
    }
    if (a == 10) {
      return true;
    }
    if (a == 172 && b >= 16 && b <= 31) {
      return true;
    }
    if (a == 192 && b == 168) {
      return true;
    }
    return false;
  }
}

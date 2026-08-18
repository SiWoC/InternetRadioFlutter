import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// SSDP M-SEARCH packet and reply parsing (UPnP device discovery).
abstract final class SsdpProtocol {
  static const String multicastHost = '239.255.255.250';

  static const int port = 1900;

  static const String mediaRendererSt =
      'urn:schemas-upnp-org:device:MediaRenderer:1';

  static const Duration listenDuration = Duration(seconds: 2);

  static String msearch({String st = mediaRendererSt, int mx = 2}) {
    return 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $multicastHost:$port\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: $mx\r\n'
        'ST: $st\r\n'
        '\r\n';
  }

  /// Parses a unicast `HTTP/1.1 200` reply, or `null` if it is not SSDP.
  static SsdpReply? parseReply(String datagram) {
    final lines = datagram.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) {
      return null;
    }
    final status = lines.first.trim().toUpperCase();
    if (!status.startsWith('HTTP/1.1 200')) {
      return null;
    }
    final headers = <String, String>{};
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        break;
      }
      final colon = line.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      final key = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();
      if (key.isNotEmpty) {
        headers[key] = value;
      }
    }
    return SsdpReply(headers);
  }

  /// Yamaha AV receivers advertise `YAMAHA` / `AV_Receiver` on SSDP.
  static bool isYamahaReceiver(SsdpReply reply) {
    final server = reply.header('server') ?? '';
    final model = reply.header('x-modelname') ?? '';
    final blob = '$server $model'.toUpperCase();
    return blob.contains('YAMAHA') || blob.contains('AV_RECEIVER');
  }

  static String? hostFromLocation(SsdpReply reply) {
    final location = reply.header('location');
    if (location == null || location.isEmpty) {
      return null;
    }
    return Uri.tryParse(location)?.host;
  }
}

/// One SSDP `200 OK` with lower-cased header names.
class SsdpReply {
  const SsdpReply(this.headers);

  final Map<String, String> headers;

  String? header(String name) => headers[name.toLowerCase()];
}

/// Sends M-SEARCH and collects unicast replies for [listen].
class SsdpClient {
  Future<List<SsdpReply>> search({
    String st = SsdpProtocol.mediaRendererSt,
    Duration listen = SsdpProtocol.listenDuration,
    int mx = 2,
  }) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    final replies = <SsdpReply>[];
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.readEventsEnabled = true;
      socket.broadcastEnabled = true;
      socket.multicastHops = 2;
      try {
        socket.joinMulticast(InternetAddress(SsdpProtocol.multicastHost));
      } on Object {
        // Membership is optional; send + unicast receive still work on many stacks.
      }

      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) {
          return;
        }
        final packet = socket?.receive();
        if (packet == null) {
          return;
        }
        final reply = SsdpProtocol.parseReply(
          utf8.decode(packet.data, allowMalformed: true),
        );
        if (reply != null) {
          replies.add(reply);
        }
      });

      final bytes = utf8.encode(SsdpProtocol.msearch(st: st, mx: mx));
      socket.send(
        bytes,
        InternetAddress(SsdpProtocol.multicastHost),
        SsdpProtocol.port,
      );
      await Future<void>.delayed(listen);
    } on Object {
      return const [];
    } finally {
      await subscription?.cancel();
      socket?.close();
    }
    return replies;
  }
}

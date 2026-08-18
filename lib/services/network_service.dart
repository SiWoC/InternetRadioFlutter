import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:internetradio/services/lan_scan.dart';
import 'package:internetradio/services/network_protocol.dart';

/// Handles one parsed Player-mode command and returns the reply line body.
typedef NetworkCommandHandler = FutureOr<String> Function(NetworkCommand command);

/// TCP client/server for Player ↔ Remote on [NetworkProtocol.port].
///
/// Remote client: line-oriented request/response ([sendCommand], [ping]).
/// Player: [startListener] / [stopListener] accept loop.
class NetworkService {
  ServerSocket? _server;
  final _clients = <Socket>{};
  var _listening = false;

  bool get isListening => _listening;

  /// Bound TCP port while listening, or `null` when stopped.
  int? get boundPort => _server?.port;

  /// Binds [port] and dispatches each request line through [onCommand].
  Future<void> startListener({
    required NetworkCommandHandler onCommand,
    int port = NetworkProtocol.port,
  }) async {
    if (_listening) {
      return;
    }

    final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _server = server;
    _listening = true;

    server.listen(
      (client) => unawaited(_handleClient(client, onCommand)),
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Future<void> stopListener() async {
    if (!_listening && _server == null) {
      return;
    }
    _listening = false;

    final clients = List<Socket>.from(_clients);
    _clients.clear();
    for (final client in clients) {
      client.destroy();
    }

    await _server?.close();
    _server = null;
  }

  Future<void> _handleClient(
    Socket client,
    NetworkCommandHandler onCommand,
  ) async {
    _clients.add(client);
    try {
      final lines = utf8.decoder.bind(client).transform(const LineSplitter());
      await for (final line in lines) {
        if (!_listening) {
          break;
        }
        if (line.isEmpty) {
          break;
        }
        final response = await onCommand(NetworkProtocol.parseCommand(line));
        client.write('$response\n');
        await client.flush();
      }
    } on Object {
      // Client disconnect / reset — ignore.
    } finally {
      _clients.remove(client);
      client.destroy();
    }
  }

  /// Connects to [ipAddress]:[port], writes one command line, reads one reply line.
  ///
  /// Returns the reply without the trailing newline, or `null` on empty host,
  /// timeout, or any other failure.
  Future<String?> sendCommand(
    String ipAddress,
    String command, {
    Duration timeout = NetworkProtocol.connectionTimeout,
    int port = NetworkProtocol.port,
  }) async {
    final host = ipAddress.trim();
    if (host.isEmpty || command.isEmpty) {
      return null;
    }

    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);

      socket.write('$command\n');
      await socket.flush();

      return await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(timeout);
    } on Object {
      return null;
    } finally {
      await socket?.close();
    }
  }

  /// Sends `PING` and returns whether the reply is `PONG`.
  Future<bool> ping(
    String ipAddress, {
    Duration timeout = NetworkProtocol.connectionTimeout,
    int port = NetworkProtocol.port,
  }) async {
    final response = await sendCommand(
      ipAddress,
      NetworkProtocol.ping,
      timeout: timeout,
      port: port,
    );
    return NetworkProtocol.isPong(response);
  }

  /// /24 TCP `PING` sweep: after [afterIp] on this LAN, else from `.1`.
  Future<String?> findPlayer({
    required String localIpv4,
    required String afterIp,
    Duration timeout = Ipv4Sweep.probeTimeout,
    int concurrency = Ipv4Sweep.concurrency,
  }) {
    return LanScan.firstSuccessInOrder(
      hosts: Ipv4Sweep.hosts(localIpv4: localIpv4, afterIp: afterIp),
      probe: (ip) => ping(ip, timeout: timeout),
      concurrency: concurrency,
    );
  }
}

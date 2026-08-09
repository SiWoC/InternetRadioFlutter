import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/models/remote_player_state.dart';
import 'package:internetradio/services/network_protocol.dart';
import 'package:internetradio/services/network_service.dart';

Future<ServerSocket> _startLineEchoServer(
  Future<String> Function(String request) reply,
) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((client) async {
    final request = await utf8.decoder
        .bind(client)
        .transform(const LineSplitter())
        .first;
    final response = await reply(request);
    client.write('$response\n');
    await client.flush();
    await client.close();
  });
  return server;
}

void main() {
  test('NetworkProtocol command builders and parse', () {
    expect(NetworkProtocol.parseCommand('PING'), isA<PingCommand>());
    expect(NetworkProtocol.parseCommand('MUTE'), isA<MuteCommand>());
    expect(NetworkProtocol.parseCommand('UNMUTE'), isA<UnmuteCommand>());
    expect(NetworkProtocol.parseCommand('GET_STATE'), isA<GetStateCommand>());

    final select = NetworkProtocol.parseCommand(
      NetworkProtocol.selectStation(3),
    );
    expect(select, isA<SelectStationCommand>());
    expect((select as SelectStationCommand).index, 3);

    final testUrl = NetworkProtocol.parseCommand(
      NetworkProtocol.testUrl('https://example/stream'),
    );
    expect(testUrl, isA<TestUrlCommand>());
    expect((testUrl as TestUrlCommand).url, 'https://example/stream');

    final invalid = NetworkProtocol.parseCommand('NOPE');
    expect(invalid, isA<InvalidCommand>());
  });

  test('NetworkProtocol STATE encode/decode', () {
    const state = RemotePlayerState(
      stationIndex: 2,
      isMuted: true,
      isPlaying: false,
    );
    final line = NetworkProtocol.encodeState(state);
    expect(line, 'STATE|2|1|0');
    expect(NetworkProtocol.parseState(line), state);
    expect(NetworkProtocol.parseState('STATE|x|1|0'), isNull);
  });

  test('sendCommand returns null for empty host or command', () async {
    final network = NetworkService();
    expect(await network.sendCommand('', 'PING'), isNull);
    expect(await network.sendCommand('127.0.0.1', ''), isNull);
  });

  test('sendCommand writes a line and returns the reply line', () async {
    final server = await _startLineEchoServer((request) async {
      expect(request, 'GET_STATE');
      return 'STATE|0|0|1';
    });
    addTearDown(server.close);

    final network = NetworkService();
    final reply = await network.sendCommand(
      '127.0.0.1',
      'GET_STATE',
      port: server.port,
    );
    expect(reply, 'STATE|0|0|1');
  });

  test('ping returns false for empty host', () async {
    final network = NetworkService();
    expect(await network.ping(''), isFalse);
    expect(await network.ping('   '), isFalse);
  });

  test('ping succeeds against local PONG server', () async {
    final server = await _startLineEchoServer((request) async {
      expect(request, NetworkProtocol.ping);
      return NetworkProtocol.pong;
    });
    addTearDown(server.close);

    final network = NetworkService();
    final ok = await network.ping(
      '127.0.0.1',
      port: server.port,
    );
    expect(ok, isTrue);
  });

  test('listener answers PING and GET_STATE', () async {
    final network = NetworkService();
    addTearDown(network.stopListener);

    await network.startListener(
      port: 0,
      onCommand: (command) {
        return switch (command) {
          PingCommand() => NetworkProtocol.pong,
          GetStateCommand() => NetworkProtocol.encodeState(
              const RemotePlayerState(
                stationIndex: 1,
                isMuted: false,
                isPlaying: true,
              ),
            ),
          InvalidCommand(:final message) => NetworkProtocol.error(message),
          _ => NetworkProtocol.ok,
        };
      },
    );

    final port = network.boundPort;
    expect(port, isNotNull);
    expect(network.isListening, isTrue);

    expect(await network.ping('127.0.0.1', port: port!), isTrue);

    final state = await network.sendCommand(
      '127.0.0.1',
      NetworkProtocol.getState,
      port: port,
    );
    expect(state, 'STATE|1|0|1');
  });
}

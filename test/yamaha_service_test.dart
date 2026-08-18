import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/models/yamaha_status.dart';
import 'package:internetradio/services/ssdp.dart';
import 'package:internetradio/services/yamaha_protocol.dart';
import 'package:internetradio/services/yamaha_service.dart';

const _liveBasicStatus =
    '<YAMAHA_AV rsp="GET" RC="0"><Main_Zone><Basic_Status>'
    '<Power_Control><Power>On</Power><Sleep>Off</Sleep></Power_Control>'
    '<Volume><Lvl><Val>-570</Val><Exp>1</Exp><Unit>dB</Unit></Lvl>'
    '<Mute>Off</Mute></Volume>'
    '<Input><Input_Sel>HDMI2</Input_Sel></Input>'
    '</Basic_Status></Main_Zone></YAMAHA_AV>';

const _putOk =
    '<YAMAHA_AV rsp="PUT" RC="0"><Main_Zone></Main_Zone></YAMAHA_AV>';

const _putRejected =
    '<YAMAHA_AV rsp="PUT" RC="4"><Main_Zone></Main_Zone></YAMAHA_AV>';

Future<HttpServer> _startYamahaFake(
  Future<String> Function(String body) reply,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    expect(request.method, 'POST');
    expect(request.uri.path, YamahaProtocol.controlPath);
    final body = await utf8.decoder.bind(request).join();
    final xml = await reply(body);
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
      ..write(xml);
    await request.response.close();
  });
  return server;
}

void main() {
  test('empty IP is a no-op', () async {
    final yamaha = YamahaService();
    expect(await yamaha.getBasicStatus(''), isNull);
    expect(await yamaha.getBasicStatus('   '), isNull);
    expect(await yamaha.setPower('', YamahaPower.on), isFalse);
    expect(await yamaha.selectInput('127.0.0.1', ''), isFalse);
  });

  test('getBasicStatus POSTs GET XML and parses the reply', () async {
    final server = await _startYamahaFake((body) async {
      expect(body, YamahaProtocol.getBasicStatusXml());
      return _liveBasicStatus;
    });
    addTearDown(server.close);

    final yamaha = YamahaService(port: server.port);
    expect(
      await yamaha.getBasicStatus('127.0.0.1'),
      const YamahaStatus(
        power: YamahaPower.on,
        inputSel: 'HDMI2',
        volumeTenthsDb: -570,
        mute: false,
      ),
    );
  });

  test('getInputList POSTs GET XML and parses writable items', () async {
    const reply =
        '<YAMAHA_AV rsp="GET" RC="0"><Main_Zone><Input><Input_Sel_Item>'
        '<Item_1><Param>HDMI4</Param><RW>RW</RW><Title>Mediaplay</Title></Item_1>'
        '</Input_Sel_Item></Input></Main_Zone></YAMAHA_AV>';
    final server = await _startYamahaFake((body) async {
      expect(body, YamahaProtocol.getInputSelItemXml());
      return reply;
    });
    addTearDown(server.close);

    final yamaha = YamahaService(port: server.port);
    expect(await yamaha.getInputList('127.0.0.1'), [
      const YamahaInput(param: 'HDMI4', title: 'Mediaplay'),
    ]);
  });

  test('setPower and selectInput succeed when RC is 0', () async {
    final posted = <String>[];
    final server = await _startYamahaFake((body) async {
      posted.add(body);
      return _putOk;
    });
    addTearDown(server.close);

    final yamaha = YamahaService(port: server.port);
    expect(await yamaha.setPower('127.0.0.1', YamahaPower.on), isTrue);
    expect(await yamaha.selectInput('127.0.0.1', 'HDMI4'), isTrue);
    expect(posted, [
      YamahaProtocol.setPowerXml(YamahaPower.on),
      YamahaProtocol.selectInputXml('HDMI4'),
    ]);
  });

  test('selectInput is false when RC is 4', () async {
    final server = await _startYamahaFake((body) async => _putRejected);
    addTearDown(server.close);

    final yamaha = YamahaService(port: server.port);
    expect(await yamaha.selectInput('127.0.0.1', 'HDMI2'), isFalse);
  });

  test('setVolume PUTs clamped tenths', () async {
    final posted = <String>[];
    final server = await _startYamahaFake((body) async {
      posted.add(body);
      return _putOk;
    });
    addTearDown(server.close);

    final yamaha = YamahaService(port: server.port);
    expect(await yamaha.setVolume('127.0.0.1', -565), isTrue);
    expect(posted, [YamahaProtocol.setVolumeXml(-565)]);
  });

  test('volumeUp GETs status then PUTs +0.5 dB', () async {
    final posted = <String>[];
    final server = await _startYamahaFake((body) async {
      posted.add(body);
      if (body == YamahaProtocol.getBasicStatusXml()) {
        return _liveBasicStatus;
      }
      return _putOk;
    });
    addTearDown(server.close);

    final yamaha = YamahaService(port: server.port);
    expect(await yamaha.volumeUp('127.0.0.1'), isTrue);
    expect(posted, [
      YamahaProtocol.getBasicStatusXml(),
      YamahaProtocol.setVolumeXml(-565),
    ]);
  });

  test('volumeDown GETs status then PUTs -0.5 dB', () async {
    final posted = <String>[];
    final server = await _startYamahaFake((body) async {
      posted.add(body);
      if (body == YamahaProtocol.getBasicStatusXml()) {
        return _liveBasicStatus;
      }
      return _putOk;
    });
    addTearDown(server.close);

    final yamaha = YamahaService(port: server.port);
    expect(await yamaha.volumeDown('127.0.0.1'), isTrue);
    expect(posted.last, YamahaProtocol.setVolumeXml(-575));
  });

  test(
    'findReceiver keeps Yamaha IPs and picks the next after afterIp',
    () async {
      final ssdp = _FakeSsdp([
        const SsdpReply({
          'location': 'http://192.168.2.3:50001/desc/device.xml',
          'server': 'Linux/4.4, UPnP/1.0, Portable SDK for UPnP devices/1.12.1',
        }),
        const SsdpReply({
          'location': 'http://192.168.2.2:49154/MediaRenderer/desc.xml',
          'server': 'VDK/5.0 UPnP/1.0 AV_Receiver/3.1 (RX-V671)',
          'x-modelname': 'RX-V671:00A0DE87302E:YAMAHA',
        }),
        const SsdpReply({
          'location': 'http://192.168.2.8:49154/MediaRenderer/desc.xml',
          'server': 'VDK/5.0 UPnP/1.0 AV_Receiver/3.1 (RX-V773)',
          'x-modelname': 'RX-V773:00A0DE000000:YAMAHA',
        }),
      ]);
      final yamaha = YamahaService(ssdp: ssdp);
      expect(await yamaha.findReceiver(afterIp: '192.168.2.2'), '192.168.2.8');
      expect(await yamaha.findReceiver(afterIp: '192.168.2.8'), '192.168.2.2');
    },
  );
}

class _FakeSsdp extends SsdpClient {
  _FakeSsdp(this.replies);

  final List<SsdpReply> replies;

  @override
  Future<List<SsdpReply>> search({
    String st = SsdpProtocol.mediaRendererSt,
    Duration listen = SsdpProtocol.listenDuration,
    int mx = 2,
  }) async {
    return replies;
  }
}

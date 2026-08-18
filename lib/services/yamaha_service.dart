import 'dart:convert';
import 'dart:io';

import 'package:internetradio/models/yamaha_status.dart';
import 'package:internetradio/services/lan_scan.dart';
import 'package:internetradio/services/ssdp.dart';
import 'package:internetradio/services/yamaha_protocol.dart';

/// HTTP facade for Yamaha Network Control POSTs.
class YamahaService {
  YamahaService({
    this.timeout = YamahaProtocol.timeout,
    this.port = YamahaProtocol.port,
    SsdpClient? ssdp,
  }) : _ssdp = ssdp ?? SsdpClient();

  final Duration timeout;
  final int port;
  final SsdpClient _ssdp;

  /// SSDP M-SEARCH for a Yamaha MediaRenderer; next IP after [afterIp].
  Future<String?> findReceiver({String afterIp = ''}) async {
    final replies = await _ssdp.search();
    final ips = <String>{};
    for (final reply in replies) {
      if (!SsdpProtocol.isYamahaReceiver(reply)) {
        continue;
      }
      final host = SsdpProtocol.hostFromLocation(reply);
      if (host != null && Ipv4Sweep.isIpv4(host)) {
        ips.add(host);
      }
    }
    return Ipv4Sweep.nextAmong(ips, afterIp);
  }

  /// GET Main Zone power, input, volume, and mute.
  Future<YamahaStatus?> getBasicStatus(String ip) async {
    final reply = await _post(ip, YamahaProtocol.getBasicStatusXml());
    return YamahaProtocol.parseBasicStatus(reply);
  }

  /// GET writable Main Zone inputs (`Param` + `Title`).
  Future<List<YamahaInput>?> getInputList(String ip) async {
    final reply = await _post(ip, YamahaProtocol.getInputSelItemXml());
    return YamahaProtocol.parseInputSelItems(reply);
  }

  Future<bool> setPower(String ip, YamahaPower power) {
    return _putOk(ip, YamahaProtocol.setPowerXml(power));
  }

  Future<bool> selectInput(String ip, String inputSel) async {
    final name = inputSel.trim();
    if (name.isEmpty) {
      return false;
    }
    return _putOk(ip, YamahaProtocol.selectInputXml(name));
  }

  /// PUT absolute volume. [tenthsDb] is tenths of a dB (`-570` = −57.0 dB).
  Future<bool> setVolume(String ip, int tenthsDb) {
    return _putOk(
      ip,
      YamahaProtocol.setVolumeXml(YamahaProtocol.clampVolumeTenthsDb(tenthsDb)),
    );
  }

  /// Raises volume by one RX-V671 step (0.5 dB).
  Future<bool> volumeUp(String ip) {
    return _nudgeVolume(ip, YamahaProtocol.volumeStepTenthsDb);
  }

  /// Lowers volume by one RX-V671 step (0.5 dB).
  Future<bool> volumeDown(String ip) {
    return _nudgeVolume(ip, -YamahaProtocol.volumeStepTenthsDb);
  }

  Future<bool> _nudgeVolume(String ip, int deltaTenthsDb) async {
    final status = await getBasicStatus(ip);
    if (status == null) {
      return false;
    }
    return setVolume(ip, status.volumeTenthsDb + deltaTenthsDb);
  }

  Future<bool> _putOk(String ip, String xml) async {
    final reply = await _post(ip, xml);
    return YamahaProtocol.isOk(reply);
  }

  Future<String?> _post(String ipAddress, String xml) async {
    final host = ipAddress.trim();
    if (host.isEmpty || xml.isEmpty) {
      return null;
    }

    final uri = Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: YamahaProtocol.controlPath,
    );

    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = timeout;
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType(
        'text',
        'xml',
        charset: 'utf-8',
      );
      request.write(xml);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      return await utf8.decoder.bind(response).join().timeout(timeout);
    } on Object {
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}

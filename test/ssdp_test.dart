import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/services/ssdp.dart';

void main() {
  test('msearch is a CRLF SSDP packet for MediaRenderer', () {
    final packet = SsdpProtocol.msearch();
    expect(packet, startsWith('M-SEARCH * HTTP/1.1\r\n'));
    expect(packet, contains('HOST: 239.255.255.250:1900\r\n'));
    expect(
      packet,
      contains('ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'),
    );
    expect(packet.endsWith('\r\n\r\n'), isTrue);
  });

  test('parseReply reads Yamaha MediaRenderer headers', () {
    const datagram =
        'HTTP/1.1 200 OK\r\n'
        'Location: http://192.168.2.2:49154/MediaRenderer/desc.xml\r\n'
        'Server: VDK/5.0 UPnP/1.0 AV_Receiver/3.1 (RX-V671)\r\n'
        'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
        'X-ModelName: RX-V671:00A0DE87302E:YAMAHA\r\n'
        '\r\n';
    final reply = SsdpProtocol.parseReply(datagram);
    expect(reply, isNotNull);
    expect(SsdpProtocol.isYamahaReceiver(reply!), isTrue);
    expect(SsdpProtocol.hostFromLocation(reply), '192.168.2.2');
  });

  test('Synology MediaServer is not a Yamaha receiver', () {
    const datagram =
        'HTTP/1.1 200 OK\r\n'
        'LOCATION: http://192.168.2.3:50001/desc/device.xml\r\n'
        'SERVER: Linux/4.4.180+, UPnP/1.0, Portable SDK for UPnP devices/1.12.1\r\n'
        'ST: urn:schemas-upnp-org:device:MediaServer:1\r\n'
        '\r\n';
    final reply = SsdpProtocol.parseReply(datagram);
    expect(reply, isNotNull);
    expect(SsdpProtocol.isYamahaReceiver(reply!), isFalse);
    expect(SsdpProtocol.hostFromLocation(reply), '192.168.2.3');
  });

  test('parseReply ignores M-SEARCH itself', () {
    expect(SsdpProtocol.parseReply(SsdpProtocol.msearch()), isNull);
  });
}

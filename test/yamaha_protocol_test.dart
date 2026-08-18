import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/models/yamaha_status.dart';
import 'package:internetradio/services/yamaha_protocol.dart';

/// Live GET from RX-V671 at 192.168.2.2 (Standby, HDMI4, −57.0 dB).
const _liveBasicStatus = '''
<YAMAHA_AV rsp="GET" RC="0"><Main_Zone><Basic_Status><Power_Control><Power>Standby</Power><Sleep>Off</Sleep></Power_Control><Volume><Lvl><Val>-570</Val><Exp>1</Exp><Unit>dB</Unit></Lvl><Mute>Off</Mute></Volume><Input><Input_Sel>HDMI4</Input_Sel><Input_Sel_Item_Info><Param>HDMI4</Param><RW>RW</RW><Title>Mediaplay</Title><Icon><On>/YamahaRemoteControl/Icons/icon086.png</On><Off></Off></Icon><Src_Name></Src_Name><Src_Number>1</Src_Number></Input_Sel_Item_Info></Input><Surround><Program_Sel><Current><Straight>Off</Straight><Enhancer>On</Enhancer><Sound_Program>Roleplaying Game</Sound_Program></Current></Program_Sel><_3D_Cinema_DSP>Off</_3D_Cinema_DSP><Dialogue_Lift>0</Dialogue_Lift></Surround><Pure_Direct><Mode>Off</Mode></Pure_Direct><Sound_Video><Tone><Bass><Val>-10</Val><Exp>1</Exp><Unit>dB</Unit></Bass><Treble><Val>0</Val><Exp>1</Exp><Unit>dB</Unit></Treble></Tone><Adaptive_DRC>Off</Adaptive_DRC></Sound_Video></Basic_Status></Main_Zone></YAMAHA_AV>
''';

const _putOk = '''
<YAMAHA_AV rsp="PUT" RC="0"><Main_Zone><Input><Input_Sel></Input_Sel></Input></Main_Zone></YAMAHA_AV>
''';

const _putRejected = '''
<YAMAHA_AV rsp="PUT" RC="4"><Main_Zone><Input><Input_Sel></Input_Sel></Input></Main_Zone></YAMAHA_AV>
''';

void main() {
  test('GET Basic_Status XML asks for GetParam', () {
    final xml = YamahaProtocol.getBasicStatusXml();
    expect(xml, contains('cmd="GET"'));
    expect(xml, contains('<Basic_Status>GetParam</Basic_Status>'));
  });

  test('PUT power / input / volume XML', () {
    expect(
      YamahaProtocol.setPowerXml(YamahaPower.on),
      contains('<Power>On</Power>'),
    );
    expect(
      YamahaProtocol.setPowerXml(YamahaPower.standby),
      contains('<Power>Standby</Power>'),
    );
    expect(
      YamahaProtocol.selectInputXml('HDMI2'),
      contains('<Input_Sel>HDMI2</Input_Sel>'),
    );
    expect(YamahaProtocol.setVolumeXml(-565), contains('<Val>-565</Val>'));
  });

  test('parseBasicStatus reads live GET and ignores Bass/Treble Val', () {
    final status = YamahaProtocol.parseBasicStatus(_liveBasicStatus);
    expect(
      status,
      const YamahaStatus(
        power: YamahaPower.standby,
        inputSel: 'HDMI4',
        volumeTenthsDb: -570,
        mute: false,
      ),
    );
  });

  test('parseBasicStatus returns null when RC is not 0', () {
    expect(YamahaProtocol.parseBasicStatus(_putRejected), isNull);
    expect(YamahaProtocol.parseBasicStatus('not xml'), isNull);
    expect(YamahaProtocol.parseBasicStatus(null), isNull);
  });

  test('parseRc reads PUT replies', () {
    expect(YamahaProtocol.parseRc(_putOk), 0);
    expect(YamahaProtocol.isOk(_putOk), isTrue);
    expect(YamahaProtocol.parseRc(_putRejected), 4);
    expect(YamahaProtocol.isOk(_putRejected), isFalse);
  });

  test('GET Input_Sel_Item XML asks for GetParam', () {
    final xml = YamahaProtocol.getInputSelItemXml();
    expect(xml, contains('cmd="GET"'));
    expect(xml, contains('<Input_Sel_Item>GetParam</Input_Sel_Item>'));
  });

  test('parseInputSelItems keeps RW items and skips R', () {
    const xml = '''
<YAMAHA_AV rsp="GET" RC="0"><Main_Zone><Input><Input_Sel_Item>
<Item_1><Param>HDMI4</Param><RW>RW</RW><Title>Mediaplay</Title></Item_1>
<Item_2><Param>HDMI2</Param><RW>RW</RW><Title>HDMI2</Title></Item_2>
<Item_3><Param>TUNER</Param><RW>R</RW><Title>TUNER</Title></Item_3>
</Input_Sel_Item></Input></Main_Zone></YAMAHA_AV>
''';
    expect(YamahaProtocol.parseInputSelItems(xml), [
      const YamahaInput(param: 'HDMI4', title: 'Mediaplay'),
      const YamahaInput(param: 'HDMI2', title: 'HDMI2'),
    ]);
  });

  test('parseInputSelItems returns null when RC is not 0', () {
    expect(YamahaProtocol.parseInputSelItems(_putRejected), isNull);
    expect(YamahaProtocol.parseInputSelItems(null), isNull);
  });

  test('clampVolumeTenthsDb stays in RX-V671 range', () {
    expect(YamahaProtocol.clampVolumeTenthsDb(-900), -805);
    expect(YamahaProtocol.clampVolumeTenthsDb(200), 165);
    expect(YamahaProtocol.clampVolumeTenthsDb(-570), -570);
  });
}

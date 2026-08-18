import 'package:internetradio/models/yamaha_status.dart';
import 'package:xml/xml.dart';
import 'package:xml/xpath.dart';

/// XML builders and parsers for Yamaha Network Control (YNC).
///
/// HTTP is always POST to [controlPath]. Success is XML `RC="0"`, not the
/// HTTP status alone.
abstract final class YamahaProtocol {
  static const String controlPath = '/YamahaRemoteControl/ctrl';

  static const int port = 80;

  static const Duration timeout = Duration(seconds: 2);

  /// RX-V671 Main Zone volume slider (`desc.xml`): tenths of a dB.
  static const int volumeMinTenthsDb = -805;
  static const int volumeMaxTenthsDb = 165;
  static const int volumeStepTenthsDb = 5;

  static const String _xmlHeader = '<?xml version="1.0" encoding="utf-8"?>';

  static const String _powerPath =
      '/YAMAHA_AV/Main_Zone/Basic_Status/Power_Control/Power';
  static const String _inputPath =
      '/YAMAHA_AV/Main_Zone/Basic_Status/Input/Input_Sel';
  static const String _volumePath =
      '/YAMAHA_AV/Main_Zone/Basic_Status/Volume/Lvl/Val';
  static const String _mutePath =
      '/YAMAHA_AV/Main_Zone/Basic_Status/Volume/Mute';
  static const String _rcPath = '/YAMAHA_AV/@RC';

  static String getBasicStatusXml() {
    return '$_xmlHeader'
        '<YAMAHA_AV cmd="GET">'
        '<Main_Zone><Basic_Status>GetParam</Basic_Status></Main_Zone>'
        '</YAMAHA_AV>';
  }

  static String getInputSelItemXml() {
    return '$_xmlHeader'
        '<YAMAHA_AV cmd="GET">'
        '<Main_Zone><Input><Input_Sel_Item>GetParam</Input_Sel_Item></Input>'
        '</Main_Zone>'
        '</YAMAHA_AV>';
  }

  static String setPowerXml(YamahaPower power) {
    return '$_xmlHeader'
        '<YAMAHA_AV cmd="PUT">'
        '<Main_Zone><Power_Control><Power>${power.xmlValue}</Power>'
        '</Power_Control></Main_Zone>'
        '</YAMAHA_AV>';
  }

  static String selectInputXml(String inputSel) {
    return '$_xmlHeader'
        '<YAMAHA_AV cmd="PUT">'
        '<Main_Zone><Input><Input_Sel>$inputSel</Input_Sel></Input></Main_Zone>'
        '</YAMAHA_AV>';
  }

  /// Absolute volume. [tenthsDb] is tenths of a dB (`-570` = −57.0 dB).
  static String setVolumeXml(int tenthsDb) {
    return '$_xmlHeader'
        '<YAMAHA_AV cmd="PUT">'
        '<Main_Zone><Volume><Lvl>'
        '<Val>$tenthsDb</Val><Exp>1</Exp><Unit>dB</Unit>'
        '</Lvl></Volume></Main_Zone>'
        '</YAMAHA_AV>';
  }

  static int clampVolumeTenthsDb(int tenthsDb) {
    if (tenthsDb < volumeMinTenthsDb) {
      return volumeMinTenthsDb;
    }
    if (tenthsDb > volumeMaxTenthsDb) {
      return volumeMaxTenthsDb;
    }
    return tenthsDb;
  }

  /// `RC` attribute, or `null` if the document is not Yamaha XML.
  static int? parseRc(String? xml) {
    if (xml == null || xml.trim().isEmpty) {
      return null;
    }
    try {
      final document = XmlDocument.parse(xml);
      final raw = _xpathString(document, _rcPath);
      return raw == null ? null : int.tryParse(raw);
    } on XmlException {
      return null;
    }
  }

  static bool isOk(String? xml) => parseRc(xml) == 0;

  /// Parses GET `Basic_Status` when `RC` is `0`.
  static YamahaStatus? parseBasicStatus(String? xml) {
    if (xml == null || xml.trim().isEmpty) {
      return null;
    }
    try {
      final document = XmlDocument.parse(xml);
      if (_xpathString(document, _rcPath) != '0') {
        return null;
      }
      final power = YamahaPower.tryParse(
        _xpathString(document, _powerPath) ?? '',
      );
      final inputSel = _xpathString(document, _inputPath)?.trim();
      final volumeRaw = _xpathString(document, _volumePath);
      final muteRaw = _xpathString(document, _mutePath);
      final volumeTenthsDb = volumeRaw == null ? null : int.tryParse(volumeRaw);
      final mute = _parseOnOff(muteRaw);
      if (power == null ||
          inputSel == null ||
          inputSel.isEmpty ||
          volumeTenthsDb == null ||
          mute == null) {
        return null;
      }
      return YamahaStatus(
        power: power,
        inputSel: inputSel,
        volumeTenthsDb: volumeTenthsDb,
        mute: mute,
      );
    } on XmlException {
      return null;
    }
  }

  /// Parses GET `Input_Sel_Item` when `RC` is `0`. Skips read-only (`RW` = `R`) entries.
  static List<YamahaInput>? parseInputSelItems(String? xml) {
    if (xml == null || xml.trim().isEmpty) {
      return null;
    }
    try {
      final document = XmlDocument.parse(xml);
      if (_xpathString(document, _rcPath) != '0') {
        return null;
      }
      final items = <YamahaInput>[];
      // ignore: experimental_member_use
      for (final node in document.xpath(
        '/YAMAHA_AV/Main_Zone/Input/Input_Sel_Item//Param',
      )) {
        final param = node.innerText.trim();
        if (param.isEmpty) {
          continue;
        }
        final parent = node.parent;
        if (parent is! XmlElement) {
          continue;
        }
        final rw = parent.findElements('RW').firstOrNull?.innerText.trim();
        if (rw == 'R') {
          continue;
        }
        final title =
            parent.findElements('Title').firstOrNull?.innerText.trim() ?? '';
        items.add(
          YamahaInput(param: param, title: title.isEmpty ? param : title),
        );
      }
      return items;
    } on XmlException {
      return null;
    }
  }

  static bool? _parseOnOff(String? raw) {
    return switch (raw) {
      'On' => true,
      'Off' => false,
      _ => null,
    };
  }

  static String? _xpathString(XmlDocument document, String expression) {
    // ignore: experimental_member_use
    final node = document.xpath(expression).firstOrNull;
    if (node == null) {
      return null;
    }
    if (node is XmlAttribute) {
      return node.value;
    }
    return node.innerText;
  }
}

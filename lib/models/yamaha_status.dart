/// Main-zone power as reported / sent over Yamaha Network Control.
enum YamahaPower {
  on,
  standby;

  /// Wire value in GET/PUT XML (`On` / `Standby`).
  String get xmlValue => switch (this) {
    YamahaPower.on => 'On',
    YamahaPower.standby => 'Standby',
  };

  static YamahaPower? tryParse(String raw) {
    return switch (raw) {
      'On' => YamahaPower.on,
      'Standby' => YamahaPower.standby,
      _ => null,
    };
  }
}

/// Named Main Zone input from GET `Input_Sel_Item`.
class YamahaInput {
  const YamahaInput({required this.param, required this.title});

  /// Wire name for PUT `Input_Sel`, e.g. `HDMI4`.
  final String param;

  /// Receiver label, e.g. `Mediaplay`.
  final String title;

  /// [title] when set, otherwise [param].
  String get label => title.isEmpty ? param : title;

  @override
  bool operator ==(Object other) {
    return other is YamahaInput && other.param == param && other.title == title;
  }

  @override
  int get hashCode => Object.hash(param, title);
}

/// Snapshot of Main Zone from GET `Basic_Status`.
class YamahaStatus {
  const YamahaStatus({
    required this.power,
    required this.inputSel,
    required this.volumeTenthsDb,
    required this.mute,
  });

  final YamahaPower power;

  /// Yamaha input name, e.g. `HDMI4` or `AUDIO2`.
  final String inputSel;

  /// Volume in tenths of a dB (`-570` is −57.0 dB).
  final int volumeTenthsDb;

  /// `true` when the receiver reports mute `On`.
  final bool mute;

  YamahaStatus copyWith({
    YamahaPower? power,
    String? inputSel,
    int? volumeTenthsDb,
    bool? mute,
  }) {
    return YamahaStatus(
      power: power ?? this.power,
      inputSel: inputSel ?? this.inputSel,
      volumeTenthsDb: volumeTenthsDb ?? this.volumeTenthsDb,
      mute: mute ?? this.mute,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is YamahaStatus &&
        other.power == power &&
        other.inputSel == inputSel &&
        other.volumeTenthsDb == volumeTenthsDb &&
        other.mute == mute;
  }

  @override
  int get hashCode => Object.hash(power, inputSel, volumeTenthsDb, mute);
}

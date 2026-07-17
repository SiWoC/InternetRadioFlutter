/// One radio station from build-time config (`assets/settings.json`).
class RadioStation {
  const RadioStation({
    required this.name,
    required this.url,
    this.imageAssetPath,
  });

  final String name;
  final String url;

  /// Flutter asset key, e.g. `assets/images/triplej.png`. Null = name fallback in UI.
  final String? imageAssetPath;

  factory RadioStation.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final url = json['url'] as String?;
    if (name == null || name.isEmpty) {
      throw FormatException('RadioStation missing name: $json');
    }
    if (url == null || url.isEmpty) {
      throw FormatException('RadioStation missing url: $json');
    }
    final imageAssetPath = json['imageAssetPath'] as String?;
    return RadioStation(
      name: name,
      url: url,
      imageAssetPath:
          (imageAssetPath == null || imageAssetPath.isEmpty) ? null : imageAssetPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'url': url,
      if (imageAssetPath != null) 'imageAssetPath': imageAssetPath,
    };
  }

  /// Parses the root object of `settings.json`.
  static List<RadioStation> listFromSettingsJson(Map<String, dynamic> root) {
    final raw = root['stations'];
    if (raw is! List) {
      throw const FormatException('settings.json missing stations list');
    }
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>)
          RadioStation.fromJson(item)
        else if (item is Map)
          RadioStation.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  RadioStation copyWith({
    String? name,
    String? url,
    String? imageAssetPath,
  }) {
    return RadioStation(
      name: name ?? this.name,
      url: url ?? this.url,
      imageAssetPath: imageAssetPath ?? this.imageAssetPath,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RadioStation &&
        other.name == name &&
        other.url == url &&
        other.imageAssetPath == imageAssetPath;
  }

  @override
  int get hashCode => Object.hash(name, url, imageAssetPath);
}

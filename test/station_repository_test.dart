import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/models/radio_station.dart';
import 'package:internetradio/services/station_repository.dart';

void main() {
  test('listFromSettingsJson parses stations', () {
    final stations = RadioStation.listFromSettingsJson({
      'stations': [
        {
          'name': 'Q-Music',
          'url': 'https://example.com/q',
          'imageAssetPath': 'assets/images/qmusic.png',
        },
        {
          'name': 'URL test',
          'url': 'https://example.com/test',
        },
      ],
    });

    expect(stations, hasLength(2));
    expect(stations.first.name, 'Q-Music');
    expect(stations.first.imageAssetPath, 'assets/images/qmusic.png');
    expect(stations.last.imageAssetPath, isNull);
  });

  test('StationRepository treats last station as URL test slot', () {
    final repo = StationRepository([
      const RadioStation(name: 'A', url: 'https://a.example'),
      const RadioStation(name: 'B', url: 'https://b.example'),
      const RadioStation(name: 'URL test', url: 'https://test.example'),
    ]);

    expect(repo.gridStations, hasLength(2));
    expect(repo.urlTestStation?.name, 'URL test');
    expect(repo.byName('B')?.url, 'https://b.example');
    expect(repo.byIndex(0)?.name, 'A');
  });

  test('fallbacks contain Triple J, Q-Music, 538', () {
    final names = StationRepository.fallbacks.map((s) => s.name).toList();
    expect(names, containsAll(['ABC Triple J NSW', 'Q-Music', 'Radio 538']));
  });
}

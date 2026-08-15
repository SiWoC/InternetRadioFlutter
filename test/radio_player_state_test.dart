import 'package:flutter_test/flutter_test.dart';
import 'package:internetradio/models/radio_player_state.dart';

void main() {
  test('fromMap reads stream station name and now-playing', () {
    final state = RadioPlayerState.fromMap({
      'url': 'https://a.example',
      'playbackState': 'Ready',
      'isPlaying': true,
      'isMuted': false,
      'streamStationName': 'Icecast One',
      'nowPlaying': 'Queen - Bohemian Rhapsody',
    });

    expect(state.streamStationName, 'Icecast One');
    expect(state.nowPlaying, 'Queen - Bohemian Rhapsody');
  });

  test('fromMap leaves stream metadata null when omitted', () {
    final state = RadioPlayerState.fromMap({
      'playbackState': 'Idle',
      'isPlaying': false,
    });

    expect(state.streamStationName, isNull);
    expect(state.nowPlaying, isNull);
  });
}

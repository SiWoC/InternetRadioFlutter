import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:internetradio/services/media3_radio_player.dart';

void main() {
  runApp(const InternetRadioApp());
}

class InternetRadioApp extends StatelessWidget {
  const InternetRadioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Internet Radio PoC',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const RadioPocScreen(),
    );
  }
}

class _TestStream {
  const _TestStream({
    required this.name,
    required this.url,
    required this.note,
  });

  final String name;
  final String url;
  final String note;
}

const _testStreams = [
  _TestStream(
    name: 'Triple J NSW',
    url: 'https://abc.streamguys1.com/live/triplejnsw/icecast.audio',
    note: 'Failed in FMOD — icecast stream',
  ),
  _TestStream(
    name: 'All Time Hits',
    url: 'https://stream.alltimehits.eu/listen.mp3',
    note: 'Worked in FMOD — MP3 stream',
  ),
];

class RadioPocScreen extends StatefulWidget {
  const RadioPocScreen({super.key});

  @override
  State<RadioPocScreen> createState() => _RadioPocScreenState();
}

class _RadioPocScreenState extends State<RadioPocScreen> {
  final _player = Media3RadioPlayer();
  RadioPlayerState _state = const RadioPlayerState();
  StreamSubscription<RadioPlayerState>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _player.stateStream.listen((state) {
      setState(() => _state = state);
    });
    _player.refreshState();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _play(String url) async {
    try {
      await _player.play(url);
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Play failed: ${error.message}')),
      );
    }
  }

  Future<void> _stop() async {
    await _player.stop();
  }

  Future<void> _toggleMute() async {
    await _player.setMuted(!_state.isMuted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media3 Stream PoC'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status: ${_state.statusLabel}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_state.isPlaying || _state.playbackState == 'buffering') ...[
                      const SizedBox(height: 8),
                      Text(
                        'Buffer: ${(_state.totalBufferedDurationMs / 1000).toStringAsFixed(1)}s',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (_state.url != null)
                      Text(
                        _state.url!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            for (final stream in _testStreams) ...[
              FilledButton.tonal(
                onPressed: () => _play(stream.url),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stream.name),
                      Text(
                        stream.note,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _state.url == null ? null : _toggleMute,
                    icon: Icon(_state.isMuted ? Icons.volume_off : Icons.volume_up),
                    label: Text(_state.isMuted ? 'Unmute' : 'Mute'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _state.url == null ? null : _stop,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

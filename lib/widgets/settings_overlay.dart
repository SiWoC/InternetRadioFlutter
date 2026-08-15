import 'package:flutter/material.dart';
import 'package:internetradio/models/app_settings.dart';

/// Full-screen settings layer: player IP, URL test, display policy, save/close.
///
/// Absorbs all pointer events so chrome and station grid underneath do not
/// receive taps. Callers track open state for screensaver suppression.
class SettingsOverlay extends StatefulWidget {
  const SettingsOverlay({
    super.key,
    required this.initialPlayerIp,
    required this.initialTestUrl,
    required this.displayPolicy,
    required this.onTestConnection,
    required this.onPersistIp,
    required this.onPlayTestUrl,
    required this.onDisplayPolicyChanged,
    required this.onSaveAndClose,
    this.bannerMessage,
  });

  final String initialPlayerIp;
  final String initialTestUrl;

  /// Applied as a wakelock only while this device is in Player mode.
  final DisplayPolicy displayPolicy;

  /// Optional warning shown at the top (e.g. invalid player IP).
  final String? bannerMessage;

  /// Returns whether `PING`/`PONG` succeeded for [ip].
  final Future<bool> Function(String ip) onTestConnection;

  /// Persists [ip] after a successful connection test (Unity parity).
  final Future<void> Function(String ip) onPersistIp;

  /// Plays [testUrl] on the URL-test slot (Player) or sends `TESTURL` (Remote).
  final Future<void> Function(String testUrl) onPlayTestUrl;

  /// Persists and applies [policy] immediately.
  final Future<void> Function(DisplayPolicy policy) onDisplayPolicyChanged;

  /// Persists [ip] and [testUrl] (either may be empty) and dismisses the overlay.
  final Future<void> Function(String ip, String testUrl) onSaveAndClose;

  @override
  State<SettingsOverlay> createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<SettingsOverlay> {
  static const _panelColor = Color(0xFF0F4A5E);
  static const _fieldFill = Color(0xFF0A3D4F);

  late final TextEditingController _ipController;
  late final TextEditingController _urlController;
  late DisplayPolicy _displayPolicy;
  String _testResult = '';
  String _urlResult = '';
  bool _testing = false;
  bool _playingUrl = false;
  bool _saving = false;

  bool get _busy => _testing || _playingUrl || _saving;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.initialPlayerIp);
    _urlController = TextEditingController(text: widget.initialTestUrl);
    _displayPolicy = widget.displayPolicy;
  }

  @override
  void dispose() {
    _ipController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _onTest() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() => _testResult = 'Error: No IP');
      return;
    }

    setState(() {
      _testing = true;
      _testResult = 'Testing...';
    });

    final ok = await widget.onTestConnection(ip);
    if (!mounted) {
      return;
    }

    if (ok) {
      await widget.onPersistIp(ip);
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _testing = false;
      _testResult = ok ? 'OK' : 'Error';
    });
  }

  Future<void> _onPlayUrl() async {
    final testUrl = _urlController.text.trim();
    if (testUrl.isEmpty) {
      setState(() => _urlResult = 'Error: No URL');
      return;
    }

    setState(() {
      _playingUrl = true;
      _urlResult = '';
    });
    try {
      await widget.onPlayTestUrl(testUrl);
    } finally {
      if (mounted) {
        setState(() => _playingUrl = false);
      }
    }
  }

  Future<void> _onDisplayPolicyChanged(bool keepOn) async {
    final policy =
        keepOn ? DisplayPolicy.keepScreenOn : DisplayPolicy.allowScreenOff;
    setState(() => _displayPolicy = policy);
    await widget.onDisplayPolicyChanged(policy);
  }

  Future<void> _onSave() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSaveAndClose(
        _ipController.text.trim(),
        _urlController.text.trim(),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final gap = isLandscape ? 8.0 : 12.0;
    final panelPad = isLandscape ? 12.0 : 16.0;

    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: EdgeInsets.all(isLandscape ? 12 : 16),
              child: Material(
                color: _panelColor,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(panelPad),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Settings',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.bannerMessage != null) ...[
                        SizedBox(height: gap),
                        Text(
                          widget.bannerMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      SizedBox(height: gap),
                      const Text(
                        'Player IP address',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _ipController,
                        enabled: !_busy,
                        keyboardType: TextInputType.text,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration('e.g. 192.168.1.10'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: _busy ? null : _onTest,
                            style: _compactButton,
                            child: const Text('Test Connection'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _testResult,
                              style: TextStyle(
                                color: _statusColor(_testResult),
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: gap),
                      const Text(
                        'Test stream URL',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _urlController,
                              enabled: !_busy,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              enableSuggestions: false,
                              style: const TextStyle(color: Colors.white),
                              decoration: _fieldDecoration('https://…'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _busy ? null : _onPlayUrl,
                            style: _compactButton,
                            child: const Text('Play'),
                          ),
                        ],
                      ),
                      if (_urlResult.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _urlResult,
                          style: TextStyle(
                            color: _statusColor(_urlResult),
                            fontSize: 16,
                          ),
                        ),
                      ],
                      SizedBox(height: gap),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text(
                          'Keep screen on',
                          style: TextStyle(color: Colors.white),
                        ),
                        value: _displayPolicy == DisplayPolicy.keepScreenOn,
                        onChanged: _busy ? null : _onDisplayPolicyChanged,
                      ),
                      SizedBox(height: isLandscape ? 12.0 : 20.0),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: _busy ? null : _onSave,
                          style: _compactButton,
                          child: const Text('Save and Exit'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static final _compactButton = FilledButton.styleFrom(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  static InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: _fieldFill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: const OutlineInputBorder(),
    );
  }

  static Color _statusColor(String result) {
    if (result == 'OK') {
      return Colors.lightGreenAccent;
    }
    if (result.startsWith('Error')) {
      return Colors.orangeAccent;
    }
    return Colors.white70;
  }
}

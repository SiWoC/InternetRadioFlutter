import 'package:flutter/material.dart';

/// Full-screen settings layer: player IP, connection test, save/close.
///
/// Absorbs all pointer events so chrome and station grid underneath do not
/// receive taps. Callers track open state for screensaver suppression.
class SettingsOverlay extends StatefulWidget {
  const SettingsOverlay({
    super.key,
    required this.initialPlayerIp,
    required this.onTestConnection,
    required this.onPersistIp,
    required this.onSaveAndClose,
    this.bannerMessage,
  });

  final String initialPlayerIp;

  /// Optional warning shown at the top (e.g. invalid player IP).
  final String? bannerMessage;

  /// Returns whether `PING`/`PONG` succeeded for [ip].
  final Future<bool> Function(String ip) onTestConnection;

  /// Persists [ip] after a successful connection test (Unity parity).
  final Future<void> Function(String ip) onPersistIp;

  /// Persists [ip] (may be empty) and dismisses the overlay.
  final Future<void> Function(String ip) onSaveAndClose;

  @override
  State<SettingsOverlay> createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<SettingsOverlay> {
  static const _panelColor = Color(0xFF0F4A5E);

  late final TextEditingController _ipController;
  String _testResult = '';
  bool _testing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.initialPlayerIp);
  }

  @override
  void dispose() {
    _ipController.dispose();
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

  Future<void> _onSave() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSaveAndClose(_ipController.text.trim());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _panelColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Settings',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.bannerMessage != null) ...[
                        const SizedBox(height: 12),
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
                      const SizedBox(height: 20),
                      const Text(
                        'Player IP address',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _ipController,
                        enabled: !_testing && !_saving,
                        keyboardType: TextInputType.text,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'e.g. 192.168.1.10',
                          hintStyle: TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Color(0xFF0A3D4F),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: _testing || _saving ? null : _onTest,
                            child: const Text('Test Connection'),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              _testResult,
                              style: TextStyle(
                                color: _testResult == 'OK'
                                    ? Colors.lightGreenAccent
                                    : _testResult.startsWith('Error')
                                        ? Colors.orangeAccent
                                        : Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: _testing || _saving ? null : _onSave,
                          child: const Text('Save'),
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
}

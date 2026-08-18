import 'package:flutter/material.dart';
import 'package:internetradio/models/app_settings.dart';

/// Full-screen settings layer: player IP, Yamaha IP, URL test,
/// display policy, save/close.
///
/// Absorbs all pointer events so chrome and station grid underneath do not
/// receive taps. Callers track open state for screensaver suppression.
class SettingsOverlay extends StatefulWidget {
  const SettingsOverlay({
    super.key,
    required this.initialPlayerIp,
    required this.initialTestUrl,
    required this.initialYamahaIp,
    required this.displayPolicy,
    required this.onTestPlayerConnection,
    required this.onPersistPlayerIp,
    required this.onFindPlayer,
    required this.onTestYamahaConnection,
    required this.onPersistYamahaIp,
    required this.onFindYamaha,
    required this.onPlayTestUrl,
    required this.onDisplayPolicyChanged,
    required this.onSaveAndClose,
    this.bannerMessage,
  });

  final String initialPlayerIp;
  final String initialTestUrl;
  final String initialYamahaIp;

  /// Applied as a wakelock only while this device is in Player mode.
  final DisplayPolicy displayPolicy;

  /// Optional warning shown at the top (e.g. invalid player IP).
  final String? bannerMessage;

  /// Returns whether `PING`/`PONG` succeeded for [ip].
  final Future<bool> Function(String ip) onTestPlayerConnection;

  /// Persists [ip] after a successful player connection test.
  final Future<void> Function(String ip) onPersistPlayerIp;

  /// /24 player sweep: after [currentIp] when it is on this LAN, else from `.1`.
  final Future<String?> Function(String currentIp) onFindPlayer;

  /// Returns whether GET `Basic_Status` succeeded for [ip].
  final Future<bool> Function(String ip) onTestYamahaConnection;

  /// Persists [ip] after a successful Yamaha connection test.
  final Future<void> Function(String ip) onPersistYamahaIp;

  /// SSDP find for a Yamaha receiver, next after [currentIp].
  final Future<String?> Function(String currentIp) onFindYamaha;

  /// Plays [testUrl] on the URL-test slot (Player) or sends `TESTURL` (Remote).
  final Future<void> Function(String testUrl) onPlayTestUrl;

  /// Persists and applies [policy] immediately.
  final Future<void> Function(DisplayPolicy policy) onDisplayPolicyChanged;

  /// Persists fields (empty allowed) and dismisses the overlay.
  final Future<void> Function({
    required String playerIp,
    required String testUrl,
    required String yamahaIp,
  })
  onSaveAndClose;

  @override
  State<SettingsOverlay> createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<SettingsOverlay> {
  static const _panelColor = Color(0xFF0F4A5E);
  static const _fieldFill = Color(0xFF0A3D4F);

  late final TextEditingController _ipController;
  late final TextEditingController _urlController;
  late final TextEditingController _yamahaIpController;
  late DisplayPolicy _displayPolicy;
  String _testResult = '';
  String _yamahaTestResult = '';
  String _urlResult = '';
  bool _testing = false;
  bool _yamahaTesting = false;
  bool _findingPlayer = false;
  bool _findingYamaha = false;
  bool _playingUrl = false;
  bool _saving = false;

  bool get _busy =>
      _testing ||
      _yamahaTesting ||
      _findingPlayer ||
      _findingYamaha ||
      _playingUrl ||
      _saving;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.initialPlayerIp);
    _urlController = TextEditingController(text: widget.initialTestUrl);
    _yamahaIpController = TextEditingController(text: widget.initialYamahaIp);
    _displayPolicy = widget.displayPolicy;
  }

  @override
  void dispose() {
    _ipController.dispose();
    _urlController.dispose();
    _yamahaIpController.dispose();
    super.dispose();
  }

  Future<void> _onTest() async {
    await _runIpTest(
      ip: _ipController.text.trim(),
      setTesting: (value) => _testing = value,
      setResult: (value) => _testResult = value,
      onTest: widget.onTestPlayerConnection,
      onPersist: widget.onPersistPlayerIp,
    );
  }

  Future<void> _onTestYamaha() async {
    await _runIpTest(
      ip: _yamahaIpController.text.trim(),
      setTesting: (value) => _yamahaTesting = value,
      setResult: (value) => _yamahaTestResult = value,
      onTest: widget.onTestYamahaConnection,
      onPersist: widget.onPersistYamahaIp,
    );
  }

  Future<void> _onFindPlayer() {
    return _runFind(
      currentIp: _ipController.text.trim(),
      field: _ipController,
      setFinding: (value) => _findingPlayer = value,
      setResult: (value) => _testResult = value,
      onFind: widget.onFindPlayer,
      onPersist: widget.onPersistPlayerIp,
    );
  }

  Future<void> _onFindYamaha() {
    return _runFind(
      currentIp: _yamahaIpController.text.trim(),
      field: _yamahaIpController,
      setFinding: (value) => _findingYamaha = value,
      setResult: (value) => _yamahaTestResult = value,
      onFind: widget.onFindYamaha,
      onPersist: widget.onPersistYamahaIp,
    );
  }

  Future<void> _runIpTest({
    required String ip,
    required void Function(bool value) setTesting,
    required void Function(String value) setResult,
    required Future<bool> Function(String ip) onTest,
    required Future<void> Function(String ip) onPersist,
  }) async {
    if (ip.isEmpty) {
      setState(() => setResult('Error: No IP'));
      return;
    }

    setState(() {
      setTesting(true);
      setResult('Testing...');
    });

    final ok = await onTest(ip);
    if (!mounted) {
      return;
    }

    if (ok) {
      await onPersist(ip);
    }
    if (!mounted) {
      return;
    }

    setState(() {
      setTesting(false);
      setResult(ok ? 'OK' : 'Error');
    });
  }

  Future<void> _runFind({
    required String currentIp,
    required TextEditingController field,
    required void Function(bool value) setFinding,
    required void Function(String value) setResult,
    required Future<String?> Function(String currentIp) onFind,
    required Future<void> Function(String ip) onPersist,
  }) async {
    setState(() {
      setFinding(true);
      setResult('Searching...');
    });

    final ip = await onFind(currentIp);
    if (!mounted) {
      return;
    }

    if (ip != null) {
      field.text = ip;
      await onPersist(ip);
    }
    if (!mounted) {
      return;
    }

    setState(() {
      setFinding(false);
      setResult(ip != null ? 'OK' : 'Error: Not found');
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
    final policy = keepOn
        ? DisplayPolicy.keepScreenOn
        : DisplayPolicy.allowScreenOff;
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
        playerIp: _ipController.text.trim(),
        testUrl: _urlController.text.trim(),
        yamahaIp: _yamahaIpController.text.trim(),
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
                          fontSize: 16,
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
                      _ipTestRow(
                        label: 'Player IP address',
                        hint: 'e.g. 192.168.1.10',
                        controller: _ipController,
                        findTooltip: 'Find player',
                        onFind: _onFindPlayer,
                        onTest: _onTest,
                        result: _testResult,
                      ),
                      SizedBox(height: gap),
                      _ipTestRow(
                        label: 'Yamaha Receiver IP address',
                        hint: 'e.g. 192.168.2.2',
                        controller: _yamahaIpController,
                        findTooltip: 'Find receiver',
                        onFind: _onFindYamaha,
                        onTest: _onTestYamaha,
                        result: _yamahaTestResult,
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

  Widget _ipTestRow({
    required String label,
    required String hint,
    required TextEditingController controller,
    required String findTooltip,
    required VoidCallback onFind,
    required VoidCallback onTest,
    required String result,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !_busy,
                keyboardType: TextInputType.text,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration(hint),
              ),
            ),
            IconButton(
              tooltip: findTooltip,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: EdgeInsets.zero,
              onPressed: _busy ? null : onFind,
              icon: const Icon(Icons.wifi_find),
              color: Colors.white70,
            ),
            FilledButton(
              onPressed: _busy ? null : onTest,
              style: _compactButton,
              child: const Text('Test'),
            ),
          ],
        ),
        if (result.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            result,
            style: TextStyle(color: _statusColor(result), fontSize: 16),
          ),
        ],
      ],
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

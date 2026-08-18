import 'package:flutter/material.dart';
import 'package:internetradio/models/yamaha_status.dart';

/// Full-screen Yamaha remote: power, input, volume.
///
/// Absorbs all pointer events so chrome and station grid underneath do not
/// receive taps. Callers track open state for screensaver suppression.
class YamahaOverlay extends StatelessWidget {
  const YamahaOverlay({
    super.key,
    required this.status,
    required this.inputs,
    required this.busy,
    required this.onPower,
    required this.onSelectInput,
    required this.onVolumeUp,
    required this.onVolumeDown,
    required this.onClose,
  });

  final YamahaStatus? status;
  final List<YamahaInput> inputs;
  final bool busy;
  final VoidCallback onPower;
  final ValueChanged<String> onSelectInput;
  final VoidCallback onVolumeUp;
  final VoidCallback onVolumeDown;
  final VoidCallback onClose;

  static const _panelColor = Color(0xFF0F4A5E);
  static const _fieldFill = Color(0xFF0A3D4F);

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final gap = isLandscape ? 8.0 : 12.0;
    final panelPad = isLandscape ? 12.0 : 16.0;
    final snapshot = status;
    final enabled = snapshot != null;
    final dropdownItems = _dropdownItems(snapshot);

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
                        'Yamaha',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: gap),
                      _statusLine(snapshot),
                      SizedBox(height: gap),
                      Align(
                        alignment: Alignment.center,
                        child: IconButton(
                          onPressed: enabled ? onPower : null,
                          tooltip: snapshot?.power == YamahaPower.on
                              ? 'Standby'
                              : 'Power on',
                          iconSize: 48,
                          icon: Icon(
                            Icons.power_settings_new,
                            color: snapshot?.power == YamahaPower.on
                                ? Colors.lightGreenAccent
                                : Colors.white70,
                          ),
                        ),
                      ),
                      SizedBox(height: gap),
                      const Text(
                        'Input',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: _fieldFill,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _selectedParam(snapshot, dropdownItems),
                              dropdownColor: _fieldFill,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              hint: const Text(
                                '—',
                                style: TextStyle(color: Colors.white38),
                              ),
                              items: [
                                for (final input in dropdownItems)
                                  DropdownMenuItem(
                                    value: input.param,
                                    child: Text(input.label),
                                  ),
                              ],
                              onChanged: enabled && dropdownItems.isNotEmpty
                                  ? (value) {
                                      if (value != null) {
                                        onSelectInput(value);
                                      }
                                    }
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: gap),
                      Row(
                        children: [
                          IconButton(
                            onPressed: enabled ? onVolumeDown : null,
                            tooltip: 'Volume down',
                            icon: const Icon(Icons.remove, color: Colors.white),
                          ),
                          Expanded(
                            child: Text(
                              snapshot == null
                                  ? '— dB'
                                  : _volumeLabel(snapshot.volumeTenthsDb),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: enabled ? onVolumeUp : null,
                            tooltip: 'Volume up',
                            icon: const Icon(Icons.add, color: Colors.white),
                          ),
                        ],
                      ),
                      SizedBox(height: isLandscape ? 12.0 : 20.0),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: onClose,
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Close'),
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

  Widget _statusLine(YamahaStatus? snapshot) {
    final String text;
    final Color color;
    if (snapshot == null) {
      text = busy ? 'Connecting...' : 'Unreachable';
      color = busy ? Colors.white70 : Colors.orangeAccent;
    } else {
      text = snapshot.power == YamahaPower.on ? 'On' : 'Standby';
      color = snapshot.power == YamahaPower.on
          ? Colors.lightGreenAccent
          : Colors.white70;
    }
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600),
    );
  }

  List<YamahaInput> _dropdownItems(YamahaStatus? snapshot) {
    final items = [...inputs];
    final current = snapshot?.inputSel.trim() ?? '';
    if (current.isNotEmpty && !items.any((input) => input.param == current)) {
      items.add(YamahaInput(param: current, title: current));
    }
    return items;
  }

  String? _selectedParam(YamahaStatus? snapshot, List<YamahaInput> items) {
    final current = snapshot?.inputSel.trim() ?? '';
    if (current.isEmpty) {
      return null;
    }
    if (items.any((input) => input.param == current)) {
      return current;
    }
    return null;
  }

  static String _volumeLabel(int tenthsDb) {
    return '${(tenthsDb / 10).toStringAsFixed(1)} dB';
  }
}

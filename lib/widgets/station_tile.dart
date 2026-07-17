import 'package:flutter/material.dart';
import 'package:internetradio/models/radio_station.dart';

/// One station button: logo or name fallback, selected highlight.
class StationTile extends StatelessWidget {
  const StationTile({
    super.key,
    required this.station,
    required this.selected,
    required this.onTap,
  });

  final RadioStation station;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? Colors.white : Colors.transparent,
              width: 3,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: _StationImage(station: station),
          ),
        ),
      ),
    );
  }
}

class _StationImage extends StatelessWidget {
  const _StationImage({required this.station});

  final RadioStation station;

  @override
  Widget build(BuildContext context) {
    final path = station.imageAssetPath;
    if (path == null) {
      return _NameFallback(name: station.name);
    }
    return Image.asset(
      path,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _NameFallback(name: station.name),
    );
  }
}

class _NameFallback extends StatelessWidget {
  const _NameFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF4A2A6A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

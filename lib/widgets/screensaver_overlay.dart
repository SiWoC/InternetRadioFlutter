import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:internetradio/models/radio_station.dart';

/// Full-screen bouncing station logo; tap dismisses.
///
/// Random start position/velocity; wall hits keep speed and pick a new
/// random outward quadrant.
class ScreensaverOverlay extends StatefulWidget {
  const ScreensaverOverlay({
    super.key,
    required this.station,
    required this.onDismiss,
  });

  final RadioStation? station;
  final VoidCallback onDismiss;

  @override
  State<ScreensaverOverlay> createState() => _ScreensaverOverlayState();
}

class _ScreensaverOverlayState extends State<ScreensaverOverlay>
    with SingleTickerProviderStateMixin {
  static const _logoSize = 140.0;

  /// Bounce speed in logical px / second.
  static const _bounceSpeed = 200.0;

  late final Ticker _ticker;
  final _random = math.Random();
  Offset _position = Offset.zero;
  Offset _velocity = Offset.zero;
  Duration? _lastElapsed;
  var _placed = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) {
      return;
    }

    final size = MediaQuery.sizeOf(context);
    final maxX = (size.width - _logoSize).clamp(0.0, double.infinity);
    final maxY = (size.height - _logoSize).clamp(0.0, double.infinity);

    if (!_placed) {
      _setRandomPositionAndVelocity(maxX, maxY);
      _placed = true;
      _lastElapsed = elapsed;
      setState(() {});
      return;
    }

    final last = _lastElapsed;
    _lastElapsed = elapsed;
    if (last == null) {
      return;
    }

    final dt = (elapsed - last).inMicroseconds / 1e6;
    if (dt <= 0) {
      return;
    }

    var x = _position.dx + _velocity.dx * dt;
    var y = _position.dy + _velocity.dy * dt;
    var vx = _velocity.dx;
    var vy = _velocity.dy;
    final speed = _velocity.distance;

    // Right wall → NW if moving up, SW if moving down.
    if (x > maxX) {
      final goingNorth = vy < 0;
      final degrees = goingNorth
          ? _random.nextDouble() * 90 + 90 // 90–180 → NW
          : _random.nextDouble() * 90 + 180; // 180–270 → SW
      final v = _velocityFromAngle(degrees, speed);
      vx = v.dx;
      vy = v.dy;
      x = maxX;
    }

    // Left wall → NE if moving up, SE if moving down.
    if (x < 0) {
      final goingNorth = vy < 0;
      final degrees = goingNorth
          ? _random.nextDouble() * 90 // 0–90 → NE
          : _random.nextDouble() * 90 + 270; // 270–360 → SE
      final v = _velocityFromAngle(degrees, speed);
      vx = v.dx;
      vy = v.dy;
      x = 0;
    }

    // Top wall → SE if moving right, SW if moving left.
    if (y < 0) {
      final goingEast = vx > 0;
      final degrees = goingEast
          ? _random.nextDouble() * 90 + 270 // 270–360 → SE
          : _random.nextDouble() * 90 + 180; // 180–270 → SW
      final v = _velocityFromAngle(degrees, speed);
      vx = v.dx;
      vy = v.dy;
      y = 0;
    }

    // Bottom wall → NE if moving right, NW if moving left.
    if (y > maxY) {
      final goingEast = vx > 0;
      final degrees = goingEast
          ? _random.nextDouble() * 90 // 0–90 → NE
          : _random.nextDouble() * 90 + 90; // 90–180 → NW
      final v = _velocityFromAngle(degrees, speed);
      vx = v.dx;
      vy = v.dy;
      y = maxY;
    }

    setState(() {
      _position = Offset(x, y);
      _velocity = Offset(vx, vy);
    });
  }

  /// Random position inside the play area and random velocity on each axis.
  void _setRandomPositionAndVelocity(double maxX, double maxY) {
    _position = Offset(
      _random.nextDouble() * maxX,
      _random.nextDouble() * maxY,
    );
    _velocity = Offset(
      (_random.nextDouble() * 2 - 1) * _bounceSpeed,
      (_random.nextDouble() * 2 - 1) * _bounceSpeed,
    );
  }

  /// Screen-up angles (0° = east, 90° = north) → Flutter velocity (y grows down).
  Offset _velocityFromAngle(double degrees, double speed) {
    final radians = degrees * math.pi / 180;
    return Offset(
      math.cos(radians) * speed,
      -math.sin(radians) * speed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onDismiss,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned(
              left: _position.dx,
              top: _position.dy,
              width: _logoSize,
              height: _logoSize,
              child: _LogoBadge(station: widget.station),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoBadge extends StatelessWidget {
  const _LogoBadge({required this.station});

  final RadioStation? station;

  @override
  Widget build(BuildContext context) {
    final path = station?.imageAssetPath;
    if (path != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          path,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _NameFallback(name: station?.name ?? ''),
        ),
      );
    }
    return _NameFallback(name: station?.name ?? 'Radio');
  }
}

class _NameFallback extends StatelessWidget {
  const _NameFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF4A2A6A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

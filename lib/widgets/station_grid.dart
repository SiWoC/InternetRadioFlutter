import 'package:flutter/material.dart';
import 'package:internetradio/models/radio_station.dart';
import 'package:internetradio/widgets/station_tile.dart';

/// Scrollable station grid.
///
/// Portrait: 3 columns, vertical scroll.
/// Landscape: 3 rows, horizontal scroll.
class StationGrid extends StatelessWidget {
  const StationGrid({
    super.key,
    required this.stations,
    required this.selectedIndex,
    required this.onStationSelected,
  });

  final List<RadioStation> stations;
  final int? selectedIndex;
  final ValueChanged<int> onStationSelected;

  static const _spacing = 5.0;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final padding = EdgeInsets.symmetric(
      horizontal: isLandscape ? 20 : 50,
      vertical: isLandscape ? 10 : 15,
    );

    return GridView.builder(
      padding: padding,
      scrollDirection: isLandscape ? Axis.horizontal : Axis.vertical,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: _spacing,
        crossAxisSpacing: _spacing,
        childAspectRatio: 1,
      ),
      itemCount: stations.length,
      itemBuilder: (context, index) {
        return StationTile(
          station: stations[index],
          selected: selectedIndex == index,
          onTap: () => onStationSelected(index),
        );
      },
    );
  }
}

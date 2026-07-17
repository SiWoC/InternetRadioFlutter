import 'package:flutter/widgets.dart';
import 'package:internetradio/controllers/radio_controller.dart';

/// Injects the app-wide [RadioController] into the widget tree.
class AppScope extends InheritedNotifier<RadioController> {
  const AppScope({
    super.key,
    required RadioController controller,
    required super.child,
  }) : super(notifier: controller);

  static RadioController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found in context');
    return scope!.notifier!;
  }
}

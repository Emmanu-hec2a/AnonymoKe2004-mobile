import 'package:flutter_riverpod/flutter_riverpod.dart';

final discoveryRefreshSignal = NotifierProvider<DiscoveryRefreshSignal, int>(
  DiscoveryRefreshSignal.new,
);

class DiscoveryRefreshSignal extends Notifier<int> {
  @override
  int build() => 0;
  void notify() => state++;
}

// `doc/vs-bloc.md`, section "Typed methods with queued execution": what the page leaves out,
// then the code under its `### Solo` heading, verbatim, then what
// `vs_bloc_rakes_test.dart` adds on top of it. Every piece of the page's
// blocks is a run of lines of this file. The bloc side of the section is
// built and run by the bench, `tool/doc_snippets.py`: this package does not
// depend on bloc.
import 'dart:math';

import 'package:solo/solo.dart';

import 'vs_bloc_stubs.dart';

class MapApi {
  final trace = <String>[];

  Future<void> moveTo(Point<double> point, {CancelToken? cancelToken}) async {
    final n = point.x.toInt();
    trace.add('moveTo $n start');
    // Native calls do not all take the same time.
    for (var left = 80 - 20 * n; left > 0; left -= 10) {
      await tick(10);
      if (cancelToken?.cancelled ?? false) {
        trace.add('moveTo $n stopped');
        return;
      }
    }
    trace.add('moveTo $n end');
  }

  Future<void> setZoom(double value, {CancelToken? cancelToken}) async {
    for (var left = 20; left > 0; left -= 10) {
      await tick(10);
      if (cancelToken?.cancelled ?? false) {
        return;
      }
    }
  }
}

class MapState {
  const MapState({this.center = const Point<double>(0, 0), this.zoom = 1});

  final Point<double> center;
  final double zoom;

  MapState copyWith({Point<double>? center, double? zoom}) =>
      MapState(center: center ?? this.center, zoom: zoom ?? this.zoom);

  @override
  String toString() => 'MapState(${center.x.toInt()}, z${zoom.toInt()})';
}

// The code of the page.

enum MapKey { moveTo, setZoom }

final class MapController extends Solo<MapState> {
  final MapApi _map;

  MapController(this._map) : super(const MapState());

  Job<void> moveTo(Point<double> point) => run<MapState, void>(
        key: MapKey.moveTo,
        policy: Policy.restart,
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          await ctx.join(() => _map.moveTo(point, cancelToken: token));
          ctx.emit(ctx.state.copyWith(center: point));
        },
      );

  Job<void> setZoom(double value) => run<MapState, void>(
        key: MapKey.setZoom,
        policy: Policy.restart,
        (ctx) async {
          final token = CancelToken();
          ctx.onCancel(token.cancel);
          await ctx.join(() => _map.setZoom(value, cancelToken: token));
          ctx.emit(ctx.state.copyWith(zoom: value));
        },
      );
}

void onMapDrag(MapController map, Point<double> point) => map.moveTo(point);

// What the test adds.

/// A job that fails with nobody waiting for it.
final class FailingMapController extends Solo<MapState> {
  FailingMapController() : super(const MapState());

  Job<void> fail() => run<MapState, void>(
        (ctx) async => throw StateError('the map failed'),
      );
}

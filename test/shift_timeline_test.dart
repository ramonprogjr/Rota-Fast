import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rota_pizza/core/utils/shift_timeline.dart';
import 'package:rota_pizza/data/demo_shift_seed.dart';
import 'package:rota_pizza/models/shift.dart';

void main() {
  test('linha do tempo tem saída, 7 paradas e fim', () {
    final shift = Shift(
      id: 1,
      startedAt: DemoShiftData.startedAt,
      endedAt: DemoShiftData.endedAt,
      gpsKm: DemoShiftData.gpsKm,
    );
    final events = ShiftTimeline.build(
      shift: shift,
      points: DemoShiftData.trackPoints(1),
      completed: DemoShiftData.deliveries(),
      originName: 'Forno da Vila',
      origin: const LatLng(DemoShiftData.originLat, DemoShiftData.originLng),
    );

    expect(events.first.kind, TimelineKind.start);
    expect(events.last.kind, TimelineKind.end);
    expect(events.where((item) => item.kind == TimelineKind.stop), hasLength(7));
    expect(events[1].title, 'Marina Alves');
    expect(events[1].kmFromPrevious, greaterThan(0.5));
  });
}

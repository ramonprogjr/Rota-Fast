import 'package:latlong2/latlong.dart';
import 'package:rota_pizza/core/utils/haversine.dart';
import 'package:rota_pizza/models/delivery.dart';
import 'package:rota_pizza/models/shift.dart';

enum TimelineKind { start, stop, end }

class ShiftTimelineEvent {
  const ShiftTimelineEvent({
    required this.kind,
    required this.time,
    required this.title,
    required this.subtitle,
    this.point,
    this.kmFromPrevious,
    this.minutesFromPrevious,
    this.delivery,
    this.stopNumber,
  });

  final TimelineKind kind;
  final DateTime time;
  final String title;
  final String subtitle;
  final LatLng? point;
  final double? kmFromPrevious;
  final int? minutesFromPrevious;
  final Delivery? delivery;
  final int? stopNumber;
}

class ShiftTimeline {
  static List<ShiftTimelineEvent> build({
    required Shift shift,
    required List<TrackPoint> points,
    required List<Delivery> completed,
    required String originName,
    LatLng? origin,
  }) {
    final events = <ShiftTimelineEvent>[];
    var previousTime = shift.startedAt;
    var previousPoint = origin ??
        (points.isEmpty ? null : LatLng(points.first.latitude, points.first.longitude));

    events.add(
      ShiftTimelineEvent(
        kind: TimelineKind.start,
        time: shift.startedAt,
        title: 'Saída',
        subtitle: originName,
        point: previousPoint,
      ),
    );

    var number = 1;
    for (final delivery in completed) {
      final time = delivery.deliveredAt ?? delivery.createdAt;
      final point = delivery.hasCoordinates
          ? LatLng(delivery.latitude!, delivery.longitude!)
          : null;
      final km = _kmBetween(points, previousTime, time, previousPoint, point);
      events.add(
        ShiftTimelineEvent(
          kind: TimelineKind.stop,
          time: time,
          title: delivery.displayName,
          subtitle: [
            delivery.shortAddress,
            if (delivery.neighborhood != null &&
                delivery.neighborhood!.trim().isNotEmpty)
              delivery.neighborhood!.trim(),
          ].join(' · '),
          point: point,
          kmFromPrevious: km,
          minutesFromPrevious: time.difference(previousTime).inMinutes,
          delivery: delivery,
          stopNumber: number,
        ),
      );
      previousTime = time;
      previousPoint = point ?? previousPoint;
      number += 1;
    }

    final end = shift.endedAt;
    if (end != null) {
      final km = _kmBetween(points, previousTime, end, previousPoint, origin);
      events.add(
        ShiftTimelineEvent(
          kind: TimelineKind.end,
          time: end,
          title: 'Fim do turno',
          subtitle: originName,
          point: origin ?? previousPoint,
          kmFromPrevious: km,
          minutesFromPrevious: end.difference(previousTime).inMinutes,
        ),
      );
    }

    return events;
  }

  static double gpsKmInRange(
    List<TrackPoint> points,
    DateTime from,
    DateTime to,
  ) {
    if (points.length < 2) {
      return 0;
    }
    var km = 0.0;
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      if (curr.recordedAt.isBefore(from) || prev.recordedAt.isAfter(to)) {
        continue;
      }
      final step = haversineKm(
        prev.latitude,
        prev.longitude,
        curr.latitude,
        curr.longitude,
      );
      if (step >= 0.015 && step <= 2.5) {
        km += step;
      }
    }
    return km;
  }

  static List<LatLng> pathInRange(
    List<TrackPoint> points,
    DateTime from,
    DateTime to,
  ) {
    return points
        .where(
          (item) =>
              !item.recordedAt.isBefore(from) && !item.recordedAt.isAfter(to),
        )
        .map((item) => LatLng(item.latitude, item.longitude))
        .toList();
  }

  static double _kmBetween(
    List<TrackPoint> points,
    DateTime from,
    DateTime to,
    LatLng? a,
    LatLng? b,
  ) {
    final gps = gpsKmInRange(points, from, to);
    if (gps > 0.05) {
      return gps;
    }
    if (a == null || b == null) {
      return 0;
    }
    return haversineKm(a.latitude, a.longitude, b.latitude, b.longitude);
  }
}

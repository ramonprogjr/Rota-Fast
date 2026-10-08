import 'package:sqflite/sqflite.dart';
import 'package:rota_pizza/models/shift.dart';

abstract class ShiftRepository {
  Future<Shift?> openShift();
  Future<Shift> start(Shift shift);
  Future<void> update(Shift shift);
  Future<void> addPoint(TrackPoint point);
  Future<List<TrackPoint>> pointsFor(int shiftId);
  Future<Shift?> latestEnded();
}

class SqliteShiftRepository implements ShiftRepository {
  SqliteShiftRepository(this._db);

  final Database _db;

  @override
  Future<Shift?> openShift() async {
    final rows = await _db.query(
      'shifts',
      where: 'ended_at IS NULL',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Shift.fromMap(rows.first);
  }

  @override
  Future<Shift> start(Shift shift) async {
    final id = await _db.insert('shifts', shift.toMap()..remove('id'));
    return shift.copyWith(id: id);
  }

  @override
  Future<void> update(Shift shift) async {
    await _db.update(
      'shifts',
      shift.toMap(),
      where: 'id = ?',
      whereArgs: [shift.id],
    );
  }

  @override
  Future<void> addPoint(TrackPoint point) async {
    await _db.insert('track_points', point.toMap()..remove('id'));
  }

  @override
  Future<List<TrackPoint>> pointsFor(int shiftId) async {
    final rows = await _db.query(
      'track_points',
      where: 'shift_id = ?',
      whereArgs: [shiftId],
      orderBy: 'recorded_at ASC',
    );
    return rows.map(TrackPoint.fromMap).toList();
  }

  @override
  Future<Shift?> latestEnded() async {
    final rows = await _db.query(
      'shifts',
      where: 'ended_at IS NOT NULL',
      orderBy: 'ended_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Shift.fromMap(rows.first);
  }
}

class MemoryShiftRepository implements ShiftRepository {
  final List<Shift> _shifts = [];
  final List<TrackPoint> _points = [];
  int _nextShift = 1;
  int _nextPoint = 1;

  @override
  Future<Shift?> openShift() async {
    for (final shift in _shifts.reversed) {
      if (shift.isOpen) {
        return shift;
      }
    }
    return null;
  }

  @override
  Future<Shift> start(Shift shift) async {
    final saved = shift.copyWith(id: _nextShift++);
    _shifts.add(saved);
    return saved;
  }

  @override
  Future<void> update(Shift shift) async {
    final index = _shifts.indexWhere((item) => item.id == shift.id);
    if (index >= 0) {
      _shifts[index] = shift;
    }
  }

  @override
  Future<void> addPoint(TrackPoint point) async {
    _points.add(
      TrackPoint(
        id: _nextPoint++,
        shiftId: point.shiftId,
        latitude: point.latitude,
        longitude: point.longitude,
        recordedAt: point.recordedAt,
      ),
    );
  }

  @override
  Future<List<TrackPoint>> pointsFor(int shiftId) async {
    return _points.where((item) => item.shiftId == shiftId).toList();
  }

  @override
  Future<Shift?> latestEnded() async {
    final ended = _shifts.where((item) => !item.isOpen).toList();
    if (ended.isEmpty) {
      return null;
    }
    return ended.last;
  }
}

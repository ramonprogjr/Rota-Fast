import { Inject, Injectable } from '@nestjs/common';
import { DEFAULT_SPEED_KMH, type LatLng } from '../common/domain/geo';
import { NotFoundAppException, UnprocessableAppException } from '../common/exceptions/app.exception';
import { DATABASE, type Database } from '../persistence/data-store';
import { findOwned } from '../persistence/entity-writer';
import { loadStops } from '../routes/route-operations';
import type { OptimizationPreviewDto, OptimizationPreviewResponse } from './dto/optimization.dto';
import { optimize, type OptimizerStop } from './route-optimizer';

@Injectable()
export class OptimizationService {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /**
   * Propõe uma ordem. SÓ LÊ: nunca grava a rota. Para aplicar, o app chama
   * PATCH /v1/routes/:id/stops/reorder (ou manda um reorder no sync).
   */
  async preview(userId: string, dto: OptimizationPreviewDto): Promise<OptimizationPreviewResponse> {
    if (!dto.routeId && !dto.stops?.length) {
      throw new UnprocessableAppException('NOTHING_TO_OPTIMIZE', 'Envie routeId ou stops.');
    }
    let stops: OptimizerStop[];
    let start: LatLng | null = dto.origin ?? null;
    let end: LatLng | null = dto.end ?? null;
    if (dto.routeId) {
      const route = await findOwned(this.db.store, 'route', userId, dto.routeId);
      if (!route) {
        throw new NotFoundAppException('route');
      }
      const open = (await loadStops(this.db.store, route.id)).filter((s) => s.isOpen);
      stops = open.map(({ stop, delivery }) => ({
        id: stop.id,
        latitude: delivery.latitude,
        longitude: delivery.longitude,
        locked: stop.locked,
        fixedPosition: stop.fixedPosition,
      }));
      if (!start && route.originLat !== null && route.originLng !== null) {
        start = { latitude: route.originLat, longitude: route.originLng };
      }
      if (!end && route.endLat !== null && route.endLng !== null) {
        end = { latitude: route.endLat, longitude: route.endLng };
      }
    } else {
      stops = dto.stops!.map((s) => ({
        id: s.id,
        latitude: s.latitude ?? null,
        longitude: s.longitude ?? null,
        locked: s.locked ?? false,
        fixedPosition: s.fixedPosition ?? null,
      }));
      if (new Set(stops.map((s) => s.id)).size !== stops.length) {
        throw new UnprocessableAppException('DUPLICATE_STOPS', 'Ids de parada repetidos.');
      }
    }
    const result = optimize(stops, { start, end, speedKmh: dto.speedKmh ?? DEFAULT_SPEED_KMH });
    return {
      routeId: dto.routeId ?? null,
      ...result,
      savedKm: Math.round((result.baselineKm - result.optimizedKm) * 100) / 100,
      method: 'nearest-neighbour+2-opt; haversine x 1.3',
    };
  }
}

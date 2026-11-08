import { randomUUID } from 'node:crypto';
import { DeliveriesService } from '../deliveries/deliveries.service';
import type { CreateDeliveryDto } from '../deliveries/dto/delivery.dto';
import { DevicesService } from '../devices/devices.service';
import { OptimizationService } from '../optimization/optimization.service';
import { MemoryDatabase } from '../persistence/memory/memory-database';
import { RoutesService } from '../routes/routes.service';
import { SyncService } from '../synchronization/sync.service';
import { UsersService } from '../users/users.service';

/** Serviços reais sobre o banco em memória (mesma interface do Prisma). */
export function createServices() {
  const db = new MemoryDatabase();
  const devices = new DevicesService(db);
  return {
    db,
    users: new UsersService(db),
    devices,
    routes: new RoutesService(db),
    deliveries: new DeliveriesService(db),
    optimization: new OptimizationService(db),
    sync: new SyncService(db, devices),
  };
}

export type Services = ReturnType<typeof createServices>;

export async function createUser(services: Services): Promise<string> {
  const id = randomUUID();
  await services.users.ensureExists({ userId: id, email: `${id.slice(0, 8)}@example.com`, isAnonymous: false });
  return id;
}

let counter = 0;

/** Entrega de teste em São Bernardo do Campo, com coordenada. */
export function deliveryInput(overrides: Partial<CreateDeliveryDto> = {}): CreateDeliveryDto {
  counter++;
  return {
    id: randomUUID(),
    customerName: `Cliente ${counter}`,
    address: `Rua ${counter}`,
    number: String(counter),
    city: 'São Bernardo do Campo',
    state: 'SP',
    latitude: -23.69 - counter * 0.001,
    longitude: -46.56 + counter * 0.001,
    ...overrides,
  };
}

/** Rota com [n] entregas novas. Devolve rota, ids das paradas e das entregas. */
export async function createRouteWithStops(services: Services, userId: string, n: number) {
  const route = await services.routes.create(userId, { name: 'Rota de teste' });
  const detail = await services.routes.addStops(userId, route.id, {
    deliveries: Array.from({ length: n }, () => deliveryInput()),
  });
  return {
    route: detail,
    stopIds: detail.stops.map((s) => s.id),
    deliveryIds: detail.stops.map((s) => s.deliveryId),
  };
}

import { z } from 'zod';
import {
  DELIVERY_PRIORITIES,
  DELIVERY_STATUSES,
  FAILURE_REASONS,
} from '../common/domain/delivery-status';
import type { SyncedEntityName } from '../persistence/entities';
import type { WireEntityType } from '../persistence/entity-writer';

/**
 * Payloads aceitos no /v1/sync/push, por entidade e operação. camelCase,
 * `.strict()`: campo desconhecido = operação recusada (invalid_payload).
 */

const date = z
  .string()
  .datetime({ offset: true })
  .transform((v) => new Date(v));
const text = (max: number) => z.string().max(max);
const optText = (max: number) => z.string().max(max).nullable().optional();
const lat = z.number().min(-90).max(90);
const lng = z.number().min(-180).max(180);

const deliveryEditable = {
  orderNumber: optText(60),
  packageId: optText(80),
  customerName: text(160),
  phone: optText(30),
  address: text(200),
  number: optText(20),
  complement: optText(120),
  neighborhood: optText(120),
  postalCode: z.string().regex(/^\d{8}$/).nullable().optional(),
  city: text(120),
  state: z.string().regex(/^[A-Z]{2}$/).nullable().optional(),
  latitude: lat.nullable().optional(),
  longitude: lng.nullable().optional(),
  locationConfirmed: z.boolean().optional(),
  value: z.number().min(0).nullable().optional(),
  notes: optText(1000),
  priority: z.enum(DELIVERY_PRIORITIES).optional(),
};

const deliveryCreate = z
  .object({
    ...deliveryEditable,
    // Na criação o app pode mandar o retrato completo (primeiro backup de
    // entregas que já têm histórico). Depois, status só por `transition`.
    status: z.enum(DELIVERY_STATUSES).optional(),
    failureReason: z.enum(FAILURE_REASONS).nullable().optional(),
    attempts: z.number().int().min(0).optional(),
    deliveredAt: date.nullable().optional(),
    createdAt: date.optional(),
  })
  .strict()
  .refine((d) => d.status !== 'FAILED' || !!d.failureReason, {
    message: 'FAILED exige failureReason',
    path: ['failureReason'],
  });

const deliveryUpdate = z.object(deliveryEditable).partial().strict();

const routeFields = {
  name: optText(120),
  status: z.enum(['draft', 'active', 'completed']).optional(),
  originLat: lat.nullable().optional(),
  originLng: lng.nullable().optional(),
  endLat: lat.nullable().optional(),
  endLng: lng.nullable().optional(),
  estimatedKm: z.number().min(0).nullable().optional(),
  estimatedMinutes: z.number().int().min(0).nullable().optional(),
  navApp: z.enum(['google', 'waze']).nullable().optional(),
  manuallyEdited: z.boolean().optional(),
  startedAt: date.nullable().optional(),
  completedAt: date.nullable().optional(),
};

const stopFields = {
  position: z.number().int().min(0),
  locked: z.boolean().optional(),
  fixedPosition: z.number().int().min(0).nullable().optional(),
};

const vehicleFields = {
  name: text(80),
  type: z.enum(['motorcycle', 'car', 'utility', 'van', 'truck']),
  plate: optText(10),
  fuelType: z.enum(['gasoline', 'ethanol', 'flex', 'diesel']).optional(),
  kmPerLiter: z.number().positive().max(200),
  fuelPrice: z.number().min(0).max(100),
  avgSpeedKmh: z.number().positive().max(200),
  odometerKm: z.number().min(0).optional(),
  oilIntervalKm: z.number().positive(),
  lastOilChangeKm: z.number().min(0).optional(),
  isActive: z.boolean().optional(),
};

const oilFields = {
  vehicleId: z.string().uuid(),
  odometerKm: z.number().min(0),
  changedAt: date,
  note: optText(500),
};

/** Resumo do trajeto: nunca uma linha por ponto de GPS. */
const trackSummary = z
  .object({
    /** Polyline codificada (Google), já simplificada no aparelho. */
    polyline: z.string().max(200_000),
    pointCount: z.number().int().min(0),
    startedAt: z.string().datetime({ offset: true }).optional(),
    endedAt: z.string().datetime({ offset: true }).optional(),
    bbox: z.tuple([lng, lat, lng, lat]).optional(),
  })
  .strict();

const shiftFields = {
  vehicleId: z.string().uuid().nullable().optional(),
  startedAt: date,
  endedAt: date.nullable().optional(),
  gpsKm: z.number().min(0).optional(),
  odometerStart: z.number().min(0).nullable().optional(),
  odometerEnd: z.number().min(0).nullable().optional(),
  track: trackSummary.nullable().optional(),
};

const baseFields = {
  name: text(80),
  address: text(200),
  city: text(120),
  latitude: lat.nullable().optional(),
  longitude: lng.nullable().optional(),
  isDefault: z.boolean().optional(),
};

const withCreatedAt = { createdAt: date.optional() };

export const transitionPayload = z
  .object({
    /** id do evento gerado no app (delivery_events.id). */
    eventId: z.string().uuid(),
    toStatus: z.enum(DELIVERY_STATUSES),
    fromStatus: z.enum(DELIVERY_STATUSES).optional(),
    reason: z.enum(FAILURE_REASONS).nullable().optional(),
    note: optText(1000),
    latitude: lat.nullable().optional(),
    longitude: lng.nullable().optional(),
    occurredAt: date.optional(),
  })
  .strict();

export const reorderPayload = z
  .object({
    /** Ids de TODAS as paradas abertas da rota, na ordem nova. */
    stopIds: z.array(z.string().uuid()).min(1).max(500),
  })
  .strict();

export interface RefSpec {
  field: string;
  entity: SyncedEntityName;
}

export interface SyncEntityDef {
  name: SyncedEntityName;
  create: z.ZodType<Record<string, unknown>, z.ZodTypeDef, unknown>;
  /** Ausente = imutável (só create/delete). */
  update?: z.ZodType<Record<string, unknown>, z.ZodTypeDef, unknown>;
  /** Campos que apontam para outra entidade do mesmo usuário. */
  refs: RefSpec[];
  /** Valores padrão do SQLite do app para colunas não enviadas. */
  defaults: Record<string, unknown>;
  /** Imutável também para delete (histórico). */
  undeletable?: boolean;
}

export const SYNC_ENTITIES: Record<WireEntityType, SyncEntityDef> = {
  delivery: {
    name: 'delivery',
    create: deliveryCreate,
    update: deliveryUpdate,
    refs: [],
    defaults: {
      orderNumber: null,
      packageId: null,
      phone: null,
      number: null,
      complement: null,
      neighborhood: null,
      postalCode: null,
      state: null,
      latitude: null,
      longitude: null,
      locationConfirmed: false,
      value: null,
      notes: null,
      priority: 'normal',
      status: 'PENDING',
      failureReason: null,
      attempts: 0,
      deliveredAt: null,
    },
  },
  route: {
    name: 'route',
    create: z.object({ ...routeFields, ...withCreatedAt }).strict(),
    update: z.object(routeFields).strict(),
    refs: [],
    defaults: {
      name: null,
      status: 'draft',
      originLat: null,
      originLng: null,
      endLat: null,
      endLng: null,
      estimatedKm: null,
      estimatedMinutes: null,
      navApp: null,
      manuallyEdited: false,
      startedAt: null,
      completedAt: null,
    },
  },
  route_stop: {
    name: 'routeStop',
    create: z
      .object({ routeId: z.string().uuid(), deliveryId: z.string().uuid(), ...stopFields, ...withCreatedAt })
      .strict(),
    update: z.object(stopFields).partial().strict(),
    refs: [
      { field: 'routeId', entity: 'route' },
      { field: 'deliveryId', entity: 'delivery' },
    ],
    defaults: { locked: false, fixedPosition: null },
  },
  delivery_event: {
    name: 'deliveryEvent',
    create: z
      .object({
        deliveryId: z.string().uuid(),
        kind: z.enum(['status', 'edit']),
        fromStatus: z.enum(DELIVERY_STATUSES).nullable().optional(),
        toStatus: z.enum(DELIVERY_STATUSES),
        reason: z.enum(FAILURE_REASONS).nullable().optional(),
        note: optText(1000),
        changedFields: z.array(z.string().max(60)).max(40).nullable().optional(),
        latitude: lat.nullable().optional(),
        longitude: lng.nullable().optional(),
        occurredAt: date,
      })
      .strict(),
    refs: [{ field: 'deliveryId', entity: 'delivery' }],
    defaults: { fromStatus: null, reason: null, note: null, changedFields: null, latitude: null, longitude: null },
    undeletable: true,
  },
  route_plan: {
    name: 'routePlan',
    create: z
      .object({
        routeId: z.string().uuid(),
        stops: z.number().int().min(0),
        baselineKm: z.number().min(0),
        baselineMinutes: z.number().int().min(0),
        optimizedKm: z.number().min(0),
        optimizedMinutes: z.number().int().min(0),
        ...withCreatedAt,
      })
      .strict(),
    refs: [{ field: 'routeId', entity: 'route' }],
    defaults: {},
  },
  vehicle: {
    name: 'vehicle',
    create: z.object({ ...vehicleFields, ...withCreatedAt }).strict(),
    update: z.object(vehicleFields).partial().strict(),
    refs: [],
    defaults: { plate: null, fuelType: 'gasoline', odometerKm: 0, lastOilChangeKm: 0, isActive: false },
  },
  oil_change: {
    name: 'oilChange',
    create: z.object({ ...oilFields, ...withCreatedAt }).strict(),
    update: z.object(oilFields).omit({ vehicleId: true }).partial().strict(),
    refs: [{ field: 'vehicleId', entity: 'vehicle' }],
    defaults: { note: null },
  },
  shift: {
    name: 'shift',
    create: z.object({ ...shiftFields, ...withCreatedAt }).strict(),
    update: z.object(shiftFields).partial().strict(),
    refs: [{ field: 'vehicleId', entity: 'vehicle' }],
    defaults: { vehicleId: null, endedAt: null, gpsKm: 0, odometerStart: null, odometerEnd: null, track: null },
  },
  base_location: {
    name: 'baseLocation',
    create: z.object({ ...baseFields, ...withCreatedAt }).strict(),
    update: z.object(baseFields).partial().strict(),
    refs: [],
    defaults: { latitude: null, longitude: null, isDefault: true },
  },
};

/** Campos de entrega que só mudam por `transition`. */
export const DELIVERY_TRANSITION_FIELDS = ['status', 'failureReason', 'attempts', 'deliveredAt'];

export function zodIssues(error: z.ZodError): string[] {
  return error.issues.map((i) => `${i.path.join('.') || '(payload)'}: ${i.message}`);
}

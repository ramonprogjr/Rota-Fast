/**
 * Formato das linhas como os serviços enxergam (camelCase, bigint já
 * convertido para number). Espelham prisma/schema.prisma; as colunas
 * geography geradas não aparecem aqui (o Prisma não as lê).
 */

export interface Timestamps {
  createdAt: Date;
  updatedAt: Date;
}

/** Campos comuns das entidades sincronizadas. */
export interface SyncedRow extends Timestamps {
  id: string;
  userId: string;
  version: number;
  /** campo -> versão em que mudou por último. */
  fieldVersions: Record<string, number>;
  deletedAt: Date | null;
}

export interface UserRow extends Timestamps {
  id: string;
  email: string | null;
  name: string | null;
  country: string;
  locale: string;
  timezone: string;
  deletedAt: Date | null;
}

export interface DeviceRow extends Timestamps {
  id: string;
  userId: string;
  platform: string;
  model: string | null;
  osVersion: string | null;
  appVersion: string | null;
  lastSeenAt: Date;
  revokedAt: Date | null;
}

export interface OrganizationRow extends Timestamps {
  id: string;
  name: string;
  ownerId: string;
  deletedAt: Date | null;
}

export interface MembershipRow extends Timestamps {
  id: string;
  organizationId: string;
  userId: string;
  role: 'owner' | 'admin' | 'driver';
}

export interface PlanRow extends Timestamps {
  id: string;
  code: string;
  name: string;
  priceCents: number;
  currency: string;
  interval: string;
  limits: Record<string, unknown>;
  isActive: boolean;
}

export interface SubscriptionRow extends Timestamps {
  id: string;
  userId: string | null;
  organizationId: string | null;
  planId: string;
  status: 'trialing' | 'active' | 'past_due' | 'canceled';
  currentPeriodStart: Date | null;
  currentPeriodEnd: Date | null;
  provider: string | null;
  providerRef: string | null;
}

export interface PaymentRow extends Timestamps {
  id: string;
  subscriptionId: string;
  userId: string | null;
  amountCents: number;
  currency: string;
  status: string;
  provider: string | null;
  providerRef: string | null;
  paidAt: Date | null;
}

export interface DeliveryRow extends SyncedRow {
  orderNumber: string | null;
  packageId: string | null;
  customerName: string;
  phone: string | null;
  address: string;
  number: string | null;
  complement: string | null;
  neighborhood: string | null;
  postalCode: string | null;
  city: string;
  state: string | null;
  latitude: number | null;
  longitude: number | null;
  locationConfirmed: boolean;
  value: number | null;
  notes: string | null;
  priority: string;
  status: string;
  failureReason: string | null;
  attempts: number;
  deliveredAt: Date | null;
}

export interface RouteRow extends SyncedRow {
  name: string | null;
  status: string;
  originLat: number | null;
  originLng: number | null;
  endLat: number | null;
  endLng: number | null;
  estimatedKm: number | null;
  estimatedMinutes: number | null;
  navApp: string | null;
  manuallyEdited: boolean;
  startedAt: Date | null;
  completedAt: Date | null;
}

export interface RouteStopRow extends SyncedRow {
  routeId: string;
  deliveryId: string;
  position: number;
  locked: boolean;
  fixedPosition: number | null;
}

export interface DeliveryEventRow extends SyncedRow {
  deliveryId: string;
  kind: string;
  fromStatus: string | null;
  toStatus: string;
  reason: string | null;
  note: string | null;
  changedFields: string[] | null;
  latitude: number | null;
  longitude: number | null;
  occurredAt: Date;
  deviceId: string | null;
}

export interface RoutePlanRow extends SyncedRow {
  routeId: string;
  stops: number;
  baselineKm: number;
  baselineMinutes: number;
  optimizedKm: number;
  optimizedMinutes: number;
}

export interface VehicleRow extends SyncedRow {
  name: string;
  type: string;
  plate: string | null;
  fuelType: string;
  kmPerLiter: number;
  fuelPrice: number;
  avgSpeedKmh: number;
  odometerKm: number;
  oilIntervalKm: number;
  lastOilChangeKm: number;
  isActive: boolean;
}

export interface OilChangeRow extends SyncedRow {
  vehicleId: string;
  odometerKm: number;
  changedAt: Date;
  note: string | null;
}

export interface ShiftRow extends SyncedRow {
  vehicleId: string | null;
  startedAt: Date;
  endedAt: Date | null;
  gpsKm: number;
  odometerStart: number | null;
  odometerEnd: number | null;
  track: Record<string, unknown> | null;
}

export interface BaseLocationRow extends SyncedRow {
  name: string;
  address: string;
  city: string;
  latitude: number | null;
  longitude: number | null;
  isDefault: boolean;
}

export interface SyncOperationRow {
  id: string;
  userId: string;
  deviceId: string;
  entityType: string;
  entityId: string;
  operationType: string;
  baseVersion: number | null;
  payload: Record<string, unknown>;
  status: 'applied' | 'conflict' | 'rejected';
  reason: string | null;
  result: Record<string, unknown>;
  clientCreatedAt: Date | null;
  receivedAt: Date;
}

export interface SyncChangeRow {
  seq: number;
  userId: string;
  entityType: string;
  entityId: string;
  version: number;
  operation: 'upsert' | 'delete';
  changedAt: Date;
}

export interface AuditLogRow {
  id: string;
  userId: string | null;
  action: string;
  entityType: string | null;
  entityId: string | null;
  metadata: Record<string, unknown>;
  createdAt: Date;
}

/** Nome da entidade = nome do delegate do Prisma. */
export interface EntityMap {
  user: UserRow;
  device: DeviceRow;
  organization: OrganizationRow;
  membership: MembershipRow;
  plan: PlanRow;
  subscription: SubscriptionRow;
  payment: PaymentRow;
  delivery: DeliveryRow;
  route: RouteRow;
  routeStop: RouteStopRow;
  deliveryEvent: DeliveryEventRow;
  routePlan: RoutePlanRow;
  vehicle: VehicleRow;
  oilChange: OilChangeRow;
  shift: ShiftRow;
  baseLocation: BaseLocationRow;
  syncOperation: SyncOperationRow;
  syncChange: SyncChangeRow;
  auditLog: AuditLogRow;
}

export type EntityName = keyof EntityMap;

/** Entidades com user_id/version/field_versions/deleted_at, que vão no sync. */
export type SyncedEntityName =
  | 'delivery'
  | 'route'
  | 'routeStop'
  | 'deliveryEvent'
  | 'routePlan'
  | 'vehicle'
  | 'oilChange'
  | 'shift'
  | 'baseLocation';

/** Campos JSON que podem ser null (o Prisma exige DbNull para eles). */
export const NULLABLE_JSON_FIELDS = new Set(['changedFields', 'track']);

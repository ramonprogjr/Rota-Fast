import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { FailureReasonRequiredError, InvalidTransitionError } from '../common/domain/delivery-status';
import {
  ConflictAppException,
  NotFoundAppException,
  UnprocessableAppException,
} from '../common/exceptions/app.exception';
import { DATABASE, type Database } from '../persistence/data-store';
import type { DeliveryRow } from '../persistence/entities';
import { EntityWriter, findOwned, staleFields } from '../persistence/entity-writer';
import {
  StatusMismatchError,
  toDeliveryResponse,
  toEventResponse,
  transitionDelivery,
} from './delivery-operations';
import type {
  CreateDeliveryEventDto,
  DeliveryEventResult,
  DeliveryResponse,
  UpdateDeliveryDto,
} from './dto/delivery.dto';

@Injectable()
export class DeliveriesService {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async get(userId: string, id: string): Promise<DeliveryResponse> {
    const row = await findOwned(this.db.store, 'delivery', userId, id);
    if (!row) {
      throw new NotFoundAppException('delivery');
    }
    return toDeliveryResponse(row);
  }

  /**
   * Edita dados (nunca status). Grava um evento `edit` com os campos alterados.
   * Com baseVersion, recusa (409) se algum desses campos mudou depois.
   */
  async update(userId: string, id: string, dto: UpdateDeliveryDto): Promise<DeliveryResponse> {
    return this.db.transaction(async (store) => {
      await store.lockUser(userId);
      const row = await findOwned(store, 'delivery', userId, id);
      if (!row) {
        throw new NotFoundAppException('delivery');
      }
      const { baseVersion, ...changes } = dto;
      if (baseVersion !== undefined) {
        const stale = staleFields(row, baseVersion, Object.keys(changes));
        if (stale.length) {
          throw new ConflictAppException('VERSION_CONFLICT', 'A entrega mudou em outro aparelho.', {
            fields: stale,
            server: toDeliveryResponse(row),
          });
        }
      }
      const writer = new EntityWriter(store, userId);
      const { row: updated, changed } = await writer.patch('delivery', row, changes as Partial<DeliveryRow>);
      if (changed.length) {
        await writer.insert('deliveryEvent', {
          id: randomUUID(),
          deliveryId: id,
          kind: 'edit',
          fromStatus: updated.status,
          toStatus: updated.status,
          reason: null,
          note: null,
          changedFields: changed,
          latitude: null,
          longitude: null,
          occurredAt: new Date(),
          deviceId: null,
        });
      }
      return toDeliveryResponse(updated);
    });
  }

  /**
   * Registra um evento. kind=status troca o status pela máquina de estados
   * do app; kind=edit só registra (os dados mudam por PATCH ou sync).
   * Repetir o mesmo `id` devolve o evento original (idempotente).
   */
  async addEvent(userId: string, deliveryId: string, dto: CreateDeliveryEventDto): Promise<DeliveryEventResult> {
    return this.db.transaction(async (store) => {
      await store.lockUser(userId);
      const delivery = await findOwned(store, 'delivery', userId, deliveryId);
      if (!delivery) {
        throw new NotFoundAppException('delivery');
      }
      if (dto.id) {
        const existing = await store.findById('deliveryEvent', dto.id);
        if (existing) {
          if (existing.userId !== userId || existing.deliveryId !== deliveryId) {
            throw new ConflictAppException('EVENT_ID_TAKEN', 'Este id de evento já foi usado.');
          }
          return { delivery: toDeliveryResponse(delivery), event: toEventResponse(existing) };
        }
      }
      const writer = new EntityWriter(store, userId);
      const kind = dto.kind ?? 'status';
      if (kind === 'edit') {
        const event = await writer.insert('deliveryEvent', {
          id: dto.id ?? randomUUID(),
          deliveryId,
          kind: 'edit',
          fromStatus: delivery.status,
          toStatus: delivery.status,
          reason: null,
          note: dto.note ?? null,
          changedFields: dto.changedFields ?? null,
          latitude: dto.latitude ?? null,
          longitude: dto.longitude ?? null,
          occurredAt: dto.occurredAt ?? new Date(),
          deviceId: dto.deviceId ?? null,
        });
        return { delivery: toDeliveryResponse(delivery), event: toEventResponse(event) };
      }
      if (!dto.toStatus) {
        throw new UnprocessableAppException('TO_STATUS_REQUIRED', 'Informe toStatus para um evento de status.');
      }
      try {
        const result = await transitionDelivery(store, writer, delivery, {
          to: dto.toStatus,
          from: dto.fromStatus,
          reason: dto.reason,
          note: dto.note,
          latitude: dto.latitude,
          longitude: dto.longitude,
          occurredAt: dto.occurredAt,
          deviceId: dto.deviceId,
          eventId: dto.id,
        });
        if (!result.event) {
          throw new ConflictAppException('ALREADY_IN_STATUS', 'A entrega já está nesse status.', {
            server: toDeliveryResponse(result.delivery),
          });
        }
        return { delivery: toDeliveryResponse(result.delivery), event: toEventResponse(result.event) };
      } catch (error) {
        throw mapTransitionError(error, delivery);
      }
    });
  }
}

export function mapTransitionError(error: unknown, delivery: DeliveryRow): unknown {
  if (error instanceof InvalidTransitionError) {
    return new UnprocessableAppException('INVALID_TRANSITION', error.message, { from: error.from, to: error.to });
  }
  if (error instanceof FailureReasonRequiredError) {
    return new UnprocessableAppException('FAILURE_REASON_REQUIRED', error.message);
  }
  if (error instanceof StatusMismatchError) {
    return new ConflictAppException('STATUS_CONFLICT', error.message, { server: toDeliveryResponse(delivery) });
  }
  return error;
}

import { Inject, Injectable } from '@nestjs/common';
import { ConflictAppException } from '../common/exceptions/app.exception';
import { DATABASE, type Database, type DataStore } from '../persistence/data-store';
import type { DeviceRow } from '../persistence/entities';
import type { RegisterDeviceDto } from './dto/device.dto';

@Injectable()
export class DevicesService {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  register(userId: string, dto: RegisterDeviceDto): Promise<DeviceRow> {
    return this.db.transaction((store) => this.upsert(store, userId, dto));
  }

  /**
   * Cria ou atualiza o aparelho. O id é gerado no app; se já pertence a outro
   * usuário, recusa (um aparelho não troca de dono pela API).
   */
  async upsert(store: DataStore, userId: string, dto: Partial<RegisterDeviceDto> & { id: string }): Promise<DeviceRow> {
    const now = new Date();
    const existing = await store.findById('device', dto.id);
    if (existing && existing.userId !== userId) {
      throw new ConflictAppException('DEVICE_ID_TAKEN', 'Este identificador de aparelho já está em uso. Gere outro.');
    }
    if (existing) {
      return store.update('device', dto.id, {
        ...(dto.platform !== undefined ? { platform: dto.platform } : {}),
        ...(dto.model !== undefined ? { model: dto.model } : {}),
        ...(dto.osVersion !== undefined ? { osVersion: dto.osVersion } : {}),
        ...(dto.appVersion !== undefined ? { appVersion: dto.appVersion } : {}),
        lastSeenAt: now,
        updatedAt: now,
      });
    }
    return store.create('device', {
      id: dto.id,
      userId,
      platform: dto.platform ?? 'android',
      model: dto.model ?? null,
      osVersion: dto.osVersion ?? null,
      appVersion: dto.appVersion ?? null,
      lastSeenAt: now,
      revokedAt: null,
      createdAt: now,
      updatedAt: now,
    });
  }
}

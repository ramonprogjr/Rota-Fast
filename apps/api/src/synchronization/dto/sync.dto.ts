import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsDate,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsUUID,
  Matches,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';
import { WIRE_TYPES } from '../../persistence/entity-writer';

export const SYNC_ENTITY_TYPES = Object.values(WIRE_TYPES);
export const SYNC_OPERATION_TYPES = ['create', 'update', 'delete', 'transition', 'reorder'] as const;
export type SyncOperationType = (typeof SYNC_OPERATION_TYPES)[number];
export const MAX_PUSH_BATCH = 500;

export class SyncOperationDto {
  /** UUID gerado no aparelho. Chave de idempotência: repetir = mesmo resultado. */
  @IsUUID()
  operationId: string;

  /** Se vier, precisa ser igual ao deviceId do lote. */
  @IsOptional()
  @IsUUID()
  deviceId?: string;

  @ApiProperty({ enum: SYNC_ENTITY_TYPES })
  @IsIn(SYNC_ENTITY_TYPES)
  entityType: string;

  /** UUID da entidade (gerado no aparelho na criação). */
  @IsUUID()
  entityId: string;

  @ApiProperty({ enum: SYNC_OPERATION_TYPES })
  @IsIn(SYNC_OPERATION_TYPES)
  operationType: SyncOperationType;

  /** Campos em camelCase. create: retrato; update: só os campos mudados. */
  @ApiProperty({ type: 'object', additionalProperties: true })
  @IsObject()
  payload: Record<string, unknown>;

  /** Versão da entidade que o aparelho tinha quando mudou. Obrigatório em update. */
  @IsOptional()
  @IsInt()
  @Min(1)
  baseVersion?: number;

  @IsOptional()
  @Type(() => Date)
  @IsDate()
  clientCreatedAt?: Date;
}

export class SyncPushDto {
  @IsUUID()
  deviceId: string;

  /** Em ordem de criação no aparelho. Máx. 500 por lote. */
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(MAX_PUSH_BATCH)
  @ValidateNested({ each: true })
  @Type(() => SyncOperationDto)
  operations: SyncOperationDto[];
}

export const SYNC_RESULT_STATUSES = ['applied', 'duplicate', 'conflict', 'rejected'] as const;
export type SyncResultStatus = (typeof SYNC_RESULT_STATUSES)[number];

export class SyncOperationResult {
  operationId: string;
  entityType: string;
  entityId: string;
  @ApiProperty({ enum: SYNC_RESULT_STATUSES })
  status: SyncResultStatus;
  /** Em `duplicate`: o status da primeira vez. */
  @ApiPropertyOptional({ enum: ['applied', 'conflict', 'rejected'] })
  originalStatus?: 'applied' | 'conflict' | 'rejected';
  /** Motivo estável (ex.: version_conflict, invalid_transition, not_found). */
  reason?: string;
  message?: string;
  /** Versão atual da entidade no servidor depois da operação. */
  version?: number;
  /** Em conflito: retrato atual no servidor, para o app resolver. */
  @ApiPropertyOptional({ type: 'object', additionalProperties: true })
  server?: Record<string, unknown> | null;
  @ApiPropertyOptional({ type: 'object', additionalProperties: true })
  details?: unknown;
}

export class SyncPushResponse {
  results: SyncOperationResult[];
  /** Contagem por status. */
  @ApiProperty({ type: 'object', additionalProperties: { type: 'number' } })
  summary: Record<SyncResultStatus, number>;
  serverTime: string;
}

export class SyncPullQueryDto {
  /** Cursor devolvido pelo pull anterior ("0" na primeira vez). */
  @IsOptional()
  @Matches(/^\d{1,18}$/)
  since?: string;

  /** Máx. de mudanças por página (1–1000, padrão 200). */
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(1000)
  limit?: number;
}

export class SyncChangeDto {
  /** Posição no log (string: bigint). */
  seq: string;
  @ApiProperty({ enum: SYNC_ENTITY_TYPES })
  entityType: string;
  entityId: string;
  /** delete = tombstone (aplicar exclusão lógica no aparelho). */
  @ApiProperty({ enum: ['upsert', 'delete'] })
  operation: 'upsert' | 'delete';
  version: number;
  /** Retrato atual (camelCase). null em tombstone. */
  @ApiPropertyOptional({ type: 'object', additionalProperties: true, nullable: true })
  data: Record<string, unknown> | null;
  deletedAt: Date | null;
}

export class SyncPullResponse {
  changes: SyncChangeDto[];
  /** Guardar e mandar no próximo pull. */
  nextCursor: string;
  /** true = chame de novo com nextCursor. */
  hasMore: boolean;
  serverTime: string;
}

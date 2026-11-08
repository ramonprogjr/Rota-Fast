import { ApiProperty, ApiPropertyOptional, OmitType, PartialType } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsBoolean,
  IsDate,
  IsIn,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import {
  DELIVERY_PRIORITIES,
  DELIVERY_STATUSES,
  type DeliveryPriority,
  type DeliveryStatus,
  FAILURE_REASONS,
  type FailureReason,
} from '../../common/domain/delivery-status';

export class CreateDeliveryDto {
  /** UUID gerado no app. Se omitido, o servidor gera. */
  @IsOptional()
  @IsUUID()
  id?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  orderNumber?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  packageId?: string;

  @IsString()
  @MaxLength(160)
  customerName: string;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  phone?: string;

  /** Logradouro. */
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  address: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  number?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  complement?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  neighborhood?: string;

  /** CEP só com dígitos. */
  @IsOptional()
  @Matches(/^\d{8}$/)
  postalCode?: string;

  @IsString()
  @MaxLength(120)
  city: string;

  /** UF. */
  @IsOptional()
  @Matches(/^[A-Z]{2}$/)
  state?: string;

  @IsOptional()
  @IsLatitude()
  latitude?: number;

  @IsOptional()
  @IsLongitude()
  longitude?: number;

  @IsOptional()
  @IsBoolean()
  locationConfirmed?: boolean;

  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  value?: number;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;

  @ApiPropertyOptional({ enum: DELIVERY_PRIORITIES })
  @IsOptional()
  @IsIn(DELIVERY_PRIORITIES)
  priority?: DeliveryPriority;
}

export class UpdateDeliveryDto extends PartialType(OmitType(CreateDeliveryDto, ['id'] as const)) {
  /** Versão que o cliente viu. Se outra mudança veio depois, 409. */
  @IsOptional()
  @IsInt()
  @Min(1)
  baseVersion?: number;
}

export class CreateDeliveryEventDto {
  /** UUID do evento gerado no app (idempotente: repetir devolve o mesmo evento). */
  @IsOptional()
  @IsUUID()
  id?: string;

  @ApiPropertyOptional({ enum: ['status', 'edit'], default: 'status' })
  @IsOptional()
  @IsIn(['status', 'edit'])
  kind?: 'status' | 'edit';

  /** Status esperado antes da troca. Se diferente do atual no servidor, 409. */
  @ApiPropertyOptional({ enum: DELIVERY_STATUSES })
  @IsOptional()
  @IsIn(DELIVERY_STATUSES)
  fromStatus?: DeliveryStatus;

  /** Obrigatório quando kind = status. */
  @ApiPropertyOptional({ enum: DELIVERY_STATUSES })
  @IsOptional()
  @IsIn(DELIVERY_STATUSES)
  toStatus?: DeliveryStatus;

  /** Obrigatório para FAILED. */
  @ApiPropertyOptional({ enum: FAILURE_REASONS })
  @IsOptional()
  @IsIn(FAILURE_REASONS)
  reason?: FailureReason;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  note?: string;

  /** Campos alterados (kind = edit). */
  @IsOptional()
  @IsString({ each: true })
  @ArrayMaxSize(40)
  changedFields?: string[];

  @IsOptional()
  @IsLatitude()
  latitude?: number;

  @IsOptional()
  @IsLongitude()
  longitude?: number;

  /** Quando aconteceu no aparelho (ISO-8601). Padrão: agora. */
  @IsOptional()
  @Type(() => Date)
  @IsDate()
  occurredAt?: Date;

  @IsOptional()
  @IsUUID()
  deviceId?: string;
}

export class DeliveryResponse {
  id: string;
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
  @ApiProperty({ enum: DELIVERY_STATUSES })
  status: string;
  failureReason: string | null;
  attempts: number;
  deliveredAt: Date | null;
  version: number;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;
}

export class DeliveryEventResponse {
  id: string;
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
  createdAt: Date;
}

export class DeliveryEventResult {
  delivery: DeliveryResponse;
  event: DeliveryEventResponse;
}

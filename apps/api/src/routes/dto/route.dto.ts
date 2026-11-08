import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
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
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import { PageQueryDto } from '../../common/dto/pagination.dto';
import { CreateDeliveryDto, DeliveryResponse } from '../../deliveries/dto/delivery.dto';

export const ROUTE_STATUSES = ['draft', 'active', 'completed'] as const;
export type RouteStatus = (typeof ROUTE_STATUSES)[number];

export class ListRoutesQueryDto extends PageQueryDto {
  @ApiPropertyOptional({ enum: ROUTE_STATUSES })
  @IsOptional()
  @IsIn(ROUTE_STATUSES)
  status?: RouteStatus;
}

export class CreateRouteDto {
  /** UUID gerado no app. Se omitido, o servidor gera. */
  @IsOptional()
  @IsUUID()
  id?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  name?: string;

  @ApiPropertyOptional({ enum: ['draft', 'active'], default: 'draft' })
  @IsOptional()
  @IsIn(['draft', 'active'])
  status?: 'draft' | 'active';

  @IsOptional()
  @IsLatitude()
  originLat?: number;

  @IsOptional()
  @IsLongitude()
  originLng?: number;

  @IsOptional()
  @IsLatitude()
  endLat?: number;

  @IsOptional()
  @IsLongitude()
  endLng?: number;

  @IsOptional()
  @IsIn(['google', 'waze'])
  navApp?: string;
}

export class UpdateRouteDto {
  /** Versão que o cliente viu. Se a rota mudou depois nos mesmos campos, 409. */
  @IsOptional()
  @IsInt()
  @Min(1)
  baseVersion?: number;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  name?: string;

  /** draft -> active|completed; active -> completed|draft; completed -> active (reabrir). */
  @ApiPropertyOptional({ enum: ROUTE_STATUSES })
  @IsOptional()
  @IsIn(ROUTE_STATUSES)
  status?: RouteStatus;

  @IsOptional()
  @IsLatitude()
  originLat?: number;

  @IsOptional()
  @IsLongitude()
  originLng?: number;

  @IsOptional()
  @IsLatitude()
  endLat?: number;

  @IsOptional()
  @IsLongitude()
  endLng?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  estimatedKm?: number;

  @IsOptional()
  @IsInt()
  @Min(0)
  estimatedMinutes?: number;

  @IsOptional()
  @IsIn(['google', 'waze'])
  navApp?: string;

  @IsOptional()
  @IsBoolean()
  manuallyEdited?: boolean;

  @IsOptional()
  @Type(() => Date)
  @IsDate()
  startedAt?: Date;
}

export class DeleteRouteQueryDto {
  /**
   * true: também exclui (lógico) as entregas que só aparecem nesta rota.
   * Entregas que estão em outra rota nunca são excluídas.
   */
  @IsOptional()
  @Type(() => String)
  @IsIn(['true', 'false'])
  withExclusiveDeliveries?: 'true' | 'false';
}

export class AddStopsDto {
  /** Entregas já existentes do usuário, na ordem em que entram no fim da rota. */
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(500)
  @IsUUID('all', { each: true })
  deliveryIds?: string[];

  /** Entregas novas, criadas e adicionadas no fim (depois de deliveryIds). */
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(500)
  @ValidateNested({ each: true })
  @Type(() => CreateDeliveryDto)
  deliveries?: CreateDeliveryDto[];
}

export class ReorderStopsDto {
  /** Ids de TODAS as paradas abertas da rota, na ordem nova, sem repetir. */
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(500)
  @IsUUID('all', { each: true })
  stopIds: string[];

  @IsOptional()
  @IsInt()
  @Min(1)
  baseVersion?: number;
}

export class RouteResponse {
  id: string;
  name: string | null;
  @ApiProperty({ enum: ROUTE_STATUSES })
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
  version: number;
  createdAt: Date;
  updatedAt: Date;
}

export class RouteStopResponse {
  id: string;
  deliveryId: string;
  position: number;
  locked: boolean;
  /** Índice 0-based entre as abertas (alfinete). */
  fixedPosition: number | null;
  /** A entrega ainda está aberta (PENDING, IN_PROGRESS ou SKIPPED). */
  isOpen: boolean;
  version: number;
  delivery: DeliveryResponse;
}

export class RouteDetailResponse extends RouteResponse {
  stops: RouteStopResponse[];
}

export class RoutePageResponse {
  items: RouteResponse[];
  page: number;
  pageSize: number;
  total: number;
}

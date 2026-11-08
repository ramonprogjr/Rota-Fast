import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

export class PointDto {
  @IsLatitude()
  latitude: number;

  @IsLongitude()
  longitude: number;
}

export class PreviewStopDto {
  /** Identificador livre (id da parada ou da entrega no app). */
  @IsString()
  @MaxLength(64)
  id: string;

  @IsOptional()
  @IsLatitude()
  latitude?: number;

  @IsOptional()
  @IsLongitude()
  longitude?: number;

  @IsOptional()
  @IsBoolean()
  locked?: boolean;

  @IsOptional()
  @IsInt()
  @Min(0)
  fixedPosition?: number;
}

export class OptimizationPreviewDto {
  /** Rota salva do usuário: usa as paradas abertas dela, na ordem atual. */
  @IsOptional()
  @IsUUID()
  routeId?: string;

  /** Ou uma lista avulsa de paradas, na ordem atual (máx. 200). */
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => PreviewStopDto)
  stops?: PreviewStopDto[];

  /** Ponto de saída. Padrão: origem da rota. */
  @IsOptional()
  @ValidateNested()
  @Type(() => PointDto)
  origin?: PointDto;

  /** Ponto final opcional. Padrão: fim da rota. */
  @IsOptional()
  @ValidateNested()
  @Type(() => PointDto)
  end?: PointDto;

  /** Velocidade média para o tempo estimado (km/h). Padrão 28 (moto). */
  @IsOptional()
  @IsNumber()
  @Min(5)
  @Max(120)
  speedKmh?: number;
}

export class OptimizationPreviewResponse {
  routeId: string | null;
  /** Ordem proposta (ids das paradas). Nada é gravado. */
  order: string[];
  baselineKm: number;
  optimizedKm: number;
  baselineMinutes: number;
  optimizedMinutes: number;
  savedKm: number;
  /** Paradas sem coordenada: mantidas no fim. */
  unlocated: string[];
  /** haversine × 1,3 (sem malha viária). */
  method: string;
}

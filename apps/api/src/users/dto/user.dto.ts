import { IsOptional, IsString, Length, Matches, MaxLength } from 'class-validator';

export class UpdateMeDto {
  /** Nome exibido. */
  @IsOptional()
  @IsString()
  @MaxLength(120)
  name?: string;

  /** País (ISO 3166-1 alfa-2), ex.: BR. */
  @IsOptional()
  @Matches(/^[A-Za-z]{2}$/)
  country?: string;

  /** Idioma (BCP 47), ex.: pt-BR. */
  @IsOptional()
  @Matches(/^[a-z]{2,3}(-[A-Z]{2})?$/)
  locale?: string;

  /** Fuso IANA, ex.: America/Sao_Paulo. */
  @IsOptional()
  @IsString()
  @Length(3, 64)
  @Matches(/^[A-Za-z_]+(\/[A-Za-z0-9_+-]+)*$/)
  timezone?: string;
}

export class MeResponse {
  id: string;
  email: string | null;
  name: string | null;
  country: string;
  locale: string;
  timezone: string;
  createdAt: Date;
  updatedAt: Date;
}

import { Controller, Get, Inject } from '@nestjs/common';
import { ApiProperty, ApiTags } from '@nestjs/swagger';
import { SkipThrottle } from '@nestjs/throttler';
import { Public } from '../common/decorators/public.decorator';
import { DATABASE, type Database } from '../persistence/data-store';

export class HealthResponse {
  @ApiProperty({ enum: ['ok', 'degraded'] })
  status: 'ok' | 'degraded';
  @ApiProperty({ enum: ['up', 'down'] })
  database: 'up' | 'down';
  version: string;
  time: string;
}

@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** Público. Usado pelo host (health check) e pelo app para saber se há servidor. */
  @Public()
  @SkipThrottle()
  @Get()
  async check(): Promise<HealthResponse> {
    const up = await this.db.ping();
    return {
      status: up ? 'ok' : 'degraded',
      database: up ? 'up' : 'down',
      version: process.env.npm_package_version ?? '0.1.0',
      time: new Date().toISOString(),
    };
  }
}

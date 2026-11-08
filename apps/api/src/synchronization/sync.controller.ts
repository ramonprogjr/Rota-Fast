import { Body, Controller, Get, HttpCode, HttpStatus, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import type { AuthPrincipal } from '../auth/jwt-verifier';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { SyncPullQueryDto, SyncPullResponse, SyncPushDto, SyncPushResponse } from './dto/sync.dto';
import { SyncService } from './sync.service';

@ApiTags('sync')
@ApiBearerAuth()
@Controller('sync')
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  /**
   * Envia até 500 operações locais. Idempotente por operationId: reenviar
   * devolve o resultado original com status `duplicate`. Cada operação volta
   * como applied | duplicate | conflict | rejected. Ver docs/api/sync-protocol.md.
   */
  @Post('push')
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  push(@CurrentUser() user: AuthPrincipal, @Body() dto: SyncPushDto): Promise<SyncPushResponse> {
    return this.sync.push(user.userId, dto);
  }

  /** Mudanças do usuário depois do cursor, com tombstones. Paginado por `limit`. */
  @Get('pull')
  pull(@CurrentUser() user: AuthPrincipal, @Query() query: SyncPullQueryDto): Promise<SyncPullResponse> {
    return this.sync.pull(user.userId, query.since, query.limit);
  }
}

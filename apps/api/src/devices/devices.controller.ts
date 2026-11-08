import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthPrincipal } from '../auth/jwt-verifier';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { DevicesService } from './devices.service';
import { DeviceResponse, RegisterDeviceDto } from './dto/device.dto';

@ApiTags('devices')
@ApiBearerAuth()
@Controller('devices')
export class DevicesController {
  constructor(private readonly devices: DevicesService) {}

  /** Registra (ou atualiza) o aparelho que vai sincronizar. Idempotente pelo id. */
  @Post()
  @HttpCode(HttpStatus.OK)
  async register(@CurrentUser() user: AuthPrincipal, @Body() dto: RegisterDeviceDto): Promise<DeviceResponse> {
    const row = await this.devices.register(user.userId, dto);
    return {
      id: row.id,
      platform: row.platform,
      model: row.model,
      osVersion: row.osVersion,
      appVersion: row.appVersion,
      lastSeenAt: row.lastSeenAt,
      createdAt: row.createdAt,
    };
  }
}

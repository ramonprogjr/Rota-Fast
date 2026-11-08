import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthPrincipal } from '../auth/jwt-verifier';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { DeliveriesService } from './deliveries.service';
import {
  CreateDeliveryEventDto,
  DeliveryEventResult,
  DeliveryResponse,
  UpdateDeliveryDto,
} from './dto/delivery.dto';

@ApiTags('deliveries')
@ApiBearerAuth()
@Controller('deliveries')
export class DeliveriesController {
  constructor(private readonly deliveries: DeliveriesService) {}

  /** Uma entrega do usuário. De outro usuário ou excluída = 404. */
  @Get(':id')
  get(@CurrentUser() user: AuthPrincipal, @Param('id', ParseUUIDPipe) id: string): Promise<DeliveryResponse> {
    return this.deliveries.get(user.userId, id);
  }

  /** Edita dados da entrega (status só por evento). Grava evento `edit`. */
  @Patch(':id')
  update(
    @CurrentUser() user: AuthPrincipal,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateDeliveryDto,
  ): Promise<DeliveryResponse> {
    return this.deliveries.update(user.userId, id, dto);
  }

  /**
   * Troca de status (kind=status, segue a máquina de estados do app) ou
   * registro de edição (kind=edit). 409 se `fromStatus` não bate; 422 se a
   * transição não é permitida ou falta o motivo de FAILED.
   */
  @Post(':id/events')
  addEvent(
    @CurrentUser() user: AuthPrincipal,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CreateDeliveryEventDto,
  ): Promise<DeliveryEventResult> {
    return this.deliveries.addEvent(user.userId, id, dto);
  }
}

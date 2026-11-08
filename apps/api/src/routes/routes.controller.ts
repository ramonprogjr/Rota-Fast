import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiNoContentResponse, ApiTags } from '@nestjs/swagger';
import type { AuthPrincipal } from '../auth/jwt-verifier';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import {
  AddStopsDto,
  CreateRouteDto,
  DeleteRouteQueryDto,
  ListRoutesQueryDto,
  ReorderStopsDto,
  RouteDetailResponse,
  RoutePageResponse,
  RouteResponse,
  UpdateRouteDto,
} from './dto/route.dto';
import { RoutesService } from './routes.service';

@ApiTags('routes')
@ApiBearerAuth()
@Controller('routes')
export class RoutesController {
  constructor(private readonly routes: RoutesService) {}

  /** Rotas do usuário, da mais nova para a mais antiga (paginado). */
  @Get()
  list(@CurrentUser() user: AuthPrincipal, @Query() query: ListRoutesQueryDto): Promise<RoutePageResponse> {
    return this.routes.list(user.userId, query);
  }

  /** Cria uma rota (draft por padrão). Só uma pode estar ativa. */
  @Post()
  create(@CurrentUser() user: AuthPrincipal, @Body() dto: CreateRouteDto): Promise<RouteResponse> {
    return this.routes.create(user.userId, dto);
  }

  /** Rota com as paradas (pela posição) e as entregas. Outro usuário = 404. */
  @Get(':id')
  get(@CurrentUser() user: AuthPrincipal, @Param('id', ParseUUIDPipe) id: string): Promise<RouteDetailResponse> {
    return this.routes.get(user.userId, id);
  }

  @Patch(':id')
  update(
    @CurrentUser() user: AuthPrincipal,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateRouteDto,
  ): Promise<RouteResponse> {
    return this.routes.update(user.userId, id, dto);
  }

  /**
   * Exclusão lógica (a confirmação é no app). Nunca exclui entregas de outras
   * rotas; com withExclusiveDeliveries=true exclui as que só estão nesta.
   */
  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiNoContentResponse()
  async remove(
    @CurrentUser() user: AuthPrincipal,
    @Param('id', ParseUUIDPipe) id: string,
    @Query() query: DeleteRouteQueryDto,
  ): Promise<void> {
    await this.routes.remove(user.userId, id, query.withExclusiveDeliveries === 'true');
  }

  /** Adiciona entregas (existentes ou novas) no fim da rota. */
  @Post(':id/stops')
  addStops(
    @CurrentUser() user: AuthPrincipal,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AddStopsDto,
  ): Promise<RouteDetailResponse> {
    return this.routes.addStops(user.userId, id, dto);
  }

  /**
   * Ordem manual: lista completa das paradas abertas, sem repetir. Concluídas
   * mantêm a posição. Marca a rota como manuallyEdited. 422 se a lista não
   * bate com as abertas.
   */
  @Patch(':id/stops/reorder')
  reorder(
    @CurrentUser() user: AuthPrincipal,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReorderStopsDto,
  ): Promise<RouteDetailResponse> {
    return this.routes.reorder(user.userId, id, dto);
  }
}

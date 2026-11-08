import { Body, Controller, Get, Patch } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthPrincipal } from '../auth/jwt-verifier';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import type { UserRow } from '../persistence/entities';
import { MeResponse, UpdateMeDto } from './dto/user.dto';
import { UsersService } from './users.service';

function toMe(user: UserRow): MeResponse {
  return {
    id: user.id,
    email: user.email,
    name: user.name,
    country: user.country,
    locale: user.locale,
    timezone: user.timezone,
    createdAt: user.createdAt,
    updatedAt: user.updatedAt,
  };
}

@ApiTags('me')
@ApiBearerAuth()
@Controller('me')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  /** Perfil do usuário logado (criado no primeiro acesso). */
  @Get()
  async getMe(@CurrentUser() user: AuthPrincipal): Promise<MeResponse> {
    return toMe(await this.users.getMe(user.userId));
  }

  /** Atualiza nome, país, idioma e fuso. O e-mail vem do Supabase Auth. */
  @Patch()
  async updateMe(@CurrentUser() user: AuthPrincipal, @Body() dto: UpdateMeDto): Promise<MeResponse> {
    return toMe(await this.users.updateMe(user.userId, dto));
  }
}

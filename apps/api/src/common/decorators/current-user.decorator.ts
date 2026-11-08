import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { AuthPrincipal } from '../../auth/jwt-verifier';

/**
 * Usuário autenticado, vindo do JWT (claim `sub`). Nunca use um user_id do
 * corpo da requisição.
 */
export const CurrentUser = createParamDecorator((_data: unknown, ctx: ExecutionContext): AuthPrincipal => {
  const req = ctx.switchToHttp().getRequest<{ user?: AuthPrincipal }>();
  if (!req.user) {
    throw new Error('CurrentUser usado em rota pública.');
  }
  return req.user;
});

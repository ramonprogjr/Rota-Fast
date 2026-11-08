import { CanActivate, ExecutionContext, Inject, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { AuthError, type AuthPrincipal, JWT_VERIFIER, type JwtVerifier } from '../../auth/jwt-verifier';
import { UsersService } from '../../users/users.service';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';
import { UnauthorizedAppException } from '../exceptions/app.exception';

/**
 * Guard global: toda rota exige `Authorization: Bearer <jwt do Supabase>`,
 * exceto as marcadas com @Public(). Identifica o usuário pelo `sub`.
 */
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    @Inject(JWT_VERIFIER) private readonly verifier: JwtVerifier,
    private readonly users: UsersService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) {
      return true;
    }
    const req = context.switchToHttp().getRequest<Request & { user?: AuthPrincipal }>();
    const token = extractBearer(req.header('authorization'));
    if (!token) {
      throw new UnauthorizedAppException('TOKEN_MISSING', 'Envie o token no cabeçalho Authorization: Bearer.');
    }
    let principal: AuthPrincipal;
    try {
      principal = await this.verifier.verify(token);
    } catch (error) {
      if (error instanceof AuthError) {
        throw new UnauthorizedAppException(error.code, error.message);
      }
      throw new UnauthorizedAppException('TOKEN_INVALID', 'Token inválido.');
    }
    // Garante a linha em `users` (FK de tudo). Cacheado em memória.
    await this.users.ensureExists(principal);
    req.user = principal;
    return true;
  }
}

export function extractBearer(header: string | undefined): string | null {
  if (!header) {
    return null;
  }
  const [scheme, value] = header.split(' ');
  if (scheme?.toLowerCase() !== 'bearer' || !value) {
    return null;
  }
  return value.trim();
}

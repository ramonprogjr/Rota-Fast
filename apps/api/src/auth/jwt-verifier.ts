import { createRemoteJWKSet, errors, jwtVerify, type JWTPayload, type JWTVerifyGetKey } from 'jose';

/** Quem está chamando, extraído do JWT do Supabase Auth. */
export interface AuthPrincipal {
  /** `sub` do token = auth.users.id = users.id. */
  userId: string;
  email?: string;
  role?: string;
  isAnonymous: boolean;
}

export type AuthErrorCode = 'TOKEN_MISSING' | 'TOKEN_EXPIRED' | 'TOKEN_INVALID';

export class AuthError extends Error {
  constructor(
    readonly code: AuthErrorCode,
    message: string,
  ) {
    super(message);
  }
}

/** Verificador injetável: produção usa JWKS remoto; testes, um par de chaves local. */
export interface JwtVerifier {
  verify(token: string): Promise<AuthPrincipal>;
}

export const JWT_VERIFIER = Symbol('JWT_VERIFIER');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface JoseVerifierOptions {
  issuer: string;
  audience: string;
  keys: JWTVerifyGetKey;
  /** Folga de relógio aceita (segundos). */
  clockToleranceSec?: number;
}

/**
 * Confere assinatura (JWKS), `iss`, `aud`, `exp`/`nbf` e `sub` (UUID).
 * Só aceita algoritmos assimétricos: o projeto Supabase precisa usar as
 * "JWT signing keys" (ES256/RS256), não o segredo HS256 legado.
 */
export class JoseJwtVerifier implements JwtVerifier {
  constructor(private readonly options: JoseVerifierOptions) {}

  static forSupabase(supabaseUrl: string, audience: string): JoseJwtVerifier {
    const base = supabaseUrl.replace(/\/+$/, '');
    const keys = createRemoteJWKSet(new URL(`${base}/auth/v1/.well-known/jwks.json`), {
      cooldownDuration: 30_000,
      cacheMaxAge: 10 * 60_000,
    });
    return new JoseJwtVerifier({ issuer: `${base}/auth/v1`, audience, keys });
  }

  async verify(token: string): Promise<AuthPrincipal> {
    if (!token) {
      throw new AuthError('TOKEN_MISSING', 'Token ausente.');
    }
    let payload: JWTPayload;
    try {
      ({ payload } = await jwtVerify(token, this.options.keys, {
        issuer: this.options.issuer,
        audience: this.options.audience,
        algorithms: ['ES256', 'RS256', 'EdDSA'],
        clockTolerance: this.options.clockToleranceSec ?? 5,
        requiredClaims: ['sub', 'exp'],
      }));
    } catch (error) {
      if (error instanceof errors.JWTExpired) {
        throw new AuthError('TOKEN_EXPIRED', 'Sessão expirada. Entre de novo.');
      }
      throw new AuthError('TOKEN_INVALID', 'Token inválido.');
    }
    if (typeof payload.sub !== 'string' || !UUID.test(payload.sub)) {
      throw new AuthError('TOKEN_INVALID', 'Token sem usuário válido.');
    }
    return {
      userId: payload.sub.toLowerCase(),
      email: typeof payload.email === 'string' ? payload.email : undefined,
      role: typeof payload.role === 'string' ? payload.role : undefined,
      isAnonymous: payload.is_anonymous === true,
    };
  }
}

/** Usado quando não há SUPABASE_URL (ex.: exportar o OpenAPI): recusa tudo. */
export class RejectAllVerifier implements JwtVerifier {
  verify(): Promise<AuthPrincipal> {
    return Promise.reject(new AuthError('TOKEN_INVALID', 'Autenticação não configurada.'));
  }
}

import type { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { generateKeyPair, SignJWT } from 'jose';
import { randomUUID } from 'node:crypto';
import type { AuthPrincipal } from '../../auth/jwt-verifier';
import { createTestAuth, TEST_AUDIENCE, TEST_ISSUER } from '../../testing/jwt-test-keys';
import type { UsersService } from '../../users/users.service';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';
import { AppException } from '../exceptions/app.exception';
import { extractBearer, JwtAuthGuard } from './jwt-auth.guard';

function contextFor(authorization: string | undefined, isPublic = false) {
  const req: { user?: AuthPrincipal; header: (name: string) => string | undefined } = {
    header: (name: string) => (name.toLowerCase() === 'authorization' ? authorization : undefined),
  };
  const handler = () => undefined;
  if (isPublic) Reflect.defineMetadata(IS_PUBLIC_KEY, true, handler);
  const ctx = {
    getHandler: () => handler,
    getClass: () => class {},
    switchToHttp: () => ({ getRequest: () => req }),
  } as unknown as ExecutionContext;
  return { ctx, req };
}

async function expectCode(promise: Promise<unknown>, status: number, code: string) {
  await expect(promise).rejects.toBeInstanceOf(AppException);
  await promise.catch((error: AppException) => {
    expect(error.getStatus()).toBe(status);
    expect(error.code).toBe(code);
  });
}

describe('JwtAuthGuard', () => {
  const userId = randomUUID();
  let auth: Awaited<ReturnType<typeof createTestAuth>>;
  let guard: JwtAuthGuard;
  let ensureExists: jest.Mock;

  beforeAll(async () => {
    auth = await createTestAuth();
  });

  beforeEach(() => {
    ensureExists = jest.fn().mockResolvedValue(undefined);
    guard = new JwtAuthGuard(new Reflector(), auth.verifier, { ensureExists } as unknown as UsersService);
  });

  it('aceita token válido e identifica o usuário pelo sub', async () => {
    const token = await auth.sign(userId);
    const { ctx, req } = contextFor(`Bearer ${token}`);
    await expect(guard.canActivate(ctx)).resolves.toBe(true);
    expect(req.user).toEqual(
      expect.objectContaining({ userId, role: 'authenticated', email: expect.any(String), isAnonymous: false }),
    );
    expect(ensureExists).toHaveBeenCalledWith(expect.objectContaining({ userId }));
  });

  it('recusa sem token (401 TOKEN_MISSING)', async () => {
    const { ctx } = contextFor(undefined);
    await expectCode(guard.canActivate(ctx), 401, 'TOKEN_MISSING');
    expect(ensureExists).not.toHaveBeenCalled();
  });

  it('recusa esquema diferente de Bearer', async () => {
    const token = await auth.sign(userId);
    const { ctx } = contextFor(`Basic ${token}`);
    await expectCode(guard.canActivate(ctx), 401, 'TOKEN_MISSING');
  });

  it('recusa token expirado (401 TOKEN_EXPIRED)', async () => {
    const token = await auth.sign(userId, { expiresIn: Math.floor(Date.now() / 1000) - 60 });
    const { ctx } = contextFor(`Bearer ${token}`);
    await expectCode(guard.canActivate(ctx), 401, 'TOKEN_EXPIRED');
  });

  it('recusa emissor errado (401 TOKEN_INVALID)', async () => {
    const token = await auth.sign(userId, { issuer: 'https://evil.example.com/auth/v1' });
    const { ctx } = contextFor(`Bearer ${token}`);
    await expectCode(guard.canActivate(ctx), 401, 'TOKEN_INVALID');
  });

  it('recusa audience errada', async () => {
    const token = await auth.sign(userId, { audience: 'anon' });
    const { ctx } = contextFor(`Bearer ${token}`);
    await expectCode(guard.canActivate(ctx), 401, 'TOKEN_INVALID');
  });

  it('recusa assinatura de outra chave', async () => {
    const other = await generateKeyPair('ES256');
    const token = await new SignJWT({ role: 'authenticated' })
      .setProtectedHeader({ alg: 'ES256', kid: 'test-key' })
      .setSubject(userId)
      .setIssuer(TEST_ISSUER)
      .setAudience(TEST_AUDIENCE)
      .setExpirationTime('1h')
      .sign(other.privateKey);
    const { ctx } = contextFor(`Bearer ${token}`);
    await expectCode(guard.canActivate(ctx), 401, 'TOKEN_INVALID');
  });

  it('recusa sub que não é UUID', async () => {
    const token = await auth.sign('not-a-uuid-at-all-000000000000000000');
    const { ctx } = contextFor(`Bearer ${token}`);
    await expectCode(guard.canActivate(ctx), 401, 'TOKEN_INVALID');
  });

  it('recusa lixo no lugar do token', async () => {
    const { ctx } = contextFor('Bearer abc.def.ghi');
    await expectCode(guard.canActivate(ctx), 401, 'TOKEN_INVALID');
  });

  it('deixa passar rota @Public() sem token', async () => {
    const { ctx } = contextFor(undefined, true);
    await expect(guard.canActivate(ctx)).resolves.toBe(true);
  });

  it('extractBearer lida com cabeçalhos tortos', () => {
    expect(extractBearer(undefined)).toBeNull();
    expect(extractBearer('Bearer')).toBeNull();
    expect(extractBearer('bearer abc')).toBe('abc');
  });
});

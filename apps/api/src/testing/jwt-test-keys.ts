import { createLocalJWKSet, exportJWK, generateKeyPair, type JWTPayload, SignJWT } from 'jose';
import { JoseJwtVerifier } from '../auth/jwt-verifier';

export const TEST_SUPABASE_URL = 'https://test-project.supabase.co';
export const TEST_ISSUER = `${TEST_SUPABASE_URL}/auth/v1`;
export const TEST_AUDIENCE = 'authenticated';

/**
 * Par de chaves local (ES256) e um JWKS em memória: o mesmo caminho de
 * verificação da produção, sem rede.
 */
export async function createTestAuth() {
  const { privateKey, publicKey } = await generateKeyPair('ES256', { extractable: true });
  const jwk = { ...(await exportJWK(publicKey)), kid: 'test-key', alg: 'ES256', use: 'sig' };
  const verifier = new JoseJwtVerifier({
    issuer: TEST_ISSUER,
    audience: TEST_AUDIENCE,
    keys: createLocalJWKSet({ keys: [jwk] }),
    clockToleranceSec: 0,
  });

  async function sign(
    sub: string,
    options: { expiresIn?: string | number; issuer?: string; audience?: string; claims?: JWTPayload } = {},
  ): Promise<string> {
    return new SignJWT({ role: 'authenticated', email: `${sub.slice(0, 8)}@example.com`, ...options.claims })
      .setProtectedHeader({ alg: 'ES256', kid: 'test-key' })
      .setSubject(sub)
      .setIssuer(options.issuer ?? TEST_ISSUER)
      .setAudience(options.audience ?? TEST_AUDIENCE)
      .setIssuedAt()
      .setExpirationTime(options.expiresIn ?? '1h')
      .sign(privateKey);
  }

  return { verifier, sign, jwk };
}

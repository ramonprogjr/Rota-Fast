import { z } from 'zod';

/** Variáveis de ambiente validadas na subida. Falha cedo se algo faltar. */
export const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  DATABASE_URL: z.string().url().refine((v) => v.startsWith('postgres'), 'DATABASE_URL deve ser postgres://'),
  DIRECT_URL: z.string().url().refine((v) => v.startsWith('postgres'), 'DIRECT_URL deve ser postgres://'),
  SUPABASE_URL: z
    .string()
    .url()
    .transform((v) => v.replace(/\/+$/, '')),
  SUPABASE_JWT_AUDIENCE: z.string().min(1).default('authenticated'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  CORS_ORIGINS: z
    .string()
    .default('')
    .transform((v) =>
      v
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean),
    ),
  RATE_LIMIT_PER_MINUTE: z.coerce.number().int().min(1).default(120),
});

export type Env = z.infer<typeof envSchema>;

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = envSchema.safeParse(source);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ');
    // Não imprime valores: só os nomes das variáveis com problema.
    throw new Error(`Configuração inválida: ${issues}`);
  }
  return parsed.data;
}

export const ENV = Symbol('ENV');

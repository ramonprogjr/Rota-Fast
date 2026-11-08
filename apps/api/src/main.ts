import 'reflect-metadata';
import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { JoseJwtVerifier } from './auth/jwt-verifier';
import { buildOpenApi, configureApp } from './bootstrap';
import { loadEnv } from './config/env';
import { PrismaDatabase } from './persistence/prisma/prisma-database';

async function main(): Promise<void> {
  const env = loadEnv();
  const app = await NestFactory.create(
    AppModule.forRoot({
      database: new PrismaDatabase(),
      verifier: JoseJwtVerifier.forSupabase(env.SUPABASE_URL, env.SUPABASE_JWT_AUDIENCE),
      rateLimitPerMinute: env.RATE_LIMIT_PER_MINUTE,
      requestLogging: true,
    }),
    { bufferLogs: false },
  );
  configureApp(app, { corsOrigins: env.CORS_ORIGINS });
  // Atrás do proxy do host (Render/Fly/Koyeb): IP real para o rate limit.
  app.getHttpAdapter().getInstance().set('trust proxy', 1);
  if (env.NODE_ENV !== 'production') {
    SwaggerModule.setup('docs', app, buildOpenApi(app));
  }
  app.enableShutdownHooks();
  await app.listen(env.PORT, '0.0.0.0');
  Logger.log(`Rota Max API ouvindo na porta ${env.PORT}`, 'Bootstrap');
}

void main();

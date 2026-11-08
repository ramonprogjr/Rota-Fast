import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { AppModule } from '../src/app.module';
import { RejectAllVerifier } from '../src/auth/jwt-verifier';
import { buildOpenApi, configureApp } from '../src/bootstrap';
import { MemoryDatabase } from '../src/persistence/memory/memory-database';

/**
 * Gera docs/api/openapi.json sem banco e sem Supabase: sobe o app com o
 * banco em memória e um verificador que recusa tudo, e só lê os metadados.
 */
async function main(): Promise<void> {
  const app = await NestFactory.create(
    AppModule.forRoot({ database: new MemoryDatabase(), verifier: new RejectAllVerifier() }),
    { logger: ['error', 'warn'] },
  );
  configureApp(app);
  await app.init();
  const document = buildOpenApi(app);
  // dist/scripts -> apps/api -> raiz do repositório
  const out = resolve(__dirname, '..', '..', '..', '..', 'docs', 'api', 'openapi.json');
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, `${JSON.stringify(document, null, 2)}\n`);
  await app.close();
  console.log(`OpenAPI gravado em ${out}`);
}

void main();

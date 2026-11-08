# Rota Max API

API NestJS do Rota Max: conta opcional, backup e sincronização do app offline-first. Supabase fornece Postgres + PostGIS + Auth; a API é a única que fala com o banco.

- Arquitetura e segurança: [docs/architecture/backend.md](../../docs/architecture/backend.md)
- DER: [docs/architecture/der.md](../../docs/architecture/der.md)
- Sincronização: [docs/api/sync-protocol.md](../../docs/api/sync-protocol.md)
- Contrato: [docs/api/openapi.json](../../docs/api/openapi.json) (`npm run openapi:export`)

## Requisitos

- Node 22 ou mais novo (CI usa 22).
- Para rodar contra um banco: um projeto Supabase (não precisa de Docker nem Postgres local para build e testes).

## Scripts

| Script | O que faz |
|---|---|
| `npm run build` | Compila para `dist/` (com o plugin do Swagger). |
| `npm run start:dev` | Sobe com watch (precisa do `.env`). |
| `npm run start:prod` | `node dist/src/main.js`. |
| `npm run lint` | ESLint. |
| `npm test` | Testes unitários (sem banco: repositório em memória). |
| `npm run test:e2e` | Sobe a API inteira com banco em memória e JWKS local. |
| `npm run prisma:generate` | Gera o Prisma Client. |
| `npm run prisma:migrate:deploy` | Aplica as migrations (usa `DIRECT_URL`). |
| `npm run openapi:export` | Gera `docs/api/openapi.json` sem banco. |

## Desenvolvimento local

```bash
cd apps/api
npm ci
npm run prisma:generate
npm run lint && npm test && npm run test:e2e
```

Build e testes não precisam de banco nem de Supabase.

## Configurar no Supabase (primeira vez)

1. **Criar o projeto** em [supabase.com](https://supabase.com) na região **South America (São Paulo) — `sa-east-1`** (LGPD e latência). Guarde a senha do banco num cofre.
2. **Auth**
   - Authentication › Providers: ligar e-mail (e, se quiser, Google).
   - Project Settings › JWT Keys: confirmar que o projeto usa **JWT Signing Keys** assimétricas (ES256/RS256). A API valida pelo JWKS em `https://<ref>.supabase.co/auth/v1/.well-known/jwks.json`; o segredo HS256 legado não é aceito.
3. **PostGIS**: Database › Extensions › habilitar `postgis` (schema `extensions`). A migration também roda `CREATE EXTENSION IF NOT EXISTS`.
4. **Data API**: Project Settings › Data API › desligar (o app não usa PostgREST). O RLS da migration já impede escrita direta, isto é uma camada a mais.
5. **Strings de conexão** (Project Settings › Database › Connection string):
   - `DATABASE_URL` = **Transaction pooler** (porta 6543) + `?pgbouncer=true&connection_limit=3`.
   - `DIRECT_URL` = **Session pooler/conexão direta** (porta 5432).
6. **Aplicar as migrations** (da sua máquina ou do CI de deploy, nunca com a senha no repositório):

   ```bash
   cd apps/api
   cp .env.example .env   # preencha os valores
   npx prisma migrate deploy
   ```

   A migration `20261108000000_init` cria tabelas, colunas `geography` geradas, índices (GIST, parciais), CHECKs, RLS e a semente de planos.
7. **Subir a API** no host (Render, Cloud Run…): build `npm ci && npx prisma generate && npm run build`, start `npm run start:prod`, health check `GET /v1/health`, variáveis do `.env.example`.

> A API conecta como o papel dono das tabelas (`postgres`), que ignora RLS. Essa credencial fica só no host da API. A chave `service_role` do Supabase não é usada nem deve ir para o app.

### Mudanças de banco

1. Editar `prisma/schema.prisma`.
2. `npx prisma migrate dev --create-only --name <nome>` contra um banco de desenvolvimento (projeto Supabase de teste).
3. Revisar o SQL: o Prisma não conhece colunas geradas (`location`), índices parciais, CHECKs nem policies — ele pode tentar recriá-los. Ajustar à mão.
4. Commitar a pasta da migration. Nunca editar uma migration já aplicada.

## Como o app Flutter chama a API

- Login opcional com `supabase_flutter` (só `SUPABASE_URL` e a chave pública via `--dart-define`). Sem login, o app não chama a API.
- Toda chamada: `Authorization: Bearer <session.accessToken>` para `API_BASE_URL` (ex.: `https://rota-max-api.onrender.com/v1`).
- Primeiro acesso: `GET /v1/me` (cria o perfil) e `POST /v1/devices` com o `device_id` guardado em `settings`.
- Sincronização: fila local `sync_queue` → `POST /v1/sync/push` (≤ 500) → `GET /v1/sync/pull?since=<cursor>` até `hasMore=false`. Detalhes e mudanças necessárias no app em [sync-protocol.md §6](../../docs/api/sync-protocol.md#6-o-que-o-app-flutter-precisa-ganhar).
- Otimização no servidor é opcional (`POST /v1/optimization/preview`); o app já otimiza localmente.

Exemplo:

```bash
curl -s https://<host>/v1/health
curl -s -H "Authorization: Bearer $TOKEN" "https://<host>/v1/routes?page=1&pageSize=20"
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"deviceId":"<uuid>","operations":[...]}' https://<host>/v1/sync/push
```

## Estrutura

```text
apps/api/
  prisma/schema.prisma            modelo (fonte das migrations)
  prisma/migrations/…_init/       SQL: tabelas, PostGIS, RLS, índices, sementes
  scripts/export-openapi.ts       gera docs/api/openapi.json
  src/
    main.ts, app.module.ts, bootstrap.ts
    config/        env validado (zod)
    common/        guard JWT, @Public, @CurrentUser, filtro de erro, middleware, regras puras
    auth/          verificador de JWT (JWKS)
    persistence/   interface de dados, Prisma, memória, EntityWriter (versão + log)
    users/ devices/ organizations/ routes/ deliveries/ optimization/
    synchronization/ subscriptions/ payments/ health/
    testing/       chaves JWT e fixtures dos testes (fora do build)
  test/            e2e
```

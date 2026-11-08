# Supabase — esboço antigo (SUBSTITUÍDO)

> **Esta pasta está obsoleta.** O banco da plataforma agora é definido e migrado pela API em
> [`apps/api/prisma/`](../apps/api/prisma) (Prisma é a única fonte de migrations), com
> PostGIS, RLS por usuário e o protocolo de sincronização. Veja
> [`docs/architecture/backend.md`](../docs/architecture/backend.md) e
> [`apps/api/README.md`](../apps/api/README.md).
>
> **Não aplique `schema.sql`.** Ele usa outro modelo (empresa como dono, `uuid-ossp`, status
> `pending/done`) e conflita com a migration da API. Fica aqui só como histórico.

O que mudou em relação a este esboço:

- O app **não** fala com o Postgres nem usa PostgREST: só com a API NestJS (e com o Supabase Auth para login).
- Dono das linhas é o usuário (`user_id = auth.uid()`); organizações ficaram preparadas (`organizations`, `memberships`).
- Entregas espelham o SQLite do app (status `PENDING/IN_PROGRESS/DELIVERED/FAILED/SKIPPED`, motivo, tentativas) e ganharam `version`, `deleted_at` e `location geography`.
- Pontos de GPS não sobem um a um: o turno guarda um resumo (`shifts.track`).
- A chave `service_role` não é usada em lugar nenhum; a API conecta com a string do Postgres, só no servidor.

`config.toml` também não é usado pela API.

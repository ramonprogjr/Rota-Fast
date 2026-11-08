# Supabase — fase futura (não usado na v1)

> **O app Rota Max v1 não usa esta pasta.** A v1 é offline-first, com SQLite no aparelho (ver [docs/PRD.md](../docs/PRD.md)). Este esboço fica como referência para a fase de plataforma: login, empresas, equipes e sincronização em nuvem.

## Ideia

- App: Flutter + SQLite local (continua sendo a fonte durante o turno, mesmo sem sinal)
- Nuvem: Supabase Postgres + Auth (+ Realtime para rastreio, Storage para comprovantes)
- Sincronização: o app envia as mudanças do SQLite em lote quando tiver rede

## Regras de segurança já no `schema.sql`

- RLS ativo em todas as tabelas, e cada usuário só enxerga dados da própria empresa (`current_company_id()`).
- O app só edita o próprio `full_name`. `role` e `company_id` mudam apenas por rotina administrativa.
- `dashboard_summary` usa `security_invoker`, então a view respeita o RLS.
- **A chave `service_role` nunca vai para o app.** Ela ignora o RLS e pode ser extraída de qualquer APK. Use-a só em backend ou Edge Function.

## Quando for retomar

1. Criar o projeto na região São Paulo (`sa-east-1`) por causa da LGPD e da latência.
2. Aplicar o `schema.sql` (`supabase db push`).
3. No app, adicionar `supabase_flutter` e passar só `SUPABASE_URL` e `SUPABASE_ANON_KEY` via `--dart-define`.
4. Desenhar a sincronização SQLite ↔ Postgres antes de escrever código: conflitos, envio em lote e pontos de GPS agregados.

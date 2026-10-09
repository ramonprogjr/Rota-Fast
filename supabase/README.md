# Supabase para Rota Max

## Objetivo

Usar o Supabase como banco e camada de autenticação para a fase de plataforma do Rota Max, mantendo o SQLite local no app móvel para funcionar offline.

## Estrutura recomendada

- App mobile: Flutter + SQLite local para uso offline
- Backend: Supabase Postgres + Auth + Realtime + Storage
- API: se necessário, pode usar Edge Functions ou um backend simples em FastAPI/Nest later

## Próximo passo

1. Criar um projeto no Supabase
2. Importar o schema em `schema.sql`
3. Configurar variáveis em `.env.example`
4. Conectar o app com `SUPABASE_URL` e `SUPABASE_ANON_KEY`

## Comandos úteis

```bash
supabase login
supabase init
supabase link --project-ref SEU_PROJECT_REF
supabase db push
```

## Observação

O projeto local do Flutter ainda continua como app mobile e usa SQLite. O Supabase entra como base central para empresas, usuários, entregadores e métricas.

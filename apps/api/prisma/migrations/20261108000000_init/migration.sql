-- Rota Max API — migration inicial.
-- Gerada a partir de prisma/schema.prisma (`prisma migrate diff --from-empty`) e
-- completada à mão com o que o Prisma não modela: extensões, colunas geography
-- GERADAS, CHECKs, índices parciais/GIST, RLS e a semente de planos.
-- Feita para rodar no Supabase com `prisma migrate deploy` usando DIRECT_URL.
-- Também roda num Postgres comum com PostGIS (cria um auth.uid() de mentira e os
-- papéis anon/authenticated se não existirem).

-- ---------------------------------------------------------------------------
-- Extensões. No Supabase elas vivem no schema "extensions".
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS "extensions";
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "postgis" WITH SCHEMA "extensions";
SET search_path TO public, extensions;

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "email" TEXT,
    "name" TEXT,
    "country" CHAR(2) NOT NULL DEFAULT 'BR',
    "locale" TEXT NOT NULL DEFAULT 'pt-BR',
    "timezone" TEXT NOT NULL DEFAULT 'America/Sao_Paulo',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "devices" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "platform" TEXT NOT NULL,
    "model" TEXT,
    "os_version" TEXT,
    "app_version" TEXT,
    "last_seen_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revoked_at" TIMESTAMPTZ(3),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "organizations" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" TEXT NOT NULL,
    "owner_id" UUID NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "organizations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "memberships" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "organization_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'driver',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "memberships_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "plans" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "price_cents" INTEGER NOT NULL DEFAULT 0,
    "currency" CHAR(3) NOT NULL DEFAULT 'BRL',
    "interval" TEXT NOT NULL DEFAULT 'month',
    "limits" JSONB NOT NULL DEFAULT '{}',
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "plans_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "subscriptions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID,
    "organization_id" UUID,
    "plan_id" UUID NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'active',
    "current_period_start" TIMESTAMPTZ(3),
    "current_period_end" TIMESTAMPTZ(3),
    "provider" TEXT,
    "provider_ref" TEXT,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payments" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "subscription_id" UUID NOT NULL,
    "user_id" UUID,
    "amount_cents" INTEGER NOT NULL,
    "currency" CHAR(3) NOT NULL DEFAULT 'BRL',
    "status" TEXT NOT NULL DEFAULT 'pending',
    "provider" TEXT,
    "provider_ref" TEXT,
    "paid_at" TIMESTAMPTZ(3),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "payments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "deliveries" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "order_number" TEXT,
    "package_id" TEXT,
    "customer_name" TEXT NOT NULL,
    "phone" TEXT,
    "address" TEXT NOT NULL,
    "number" TEXT,
    "complement" TEXT,
    "neighborhood" TEXT,
    "postal_code" TEXT,
    "city" TEXT NOT NULL,
    "state" TEXT,
    "latitude" DOUBLE PRECISION,
    "longitude" DOUBLE PRECISION,
    "location" geography(Point,4326) GENERATED ALWAYS AS (CASE WHEN "latitude" IS NOT NULL AND "longitude" IS NOT NULL THEN (ST_SetSRID(ST_MakePoint("longitude", "latitude"), 4326))::geography END) STORED,
    "location_confirmed" BOOLEAN NOT NULL DEFAULT false,
    "value" DOUBLE PRECISION,
    "notes" TEXT,
    "priority" TEXT NOT NULL DEFAULT 'normal',
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "failure_reason" TEXT,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "delivered_at" TIMESTAMPTZ(3),
    "version" BIGINT NOT NULL DEFAULT 1,
    "field_versions" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "deliveries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "routes" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "name" TEXT,
    "status" TEXT NOT NULL DEFAULT 'draft',
    "origin_lat" DOUBLE PRECISION,
    "origin_lng" DOUBLE PRECISION,
    "end_lat" DOUBLE PRECISION,
    "end_lng" DOUBLE PRECISION,
    "estimated_km" DOUBLE PRECISION,
    "estimated_minutes" INTEGER,
    "nav_app" TEXT,
    "manually_edited" BOOLEAN NOT NULL DEFAULT false,
    "started_at" TIMESTAMPTZ(3),
    "completed_at" TIMESTAMPTZ(3),
    "version" BIGINT NOT NULL DEFAULT 1,
    "field_versions" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "routes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "route_stops" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "route_id" UUID NOT NULL,
    "delivery_id" UUID NOT NULL,
    "position" INTEGER NOT NULL,
    "locked" BOOLEAN NOT NULL DEFAULT false,
    "fixed_position" INTEGER,
    "version" BIGINT NOT NULL DEFAULT 1,
    "field_versions" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "route_stops_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "delivery_events" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "delivery_id" UUID NOT NULL,
    "kind" TEXT NOT NULL DEFAULT 'status',
    "from_status" TEXT,
    "to_status" TEXT NOT NULL,
    "reason" TEXT,
    "note" TEXT,
    "changed_fields" JSONB,
    "latitude" DOUBLE PRECISION,
    "longitude" DOUBLE PRECISION,
    "occurred_at" TIMESTAMPTZ(3) NOT NULL,
    "device_id" UUID,
    "version" BIGINT NOT NULL DEFAULT 1,
    "field_versions" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "delivery_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "route_plans" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "route_id" UUID NOT NULL,
    "stops" INTEGER NOT NULL,
    "baseline_km" DOUBLE PRECISION NOT NULL,
    "baseline_minutes" INTEGER NOT NULL,
    "optimized_km" DOUBLE PRECISION NOT NULL,
    "optimized_minutes" INTEGER NOT NULL,
    "version" BIGINT NOT NULL DEFAULT 1,
    "field_versions" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "route_plans_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "vehicles" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "plate" TEXT,
    "fuel_type" TEXT NOT NULL DEFAULT 'gasoline',
    "km_per_liter" DOUBLE PRECISION NOT NULL,
    "fuel_price" DOUBLE PRECISION NOT NULL,
    "avg_speed_kmh" DOUBLE PRECISION NOT NULL,
    "odometer_km" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "oil_interval_km" DOUBLE PRECISION NOT NULL,
    "last_oil_change_km" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "is_active" BOOLEAN NOT NULL DEFAULT false,
    "version" BIGINT NOT NULL DEFAULT 1,
    "field_versions" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "vehicles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "oil_changes" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "vehicle_id" UUID NOT NULL,
    "odometer_km" DOUBLE PRECISION NOT NULL,
    "changed_at" TIMESTAMPTZ(3) NOT NULL,
    "note" TEXT,
    "version" BIGINT NOT NULL DEFAULT 1,
    "field_versions" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "oil_changes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "shifts" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "vehicle_id" UUID,
    "started_at" TIMESTAMPTZ(3) NOT NULL,
    "ended_at" TIMESTAMPTZ(3),
    "gps_km" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "odometer_start" DOUBLE PRECISION,
    "odometer_end" DOUBLE PRECISION,
    "track" JSONB,
    "version" BIGINT NOT NULL DEFAULT 1,
    "field_versions" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "shifts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "base_locations" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "address" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "latitude" DOUBLE PRECISION,
    "longitude" DOUBLE PRECISION,
    "location" geography(Point,4326) GENERATED ALWAYS AS (CASE WHEN "latitude" IS NOT NULL AND "longitude" IS NOT NULL THEN (ST_SetSRID(ST_MakePoint("longitude", "latitude"), 4326))::geography END) STORED,
    "is_default" BOOLEAN NOT NULL DEFAULT true,
    "version" BIGINT NOT NULL DEFAULT 1,
    "field_versions" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(3),

    CONSTRAINT "base_locations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sync_operations" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "device_id" UUID NOT NULL,
    "entity_type" TEXT NOT NULL,
    "entity_id" UUID NOT NULL,
    "operation_type" TEXT NOT NULL,
    "base_version" BIGINT,
    "payload" JSONB NOT NULL,
    "status" TEXT NOT NULL,
    "reason" TEXT,
    "result" JSONB NOT NULL,
    "client_created_at" TIMESTAMPTZ(3),
    "received_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sync_operations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sync_changes" (
    "seq" BIGSERIAL NOT NULL,
    "user_id" UUID NOT NULL,
    "entity_type" TEXT NOT NULL,
    "entity_id" UUID NOT NULL,
    "version" BIGINT NOT NULL,
    "operation" TEXT NOT NULL,
    "changed_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sync_changes_pkey" PRIMARY KEY ("seq")
);

-- CreateTable
CREATE TABLE "audit_logs" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID,
    "action" TEXT NOT NULL,
    "entity_type" TEXT,
    "entity_id" UUID,
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "devices_user_id_idx" ON "devices"("user_id");

-- CreateIndex
CREATE INDEX "organizations_owner_id_idx" ON "organizations"("owner_id");

-- CreateIndex
CREATE INDEX "memberships_user_id_idx" ON "memberships"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "memberships_organization_id_user_id_key" ON "memberships"("organization_id", "user_id");

-- CreateIndex
CREATE UNIQUE INDEX "plans_code_key" ON "plans"("code");

-- CreateIndex
CREATE INDEX "subscriptions_user_id_idx" ON "subscriptions"("user_id");

-- CreateIndex
CREATE INDEX "subscriptions_organization_id_idx" ON "subscriptions"("organization_id");

-- CreateIndex
CREATE INDEX "payments_subscription_id_idx" ON "payments"("subscription_id");

-- CreateIndex
CREATE INDEX "payments_user_id_idx" ON "payments"("user_id");

-- CreateIndex
CREATE INDEX "deliveries_user_id_status_idx" ON "deliveries"("user_id", "status");

-- CreateIndex
CREATE INDEX "deliveries_user_id_updated_at_idx" ON "deliveries"("user_id", "updated_at");

-- CreateIndex
CREATE INDEX "deliveries_created_at_idx" ON "deliveries"("created_at");

-- CreateIndex
CREATE INDEX "routes_user_id_status_idx" ON "routes"("user_id", "status");

-- CreateIndex
CREATE INDEX "routes_user_id_updated_at_idx" ON "routes"("user_id", "updated_at");

-- CreateIndex
CREATE INDEX "routes_created_at_idx" ON "routes"("created_at");

-- CreateIndex
CREATE INDEX "route_stops_route_id_position_idx" ON "route_stops"("route_id", "position");

-- CreateIndex
CREATE INDEX "route_stops_delivery_id_idx" ON "route_stops"("delivery_id");

-- CreateIndex
CREATE INDEX "route_stops_user_id_updated_at_idx" ON "route_stops"("user_id", "updated_at");

-- CreateIndex
CREATE INDEX "delivery_events_delivery_id_occurred_at_idx" ON "delivery_events"("delivery_id", "occurred_at");

-- CreateIndex
CREATE INDEX "delivery_events_user_id_updated_at_idx" ON "delivery_events"("user_id", "updated_at");

-- CreateIndex
CREATE INDEX "delivery_events_created_at_idx" ON "delivery_events"("created_at");

-- CreateIndex
CREATE INDEX "route_plans_route_id_idx" ON "route_plans"("route_id");

-- CreateIndex
CREATE INDEX "route_plans_user_id_updated_at_idx" ON "route_plans"("user_id", "updated_at");

-- CreateIndex
CREATE INDEX "vehicles_user_id_updated_at_idx" ON "vehicles"("user_id", "updated_at");

-- CreateIndex
CREATE INDEX "oil_changes_vehicle_id_changed_at_idx" ON "oil_changes"("vehicle_id", "changed_at");

-- CreateIndex
CREATE INDEX "oil_changes_user_id_updated_at_idx" ON "oil_changes"("user_id", "updated_at");

-- CreateIndex
CREATE INDEX "shifts_user_id_started_at_idx" ON "shifts"("user_id", "started_at");

-- CreateIndex
CREATE INDEX "shifts_user_id_updated_at_idx" ON "shifts"("user_id", "updated_at");

-- CreateIndex
CREATE INDEX "base_locations_user_id_updated_at_idx" ON "base_locations"("user_id", "updated_at");

-- CreateIndex
CREATE INDEX "sync_operations_user_id_received_at_idx" ON "sync_operations"("user_id", "received_at");

-- CreateIndex
CREATE INDEX "sync_operations_entity_id_idx" ON "sync_operations"("entity_id");

-- CreateIndex
CREATE INDEX "sync_operations_user_id_status_idx" ON "sync_operations"("user_id", "status");

-- CreateIndex
CREATE INDEX "sync_changes_user_id_seq_idx" ON "sync_changes"("user_id", "seq");

-- CreateIndex
CREATE INDEX "audit_logs_user_id_created_at_idx" ON "audit_logs"("user_id", "created_at");

-- AddForeignKey
ALTER TABLE "devices" ADD CONSTRAINT "devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "memberships" ADD CONSTRAINT "memberships_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "memberships" ADD CONSTRAINT "memberships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "plans"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payments" ADD CONSTRAINT "payments_subscription_id_fkey" FOREIGN KEY ("subscription_id") REFERENCES "subscriptions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "deliveries" ADD CONSTRAINT "deliveries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "routes" ADD CONSTRAINT "routes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "route_stops" ADD CONSTRAINT "route_stops_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "route_stops" ADD CONSTRAINT "route_stops_route_id_fkey" FOREIGN KEY ("route_id") REFERENCES "routes"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "route_stops" ADD CONSTRAINT "route_stops_delivery_id_fkey" FOREIGN KEY ("delivery_id") REFERENCES "deliveries"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "delivery_events" ADD CONSTRAINT "delivery_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "delivery_events" ADD CONSTRAINT "delivery_events_delivery_id_fkey" FOREIGN KEY ("delivery_id") REFERENCES "deliveries"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "route_plans" ADD CONSTRAINT "route_plans_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "route_plans" ADD CONSTRAINT "route_plans_route_id_fkey" FOREIGN KEY ("route_id") REFERENCES "routes"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vehicles" ADD CONSTRAINT "vehicles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "oil_changes" ADD CONSTRAINT "oil_changes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "oil_changes" ADD CONSTRAINT "oil_changes_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "vehicles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "shifts" ADD CONSTRAINT "shifts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "shifts" ADD CONSTRAINT "shifts_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "vehicles"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "base_locations" ADD CONSTRAINT "base_locations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- ===========================================================================
-- Daqui para baixo: SQL que o Prisma não gera.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Ligação com o Supabase Auth: users.id = auth.users.id.
-- Fora do Supabase (Postgres local) cria um auth.uid() que lê o claim do
-- PostgREST e os papéis anon/authenticated, para as policies compilarem.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'auth' AND p.proname = 'uid'
  ) THEN
    CREATE SCHEMA IF NOT EXISTS auth;
    EXECUTE $fn$
      CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
      'SELECT nullif(current_setting(''request.jwt.claim.sub'', true), '''')::uuid'
    $fn$;
  END IF;
  IF to_regclass('auth.users') IS NOT NULL THEN
    ALTER TABLE "users" ADD CONSTRAINT "users_auth_users_fkey"
      FOREIGN KEY ("id") REFERENCES auth.users ("id") ON DELETE CASCADE;
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- Regras de domínio (CHECK). Espelham o app (lib/models) e a API.
-- ---------------------------------------------------------------------------
ALTER TABLE "deliveries"
  ADD CONSTRAINT "deliveries_status_check"
    CHECK ("status" IN ('PENDING','IN_PROGRESS','DELIVERED','FAILED','SKIPPED')),
  ADD CONSTRAINT "deliveries_priority_check"
    CHECK ("priority" IN ('normal','high','urgent')),
  ADD CONSTRAINT "deliveries_failure_reason_check"
    CHECK ("failure_reason" IS NULL OR "failure_reason" IN ('ABSENT','ADDRESS_NOT_FOUND','REFUSED','CLOSED','ACCESS','OTHER')),
  ADD CONSTRAINT "deliveries_attempts_check" CHECK ("attempts" >= 0),
  ADD CONSTRAINT "deliveries_lat_check" CHECK ("latitude" IS NULL OR "latitude" BETWEEN -90 AND 90),
  ADD CONSTRAINT "deliveries_lng_check" CHECK ("longitude" IS NULL OR "longitude" BETWEEN -180 AND 180),
  ADD CONSTRAINT "deliveries_version_check" CHECK ("version" >= 1);

ALTER TABLE "routes"
  ADD CONSTRAINT "routes_status_check" CHECK ("status" IN ('draft','active','completed')),
  ADD CONSTRAINT "routes_version_check" CHECK ("version" >= 1);

ALTER TABLE "route_stops"
  ADD CONSTRAINT "route_stops_position_check" CHECK ("position" >= 0),
  ADD CONSTRAINT "route_stops_fixed_position_check" CHECK ("fixed_position" IS NULL OR "fixed_position" >= 0);

ALTER TABLE "delivery_events"
  ADD CONSTRAINT "delivery_events_kind_check" CHECK ("kind" IN ('status','edit')),
  ADD CONSTRAINT "delivery_events_to_status_check"
    CHECK ("to_status" IN ('PENDING','IN_PROGRESS','DELIVERED','FAILED','SKIPPED')),
  ADD CONSTRAINT "delivery_events_from_status_check"
    CHECK ("from_status" IS NULL OR "from_status" IN ('PENDING','IN_PROGRESS','DELIVERED','FAILED','SKIPPED'));

ALTER TABLE "vehicles"
  ADD CONSTRAINT "vehicles_type_check" CHECK ("type" IN ('motorcycle','car','utility','van','truck')),
  ADD CONSTRAINT "vehicles_fuel_type_check" CHECK ("fuel_type" IN ('gasoline','ethanol','flex','diesel'));

ALTER TABLE "memberships"
  ADD CONSTRAINT "memberships_role_check" CHECK ("role" IN ('owner','admin','driver'));

ALTER TABLE "subscriptions"
  ADD CONSTRAINT "subscriptions_status_check" CHECK ("status" IN ('trialing','active','past_due','canceled')),
  ADD CONSTRAINT "subscriptions_owner_check" CHECK (num_nonnulls("user_id", "organization_id") = 1);

ALTER TABLE "payments"
  ADD CONSTRAINT "payments_status_check" CHECK ("status" IN ('pending','paid','failed','refunded'));

ALTER TABLE "sync_operations"
  ADD CONSTRAINT "sync_operations_status_check" CHECK ("status" IN ('applied','conflict','rejected')),
  ADD CONSTRAINT "sync_operations_type_check"
    CHECK ("operation_type" IN ('create','update','delete','transition','reorder'));

ALTER TABLE "sync_changes"
  ADD CONSTRAINT "sync_changes_operation_check" CHECK ("operation" IN ('upsert','delete'));

-- ---------------------------------------------------------------------------
-- Índices que o Prisma não modela.
-- ---------------------------------------------------------------------------
-- Uma entrega aparece no máximo uma vez por rota (entre as paradas vivas).
CREATE UNIQUE INDEX "route_stops_route_delivery_live_key"
  ON "route_stops" ("route_id", "delivery_id") WHERE "deleted_at" IS NULL;
-- Só uma rota ativa por usuário.
CREATE UNIQUE INDEX "routes_one_active_per_user"
  ON "routes" ("user_id") WHERE "status" = 'active' AND "deleted_at" IS NULL;
-- Só um veículo ativo por usuário.
CREATE UNIQUE INDEX "vehicles_one_active_per_user"
  ON "vehicles" ("user_id") WHERE "is_active" AND "deleted_at" IS NULL;
-- Geografia.
CREATE INDEX "deliveries_location_gist" ON "deliveries" USING GIST ("location");
CREATE INDEX "base_locations_location_gist" ON "base_locations" USING GIST ("location");

-- ---------------------------------------------------------------------------
-- RLS — defesa em profundidade.
-- O app NUNCA fala com o Postgres: só com a API. A API conecta como dona das
-- tabelas (papel "postgres" no Supabase), que ignora RLS (sem FORCE). Os papéis
-- anon/authenticated (Data API/PostgREST) só conseguem LER as próprias linhas;
-- nenhuma escrita direta. Recomendação: desligar a Data API no painel.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_org_member(org uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.memberships m
    WHERE m.organization_id = org AND m.user_id = (SELECT auth.uid())
  )
$$;
REVOKE ALL ON FUNCTION public.is_org_member(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_org_member(uuid) TO authenticated;

DO $$
DECLARE
  t text;
  owned text[] := ARRAY[
    'devices','deliveries','routes','route_stops','delivery_events','route_plans',
    'vehicles','oil_changes','shifts','base_locations','sync_operations',
    'sync_changes','audit_logs','payments'
  ];
  all_tables text[] := ARRAY[
    'users','devices','organizations','memberships','plans','subscriptions','payments',
    'deliveries','routes','route_stops','delivery_events','route_plans','vehicles',
    'oil_changes','shifts','base_locations','sync_operations','sync_changes','audit_logs'
  ];
BEGIN
  FOREACH t IN ARRAY all_tables LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated', t);
    EXECUTE format('GRANT SELECT ON public.%I TO authenticated', t);
  END LOOP;

  FOREACH t IN ARRAY owned LOOP
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()))',
      t || '_owner_select', t
    );
  END LOOP;
END
$$;

CREATE POLICY "users_self_select" ON "users"
  FOR SELECT TO authenticated USING ("id" = (SELECT auth.uid()));

-- Organizações (preparado): membros leem a organização e as filiações dela.
CREATE POLICY "organizations_member_select" ON "organizations"
  FOR SELECT TO authenticated USING (public.is_org_member("id"));
CREATE POLICY "memberships_member_select" ON "memberships"
  FOR SELECT TO authenticated
  USING ("user_id" = (SELECT auth.uid()) OR public.is_org_member("organization_id"));

CREATE POLICY "plans_public_select" ON "plans"
  FOR SELECT TO authenticated USING ("is_active");

CREATE POLICY "subscriptions_owner_select" ON "subscriptions"
  FOR SELECT TO authenticated
  USING (
    "user_id" = (SELECT auth.uid())
    OR ("organization_id" IS NOT NULL AND public.is_org_member("organization_id"))
  );

-- O cursor do pull depende desta sequência: só a API escreve.
REVOKE ALL ON SEQUENCE "sync_changes_seq_seq" FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- Semente: planos. Monetização preparada e desligada (pro inativo).
-- ---------------------------------------------------------------------------
INSERT INTO "plans" ("code", "name", "price_cents", "currency", "interval", "limits", "is_active", "updated_at")
VALUES
  ('free', 'Grátis', 0, 'BRL', 'month',
   '{"devices": 2, "syncEnabled": true, "historyDays": 365}', true, CURRENT_TIMESTAMP),
  ('pro', 'Pro', 0, 'BRL', 'month',
   '{"devices": 5, "syncEnabled": true, "historyDays": 1825}', false, CURRENT_TIMESTAMP)
ON CONFLICT ("code") DO NOTHING;

COMMENT ON TABLE "sync_operations" IS 'Operações de /v1/sync/push. id = operation_id (idempotência). Conflitos ficam guardados.';
COMMENT ON TABLE "sync_changes" IS 'Log de mudanças por usuário; seq é o cursor de /v1/sync/pull. Inclui tombstones.';
COMMENT ON COLUMN "deliveries"."location" IS 'Gerada de latitude/longitude. Não escrever.';
COMMENT ON COLUMN "deliveries"."field_versions" IS 'Mapa campo -> versão em que mudou por último (detecção de conflito por campo).';

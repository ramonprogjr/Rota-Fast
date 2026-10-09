create extension if not exists "uuid-ossp";

create table if not exists public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  city text not null default 'São Bernardo do Campo',
  plan text not null default 'starter',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid references public.companies(id) on delete set null,
  full_name text not null,
  email text not null unique,
  role text not null default 'driver' check (role in ('driver', 'manager', 'admin')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.drivers (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  profile_id uuid references public.profiles(id) on delete set null,
  full_name text not null,
  phone text,
  vehicle_type text not null default 'Moto',
  status text not null default 'available' check (status in ('available', 'busy', 'offline')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.shifts (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  driver_id uuid not null references public.drivers(id) on delete cascade,
  title text,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  status text not null default 'active' check (status in ('planned', 'active', 'completed', 'cancelled')),
  route_km double precision not null default 0,
  earnings double precision not null default 0,
  deliveries_completed integer not null default 0,
  deliveries_pending integer not null default 0,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.deliveries (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  driver_id uuid references public.drivers(id) on delete set null,
  customer_name text not null,
  phone text,
  address text not null,
  number text,
  complement text,
  neighborhood text,
  city text not null default 'São Bernardo do Campo',
  latitude double precision,
  longitude double precision,
  value double precision,
  priority text not null default 'normal' check (priority in ('normal', 'high', 'urgent')),
  status text not null default 'pending' check (status in ('pending', 'done')),
  route_order integer,
  location_confirmed boolean not null default false,
  created_at timestamptz not null default now(),
  delivered_at timestamptz
);

create table if not exists public.track_points (
  id uuid primary key default uuid_generate_v4(),
  shift_id uuid not null references public.shifts(id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  recorded_at timestamptz not null default now()
);

create index if not exists idx_companies_name on public.companies(name);
create index if not exists idx_profiles_company on public.profiles(company_id);
create index if not exists idx_drivers_company on public.drivers(company_id);
create index if not exists idx_deliveries_company_status on public.deliveries(company_id, status, created_at);
create index if not exists idx_shifts_driver on public.shifts(driver_id, started_at);

alter table public.companies enable row level security;
alter table public.profiles enable row level security;
alter table public.drivers enable row level security;
alter table public.shifts enable row level security;
alter table public.deliveries enable row level security;
alter table public.track_points enable row level security;

create policy "Empresa pode ver seus dados" on public.companies
for all using (true) with check (true);

create policy "Usuários podem ver seu perfil" on public.profiles
for all using (auth.uid() = id) with check (auth.uid() = id);

create policy "Usuários da empresa podem ver entregadores" on public.drivers
for all using (true) with check (true);

create policy "Usuários da empresa podem ver turnos" on public.shifts
for all using (true) with check (true);

create policy "Usuários da empresa podem ver entregas" on public.deliveries
for all using (true) with check (true);

create policy "Usuários da empresa podem ver pontos" on public.track_points
for all using (true) with check (true);

create or replace view public.dashboard_summary as
select
  d.company_id,
  date_trunc('day', d.created_at)::date as day,
  count(*) as deliveries,
  coalesce(sum(d.value), 0) as earnings,
  count(distinct d.driver_id) as active_drivers
from public.deliveries d
where d.status = 'done'
group by d.company_id, date_trunc('day', d.created_at)::date;

-- =====================================================================
-- Sistem Clinic · Etapa 1 · Schema base (multi-empresa)
-- Toda tabela de negócio tem empresa_id. Chaves estrangeiras compostas
-- (id, empresa_id) garantem que um registro filho nunca aponte para um
-- pai de outra empresa.
-- =====================================================================

create extension if not exists pgcrypto;

create schema if not exists app;
comment on schema app is 'Funções internas (não expostas pela API REST).';

-- ---------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------
create type public.segmento_empresa as enum ('clinica', 'odontologia', 'estetica', 'salao', 'outro');
create type public.status_assinatura as enum ('teste', 'ativa', 'inadimplente', 'bloqueada', 'cancelada');
create type public.papel_membro as enum ('dono', 'recepcao', 'profissional');

-- ---------------------------------------------------------------------
-- Gatilho genérico de atualizado_em
-- ---------------------------------------------------------------------
create or replace function app.tocar_atualizado_em()
returns trigger language plpgsql as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- Plataforma
-- ---------------------------------------------------------------------
create table public.planos (
  id                    uuid primary key default gen_random_uuid(),
  codigo                text not null unique,
  nome                  text not null,
  descricao             text,
  preco_mensal          numeric(10,2) not null check (preco_mensal >= 0),
  limite_unidades       int check (limite_unidades > 0),        -- null = ilimitado
  limite_profissionais  int check (limite_profissionais > 0),
  limite_usuarios       int check (limite_usuarios > 0),
  recursos              jsonb not null default '{}'::jsonb,
  ordem                 int not null default 0,
  ativo                 boolean not null default true,
  criado_em             timestamptz not null default now(),
  atualizado_em         timestamptz not null default now()
);

create table public.empresas (
  id                 uuid primary key default gen_random_uuid(),
  nome               text not null check (length(trim(nome)) between 2 and 120),
  documento          text,
  segmento           public.segmento_empresa not null default 'clinica',
  telefone           text,
  plano_id           uuid not null references public.planos(id),
  status_assinatura  public.status_assinatura not null default 'teste',
  teste_ate          timestamptz,
  bloqueada_em       timestamptz,
  logo_url           text,
  cor_marca          text check (cor_marca is null or cor_marca ~ '^#[0-9a-fA-F]{6}$'),
  criado_por         uuid references auth.users(id) on delete set null,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now()
);
create index on public.empresas (plano_id);
create index on public.empresas (status_assinatura);

create table public.admins_plataforma (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  criado_em  timestamptz not null default now()
);

create table public.auditoria (
  id           bigint generated always as identity primary key,
  empresa_id   uuid references public.empresas(id) on delete set null,
  user_id      uuid,
  acao         text not null,
  tabela       text,
  registro_id  uuid,
  dados        jsonb,
  criado_em    timestamptz not null default now()
);
create index on public.auditoria (empresa_id, criado_em desc);

-- ---------------------------------------------------------------------
-- Acesso e usuários
-- ---------------------------------------------------------------------
create table public.perfis (
  id             uuid primary key references auth.users(id) on delete cascade,
  nome           text,
  email          text,
  telefone       text,
  avatar_url     text,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);

create table public.membros (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  papel           public.papel_membro not null,
  todas_unidades  boolean not null default false,
  ativo           boolean not null default true,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  unique (empresa_id, user_id),
  unique (id, empresa_id)
);
create index on public.membros (user_id);
-- liga ao perfil para a API conseguir trazer nome/e-mail junto com o vínculo
alter table public.membros
  add constraint membros_perfil_fk foreign key (user_id) references public.perfis(id) on delete cascade;

-- ---------------------------------------------------------------------
-- Estrutura da empresa
-- ---------------------------------------------------------------------
create table public.unidades (
  id                     uuid primary key default gen_random_uuid(),
  empresa_id             uuid not null references public.empresas(id) on delete cascade,
  nome                   text not null check (length(trim(nome)) between 2 and 120),
  telefone               text,
  endereco               text,
  cidade                 text,
  uf                     char(2),
  fuso_horario           text not null default 'America/Sao_Paulo',
  link_avaliacao_google  text,
  ativo                  boolean not null default true,
  criado_em              timestamptz not null default now(),
  atualizado_em          timestamptz not null default now(),
  unique (id, empresa_id)
);
create index on public.unidades (empresa_id);

create table public.membro_unidades (
  empresa_id  uuid not null,
  membro_id   uuid not null,
  unidade_id  uuid not null,
  primary key (membro_id, unidade_id),
  foreign key (membro_id, empresa_id)  references public.membros(id, empresa_id)  on delete cascade,
  foreign key (unidade_id, empresa_id) references public.unidades(id, empresa_id) on delete cascade
);
create index on public.membro_unidades (empresa_id);
create index on public.membro_unidades (unidade_id);

create table public.horarios_unidade (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null,
  unidade_id  uuid not null,
  dia_semana  smallint not null check (dia_semana between 0 and 6),  -- 0 = domingo
  abre        time not null,
  fecha       time not null,
  check (fecha > abre),
  foreign key (unidade_id, empresa_id) references public.unidades(id, empresa_id) on delete cascade
);
create index on public.horarios_unidade (empresa_id);
create index on public.horarios_unidade (unidade_id, dia_semana);

create table public.profissionais (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas(id) on delete cascade,
  membro_id      uuid,
  nome           text not null check (length(trim(nome)) between 2 and 120),
  especialidade  text,
  registro       text,
  telefone       text,
  email          text,
  cor_agenda     text not null default '#2563EB' check (cor_agenda ~ '^#[0-9a-fA-F]{6}$'),
  ativo          boolean not null default true,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (id, empresa_id),
  foreign key (membro_id, empresa_id) references public.membros(id, empresa_id) on delete set null (membro_id)
);
create index on public.profissionais (empresa_id);
create unique index profissionais_membro_unico on public.profissionais (membro_id) where membro_id is not null;

create table public.profissional_unidades (
  empresa_id       uuid not null,
  profissional_id  uuid not null,
  unidade_id       uuid not null,
  primary key (profissional_id, unidade_id),
  foreign key (profissional_id, empresa_id) references public.profissionais(id, empresa_id) on delete cascade,
  foreign key (unidade_id, empresa_id)      references public.unidades(id, empresa_id)      on delete cascade
);
create index on public.profissional_unidades (empresa_id);
create index on public.profissional_unidades (unidade_id);

create table public.jornadas (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null,
  profissional_id  uuid not null,
  unidade_id       uuid not null,
  dia_semana       smallint not null check (dia_semana between 0 and 6),
  inicio           time not null,
  fim              time not null,
  check (fim > inicio),
  foreign key (profissional_id, empresa_id) references public.profissionais(id, empresa_id) on delete cascade,
  foreign key (unidade_id, empresa_id)      references public.unidades(id, empresa_id)      on delete cascade
);
create index on public.jornadas (empresa_id);
create index on public.jornadas (profissional_id, dia_semana);

create table public.servicos (
  id                  uuid primary key default gen_random_uuid(),
  empresa_id          uuid not null references public.empresas(id) on delete cascade,
  nome                text not null check (length(trim(nome)) between 2 and 120),
  descricao           text,
  categoria           text,
  duracao_min         int not null check (duracao_min between 5 and 720),
  preco               numeric(10,2) not null default 0 check (preco >= 0),
  intervalo_apos_min  int not null default 0 check (intervalo_apos_min between 0 and 240),
  cor                 text check (cor is null or cor ~ '^#[0-9a-fA-F]{6}$'),
  agendavel_whatsapp  boolean not null default true,
  ativo               boolean not null default true,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  unique (id, empresa_id)
);
create index on public.servicos (empresa_id);

create table public.servico_profissionais (
  empresa_id       uuid not null,
  servico_id       uuid not null,
  profissional_id  uuid not null,
  preco_proprio    numeric(10,2) check (preco_proprio >= 0),
  duracao_propria  int check (duracao_propria between 5 and 720),
  primary key (servico_id, profissional_id),
  foreign key (servico_id, empresa_id)      references public.servicos(id, empresa_id)      on delete cascade,
  foreign key (profissional_id, empresa_id) references public.profissionais(id, empresa_id) on delete cascade
);
create index on public.servico_profissionais (empresa_id);
create index on public.servico_profissionais (profissional_id);

create table public.convites (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas(id) on delete cascade,
  email            text not null check (email = lower(trim(email)) and email like '%@%'),
  papel            public.papel_membro not null,
  todas_unidades   boolean not null default false,
  unidade_ids      uuid[] not null default '{}',
  profissional_id  uuid,
  token            uuid not null unique default gen_random_uuid(),
  expira_em        timestamptz not null default now() + interval '7 days',
  aceito_em        timestamptz,
  aceito_por       uuid references auth.users(id) on delete set null,
  criado_por       uuid references auth.users(id) on delete set null,
  criado_em        timestamptz not null default now(),
  foreign key (profissional_id, empresa_id) references public.profissionais(id, empresa_id) on delete set null (profissional_id)
);
create index on public.convites (empresa_id);
create index on public.convites (email);

-- ---------------------------------------------------------------------
-- Gatilhos de atualizado_em
-- ---------------------------------------------------------------------
create trigger tg_planos_atualizado        before update on public.planos        for each row execute function app.tocar_atualizado_em();
create trigger tg_empresas_atualizado      before update on public.empresas      for each row execute function app.tocar_atualizado_em();
create trigger tg_perfis_atualizado        before update on public.perfis        for each row execute function app.tocar_atualizado_em();
create trigger tg_membros_atualizado       before update on public.membros       for each row execute function app.tocar_atualizado_em();
create trigger tg_unidades_atualizado      before update on public.unidades      for each row execute function app.tocar_atualizado_em();
create trigger tg_profissionais_atualizado before update on public.profissionais for each row execute function app.tocar_atualizado_em();
create trigger tg_servicos_atualizado      before update on public.servicos      for each row execute function app.tocar_atualizado_em();

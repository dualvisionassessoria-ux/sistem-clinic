-- Sistem Clinic · instalação completa (gerado por montar_instalacao.sh)
-- Cole tudo no SQL Editor do Supabase e clique em Run. Rode UMA vez num projeto vazio.

-- >>> migrations/20261124000100_schema_base.sql
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

-- >>> migrations/20261124000200_funcoes_e_regras.sql
-- =====================================================================
-- Sistem Clinic · Etapa 1 · Funções auxiliares e regras de negócio
-- (gatilhos de limite do plano, proteção do último dono, perfil)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Funções auxiliares usadas pelo RLS.
-- security definer: leem membros/empresas sem passar pelo RLS,
-- o que evita recursão nas políticas.
-- ---------------------------------------------------------------------

-- Usuário é super-admin da plataforma?
create or replace function app.is_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admins_plataforma where user_id = auth.uid());
$$;

-- Usuário tem vínculo ativo com a empresa (qualquer status de assinatura)?
-- Usado só para LER a própria empresa (e mostrar o aviso de bloqueio).
create or replace function app.vinculado(p_empresa uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.membros m
    where m.empresa_id = p_empresa and m.user_id = auth.uid() and m.ativo
  );
$$;

-- Usuário é membro ativo de uma empresa com assinatura liberada?
create or replace function app.e_membro(p_empresa uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.membros m
    join public.empresas e on e.id = m.empresa_id
    where m.empresa_id = p_empresa
      and m.user_id = auth.uid()
      and m.ativo
      and e.status_assinatura in ('teste', 'ativa', 'inadimplente')
  );
$$;

-- Usuário tem um destes papéis na empresa (com assinatura liberada)?
create or replace function app.tem_papel(p_empresa uuid, p_papeis public.papel_membro[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.membros m
    join public.empresas e on e.id = m.empresa_id
    where m.empresa_id = p_empresa
      and m.user_id = auth.uid()
      and m.ativo
      and m.papel = any (p_papeis)
      and e.status_assinatura in ('teste', 'ativa', 'inadimplente')
  );
$$;

create or replace function app.e_dono(p_empresa uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select app.tem_papel(p_empresa, array['dono']::public.papel_membro[]);
$$;

-- Usuário enxerga esta unidade? Dono e quem tem todas_unidades veem todas;
-- os demais só as unidades vinculadas em membro_unidades.
create or replace function app.ve_unidade(p_unidade uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.unidades u
    join public.membros m on m.empresa_id = u.empresa_id
    where u.id = p_unidade
      and m.user_id = auth.uid()
      and m.ativo
      and (
        m.papel = 'dono'
        or m.todas_unidades
        or exists (
          select 1 from public.membro_unidades mu
          where mu.membro_id = m.id and mu.unidade_id = p_unidade
        )
      )
  );
$$;

-- Usuário divide alguma empresa com outro usuário? (para ler perfis de colegas)
create or replace function app.colega(p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.membros a
    join public.membros b on b.empresa_id = a.empresa_id
    where a.user_id = auth.uid() and a.ativo
      and b.user_id = p_user
  );
$$;

-- Recurso do plano liberado para a empresa? (usado pelo front e pelas próximas etapas)
create or replace function app.tem_recurso(p_empresa uuid, p_recurso text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((p.recursos ->> p_recurso)::boolean, false)
  from public.empresas e join public.planos p on p.id = e.plano_id
  where e.id = p_empresa;
$$;

-- ---------------------------------------------------------------------
-- Perfil automático para cada novo usuário do Supabase Auth
-- ---------------------------------------------------------------------
create or replace function app.criar_perfil_novo_usuario()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.perfis (id, nome, email)
  values (new.id, nullif(trim(new.raw_user_meta_data ->> 'nome'), ''), lower(new.email))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger tg_auth_novo_usuario
  after insert on auth.users
  for each row execute function app.criar_perfil_novo_usuario();

-- ---------------------------------------------------------------------
-- Limites do plano (unidades, profissionais, usuários)
-- ---------------------------------------------------------------------
create or replace function app.checar_limite_plano()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_plano   public.planos;
  v_limite  int;
  v_total   int;
  v_rotulo  text;
begin
  -- Só conta quando o registro está (ou fica) ativo.
  if not new.ativo then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.ativo then
    return new;
  end if;

  select p.* into v_plano
  from public.empresas e join public.planos p on p.id = e.plano_id
  where e.id = new.empresa_id;

  if tg_table_name = 'unidades' then
    v_limite := v_plano.limite_unidades;
    v_rotulo := 'unidades';
    select count(*) into v_total from public.unidades
      where empresa_id = new.empresa_id and ativo and id <> new.id;
  elsif tg_table_name = 'profissionais' then
    v_limite := v_plano.limite_profissionais;
    v_rotulo := 'profissionais';
    select count(*) into v_total from public.profissionais
      where empresa_id = new.empresa_id and ativo and id <> new.id;
  elsif tg_table_name = 'membros' then
    v_limite := v_plano.limite_usuarios;
    v_rotulo := 'usuários';
    select count(*) into v_total from public.membros
      where empresa_id = new.empresa_id and ativo and id <> new.id;
  end if;

  if v_limite is not null and v_total >= v_limite then
    raise exception 'O plano % permite até % %. Faça upgrade para cadastrar mais.',
      v_plano.nome, v_limite, v_rotulo
      using errcode = 'P0001', hint = 'limite_plano';
  end if;
  return new;
end;
$$;

create trigger tg_limite_unidades      before insert or update of ativo on public.unidades      for each row execute function app.checar_limite_plano();
create trigger tg_limite_profissionais before insert or update of ativo on public.profissionais for each row execute function app.checar_limite_plano();
create trigger tg_limite_membros       before insert or update of ativo on public.membros       for each row execute function app.checar_limite_plano();

-- ---------------------------------------------------------------------
-- A empresa nunca fica sem dono ativo
-- ---------------------------------------------------------------------
create or replace function app.proteger_ultimo_dono()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.papel = 'dono' and old.ativo
     and (tg_op = 'DELETE' or new.papel <> 'dono' or not new.ativo)
     and not exists (
       select 1 from public.membros
       where empresa_id = old.empresa_id and papel = 'dono' and ativo and id <> old.id
     )
     -- permite a remoção em cascata quando a própria empresa é apagada
     and exists (select 1 from public.empresas where id = old.empresa_id)
  then
    raise exception 'A empresa precisa ter pelo menos um dono ativo.'
      using errcode = 'P0001', hint = 'ultimo_dono';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger tg_proteger_ultimo_dono
  before update or delete on public.membros
  for each row execute function app.proteger_ultimo_dono();

-- ---------------------------------------------------------------------
-- Permissões de execução das funções auxiliares
-- ---------------------------------------------------------------------
grant usage on schema app to anon, authenticated, service_role;
revoke all on all functions in schema app from public;
grant execute on function
  app.is_super_admin(), app.vinculado(uuid), app.e_membro(uuid),
  app.tem_papel(uuid, public.papel_membro[]), app.e_dono(uuid),
  app.ve_unidade(uuid), app.colega(uuid), app.tem_recurso(uuid, text)
to authenticated, service_role;
-- a política de leitura de planos (visitante na página de cadastro) usa is_super_admin
grant execute on function app.is_super_admin() to anon;

-- >>> migrations/20261124000300_rls.sql
-- =====================================================================
-- Sistem Clinic · Etapa 1 · Row Level Security
-- Regra geral: ler = membro da empresa; gravar = dono da empresa;
-- super-admin lê e grava tudo. Empresas bloqueadas/canceladas ficam
-- invisíveis para os próprios usuários (exceto o registro da empresa).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Privilégios de tabela: nada para anon, exceto ler planos.
-- ---------------------------------------------------------------------
revoke all on all tables in schema public from anon;
grant select on public.planos to anon;

grant select, insert, update, delete on all tables in schema public to authenticated;

-- Colunas sensíveis de empresas: só funções (RPC) alteram plano e status.
revoke insert, update, delete on public.empresas from authenticated;
grant update (nome, documento, segmento, telefone, logo_url, cor_marca) on public.empresas to authenticated;

-- membros: ninguém insere direto (só via aceitar_convite / criar_empresa);
-- não se troca usuário nem empresa de um vínculo.
revoke insert, update on public.membros from authenticated;
grant update (papel, todas_unidades, ativo) on public.membros to authenticated;

-- convites: criados por convidar_usuario(), aceitos por aceitar_convite().
revoke insert, update on public.convites from authenticated;

-- perfis: criados pelo gatilho; o usuário só edita os próprios dados.
revoke insert, delete, update on public.perfis from authenticated;
grant update (nome, telefone, avatar_url) on public.perfis to authenticated;

-- tabelas da plataforma
revoke all on public.admins_plataforma from authenticated;
revoke insert, update, delete on public.auditoria from authenticated;

-- ---------------------------------------------------------------------
-- Liga o RLS em todas as tabelas
-- ---------------------------------------------------------------------
alter table public.planos                enable row level security;
alter table public.empresas              enable row level security;
alter table public.admins_plataforma     enable row level security;
alter table public.auditoria             enable row level security;
alter table public.perfis                enable row level security;
alter table public.membros               enable row level security;
alter table public.membro_unidades       enable row level security;
alter table public.convites              enable row level security;
alter table public.unidades              enable row level security;
alter table public.horarios_unidade      enable row level security;
alter table public.profissionais         enable row level security;
alter table public.profissional_unidades enable row level security;
alter table public.jornadas              enable row level security;
alter table public.servicos              enable row level security;
alter table public.servico_profissionais enable row level security;

-- ---------------------------------------------------------------------
-- planos: todos leem os ativos; super-admin gerencia
-- ---------------------------------------------------------------------
create policy planos_ler on public.planos for select to anon, authenticated
  using (ativo or (select app.is_super_admin()));
create policy planos_admin on public.planos for all to authenticated
  using ((select app.is_super_admin())) with check ((select app.is_super_admin()));

-- ---------------------------------------------------------------------
-- empresas
-- ---------------------------------------------------------------------
create policy empresas_ler on public.empresas for select to authenticated
  using ((select app.is_super_admin()) or app.vinculado(id));
create policy empresas_editar on public.empresas for update to authenticated
  using ((select app.is_super_admin()) or app.e_dono(id))
  with check ((select app.is_super_admin()) or app.e_dono(id));

-- admins_plataforma: sem políticas = ninguém acessa pela API.

-- auditoria: só super-admin lê
create policy auditoria_ler on public.auditoria for select to authenticated
  using ((select app.is_super_admin()));

-- ---------------------------------------------------------------------
-- perfis
-- ---------------------------------------------------------------------
create policy perfis_ler on public.perfis for select to authenticated
  using (id = (select auth.uid()) or (select app.is_super_admin()) or app.colega(id));
create policy perfis_editar on public.perfis for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- ---------------------------------------------------------------------
-- membros e membro_unidades
-- ---------------------------------------------------------------------
create policy membros_ler on public.membros for select to authenticated
  using (
    user_id = (select auth.uid())          -- o próprio vínculo (lista "minhas empresas")
    or (select app.is_super_admin())
    or app.e_membro(empresa_id)
  );
create policy membros_editar on public.membros for update to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id))
  with check ((select app.is_super_admin()) or app.e_dono(empresa_id));
create policy membros_remover on public.membros for delete to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id));

create policy membro_unidades_ler on public.membro_unidades for select to authenticated
  using ((select app.is_super_admin()) or app.e_membro(empresa_id));
create policy membro_unidades_gravar on public.membro_unidades for all to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id))
  with check ((select app.is_super_admin()) or app.e_dono(empresa_id));

-- ---------------------------------------------------------------------
-- convites: só o dono vê e cancela
-- ---------------------------------------------------------------------
create policy convites_ler on public.convites for select to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id));
create policy convites_remover on public.convites for delete to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id));

-- ---------------------------------------------------------------------
-- unidades e horários: leitura filtrada pelas unidades do usuário
-- ---------------------------------------------------------------------
create policy unidades_ler on public.unidades for select to authenticated
  using ((select app.is_super_admin()) or (app.e_membro(empresa_id) and app.ve_unidade(id)));
create policy unidades_gravar on public.unidades for all to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id))
  with check ((select app.is_super_admin()) or app.e_dono(empresa_id));

create policy horarios_ler on public.horarios_unidade for select to authenticated
  using ((select app.is_super_admin()) or (app.e_membro(empresa_id) and app.ve_unidade(unidade_id)));
create policy horarios_gravar on public.horarios_unidade for all to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id))
  with check ((select app.is_super_admin()) or app.e_dono(empresa_id));

-- ---------------------------------------------------------------------
-- profissionais, vínculos e jornadas: todos da empresa leem, dono grava
-- ---------------------------------------------------------------------
create policy profissionais_ler on public.profissionais for select to authenticated
  using ((select app.is_super_admin()) or app.e_membro(empresa_id));
create policy profissionais_gravar on public.profissionais for all to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id))
  with check ((select app.is_super_admin()) or app.e_dono(empresa_id));

create policy prof_unidades_ler on public.profissional_unidades for select to authenticated
  using ((select app.is_super_admin()) or app.e_membro(empresa_id));
create policy prof_unidades_gravar on public.profissional_unidades for all to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id))
  with check ((select app.is_super_admin()) or app.e_dono(empresa_id));

create policy jornadas_ler on public.jornadas for select to authenticated
  using ((select app.is_super_admin()) or app.e_membro(empresa_id));
create policy jornadas_gravar on public.jornadas for all to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id))
  with check ((select app.is_super_admin()) or app.e_dono(empresa_id));

-- ---------------------------------------------------------------------
-- serviços
-- ---------------------------------------------------------------------
create policy servicos_ler on public.servicos for select to authenticated
  using ((select app.is_super_admin()) or app.e_membro(empresa_id));
create policy servicos_gravar on public.servicos for all to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id))
  with check ((select app.is_super_admin()) or app.e_dono(empresa_id));

create policy serv_prof_ler on public.servico_profissionais for select to authenticated
  using ((select app.is_super_admin()) or app.e_membro(empresa_id));
create policy serv_prof_gravar on public.servico_profissionais for all to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id))
  with check ((select app.is_super_admin()) or app.e_dono(empresa_id));

-- >>> migrations/20261124000400_rpc.sql
-- =====================================================================
-- Sistem Clinic · Etapa 1 · Funções chamadas pelo front (RPC)
-- Ações sensíveis passam por aqui; o front nunca grava direto em
-- empresas (plano/status), membros (inserção) ou convites.
-- =====================================================================

-- ---------------------------------------------------------------------
-- criar_empresa: cadastro self-service (teste de 7 dias).
-- O usuário logado vira dono. Limite de 3 empresas criadas por usuário.
-- ---------------------------------------------------------------------
create or replace function public.criar_empresa(
  p_nome          text,
  p_segmento      public.segmento_empresa,
  p_plano_codigo  text,
  p_nome_unidade  text default null,
  p_documento     text default null,
  p_telefone      text default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid      uuid := auth.uid();
  v_plano    uuid;
  v_empresa  uuid;
  v_unidade  uuid;
begin
  if v_uid is null then
    raise exception 'Faça login para criar a empresa.' using errcode = '42501';
  end if;

  if not app.is_super_admin() and (
    select count(*) from public.empresas where criado_por = v_uid
  ) >= 3 then
    raise exception 'Limite de empresas criadas por este usuário atingido. Fale com o suporte.'
      using errcode = 'P0001';
  end if;

  select id into v_plano from public.planos where codigo = p_plano_codigo and ativo;
  if v_plano is null then
    raise exception 'Plano inválido.' using errcode = 'P0001';
  end if;

  insert into public.empresas (nome, segmento, plano_id, documento, telefone, status_assinatura, teste_ate, criado_por)
  values (trim(p_nome), p_segmento, v_plano, nullif(trim(p_documento), ''), nullif(trim(p_telefone), ''),
          'teste', now() + interval '7 days', v_uid)
  returning id into v_empresa;

  insert into public.membros (empresa_id, user_id, papel, todas_unidades)
  values (v_empresa, v_uid, 'dono', true);

  insert into public.unidades (empresa_id, nome, telefone)
  values (v_empresa, coalesce(nullif(trim(p_nome_unidade), ''), 'Unidade principal'), nullif(trim(p_telefone), ''))
  returning id into v_unidade;

  -- horário padrão: segunda a sexta 08h–18h, sábado 08h–12h
  insert into public.horarios_unidade (empresa_id, unidade_id, dia_semana, abre, fecha)
  select v_empresa, v_unidade, d, '08:00', case when d = 6 then '12:00'::time else '18:00'::time end
  from generate_series(1, 6) d;

  insert into public.auditoria (empresa_id, user_id, acao, tabela, registro_id, dados)
  values (v_empresa, v_uid, 'empresa_criada', 'empresas', v_empresa,
          jsonb_build_object('plano', p_plano_codigo, 'origem', 'self_service'));

  return v_empresa;
end;
$$;

-- ---------------------------------------------------------------------
-- convidar_usuario: o dono gera um convite (link) para recepção,
-- profissional ou outro dono. Devolve o token do link.
-- ---------------------------------------------------------------------
create or replace function public.convidar_usuario(
  p_empresa          uuid,
  p_email            text,
  p_papel            public.papel_membro,
  p_unidade_ids      uuid[] default '{}',
  p_todas_unidades   boolean default false,
  p_profissional_id  uuid default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_email   text := lower(trim(p_email));
  v_token   uuid;
  v_limite  int;
  v_ocupado int;
begin
  if not (app.e_dono(p_empresa) or app.is_super_admin()) then
    raise exception 'Só o dono pode convidar usuários.' using errcode = '42501';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'E-mail inválido.' using errcode = 'P0001';
  end if;

  -- unidades informadas precisam ser da empresa
  if exists (
    select 1 from unnest(coalesce(p_unidade_ids, '{}')) uid
    where not exists (select 1 from public.unidades u where u.id = uid and u.empresa_id = p_empresa)
  ) then
    raise exception 'Unidade inválida.' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.membros m join public.perfis p on p.id = m.user_id
    where m.empresa_id = p_empresa and m.ativo and p.email = v_email
  ) then
    raise exception 'Este e-mail já faz parte da equipe.' using errcode = 'P0001';
  end if;

  -- limite de usuários do plano conta membros ativos + convites pendentes
  select p.limite_usuarios into v_limite
  from public.empresas e join public.planos p on p.id = e.plano_id where e.id = p_empresa;
  select (select count(*) from public.membros where empresa_id = p_empresa and ativo)
       + (select count(*) from public.convites where empresa_id = p_empresa and aceito_em is null
            and expira_em > now() and email <> v_email)
    into v_ocupado;
  if v_limite is not null and v_ocupado >= v_limite then
    raise exception 'O plano permite até % usuários. Faça upgrade para convidar mais.', v_limite
      using errcode = 'P0001', hint = 'limite_plano';
  end if;

  -- um convite pendente por e-mail e empresa: substitui o anterior
  delete from public.convites where empresa_id = p_empresa and email = v_email and aceito_em is null;

  insert into public.convites (empresa_id, email, papel, unidade_ids, todas_unidades, profissional_id, criado_por)
  values (p_empresa, v_email, p_papel, coalesce(p_unidade_ids, '{}'), p_todas_unidades, p_profissional_id, auth.uid())
  returning token into v_token;

  return v_token;
end;
$$;

-- ---------------------------------------------------------------------
-- ver_convite: dados mínimos para a tela "Aceitar convite" (sem login)
-- ---------------------------------------------------------------------
create or replace function public.ver_convite(p_token uuid)
returns table (empresa_nome text, email text, papel public.papel_membro, expirado boolean, aceito boolean)
language sql stable security definer set search_path = '' as $$
  select e.nome, c.email, c.papel, c.expira_em < now(), c.aceito_em is not null
  from public.convites c join public.empresas e on e.id = c.empresa_id
  where c.token = p_token;
$$;

-- ---------------------------------------------------------------------
-- aceitar_convite: o usuário logado (com o mesmo e-mail) entra na empresa
-- ---------------------------------------------------------------------
create or replace function public.aceitar_convite(p_token uuid)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid     uuid := auth.uid();
  v_email   text;
  v_conv    public.convites;
  v_membro  uuid;
begin
  if v_uid is null then
    raise exception 'Faça login para aceitar o convite.' using errcode = '42501';
  end if;
  select lower(email) into v_email from auth.users where id = v_uid;

  select * into v_conv from public.convites where token = p_token for update;
  if v_conv.id is null then
    raise exception 'Convite não encontrado.' using errcode = 'P0001';
  end if;
  if v_conv.aceito_em is not null then
    raise exception 'Este convite já foi usado.' using errcode = 'P0001';
  end if;
  if v_conv.expira_em < now() then
    raise exception 'Este convite expirou. Peça um novo ao responsável.' using errcode = 'P0001';
  end if;
  if v_conv.email <> v_email then
    raise exception 'Este convite foi enviado para %. Entre com esse e-mail.', v_conv.email
      using errcode = 'P0001';
  end if;

  insert into public.membros (empresa_id, user_id, papel, todas_unidades, ativo)
  values (v_conv.empresa_id, v_uid, v_conv.papel, v_conv.todas_unidades, true)
  on conflict (empresa_id, user_id)
    do update set papel = excluded.papel, todas_unidades = excluded.todas_unidades, ativo = true
  returning id into v_membro;

  delete from public.membro_unidades where membro_id = v_membro;
  insert into public.membro_unidades (empresa_id, membro_id, unidade_id)
  select v_conv.empresa_id, v_membro, u from unnest(v_conv.unidade_ids) u
  on conflict do nothing;

  if v_conv.profissional_id is not null then
    update public.profissionais set membro_id = v_membro
    where id = v_conv.profissional_id and empresa_id = v_conv.empresa_id and membro_id is null;
  end if;

  update public.convites set aceito_em = now(), aceito_por = v_uid where id = v_conv.id;
  return v_conv.empresa_id;
end;
$$;

-- ---------------------------------------------------------------------
-- definir_unidades_membro: dono troca as unidades de um usuário
-- ---------------------------------------------------------------------
create or replace function public.definir_unidades_membro(p_membro uuid, p_unidade_ids uuid[])
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_empresa uuid;
begin
  select empresa_id into v_empresa from public.membros where id = p_membro;
  if v_empresa is null or not (app.e_dono(v_empresa) or app.is_super_admin()) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  delete from public.membro_unidades where membro_id = p_membro;
  insert into public.membro_unidades (empresa_id, membro_id, unidade_id)
  select v_empresa, p_membro, u.id from public.unidades u
  where u.empresa_id = v_empresa and u.id = any (p_unidade_ids);
end;
$$;

-- ---------------------------------------------------------------------
-- Super-admin: status da assinatura e plano
-- ---------------------------------------------------------------------
create or replace function public.definir_status_assinatura(
  p_empresa  uuid,
  p_status   public.status_assinatura,
  p_teste_ate timestamptz default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_antigo public.status_assinatura;
begin
  if not app.is_super_admin() then
    raise exception 'Apenas o administrador da plataforma.' using errcode = '42501';
  end if;
  select status_assinatura into v_antigo from public.empresas where id = p_empresa for update;
  if not found then
    raise exception 'Empresa não encontrada.' using errcode = 'P0001';
  end if;

  update public.empresas set
    status_assinatura = p_status,
    bloqueada_em = case when p_status in ('bloqueada', 'cancelada') then now() else null end,
    teste_ate = coalesce(p_teste_ate, teste_ate)
  where id = p_empresa;

  insert into public.auditoria (empresa_id, user_id, acao, tabela, registro_id, dados)
  values (p_empresa, auth.uid(), 'status_assinatura', 'empresas', p_empresa,
          jsonb_build_object('de', v_antigo, 'para', p_status, 'teste_ate', p_teste_ate));
end;
$$;

create or replace function public.definir_plano_empresa(p_empresa uuid, p_plano_codigo text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_plano uuid;
begin
  if not app.is_super_admin() then
    raise exception 'Apenas o administrador da plataforma.' using errcode = '42501';
  end if;
  select id into v_plano from public.planos where codigo = p_plano_codigo;
  if v_plano is null then
    raise exception 'Plano inválido.' using errcode = 'P0001';
  end if;
  update public.empresas set plano_id = v_plano where id = p_empresa;
  insert into public.auditoria (empresa_id, user_id, acao, tabela, registro_id, dados)
  values (p_empresa, auth.uid(), 'plano_alterado', 'empresas', p_empresa,
          jsonb_build_object('plano', p_plano_codigo));
end;
$$;

-- Lista de empresas com números para o painel do super-admin
create or replace function public.admin_listar_empresas()
returns table (
  id uuid, nome text, segmento public.segmento_empresa, plano_codigo text, plano_nome text,
  preco_mensal numeric, status_assinatura public.status_assinatura, teste_ate timestamptz,
  criado_em timestamptz, dono_email text, unidades bigint, profissionais bigint, usuarios bigint
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_super_admin() then
    raise exception 'Apenas o administrador da plataforma.' using errcode = '42501';
  end if;
  return query
  select e.id, e.nome, e.segmento, p.codigo, p.nome, p.preco_mensal, e.status_assinatura,
         e.teste_ate, e.criado_em,
         (select pf.email from public.membros m join public.perfis pf on pf.id = m.user_id
           where m.empresa_id = e.id and m.papel = 'dono' and m.ativo order by m.criado_em limit 1),
         (select count(*) from public.unidades u where u.empresa_id = e.id and u.ativo),
         (select count(*) from public.profissionais pr where pr.empresa_id = e.id and pr.ativo),
         (select count(*) from public.membros m where m.empresa_id = e.id and m.ativo)
  from public.empresas e join public.planos p on p.id = e.plano_id
  order by e.criado_em desc;
end;
$$;

-- Front pergunta se o usuário logado é super-admin
create or replace function public.sou_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select app.is_super_admin();
$$;

-- ---------------------------------------------------------------------
-- Permissões das RPCs
-- ---------------------------------------------------------------------
revoke execute on function
  public.criar_empresa(text, public.segmento_empresa, text, text, text, text),
  public.convidar_usuario(uuid, text, public.papel_membro, uuid[], boolean, uuid),
  public.ver_convite(uuid),
  public.aceitar_convite(uuid),
  public.definir_unidades_membro(uuid, uuid[]),
  public.definir_status_assinatura(uuid, public.status_assinatura, timestamptz),
  public.definir_plano_empresa(uuid, text),
  public.admin_listar_empresas(),
  public.sou_super_admin()
from public, anon;

grant execute on function
  public.criar_empresa(text, public.segmento_empresa, text, text, text, text),
  public.convidar_usuario(uuid, text, public.papel_membro, uuid[], boolean, uuid),
  public.ver_convite(uuid),
  public.aceitar_convite(uuid),
  public.definir_unidades_membro(uuid, uuid[]),
  public.definir_status_assinatura(uuid, public.status_assinatura, timestamptz),
  public.definir_plano_empresa(uuid, text),
  public.admin_listar_empresas(),
  public.sou_super_admin()
to authenticated;

grant execute on function public.ver_convite(uuid) to anon;

-- >>> migrations/20261124000500_planos.sql
-- =====================================================================
-- Sistem Clinic · Planos iniciais
-- Para mudar preço, limite ou recurso depois, basta editar a linha
-- na tabela planos (Table Editor do Supabase). null = ilimitado.
-- =====================================================================
insert into public.planos
  (codigo, nome, descricao, preco_mensal, limite_unidades, limite_profissionais, limite_usuarios, ordem, recursos)
values
  ('essencial', 'Essencial', 'Agenda, clientes e lembretes automáticos no WhatsApp.',
   80.00, 1, 3, 4, 1,
   '{"agenda": true, "clientes": true, "lembretes_whatsapp": true, "textos_editaveis": true,
     "financeiro": true, "avaliacao_google": false, "campanhas": false,
     "relatorios_completos": false, "marcacao_whatsapp": false, "marcacao_ia": false}'),
  ('profissional', 'Profissional', 'Tudo do Essencial + avaliações no Google, campanhas e relatórios.',
   110.00, 2, 8, 12, 2,
   '{"agenda": true, "clientes": true, "lembretes_whatsapp": true, "textos_editaveis": true,
     "financeiro": true, "avaliacao_google": true, "campanhas": true,
     "relatorios_completos": true, "marcacao_whatsapp": false, "marcacao_ia": false}'),
  ('premium', 'Premium', 'Tudo do Profissional + marcação automática pelo WhatsApp com IA.',
   190.00, 5, null, null, 3,
   '{"agenda": true, "clientes": true, "lembretes_whatsapp": true, "textos_editaveis": true,
     "financeiro": true, "avaliacao_google": true, "campanhas": true,
     "relatorios_completos": true, "marcacao_whatsapp": true, "marcacao_ia": true}')
on conflict (codigo) do nothing;

-- >>> migrations/20261124000600_admin.sql
-- =====================================================================
-- Sistem Clinic · Painel do super-admin (abas)
-- Criar empresa pelo admin, resumo da plataforma e histórico.
-- =====================================================================

-- ---------------------------------------------------------------------
-- admin_criar_empresa: você cadastra a empresa e gera o convite do dono.
-- Devolve o id da empresa e o token do convite (null se sem e-mail).
-- ---------------------------------------------------------------------
create or replace function public.admin_criar_empresa(
  p_nome          text,
  p_segmento      public.segmento_empresa,
  p_plano_codigo  text,
  p_email_dono    text default null,
  p_nome_unidade  text default null,
  p_telefone      text default null,
  p_documento     text default null,
  p_status        public.status_assinatura default 'teste',
  p_dias_teste    int default 7
) returns table (empresa_id uuid, token uuid)
language plpgsql security definer set search_path = '' as $$
declare
  v_plano    uuid;
  v_empresa  uuid;
  v_unidade  uuid;
  v_token    uuid;
  v_email    text := nullif(lower(trim(p_email_dono)), '');
begin
  if not app.is_super_admin() then
    raise exception 'Apenas o administrador da plataforma.' using errcode = '42501';
  end if;
  select id into v_plano from public.planos where codigo = p_plano_codigo;
  if v_plano is null then
    raise exception 'Plano inválido.' using errcode = 'P0001';
  end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'E-mail do dono inválido.' using errcode = 'P0001';
  end if;

  insert into public.empresas (nome, segmento, plano_id, documento, telefone, status_assinatura, teste_ate, criado_por)
  values (trim(p_nome), p_segmento, v_plano, nullif(trim(p_documento), ''), nullif(trim(p_telefone), ''),
          p_status,
          case when p_status = 'teste' then now() + make_interval(days => greatest(coalesce(p_dias_teste, 7), 1)) end,
          auth.uid())
  returning id into v_empresa;

  insert into public.unidades (empresa_id, nome, telefone)
  values (v_empresa, coalesce(nullif(trim(p_nome_unidade), ''), 'Unidade principal'), nullif(trim(p_telefone), ''))
  returning id into v_unidade;

  insert into public.horarios_unidade (empresa_id, unidade_id, dia_semana, abre, fecha)
  select v_empresa, v_unidade, d, '08:00', case when d = 6 then '12:00'::time else '18:00'::time end
  from generate_series(1, 6) d;

  if v_email is not null then
    insert into public.convites (empresa_id, email, papel, todas_unidades, criado_por, expira_em)
    values (v_empresa, v_email, 'dono', true, auth.uid(), now() + interval '30 days')
    returning convites.token into v_token;
  end if;

  insert into public.auditoria (empresa_id, user_id, acao, tabela, registro_id, dados)
  values (v_empresa, auth.uid(), 'empresa_criada', 'empresas', v_empresa,
          jsonb_build_object('plano', p_plano_codigo, 'origem', 'admin', 'email_dono', v_email));

  return query select v_empresa, v_token;
end;
$$;

-- ---------------------------------------------------------------------
-- admin_convite_dono: gera (ou renova) o link de convite do dono
-- ---------------------------------------------------------------------
create or replace function public.admin_convite_dono(p_empresa uuid, p_email text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(trim(p_email));
  v_token uuid;
begin
  if not app.is_super_admin() then
    raise exception 'Apenas o administrador da plataforma.' using errcode = '42501';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'E-mail inválido.' using errcode = 'P0001';
  end if;
  delete from public.convites where empresa_id = p_empresa and email = v_email and aceito_em is null;
  insert into public.convites (empresa_id, email, papel, todas_unidades, criado_por, expira_em)
  values (p_empresa, v_email, 'dono', true, auth.uid(), now() + interval '30 days')
  returning token into v_token;
  return v_token;
end;
$$;

-- ---------------------------------------------------------------------
-- admin_listar_empresas: agora com documento, telefone e convite pendente
-- ---------------------------------------------------------------------
drop function if exists public.admin_listar_empresas();
create or replace function public.admin_listar_empresas()
returns table (
  id uuid, nome text, segmento public.segmento_empresa, documento text, telefone text,
  plano_codigo text, plano_nome text, preco_mensal numeric,
  status_assinatura public.status_assinatura, teste_ate timestamptz, bloqueada_em timestamptz,
  criado_em timestamptz, dono_email text, convite_pendente text,
  unidades bigint, profissionais bigint, usuarios bigint, servicos bigint
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_super_admin() then
    raise exception 'Apenas o administrador da plataforma.' using errcode = '42501';
  end if;
  return query
  select e.id, e.nome, e.segmento, e.documento, e.telefone, p.codigo, p.nome, p.preco_mensal,
         e.status_assinatura, e.teste_ate, e.bloqueada_em, e.criado_em,
         (select pf.email from public.membros m join public.perfis pf on pf.id = m.user_id
           where m.empresa_id = e.id and m.papel = 'dono' and m.ativo order by m.criado_em limit 1),
         (select c.email from public.convites c
           where c.empresa_id = e.id and c.papel = 'dono' and c.aceito_em is null and c.expira_em > now()
           order by c.criado_em desc limit 1),
         (select count(*) from public.unidades u where u.empresa_id = e.id and u.ativo),
         (select count(*) from public.profissionais pr where pr.empresa_id = e.id and pr.ativo),
         (select count(*) from public.membros m where m.empresa_id = e.id and m.ativo),
         (select count(*) from public.servicos sv where sv.empresa_id = e.id and sv.ativo)
  from public.empresas e join public.planos p on p.id = e.plano_id
  order by e.criado_em desc;
end;
$$;

-- ---------------------------------------------------------------------
-- admin_historico: últimas ações registradas, com nome da empresa
-- ---------------------------------------------------------------------
create or replace function public.admin_historico(p_limite int default 100)
returns table (id bigint, criado_em timestamptz, acao text, empresa_id uuid, empresa_nome text, usuario_email text, dados jsonb)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_super_admin() then
    raise exception 'Apenas o administrador da plataforma.' using errcode = '42501';
  end if;
  return query
  select a.id, a.criado_em, a.acao, a.empresa_id, e.nome, pf.email, a.dados
  from public.auditoria a
  left join public.empresas e on e.id = a.empresa_id
  left join public.perfis pf on pf.id = a.user_id
  order by a.criado_em desc
  limit least(greatest(p_limite, 1), 500);
end;
$$;

-- ---------------------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------------------
revoke execute on function
  public.admin_criar_empresa(text, public.segmento_empresa, text, text, text, text, text, public.status_assinatura, int),
  public.admin_convite_dono(uuid, text),
  public.admin_listar_empresas(),
  public.admin_historico(int)
from public, anon;
grant execute on function
  public.admin_criar_empresa(text, public.segmento_empresa, text, text, text, text, text, public.status_assinatura, int),
  public.admin_convite_dono(uuid, text),
  public.admin_listar_empresas(),
  public.admin_historico(int)
to authenticated;

-- >>> migrations/20261124000700_atendimento.sql
-- =====================================================================
-- Sistem Clinic · Etapa 2 · Pacientes, agenda, bloqueios e financeiro
-- =====================================================================

create schema if not exists extensions;
create extension if not exists btree_gist with schema extensions;

create type public.status_agendamento as enum ('agendado', 'confirmado', 'atendido', 'faltou', 'cancelado');
create type public.origem_agendamento as enum ('painel', 'whatsapp', 'online');
create type public.forma_pagamento as enum ('pix', 'dinheiro', 'cartao_credito', 'cartao_debito', 'convenio', 'outro');

-- ---------------------------------------------------------------------
-- Pacientes / clientes
-- ---------------------------------------------------------------------
create table public.clientes (
  id                uuid primary key default gen_random_uuid(),
  empresa_id        uuid not null references public.empresas(id) on delete cascade,
  nome              text not null check (length(trim(nome)) between 2 and 160),
  telefone          text,                         -- só dígitos, com DDI (5511999998888)
  email             text,
  data_nascimento   date,
  documento         text,
  genero            text,
  endereco          text,
  observacoes       text,
  origem            text,                         -- indicação, Instagram, Google...
  aceita_whatsapp   boolean not null default true,
  ultima_visita_em  timestamptz,
  ativo             boolean not null default true,
  criado_por        uuid references auth.users(id) on delete set null,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  unique (id, empresa_id)
);
create index on public.clientes (empresa_id, nome);
create unique index clientes_telefone_unico on public.clientes (empresa_id, telefone) where telefone is not null and ativo;
create index clientes_aniversario on public.clientes (empresa_id, extract(month from data_nascimento), extract(day from data_nascimento));
create trigger tg_clientes_atualizado before update on public.clientes for each row execute function app.tocar_atualizado_em();

-- telefone sempre só com dígitos e com 55 na frente (formato do WhatsApp)
create or replace function app.normalizar_telefone(p text)
returns text language sql immutable as $$
  select case
    when p is null or regexp_replace(p, '\D', '', 'g') = '' then null
    when length(regexp_replace(p, '\D', '', 'g')) <= 11 then '55' || regexp_replace(p, '\D', '', 'g')
    else regexp_replace(p, '\D', '', 'g')
  end;
$$;

create or replace function app.tg_cliente_normalizar()
returns trigger language plpgsql as $$
begin
  new.telefone := app.normalizar_telefone(new.telefone);
  new.email := nullif(lower(trim(new.email)), '');
  return new;
end;
$$;
create trigger tg_clientes_normalizar before insert or update on public.clientes
  for each row execute function app.tg_cliente_normalizar();

-- ---------------------------------------------------------------------
-- Agendamentos
-- ---------------------------------------------------------------------
create table public.agendamentos (
  id                        uuid primary key default gen_random_uuid(),
  empresa_id                uuid not null references public.empresas(id) on delete cascade,
  unidade_id                uuid not null,
  profissional_id           uuid not null,
  cliente_id                uuid not null,
  servico_id                uuid,
  inicio                    timestamptz not null,
  fim                       timestamptz not null,
  status                    public.status_agendamento not null default 'agendado',
  encaixe                   boolean not null default false,
  origem                    public.origem_agendamento not null default 'painel',
  valor                     numeric(10,2) check (valor >= 0),
  observacoes               text,
  criado_por                uuid references auth.users(id) on delete set null,
  confirmado_em             timestamptz,
  cancelado_em              timestamptz,
  motivo_cancelamento       text,
  -- controle dos envios automáticos de WhatsApp (Etapa 3)
  confirmacao_enviada_em    timestamptz,
  lembrete_enviado_em       timestamptz,
  pos_atendimento_enviado_em timestamptz,
  criado_em                 timestamptz not null default now(),
  atualizado_em             timestamptz not null default now(),
  check (fim > inicio),
  unique (id, empresa_id),
  foreign key (unidade_id, empresa_id)      references public.unidades(id, empresa_id),
  foreign key (profissional_id, empresa_id) references public.profissionais(id, empresa_id),
  foreign key (cliente_id, empresa_id)      references public.clientes(id, empresa_id),
  foreign key (servico_id, empresa_id)      references public.servicos(id, empresa_id),
  -- o mesmo profissional não pode ter dois horários sobrepostos (exceto encaixe)
  constraint agendamentos_sem_conflito exclude using gist (
    profissional_id with =,
    tstzrange(inicio, fim) with &&
  ) where (status in ('agendado', 'confirmado', 'atendido') and not encaixe)
);
create index on public.agendamentos (empresa_id, inicio);
create index on public.agendamentos (profissional_id, inicio);
create index on public.agendamentos (unidade_id, inicio);
create index on public.agendamentos (cliente_id, inicio desc);
create index agendamentos_pendentes_envio on public.agendamentos (inicio) where status in ('agendado', 'confirmado');
create trigger tg_agendamentos_atualizado before update on public.agendamentos for each row execute function app.tocar_atualizado_em();

create table public.historico_status (
  id              bigint generated always as identity primary key,
  empresa_id      uuid not null references public.empresas(id) on delete cascade,
  agendamento_id  uuid not null references public.agendamentos(id) on delete cascade,
  de              public.status_agendamento,
  para            public.status_agendamento not null,
  alterado_por    uuid,
  origem          text not null default 'painel',
  criado_em       timestamptz not null default now()
);
create index on public.historico_status (agendamento_id);

-- carimba datas e registra a troca de status
create or replace function app.tg_agendamento_status()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_origem text := coalesce(nullif(current_setting('app.origem', true), ''), 'painel');
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    if new.status = 'confirmado' and new.confirmado_em is null then new.confirmado_em := now(); end if;
    if new.status = 'cancelado' and new.cancelado_em is null then new.cancelado_em := now(); end if;
  end if;
  return new;
end;
$$;
create trigger tg_agendamentos_status before insert or update of status on public.agendamentos
  for each row execute function app.tg_agendamento_status();

create or replace function app.tg_agendamento_historico()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.historico_status (empresa_id, agendamento_id, de, para, alterado_por, origem)
    values (new.empresa_id, new.id, case when tg_op = 'UPDATE' then old.status end, new.status, auth.uid(),
            coalesce(nullif(current_setting('app.origem', true), ''), case when auth.uid() is null then 'sistema' else 'painel' end));
  end if;
  if new.status = 'atendido' then
    update public.clientes set ultima_visita_em = greatest(coalesce(ultima_visita_em, new.inicio), new.inicio)
    where id = new.cliente_id;
  end if;
  return null;
end;
$$;
create trigger tg_agendamentos_historico after insert or update of status on public.agendamentos
  for each row execute function app.tg_agendamento_historico();

-- ---------------------------------------------------------------------
-- Bloqueios de agenda (folga, feriado, reunião...)
-- ---------------------------------------------------------------------
create table public.bloqueios_agenda (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas(id) on delete cascade,
  unidade_id       uuid not null,
  profissional_id  uuid,                       -- vazio = unidade inteira
  inicio           timestamptz not null,
  fim              timestamptz not null,
  motivo           text,
  criado_por       uuid references auth.users(id) on delete set null,
  criado_em        timestamptz not null default now(),
  check (fim > inicio),
  foreign key (unidade_id, empresa_id)      references public.unidades(id, empresa_id) on delete cascade,
  foreign key (profissional_id, empresa_id) references public.profissionais(id, empresa_id) on delete cascade
);
create index on public.bloqueios_agenda (unidade_id, inicio);

-- ---------------------------------------------------------------------
-- Financeiro: recebimentos
-- ---------------------------------------------------------------------
create table public.pagamentos (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references public.empresas(id) on delete cascade,
  unidade_id       uuid not null,
  agendamento_id   uuid,
  cliente_id       uuid,
  profissional_id  uuid,
  valor            numeric(10,2) not null check (valor > 0),
  forma            public.forma_pagamento not null default 'pix',
  recebido_em      timestamptz not null default now(),
  descricao        text,
  registrado_por   uuid references auth.users(id) on delete set null,
  criado_em        timestamptz not null default now(),
  foreign key (unidade_id, empresa_id)      references public.unidades(id, empresa_id),
  foreign key (agendamento_id, empresa_id)  references public.agendamentos(id, empresa_id) on delete set null (agendamento_id),
  foreign key (cliente_id, empresa_id)      references public.clientes(id, empresa_id) on delete set null (cliente_id),
  foreign key (profissional_id, empresa_id) references public.profissionais(id, empresa_id) on delete set null (profissional_id)
);
create index on public.pagamentos (empresa_id, recebido_em);
create index on public.pagamentos (agendamento_id);

-- ---------------------------------------------------------------------
-- Funções auxiliares de acesso
-- ---------------------------------------------------------------------

-- id do profissional ligado ao login atual, na empresa
create or replace function app.meu_profissional(p_empresa uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select p.id from public.profissionais p
  join public.membros m on m.id = p.membro_id
  where p.empresa_id = p_empresa and m.user_id = auth.uid() and m.ativo
  limit 1;
$$;

-- chamada feita pelas Edge Functions com a service_role?
create or replace function app.e_servico()
returns boolean language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') = 'service_role';
$$;

-- o usuário enxerga este agendamento/registro? (dono: tudo; recepção: unidades dela; profissional: os seus)
create or replace function app.ve_atendimento(p_empresa uuid, p_unidade uuid, p_profissional uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select app.is_super_admin()
      or app.e_dono(p_empresa)
      or (app.tem_papel(p_empresa, array['recepcao']::public.papel_membro[]) and app.ve_unidade(p_unidade))
      or (p_profissional is not null and app.tem_papel(p_empresa, array['profissional']::public.papel_membro[])
          and p_profissional = app.meu_profissional(p_empresa));
$$;

-- pode criar/alterar agenda nesta unidade? (dono e recepção)
create or replace function app.opera_agenda(p_empresa uuid, p_unidade uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select app.is_super_admin()
      or app.e_dono(p_empresa)
      or (app.tem_papel(p_empresa, array['recepcao']::public.papel_membro[]) and app.ve_unidade(p_unidade));
$$;

-- profissional vê o paciente se já atendeu/vai atender
create or replace function app.ve_cliente(p_empresa uuid, p_cliente uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select app.is_super_admin()
      or app.tem_papel(p_empresa, array['dono', 'recepcao']::public.papel_membro[])
      or exists (
        select 1 from public.agendamentos a
        where a.cliente_id = p_cliente and a.profissional_id = app.meu_profissional(p_empresa)
      );
$$;

grant execute on function app.meu_profissional(uuid), app.e_servico(), app.ve_atendimento(uuid, uuid, uuid),
  app.opera_agenda(uuid, uuid), app.ve_cliente(uuid, uuid), app.normalizar_telefone(text)
to authenticated, service_role;

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
grant select, insert, update, delete on public.clientes, public.agendamentos, public.bloqueios_agenda, public.pagamentos to authenticated;
grant select on public.historico_status to authenticated;
revoke all on public.clientes, public.agendamentos, public.bloqueios_agenda, public.pagamentos, public.historico_status from anon;

alter table public.clientes         enable row level security;
alter table public.agendamentos     enable row level security;
alter table public.historico_status enable row level security;
alter table public.bloqueios_agenda enable row level security;
alter table public.pagamentos       enable row level security;

-- clientes
create policy clientes_ler on public.clientes for select to authenticated
  using (app.e_membro(empresa_id) and app.ve_cliente(empresa_id, id) or (select app.is_super_admin()));
create policy clientes_criar on public.clientes for insert to authenticated
  with check ((select app.is_super_admin()) or app.tem_papel(empresa_id, array['dono', 'recepcao']::public.papel_membro[]));
create policy clientes_editar on public.clientes for update to authenticated
  using ((select app.is_super_admin()) or app.tem_papel(empresa_id, array['dono', 'recepcao']::public.papel_membro[]))
  with check ((select app.is_super_admin()) or app.tem_papel(empresa_id, array['dono', 'recepcao']::public.papel_membro[]));
create policy clientes_remover on public.clientes for delete to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id));

-- agendamentos (profissional muda status pela função atualizar_status_agendamento)
create policy agendamentos_ler on public.agendamentos for select to authenticated
  using (app.e_membro(empresa_id) and app.ve_atendimento(empresa_id, unidade_id, profissional_id) or (select app.is_super_admin()));
create policy agendamentos_gravar on public.agendamentos for all to authenticated
  using ((app.e_membro(empresa_id) and app.opera_agenda(empresa_id, unidade_id)) or (select app.is_super_admin()))
  with check ((app.e_membro(empresa_id) and app.opera_agenda(empresa_id, unidade_id)) or (select app.is_super_admin()));

create policy historico_status_ler on public.historico_status for select to authenticated
  using ((select app.is_super_admin()) or exists (
    select 1 from public.agendamentos a where a.id = agendamento_id
  ));

-- bloqueios: todos da unidade veem; dono e recepção gravam
create policy bloqueios_ler on public.bloqueios_agenda for select to authenticated
  using ((select app.is_super_admin()) or (app.e_membro(empresa_id) and app.ve_unidade(unidade_id)));
create policy bloqueios_gravar on public.bloqueios_agenda for all to authenticated
  using ((app.e_membro(empresa_id) and app.opera_agenda(empresa_id, unidade_id)) or (select app.is_super_admin()))
  with check ((app.e_membro(empresa_id) and app.opera_agenda(empresa_id, unidade_id)) or (select app.is_super_admin()));

-- pagamentos
create policy pagamentos_ler on public.pagamentos for select to authenticated
  using (app.e_membro(empresa_id) and app.ve_atendimento(empresa_id, unidade_id, profissional_id) or (select app.is_super_admin()));
create policy pagamentos_gravar on public.pagamentos for all to authenticated
  using ((app.e_membro(empresa_id) and app.opera_agenda(empresa_id, unidade_id)) or (select app.is_super_admin()))
  with check ((app.e_membro(empresa_id) and app.opera_agenda(empresa_id, unidade_id)) or (select app.is_super_admin()));

-- ---------------------------------------------------------------------
-- RPC: status do agendamento (também usada pelo profissional)
-- ---------------------------------------------------------------------
create or replace function public.atualizar_status_agendamento(
  p_agendamento uuid,
  p_status      public.status_agendamento,
  p_motivo      text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v public.agendamentos;
begin
  select * into v from public.agendamentos where id = p_agendamento for update;
  if v.id is null or not app.e_membro(v.empresa_id) and not app.is_super_admin() then
    raise exception 'Agendamento não encontrado.' using errcode = 'P0001';
  end if;
  if not (app.opera_agenda(v.empresa_id, v.unidade_id)
          or (p_status in ('atendido', 'faltou') and v.profissional_id = app.meu_profissional(v.empresa_id))) then
    raise exception 'Sem permissão para alterar este agendamento.' using errcode = '42501';
  end if;
  update public.agendamentos
     set status = p_status,
         motivo_cancelamento = case when p_status = 'cancelado' then coalesce(p_motivo, motivo_cancelamento) else motivo_cancelamento end
   where id = p_agendamento;
end;
$$;

-- ---------------------------------------------------------------------
-- RPC: horários livres de um profissional num dia (agenda e WhatsApp)
-- Considera jornada, agendamentos, bloqueios, duração do serviço e
-- horário já passado. Passo de 15 minutos.
-- ---------------------------------------------------------------------
create or replace function public.horarios_livres(
  p_unidade      uuid,
  p_profissional uuid,
  p_servico      uuid,
  p_data         date,
  p_passo_min    int default 15
) returns table (inicio timestamptz, fim timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_empresa  uuid;
  v_fuso     text;
  v_duracao  int;
begin
  select u.empresa_id, u.fuso_horario into v_empresa, v_fuso from public.unidades u where u.id = p_unidade and u.ativo;
  if v_empresa is null then return; end if;
  if not (app.e_servico() or app.is_super_admin() or app.e_membro(v_empresa)) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;

  select coalesce(sp.duracao_propria, s.duracao_min) + s.intervalo_apos_min into v_duracao
  from public.servicos s
  left join public.servico_profissionais sp on sp.servico_id = s.id and sp.profissional_id = p_profissional
  where s.id = p_servico and s.empresa_id = v_empresa;
  v_duracao := coalesce(v_duracao, 30);

  return query
  with faixas as (
    select (p_data + j.inicio) at time zone v_fuso as ini, (p_data + j.fim) at time zone v_fuso as fim_j
    from public.jornadas j
    where j.profissional_id = p_profissional and j.unidade_id = p_unidade
      and j.dia_semana = extract(dow from p_data)::int
  ),
  candidatos as (
    select g as ini, g + make_interval(mins => v_duracao) as fim_c
    from faixas f,
         generate_series(f.ini, f.fim_j - make_interval(mins => v_duracao), make_interval(mins => p_passo_min)) g
  )
  select c.ini, c.fim_c
  from candidatos c
  where c.ini > now()
    and not exists (
      select 1 from public.agendamentos a
      where a.profissional_id = p_profissional
        and a.status in ('agendado', 'confirmado', 'atendido') and not a.encaixe
        and tstzrange(a.inicio, a.fim) && tstzrange(c.ini, c.fim_c)
    )
    and not exists (
      select 1 from public.bloqueios_agenda b
      where b.unidade_id = p_unidade
        and (b.profissional_id is null or b.profissional_id = p_profissional)
        and tstzrange(b.inicio, b.fim) && tstzrange(c.ini, c.fim_c)
    )
  order by c.ini;
end;
$$;

-- ---------------------------------------------------------------------
-- RPC: relatório do período (dashboard, financeiro e relatórios)
-- ---------------------------------------------------------------------
create or replace function public.relatorio_periodo(
  p_empresa  uuid,
  p_inicio   timestamptz,
  p_fim      timestamptz,
  p_unidade  uuid default null
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_prof uuid;
  r jsonb;
begin
  if not (app.is_super_admin() or app.e_membro(p_empresa)) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  -- profissional só vê os próprios números; recepção, as unidades dela
  if not (app.is_super_admin() or app.e_dono(p_empresa)) and app.tem_papel(p_empresa, array['profissional']::public.papel_membro[]) then
    v_prof := app.meu_profissional(p_empresa);
    if v_prof is null then v_prof := '00000000-0000-0000-0000-000000000000'; end if;
  end if;

  with ag as (
    select a.* from public.agendamentos a
    where a.empresa_id = p_empresa and a.inicio >= p_inicio and a.inicio < p_fim
      and (p_unidade is null or a.unidade_id = p_unidade)
      and (v_prof is null or a.profissional_id = v_prof)
      and (app.is_super_admin() or app.e_dono(p_empresa) or v_prof is not null or app.ve_unidade(a.unidade_id))
  ),
  pg as (
    select p.* from public.pagamentos p
    where p.empresa_id = p_empresa and p.recebido_em >= p_inicio and p.recebido_em < p_fim
      and (p_unidade is null or p.unidade_id = p_unidade)
      and (v_prof is null or p.profissional_id = v_prof)
      and (app.is_super_admin() or app.e_dono(p_empresa) or v_prof is not null or app.ve_unidade(p.unidade_id))
  ),
  novos as (
    select count(*) n from public.clientes c
    where c.empresa_id = p_empresa and c.criado_em >= p_inicio and c.criado_em < p_fim
  )
  select jsonb_build_object(
    'agendamentos', (select count(*) from ag where status <> 'cancelado'),
    'por_status', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from ag group by status) x), '{}'::jsonb),
    'taxa_faltas', (select case when count(*) filter (where status in ('atendido', 'faltou')) = 0 then 0
                     else round(100.0 * count(*) filter (where status = 'faltou') / count(*) filter (where status in ('atendido', 'faltou')), 1) end from ag),
    'faturamento', (select coalesce(sum(valor), 0) from pg),
    'a_receber', (select coalesce(sum(a.valor), 0) from ag a where a.status = 'atendido'
                    and not exists (select 1 from public.pagamentos p where p.agendamento_id = a.id)),
    'novos_clientes', (select n from novos),
    'ticket_medio', (select case when count(*) = 0 then 0 else round(sum(valor) / count(*), 2) end from pg),
    'por_forma', coalesce((select jsonb_object_agg(forma, total) from (select forma, sum(valor) total from pg group by forma) x), '{}'::jsonb),
    'por_profissional', coalesce((
      select jsonb_agg(jsonb_build_object('id', pr.id, 'nome', pr.nome, 'cor', pr.cor_agenda,
        'atendidos', (select count(*) from ag where profissional_id = pr.id and status = 'atendido'),
        'faltas', (select count(*) from ag where profissional_id = pr.id and status = 'faltou'),
        'agendamentos', (select count(*) from ag where profissional_id = pr.id and status <> 'cancelado'),
        'faturamento', (select coalesce(sum(valor), 0) from pg where profissional_id = pr.id))
        order by pr.nome)
      from public.profissionais pr where pr.empresa_id = p_empresa and (v_prof is null or pr.id = v_prof)), '[]'::jsonb),
    'por_servico', coalesce((
      select jsonb_agg(x order by x->>'qtd' desc) from (
        select jsonb_build_object('nome', s.nome, 'qtd', count(*), 'valor', coalesce(sum(a.valor), 0)) x
        from ag a join public.servicos s on s.id = a.servico_id
        where a.status = 'atendido' group by s.nome order by count(*) desc limit 10) t), '[]'::jsonb),
    'por_dia', coalesce((
      select jsonb_agg(jsonb_build_object('dia', d, 'agendamentos', qa, 'faturamento', fat) order by d) from (
        select d::date d,
          (select count(*) from ag where (inicio at time zone 'America/Sao_Paulo')::date = d::date and status <> 'cancelado') qa,
          (select coalesce(sum(valor), 0) from pg where (recebido_em at time zone 'America/Sao_Paulo')::date = d::date) fat
        from generate_series((p_inicio at time zone 'America/Sao_Paulo')::date, ((p_fim - interval '1 second') at time zone 'America/Sao_Paulo')::date, interval '1 day') d
      ) t), '[]'::jsonb)
  ) into r;
  return r;
end;
$$;

revoke execute on function
  public.atualizar_status_agendamento(uuid, public.status_agendamento, text),
  public.horarios_livres(uuid, uuid, uuid, date, int),
  public.relatorio_periodo(uuid, timestamptz, timestamptz, uuid)
from public, anon;
grant execute on function
  public.atualizar_status_agendamento(uuid, public.status_agendamento, text),
  public.horarios_livres(uuid, uuid, uuid, date, int),
  public.relatorio_periodo(uuid, timestamptz, timestamptz, uuid)
to authenticated, service_role;

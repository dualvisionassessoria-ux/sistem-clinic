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

-- >>> migrations/20261124000800_whatsapp.sql
-- =====================================================================
-- Sistem Clinic · Etapas 3 e 4 · WhatsApp (Evolution API)
-- Conexão por unidade, mensagens automáticas (confirmação, lembrete,
-- pós-atendimento, aniversário, retorno), campanhas e marcação pelo
-- WhatsApp. A Evolution API só é chamada pela Edge Function "whatsapp";
-- o navegador nunca vê chaves nem tokens.
-- =====================================================================

create type public.tipo_mensagem as enum (
  'confirmacao', 'lembrete', 'pos_atendimento', 'aniversario', 'retorno',
  'resposta_sim', 'resposta_nao', 'campanha', 'bot', 'entrada'
);
create type public.status_mensagem as enum ('pendente', 'enviando', 'enviada', 'erro', 'recebida');

-- ---------------------------------------------------------------------
-- Configuração interna (fora da API) e segredos
-- ---------------------------------------------------------------------
create table app.config (
  chave  text primary key,
  valor  text not null
);
insert into app.config (chave, valor) values ('cron_secret', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
on conflict (chave) do nothing;

-- ---------------------------------------------------------------------
-- Instância do WhatsApp (uma por unidade)
-- ---------------------------------------------------------------------
create table public.whatsapp_instancias (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id) on delete cascade,
  unidade_id      uuid not null unique,
  nome_instancia  text not null unique,
  status          text not null default 'desconectado' check (status in ('desconectado', 'conectando', 'conectado')),
  numero          text,
  conectado_em    timestamptz,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  unique (id, empresa_id),
  foreign key (unidade_id, empresa_id) references public.unidades(id, empresa_id) on delete cascade
);
create trigger tg_whatsapp_instancias_atualizado before update on public.whatsapp_instancias
  for each row execute function app.tocar_atualizado_em();

create table app.whatsapp_segredos (
  instancia_id   uuid primary key references public.whatsapp_instancias(id) on delete cascade,
  webhook_token  text not null unique default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
);

-- conversa do robô de marcação (estado por telefone)
create table app.conversas_bot (
  instancia_id   uuid not null references public.whatsapp_instancias(id) on delete cascade,
  telefone       text not null,
  etapa          text not null,
  dados          jsonb not null default '{}'::jsonb,
  atualizado_em  timestamptz not null default now(),
  primary key (instancia_id, telefone)
);

-- ---------------------------------------------------------------------
-- Modelos de mensagem (textos editáveis com {{variáveis}})
-- ---------------------------------------------------------------------
create table public.modelos_mensagem (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas(id) on delete cascade,
  tipo           public.tipo_mensagem not null,
  ativo          boolean not null default true,
  texto          text not null check (length(trim(texto)) between 1 and 2000),
  horas          int check (horas between 0 and 72),     -- antes (confirmação/lembrete), depois (pós) ou hora do envio (aniversário)
  dias           int check (dias between 7 and 730),     -- retorno: dias sem visita
  atualizado_em  timestamptz not null default now(),
  unique (empresa_id, tipo)
);
create trigger tg_modelos_atualizado before update on public.modelos_mensagem
  for each row execute function app.tocar_atualizado_em();

-- ---------------------------------------------------------------------
-- Campanhas e fila/registro de mensagens
-- ---------------------------------------------------------------------
create table public.campanhas (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas(id) on delete cascade,
  nome        text not null,
  publico     text not null,
  dias        int,
  texto       text not null,
  total       int not null default 0,
  criado_por  uuid references auth.users(id) on delete set null,
  criado_em   timestamptz not null default now()
);

create table public.mensagens (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id) on delete cascade,
  unidade_id      uuid,
  instancia_id    uuid references public.whatsapp_instancias(id) on delete set null,
  cliente_id      uuid references public.clientes(id) on delete set null,
  agendamento_id  uuid references public.agendamentos(id) on delete set null,
  campanha_id     uuid references public.campanhas(id) on delete set null,
  tipo            public.tipo_mensagem not null,
  direcao         text not null default 'saida' check (direcao in ('saida', 'entrada')),
  telefone        text not null,
  texto           text not null,
  status          public.status_mensagem not null default 'pendente',
  tentativas      int not null default 0,
  erro            text,
  id_externo      text,
  enviar_apos     timestamptz not null default now(),
  enviada_em      timestamptz,
  criado_em       timestamptz not null default now()
);
create index mensagens_fila on public.mensagens (enviar_apos) where status = 'pendente';
create index on public.mensagens (empresa_id, criado_em desc);
create index on public.mensagens (cliente_id, tipo, criado_em desc);

-- ---------------------------------------------------------------------
-- Textos padrão
-- ---------------------------------------------------------------------
create or replace function app.criar_modelos_padrao(p_empresa uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.modelos_mensagem (empresa_id, tipo, texto, horas, dias) values
  (p_empresa, 'confirmacao',
   E'Olá, {{primeiro_nome}}! 😊\nPassando para confirmar seu horário de *{{servico}}* com {{profissional}} {{dia_semana}}, *{{data}} às {{hora}}*, na {{empresa}}.\n\nResponda *SIM* para confirmar ou *NÃO* para cancelar.', 24, null),
  (p_empresa, 'lembrete',
   E'Oi, {{primeiro_nome}}! Lembrete: seu horário é hoje às *{{hora}}* com {{profissional}}.\n📍 {{endereco}}\nAté já!', 2, null),
  (p_empresa, 'pos_atendimento',
   E'Obrigado pela visita, {{primeiro_nome}}! 💙\nSua opinião ajuda muito a gente. Pode deixar uma avaliação? Leva 1 minuto:\n{{link_avaliacao}}', 2, null),
  (p_empresa, 'aniversario',
   E'Feliz aniversário, {{primeiro_nome}}! 🎉\nToda a equipe da {{empresa}} deseja um dia maravilhoso para você!', 9, null),
  (p_empresa, 'retorno',
   E'Oi, {{primeiro_nome}}! Sentimos sua falta aqui na {{empresa}} 💙\nQue tal agendar seu retorno? É só responder esta mensagem.', null, 90),
  (p_empresa, 'resposta_sim', E'Perfeito, {{primeiro_nome}}! Seu horário de {{data}} às {{hora}} está confirmado. ✅', null, null),
  (p_empresa, 'resposta_nao', E'Tudo bem, {{primeiro_nome}}. Cancelamos seu horário de {{data}} às {{hora}}. Quando quiser remarcar, é só chamar por aqui.', null, null)
  on conflict (empresa_id, tipo) do nothing;
$$;

create or replace function app.tg_empresa_modelos()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform app.criar_modelos_padrao(new.id);
  return null;
end;
$$;
create trigger tg_empresas_modelos after insert on public.empresas
  for each row execute function app.tg_empresa_modelos();

select app.criar_modelos_padrao(id) from public.empresas;

-- ---------------------------------------------------------------------
-- Funções auxiliares
-- ---------------------------------------------------------------------

-- compara telefones ignorando o 55 e o nono dígito (o WhatsApp às vezes manda sem)
create or replace function app.mesmo_telefone(a text, b text)
returns boolean language sql immutable as $$
  with x as (
    select regexp_replace(regexp_replace(coalesce(a, ''), '\D', '', 'g'), '^55(\d{10,11})$', '\1') as a,
           regexp_replace(regexp_replace(coalesce(b, ''), '\D', '', 'g'), '^55(\d{10,11})$', '\1') as b
  )
  select length(a) >= 10 and length(b) >= 10 and left(a, 2) = left(b, 2) and right(a, 8) = right(b, 8) from x;
$$;

create or replace function app.normalizar_texto(p text)
returns text language sql immutable as $$
  select trim(regexp_replace(translate(lower(coalesce(p, '')), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc'), '\s+', ' ', 'g'));
$$;

create or replace function app.render(p_texto text, p_vars jsonb)
returns text language plpgsql immutable as $$
declare
  r text := p_texto;
  k text;
begin
  for k in select jsonb_object_keys(p_vars) loop
    r := replace(r, '{{' || k || '}}', coalesce(p_vars ->> k, ''));
  end loop;
  return r;
end;
$$;

create or replace function app.dia_semana_pt(p date)
returns text language sql immutable as $$
  select (array['domingo', 'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado'])[extract(dow from p)::int + 1];
$$;

-- variáveis de um cliente
create or replace function app.vars_cliente(p_cliente uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('nome', c.nome, 'primeiro_nome', split_part(c.nome, ' ', 1), 'empresa', e.nome)
  from public.clientes c join public.empresas e on e.id = c.empresa_id
  where c.id = p_cliente;
$$;

-- variáveis de um agendamento
create or replace function app.vars_agendamento(p_agendamento uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'nome', c.nome,
    'primeiro_nome', split_part(c.nome, ' ', 1),
    'empresa', e.nome,
    'unidade', u.nome,
    'endereco', concat_ws(', ', u.endereco, u.cidade),
    'telefone_unidade', u.telefone,
    'data', to_char(a.inicio at time zone u.fuso_horario, 'DD/MM'),
    'hora', to_char(a.inicio at time zone u.fuso_horario, 'HH24:MI'),
    'dia_semana', app.dia_semana_pt((a.inicio at time zone u.fuso_horario)::date),
    'servico', coalesce(s.nome, 'atendimento'),
    'profissional', p.nome,
    'link_avaliacao', u.link_avaliacao_google
  )
  from public.agendamentos a
  join public.clientes c on c.id = a.cliente_id
  join public.empresas e on e.id = a.empresa_id
  join public.unidades u on u.id = a.unidade_id
  join public.profissionais p on p.id = a.profissional_id
  left join public.servicos s on s.id = a.servico_id
  where a.id = p_agendamento;
$$;

create or replace function app.recurso_empresa(p_empresa uuid, p_recurso text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((p.recursos ->> p_recurso)::boolean, false)
     and e.status_assinatura in ('teste', 'ativa', 'inadimplente')
     and (e.status_assinatura <> 'teste' or e.teste_ate is null or e.teste_ate > now())
  from public.empresas e join public.planos p on p.id = e.plano_id
  where e.id = p_empresa;
$$;

-- instância conectada para falar com um cliente: a da unidade do último atendimento, senão qualquer uma da empresa
create or replace function app.instancia_para_cliente(p_empresa uuid, p_cliente uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select i.id from public.whatsapp_instancias i
  where i.empresa_id = p_empresa and i.status = 'conectado'
  order by (i.unidade_id = (select a.unidade_id from public.agendamentos a where a.cliente_id = p_cliente order by a.inicio desc limit 1)) desc nulls last,
           i.criado_em
  limit 1;
$$;

create or replace function app.enfileirar(
  p_empresa uuid, p_instancia uuid, p_cliente uuid, p_agendamento uuid, p_tipo public.tipo_mensagem,
  p_telefone text, p_texto text, p_campanha uuid default null, p_enviar_apos timestamptz default now(),
  p_status public.status_mensagem default 'pendente'
) returns uuid language sql security definer set search_path = '' as $$
  insert into public.mensagens (empresa_id, unidade_id, instancia_id, cliente_id, agendamento_id, campanha_id, tipo, telefone, texto, enviar_apos, status)
  select p_empresa, i.unidade_id, p_instancia, p_cliente, p_agendamento, p_campanha, p_tipo, p_telefone, p_texto, p_enviar_apos, p_status
  from public.whatsapp_instancias i where i.id = p_instancia
  returning id;
$$;

-- horários livres sem checagem de permissão (uso interno do robô)
create or replace function app.horarios_livres(p_unidade uuid, p_profissional uuid, p_servico uuid, p_data date, p_passo_min int default 15)
returns table (inicio timestamptz, fim timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_empresa uuid;
  v_fuso text;
  v_duracao int;
begin
  select u.empresa_id, u.fuso_horario into v_empresa, v_fuso from public.unidades u where u.id = p_unidade and u.ativo;
  if v_empresa is null then return; end if;
  select coalesce(sp.duracao_propria, s.duracao_min) + s.intervalo_apos_min into v_duracao
  from public.servicos s
  left join public.servico_profissionais sp on sp.servico_id = s.id and sp.profissional_id = p_profissional
  where s.id = p_servico and s.empresa_id = v_empresa;
  v_duracao := coalesce(v_duracao, 30);

  return query
  with faixas as (
    select (p_data + j.inicio) at time zone v_fuso as ini, (p_data + j.fim) at time zone v_fuso as fim_j
    from public.jornadas j
    where j.profissional_id = p_profissional and j.unidade_id = p_unidade and j.dia_semana = extract(dow from p_data)::int
  ),
  candidatos as (
    select g as ini, g + make_interval(mins => v_duracao) as fim_c
    from faixas f, generate_series(f.ini, f.fim_j - make_interval(mins => v_duracao), make_interval(mins => p_passo_min)) g
  )
  select c.ini, c.fim_c from candidatos c
  where c.ini > now()
    and not exists (
      select 1 from public.agendamentos a
      where a.profissional_id = p_profissional and a.status in ('agendado', 'confirmado', 'atendido') and not a.encaixe
        and tstzrange(a.inicio, a.fim) && tstzrange(c.ini, c.fim_c))
    and not exists (
      select 1 from public.bloqueios_agenda b
      where b.unidade_id = p_unidade and (b.profissional_id is null or b.profissional_id = p_profissional)
        and tstzrange(b.inicio, b.fim) && tstzrange(c.ini, c.fim_c))
  order by c.ini;
end;
$$;

-- a versão pública passa a usar a interna, depois de checar permissão
create or replace function public.horarios_livres(
  p_unidade uuid, p_profissional uuid, p_servico uuid, p_data date, p_passo_min int default 15
) returns table (inicio timestamptz, fim timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare v_empresa uuid;
begin
  select u.empresa_id into v_empresa from public.unidades u where u.id = p_unidade;
  if v_empresa is null then return; end if;
  if not (app.e_servico() or app.is_super_admin() or app.e_membro(v_empresa)) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query select * from app.horarios_livres(p_unidade, p_profissional, p_servico, p_data, p_passo_min);
end;
$$;

-- ---------------------------------------------------------------------
-- Geração das mensagens automáticas (rodada a cada minuto pelo agendador)
-- ---------------------------------------------------------------------
create or replace function app.gerar_mensagens_automaticas()
returns int language plpgsql security definer set search_path = '' as $$
declare
  r record;
  n int := 0;
  v_local timestamp;
begin
  -- confirmação (X horas antes; só para quem ainda está "agendado")
  for r in
    select a.id, a.empresa_id, a.cliente_id, c.telefone, i.id as inst, m.texto
    from public.agendamentos a
    join public.clientes c on c.id = a.cliente_id and c.aceita_whatsapp and c.telefone is not null
    join public.whatsapp_instancias i on i.unidade_id = a.unidade_id and i.status = 'conectado'
    join public.modelos_mensagem m on m.empresa_id = a.empresa_id and m.tipo = 'confirmacao' and m.ativo
    left join public.modelos_mensagem l on l.empresa_id = a.empresa_id and l.tipo = 'lembrete' and l.ativo
    where a.status = 'agendado' and a.confirmacao_enviada_em is null
      and a.inicio <= now() + make_interval(hours => coalesce(m.horas, 24))
      and a.inicio > now() + make_interval(hours => greatest(coalesce(l.horas, 0), 1))
      and app.recurso_empresa(a.empresa_id, 'lembretes_whatsapp')
    for update of a skip locked
  loop
    perform app.enfileirar(r.empresa_id, r.inst, r.cliente_id, r.id, 'confirmacao', r.telefone, app.render(r.texto, app.vars_agendamento(r.id)));
    update public.agendamentos set confirmacao_enviada_em = now() where id = r.id;
    n := n + 1;
  end loop;

  -- lembrete (X horas antes)
  for r in
    select a.id, a.empresa_id, a.cliente_id, c.telefone, i.id as inst, m.texto
    from public.agendamentos a
    join public.clientes c on c.id = a.cliente_id and c.aceita_whatsapp and c.telefone is not null
    join public.whatsapp_instancias i on i.unidade_id = a.unidade_id and i.status = 'conectado'
    join public.modelos_mensagem m on m.empresa_id = a.empresa_id and m.tipo = 'lembrete' and m.ativo
    where a.status in ('agendado', 'confirmado') and a.lembrete_enviado_em is null
      and a.inicio > now()
      and a.inicio <= now() + make_interval(hours => coalesce(m.horas, 2))
      and a.criado_em < a.inicio - make_interval(hours => coalesce(m.horas, 2))
      and app.recurso_empresa(a.empresa_id, 'lembretes_whatsapp')
    for update of a skip locked
  loop
    perform app.enfileirar(r.empresa_id, r.inst, r.cliente_id, r.id, 'lembrete', r.telefone, app.render(r.texto, app.vars_agendamento(r.id)));
    update public.agendamentos set lembrete_enviado_em = now() where id = r.id;
    n := n + 1;
  end loop;

  -- pós-atendimento com pedido de avaliação no Google
  for r in
    select a.id, a.empresa_id, a.cliente_id, c.telefone, i.id as inst, m.texto
    from public.agendamentos a
    join public.unidades u on u.id = a.unidade_id and nullif(trim(u.link_avaliacao_google), '') is not null
    join public.clientes c on c.id = a.cliente_id and c.aceita_whatsapp and c.telefone is not null
    join public.whatsapp_instancias i on i.unidade_id = a.unidade_id and i.status = 'conectado'
    join public.modelos_mensagem m on m.empresa_id = a.empresa_id and m.tipo = 'pos_atendimento' and m.ativo
    where a.status = 'atendido' and a.pos_atendimento_enviado_em is null
      and a.fim <= now() - make_interval(hours => coalesce(m.horas, 2))
      and a.fim > now() - interval '2 days'
      and extract(hour from now() at time zone u.fuso_horario) between 8 and 20
      and app.recurso_empresa(a.empresa_id, 'avaliacao_google')
      -- no máximo um pedido de avaliação a cada 60 dias por paciente
      and not exists (select 1 from public.mensagens x where x.cliente_id = a.cliente_id and x.tipo = 'pos_atendimento' and x.criado_em > now() - interval '60 days')
    for update of a skip locked
  loop
    perform app.enfileirar(r.empresa_id, r.inst, r.cliente_id, r.id, 'pos_atendimento', r.telefone, app.render(r.texto, app.vars_agendamento(r.id)));
    update public.agendamentos set pos_atendimento_enviado_em = now() where id = r.id;
    n := n + 1;
  end loop;

  -- aniversário (uma vez por ano, a partir da hora escolhida)
  for r in
    select c.id, c.empresa_id, c.telefone, m.texto, app.instancia_para_cliente(c.empresa_id, c.id) as inst
    from public.clientes c
    join public.modelos_mensagem m on m.empresa_id = c.empresa_id and m.tipo = 'aniversario' and m.ativo
    where c.ativo and c.aceita_whatsapp and c.telefone is not null and c.data_nascimento is not null
      and extract(month from c.data_nascimento) = extract(month from now() at time zone 'America/Sao_Paulo')
      and extract(day from c.data_nascimento) = extract(day from now() at time zone 'America/Sao_Paulo')
      and extract(hour from now() at time zone 'America/Sao_Paulo') between coalesce(m.horas, 9) and 20
      and app.recurso_empresa(c.empresa_id, 'campanhas')
      and not exists (select 1 from public.mensagens x where x.cliente_id = c.id and x.tipo = 'aniversario' and x.criado_em > now() - interval '300 days')
  loop
    continue when r.inst is null;
    perform app.enfileirar(r.empresa_id, r.inst, r.id, null, 'aniversario', r.telefone, app.render(r.texto, app.vars_cliente(r.id)));
    n := n + 1;
  end loop;

  -- retorno: paciente sem vir há X dias e sem nada marcado
  v_local := now() at time zone 'America/Sao_Paulo';
  if extract(hour from v_local) between 9 and 19 and extract(dow from v_local) between 1 and 6 then
    for r in
      select c.id, c.empresa_id, c.telefone, m.texto, app.instancia_para_cliente(c.empresa_id, c.id) as inst
      from public.clientes c
      join public.modelos_mensagem m on m.empresa_id = c.empresa_id and m.tipo = 'retorno' and m.ativo
      where c.ativo and c.aceita_whatsapp and c.telefone is not null
        and c.ultima_visita_em <= now() - make_interval(days => coalesce(m.dias, 90))
        and c.ultima_visita_em > now() - make_interval(days => coalesce(m.dias, 90) + 7)
        and app.recurso_empresa(c.empresa_id, 'campanhas')
        and not exists (select 1 from public.agendamentos a where a.cliente_id = c.id and a.inicio > now() and a.status in ('agendado', 'confirmado'))
        and not exists (select 1 from public.mensagens x where x.cliente_id = c.id and x.tipo = 'retorno' and x.criado_em > c.ultima_visita_em)
      limit 200
    loop
      continue when r.inst is null;
      perform app.enfileirar(r.empresa_id, r.inst, r.id, null, 'retorno', r.telefone, app.render(r.texto, app.vars_cliente(r.id)));
      n := n + 1;
    end loop;
  end if;

  return n;
end;
$$;

-- ---------------------------------------------------------------------
-- RPCs usadas pela Edge Function (só service_role)
-- ---------------------------------------------------------------------

-- ciclo do agendador: gera as automáticas e entrega um lote da fila para envio
create or replace function public.whatsapp_ciclo(p_segredo text, p_limite int default 25)
returns table (id uuid, nome_instancia text, telefone text, texto text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  if p_segredo is distinct from (select valor from app.config where chave = 'cron_secret') then
    raise exception 'Segredo inválido.' using errcode = '42501';
  end if;
  perform app.gerar_mensagens_automaticas();

  -- reabre envios que ficaram presos
  update public.mensagens m set status = 'pendente'
  where m.status = 'enviando' and m.enviar_apos < now() - interval '10 minutes' and m.tentativas < 3;

  return query
  with lote as (
    select m.id from public.mensagens m
    join public.whatsapp_instancias i on i.id = m.instancia_id and i.status = 'conectado'
    where m.status = 'pendente' and m.enviar_apos <= now()
    order by m.enviar_apos
    limit p_limite
    for update of m skip locked
  )
  update public.mensagens m set status = 'enviando', tentativas = m.tentativas + 1, enviar_apos = now()
  from lote, public.whatsapp_instancias i
  where m.id = lote.id and i.id = m.instancia_id
  returning m.id, i.nome_instancia, m.telefone, m.texto;
end;
$$;

create or replace function public.whatsapp_resultado_envio(p_id uuid, p_ok boolean, p_erro text default null, p_id_externo text default null)
returns void language sql security definer set search_path = '' as $$
  update public.mensagens set
    status = case when p_ok then 'enviada'::public.status_mensagem when tentativas >= 3 then 'erro' else 'pendente' end,
    enviada_em = case when p_ok then now() end,
    enviar_apos = case when p_ok then enviar_apos else now() + interval '5 minutes' end,
    erro = case when p_ok then null else left(p_erro, 500) end,
    id_externo = coalesce(p_id_externo, id_externo)
  where id = p_id;
$$;

create or replace function public.whatsapp_instancia_por_token(p_token text)
returns table (id uuid, empresa_id uuid, unidade_id uuid, nome_instancia text)
language sql stable security definer set search_path = '' as $$
  select i.id, i.empresa_id, i.unidade_id, i.nome_instancia
  from app.whatsapp_segredos s join public.whatsapp_instancias i on i.id = s.instancia_id
  where s.webhook_token = p_token;
$$;

create or replace function public.whatsapp_segredo_instancia(p_instancia uuid)
returns text language sql stable security definer set search_path = '' as $$
  select webhook_token from app.whatsapp_segredos where instancia_id = p_instancia;
$$;

create or replace function public.whatsapp_atualizar_conexao(p_instancia uuid, p_status text, p_numero text default null)
returns void language sql security definer set search_path = '' as $$
  update public.whatsapp_instancias set
    status = p_status,
    numero = coalesce(nullif(regexp_replace(coalesce(p_numero, ''), '\D', '', 'g'), ''), case when p_status = 'desconectado' then null else numero end),
    conectado_em = case when p_status = 'conectado' and status <> 'conectado' then now() when p_status = 'conectado' then conectado_em end
  where id = p_instancia;
$$;

-- chamada pelo painel (com o login do usuário) antes de conectar/consultar
create or replace function public.whatsapp_acesso_instancia(p_unidade uuid, p_gerir boolean default false)
returns table (id uuid, nome_instancia text, status text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_empresa uuid;
begin
  select u.empresa_id into v_empresa from public.unidades u where u.id = p_unidade;
  if v_empresa is null or not (app.is_super_admin() or app.e_membro(v_empresa)) then
    raise exception 'Unidade não encontrada.' using errcode = 'P0001';
  end if;
  if p_gerir then
    if not (app.is_super_admin() or app.e_dono(v_empresa)) then
      raise exception 'Só o dono pode conectar o WhatsApp.' using errcode = '42501';
    end if;
    if not app.recurso_empresa(v_empresa, 'lembretes_whatsapp') then
      raise exception 'O plano atual não inclui WhatsApp.' using errcode = 'P0001';
    end if;
    insert into public.whatsapp_instancias (empresa_id, unidade_id, nome_instancia)
    values (v_empresa, p_unidade, 'sc_' || replace(p_unidade::text, '-', ''))
    on conflict (unidade_id) do nothing;
    insert into app.whatsapp_segredos (instancia_id)
    select i.id from public.whatsapp_instancias i where i.unidade_id = p_unidade
    on conflict do nothing;
  end if;
  return query select i.id, i.nome_instancia, i.status from public.whatsapp_instancias i where i.unidade_id = p_unidade;
end;
$$;

-- ---------------------------------------------------------------------
-- Mensagem recebida: confirmação SIM/NÃO e robô de marcação (Premium)
-- Devolve as respostas a enviar (já registradas como "enviando").
-- ---------------------------------------------------------------------
create or replace function app.responder(p_inst public.whatsapp_instancias, p_tel text, p_cliente uuid, p_texto text, p_tipo public.tipo_mensagem default 'bot')
returns uuid language sql security definer set search_path = '' as $$
  select app.enfileirar(p_inst.empresa_id, p_inst.id, p_cliente, null, p_tipo, p_tel, p_texto, null, now(), 'enviando');
$$;

create or replace function app.bot_menu(p_empresa text, p_nome text)
returns text language sql immutable as $$
  select 'Olá' || coalesce(', ' || nullif(split_part(p_nome, ' ', 1), ''), '') || '! 👋 Aqui é o atendimento automático da *' || p_empresa || E'*.\n\nResponda com o número:\n*1* - Marcar horário\n*2* - Meus horários\n*3* - Falar com a recepção';
$$;

create or replace function public.whatsapp_processar_entrada(
  p_instancia uuid, p_telefone text, p_nome text, p_texto text, p_id_externo text default null
) returns table (id uuid, nome_instancia text, telefone text, texto text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_inst      public.whatsapp_instancias;
  v_emp       public.empresas;
  v_uni       public.unidades;
  v_tel       text := app.normalizar_telefone(p_telefone);
  v_txt       text := app.normalizar_texto(p_texto);
  v_cli       public.clientes;
  v_conv      app.conversas_bot;
  v_ag        public.agendamentos;
  v_ids       uuid[] := '{}';
  v_msg       text;
  v_opcao     int;
  v_dados     jsonb;
  v_lista     jsonb;
  v_linhas    text;
  v_dia       date;
  v_inicio    timestamptz;
  v_prof      uuid;
  v_dur       int;
  v_valor     numeric;
  i           int;
  rec         record;
begin
  select * into v_inst from public.whatsapp_instancias w where w.id = p_instancia;
  if v_inst.id is null or v_tel is null then return; end if;
  select * into v_emp from public.empresas e where e.id = v_inst.empresa_id;
  select * into v_uni from public.unidades u where u.id = v_inst.unidade_id;

  select * into v_cli from public.clientes c
  where c.empresa_id = v_inst.empresa_id and c.ativo and app.mesmo_telefone(c.telefone, v_tel)
  order by c.atualizado_em desc limit 1;

  -- registra a mensagem recebida
  insert into public.mensagens (empresa_id, unidade_id, instancia_id, cliente_id, tipo, direcao, telefone, texto, status, id_externo, enviada_em)
  values (v_inst.empresa_id, v_inst.unidade_id, v_inst.id, v_cli.id, 'entrada', 'entrada', v_tel, left(coalesce(p_texto, ''), 4000), 'recebida', p_id_externo, now());

  if v_emp.status_assinatura not in ('teste', 'ativa', 'inadimplente') then return; end if;

  select * into v_conv from app.conversas_bot c where c.instancia_id = v_inst.id and c.telefone = v_tel;
  -- recepção assumiu a conversa: o robô fica quieto por 12 horas
  if v_conv.etapa = 'humano' and v_conv.atualizado_em > now() - interval '12 hours' then return; end if;
  if v_conv.etapa is not null and v_conv.atualizado_em < now() - interval '30 minutes' then
    delete from app.conversas_bot c where c.instancia_id = v_inst.id and c.telefone = v_tel;
    v_conv := null;
  end if;

  perform set_config('app.origem', 'whatsapp', true);

  -- 1) resposta à confirmação
  if v_cli.id is not null and (v_conv.etapa is null or v_conv.etapa = 'menu')
     and (v_txt ~ '^(sim|s|ss|confirmo|confirmado|confirmar|confirma|ok|okay|certo|claro|pode)([^a-z]|$)' or v_txt like '👍%'
          or v_txt ~ '^(nao|n|cancelar|cancela|cancelo|desmarcar|desmarca)([^a-z]|$)') then
    select * into v_ag from public.agendamentos a
    where a.cliente_id = v_cli.id and a.status = 'agendado' and a.confirmacao_enviada_em is not null and a.inicio > now()
    order by a.inicio limit 1;
    if v_ag.id is not null then
      if v_txt ~ '^(nao|n|cancelar|cancela|cancelo|desmarcar|desmarca)([^a-z]|$)' then
        update public.agendamentos set status = 'cancelado', motivo_cancelamento = 'Cancelado pelo paciente no WhatsApp' where agendamentos.id = v_ag.id;
        select m.texto into v_msg from public.modelos_mensagem m where m.empresa_id = v_inst.empresa_id and m.tipo = 'resposta_nao';
        v_ids := v_ids || app.responder(v_inst, v_tel, v_cli.id, app.render(coalesce(v_msg, 'Horário cancelado.'), app.vars_agendamento(v_ag.id)), 'resposta_nao');
        if app.recurso_empresa(v_inst.empresa_id, 'marcacao_whatsapp') then
          v_ids := v_ids || app.responder(v_inst, v_tel, v_cli.id, 'Se quiser escolher outro horário agora, responda *1*.');
          insert into app.conversas_bot (instancia_id, telefone, etapa) values (v_inst.id, v_tel, 'menu')
          on conflict (instancia_id, telefone) do update set etapa = 'menu', dados = '{}', atualizado_em = now();
        end if;
      else
        update public.agendamentos set status = 'confirmado' where agendamentos.id = v_ag.id;
        select m.texto into v_msg from public.modelos_mensagem m where m.empresa_id = v_inst.empresa_id and m.tipo = 'resposta_sim';
        v_ids := v_ids || app.responder(v_inst, v_tel, v_cli.id, app.render(coalesce(v_msg, 'Horário confirmado!'), app.vars_agendamento(v_ag.id)), 'resposta_sim');
      end if;
      return query select m.id, v_inst.nome_instancia, m.telefone, m.texto from public.mensagens m where m.id = any(v_ids) order by m.criado_em, m.id;
      return;
    end if;
  end if;

  -- 2) robô de marcação (plano Premium)
  if not app.recurso_empresa(v_inst.empresa_id, 'marcacao_whatsapp') then return; end if;

  v_dados := coalesce(v_conv.dados, '{}'::jsonb);
  v_opcao := case when v_txt ~ '^\d{1,2}$' then v_txt::int end;

  if v_txt in ('menu', 'voltar', 'inicio', 'oi', 'ola', 'bom dia', 'boa tarde', 'boa noite') and coalesce(v_conv.etapa, 'menu') <> 'nome' then
    v_conv.etapa := null;
    v_opcao := null;
  end if;

  <<maquina>>
  loop
    case coalesce(v_conv.etapa, 'menu')

    when 'menu' then
      if v_opcao = 1 then
        select jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome) order by s.nome) into v_lista
        from public.servicos s
        where s.empresa_id = v_inst.empresa_id and s.ativo and s.agendavel_whatsapp
          and exists (select 1 from public.profissional_unidades pu join public.profissionais p on p.id = pu.profissional_id and p.ativo
                      where pu.unidade_id = v_inst.unidade_id
                        and (not exists (select 1 from public.servico_profissionais sp where sp.servico_id = s.id)
                             or exists (select 1 from public.servico_profissionais sp where sp.servico_id = s.id and sp.profissional_id = p.id)));
        if v_lista is null then
          v_msg := 'No momento não há serviços disponíveis para marcar por aqui. Responda *3* para falar com a recepção.';
          v_conv.etapa := 'menu';
        else
          v_linhas := '';
          for i in 0 .. jsonb_array_length(v_lista) - 1 loop
            v_linhas := v_linhas || E'\n*' || (i + 1) || '* - ' || (v_lista -> i ->> 'nome');
          end loop;
          v_msg := 'Qual serviço você quer marcar?' || v_linhas || E'\n\n_Responda com o número. Para voltar, envie MENU._';
          v_conv.etapa := 'servico';
          v_dados := jsonb_build_object('servicos', v_lista);
        end if;
      elsif v_opcao = 2 then
        if v_cli.id is null then
          v_msg := E'Não encontrei horários marcados para este número.\n\nResponda *1* para marcar um horário.';
        else
          select jsonb_agg(jsonb_build_object('id', a.id) order by a.inicio), string_agg(
                   E'\n*' || rn || '* - ' || to_char(a.inicio at time zone v_uni.fuso_horario, 'DD/MM "às" HH24:MI') || ' · ' || coalesce(s.nome, 'Atendimento') || ' com ' || p.nome, '' order by a.inicio)
            into v_lista, v_linhas
          from (select a.*, row_number() over (order by a.inicio) rn from public.agendamentos a
                where a.cliente_id = v_cli.id and a.inicio > now() and a.status in ('agendado', 'confirmado') limit 9) a
          join public.profissionais p on p.id = a.profissional_id
          left join public.servicos s on s.id = a.servico_id;
          if v_lista is null then
            v_msg := E'Você não tem horários marcados.\n\nResponda *1* para marcar.';
          else
            v_msg := 'Seus próximos horários:' || v_linhas || E'\n\nPara cancelar um deles, responda com o número. Para voltar, envie MENU.';
            v_conv.etapa := 'meus';
            v_dados := jsonb_build_object('agendamentos', v_lista);
          end if;
        end if;
      elsif v_opcao = 3 then
        v_msg := 'Certo! Avisei a recepção e logo alguém responde por aqui. 😊';
        v_conv.etapa := 'humano';
      else
        v_msg := app.bot_menu(v_emp.nome, coalesce(v_cli.nome, p_nome));
        v_conv.etapa := 'menu';
      end if;

    when 'servico' then
      if v_opcao between 1 and jsonb_array_length(v_dados -> 'servicos') then
        v_dados := v_dados || jsonb_build_object('servico', v_dados -> 'servicos' -> (v_opcao - 1));
        select jsonb_agg(jsonb_build_object('id', p.id, 'nome', p.nome) order by p.nome) into v_lista
        from public.profissionais p
        join public.profissional_unidades pu on pu.profissional_id = p.id and pu.unidade_id = v_inst.unidade_id
        where p.ativo and (not exists (select 1 from public.servico_profissionais sp where sp.servico_id = (v_dados -> 'servico' ->> 'id')::uuid)
                           or exists (select 1 from public.servico_profissionais sp where sp.servico_id = (v_dados -> 'servico' ->> 'id')::uuid and sp.profissional_id = p.id));
        v_dados := v_dados || jsonb_build_object('profissionais', coalesce(v_lista, '[]'::jsonb));
        if jsonb_array_length(coalesce(v_lista, '[]'::jsonb)) <= 1 then
          v_dados := v_dados || jsonb_build_object('profissional', coalesce(v_lista -> 0, 'null'::jsonb));
          v_conv.etapa := 'listar_dias';
          continue maquina;
        end if;
        v_linhas := E'\n*0* - Tanto faz (primeiro horário livre)';
        for i in 0 .. jsonb_array_length(v_lista) - 1 loop
          v_linhas := v_linhas || E'\n*' || (i + 1) || '* - ' || (v_lista -> i ->> 'nome');
        end loop;
        v_msg := 'Com qual profissional?' || v_linhas;
        v_conv.etapa := 'profissional';
      else
        v_msg := 'Não entendi. Responda só com o número do serviço, ou envie MENU para voltar.';
      end if;

    when 'profissional' then
      if v_opcao = 0 then
        v_dados := v_dados || jsonb_build_object('profissional', 'null'::jsonb);
        v_conv.etapa := 'listar_dias';
        continue maquina;
      elsif v_opcao between 1 and jsonb_array_length(v_dados -> 'profissionais') then
        v_dados := v_dados || jsonb_build_object('profissional', v_dados -> 'profissionais' -> (v_opcao - 1));
        v_conv.etapa := 'listar_dias';
        continue maquina;
      else
        v_msg := 'Não entendi. Responda com o número do profissional (ou *0* para tanto faz).';
      end if;

    when 'listar_dias' then
      v_lista := '[]'::jsonb;
      v_linhas := '';
      for i in 0 .. 20 loop
        exit when jsonb_array_length(v_lista) >= 7;
        v_dia := (now() at time zone v_uni.fuso_horario)::date + i;
        if exists (
          select 1 from jsonb_array_elements(case when v_dados -> 'profissional' = 'null'::jsonb then v_dados -> 'profissionais' else jsonb_build_array(v_dados -> 'profissional') end) pr,
               lateral app.horarios_livres(v_inst.unidade_id, (pr ->> 'id')::uuid, (v_dados -> 'servico' ->> 'id')::uuid, v_dia, 30) h
        ) then
          v_lista := v_lista || to_jsonb(v_dia);
          v_linhas := v_linhas || E'\n*' || jsonb_array_length(v_lista) || '* - ' || initcap(split_part(app.dia_semana_pt(v_dia), '-', 1)) || ', ' || to_char(v_dia, 'DD/MM');
        end if;
      end loop;
      if jsonb_array_length(v_lista) = 0 then
        v_msg := 'Não encontrei horários livres nos próximos dias. Responda *3* para falar com a recepção ou MENU para voltar.';
        v_conv.etapa := 'menu';
        v_dados := '{}';
      else
        v_msg := 'Para qual dia?' || v_linhas;
        v_dados := v_dados || jsonb_build_object('dias', v_lista);
        v_conv.etapa := 'dia';
      end if;

    when 'dia' then
      if v_opcao between 1 and jsonb_array_length(v_dados -> 'dias') then
        v_dia := (v_dados -> 'dias' ->> (v_opcao - 1))::date;
        select jsonb_agg(jsonb_build_object('inicio', x.inicio, 'prof', x.prof) order by x.inicio) into v_lista
        from (
          select distinct on (h.inicio) h.inicio, (pr ->> 'id')::uuid as prof
          from jsonb_array_elements(case when v_dados -> 'profissional' = 'null'::jsonb then v_dados -> 'profissionais' else jsonb_build_array(v_dados -> 'profissional') end) pr,
               lateral app.horarios_livres(v_inst.unidade_id, (pr ->> 'id')::uuid, (v_dados -> 'servico' ->> 'id')::uuid, v_dia, 30) h
          order by h.inicio
          limit 12
        ) x;
        if v_lista is null then
          v_msg := 'Os horários desse dia acabaram de ser ocupados. Escolha outro dia:';
          v_conv.etapa := 'listar_dias';
          continue maquina;
        end if;
        v_linhas := '';
        for i in 0 .. jsonb_array_length(v_lista) - 1 loop
          v_linhas := v_linhas || E'\n*' || (i + 1) || '* - ' || to_char((v_lista -> i ->> 'inicio')::timestamptz at time zone v_uni.fuso_horario, 'HH24:MI');
        end loop;
        v_msg := 'Horários livres em ' || to_char(v_dia, 'DD/MM') || ':' || v_linhas;
        v_dados := v_dados || jsonb_build_object('horarios', v_lista);
        v_conv.etapa := 'horario';
      else
        v_msg := 'Não entendi. Responda com o número do dia.';
      end if;

    when 'horario' then
      if v_opcao between 1 and jsonb_array_length(v_dados -> 'horarios') then
        v_dados := v_dados || jsonb_build_object('escolhido', v_dados -> 'horarios' -> (v_opcao - 1));
        if v_cli.id is null then
          v_msg := 'Para finalizar, qual é o seu *nome completo*?';
          v_conv.etapa := 'nome';
        else
          v_conv.etapa := 'resumo';
          continue maquina;
        end if;
      else
        v_msg := 'Não entendi. Responda com o número do horário.';
      end if;

    when 'nome' then
      if length(trim(coalesce(p_texto, ''))) between 3 and 160 and v_opcao is null then
        insert into public.clientes (empresa_id, nome, telefone, origem)
        values (v_inst.empresa_id, initcap(trim(p_texto)), v_tel, 'WhatsApp')
        returning * into v_cli;
        v_conv.etapa := 'resumo';
        continue maquina;
      else
        v_msg := 'Por favor, me diga seu nome completo.';
      end if;

    when 'resumo' then
      select p.nome into v_linhas from public.profissionais p where p.id = (v_dados -> 'escolhido' ->> 'prof')::uuid;
      v_inicio := (v_dados -> 'escolhido' ->> 'inicio')::timestamptz;
      v_msg := 'Confirma o agendamento?' || E'\n\n📋 ' || (v_dados -> 'servico' ->> 'nome') || E'\n👤 ' || v_linhas
        || E'\n📅 ' || app.dia_semana_pt((v_inicio at time zone v_uni.fuso_horario)::date) || ', ' || to_char(v_inicio at time zone v_uni.fuso_horario, 'DD/MM "às" HH24:MI')
        || E'\n📍 ' || v_uni.nome || E'\n\n*1* - Confirmar\n*2* - Escolher outro horário';
      v_conv.etapa := 'confirmar';

    when 'confirmar' then
      if v_opcao = 1 then
        v_inicio := (v_dados -> 'escolhido' ->> 'inicio')::timestamptz;
        v_prof := (v_dados -> 'escolhido' ->> 'prof')::uuid;
        select coalesce(sp.duracao_propria, s.duracao_min) + s.intervalo_apos_min, coalesce(sp.preco_proprio, s.preco)
          into v_dur, v_valor
        from public.servicos s left join public.servico_profissionais sp on sp.servico_id = s.id and sp.profissional_id = v_prof
        where s.id = (v_dados -> 'servico' ->> 'id')::uuid;
        begin
          insert into public.agendamentos (empresa_id, unidade_id, profissional_id, cliente_id, servico_id, inicio, fim, status, origem, valor)
          values (v_inst.empresa_id, v_inst.unidade_id, v_prof, v_cli.id, (v_dados -> 'servico' ->> 'id')::uuid,
                  v_inicio, v_inicio + make_interval(mins => coalesce(v_dur, 30)), 'confirmado', 'whatsapp', v_valor)
          returning * into v_ag;
          v_msg := 'Pronto, ' || split_part(v_cli.nome, ' ', 1) || '! Seu horário está marcado ✅' || E'\n\n'
            || to_char(v_inicio at time zone v_uni.fuso_horario, 'DD/MM "às" HH24:MI') || ' · ' || (v_dados -> 'servico' ->> 'nome')
            || coalesce(E'\n📍 ' || nullif(concat_ws(', ', v_uni.endereco, v_uni.cidade), ''), '')
            || E'\n\nSe precisar, envie MENU a qualquer momento.';
          v_conv.etapa := null;
          v_dados := '{}';
        exception when exclusion_violation then
          v_msg := 'Esse horário acabou de ser ocupado. 😕 Vamos escolher outro:';
          v_ids := v_ids || app.responder(v_inst, v_tel, v_cli.id, v_msg);
          v_conv.etapa := 'listar_dias';
          continue maquina;
        end;
      elsif v_opcao = 2 then
        v_conv.etapa := 'listar_dias';
        continue maquina;
      else
        v_msg := 'Responda *1* para confirmar ou *2* para escolher outro horário.';
      end if;

    when 'meus' then
      if v_opcao between 1 and jsonb_array_length(v_dados -> 'agendamentos') then
        v_dados := v_dados || jsonb_build_object('cancelar', v_dados -> 'agendamentos' -> (v_opcao - 1) ->> 'id');
        select * into v_ag from public.agendamentos a where a.id = (v_dados ->> 'cancelar')::uuid;
        v_msg := 'Deseja cancelar o horário de ' || to_char(v_ag.inicio at time zone v_uni.fuso_horario, 'DD/MM "às" HH24:MI') || E'?\n\n*1* - Sim, cancelar\n*2* - Não';
        v_conv.etapa := 'cancelar';
      else
        v_msg := 'Responda com o número do horário que quer cancelar, ou envie MENU.';
      end if;

    when 'cancelar' then
      if v_opcao = 1 then
        update public.agendamentos a set status = 'cancelado', motivo_cancelamento = 'Cancelado pelo paciente no WhatsApp'
        where a.id = (v_dados ->> 'cancelar')::uuid and a.cliente_id = v_cli.id and a.status in ('agendado', 'confirmado');
        v_msg := E'Horário cancelado. Quer marcar outro? Responda *1*.';
        v_conv.etapa := 'menu';
        v_dados := '{}';
      else
        v_msg := app.bot_menu(v_emp.nome, v_cli.nome);
        v_conv.etapa := 'menu';
        v_dados := '{}';
      end if;

    else
      v_conv.etapa := null;
      continue maquina;
    end case;
    exit maquina;
  end loop;

  if v_conv.etapa is null then
    delete from app.conversas_bot c where c.instancia_id = v_inst.id and c.telefone = v_tel;
  else
    insert into app.conversas_bot (instancia_id, telefone, etapa, dados, atualizado_em)
    values (v_inst.id, v_tel, v_conv.etapa, v_dados, now())
    on conflict (instancia_id, telefone) do update set etapa = excluded.etapa, dados = excluded.dados, atualizado_em = now();
  end if;

  if v_msg is not null then
    v_ids := v_ids || app.responder(v_inst, v_tel, v_cli.id, v_msg);
  end if;
  return query select m.id, v_inst.nome_instancia, m.telefone, m.texto from public.mensagens m where m.id = any(v_ids) order by m.criado_em, m.id;
end;
$$;

-- ---------------------------------------------------------------------
-- Campanhas (dono; planos com "campanhas")
-- ---------------------------------------------------------------------
create or replace function app.publico_campanha(p_empresa uuid, p_publico text, p_dias int)
returns setof public.clientes language sql stable security definer set search_path = '' as $$
  select c.* from public.clientes c
  where c.empresa_id = p_empresa and c.ativo and c.aceita_whatsapp and c.telefone is not null
    and case p_publico
      when 'todos' then true
      when 'sumidos' then c.ultima_visita_em < now() - make_interval(days => coalesce(p_dias, 60))
      when 'aniversariantes_mes' then extract(month from c.data_nascimento) = extract(month from now() at time zone 'America/Sao_Paulo')
      when 'nunca_vieram' then c.ultima_visita_em is null
      else false end
    and not exists (select 1 from public.agendamentos a where a.cliente_id = c.id and a.inicio > now() and a.status in ('agendado', 'confirmado') and p_publico in ('sumidos', 'nunca_vieram'));
$$;

create or replace function public.contar_publico_campanha(p_empresa uuid, p_publico text, p_dias int default 60)
returns int language plpgsql stable security definer set search_path = '' as $$
begin
  if not (app.is_super_admin() or app.e_dono(p_empresa)) then raise exception 'Sem permissão.' using errcode = '42501'; end if;
  return (select count(*) from app.publico_campanha(p_empresa, p_publico, p_dias));
end;
$$;

create or replace function public.criar_campanha(p_empresa uuid, p_nome text, p_publico text, p_dias int, p_texto text)
returns int language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_n int := 0;
  r record;
  v_inst uuid;
begin
  if not (app.is_super_admin() or app.e_dono(p_empresa)) then raise exception 'Só o dono envia campanhas.' using errcode = '42501'; end if;
  if not app.recurso_empresa(p_empresa, 'campanhas') then raise exception 'O plano atual não inclui campanhas.' using errcode = 'P0001'; end if;
  if length(trim(coalesce(p_texto, ''))) < 5 then raise exception 'Escreva a mensagem da campanha.' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.whatsapp_instancias i where i.empresa_id = p_empresa and i.status = 'conectado') then
    raise exception 'Conecte o WhatsApp antes de enviar campanhas.' using errcode = 'P0001';
  end if;
  insert into public.campanhas (empresa_id, nome, publico, dias, texto, criado_por)
  values (p_empresa, coalesce(nullif(trim(p_nome), ''), 'Campanha'), p_publico, p_dias, p_texto, auth.uid())
  returning id into v_id;
  for r in select * from app.publico_campanha(p_empresa, p_publico, p_dias) limit 1000 loop
    v_inst := app.instancia_para_cliente(p_empresa, r.id);
    continue when v_inst is null;
    -- espaça os envios (cerca de 1 a cada 20 segundos) para não bloquear o número
    perform app.enfileirar(p_empresa, v_inst, r.id, null, 'campanha', r.telefone, app.render(p_texto, app.vars_cliente(r.id)), v_id, now() + make_interval(secs => v_n * 20));
    v_n := v_n + 1;
  end loop;
  update public.campanhas set total = v_n where id = v_id;
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------
-- Permissões e RLS
-- ---------------------------------------------------------------------
revoke all on app.config, app.whatsapp_segredos, app.conversas_bot from public, anon, authenticated;

grant select on public.whatsapp_instancias, public.modelos_mensagem, public.mensagens, public.campanhas to authenticated;
grant update (ativo, texto, horas, dias) on public.modelos_mensagem to authenticated;
revoke all on public.whatsapp_instancias, public.modelos_mensagem, public.mensagens, public.campanhas from anon;

alter table public.whatsapp_instancias enable row level security;
alter table public.modelos_mensagem    enable row level security;
alter table public.mensagens           enable row level security;
alter table public.campanhas           enable row level security;

create policy whatsapp_instancias_ler on public.whatsapp_instancias for select to authenticated
  using ((select app.is_super_admin()) or app.e_membro(empresa_id));
create policy modelos_ler on public.modelos_mensagem for select to authenticated
  using ((select app.is_super_admin()) or app.e_membro(empresa_id));
create policy modelos_editar on public.modelos_mensagem for update to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id))
  with check ((select app.is_super_admin()) or app.e_dono(empresa_id));
create policy mensagens_ler on public.mensagens for select to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id)
         or (app.tem_papel(empresa_id, array['recepcao']::public.papel_membro[]) and (unidade_id is null or app.ve_unidade(unidade_id))));
create policy campanhas_ler on public.campanhas for select to authenticated
  using ((select app.is_super_admin()) or app.e_dono(empresa_id));

revoke execute on function
  public.whatsapp_ciclo(text, int), public.whatsapp_resultado_envio(uuid, boolean, text, text),
  public.whatsapp_instancia_por_token(text), public.whatsapp_segredo_instancia(uuid),
  public.whatsapp_atualizar_conexao(uuid, text, text), public.whatsapp_processar_entrada(uuid, text, text, text, text),
  public.whatsapp_acesso_instancia(uuid, boolean), public.contar_publico_campanha(uuid, text, int), public.criar_campanha(uuid, text, text, int, text)
from public, anon;
grant execute on function
  public.whatsapp_ciclo(text, int), public.whatsapp_resultado_envio(uuid, boolean, text, text),
  public.whatsapp_instancia_por_token(text), public.whatsapp_segredo_instancia(uuid),
  public.whatsapp_atualizar_conexao(uuid, text, text), public.whatsapp_processar_entrada(uuid, text, text, text, text)
to service_role;
grant execute on function
  public.whatsapp_acesso_instancia(uuid, boolean), public.contar_publico_campanha(uuid, text, int), public.criar_campanha(uuid, text, text, int, text)
to authenticated, service_role;

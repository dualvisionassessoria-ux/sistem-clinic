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

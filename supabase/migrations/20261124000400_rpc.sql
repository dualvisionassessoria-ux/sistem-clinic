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

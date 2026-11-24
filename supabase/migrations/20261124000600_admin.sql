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

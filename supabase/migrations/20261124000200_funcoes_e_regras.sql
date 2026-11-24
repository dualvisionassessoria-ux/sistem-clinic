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

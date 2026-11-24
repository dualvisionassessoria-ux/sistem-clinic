-- =====================================================================
-- Teste de isolamento multi-empresa (RLS)
-- Rodar num banco de TESTE com as migrações aplicadas:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/isolamento.sql
-- Tudo roda dentro de uma transação e é desfeito no final (rollback).
-- =====================================================================
\set ON_ERROR_STOP 1
begin;

create schema test;
grant usage on schema test to authenticated, anon;

-- executa um comando e devolve true se ele FALHOU (erro ou nenhuma linha afetada)
create function test.falha(p_sql text) returns boolean language plpgsql as $$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n = 0;
exception when others then
  return true;
end;
$$;
grant execute on function test.falha(text) to authenticated, anon;

create function test.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if p_cond is distinct from true then
    raise exception 'FALHOU: %', p_msg;
  end if;
  raise notice 'ok - %', p_msg;
end;
$$;
grant execute on function test.ok(boolean, text) to authenticated, anon;

-- usuários fictícios
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'admin@teste.com',  '{"nome":"Admin"}'),
  ('00000000-0000-0000-0000-0000000000a1', 'donoa@teste.com',  '{"nome":"Dono A"}'),
  ('00000000-0000-0000-0000-0000000000a2', 'recepa@teste.com', '{"nome":"Recepção A"}'),
  ('00000000-0000-0000-0000-0000000000a3', 'profa@teste.com',  '{"nome":"Prof A"}'),
  ('00000000-0000-0000-0000-0000000000b1', 'donob@teste.com',  '{"nome":"Dono B"}');
insert into public.admins_plataforma (user_id) values ('00000000-0000-0000-0000-00000000000a');

select test.ok((select count(*) from public.perfis) = 5, 'perfil criado automaticamente para cada usuário');

-- variáveis
\set ADMIN  '00000000-0000-0000-0000-00000000000a'
\set DONOA  '00000000-0000-0000-0000-0000000000a1'
\set RECEPA '00000000-0000-0000-0000-0000000000a2'
\set PROFA  '00000000-0000-0000-0000-0000000000a3'
\set DONOB  '00000000-0000-0000-0000-0000000000b1'

-- ---------------------------------------------------------------- Dono A
select set_config('request.jwt.claims', json_build_object('sub', :'DONOA')::text, true);
set local role authenticated;

select public.criar_empresa('Clínica A', 'odontologia', 'essencial', 'Centro') as empresa_a \gset
select id as unidade_a1 from public.unidades where empresa_id = :'empresa_a' \gset
select test.ok((select count(*) from public.unidades) = 1, 'dono A vê a própria unidade');
select test.ok((select count(*) from public.horarios_unidade) = 6, 'horário padrão criado');
select test.ok(test.falha(format($q$insert into public.unidades (empresa_id, nome) values (%L, 'Filial')$q$, :'empresa_a')),
  'plano Essencial bloqueia a 2ª unidade');
select test.ok(test.falha(format($q$update public.empresas set status_assinatura = 'ativa' where id = %L$q$, :'empresa_a')),
  'dono não altera o próprio status de assinatura');
select test.ok(test.falha(format($q$update public.empresas set plano_id = (select id from public.planos where codigo='premium') where id = %L$q$, :'empresa_a')),
  'dono não altera o próprio plano');
select test.ok(not test.falha(format($q$update public.empresas set nome = 'Clínica A Sorriso' where id = %L$q$, :'empresa_a')),
  'dono altera o nome da empresa');

insert into public.servicos (empresa_id, nome, duracao_min, preco)
values (:'empresa_a', 'Limpeza', 40, 150) returning id as servico_a \gset
insert into public.profissionais (empresa_id, nome) values (:'empresa_a', 'Dra. Ana') returning id as prof_a \gset
insert into public.profissional_unidades (empresa_id, profissional_id, unidade_id) values (:'empresa_a', :'prof_a', :'unidade_a1');
insert into public.servico_profissionais (empresa_id, servico_id, profissional_id) values (:'empresa_a', :'servico_a', :'prof_a');
insert into public.jornadas (empresa_id, profissional_id, unidade_id, dia_semana, inicio, fim)
values (:'empresa_a', :'prof_a', :'unidade_a1', 1, '08:00', '17:00');

select public.convidar_usuario(:'empresa_a', 'RecepA@teste.com', 'recepcao', array[:'unidade_a1']::uuid[]) as conv_recep \gset
select public.convidar_usuario(:'empresa_a', 'profa@teste.com', 'profissional', '{}', false, :'prof_a') as conv_prof \gset
select test.ok(test.falha(format($q$update public.membros set papel = 'recepcao' where user_id = %L$q$, :'DONOA')),
  'último dono não pode deixar de ser dono');
reset role;

-- ---------------------------------------------------------------- Admin
select set_config('request.jwt.claims', json_build_object('sub', :'ADMIN')::text, true);
set local role authenticated;
select public.definir_plano_empresa(:'empresa_a', 'profissional');
select test.ok((select count(*) from public.admin_listar_empresas()) = 1, 'admin lista empresas');
reset role;

-- ---------------------------------------------------------------- Dono A (plano Profissional)
select set_config('request.jwt.claims', json_build_object('sub', :'DONOA')::text, true);
set local role authenticated;
insert into public.unidades (empresa_id, nome) values (:'empresa_a', 'Filial') returning id as unidade_a2 \gset
select test.ok((select count(*) from public.unidades) = 2, 'após upgrade, 2ª unidade permitida');
reset role;

-- ---------------------------------------------------------------- Recepção A
select set_config('request.jwt.claims', json_build_object('sub', :'RECEPA')::text, true);
set local role authenticated;
select test.ok((select count(*) from public.unidades) = 0, 'antes de aceitar o convite, recepção não vê nada');
select test.ok(test.falha(format($q$select public.aceitar_convite(%L)$q$, :'conv_prof')),
  'não aceita convite de outro e-mail');
select public.aceitar_convite(:'conv_recep');
select test.ok((select count(*) from public.unidades) = 1, 'recepção vê só a unidade vinculada');
select test.ok((select count(*) from public.servicos) = 1, 'recepção vê serviços da empresa');
select test.ok(test.falha(format($q$insert into public.servicos (empresa_id, nome, duracao_min) values (%L, 'X', 30)$q$, :'empresa_a')),
  'recepção não cria serviço');
select test.ok(test.falha(format($q$update public.servicos set preco = 1 where id = %L$q$, :'servico_a')),
  'recepção não altera preço');
select test.ok(test.falha($q$insert into public.membros (empresa_id, user_id, papel) select empresa_id, user_id, 'dono' from public.membros limit 1$q$),
  'recepção não se promove a dono');
select test.ok(test.falha(format($q$update public.membros set papel = 'dono' where user_id = %L$q$, :'RECEPA')),
  'recepção não altera o próprio papel');
select test.ok((select count(*) from public.convites) = 0, 'recepção não vê convites');
reset role;

-- ---------------------------------------------------------------- Profissional A
select set_config('request.jwt.claims', json_build_object('sub', :'PROFA')::text, true);
set local role authenticated;
select public.aceitar_convite(:'conv_prof');
select test.ok((select membro_id is not null from public.profissionais where id = :'prof_a'), 'convite vincula login ao profissional');
select test.ok(test.falha(format($q$update public.jornadas set fim = '20:00' where profissional_id = %L$q$, :'prof_a')),
  'profissional não edita a própria jornada');
select test.ok((select count(*) from public.perfis) = 3, 'profissional vê perfis só dos colegas da empresa');
reset role;

-- ---------------------------------------------------------------- Dono B (outra empresa)
select set_config('request.jwt.claims', json_build_object('sub', :'DONOB')::text, true);
set local role authenticated;
select public.criar_empresa('Salão B', 'salao', 'profissional') as empresa_b \gset
insert into public.servicos (empresa_id, nome, duracao_min) values (:'empresa_b', 'Corte', 30) returning id as servico_b \gset

select test.ok((select count(*) from public.empresas) = 1, 'dono B vê só a própria empresa');
select test.ok((select count(*) from public.unidades where empresa_id = :'empresa_a') = 0, 'dono B não vê unidades de A');
select test.ok((select count(*) from public.servicos where empresa_id = :'empresa_a') = 0, 'dono B não vê serviços de A');
select test.ok((select count(*) from public.profissionais where empresa_id = :'empresa_a') = 0, 'dono B não vê profissionais de A');
select test.ok((select count(*) from public.membros where empresa_id = :'empresa_a') = 0, 'dono B não vê equipe de A');
select test.ok((select count(*) from public.perfis) = 1, 'dono B não vê perfis de A');
select test.ok(test.falha(format($q$insert into public.unidades (empresa_id, nome) values (%L, 'Invasão')$q$, :'empresa_a')),
  'dono B não cria unidade em A');
select test.ok(test.falha(format($q$update public.servicos set preco = 0 where id = %L$q$, :'servico_a')),
  'dono B não altera serviço de A');
select test.ok(test.falha(format($q$delete from public.servicos where id = %L$q$, :'servico_a')),
  'dono B não apaga serviço de A');
select test.ok(test.falha(format($q$insert into public.servico_profissionais (empresa_id, servico_id, profissional_id) values (%L, %L, %L)$q$, :'empresa_b', :'servico_b', :'prof_a')),
  'dono B não liga profissional de A ao seu serviço');
select test.ok(test.falha(format($q$update public.servicos set empresa_id = %L where id = %L$q$, :'empresa_a', :'servico_b')),
  'dono B não move registro para a empresa A');
select test.ok(test.falha(format($q$select public.convidar_usuario(%L, 'x@x.com', 'dono')$q$, :'empresa_a')),
  'dono B não convida para a empresa A');
select test.ok(test.falha(format($q$select public.definir_status_assinatura(%L, 'ativa')$q$, :'empresa_b')),
  'dono não usa função de super-admin');
select test.ok(test.falha('select * from public.admin_listar_empresas()'), 'dono não lista todas as empresas');
reset role;

-- ---------------------------------------------------------------- Admin bloqueia A
select set_config('request.jwt.claims', json_build_object('sub', :'ADMIN')::text, true);
set local role authenticated;
select test.ok((select count(*) from public.empresas) = 2, 'admin vê todas as empresas');
select public.definir_status_assinatura(:'empresa_a', 'bloqueada');
reset role;

select set_config('request.jwt.claims', json_build_object('sub', :'DONOA')::text, true);
set local role authenticated;
select test.ok((select status_assinatura from public.empresas where id = :'empresa_a') = 'bloqueada', 'dono A vê o aviso de bloqueio');
select test.ok((select count(*) from public.unidades) = 0, 'empresa bloqueada: dados ficam inacessíveis');
select test.ok(test.falha(format($q$insert into public.servicos (empresa_id, nome, duracao_min) values (%L, 'Y', 30)$q$, :'empresa_a')),
  'empresa bloqueada: não grava');
reset role;

-- ---------------------------------------------------------------- Visitante sem login
select set_config('request.jwt.claims', '', true);
set local role anon;
select test.ok((select count(*) from public.planos) = 3, 'visitante vê os planos');
select test.ok(test.falha('select 1 from public.empresas'), 'visitante não lê empresas');
select test.ok((select empresa_nome from public.ver_convite(:'conv_recep')) = 'Clínica A Sorriso', 'visitante vê dados do convite pelo token');
reset role;

select 'TODOS OS TESTES PASSARAM' as resultado;
rollback;

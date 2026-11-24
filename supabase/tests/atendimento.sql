-- =====================================================================
-- Testes da Etapa 2: pacientes, agenda, bloqueios, financeiro e relatório
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/atendimento.sql
-- Tudo roda numa transação e é desfeito no final (rollback).
-- =====================================================================
\set ON_ERROR_STOP 1
begin;

create schema test;
grant usage on schema test to authenticated, anon;
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
create function test.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if p_cond is distinct from true then raise exception 'FALHOU: %', p_msg; end if;
  raise notice 'ok - %', p_msg;
end;
$$;
grant execute on all functions in schema test to authenticated, anon;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'donoa@teste.com',  '{"nome":"Dono A"}'),
  ('00000000-0000-0000-0000-0000000000a2', 'recepa@teste.com', '{"nome":"Recepção A"}'),
  ('00000000-0000-0000-0000-0000000000a3', 'profa@teste.com',  '{"nome":"Prof A"}'),
  ('00000000-0000-0000-0000-0000000000b1', 'donob@teste.com',  '{"nome":"Dono B"}');
\set DONOA  '00000000-0000-0000-0000-0000000000a1'
\set RECEPA '00000000-0000-0000-0000-0000000000a2'
\set PROFA  '00000000-0000-0000-0000-0000000000a3'
\set DONOB  '00000000-0000-0000-0000-0000000000b1'
select (current_date + 7)::text as dia \gset

-- ---------------------------------------------------------------- Dono A monta a clínica
select set_config('request.jwt.claims', json_build_object('sub', :'DONOA')::text, true);
set local role authenticated;
select public.criar_empresa('Clínica A', 'clinica', 'profissional', 'Centro') as empresa_a \gset
select id as unid1 from public.unidades where empresa_id = :'empresa_a' \gset
insert into public.unidades (empresa_id, nome) values (:'empresa_a', 'Filial') returning id as unid2 \gset
insert into public.servicos (empresa_id, nome, duracao_min, preco) values (:'empresa_a', 'Consulta', 60, 200) returning id as serv \gset
insert into public.profissionais (empresa_id, nome) values (:'empresa_a', 'Dra. Ana') returning id as prof1 \gset
insert into public.profissionais (empresa_id, nome) values (:'empresa_a', 'Dr. Beto') returning id as prof2 \gset
insert into public.profissional_unidades (empresa_id, profissional_id, unidade_id)
  values (:'empresa_a', :'prof1', :'unid1'), (:'empresa_a', :'prof2', :'unid2');
insert into public.jornadas (empresa_id, profissional_id, unidade_id, dia_semana, inicio, fim)
  select :'empresa_a', :'prof1', :'unid1', d, '08:00', '12:00' from generate_series(0, 6) d;
select public.convidar_usuario(:'empresa_a', 'recepa@teste.com', 'recepcao', array[:'unid1']::uuid[]) as conv_recep \gset
select public.convidar_usuario(:'empresa_a', 'profa@teste.com', 'profissional', '{}', false, :'prof1') as conv_prof \gset

insert into public.clientes (empresa_id, nome, telefone, data_nascimento)
  values (:'empresa_a', 'Maria Souza', '(11) 99999-8888', '1990-05-10') returning id as cli1 \gset
insert into public.clientes (empresa_id, nome) values (:'empresa_a', 'João Lima') returning id as cli2 \gset
select test.ok((select telefone from public.clientes where id = :'cli1') = '5511999998888', 'telefone do paciente normalizado para WhatsApp');
select test.ok(test.falha(format($q$insert into public.clientes (empresa_id, nome, telefone) values (%L, 'Outra', '11 99999 8888')$q$, :'empresa_a')),
  'não duplica paciente com o mesmo telefone');

select test.ok((select count(*) from public.horarios_livres(:'unid1', :'prof1', :'serv', :'dia'::date)) = 13,
  'horários livres: 08:00 a 11:00 de 15 em 15 min para consulta de 1h');

insert into public.agendamentos (empresa_id, unidade_id, profissional_id, cliente_id, servico_id, inicio, fim, valor)
  values (:'empresa_a', :'unid1', :'prof1', :'cli1', :'serv',
          (:'dia' || ' 09:00')::timestamp at time zone 'America/Sao_Paulo', (:'dia' || ' 10:00')::timestamp at time zone 'America/Sao_Paulo', 200)
  returning id as ag1 \gset
select test.ok((select count(*) from public.horarios_livres(:'unid1', :'prof1', :'serv', :'dia'::date)) = 6,
  'horário ocupado sai da lista de livres');
select test.ok(test.falha(format($q$insert into public.agendamentos (empresa_id, unidade_id, profissional_id, cliente_id, inicio, fim)
  values (%L, %L, %L, %L, %L::timestamptz + interval '30 min', %L::timestamptz + interval '90 min')$q$,
  :'empresa_a', :'unid1', :'prof1', :'cli2', (:'dia' || ' 09:00')::timestamp at time zone 'America/Sao_Paulo', (:'dia' || ' 09:00')::timestamp at time zone 'America/Sao_Paulo')),
  'não marca dois pacientes no mesmo horário do profissional');
insert into public.agendamentos (empresa_id, unidade_id, profissional_id, cliente_id, inicio, fim, encaixe)
  values (:'empresa_a', :'unid1', :'prof1', :'cli2',
          (:'dia' || ' 09:30')::timestamp at time zone 'America/Sao_Paulo', (:'dia' || ' 09:45')::timestamp at time zone 'America/Sao_Paulo', true)
  returning id as ag_encaixe \gset
select test.ok(:'ag_encaixe' is not null, 'encaixe pode sobrepor horário');
insert into public.agendamentos (empresa_id, unidade_id, profissional_id, cliente_id, inicio, fim)
  values (:'empresa_a', :'unid2', :'prof2', :'cli2',
          (:'dia' || ' 14:00')::timestamp at time zone 'America/Sao_Paulo', (:'dia' || ' 15:00')::timestamp at time zone 'America/Sao_Paulo')
  returning id as ag_filial \gset

insert into public.bloqueios_agenda (empresa_id, unidade_id, profissional_id, inicio, fim, motivo)
  values (:'empresa_a', :'unid1', null, (:'dia' || ' 11:00')::timestamp at time zone 'America/Sao_Paulo', (:'dia' || ' 12:00')::timestamp at time zone 'America/Sao_Paulo', 'Reunião');
select test.ok((select count(*) from public.horarios_livres(:'unid1', :'prof1', :'serv', :'dia'::date)) = 2,
  'bloqueio da unidade sai da lista de livres');
select test.ok((select count(*) from public.historico_status where agendamento_id = :'ag1') = 1, 'histórico registra a criação');
reset role;

-- ---------------------------------------------------------------- Recepção A (só unidade 1)
select set_config('request.jwt.claims', json_build_object('sub', :'RECEPA')::text, true);
set local role authenticated;
select public.aceitar_convite(:'conv_recep');
select test.ok((select count(*) from public.agendamentos) = 2, 'recepção vê só a agenda da própria unidade');
select test.ok((select count(*) from public.clientes) = 2, 'recepção vê os pacientes da empresa');
select test.ok(test.falha(format($q$insert into public.agendamentos (empresa_id, unidade_id, profissional_id, cliente_id, inicio, fim)
  values (%L, %L, %L, %L, now() + interval '20 days', now() + interval '20 days 1 hour')$q$, :'empresa_a', :'unid2', :'prof2', :'cli1')),
  'recepção não marca em outra unidade');
select public.atualizar_status_agendamento(:'ag1', 'confirmado');
select test.ok((select confirmado_em is not null from public.agendamentos where id = :'ag1'), 'confirmação carimba a data');
select test.ok(test.falha(format($q$select public.atualizar_status_agendamento(%L, 'cancelado')$q$, :'ag_filial')),
  'recepção não altera agendamento de outra unidade');
select test.ok(test.falha(format($q$delete from public.clientes where id = %L$q$, :'cli2')), 'recepção não apaga paciente');
reset role;

-- ---------------------------------------------------------------- Profissional A (Dra. Ana)
select set_config('request.jwt.claims', json_build_object('sub', :'PROFA')::text, true);
set local role authenticated;
select public.aceitar_convite(:'conv_prof');
select test.ok((select count(*) from public.agendamentos) = 2, 'profissional vê só os próprios atendimentos');
select test.ok((select count(*) from public.clientes) = 2, 'profissional vê só os pacientes que atende');
select public.atualizar_status_agendamento(:'ag1', 'atendido');
select test.ok((select ultima_visita_em is not null from public.clientes where id = :'cli1'), 'atendido atualiza a última visita do paciente');
select test.ok(test.falha(format($q$select public.atualizar_status_agendamento(%L, 'cancelado')$q$, :'ag_encaixe')),
  'profissional não cancela agendamento');
select test.ok(test.falha(format($q$update public.agendamentos set valor = 0 where id = %L$q$, :'ag1')), 'profissional não altera valor');
select test.ok(test.falha(format($q$insert into public.pagamentos (empresa_id, unidade_id, valor) values (%L, %L, 10)$q$, :'empresa_a', :'unid1')),
  'profissional não lança recebimento');
reset role;

-- ---------------------------------------------------------------- Dono A: financeiro e relatório
select set_config('request.jwt.claims', json_build_object('sub', :'DONOA')::text, true);
set local role authenticated;
insert into public.pagamentos (empresa_id, unidade_id, agendamento_id, cliente_id, profissional_id, valor, forma, recebido_em)
  values (:'empresa_a', :'unid1', :'ag1', :'cli1', :'prof1', 200, 'pix', (:'dia' || ' 10:00')::timestamp at time zone 'America/Sao_Paulo');
select public.relatorio_periodo(:'empresa_a', :'dia'::date::timestamptz - interval '1 day', :'dia'::date::timestamptz + interval '2 days') as rel \gset
select test.ok((:'rel'::jsonb ->> 'faturamento')::numeric = 200, 'relatório soma o faturamento');
select test.ok((:'rel'::jsonb ->> 'agendamentos')::int = 3, 'relatório conta agendamentos');
select test.ok(jsonb_array_length(:'rel'::jsonb -> 'por_profissional') = 2, 'relatório por profissional');
reset role;

select set_config('request.jwt.claims', json_build_object('sub', :'PROFA')::text, true);
set local role authenticated;
select public.relatorio_periodo(:'empresa_a', :'dia'::date::timestamptz - interval '1 day', :'dia'::date::timestamptz + interval '2 days') as relp \gset
select test.ok(jsonb_array_length(:'relp'::jsonb -> 'por_profissional') = 1 and (:'relp'::jsonb ->> 'agendamentos')::int = 2,
  'profissional vê só os próprios números');
reset role;

-- ---------------------------------------------------------------- Dono B (outra empresa)
select set_config('request.jwt.claims', json_build_object('sub', :'DONOB')::text, true);
set local role authenticated;
select public.criar_empresa('Salão B', 'salao', 'essencial') as empresa_b \gset
select id as unidb from public.unidades where empresa_id = :'empresa_b' \gset
select test.ok((select count(*) from public.clientes) = 0, 'dono B não vê pacientes de A');
select test.ok((select count(*) from public.agendamentos) = 0, 'dono B não vê agenda de A');
select test.ok((select count(*) from public.pagamentos) = 0, 'dono B não vê recebimentos de A');
select test.ok(test.falha(format($q$select public.horarios_livres(%L, %L, %L, %L)$q$, :'unid1', :'prof1', :'serv', :'dia')), 'dono B não consulta horários de A');
select test.ok(test.falha(format($q$select public.relatorio_periodo(%L, now() - interval '1 year', now())$q$, :'empresa_a')), 'dono B não lê relatório de A');
select test.ok(test.falha(format($q$insert into public.agendamentos (empresa_id, unidade_id, profissional_id, cliente_id, inicio, fim)
  values (%L, %L, %L, %L, now() + interval '30 days', now() + interval '30 days 1 hour')$q$, :'empresa_b', :'unidb', :'prof1', :'cli1')),
  'dono B não usa profissional e paciente de A');
select test.ok(test.falha(format($q$select public.atualizar_status_agendamento(%L, 'cancelado')$q$, :'ag1')), 'dono B não altera agendamento de A');
reset role;

select set_config('request.jwt.claims', '', true);
set local role anon;
select test.ok(test.falha('select 1 from public.clientes'), 'visitante não lê pacientes');
reset role;

select 'TODOS OS TESTES PASSARAM' as resultado;
rollback;

-- =====================================================================
-- Testes do WhatsApp: mensagens automáticas, fila, respostas SIM/NÃO,
-- robô de marcação, campanhas e permissões. Desfeito no final (rollback).
-- =====================================================================
\set ON_ERROR_STOP 1
begin;
create schema test;
grant usage on schema test to authenticated, anon, service_role;
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
grant execute on all functions in schema test to authenticated, anon, service_role;
-- no Supabase a service_role já tem acesso às tabelas públicas
grant select, insert, update, delete on all tables in schema public to service_role;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'donoa@teste.com', '{"nome":"Dono A"}'),
  ('00000000-0000-0000-0000-0000000000b1', 'donob@teste.com', '{"nome":"Dono B"}');
\set DONOA '00000000-0000-0000-0000-0000000000a1'
\set DONOB '00000000-0000-0000-0000-0000000000b1'
\set SERVICO '{"role":"service_role"}'

-- ---------------------------------------------------------------- Dono A (Premium)
select set_config('request.jwt.claims', json_build_object('sub', :'DONOA')::text, true);
set local role authenticated;
select public.criar_empresa('Clínica A', 'clinica', 'premium', 'Centro') as empresa_a \gset
select id as unid from public.unidades where empresa_id = :'empresa_a' \gset
update public.unidades set link_avaliacao_google = 'https://g.page/r/teste', endereco = 'Rua A, 1', cidade = 'São Paulo' where id = :'unid';
insert into public.servicos (empresa_id, nome, duracao_min, preco) values (:'empresa_a', 'Consulta', 30, 120) returning id as serv \gset
insert into public.profissionais (empresa_id, nome) values (:'empresa_a', 'Dra. Ana') returning id as prof \gset
insert into public.profissional_unidades (empresa_id, profissional_id, unidade_id) values (:'empresa_a', :'prof', :'unid');
insert into public.jornadas (empresa_id, profissional_id, unidade_id, dia_semana, inicio, fim)
  select :'empresa_a', :'prof', :'unid', d, '00:00', '23:59' from generate_series(0, 6) d;
insert into public.clientes (empresa_id, nome, telefone) values (:'empresa_a', 'Maria Souza', '(11) 99999-8888') returning id as cli \gset

select test.ok((select count(*) from public.modelos_mensagem where empresa_id = :'empresa_a') = 7, 'textos padrão criados com a empresa');
select test.ok(not test.falha(format($q$update public.modelos_mensagem set texto = 'Oi {{primeiro_nome}}, confirma {{data}} {{hora}}? SIM ou NÃO' where empresa_id = %L and tipo = 'confirmacao'$q$, :'empresa_a')),
  'dono edita o texto da confirmação');
select * from public.whatsapp_acesso_instancia(:'unid', true) \gset inst_
select test.ok(:'inst_status' = 'desconectado', 'dono cria a instância da unidade');
select test.ok(test.falha('select * from public.whatsapp_ciclo(''x'')'), 'usuário não roda o ciclo de envio');
select test.ok(test.falha(format($q$select * from public.whatsapp_processar_entrada(%L, '5511999998888', 'x', 'sim')$q$, :'inst_id')), 'usuário não simula mensagem recebida');
select test.ok(test.falha('select valor from app.config'), 'usuário não lê segredos');

insert into public.agendamentos (empresa_id, unidade_id, profissional_id, cliente_id, servico_id, inicio, fim, valor, criado_em)
  values (:'empresa_a', :'unid', :'prof', :'cli', :'serv', date_trunc('minute', now()) + interval '20 hours', date_trunc('minute', now()) + interval '20 hours 30 min', 120, now() - interval '1 day')
  returning id as ag1 \gset
insert into public.agendamentos (empresa_id, unidade_id, profissional_id, cliente_id, servico_id, inicio, fim, valor, criado_em)
  values (:'empresa_a', :'unid', :'prof', :'cli', :'serv', date_trunc('minute', now()) + interval '90 min', date_trunc('minute', now()) + interval '120 min', 120, now() - interval '1 day')
  returning id as ag2 \gset
reset role;

-- ---------------------------------------------------------------- Edge Function (service_role)
select (select valor from app.config where chave = 'cron_secret') as segredo \gset
select set_config('request.jwt.claims', :'SERVICO', true);
set local role service_role;
select test.ok(test.falha('select * from public.whatsapp_ciclo(''errado'')'), 'ciclo exige o segredo do agendador');
select test.ok((select count(*) from public.whatsapp_ciclo(:'segredo')) = 0, 'sem WhatsApp conectado nada é gerado');
select public.whatsapp_atualizar_conexao(:'inst_id', 'conectado', '5511900001111');
select test.ok((select count(*) from public.whatsapp_ciclo(:'segredo')) = 2, 'gera confirmação (24h) e lembrete (2h)');
select test.ok((select texto from public.mensagens where agendamento_id = :'ag1' and tipo = 'confirmacao') like 'Oi Maria, confirma%', 'texto usa as variáveis');
select test.ok((select count(*) from public.whatsapp_ciclo(:'segredo')) = 0, 'não envia duas vezes');
select public.whatsapp_resultado_envio(id, true, null, 'abc') from public.mensagens where tipo in ('confirmacao', 'lembrete');
select test.ok((select count(*) from public.mensagens where status = 'enviada') = 2, 'envio registrado');

-- resposta SIM (número sem o nono dígito, como o WhatsApp às vezes manda)
select test.ok((select texto from public.whatsapp_processar_entrada(:'inst_id', '551199998888', 'Maria', 'Sim, confirmo!')) like 'Perfeito, Maria!%', 'responde a confirmação');
select test.ok((select status from public.agendamentos where id = :'ag1') = 'confirmado', 'SIM confirma o agendamento');
select test.ok((select origem from public.historico_status where agendamento_id = :'ag1' order by id desc limit 1) = 'whatsapp', 'histórico marca origem WhatsApp');

-- resposta NÃO
update public.agendamentos set status = 'agendado' where id = :'ag1';
select test.ok((select count(*) from public.whatsapp_processar_entrada(:'inst_id', '5511999998888', 'Maria', 'não')) = 2, 'NÃO responde e oferece remarcar');
select test.ok((select status from public.agendamentos where id = :'ag1') = 'cancelado', 'NÃO cancela o agendamento');

-- robô de marcação: número novo
select test.ok((select texto from public.whatsapp_processar_entrada(:'inst_id', '5521988887777', 'Carlos', 'oi')) like '%1* - Marcar horário%', 'robô mostra o menu');
select test.ok((select texto from public.whatsapp_processar_entrada(:'inst_id', '5521988887777', 'Carlos', '1')) like 'Qual serviço%Consulta%', 'robô lista serviços');
select test.ok((select texto from public.whatsapp_processar_entrada(:'inst_id', '5521988887777', 'Carlos', '1')) like 'Para qual dia?%', 'com um profissional, pula direto para os dias');
select test.ok((select texto from public.whatsapp_processar_entrada(:'inst_id', '5521988887777', 'Carlos', '1')) like 'Horários livres em%', 'robô lista horários');
select test.ok((select texto from public.whatsapp_processar_entrada(:'inst_id', '5521988887777', 'Carlos', '1')) like '%nome completo%', 'paciente novo: pede o nome');
select test.ok((select texto from public.whatsapp_processar_entrada(:'inst_id', '5521988887777', 'Carlos', 'carlos eduardo')) like 'Confirma o agendamento?%', 'mostra o resumo');
select test.ok((select texto from public.whatsapp_processar_entrada(:'inst_id', '5521988887777', 'Carlos', '1')) like 'Pronto, Carlos!%', 'confirma a marcação');
select test.ok((select count(*) from public.agendamentos a join public.clientes c on c.id = a.cliente_id
  where c.nome = 'Carlos Eduardo' and a.origem = 'whatsapp' and a.status = 'confirmado') = 1, 'agendamento criado pelo WhatsApp com paciente novo');
select test.ok((select texto from public.whatsapp_processar_entrada(:'inst_id', '5521988887777', 'Carlos', '2')) like 'Seus próximos horários:%', 'paciente consulta os próprios horários');
select test.ok((select texto from public.whatsapp_processar_entrada(:'inst_id', '5521988887777', 'Carlos', '1')) like 'Deseja cancelar%', 'pede confirmação para cancelar');
select test.ok((select texto from public.whatsapp_processar_entrada(:'inst_id', '5521988887777', 'Carlos', '1')) like 'Horário cancelado%', 'cancela pelo robô');
select test.ok((select texto from public.whatsapp_processar_entrada(:'inst_id', '5521988887777', 'Carlos', '3')) like 'Certo! Avisei a recepção%', 'pede atendimento humano');
select test.ok((select count(*) from public.whatsapp_processar_entrada(:'inst_id', '5521988887777', 'Carlos', 'olá?')) = 0, 'robô fica quieto enquanto a recepção atende');
select test.ok((select count(*) from public.mensagens where direcao = 'entrada') = 14, 'mensagens recebidas ficam registradas');

-- pós-atendimento com avaliação
update public.agendamentos set status = 'atendido', inicio = now() - interval '4 hours', fim = now() - interval '3 hours' where id = :'ag2';
select app.gerar_mensagens_automaticas();
select test.ok(exists (select 1 from public.mensagens where agendamento_id = :'ag2' and tipo = 'pos_atendimento' and texto like '%https://g.page/r/teste%')
  or extract(hour from now() at time zone 'America/Sao_Paulo') not between 8 and 20, 'pós-atendimento pede avaliação no Google');
reset role;

-- ---------------------------------------------------------------- Campanha (dono)
select set_config('request.jwt.claims', json_build_object('sub', :'DONOA')::text, true);
set local role authenticated;
select test.ok(public.contar_publico_campanha(:'empresa_a', 'todos') = 2, 'conta o público da campanha');
select test.ok(public.criar_campanha(:'empresa_a', 'Novembro', 'todos', null, 'Oi {{primeiro_nome}}, temos novidades na {{empresa}}!') = 2, 'campanha entra na fila');
select test.ok((select count(*) from public.mensagens where tipo = 'campanha' and texto like 'Oi Maria, temos novidades na Clínica A!') = 1, 'campanha personaliza o texto');
select test.ok((select count(*) from public.mensagens) > 0, 'dono vê o registro de mensagens');
reset role;

-- ---------------------------------------------------------------- Dono B (Essencial)
select set_config('request.jwt.claims', json_build_object('sub', :'DONOB')::text, true);
set local role authenticated;
select public.criar_empresa('Salão B', 'salao', 'essencial') as empresa_b \gset
select id as unidb from public.unidades where empresa_id = :'empresa_b' \gset
select test.ok((select count(*) from public.mensagens) = 0, 'dono B não vê mensagens de A');
select test.ok((select count(*) from public.whatsapp_instancias) = 0, 'dono B não vê o WhatsApp de A');
select test.ok(test.falha(format($q$update public.modelos_mensagem set texto = 'x' where empresa_id = %L$q$, :'empresa_a')), 'dono B não altera textos de A');
select test.ok(test.falha(format($q$select * from public.whatsapp_acesso_instancia(%L, true)$q$, :'unid')), 'dono B não conecta WhatsApp em A');
select test.ok(test.falha(format($q$select public.criar_campanha(%L, 'x', 'todos', null, 'teste de campanha')$q$, :'empresa_b')), 'plano Essencial não tem campanhas');
select * from public.whatsapp_acesso_instancia(:'unidb', true) \gset instb_
reset role;
select set_config('request.jwt.claims', :'SERVICO', true);
set local role service_role;
select public.whatsapp_atualizar_conexao(:'instb_id', 'conectado');
select test.ok((select count(*) from public.whatsapp_processar_entrada(:'instb_id', '5531977776666', 'Ana', 'oi')) = 0, 'sem Premium o robô não responde');
reset role;

select 'TODOS OS TESTES PASSARAM' as resultado;
rollback;

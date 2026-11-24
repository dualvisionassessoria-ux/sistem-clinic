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

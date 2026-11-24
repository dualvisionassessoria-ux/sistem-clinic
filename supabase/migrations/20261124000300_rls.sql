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

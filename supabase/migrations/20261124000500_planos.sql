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

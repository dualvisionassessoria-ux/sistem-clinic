# Sistem Clinic

SaaS de gestão para clínicas, estéticas e salões, com várias empresas no mesmo sistema
(multi-empresa), cada uma com suas unidades, profissionais, serviços e equipe.

- **Front-end:** React + Vite + Tailwind (pasta `web/`), publicado como site estático na HostGator.
- **Banco, login e regras:** Supabase (pasta `supabase/`), com RLS separando os dados de cada empresa.
- **WhatsApp:** Evolution API (a partir da Etapa 3).

## Etapa 1 (esta versão)

- Cadastro self-service da empresa com 7 dias de teste e escolha de plano (Essencial, Profissional, Premium).
- Login, recuperação de senha e convite de equipe por link (dono, recepção, profissional).
- Cadastros: empresa, unidades com horário de funcionamento, profissionais com unidades, jornada e serviços,
  serviços com duração, preço e quem atende, equipe com papéis e unidades.
- Limites do plano aplicados no banco (unidades, profissionais, usuários).
- Painel do super-admin: lista de empresas, plano, status da assinatura, bloqueio.

---

## 1. Instalar o banco no Supabase

1. No painel do Supabase, abra **SQL Editor → New query**.
2. Copie todo o conteúdo de [`supabase/instalar.sql`](supabase/instalar.sql), cole e clique em **Run**.
   Deve terminar com "Success. No rows returned".
3. Em **Table Editor → planos**, confira os 3 planos. Preços e limites podem ser alterados ali mesmo
   (`null` = ilimitado).

> As migrações separadas estão em `supabase/migrations/`. O `instalar.sql` é só a junção delas
> (gerada por `supabase/montar_instalacao.sh`). Se usar a Supabase CLI, `supabase db push` aplica as migrações.

## 2. Configurar o login (Authentication)

Em **Authentication → URL Configuration**:

- **Site URL:** `https://app.sistemclinic.com.br`
- **Redirect URLs:** adicione `https://app.sistemclinic.com.br/**` e, para testes no computador, `http://localhost:5173/**`

Em **Authentication → Emails (Templates)**, traduza os textos de "Confirm signup" e "Reset password" para português
(o link `{{ .ConfirmationURL }}` precisa continuar no texto).

Recomendado: em **Authentication → Emails → SMTP Settings**, configurar um SMTP próprio (ex.: o e-mail do domínio na
HostGator). O SMTP padrão do Supabase envia poucos e-mails por hora e serve só para testes.

## 3. Tornar-se super-admin

1. Crie sua conta pelo próprio site (Criar conta).
2. No SQL Editor, rode [`supabase/tornar_super_admin.sql`](supabase/tornar_super_admin.sql) trocando o e-mail pelo seu.
3. Saia e entre de novo: aparece o ícone de escudo (**Painel da plataforma**).

## 4. Rodar no computador (opcional)

```bash
cd web
cp .env.example .env      # já vem com a URL e a chave pública do projeto
npm install
npm run dev               # abre em http://localhost:5173
```

## 5. Publicar na HostGator

1. No cPanel, crie o subdomínio **app.sistemclinic.com.br** (Domínios → Subdomínios). Anote a pasta dele
   (ex.: `public_html/app`). Ative o SSL gratuito (SSL/TLS Status → AutoSSL).
2. No computador: `cd web && npm install && npm run build`. Isso gera a pasta `web/dist/`.
3. Envie **o conteúdo** de `web/dist/` (incluindo o arquivo oculto `.htaccess`) para a pasta do subdomínio,
   pelo Gerenciador de Arquivos do cPanel ou por FTP.
4. Acesse `https://app.sistemclinic.com.br`.

O `.htaccess` força HTTPS e faz as rotas do app (ex.: `/unidades`) funcionarem ao recarregar a página.

## 6. Ligar o WhatsApp (Evolution API)

A Evolution API só é chamada pela Edge Function `supabase/functions/whatsapp`. O navegador nunca vê a chave.

1. **Banco**: rode `supabase/migrations/20261124000800_whatsapp.sql` no SQL Editor (já incluso no `instalar.sql`).
2. **Edge Function**: Supabase → Edge Functions → *Deploy a new function* → *Via editor*, nome `whatsapp`, cole `supabase/functions/whatsapp/index.ts` e publique.
   Depois, nos detalhes da função, **desligue "Verify JWT"** (o webhook e o agendador não mandam login; o painel é validado dentro da função).
   Pela linha de comando: `npx supabase functions deploy whatsapp --no-verify-jwt --project-ref txnwrycavxkpyyhcpffj`.
3. **Segredos** (Edge Functions → Secrets): `EVOLUTION_URL` (endereço do servidor, sem barra no fim) e `EVOLUTION_API_KEY` (chave global).
   Se o servidor for da versão 1.x, crie também `EVOLUTION_VERSAO=1`.
4. **Agendador**: rode `supabase/agendar_whatsapp.sql` no SQL Editor. Ele chama a função a cada minuto (pg_cron + pg_net) para gerar e enviar as mensagens.
5. No sistema, o dono abre **WhatsApp → Conexão → Conectar** em cada unidade e lê o QR Code.

O que roda sozinho: confirmação X horas antes (SIM/NÃO muda o status), lembrete, pós-atendimento com link de avaliação do Google (Profissional+),
aniversário e convite de retorno (Profissional+), campanhas e marcação pelo WhatsApp (Premium). Testes: `supabase/tests/whatsapp.sql`.

## Segurança

- O front usa só a chave **publishable/anon**, que é pública. A `service_role`/secret key nunca vai para o front
  nem para o repositório.
- Toda tabela tem RLS. As regras estão em `supabase/migrations/20261124000300_rls.sql`.
- Teste de isolamento entre empresas: `supabase/tests/isolamento.sql` (43 verificações), rodado contra um
  Postgres de teste com `supabase/tests/stub_supabase_local.sql` antes das migrações.

-- =====================================================================
-- Sistem Clinic · Liga o agendador do WhatsApp (rodar UMA vez no SQL Editor,
-- depois de publicar a Edge Function "whatsapp").
-- A cada minuto o banco chama a função, que gera as mensagens automáticas
-- (confirmação, lembrete, avaliação, aniversário, retorno) e envia a fila.
-- O segredo do agendador fica numa tabela interna (app.config), fora da API.
-- =====================================================================
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

select cron.unschedule(jobid) from cron.job where jobname = 'sistem-clinic-whatsapp';

select cron.schedule(
  'sistem-clinic-whatsapp',
  '* * * * *',
  $$
  select net.http_post(
    url := 'https://txnwrycavxkpyyhcpffj.supabase.co/functions/v1/whatsapp?acao=ciclo',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object('segredo', (select valor from app.config where chave = 'cron_secret')),
    timeout_milliseconds := 120000
  );
  $$
);

-- Para conferir depois: select * from cron.job_run_details order by start_time desc limit 5;

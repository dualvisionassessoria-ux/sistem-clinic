-- Rode no SQL Editor DEPOIS de criar sua conta pelo site.
-- Troque o e-mail pelo seu. Isso libera o "Painel da plataforma".
insert into public.admins_plataforma (user_id)
select id from auth.users where email = 'SEU-EMAIL@exemplo.com'
on conflict do nothing;

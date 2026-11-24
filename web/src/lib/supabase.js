import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !key) {
  // eslint-disable-next-line no-console
  console.error('Configure VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY no arquivo .env')
}

export const supabase = createClient(url, key, {
  auth: {
    flowType: 'pkce',
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
})

/** Traduz erros do Supabase/Postgres para mensagens em português. */
export function mensagemErro(err) {
  if (!err) return ''
  const msg = err.message || String(err)
  const mapa = [
    [/Invalid login credentials/i, 'E-mail ou senha incorretos.'],
    [/Email not confirmed/i, 'Confirme seu e-mail antes de entrar. Procure a mensagem na sua caixa de entrada.'],
    [/User already registered/i, 'Já existe uma conta com este e-mail. Use "Entrar".'],
    [/Password should be at least/i, 'A senha precisa ter pelo menos 6 caracteres.'],
    [/rate limit|too many requests/i, 'Muitas tentativas. Aguarde um minuto e tente de novo.'],
    [/duplicate key/i, 'Já existe um cadastro igual.'],
    [/violates row-level security|permission denied/i, 'Você não tem permissão para esta ação.'],
    [/violates check constraint/i, 'Algum campo tem valor inválido. Confira e tente de novo.'],
    [/Failed to fetch|NetworkError/i, 'Sem conexão com o servidor. Verifique sua internet.'],
  ]
  for (const [re, txt] of mapa) if (re.test(msg)) return txt
  return msg
}

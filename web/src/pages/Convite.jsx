import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { MailCheck } from 'lucide-react'
import TelaAcesso from '../components/TelaAcesso.jsx'
import { Alerta, Botao, Campo, Carregando, Entrada } from '../components/ui.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'
import { CHAVE_CONVITE, useSessao } from '../lib/sessao.jsx'
import { PAPEIS } from '../lib/formato.js'

export default function Convite() {
  const { token } = useParams()
  const s = useSessao()
  const navegar = useNavigate()
  const [convite, setConvite] = useState(undefined)
  const [modo, setModo] = useState('criar') // criar | entrar
  const [nome, setNome] = useState('')
  const [senha, setSenha] = useState('')
  const [erro, setErro] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [confirmarEmail, setConfirmarEmail] = useState(false)

  useEffect(() => {
    supabase.rpc('ver_convite', { p_token: token }).then(({ data }) => setConvite(data?.[0] ?? null))
  }, [token])

  async function aceitar() {
    setErro('')
    setEnviando(true)
    const { data: empresaId, error } = await supabase.rpc('aceitar_convite', { p_token: token })
    setEnviando(false)
    if (error) return setErro(mensagemErro(error))
    s.setEmpresaId(empresaId)
    await s.recarregar()
    navegar('/', { replace: true })
  }

  async function acessar(e) {
    e.preventDefault()
    setErro('')
    setEnviando(true)
    try {
      localStorage.setItem(CHAVE_CONVITE, token)
    } catch { /* sem storage */ }
    const resp =
      modo === 'criar'
        ? await supabase.auth.signUp({
            email: convite.email,
            password: senha,
            options: { data: { nome: nome.trim() }, emailRedirectTo: `${window.location.origin}/convite/${token}` },
          })
        : await supabase.auth.signInWithPassword({ email: convite.email, password: senha })
    setEnviando(false)
    if (resp.error) return setErro(mensagemErro(resp.error))
    if (modo === 'criar' && !resp.data.session) setConfirmarEmail(true)
  }

  if (convite === undefined || s.carregando) return <Carregando />

  if (!convite || convite.expirado || convite.aceito) {
    return (
      <TelaAcesso titulo="Convite indisponível">
        <Alerta tipo="aviso">
          {convite?.aceito ? 'Este convite já foi usado.' : convite?.expirado ? 'Este convite expirou.' : 'Convite não encontrado.'} Peça um novo link ao responsável pela empresa.
        </Alerta>
        <p className="mt-6 text-center text-sm"><Link to="/entrar" className="font-medium text-marca-700">Ir para o login</Link></p>
      </TelaAcesso>
    )
  }

  const titulo = `Entrar na equipe da ${convite.empresa_nome}`
  const subtitulo = `Você foi convidado(a) como ${PAPEIS[convite.papel]}.`

  if (confirmarEmail) {
    return (
      <TelaAcesso titulo="Confirme seu e-mail">
        <div className="rounded-2xl bg-agua-50 p-6 text-center">
          <MailCheck className="mx-auto size-10 text-agua-600" />
          <p className="mt-3 text-slate-700">Enviamos um link para <strong>{convite.email}</strong>. Clique nele para concluir a entrada na equipe.</p>
        </div>
      </TelaAcesso>
    )
  }

  if (s.usuario) {
    const mesmoEmail = s.usuario.email?.toLowerCase() === convite.email
    return (
      <TelaAcesso titulo={titulo} subtitulo={subtitulo}>
        {mesmoEmail ? (
          <div className="space-y-4">
            <Alerta>{erro}</Alerta>
            <Botao className="w-full" carregando={enviando} onClick={aceitar}>Aceitar convite</Botao>
          </div>
        ) : (
          <div className="space-y-4">
            <Alerta tipo="aviso">O convite foi enviado para {convite.email}, mas você está conectado como {s.usuario.email}.</Alerta>
            <Botao variante="secundario" className="w-full" onClick={() => s.sair()}>Sair e entrar com {convite.email}</Botao>
          </div>
        )}
      </TelaAcesso>
    )
  }

  return (
    <TelaAcesso titulo={titulo} subtitulo={subtitulo}>
      <div className="mb-5 grid grid-cols-2 rounded-xl bg-slate-100 p-1 text-sm font-medium">
        {[['criar', 'Primeiro acesso'], ['entrar', 'Já tenho conta']].map(([k, v]) => (
          <button key={k} type="button" onClick={() => setModo(k)}
            className={`rounded-lg py-2 ${modo === k ? 'bg-white shadow-sm text-slate-900' : 'text-slate-500'}`}>{v}</button>
        ))}
      </div>
      <form onSubmit={acessar} className="space-y-4">
        <Campo rotulo="E-mail"><Entrada value={convite.email} disabled /></Campo>
        {modo === 'criar' && (
          <Campo rotulo="Seu nome"><Entrada required value={nome} onChange={(e) => setNome(e.target.value)} /></Campo>
        )}
        <Campo rotulo={modo === 'criar' ? 'Crie uma senha' : 'Senha'} dica={modo === 'criar' ? 'Mínimo de 8 caracteres.' : undefined}>
          <Entrada type="password" required minLength={modo === 'criar' ? 8 : undefined} value={senha} onChange={(e) => setSenha(e.target.value)}
            autoComplete={modo === 'criar' ? 'new-password' : 'current-password'} />
        </Campo>
        <Alerta>{erro}</Alerta>
        <Botao type="submit" carregando={enviando} className="w-full">{modo === 'criar' ? 'Criar acesso' : 'Entrar e aceitar'}</Botao>
      </form>
    </TelaAcesso>
  )
}

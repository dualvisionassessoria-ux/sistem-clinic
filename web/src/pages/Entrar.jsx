import { useEffect, useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import TelaAcesso from '../components/TelaAcesso.jsx'
import { Alerta, Botao, Campo, Entrada } from '../components/ui.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'
import { useSessao } from '../lib/sessao.jsx'

export default function Entrar() {
  const s = useSessao()
  const navegar = useNavigate()
  const local = useLocation()
  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
  const [erro, setErro] = useState('')
  const [enviando, setEnviando] = useState(false)

  useEffect(() => {
    if (!s.carregando && s.usuario) navegar(local.state?.de || '/', { replace: true })
  }, [s.carregando, s.usuario, navegar, local.state])

  async function entrar(e) {
    e.preventDefault()
    setErro('')
    setEnviando(true)
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password: senha })
    setEnviando(false)
    if (error) setErro(mensagemErro(error))
  }

  return (
    <TelaAcesso titulo="Entrar" subtitulo="Acesse a agenda e os cadastros da sua empresa.">
      <form onSubmit={entrar} className="space-y-4">
        <Campo rotulo="E-mail">
          <Entrada type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="voce@clinica.com.br" />
        </Campo>
        <Campo rotulo="Senha">
          <Entrada type="password" autoComplete="current-password" required value={senha} onChange={(e) => setSenha(e.target.value)} />
        </Campo>
        <div className="text-right">
          <Link to="/esqueci-senha" className="text-sm font-medium text-marca-700 hover:underline">Esqueci a senha</Link>
        </div>
        <Alerta>{erro}</Alerta>
        <Botao type="submit" carregando={enviando} className="w-full">Entrar</Botao>
      </form>
      <p className="mt-8 text-center text-sm text-slate-600">
        Ainda não tem conta?{' '}
        <Link to="/criar-conta" className="font-semibold text-agua-600 hover:underline">Teste grátis por 7 dias</Link>
      </p>
    </TelaAcesso>
  )
}

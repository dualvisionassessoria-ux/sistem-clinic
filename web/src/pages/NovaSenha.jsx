import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import TelaAcesso from '../components/TelaAcesso.jsx'
import { Alerta, Botao, Campo, Carregando, Entrada } from '../components/ui.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'
import { useSessao } from '../lib/sessao.jsx'

export default function NovaSenha() {
  const s = useSessao()
  const navegar = useNavigate()
  const [senha, setSenha] = useState('')
  const [confirma, setConfirma] = useState('')
  const [erro, setErro] = useState('')
  const [enviando, setEnviando] = useState(false)

  if (s.carregando) return <Carregando />
  if (!s.usuario) {
    return (
      <TelaAcesso titulo="Link expirado">
        <Alerta tipo="aviso">Este link de recuperação não é mais válido. Peça um novo em "Esqueci a senha".</Alerta>
      </TelaAcesso>
    )
  }

  async function salvar(e) {
    e.preventDefault()
    if (senha !== confirma) return setErro('As senhas não conferem.')
    setErro('')
    setEnviando(true)
    const { error } = await supabase.auth.updateUser({ password: senha })
    setEnviando(false)
    if (error) return setErro(mensagemErro(error))
    s.setRecuperandoSenha(false)
    navegar('/', { replace: true })
  }

  return (
    <TelaAcesso titulo="Criar nova senha" subtitulo={s.usuario.email}>
      <form onSubmit={salvar} className="space-y-4">
        <Campo rotulo="Nova senha" dica="Mínimo de 8 caracteres.">
          <Entrada type="password" autoComplete="new-password" minLength={8} required value={senha} onChange={(e) => setSenha(e.target.value)} />
        </Campo>
        <Campo rotulo="Repita a senha">
          <Entrada type="password" autoComplete="new-password" minLength={8} required value={confirma} onChange={(e) => setConfirma(e.target.value)} />
        </Campo>
        <Alerta>{erro}</Alerta>
        <Botao type="submit" carregando={enviando} className="w-full">Salvar senha</Botao>
      </form>
    </TelaAcesso>
  )
}

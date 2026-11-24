import { useState } from 'react'
import { Link } from 'react-router-dom'
import TelaAcesso from '../components/TelaAcesso.jsx'
import { Alerta, Botao, Campo, Entrada } from '../components/ui.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'

export default function EsqueciSenha() {
  const [email, setEmail] = useState('')
  const [erro, setErro] = useState('')
  const [enviado, setEnviado] = useState(false)
  const [enviando, setEnviando] = useState(false)

  async function enviar(e) {
    e.preventDefault()
    setErro('')
    setEnviando(true)
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/nova-senha`,
    })
    setEnviando(false)
    if (error) setErro(mensagemErro(error))
    else setEnviado(true)
  }

  return (
    <TelaAcesso titulo="Recuperar senha" subtitulo="Enviaremos um link para você criar uma nova senha.">
      {enviado ? (
        <Alerta tipo="sucesso">Pronto! Se existir uma conta com {email}, você vai receber o link em alguns minutos. Confira também a caixa de spam.</Alerta>
      ) : (
        <form onSubmit={enviar} className="space-y-4">
          <Campo rotulo="E-mail">
            <Entrada type="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
          </Campo>
          <Alerta>{erro}</Alerta>
          <Botao type="submit" carregando={enviando} className="w-full">Enviar link</Botao>
        </form>
      )}
      <p className="mt-8 text-center text-sm">
        <Link to="/entrar" className="font-medium text-marca-700 hover:underline">Voltar para o login</Link>
      </p>
    </TelaAcesso>
  )
}

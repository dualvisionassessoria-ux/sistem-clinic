import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Check, MailCheck } from 'lucide-react'
import TelaAcesso from '../components/TelaAcesso.jsx'
import { Alerta, Botao, Campo, Carregando, Entrada, Selecao, cx } from '../components/ui.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'
import { useSessao } from '../lib/sessao.jsx'
import { SEGMENTOS, reais } from '../lib/formato.js'

const DESTAQUES = {
  essencial: ['Agenda e cadastro de clientes', 'Confirmação 24h e lembrete 2h no WhatsApp', 'Financeiro simples'],
  profissional: ['Tudo do Essencial', 'Pedido de avaliação no Google', 'Campanhas de retorno e aniversário', 'Relatórios por profissional'],
  premium: ['Tudo do Profissional', 'Marcação automática pelo WhatsApp', 'Atendimento com IA'],
}

export default function CriarConta() {
  const s = useSessao()
  const navegar = useNavigate()
  const [planos, setPlanos] = useState([])
  const [plano, setPlano] = useState('profissional')
  const [form, setForm] = useState({ empresa: '', segmento: 'odontologia', unidade: '', telefone: '', nome: '', email: '', senha: '' })
  const [erro, setErro] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [confirmarEmail, setConfirmarEmail] = useState(false)

  const logado = !!s.usuario

  useEffect(() => {
    supabase.from('planos').select('*').eq('ativo', true).order('ordem').then(({ data }) => setPlanos(data ?? []))
  }, [])

  useEffect(() => {
    if (!s.carregando && logado && s.vinculos.length) navegar('/', { replace: true })
  }, [s.carregando, logado, s.vinculos.length, navegar])

  const campo = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }))

  async function enviar(e) {
    e.preventDefault()
    setErro('')
    setEnviando(true)
    const empresa = {
      nome: form.empresa.trim(),
      segmento: form.segmento,
      plano,
      unidade: form.unidade.trim(),
      telefone: form.telefone.trim(),
    }

    try {
      if (logado) {
        const { data: id, error } = await supabase.rpc('criar_empresa', {
          p_nome: empresa.nome,
          p_segmento: empresa.segmento,
          p_plano_codigo: plano,
          p_nome_unidade: empresa.unidade || null,
          p_telefone: empresa.telefone || null,
        })
        if (error) throw error
        s.setEmpresaId(id)
        await s.recarregar()
        navegar('/', { replace: true })
        return
      }

      // a empresa fica guardada no cadastro do usuário e é criada no primeiro login
      const { data, error } = await supabase.auth.signUp({
        email: form.email.trim(),
        password: form.senha,
        options: {
          data: { nome: form.nome.trim(), empresa_pendente: empresa },
          emailRedirectTo: `${window.location.origin}/`,
        },
      })
      if (error) throw error
      if (!data.session) setConfirmarEmail(true)
    } catch (err) {
      setErro(mensagemErro(err))
    } finally {
      setEnviando(false)
    }
  }

  if (s.carregando) return <Carregando />

  if (confirmarEmail) {
    return (
      <TelaAcesso titulo="Confirme seu e-mail">
        <div className="rounded-2xl bg-agua-50 p-6 text-center">
          <MailCheck className="mx-auto size-10 text-agua-600" />
          <p className="mt-3 text-slate-700">
            Enviamos um link para <strong>{form.email}</strong>. Clique nele para ativar a conta. Sua empresa será criada no primeiro acesso.
          </p>
          <p className="mt-2 text-xs text-slate-500">Não chegou? Confira a caixa de spam.</p>
        </div>
      </TelaAcesso>
    )
  }

  return (
    <TelaAcesso
      largo
      titulo={logado ? 'Cadastre sua empresa' : 'Comece seu teste grátis'}
      subtitulo="7 dias grátis, sem cartão. Você escolhe o plano agora e pode mudar depois."
    >
      <form onSubmit={enviar} className="space-y-6">
        <fieldset>
          <legend className="mb-2 text-sm font-medium text-slate-700">Plano</legend>
          <div className="grid gap-3 sm:grid-cols-3">
            {planos.map((p) => {
              const ativo = plano === p.codigo
              return (
                <button
                  type="button"
                  key={p.id}
                  onClick={() => setPlano(p.codigo)}
                  className={cx(
                    'relative rounded-2xl border p-4 text-left transition',
                    ativo ? 'border-marca-600 bg-marca-50 ring-2 ring-marca-600/20' : 'border-slate-200 hover:border-slate-300',
                  )}
                >
                  {p.codigo === 'profissional' && (
                    <span className="absolute -top-2.5 right-3 rounded-full bg-agua-500 px-2 py-0.5 text-[10px] font-semibold text-white">Mais escolhido</span>
                  )}
                  <p className="font-semibold text-slate-900">{p.nome}</p>
                  <p className="mt-1 text-lg font-bold text-marca-700">
                    {reais(p.preco_mensal)}<span className="text-xs font-normal text-slate-500">/mês</span>
                  </p>
                  <p className="mt-1 text-xs text-slate-500">
                    {p.limite_unidades === 1 ? '1 unidade' : `até ${p.limite_unidades ?? '∞'} unidades`} · {p.limite_profissionais == null ? 'profissionais ilimitados' : `até ${p.limite_profissionais} profissionais`}
                  </p>
                  <ul className="mt-3 space-y-1">
                    {(DESTAQUES[p.codigo] ?? []).map((d) => (
                      <li key={d} className="flex gap-1.5 text-xs text-slate-600">
                        <Check className="mt-0.5 size-3.5 shrink-0 text-agua-600" /> {d}
                      </li>
                    ))}
                  </ul>
                </button>
              )
            })}
          </div>
        </fieldset>

        <div className="grid gap-4 sm:grid-cols-2">
          <Campo rotulo="Nome da empresa" className="sm:col-span-2">
            <Entrada required minLength={2} value={form.empresa} onChange={campo('empresa')} placeholder="Ex.: Clínica Sorriso" />
          </Campo>
          <Campo rotulo="Segmento">
            <Selecao value={form.segmento} onChange={campo('segmento')}>
              {Object.entries(SEGMENTOS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </Selecao>
          </Campo>
          <Campo rotulo="WhatsApp da empresa">
            <Entrada type="tel" inputMode="tel" value={form.telefone} onChange={campo('telefone')} placeholder="(11) 99999-9999" />
          </Campo>
          <Campo rotulo="Nome da primeira unidade" dica="Ex.: Centro, Matriz. Você pode adicionar outras depois." className="sm:col-span-2">
            <Entrada value={form.unidade} onChange={campo('unidade')} placeholder="Unidade principal" />
          </Campo>
        </div>

        {!logado && (
          <div className="grid gap-4 border-t border-slate-100 pt-6 sm:grid-cols-2">
            <Campo rotulo="Seu nome" className="sm:col-span-2">
              <Entrada required autoComplete="name" value={form.nome} onChange={campo('nome')} />
            </Campo>
            <Campo rotulo="Seu e-mail">
              <Entrada type="email" required autoComplete="email" value={form.email} onChange={campo('email')} />
            </Campo>
            <Campo rotulo="Senha" dica="Mínimo de 8 caracteres.">
              <Entrada type="password" required minLength={8} autoComplete="new-password" value={form.senha} onChange={campo('senha')} />
            </Campo>
          </div>
        )}

        <Alerta>{erro}</Alerta>
        <Botao type="submit" carregando={enviando} className="w-full">
          {logado ? 'Criar empresa' : 'Criar conta e começar o teste'}
        </Botao>
        <p className="text-center text-xs text-slate-500">
          Ao continuar, você concorda com os termos de uso do Sistem Clinic.
        </p>
      </form>
      {!logado && (
        <p className="mt-8 text-center text-sm text-slate-600">
          Já tem conta? <Link to="/entrar" className="font-semibold text-marca-700 hover:underline">Entrar</Link>
        </p>
      )}
    </TelaAcesso>
  )
}

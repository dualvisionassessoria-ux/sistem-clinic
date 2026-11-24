import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { ArrowLeft, CalendarPlus, MessageCircle, Phone, Cake, AlertTriangle, Trash2 } from 'lucide-react'
import { Botao, Cartao, Carregando, Etiqueta, Vazio, cx, useAviso } from '../components/ui.jsx'
import { PainelAgendamento, PainelDetalhe, StatusEtiqueta, useCadastros, useOpera } from '../components/Atendimento.jsx'
import { FormPaciente, registroPaciente } from './Pacientes.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'
import { ok, useDados } from '../lib/useDados.js'
import { linkWhatsApp, reais, data as dataBR } from '../lib/formato.js'
import { FORMAS_PAGAMENTO, dataHora, deIso, idade, iniciais, telefone } from '../lib/agenda.js'

const ABAS = [['historico', 'Histórico'], ['dados', 'Dados'], ['financeiro', 'Financeiro']]

export default function Paciente() {
  const { id } = useParams()
  const s = useSessao()
  const opera = useOpera()
  const avisar = useAviso()
  const navegar = useNavigate()
  const [aba, setAba] = useState('historico')
  const [f, setF] = useState(null)
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)
  const [detalhe, setDetalhe] = useState(null)
  const [editar, setEditar] = useState(null)
  const { dados: cad } = useCadastros(s.empresa.id)

  const { dados, carregando, recarregar } = useDados(async () => {
    const [c, ag, pg] = await Promise.all([
      supabase.from('clientes').select('*').eq('id', id).maybeSingle(),
      supabase.from('agendamentos').select('id, inicio, fim, status, valor, encaixe, origem, profissional_id, servico:servicos(nome)').eq('cliente_id', id).order('inicio', { ascending: false }).limit(200),
      supabase.from('pagamentos').select('id, valor, forma, recebido_em, descricao, profissional_id').eq('cliente_id', id).order('recebido_em', { ascending: false }).limit(200),
    ])
    return { cliente: ok(c), agendamentos: ok(ag) ?? [], pagamentos: ok(pg) ?? [] }
  }, [id])

  useEffect(() => {
    if (!dados?.cliente) return
    const c = dados.cliente
    setF({
      nome: c.nome, telefone: telefone(c.telefone), data_nascimento: c.data_nascimento ?? '', email: c.email ?? '', documento: c.documento ?? '',
      genero: c.genero ?? '', origem: c.origem ?? '', endereco: c.endereco ?? '', observacoes: c.observacoes ?? '', aceita_whatsapp: c.aceita_whatsapp,
    })
  }, [dados])

  if (carregando && !dados) return <Carregando />
  if (!dados?.cliente) return <Vazio titulo="Paciente não encontrado" acao={<Botao onClick={() => navegar('/pacientes')}>Voltar</Botao>} />

  const c = dados.cliente
  const profs = Object.fromEntries((cad?.profissionais ?? []).map((p) => [p.id, p]))
  const atendidos = dados.agendamentos.filter((a) => a.status === 'atendido')
  const faltas = dados.agendamentos.filter((a) => a.status === 'faltou').length
  const totalPago = dados.pagamentos.reduce((t, p) => t + Number(p.valor), 0)
  const proximos = dados.agendamentos.filter((a) => new Date(a.inicio) > new Date() && ['agendado', 'confirmado'].includes(a.status)).reverse()
  const nasc = c.data_nascimento && deIso(c.data_nascimento)
  const hoje = new Date()
  const aniversarioHoje = nasc && nasc.getDate() === hoje.getDate() && nasc.getMonth() === hoje.getMonth()
  const primeiroNome = c.nome.split(' ')[0]
  const msg = aniversarioHoje
    ? `Feliz aniversário, ${primeiroNome}! 🎉 Toda a equipe da ${s.empresa.nome} deseja um dia maravilhoso!`
    : `Olá, ${primeiroNome}! Aqui é da ${s.empresa.nome}.`

  async function salvar(e) {
    e.preventDefault()
    setErro('')
    setSalvando(true)
    try {
      ok(await supabase.from('clientes').update(registroPaciente(f)).eq('id', id))
      avisar('Ficha atualizada')
      recarregar()
    } catch (err) {
      setErro(mensagemErro(err))
    } finally {
      setSalvando(false)
    }
  }

  async function inativar() {
    if (!window.confirm(`Remover ${c.nome} da lista de pacientes? O histórico de atendimentos é mantido.`)) return
    const { error } = await supabase.from('clientes').update({ ativo: false }).eq('id', id)
    if (error) return avisar(mensagemErro(error), 'erro')
    avisar('Paciente removido da lista')
    navegar('/pacientes')
  }

  return (
    <div className="space-y-5">
      <Link to="/pacientes" className="inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800"><ArrowLeft className="size-4" /> Pacientes</Link>

      <Cartao className="p-5">
        <div className="flex items-start gap-4">
          <span className="grid size-14 shrink-0 place-items-center rounded-2xl bg-agua-50 text-lg font-bold text-agua-700">{iniciais(c.nome)}</span>
          <div className="min-w-0 flex-1">
            <h1 className="text-xl font-bold text-slate-900">{c.nome}</h1>
            <p className="text-sm text-slate-500">
              {[nasc && `${idade(c.data_nascimento)} anos`, c.telefone && telefone(c.telefone), c.origem].filter(Boolean).join(' · ') || 'Sem dados de contato'}
            </p>
            <div className="mt-2 flex flex-wrap gap-2">
              {aniversarioHoje && <Etiqueta className="bg-pink-100 text-pink-700"><Cake className="mr-1 size-3" />Aniversário hoje</Etiqueta>}
              {!c.ativo && <Etiqueta className="bg-slate-200 text-slate-600">Removido da lista</Etiqueta>}
              {!c.aceita_whatsapp && <Etiqueta className="bg-slate-100 text-slate-600">Não recebe mensagens automáticas</Etiqueta>}
            </div>
          </div>
        </div>
        {c.observacoes && (
          <p className="mt-4 flex gap-2 whitespace-pre-line rounded-xl bg-amber-50 p-3 text-sm text-amber-900">
            <AlertTriangle className="mt-0.5 size-4 shrink-0" /> {c.observacoes}
          </p>
        )}
        <div className="mt-4 grid grid-cols-2 gap-2 sm:flex">
          {opera && <Botao onClick={() => navegar(`/agenda?novo=1&cliente=${c.id}`)}><CalendarPlus className="size-4" /> Agendar</Botao>}
          {c.telefone && (
            <>
              <a href={linkWhatsApp(msg, c.telefone)} target="_blank" rel="noreferrer"
                className="inline-flex h-11 items-center justify-center gap-2 rounded-xl bg-emerald-500 px-4 text-sm font-semibold text-white hover:bg-emerald-600">
                <MessageCircle className="size-4" /> WhatsApp
              </a>
              <a href={`tel:+${c.telefone}`} className="hidden h-11 items-center justify-center gap-2 rounded-xl border border-slate-300 px-4 text-sm font-semibold text-slate-700 hover:bg-slate-50 sm:inline-flex">
                <Phone className="size-4" /> Ligar
              </a>
            </>
          )}
        </div>
      </Cartao>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        {[
          ['Atendimentos', atendidos.length],
          ['Faltas', faltas],
          ['Total pago', reais(totalPago)],
          ['Última visita', c.ultima_visita_em ? dataBR(c.ultima_visita_em) : '—'],
        ].map(([r, v]) => (
          <Cartao key={r} className="p-4">
            <p className="text-xs text-slate-500">{r}</p>
            <p className="mt-1 text-lg font-bold text-slate-900">{v}</p>
          </Cartao>
        ))}
      </div>

      <div className="flex gap-1 rounded-xl bg-slate-100 p-1">
        {ABAS.map(([k, r]) => (
          <button key={k} onClick={() => setAba(k)}
            className={cx('flex-1 rounded-lg py-2 text-sm font-medium', aba === k ? 'bg-white text-marca-700 shadow-sm' : 'text-slate-500')}>{r}</button>
        ))}
      </div>

      {aba === 'historico' && (
        <div className="space-y-4">
          {proximos.length > 0 && (
            <section>
              <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400">Próximos</h2>
              <ListaAgendamentos itens={proximos} profs={profs} aoAbrir={setDetalhe} />
            </section>
          )}
          <section>
            <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400">Histórico</h2>
            {dados.agendamentos.filter((a) => !proximos.includes(a)).length
              ? <ListaAgendamentos itens={dados.agendamentos.filter((a) => !proximos.includes(a))} profs={profs} aoAbrir={setDetalhe} />
              : <p className="rounded-2xl border border-dashed border-slate-300 p-6 text-center text-sm text-slate-500">Nenhum atendimento ainda.</p>}
          </section>
        </div>
      )}

      {aba === 'dados' && f && (
        <Cartao className="p-5">
          <FormPaciente id="form-ficha" f={f} setF={setF} aoEnviar={salvar} erro={erro} somenteLeitura={!opera} />
          {opera && (
            <div className="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:justify-between">
              {s.eDono && c.ativo && <Botao variante="perigo" onClick={inativar}><Trash2 className="size-4" /> Remover paciente</Botao>}
              <Botao type="submit" form="form-ficha" carregando={salvando}>Salvar alterações</Botao>
            </div>
          )}
          <p className="mt-4 text-xs text-slate-400">Cadastrado em {dataBR(c.criado_em)}</p>
        </Cartao>
      )}

      {aba === 'financeiro' && (
        !dados.pagamentos.length
          ? <p className="rounded-2xl border border-dashed border-slate-300 p-6 text-center text-sm text-slate-500">Nenhum recebimento registrado.</p>
          : (
            <Cartao className="divide-y divide-slate-100">
              {dados.pagamentos.map((p) => (
                <div key={p.id} className="flex items-center justify-between gap-3 px-4 py-3">
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-slate-800">{FORMAS_PAGAMENTO[p.forma]}{p.profissional_id && profs[p.profissional_id] ? ` · ${profs[p.profissional_id].nome}` : ''}</p>
                    <p className="truncate text-xs text-slate-500">{dataHora(p.recebido_em)}{p.descricao ? ` · ${p.descricao}` : ''}</p>
                  </div>
                  <p className="font-semibold text-slate-900">{reais(p.valor)}</p>
                </div>
              ))}
            </Cartao>
          )
      )}

      {cad && <PainelDetalhe agendamentoId={detalhe} cad={cad} aoFechar={() => setDetalhe(null)} aoMudar={recarregar}
        aoEditar={(a) => { setDetalhe(null); setEditar(a) }} />}
      {cad && <PainelAgendamento aberto={!!editar} inicial={editar} cad={cad} aoFechar={() => setEditar(null)} aoSalvar={recarregar} />}
    </div>
  )
}

function ListaAgendamentos({ itens, profs, aoAbrir }) {
  return (
    <Cartao className="divide-y divide-slate-100">
      {itens.map((a) => (
        <button key={a.id} onClick={() => aoAbrir(a.id)} className="flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-slate-50">
          <span className="h-9 w-1 shrink-0 rounded-full" style={{ background: profs[a.profissional_id]?.cor_agenda ?? '#CBD5E1' }} />
          <span className="min-w-0 flex-1">
            <span className="block truncate text-sm font-medium text-slate-800">{a.servico?.nome ?? 'Atendimento'}{profs[a.profissional_id] ? ` · ${profs[a.profissional_id].nome}` : ''}</span>
            <span className="block text-xs text-slate-500">{dataHora(a.inicio)}{a.valor != null ? ` · ${reais(a.valor)}` : ''}</span>
          </span>
          <StatusEtiqueta status={a.status} />
        </button>
      ))}
    </Cartao>
  )
}

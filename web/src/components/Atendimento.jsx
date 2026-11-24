import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  Search, UserPlus, Phone, MessageCircle, Clock, Check, X, CalendarClock, UserX, Wallet, RotateCcw, Pencil, Trash2, Zap, History,
} from 'lucide-react'
import { Alerta, AreaTexto, Botao, Campo, Entrada, Etiqueta, Interruptor, Painel, Selecao, cx, useAviso } from './ui.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'
import { ok, useDados } from '../lib/useDados.js'
import { duracao, linkWhatsApp, reais } from '../lib/formato.js'
import {
  FORMAS_PAGAMENTO, ORIGENS, STATUS_AGENDAMENTO, dataHora, deIso, diaLongo, horaDe, isoDia, numeroBR, paraCampo, telefone,
} from '../lib/agenda.js'

/* ------------------------------------------------------------------ cadastros usados na agenda */
export function useCadastros(empresaId) {
  return useDados(async () => {
    const [u, p, pu, sv, sp, j, h] = await Promise.all([
      supabase.from('unidades').select('id, nome, fuso_horario, telefone, link_avaliacao_google').eq('empresa_id', empresaId).eq('ativo', true).order('nome'),
      supabase.from('profissionais').select('id, nome, cor_agenda, membro_id').eq('empresa_id', empresaId).eq('ativo', true).order('nome'),
      supabase.from('profissional_unidades').select('profissional_id, unidade_id').eq('empresa_id', empresaId),
      supabase.from('servicos').select('id, nome, duracao_min, preco, intervalo_apos_min, cor').eq('empresa_id', empresaId).eq('ativo', true).order('nome'),
      supabase.from('servico_profissionais').select('servico_id, profissional_id, preco_proprio, duracao_propria').eq('empresa_id', empresaId),
      supabase.from('jornadas').select('profissional_id, unidade_id, dia_semana, inicio, fim').eq('empresa_id', empresaId),
      supabase.from('horarios_unidade').select('unidade_id, dia_semana, abre, fecha').eq('empresa_id', empresaId),
    ])
    return {
      unidades: ok(u), profissionais: ok(p), profUnidades: ok(pu), servicos: ok(sv), servProfs: ok(sp), jornadas: ok(j), horarios: ok(h),
    }
  }, [empresaId])
}

/** Quem pode marcar, remarcar e receber (dono e recepção). */
export function useOpera() {
  const s = useSessao()
  return s.eDono || s.papel === 'recepcao'
}

export function profissionaisDaUnidade(cad, unidadeId) {
  const ids = new Set(cad.profUnidades.filter((x) => x.unidade_id === unidadeId).map((x) => x.profissional_id))
  return cad.profissionais.filter((p) => ids.has(p.id))
}

function precoEDuracao(cad, servicoId, profissionalId) {
  const sv = cad.servicos.find((x) => x.id === servicoId)
  if (!sv) return { duracao: 30, preco: null, intervalo: 0 }
  const sp = cad.servProfs.find((x) => x.servico_id === servicoId && x.profissional_id === profissionalId)
  return {
    duracao: sp?.duracao_propria ?? sv.duracao_min,
    preco: sp?.preco_proprio ?? sv.preco,
    intervalo: sv.intervalo_apos_min ?? 0,
  }
}

export function StatusEtiqueta({ status }) {
  const st = STATUS_AGENDAMENTO[status]
  return <Etiqueta className={st.cor}>{st.rotulo}</Etiqueta>
}

/* ------------------------------------------------------------------ busca / cadastro rápido de paciente */
function limparBusca(t) {
  return t.replace(/[,()%*]/g, ' ').trim()
}

export function BuscaPaciente({ empresaId, valor, aoEscolher }) {
  const [texto, setTexto] = useState('')
  const [lista, setLista] = useState([])
  const [novo, setNovo] = useState(null)
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)

  useEffect(() => {
    const t = limparBusca(texto)
    if (t.length < 2) { setLista([]); return }
    const digitos = t.replace(/\D/g, '')
    const id = setTimeout(async () => {
      let q = supabase.from('clientes').select('id, nome, telefone, data_nascimento').eq('empresa_id', empresaId).eq('ativo', true).limit(8).order('nome')
      q = digitos.length >= 4 ? q.ilike('telefone', `%${digitos}%`) : q.ilike('nome', `%${t}%`)
      const { data } = await q
      setLista(data ?? [])
    }, 250)
    return () => clearTimeout(id)
  }, [texto, empresaId])

  async function cadastrar() {
    setErro('')
    if ((novo.nome || '').trim().length < 2) return setErro('Informe o nome do paciente.')
    setSalvando(true)
    try {
      const c = ok(await supabase.from('clientes').insert({
        empresa_id: empresaId, nome: novo.nome.trim(), telefone: novo.telefone || null, data_nascimento: novo.data_nascimento || null,
      }).select('id, nome, telefone, data_nascimento').single())
      aoEscolher(c)
      setNovo(null)
      setTexto('')
    } catch (e) {
      setErro(mensagemErro(e))
    } finally {
      setSalvando(false)
    }
  }

  if (valor) {
    return (
      <div className="flex items-center gap-3 rounded-xl border border-agua-200 bg-agua-50/60 px-3.5 py-2.5">
        <div className="min-w-0 flex-1">
          <p className="truncate font-medium text-slate-900">{valor.nome}</p>
          {valor.telefone && <p className="text-xs text-slate-500">{telefone(valor.telefone)}</p>}
        </div>
        <button type="button" onClick={() => aoEscolher(null)} className="text-sm font-medium text-marca-700">Trocar</button>
      </div>
    )
  }

  if (novo) {
    return (
      <div className="space-y-3 rounded-xl border border-slate-200 p-3">
        <p className="text-sm font-semibold text-slate-800">Novo paciente</p>
        <Entrada placeholder="Nome completo" value={novo.nome} onChange={(e) => setNovo({ ...novo, nome: e.target.value })} autoFocus />
        <div className="grid grid-cols-2 gap-2">
          <Entrada placeholder="WhatsApp (DDD)" inputMode="tel" value={novo.telefone} onChange={(e) => setNovo({ ...novo, telefone: e.target.value })} />
          <Entrada type="date" aria-label="Nascimento" value={novo.data_nascimento} onChange={(e) => setNovo({ ...novo, data_nascimento: e.target.value })} />
        </div>
        <Alerta>{erro}</Alerta>
        <div className="flex gap-2">
          <Botao type="button" variante="secundario" className="h-10 flex-1" onClick={() => setNovo(null)}>Voltar</Botao>
          <Botao type="button" className="h-10 flex-1" carregando={salvando} onClick={cadastrar}>Cadastrar</Botao>
        </div>
      </div>
    )
  }

  const pareceTelefone = /^\d[\d\s()-]*$/.test(texto.trim())
  return (
    <div>
      <div className="relative">
        <Search className="pointer-events-none absolute left-3.5 top-3.5 size-4 text-slate-400" />
        <Entrada className="pl-10" placeholder="Nome ou telefone do paciente" value={texto} onChange={(e) => setTexto(e.target.value)} />
      </div>
      {(lista.length > 0 || texto.trim().length >= 2) && (
        <div className="mt-2 divide-y divide-slate-100 overflow-hidden rounded-xl border border-slate-200">
          {lista.map((c) => (
            <button key={c.id} type="button" onClick={() => { aoEscolher(c); setTexto('') }}
              className="flex w-full items-center justify-between gap-2 px-3.5 py-2.5 text-left hover:bg-slate-50">
              <span className="truncate text-sm font-medium text-slate-800">{c.nome}</span>
              <span className="shrink-0 text-xs text-slate-500">{telefone(c.telefone)}</span>
            </button>
          ))}
          <button type="button" onClick={() => setNovo({ nome: pareceTelefone ? '' : texto.trim(), telefone: pareceTelefone ? texto.trim() : '', data_nascimento: '' })}
            className="flex w-full items-center gap-2 px-3.5 py-2.5 text-left text-sm font-medium text-marca-700 hover:bg-marca-50">
            <UserPlus className="size-4" /> Cadastrar novo paciente{texto.trim() && !pareceTelefone ? `: ${texto.trim()}` : ''}
          </button>
        </div>
      )}
    </div>
  )
}

/* ------------------------------------------------------------------ novo / editar agendamento */
export function PainelAgendamento({ aberto, inicial, cad, aoFechar, aoSalvar }) {
  const s = useSessao()
  const avisar = useAviso()
  const empresaId = s.empresa.id
  const [f, setF] = useState(null)
  const [livres, setLivres] = useState(null)
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)

  useEffect(() => {
    if (!aberto) return
    setErro('')
    const ini = inicial ?? {}
    if (ini.id) {
      const d = new Date(ini.inicio)
      setF({
        id: ini.id, cliente: ini.cliente, unidade_id: ini.unidade_id, profissional_id: ini.profissional_id, servico_id: ini.servico_id ?? '',
        dia: isoDia(d), hora: horaDe(d), duracao: Math.round((new Date(ini.fim) - d) / 60000), encaixe: ini.encaixe,
        valor: paraCampo(ini.valor), observacoes: ini.observacoes ?? '', horaOriginal: horaDe(d), diaOriginal: isoDia(d),
      })
    } else {
      const unidade = ini.unidade_id ?? cad.unidades[0]?.id ?? ''
      setF({
        cliente: ini.cliente ?? null, unidade_id: unidade, profissional_id: ini.profissional_id ?? '', servico_id: '',
        dia: ini.dia ?? isoDia(new Date()), hora: ini.hora ?? '', duracao: 30, encaixe: false, valor: '', observacoes: '',
      })
    }
  }, [aberto, inicial, cad])

  const profsUnidade = useMemo(() => (f ? profissionaisDaUnidade(cad, f.unidade_id) : []), [cad, f?.unidade_id]) // eslint-disable-line react-hooks/exhaustive-deps
  const profsServico = useMemo(() => {
    if (!f?.servico_id) return profsUnidade
    const ligados = new Set(cad.servProfs.filter((x) => x.servico_id === f.servico_id).map((x) => x.profissional_id))
    return ligados.size ? profsUnidade.filter((p) => ligados.has(p.id)) : profsUnidade
  }, [cad, f?.servico_id, profsUnidade]) // eslint-disable-line react-hooks/exhaustive-deps

  // horários livres do dia
  useEffect(() => {
    if (!f || !f.unidade_id || !f.profissional_id || !f.dia || f.encaixe) { setLivres(null); return }
    let ativo = true
    setLivres('carregando')
    supabase.rpc('horarios_livres', { p_unidade: f.unidade_id, p_profissional: f.profissional_id, p_servico: f.servico_id || null, p_data: f.dia })
      .then(({ data, error }) => { if (ativo) setLivres(error ? [] : (data ?? []).map((x) => horaDe(x.inicio))) })
    return () => { ativo = false }
  }, [f?.unidade_id, f?.profissional_id, f?.servico_id, f?.dia, f?.encaixe]) // eslint-disable-line react-hooks/exhaustive-deps

  if (!aberto || !f) return null

  const muda = (k, v) => setF((x) => ({ ...x, [k]: v }))
  function escolherServico(id) {
    setF((x) => {
      const pd = precoEDuracao(cad, id, x.profissional_id)
      const ligados = cad.servProfs.filter((sp) => sp.servico_id === id).map((sp) => sp.profissional_id)
      const prof = !id || !ligados.length || ligados.includes(x.profissional_id) ? x.profissional_id : ''
      return { ...x, servico_id: id, profissional_id: prof, duracao: pd.duracao + pd.intervalo, valor: pd.preco != null ? paraCampo(pd.preco) : x.valor }
    })
  }
  function escolherProf(id) {
    setF((x) => {
      if (!x.servico_id) return { ...x, profissional_id: id }
      const pd = precoEDuracao(cad, x.servico_id, id)
      return { ...x, profissional_id: id, duracao: pd.duracao + pd.intervalo, valor: pd.preco != null ? paraCampo(pd.preco) : x.valor }
    })
  }

  async function salvar(e) {
    e.preventDefault()
    setErro('')
    if (!f.cliente) return setErro('Escolha ou cadastre o paciente.')
    if (!f.profissional_id) return setErro('Escolha o profissional.')
    if (!f.hora) return setErro('Escolha o horário.')
    const valor = f.valor === '' ? null : numeroBR(f.valor)
    if (valor != null && (Number.isNaN(valor) || valor < 0)) return setErro('Valor inválido.')
    const inicio = deIso(f.dia, f.hora)
    const fim = new Date(inicio.getTime() + Number(f.duracao || 30) * 60000)
    const registro = {
      empresa_id: empresaId, unidade_id: f.unidade_id, profissional_id: f.profissional_id, cliente_id: f.cliente.id,
      servico_id: f.servico_id || null, inicio: inicio.toISOString(), fim: fim.toISOString(), encaixe: f.encaixe,
      valor, observacoes: f.observacoes.trim() || null,
    }
    setSalvando(true)
    try {
      if (f.id) ok(await supabase.from('agendamentos').update(registro).eq('id', f.id))
      else ok(await supabase.from('agendamentos').insert({ ...registro, criado_por: s.usuario.id }))
      avisar(f.id ? 'Agendamento atualizado' : 'Agendamento criado')
      aoSalvar?.()
      aoFechar()
    } catch (err) {
      setErro(mensagemErro(err))
    } finally {
      setSalvando(false)
    }
  }

  const opcoesHora = Array.isArray(livres)
    ? [...new Set([...(f.id && f.dia === f.diaOriginal ? [f.horaOriginal] : []), ...livres])].sort()
    : []

  return (
    <Painel aberto={aberto} aoFechar={aoFechar} titulo={f.id ? 'Editar agendamento' : 'Novo agendamento'}
      rodape={
        <div className="flex gap-2">
          <Botao variante="secundario" className="flex-1" onClick={aoFechar}>Cancelar</Botao>
          <Botao className="flex-1" type="submit" form="form-agendamento" carregando={salvando}>Salvar</Botao>
        </div>
      }>
      <form id="form-agendamento" onSubmit={salvar} className="space-y-4">
        <Campo rotulo="Paciente">
          <BuscaPaciente empresaId={empresaId} valor={f.cliente} aoEscolher={(c) => muda('cliente', c)} />
        </Campo>
        {cad.unidades.length > 1 && (
          <Campo rotulo="Unidade">
            <Selecao value={f.unidade_id} onChange={(e) => setF((x) => ({ ...x, unidade_id: e.target.value, profissional_id: '' }))}>
              {cad.unidades.map((u) => <option key={u.id} value={u.id}>{u.nome}</option>)}
            </Selecao>
          </Campo>
        )}
        <Campo rotulo="Serviço">
          <Selecao value={f.servico_id} onChange={(e) => escolherServico(e.target.value)}>
            <option value="">Sem serviço definido</option>
            {cad.servicos.map((sv) => <option key={sv.id} value={sv.id}>{sv.nome} · {duracao(sv.duracao_min)} · {reais(sv.preco)}</option>)}
          </Selecao>
        </Campo>
        <Campo rotulo="Profissional">
          {!profsServico.length ? (
            <p className="rounded-xl bg-amber-50 px-3 py-2 text-sm text-amber-800">Nenhum profissional atende {f.servico_id ? 'este serviço ' : ''}nesta unidade.</p>
          ) : (
            <div className="flex flex-wrap gap-2">
              {profsServico.map((p) => (
                <button key={p.id} type="button" onClick={() => escolherProf(p.id)}
                  className={cx('flex items-center gap-2 rounded-full border px-3 py-1.5 text-sm',
                    f.profissional_id === p.id ? 'border-marca-600 bg-marca-50 font-semibold text-marca-800' : 'border-slate-300 text-slate-700 hover:bg-slate-50')}>
                  <span className="size-2.5 rounded-full" style={{ background: p.cor_agenda }} /> {p.nome}
                </button>
              ))}
            </div>
          )}
        </Campo>
        <div className="grid grid-cols-2 gap-3">
          <Campo rotulo="Data"><Entrada type="date" required value={f.dia} onChange={(e) => muda('dia', e.target.value)} /></Campo>
          <Campo rotulo="Duração (min)"><Entrada type="number" min={5} max={720} step={5} value={f.duracao} onChange={(e) => muda('duracao', e.target.value)} /></Campo>
        </div>
        <p className="-mt-2 text-xs text-slate-500">{diaLongo(deIso(f.dia))}</p>

        <Interruptor ligado={f.encaixe} aoMudar={(v) => muda('encaixe', v)} rotulo="Encaixe"
          descricao="Permite marcar por cima de outro horário do profissional." />

        <Campo rotulo="Horário">
          {!f.encaixe && f.profissional_id && (
            livres === 'carregando' ? <p className="text-sm text-slate-500">Buscando horários livres…</p>
              : opcoesHora.length ? (
                <div className="mb-2 grid grid-cols-4 gap-2 sm:grid-cols-5">
                  {opcoesHora.map((h) => (
                    <button key={h} type="button" onClick={() => muda('hora', h)}
                      className={cx('rounded-lg border py-2 text-sm font-medium',
                        f.hora === h ? 'border-marca-600 bg-marca-700 text-white' : 'border-slate-200 text-slate-700 hover:border-marca-300')}>
                      {h}
                    </button>
                  ))}
                </div>
              ) : <p className="mb-2 rounded-xl bg-slate-50 px-3 py-2 text-sm text-slate-500">Sem horários livres na jornada deste dia. Use outro dia, um horário manual ou encaixe.</p>
          )}
          <div className="flex items-center gap-2">
            <Entrada type="time" step={300} className="w-36!" value={f.hora} onChange={(e) => muda('hora', e.target.value)} />
            <span className="text-xs text-slate-500">{f.encaixe ? 'Horário do encaixe' : 'ou digite outro horário'}</span>
          </div>
        </Campo>

        <Campo rotulo="Valor (R$)" dica="Vem do preço do serviço. Pode alterar.">
          <Entrada inputMode="decimal" placeholder="0,00" value={f.valor} onChange={(e) => muda('valor', e.target.value)} />
        </Campo>
        <Campo rotulo="Observações"><AreaTexto rows={2} value={f.observacoes} onChange={(e) => muda('observacoes', e.target.value)} /></Campo>
        <Alerta>{erro}</Alerta>
      </form>
    </Painel>
  )
}

/* ------------------------------------------------------------------ recebimento */
export function FormRecebimento({ agendamento, sugerido, aoSalvar, aoCancelar }) {
  const s = useSessao()
  const avisar = useAviso()
  const [f, setF] = useState({ valor: paraCampo(sugerido), forma: 'pix', descricao: '' })
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)

  async function salvar() {
    setErro('')
    const valor = numeroBR(f.valor)
    if (!valor || Number.isNaN(valor) || valor <= 0) return setErro('Informe um valor maior que zero.')
    setSalvando(true)
    try {
      ok(await supabase.from('pagamentos').insert({
        empresa_id: s.empresa.id, unidade_id: agendamento.unidade_id, agendamento_id: agendamento.id, cliente_id: agendamento.cliente_id,
        profissional_id: agendamento.profissional_id, valor, forma: f.forma, descricao: f.descricao || null, registrado_por: s.usuario.id,
      }))
      avisar('Recebimento registrado')
      aoSalvar()
    } catch (e) {
      setErro(mensagemErro(e))
    } finally {
      setSalvando(false)
    }
  }

  return (
    <div className="space-y-3 rounded-2xl border border-agua-200 bg-agua-50/50 p-4">
      <p className="text-sm font-semibold text-slate-800">Registrar recebimento</p>
      <div className="grid grid-cols-2 gap-2">
        <Entrada inputMode="decimal" aria-label="Valor" value={f.valor} onChange={(e) => setF({ ...f, valor: e.target.value })} />
        <Selecao aria-label="Forma" value={f.forma} onChange={(e) => setF({ ...f, forma: e.target.value })}>
          {Object.entries(FORMAS_PAGAMENTO).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </Selecao>
      </div>
      <Entrada placeholder="Observação (opcional)" value={f.descricao} onChange={(e) => setF({ ...f, descricao: e.target.value })} />
      <Alerta>{erro}</Alerta>
      <div className="flex gap-2">
        <Botao variante="secundario" className="h-10 flex-1" onClick={aoCancelar}>Cancelar</Botao>
        <Botao variante="agua" className="h-10 flex-1" carregando={salvando} onClick={salvar}>Confirmar</Botao>
      </div>
    </div>
  )
}

/* ------------------------------------------------------------------ detalhe do agendamento */
export function PainelDetalhe({ agendamentoId, cad, aoFechar, aoMudar, aoEditar }) {
  const s = useSessao()
  const avisar = useAviso()
  const opera = useOpera()
  const [receber, setReceber] = useState(false)
  const [cancelar, setCancelar] = useState(null)
  const [ocupado, setOcupado] = useState('')

  const { dados: a, recarregar } = useDados(async () => {
    if (!agendamentoId) return null
    const [ag, pg, hs] = await Promise.all([
      supabase.from('agendamentos').select('*, cliente:clientes(id, nome, telefone, data_nascimento), servico:servicos(id, nome)').eq('id', agendamentoId).single(),
      supabase.from('pagamentos').select('id, valor, forma, recebido_em').eq('agendamento_id', agendamentoId).order('recebido_em'),
      supabase.from('historico_status').select('id, de, para, origem, criado_em').eq('agendamento_id', agendamentoId).order('criado_em'),
    ])
    return { ...ok(ag), pagamentos: ok(pg) ?? [], historico: ok(hs) ?? [] }
  }, [agendamentoId])

  useEffect(() => { setReceber(false); setCancelar(null) }, [agendamentoId])

  if (!agendamentoId) return null
  const prof = a && cad.profissionais.find((p) => p.id === a.profissional_id)
  const unidade = a && cad.unidades.find((u) => u.id === a.unidade_id)
  const pago = a ? a.pagamentos.reduce((t, p) => t + Number(p.valor), 0) : 0
  const saldo = a ? Math.max(0, Number(a.valor || 0) - pago) : 0
  const meu = a && prof?.membro_id && prof.membro_id === s.vinculo?.id
  const podeFinalizar = opera || meu

  async function mudarStatus(status, motivo) {
    setOcupado(status)
    const { error } = await supabase.rpc('atualizar_status_agendamento', { p_agendamento: a.id, p_status: status, p_motivo: motivo ?? null })
    setOcupado('')
    if (error) return avisar(mensagemErro(error), 'erro')
    avisar(`Marcado como ${STATUS_AGENDAMENTO[status].rotulo.toLowerCase()}`)
    setCancelar(null)
    recarregar()
    aoMudar?.()
  }

  const msgWhats = a && `Olá, ${a.cliente.nome.split(' ')[0]}! Aqui é da ${s.empresa.nome}. Seu horário${a.servico ? ` de ${a.servico.nome}` : ''} está marcado para ${dataHora(a.inicio)}${prof ? ` com ${prof.nome}` : ''}. Podemos confirmar?`

  return (
    <Painel aberto={!!agendamentoId} aoFechar={aoFechar} titulo="Agendamento">
      {!a ? <p className="py-10 text-center text-sm text-slate-500">Carregando…</p> : (
        <div className="space-y-5">
          <div className="flex items-start gap-3">
            <span className="mt-1 h-12 w-1.5 shrink-0 rounded-full" style={{ background: prof?.cor_agenda }} />
            <div className="min-w-0 flex-1">
              <Link to={`/pacientes/${a.cliente.id}`} className="text-lg font-semibold text-slate-900 hover:text-marca-700">{a.cliente.nome}</Link>
              <p className="text-sm text-slate-600">{a.servico?.nome ?? 'Atendimento'}{prof && ` · ${prof.nome}`}</p>
              <p className="mt-1 flex items-center gap-1.5 text-sm text-slate-500">
                <Clock className="size-4" /> {diaLongo(a.inicio)}, {horaDe(a.inicio)} às {horaDe(a.fim)}
              </p>
              {cad.unidades.length > 1 && <p className="text-xs text-slate-400">{unidade?.nome}</p>}
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <StatusEtiqueta status={a.status} />
            {a.encaixe && <Etiqueta className="bg-violet-100 text-violet-700"><Zap className="mr-1 size-3" />Encaixe</Etiqueta>}
            {a.origem !== 'painel' && <Etiqueta className="bg-agua-50 text-agua-700">via {ORIGENS[a.origem]}</Etiqueta>}
            {a.valor != null && <Etiqueta className="bg-slate-100 text-slate-700">{reais(a.valor)}</Etiqueta>}
            {pago > 0 && <Etiqueta className="bg-emerald-50 text-emerald-700">Pago {reais(pago)}</Etiqueta>}
          </div>

          {a.cliente.telefone && (
            <div className="flex gap-2">
              <a href={linkWhatsApp(msgWhats, a.cliente.telefone)} target="_blank" rel="noreferrer"
                className="inline-flex h-10 flex-1 items-center justify-center gap-2 rounded-xl bg-emerald-500 text-sm font-semibold text-white hover:bg-emerald-600">
                <MessageCircle className="size-4" /> WhatsApp
              </a>
              <a href={`tel:+${a.cliente.telefone}`} className="inline-flex h-10 flex-1 items-center justify-center gap-2 rounded-xl border border-slate-300 text-sm font-semibold text-slate-700 hover:bg-slate-50">
                <Phone className="size-4" /> {telefone(a.cliente.telefone)}
              </a>
            </div>
          )}

          {a.observacoes && <p className="whitespace-pre-line rounded-xl bg-slate-50 p-3 text-sm text-slate-700">{a.observacoes}</p>}
          {a.status === 'cancelado' && a.motivo_cancelamento && <p className="text-sm text-slate-500">Motivo do cancelamento: {a.motivo_cancelamento}</p>}

          {/* ações de status */}
          {cancelar !== null ? (
            <div className="space-y-2 rounded-2xl border border-red-200 bg-red-50/50 p-4">
              <p className="text-sm font-semibold text-slate-800">Cancelar este agendamento?</p>
              <Entrada placeholder="Motivo (opcional)" value={cancelar} onChange={(e) => setCancelar(e.target.value)} />
              <div className="flex gap-2">
                <Botao variante="secundario" className="h-10 flex-1" onClick={() => setCancelar(null)}>Voltar</Botao>
                <Botao variante="perigo" className="h-10 flex-1" carregando={ocupado === 'cancelado'} onClick={() => mudarStatus('cancelado', cancelar)}>Cancelar horário</Botao>
              </div>
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-2">
              {opera && a.status === 'agendado' && (
                <Botao variante="agua" carregando={ocupado === 'confirmado'} onClick={() => mudarStatus('confirmado')}><Check className="size-4" /> Confirmar</Botao>
              )}
              {podeFinalizar && ['agendado', 'confirmado'].includes(a.status) && (
                <>
                  <Botao carregando={ocupado === 'atendido'} onClick={() => mudarStatus('atendido')}><Check className="size-4" /> Atendido</Botao>
                  <Botao variante="secundario" carregando={ocupado === 'faltou'} onClick={() => mudarStatus('faltou')}><UserX className="size-4" /> Faltou</Botao>
                </>
              )}
              {opera && ['agendado', 'confirmado'].includes(a.status) && (
                <Botao variante="perigo" onClick={() => setCancelar('')}><X className="size-4" /> Cancelar</Botao>
              )}
              {opera && ['faltou', 'cancelado', 'atendido'].includes(a.status) && (
                <Botao variante="secundario" carregando={ocupado === 'agendado'} onClick={() => mudarStatus('agendado')}><RotateCcw className="size-4" /> Reabrir</Botao>
              )}
              {opera && a.status !== 'atendido' && (
                <Botao variante="secundario" onClick={() => aoEditar({ ...a })}><CalendarClock className="size-4" /> Remarcar</Botao>
              )}
              {opera && a.status === 'atendido' && (
                <Botao variante="secundario" onClick={() => aoEditar({ ...a })}><Pencil className="size-4" /> Editar</Botao>
              )}
            </div>
          )}

          {/* financeiro */}
          {opera && a.status === 'atendido' && saldo > 0 && !receber && (
            <Botao variante="agua" className="w-full" onClick={() => setReceber(true)}><Wallet className="size-4" /> Receber {reais(saldo)}</Botao>
          )}
          {opera && a.status === 'atendido' && saldo === 0 && !a.pagamentos.length && !receber && (
            <Botao variante="secundario" className="w-full" onClick={() => setReceber(true)}><Wallet className="size-4" /> Registrar recebimento</Botao>
          )}
          {receber && (
            <FormRecebimento agendamento={a} sugerido={saldo || a.valor} aoCancelar={() => setReceber(false)}
              aoSalvar={() => { setReceber(false); recarregar(); aoMudar?.() }} />
          )}
          {a.pagamentos.length > 0 && (
            <div>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-slate-400">Recebimentos</p>
              <ul className="divide-y divide-slate-100 rounded-xl border border-slate-200">
                {a.pagamentos.map((p) => (
                  <li key={p.id} className="flex items-center justify-between px-3 py-2 text-sm">
                    <span className="text-slate-600">{FORMAS_PAGAMENTO[p.forma]} · {dataHora(p.recebido_em)}</span>
                    <span className="font-semibold text-slate-800">{reais(p.valor)}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {a.historico.length > 0 && (
            <div>
              <p className="mb-1 flex items-center gap-1 text-xs font-semibold uppercase tracking-wide text-slate-400"><History className="size-3.5" /> Histórico</p>
              <ul className="space-y-1 text-xs text-slate-500">
                {a.historico.map((h) => (
                  <li key={h.id}>{dataHora(h.criado_em)} · {h.de ? `${STATUS_AGENDAMENTO[h.de].rotulo} → ` : 'Criado como '}{STATUS_AGENDAMENTO[h.para].rotulo}{h.origem !== 'painel' && ` (${h.origem})`}</li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}
    </Painel>
  )
}

/* ------------------------------------------------------------------ bloqueio de agenda */
export function PainelBloqueio({ aberto, inicial, cad, unidadeId, aoFechar, aoSalvar }) {
  const s = useSessao()
  const avisar = useAviso()
  const [f, setF] = useState(null)
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)

  useEffect(() => {
    if (!aberto) return
    setErro('')
    if (inicial?.id) {
      const de = horaDe(inicial.inicio)
      const ate = horaDe(inicial.fim)
      const diaTodo = isoDia(new Date(inicial.inicio)) !== isoDia(new Date(inicial.fim)) || (de === '00:00' && ate === '23:59')
      setF({ ...inicial, dia: isoDia(new Date(inicial.inicio)), ate_dia: isoDia(new Date(inicial.fim)), de, ate, profissional_id: inicial.profissional_id ?? '', motivo: inicial.motivo ?? '', diaTodo })
    } else {
      setF({ unidade_id: unidadeId, profissional_id: inicial?.profissional_id ?? '', dia: inicial?.dia ?? isoDia(new Date()), ate_dia: '', de: '12:00', ate: '13:00', motivo: '', diaTodo: false })
    }
  }, [aberto, inicial, unidadeId])

  if (!aberto || !f) return null
  const profs = profissionaisDaUnidade(cad, f.unidade_id)

  async function salvar(e) {
    e.preventDefault()
    setErro('')
    const inicio = deIso(f.dia, f.diaTodo ? '00:00' : f.de)
    const fim = f.diaTodo ? deIso(f.ate_dia || f.dia, '23:59') : deIso(f.dia, f.ate)
    if (fim <= inicio) return setErro('O fim precisa ser depois do início.')
    setSalvando(true)
    try {
      const reg = { empresa_id: s.empresa.id, unidade_id: f.unidade_id, profissional_id: f.profissional_id || null, inicio: inicio.toISOString(), fim: fim.toISOString(), motivo: f.motivo || null }
      if (f.id) ok(await supabase.from('bloqueios_agenda').update(reg).eq('id', f.id))
      else ok(await supabase.from('bloqueios_agenda').insert({ ...reg, criado_por: s.usuario.id }))
      avisar('Bloqueio salvo')
      aoSalvar?.()
      aoFechar()
    } catch (err) {
      setErro(mensagemErro(err))
    } finally {
      setSalvando(false)
    }
  }

  async function remover() {
    setSalvando(true)
    const { error } = await supabase.from('bloqueios_agenda').delete().eq('id', f.id)
    setSalvando(false)
    if (error) return setErro(mensagemErro(error))
    avisar('Bloqueio removido')
    aoSalvar?.()
    aoFechar()
  }

  return (
    <Painel aberto={aberto} aoFechar={aoFechar} titulo={f.id ? 'Bloqueio de agenda' : 'Bloquear horário'}
      rodape={
        <div className="flex gap-2">
          {f.id ? <Botao variante="perigo" className="flex-1" carregando={salvando} onClick={remover}><Trash2 className="size-4" /> Remover</Botao>
            : <Botao variante="secundario" className="flex-1" onClick={aoFechar}>Cancelar</Botao>}
          <Botao className="flex-1" type="submit" form="form-bloqueio" carregando={salvando}>Salvar</Botao>
        </div>
      }>
      <form id="form-bloqueio" onSubmit={salvar} className="space-y-4">
        <p className="text-sm text-slate-500">Use para folgas, feriados, reuniões ou almoço. Ninguém consegue marcar nesse período, nem pelo WhatsApp.</p>
        <Campo rotulo="Quem fica bloqueado">
          <Selecao value={f.profissional_id} onChange={(e) => setF({ ...f, profissional_id: e.target.value })}>
            <option value="">Unidade inteira (todos os profissionais)</option>
            {profs.map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
          </Selecao>
        </Campo>
        {<Interruptor ligado={f.diaTodo} aoMudar={(v) => setF({ ...f, diaTodo: v })} rotulo="Dia inteiro" descricao="Pode cobrir vários dias seguidos (férias, feriado prolongado)." />}
        <div className="grid grid-cols-2 gap-3">
          <Campo rotulo={f.diaTodo ? 'Do dia' : 'Dia'}><Entrada type="date" required value={f.dia} onChange={(e) => setF({ ...f, dia: e.target.value })} /></Campo>
          {f.diaTodo && <Campo rotulo="Até o dia"><Entrada type="date" value={f.ate_dia} min={f.dia} onChange={(e) => setF({ ...f, ate_dia: e.target.value })} /></Campo>}
        </div>
        {!f.diaTodo && (
          <div className="grid grid-cols-2 gap-3">
            <Campo rotulo="Das"><Entrada type="time" required value={f.de} onChange={(e) => setF({ ...f, de: e.target.value })} /></Campo>
            <Campo rotulo="Até"><Entrada type="time" required value={f.ate} onChange={(e) => setF({ ...f, ate: e.target.value })} /></Campo>
          </div>
        )}
        <Campo rotulo="Motivo"><Entrada placeholder="Ex.: Almoço, Feriado, Congresso" value={f.motivo ?? ''} onChange={(e) => setF({ ...f, motivo: e.target.value })} /></Campo>
        <Alerta>{erro}</Alerta>
      </form>
    </Painel>
  )
}

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { ChevronLeft, ChevronRight, Plus, Ban, CalendarDays, RefreshCw, Zap, MessageCircle } from 'lucide-react'
import { Botao, Cartao, Carregando, Selecao, Vazio, cx } from '../components/ui.jsx'
import {
  PainelAgendamento, PainelBloqueio, PainelDetalhe, StatusEtiqueta, profissionaisDaUnidade, useCadastros, useOpera,
} from '../components/Atendimento.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { supabase } from '../lib/supabase.js'
import { ok } from '../lib/useDados.js'
import {
  STATUS_AGENDAMENTO, diaCurto, diaLongo, horaDe, inicioDia, inicioSemana, isoDia, minParaHora, minutosDe, somarDias,
} from '../lib/agenda.js'

const PX_MIN = 1.6 // altura de 1 minuto na grade (1h = 96px)
const CHAVE = 'sc_agenda_pref'

function lerPref() {
  try { return JSON.parse(localStorage.getItem(CHAVE)) ?? {} } catch { return {} }
}

const minutos = (t) => { const [h, m] = String(t).split(':').map(Number); return h * 60 + m }

/** distribui agendamentos sobrepostos em colunas lado a lado */
function emFaixas(itens) {
  const ord = [...itens].sort((a, b) => new Date(a.inicio) - new Date(b.inicio))
  const fimFaixa = []
  const res = ord.map((a) => {
    const ini = new Date(a.inicio).getTime()
    let faixa = fimFaixa.findIndex((f) => f <= ini)
    if (faixa === -1) { faixa = fimFaixa.length; fimFaixa.push(0) }
    fimFaixa[faixa] = new Date(a.fim).getTime()
    return { a, faixa }
  })
  return res.map((r) => {
    const ini = new Date(r.a.inicio).getTime()
    const fim = new Date(r.a.fim).getTime()
    const sobre = res.filter((o) => new Date(o.a.inicio).getTime() < fim && new Date(o.a.fim).getTime() > ini)
    return { ...r, total: Math.max(...sobre.map((o) => o.faixa)) + 1 }
  })
}

export default function Agenda() {
  const s = useSessao()
  const opera = useOpera()
  const navegar = useNavigate()
  const [params, setParams] = useSearchParams()
  const empresaId = s.empresa.id
  const pref = useMemo(lerPref, [])
  const { dados: cad, carregando: carregandoCad } = useCadastros(empresaId)

  const [dia, setDia] = useState(() => inicioDia(new Date()))
  const [visao, setVisao] = useState(pref.visao ?? 'dia')
  const [unidadeId, setUnidadeId] = useState(pref.unidadeId ?? '')
  const [profFiltro, setProfFiltro] = useState(pref.prof ?? '')
  const [verCancelados, setVerCancelados] = useState(false)
  const [itens, setItens] = useState(null)
  const [atualizando, setAtualizando] = useState(false)

  const [novo, setNovo] = useState(null) // dados iniciais do formulário
  const [detalhe, setDetalhe] = useState(null)
  const [bloqueio, setBloqueio] = useState(null)

  // unidade padrão
  useEffect(() => {
    if (!cad) return
    if (!cad.unidades.some((u) => u.id === unidadeId)) setUnidadeId(cad.unidades[0]?.id ?? '')
  }, [cad, unidadeId])

  useEffect(() => {
    try { localStorage.setItem(CHAVE, JSON.stringify({ visao, unidadeId, prof: profFiltro })) } catch { /* sem armazenamento */ }
  }, [visao, unidadeId, profFiltro])

  // abrir "novo agendamento" vindo da ficha do paciente
  useEffect(() => {
    if (!cad || params.get('novo') == null) return
    const clienteId = params.get('cliente')
    ;(async () => {
      const cliente = clienteId ? (await supabase.from('clientes').select('id, nome, telefone').eq('id', clienteId).maybeSingle()).data : null
      setNovo({ cliente, unidade_id: unidadeId || cad.unidades[0]?.id })
      setParams({}, { replace: true })
    })()
  }, [cad, params]) // eslint-disable-line react-hooks/exhaustive-deps

  const periodo = useMemo(() => {
    const ini = visao === 'semana' ? inicioSemana(dia) : dia
    return { ini, fim: somarDias(ini, visao === 'semana' ? 7 : 1) }
  }, [dia, visao])

  const profsUnidade = useMemo(() => (cad && unidadeId ? profissionaisDaUnidade(cad, unidadeId) : []), [cad, unidadeId])
  const meuProf = cad?.profissionais.find((p) => p.membro_id && p.membro_id === s.vinculo?.id)?.id

  const carregar = useCallback(async () => {
    if (!unidadeId) return
    setAtualizando(true)
    try {
      const [ag, bl] = await Promise.all([
        supabase.from('agendamentos')
          .select('id, unidade_id, profissional_id, cliente_id, servico_id, inicio, fim, status, encaixe, origem, valor, observacoes, cliente:clientes(id, nome, telefone), servico:servicos(id, nome, cor)')
          .eq('empresa_id', empresaId).eq('unidade_id', unidadeId)
          .gte('inicio', periodo.ini.toISOString()).lt('inicio', periodo.fim.toISOString()).order('inicio'),
        supabase.from('bloqueios_agenda').select('*').eq('empresa_id', empresaId).eq('unidade_id', unidadeId)
          .lt('inicio', periodo.fim.toISOString()).gt('fim', periodo.ini.toISOString()),
      ])
      setItens({ agendamentos: ok(ag), bloqueios: ok(bl) })
    } catch {
      setItens((x) => x ?? { agendamentos: [], bloqueios: [] })
    } finally {
      setAtualizando(false)
    }
  }, [empresaId, unidadeId, periodo])

  useEffect(() => { carregar() }, [carregar])
  useEffect(() => {
    const t = setInterval(carregar, 60000)
    const foco = () => document.visibilityState === 'visible' && carregar()
    document.addEventListener('visibilitychange', foco)
    return () => { clearInterval(t); document.removeEventListener('visibilitychange', foco) }
  }, [carregar])

  if (carregandoCad || !cad) return <Carregando />
  if (!cad.unidades.length) return <Vazio icone={CalendarDays} titulo="Nenhuma unidade disponível" texto="Cadastre uma unidade para usar a agenda." />

  const passo = visao === 'semana' ? 7 : 1
  const hoje = inicioDia(new Date())
  const agFiltrados = (itens?.agendamentos ?? []).filter((a) =>
    (verCancelados || a.status !== 'cancelado') && (!profFiltro || a.profissional_id === profFiltro))
  const cancelados = (itens?.agendamentos ?? []).filter((a) => a.status === 'cancelado').length
  const titulo = visao === 'semana'
    ? `${diaCurto(periodo.ini)} a ${diaCurto(somarDias(periodo.fim, -1))}`
    : diaLongo(dia)

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold text-slate-900 md:text-2xl">Agenda</h1>
          <p className="text-sm text-slate-500">{titulo}</p>
        </div>
        {opera && (
          <div className="flex gap-2">
            <Botao variante="secundario" onClick={() => setBloqueio({ dia: isoDia(dia), profissional_id: profFiltro })}>
              <Ban className="size-4" /> <span className="hidden sm:inline">Bloquear</span>
            </Botao>
            <Botao onClick={() => setNovo({ unidade_id: unidadeId, dia: isoDia(dia < hoje ? hoje : dia), profissional_id: profFiltro })}>
              <Plus className="size-4" /> Agendar
            </Botao>
          </div>
        )}
      </div>

      {/* barra de controles */}
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <div className="flex items-center rounded-xl border border-slate-200 bg-white">
          <button onClick={() => setDia((d) => somarDias(d, -passo))} className="p-2.5 text-slate-600 hover:bg-slate-50" aria-label="Anterior"><ChevronLeft className="size-5" /></button>
          <button onClick={() => setDia(hoje)} className="border-x border-slate-200 px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50">Hoje</button>
          <button onClick={() => setDia((d) => somarDias(d, passo))} className="p-2.5 text-slate-600 hover:bg-slate-50" aria-label="Próximo"><ChevronRight className="size-5" /></button>
        </div>
        <input type="date" value={isoDia(dia)} onChange={(e) => e.target.value && setDia(new Date(`${e.target.value}T00:00`))}
          className="h-11 rounded-xl border border-slate-200 bg-white px-3 text-sm text-slate-700" aria-label="Ir para a data" />
        <div className="flex rounded-xl bg-slate-100 p-1">
          {[['dia', 'Dia'], ['semana', 'Semana']].map(([v, r]) => (
            <button key={v} onClick={() => setVisao(v)}
              className={cx('rounded-lg px-3 py-1.5 text-sm font-medium', visao === v ? 'bg-white text-marca-700 shadow-sm' : 'text-slate-500')}>{r}</button>
          ))}
        </div>
        {cad.unidades.length > 1 && (
          <Selecao className="h-11 w-auto! min-w-36" value={unidadeId} onChange={(e) => { setUnidadeId(e.target.value); setProfFiltro('') }} aria-label="Unidade">
            {cad.unidades.map((u) => <option key={u.id} value={u.id}>{u.nome}</option>)}
          </Selecao>
        )}
        {profsUnidade.length > 1 && (
          <Selecao className="h-11 w-auto! min-w-40" value={profFiltro} onChange={(e) => setProfFiltro(e.target.value)} aria-label="Profissional">
            <option value="">Todos os profissionais</option>
            {meuProf && <option value={meuProf}>Minha agenda</option>}
            {profsUnidade.map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
          </Selecao>
        )}
        <button onClick={carregar} className="ml-auto rounded-full p-2 text-slate-400 hover:bg-slate-100" aria-label="Atualizar">
          <RefreshCw className={cx('size-4', atualizando && 'animate-spin')} />
        </button>
      </div>

      {cancelados > 0 && (
        <label className="mb-3 flex w-fit items-center gap-2 text-xs text-slate-500">
          <input type="checkbox" checked={verCancelados} onChange={(e) => setVerCancelados(e.target.checked)} />
          Mostrar {cancelados} {cancelados === 1 ? 'cancelado' : 'cancelados'}
        </label>
      )}

      {!profsUnidade.length ? (
        <Vazio icone={CalendarDays} titulo="Nenhum profissional nesta unidade"
          texto="Cadastre os profissionais, ligue-os à unidade e defina a jornada para usar a agenda."
          acao={s.eDono && <Botao onClick={() => navegar('/profissionais')}>Ir para profissionais</Botao>} />
      ) : !itens ? <Carregando /> : visao === 'dia' ? (
        <GradeDia
          dia={dia} cad={cad} unidadeId={unidadeId}
          profs={profFiltro ? profsUnidade.filter((p) => p.id === profFiltro) : profsUnidade}
          agendamentos={agFiltrados} bloqueios={itens.bloqueios}
          opera={opera}
          aoClicarVazio={(profissional_id, hora) => setNovo({ unidade_id: unidadeId, dia: isoDia(dia), profissional_id, hora })}
          aoAbrir={(a) => setDetalhe(a.id)} aoAbrirBloqueio={(b) => opera && setBloqueio(b)}
        />
      ) : (
        <Semana ini={periodo.ini} cad={cad} agendamentos={agFiltrados} bloqueios={itens.bloqueios}
          profFiltro={profFiltro} aoAbrir={(a) => setDetalhe(a.id)} aoAbrirDia={(d) => { setDia(d); setVisao('dia') }} />
      )}

      <PainelAgendamento aberto={!!novo} inicial={novo} cad={cad} aoFechar={() => setNovo(null)} aoSalvar={carregar} />
      <PainelDetalhe agendamentoId={detalhe} cad={cad} aoFechar={() => setDetalhe(null)} aoMudar={carregar}
        aoEditar={(a) => { setDetalhe(null); setNovo(a) }} />
      <PainelBloqueio aberto={!!bloqueio} inicial={bloqueio} cad={cad} unidadeId={unidadeId} aoFechar={() => setBloqueio(null)} aoSalvar={carregar} />
    </div>
  )
}

/* ------------------------------------------------------------------ visão do dia (grade por profissional) */
function GradeDia({ dia, cad, unidadeId, profs, agendamentos, bloqueios, opera, aoClicarVazio, aoAbrir, aoAbrirBloqueio }) {
  const rolagem = useRef(null)
  const dow = dia.getDay()
  const jornadas = cad.jornadas.filter((j) => j.unidade_id === unidadeId && j.dia_semana === dow)
  const horario = cad.horarios.filter((h) => h.unidade_id === unidadeId && h.dia_semana === dow)

  // faixa visível: horário da unidade/jornadas, ampliado pelos agendamentos do dia
  let ini = Math.min(...[...jornadas.map((j) => minutos(j.inicio)), ...horario.map((h) => minutos(h.abre))], 8 * 60)
  let fim = Math.max(...[...jornadas.map((j) => minutos(j.fim)), ...horario.map((h) => minutos(h.fecha))], 18 * 60)
  for (const a of agendamentos) {
    ini = Math.min(ini, minutosDe(a.inicio))
    fim = Math.max(fim, new Date(a.fim).getDate() !== dia.getDate() ? 24 * 60 : minutosDe(a.fim))
  }
  ini = Math.floor(ini / 60) * 60
  fim = Math.min(24 * 60, Math.ceil(fim / 60) * 60)
  const altura = (fim - ini) * PX_MIN
  const horas = []
  for (let m = ini; m < fim; m += 60) horas.push(m)

  const agora = new Date()
  const ehHoje = isoDia(agora) === isoDia(dia)
  const agoraMin = agora.getHours() * 60 + agora.getMinutes()

  // ao abrir hoje, rola até perto do horário atual
  useEffect(() => {
    if (ehHoje && rolagem.current) rolagem.current.scrollTop = Math.max(0, (agoraMin - ini - 60) * PX_MIN)
  }, [ehHoje]) // eslint-disable-line react-hooks/exhaustive-deps

  const diaIni = inicioDia(dia).getTime()
  const posBloqueio = (b) => {
    const bi = Math.max(new Date(b.inicio).getTime(), diaIni)
    const bf = Math.min(new Date(b.fim).getTime(), diaIni + 86400000)
    const top = Math.max(0, (bi - diaIni) / 60000 - ini)
    const bottom = Math.min(fim - ini, (bf - diaIni) / 60000 - ini)
    return { top: top * PX_MIN, height: Math.max(0, bottom - top) * PX_MIN }
  }

  const clicar = (e, profId) => {
    if (!opera) return
    const y = e.clientY - e.currentTarget.getBoundingClientRect().top
    const m = ini + Math.floor(y / PX_MIN / 15) * 15
    aoClicarVazio(profId, minParaHora(m))
  }

  return (
    <Cartao className="overflow-hidden">
      <div ref={rolagem} className="max-h-[calc(100dvh-15rem)] overflow-auto md:max-h-[calc(100dvh-13rem)]">
        <div className="flex min-w-fit">
          {/* coluna de horas */}
          <div className="sticky left-0 z-20 w-14 shrink-0 border-r border-slate-100 bg-white">
            <div className="sticky top-0 z-10 h-12 border-b border-slate-200 bg-white" />
            <div className="relative" style={{ height: altura }}>
              {horas.map((m) => (
                <span key={m} className="absolute right-2 -translate-y-2 text-[11px] text-slate-400" style={{ top: (m - ini) * PX_MIN }}>
                  {m === ini ? '' : minParaHora(m)}
                </span>
              ))}
            </div>
          </div>

          {profs.map((p) => {
            const meus = agendamentos.filter((a) => a.profissional_id === p.id)
            const jp = jornadas.filter((j) => j.profissional_id === p.id)
            const bl = bloqueios.filter((b) => !b.profissional_id || b.profissional_id === p.id)
            return (
              <div key={p.id} className="min-w-40 flex-1 border-r border-slate-100 last:border-r-0">
                <div className="sticky top-0 z-10 flex h-12 items-center gap-2 border-b border-slate-200 bg-white px-3">
                  <span className="size-2.5 shrink-0 rounded-full" style={{ background: p.cor_agenda }} />
                  <span className="truncate text-sm font-semibold text-slate-800">{p.nome}</span>
                  <span className="ml-auto text-xs text-slate-400">{meus.filter((a) => a.status !== 'cancelado').length || ''}</span>
                </div>
                <div className={cx('relative bg-slate-50', opera && 'cursor-pointer')} style={{ height: altura }} onClick={(e) => clicar(e, p.id)}>
                  {/* jornada (área branca) */}
                  {jp.map((j, i) => (
                    <div key={i} className="absolute inset-x-0 bg-white"
                      style={{ top: (minutos(j.inicio) - ini) * PX_MIN, height: (minutos(j.fim) - minutos(j.inicio)) * PX_MIN }} />
                  ))}
                  {/* linhas das horas */}
                  {horas.map((m) => (
                    <div key={m} className="pointer-events-none absolute inset-x-0 border-t border-slate-100" style={{ top: (m - ini) * PX_MIN }}>
                      <div className="border-t border-dashed border-slate-50" style={{ marginTop: 30 * PX_MIN }} />
                    </div>
                  ))}
                  {/* bloqueios */}
                  {bl.map((b) => {
                    const pos = posBloqueio(b)
                    if (!pos.height) return null
                    return (
                      <button key={b.id} onClick={(e) => { e.stopPropagation(); aoAbrirBloqueio(b) }}
                        className="absolute inset-x-1 z-[5] overflow-hidden rounded-lg border border-slate-300 px-2 py-1 text-left text-xs text-slate-500"
                        style={{ ...pos, backgroundImage: 'repeating-linear-gradient(45deg, #f1f5f9 0 6px, #e2e8f0 6px 12px)' }}>
                        <span className="font-medium">Bloqueado</span>{b.motivo && ` · ${b.motivo}`}
                      </button>
                    )
                  })}
                  {/* agendamentos */}
                  {emFaixas(meus).map(({ a, faixa, total }) => {
                    const top = (minutosDe(a.inicio) - ini) * PX_MIN
                    const dur = (new Date(a.fim) - new Date(a.inicio)) / 60000
                    const h = Math.max(22, dur * PX_MIN - 2)
                    const cor = a.servico?.cor || p.cor_agenda
                    const st = STATUS_AGENDAMENTO[a.status]
                    return (
                      <button key={a.id} onClick={(e) => { e.stopPropagation(); aoAbrir(a) }}
                        className={cx('absolute z-10 overflow-hidden rounded-lg border-l-4 px-2 py-0.5 text-left shadow-sm transition hover:z-20 hover:shadow-md',
                          a.status === 'cancelado' && 'opacity-50 line-through', a.status === 'faltou' && 'opacity-70')}
                        style={{
                          top: top + 1, height: h, left: `calc(${(faixa / total) * 100}% + 3px)`, width: `calc(${100 / total}% - 6px)`,
                          background: `${cor}1F`, borderLeftColor: st.ponto,
                        }}>
                        {h < 40 ? (
                          <p className="truncate text-xs text-slate-800"><b className="text-slate-600">{horaDe(a.inicio)}</b>{a.encaixe && ' ⚡'} {a.cliente?.nome}</p>
                        ) : (<>
                        <p className="flex items-center gap-1 truncate text-[11px] font-semibold text-slate-600">
                          {horaDe(a.inicio)}
                          {a.encaixe && <Zap className="size-3 text-violet-600" />}
                          {a.origem === 'whatsapp' && <MessageCircle className="size-3 text-emerald-600" />}
                          {a.status === 'confirmado' && <span className="text-agua-700">✓</span>}
                        </p>
                        <p className="truncate text-sm font-semibold leading-tight text-slate-900">{a.cliente?.nome}</p>
                        {h > 50 && <p className="truncate text-xs text-slate-600">{a.servico?.nome}</p>}
                        </>)}
                      </button>
                    )
                  })}
                  {/* linha do horário atual */}
                  {ehHoje && agoraMin >= ini && agoraMin <= fim && (
                    <div className="pointer-events-none absolute inset-x-0 z-30 border-t-2 border-red-400" style={{ top: (agoraMin - ini) * PX_MIN }}>
                      <span className="absolute -left-1 -top-[5px] size-2 rounded-full bg-red-400" />
                    </div>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      </div>
      <Legenda />
    </Cartao>
  )
}

function Legenda() {
  return (
    <div className="flex flex-wrap gap-x-4 gap-y-1 border-t border-slate-100 px-4 py-2 text-[11px] text-slate-500">
      {Object.entries(STATUS_AGENDAMENTO).map(([k, v]) => (
        <span key={k} className="flex items-center gap-1"><span className="h-3 w-1 rounded-full" style={{ background: v.ponto }} />{v.rotulo}</span>
      ))}
      <span className="flex items-center gap-1"><Zap className="size-3 text-violet-600" />Encaixe</span>
    </div>
  )
}

/* ------------------------------------------------------------------ visão da semana */
function Semana({ ini, cad, agendamentos, bloqueios, profFiltro, aoAbrir, aoAbrirDia }) {
  const dias = Array.from({ length: 7 }, (_, i) => somarDias(ini, i))
  const hoje = isoDia(new Date())
  const profs = Object.fromEntries(cad.profissionais.map((p) => [p.id, p]))
  return (
    <div className="grid gap-3 lg:grid-cols-7 lg:gap-2">
      {dias.map((d) => {
        const lista = agendamentos.filter((a) => isoDia(new Date(a.inicio)) === isoDia(d))
        const bl = bloqueios.filter((b) => new Date(b.inicio) < somarDias(d, 1) && new Date(b.fim) > d && (!profFiltro || !b.profissional_id || b.profissional_id === profFiltro))
        const ehHoje = isoDia(d) === hoje
        return (
          <Cartao key={isoDia(d)} className={cx('flex flex-col overflow-hidden', ehHoje && 'ring-2 ring-agua-400')}>
            <button onClick={() => aoAbrirDia(d)} className={cx('flex items-center justify-between border-b border-slate-100 px-3 py-2 text-left hover:bg-slate-50', ehHoje && 'bg-agua-50')}>
              <span className="text-sm font-semibold text-slate-800">{diaCurto(d)}</span>
              <span className="text-xs text-slate-400">{lista.filter((a) => a.status !== 'cancelado').length || ''}</span>
            </button>
            <div className="flex-1 space-y-1 p-2">
              {bl.map((b) => (
                <p key={b.id} className="rounded-md bg-slate-100 px-2 py-1 text-[11px] text-slate-500">
                  Bloqueado{b.profissional_id ? ` · ${profs[b.profissional_id]?.nome ?? ''}` : ''}{b.motivo ? ` · ${b.motivo}` : ''}
                </p>
              ))}
              {!lista.length && !bl.length && <p className="px-1 py-2 text-xs text-slate-300">Livre</p>}
              {lista.map((a) => (
                <button key={a.id} onClick={() => aoAbrir(a)}
                  className={cx('flex w-full items-start gap-2 rounded-lg px-2 py-1.5 text-left hover:bg-slate-50', a.status === 'cancelado' && 'opacity-50 line-through')}>
                  <span className="mt-1 h-7 w-1 shrink-0 rounded-full" style={{ background: STATUS_AGENDAMENTO[a.status].ponto }} />
                  <span className="min-w-0 flex-1">
                    <span className="block text-[11px] font-semibold text-slate-500">
                      {horaDe(a.inicio)}{!profFiltro && profs[a.profissional_id] && ` · ${profs[a.profissional_id].nome.split(' ')[0]}`}
                    </span>
                    <span className="block truncate text-sm font-medium text-slate-800">{a.cliente?.nome}</span>
                  </span>
                  <span className="lg:hidden"><StatusEtiqueta status={a.status} /></span>
                </button>
              ))}
            </div>
          </Cartao>
        )
      })}
    </div>
  )
}

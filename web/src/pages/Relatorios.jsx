import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { Lock, Table2, BarChart3 } from 'lucide-react'
import { Cartao, Carregando, Entrada, Selecao, cx } from '../components/ui.jsx'
import { useCadastros } from '../components/Atendimento.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { supabase } from '../lib/supabase.js'
import { ok, useDados } from '../lib/useDados.js'
import { reais } from '../lib/formato.js'
import { FORMAS_PAGAMENTO, STATUS_AGENDAMENTO, deIso, inicioDia, inicioMes, isoDia, somarDias } from '../lib/agenda.js'

const PERIODOS = [
  ['mes', 'Este mês'],
  ['mes_passado', 'Mês passado'],
  ['7', 'Últimos 7 dias'],
  ['30', 'Últimos 30 dias'],
  ['90', 'Últimos 90 dias'],
  ['outro', 'Escolher datas'],
]

function intervalo(p, de, ate) {
  const hoje = inicioDia(new Date())
  if (p === 'mes') return [inicioMes(hoje), somarDias(hoje, 1)]
  if (p === 'mes_passado') return [new Date(hoje.getFullYear(), hoje.getMonth() - 1, 1), inicioMes(hoje)]
  if (p === 'outro') return [deIso(de), somarDias(deIso(ate), 1)]
  return [somarDias(hoje, -Number(p) + 1), somarDias(hoje, 1)]
}

export default function Relatorios() {
  const s = useSessao()
  const empresaId = s.empresa.id
  const completo = !!s.plano?.recursos?.relatorios_completos
  const [periodo, setPeriodo] = useState('mes')
  const [de, setDe] = useState(isoDia(inicioMes(new Date())))
  const [ate, setAte] = useState(isoDia(new Date()))
  const [unidadeId, setUnidadeId] = useState('')
  const { dados: cad } = useCadastros(empresaId)
  const [ini, fim] = useMemo(() => intervalo(periodo, de, ate), [periodo, de, ate])

  const { dados: rel, carregando } = useDados(async () => ok(await supabase.rpc('relatorio_periodo', {
    p_empresa: empresaId, p_inicio: ini.toISOString(), p_fim: fim.toISOString(), p_unidade: unidadeId || null,
  })), [empresaId, ini.getTime(), fim.getTime(), unidadeId])

  return (
    <div>
      <div className="mb-4">
        <h1 className="text-xl font-bold text-slate-900 md:text-2xl">Relatórios</h1>
        <p className="text-sm text-slate-500">Agendamentos, faltas, faturamento e pacientes novos</p>
      </div>

      <div className="mb-5 flex flex-wrap items-center gap-2">
        <Selecao className="h-11 w-auto!" value={periodo} onChange={(e) => setPeriodo(e.target.value)} aria-label="Período">
          {PERIODOS.map(([k, r]) => <option key={k} value={k}>{r}</option>)}
        </Selecao>
        {periodo === 'outro' && (
          <>
            <Entrada type="date" className="w-auto!" value={de} onChange={(e) => e.target.value && setDe(e.target.value)} aria-label="De" />
            <Entrada type="date" className="w-auto!" value={ate} min={de} onChange={(e) => e.target.value && setAte(e.target.value)} aria-label="Até" />
          </>
        )}
        {cad?.unidades.length > 1 && (
          <Selecao className="h-11 w-auto!" value={unidadeId} onChange={(e) => setUnidadeId(e.target.value)} aria-label="Unidade">
            <option value="">Todas as unidades</option>
            {cad.unidades.map((u) => <option key={u.id} value={u.id}>{u.nome}</option>)}
          </Selecao>
        )}
      </div>

      {carregando && !rel ? <Carregando /> : !rel ? null : (
        <div className="space-y-5">
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
            <Kpi rotulo="Agendamentos" valor={rel.agendamentos} />
            <Kpi rotulo="Taxa de faltas" valor={`${rel.taxa_faltas}%`} detalhe={`${rel.por_status?.faltou ?? 0} faltas`} />
            <Kpi rotulo="Faturamento" valor={reais(rel.faturamento)} />
            <Kpi rotulo="Ticket médio" valor={reais(rel.ticket_medio)} />
            <Kpi rotulo="Pacientes novos" valor={rel.novos_clientes} />
          </div>

          <div className="grid gap-5 lg:grid-cols-3">
            <Cartao className="p-5 lg:col-span-2">
              <GraficoDias dias={rel.por_dia} />
            </Cartao>
            <Cartao className="p-5">
              <p className="mb-4 text-sm font-semibold text-slate-800">Situação dos agendamentos</p>
              <Barras itens={Object.keys(STATUS_AGENDAMENTO).map((k) => ({
                rotulo: STATUS_AGENDAMENTO[k].rotulo, valor: rel.por_status?.[k] ?? 0, cor: STATUS_AGENDAMENTO[k].ponto, texto: String(rel.por_status?.[k] ?? 0),
              }))} />
            </Cartao>
          </div>

          {completo ? (
            <div className="grid gap-5 lg:grid-cols-2">
              <Cartao className="overflow-x-auto">
                <p className="px-5 pt-5 text-sm font-semibold text-slate-800">Por profissional</p>
                <table className="mt-2 w-full min-w-[420px] text-sm">
                  <thead>
                    <tr className="border-b border-slate-100 text-left text-xs uppercase tracking-wide text-slate-400">
                      <th className="px-5 py-2 font-semibold">Profissional</th>
                      <th className="px-2 py-2 text-right font-semibold">Agend.</th>
                      <th className="px-2 py-2 text-right font-semibold">Faltas</th>
                      <th className="px-5 py-2 text-right font-semibold">Faturado</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {rel.por_profissional.map((p) => (
                      <tr key={p.id}>
                        <td className="px-5 py-2.5"><span className="flex items-center gap-2 text-slate-800"><span className="size-2.5 rounded-full" style={{ background: p.cor }} />{p.nome}</span></td>
                        <td className="px-2 py-2.5 text-right text-slate-700">{p.agendamentos}</td>
                        <td className="px-2 py-2.5 text-right text-slate-700">{p.faltas}</td>
                        <td className="px-5 py-2.5 text-right font-medium text-slate-900">{reais(p.faturamento)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </Cartao>
              <Cartao className="p-5">
                <p className="mb-4 text-sm font-semibold text-slate-800">Serviços mais feitos</p>
                {!rel.por_servico.length ? <p className="text-sm text-slate-400">Nenhum atendimento concluído no período.</p> : (
                  <Barras itens={rel.por_servico.map((x) => ({ rotulo: x.nome, valor: Number(x.qtd), cor: '#14B8A6', texto: `${x.qtd} · ${reais(x.valor)}` }))} />
                )}
              </Cartao>
              <Cartao className="p-5">
                <p className="mb-4 text-sm font-semibold text-slate-800">Faturamento por forma de pagamento</p>
                {!Object.keys(rel.por_forma).length ? <p className="text-sm text-slate-400">Nenhum recebimento no período.</p> : (
                  <Barras itens={Object.entries(rel.por_forma).sort((a, b) => b[1] - a[1]).map(([k, v]) => ({ rotulo: FORMAS_PAGAMENTO[k], valor: Number(v), cor: '#2563EB', texto: reais(v) }))} />
                )}
              </Cartao>
              <Cartao className="p-5">
                <p className="mb-1 text-sm font-semibold text-slate-800">A receber</p>
                <p className="text-2xl font-bold text-slate-900">{reais(rel.a_receber)}</p>
                <p className="mt-1 text-sm text-slate-500">Atendimentos concluídos sem recebimento registrado.</p>
                <Link to="/financeiro" className="mt-3 inline-block text-sm font-semibold text-marca-700 hover:underline">Ir para o financeiro</Link>
              </Cartao>
            </div>
          ) : (
            <Cartao className="flex items-center gap-4 p-5">
              <span className="grid size-11 shrink-0 place-items-center rounded-2xl bg-marca-50 text-marca-700"><Lock className="size-5" /></span>
              <div>
                <p className="font-semibold text-slate-900">Relatórios completos no plano Profissional</p>
                <p className="text-sm text-slate-500">Números por profissional, serviços mais feitos e faturamento por forma de pagamento.</p>
              </div>
            </Cartao>
          )}
        </div>
      )}
    </div>
  )
}

function Kpi({ rotulo, valor, detalhe }) {
  return (
    <Cartao className="p-4">
      <p className="text-xs text-slate-500">{rotulo}</p>
      <p className="mt-1 text-xl font-bold text-slate-900">{valor}</p>
      {detalhe && <p className="text-xs text-slate-400">{detalhe}</p>}
    </Cartao>
  )
}

/** barras horizontais com rótulo e valor em texto (a cor só acompanha) */
function Barras({ itens }) {
  const max = Math.max(1, ...itens.map((i) => i.valor))
  return (
    <div className="space-y-3">
      {itens.map((i) => (
        <div key={i.rotulo}>
          <div className="mb-1 flex justify-between gap-2 text-sm">
            <span className="truncate text-slate-600">{i.rotulo}</span>
            <span className="shrink-0 font-medium text-slate-800">{i.texto}</span>
          </div>
          <div className="h-2 rounded-full bg-slate-100">
            <div className="h-full rounded-full" style={{ width: `${(i.valor / max) * 100}%`, background: i.cor }} />
          </div>
        </div>
      ))}
    </div>
  )
}

/** colunas por dia, com dica ao passar o dedo/mouse e alternativa em tabela */
function GraficoDias({ dias }) {
  const [medida, setMedida] = useState('agendamentos')
  const [tabela, setTabela] = useState(false)
  const [foco, setFoco] = useState(null)
  const valores = dias.map((d) => Number(d[medida]))
  const max = Math.max(1, ...valores)
  const fmt = (v) => (medida === 'faturamento' ? reais(v) : v)
  const rotuloDia = (d) => deIso(d.dia).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })
  const passoRotulo = Math.ceil(dias.length / 8)

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm font-semibold text-slate-800">{medida === 'agendamentos' ? 'Agendamentos por dia' : 'Faturamento por dia'}</p>
        <div className="flex items-center gap-2">
          <div className="flex rounded-lg bg-slate-100 p-0.5 text-xs">
            {[['agendamentos', 'Agendamentos'], ['faturamento', 'Faturamento']].map(([k, r]) => (
              <button key={k} onClick={() => setMedida(k)} className={cx('rounded-md px-2.5 py-1 font-medium', medida === k ? 'bg-white text-marca-700 shadow-sm' : 'text-slate-500')}>{r}</button>
            ))}
          </div>
          <button onClick={() => setTabela((t) => !t)} className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-100" aria-label={tabela ? 'Ver gráfico' : 'Ver tabela'}>
            {tabela ? <BarChart3 className="size-4" /> : <Table2 className="size-4" />}
          </button>
        </div>
      </div>

      {tabela ? (
        <div className="max-h-64 overflow-y-auto text-sm">
          <table className="w-full">
            <tbody className="divide-y divide-slate-100">
              {dias.map((d) => (
                <tr key={d.dia}><td className="py-1.5 text-slate-600">{rotuloDia(d)}</td><td className="py-1.5 text-right text-slate-500">{d.agendamentos} agend.</td><td className="py-1.5 text-right font-medium text-slate-800">{reais(d.faturamento)}</td></tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="relative">
          <div className="pointer-events-none absolute inset-x-0 top-0 border-t border-dashed border-slate-200" />
          <span className="absolute -top-4 right-0 text-[11px] text-slate-400">{fmt(max)}</span>
          <div className="flex h-48 items-end gap-[2px]" onMouseLeave={() => setFoco(null)}>
            {dias.map((d, i) => (
              <div key={d.dia} className="relative flex h-full flex-1 items-end" onMouseEnter={() => setFoco(i)} onClick={() => setFoco(i)}>
                <div className={cx('w-full rounded-t-[4px] transition-colors', foco === i ? 'bg-marca-700' : 'bg-marca-500')}
                  style={{ height: `${(valores[i] / max) * 100}%`, minHeight: valores[i] ? 2 : 0 }} />
                {foco === i && (
                  <div className={cx('pointer-events-none absolute bottom-full z-10 mb-2 whitespace-nowrap rounded-lg bg-slate-900 px-2.5 py-1.5 text-xs text-white shadow-lg',
                    i > dias.length / 2 ? 'right-0' : 'left-0')}>
                    <p className="font-semibold">{rotuloDia(d)}</p>
                    <p>{d.agendamentos} agendamentos · {reais(d.faturamento)}</p>
                  </div>
                )}
              </div>
            ))}
          </div>
          <div className="mt-1 flex gap-[2px] border-t border-slate-200 pt-1">
            {dias.map((d, i) => (
              <span key={d.dia} className="flex-1 whitespace-nowrap text-center text-[10px] text-slate-400">{i % passoRotulo === 0 ? rotuloDia(d) : ''}</span>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

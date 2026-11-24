import { useMemo, useState } from 'react'
import { ChevronLeft, ChevronRight, Plus, Wallet, Download, Trash2, Clock3, UserRound } from 'lucide-react'
import { Alerta, Botao, Campo, Cartao, Carregando, Entrada, Painel, Selecao, cx, useAviso } from '../components/ui.jsx'
import { BuscaPaciente, FormRecebimento, profissionaisDaUnidade, useCadastros, useOpera } from '../components/Atendimento.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'
import { ok, useDados } from '../lib/useDados.js'
import { reais } from '../lib/formato.js'
import { FORMAS_PAGAMENTO, dataHora, deIso, fimMes, inicioMes, isoDia, nomeMes, numeroBR } from '../lib/agenda.js'

const ABAS = [['recebidos', 'Recebimentos'], ['receber', 'A receber'], ['profissionais', 'Por profissional']]

export default function Financeiro() {
  const s = useSessao()
  const opera = useOpera()
  const avisar = useAviso()
  const empresaId = s.empresa.id
  const [mes, setMes] = useState(() => inicioMes(new Date()))
  const [unidadeId, setUnidadeId] = useState('')
  const [aba, setAba] = useState('recebidos')
  const [avulso, setAvulso] = useState(null)
  const [recebendo, setRecebendo] = useState(null)
  const { dados: cad } = useCadastros(empresaId)

  const { dados, carregando, recarregar } = useDados(async () => {
    const ini = mes.toISOString()
    const fim = fimMes(mes).toISOString()
    let qp = supabase.from('pagamentos').select('id, valor, forma, recebido_em, descricao, unidade_id, profissional_id, agendamento_id, cliente:clientes(id, nome)')
      .eq('empresa_id', empresaId).gte('recebido_em', ini).lt('recebido_em', fim).order('recebido_em', { ascending: false })
    let qa = supabase.from('agendamentos').select('id, inicio, valor, unidade_id, profissional_id, cliente_id, cliente:clientes(id, nome), servico:servicos(nome), pagamentos(valor)')
      .eq('empresa_id', empresaId).eq('status', 'atendido').gte('inicio', ini).lt('inicio', fim).order('inicio')
    if (unidadeId) { qp = qp.eq('unidade_id', unidadeId); qa = qa.eq('unidade_id', unidadeId) }
    const [pg, ag, rel] = await Promise.all([
      qp, qa,
      supabase.rpc('relatorio_periodo', { p_empresa: empresaId, p_inicio: ini, p_fim: fim, p_unidade: unidadeId || null }),
    ])
    const aReceber = ok(ag).map((a) => ({ ...a, saldo: Number(a.valor || 0) - a.pagamentos.reduce((t, p) => t + Number(p.valor), 0) }))
      .filter((a) => a.saldo > 0)
    return { pagamentos: ok(pg), aReceber, rel: ok(rel) }
  }, [empresaId, mes, unidadeId])

  const profs = useMemo(() => Object.fromEntries((cad?.profissionais ?? []).map((p) => [p.id, p])), [cad])

  async function remover(p) {
    if (!window.confirm(`Apagar o recebimento de ${reais(p.valor)}?`)) return
    const { error } = await supabase.from('pagamentos').delete().eq('id', p.id)
    if (error) return avisar(mensagemErro(error), 'erro')
    avisar('Recebimento apagado')
    recarregar()
  }

  function exportar() {
    const linhas = [['Data', 'Paciente', 'Profissional', 'Forma', 'Valor', 'Descrição']]
    for (const p of dados.pagamentos) {
      linhas.push([
        new Date(p.recebido_em).toLocaleString('pt-BR'), p.cliente?.nome ?? '', profs[p.profissional_id]?.nome ?? '',
        FORMAS_PAGAMENTO[p.forma], String(p.valor).replace('.', ','), p.descricao ?? '',
      ])
    }
    const csv = '﻿' + linhas.map((l) => l.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(';')).join('\n')
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }))
    const a = document.createElement('a')
    a.href = url
    a.download = `recebimentos-${isoDia(mes).slice(0, 7)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  const rel = dados?.rel
  const totalReceber = (dados?.aReceber ?? []).reduce((t, a) => t + a.saldo, 0)

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold text-slate-900 md:text-2xl">Financeiro</h1>
          <p className="text-sm text-slate-500">Recebimentos dos atendimentos</p>
        </div>
        {opera && <Botao onClick={() => setAvulso({})}><Plus className="size-4" /> <span className="hidden sm:inline">Lançar recebimento</span></Botao>}
      </div>

      <div className="mb-4 flex flex-wrap items-center gap-2">
        <div className="flex items-center rounded-xl border border-slate-200 bg-white">
          <button onClick={() => setMes((m) => new Date(m.getFullYear(), m.getMonth() - 1, 1))} className="p-2.5 text-slate-600 hover:bg-slate-50" aria-label="Mês anterior"><ChevronLeft className="size-5" /></button>
          <span className="min-w-36 border-x border-slate-200 px-3 py-2 text-center text-sm font-medium text-slate-700">{nomeMes(mes)}</span>
          <button onClick={() => setMes((m) => new Date(m.getFullYear(), m.getMonth() + 1, 1))} className="p-2.5 text-slate-600 hover:bg-slate-50" aria-label="Próximo mês"><ChevronRight className="size-5" /></button>
        </div>
        {cad?.unidades.length > 1 && (
          <Selecao className="h-11 w-auto!" value={unidadeId} onChange={(e) => setUnidadeId(e.target.value)} aria-label="Unidade">
            <option value="">Todas as unidades</option>
            {cad.unidades.map((u) => <option key={u.id} value={u.id}>{u.nome}</option>)}
          </Selecao>
        )}
      </div>

      {carregando && !dados ? <Carregando /> : !dados ? null : (
        <div className="space-y-5">
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Indicador rotulo="Recebido" valor={reais(rel.faturamento)} destaque />
            <Indicador rotulo="A receber" valor={reais(totalReceber)} detalhe={`${dados.aReceber.length} atendimentos`} />
            <Indicador rotulo="Ticket médio" valor={reais(rel.ticket_medio)} />
            <Indicador rotulo="Atendidos" valor={rel.por_status?.atendido ?? 0} detalhe={`${rel.taxa_faltas}% de faltas`} />
          </div>

          {Object.keys(rel.por_forma).length > 0 && (
            <Cartao className="p-4">
              <p className="mb-3 text-sm font-semibold text-slate-800">Por forma de pagamento</p>
              <div className="space-y-2">
                {Object.entries(rel.por_forma).sort((a, b) => b[1] - a[1]).map(([k, v]) => (
                  <div key={k} className="flex items-center gap-3 text-sm">
                    <span className="w-32 shrink-0 text-slate-600">{FORMAS_PAGAMENTO[k]}</span>
                    <div className="h-2 flex-1 overflow-hidden rounded-full bg-slate-100">
                      <div className="h-full rounded-full bg-agua-500" style={{ width: `${(v / rel.faturamento) * 100}%` }} />
                    </div>
                    <span className="w-24 text-right font-medium text-slate-800">{reais(v)}</span>
                  </div>
                ))}
              </div>
            </Cartao>
          )}

          <div className="flex gap-1 rounded-xl bg-slate-100 p-1">
            {ABAS.map(([k, r]) => (
              <button key={k} onClick={() => setAba(k)}
                className={cx('flex-1 rounded-lg py-2 text-sm font-medium', aba === k ? 'bg-white text-marca-700 shadow-sm' : 'text-slate-500')}>{r}</button>
            ))}
          </div>

          {aba === 'recebidos' && (
            !dados.pagamentos.length ? <Nada texto="Nenhum recebimento neste mês." /> : (
              <>
                <div className="flex justify-end">
                  <button onClick={exportar} className="inline-flex items-center gap-1.5 text-sm font-medium text-marca-700 hover:underline"><Download className="size-4" /> Baixar planilha (CSV)</button>
                </div>
                <Cartao className="divide-y divide-slate-100">
                  {dados.pagamentos.map((p) => (
                    <div key={p.id} className="flex items-center gap-3 px-4 py-3">
                      <span className="grid size-9 shrink-0 place-items-center rounded-xl bg-emerald-50 text-emerald-600"><Wallet className="size-4" /></span>
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium text-slate-800">{p.cliente?.nome ?? p.descricao ?? 'Recebimento avulso'}</p>
                        <p className="truncate text-xs text-slate-500">
                          {[dataHora(p.recebido_em), FORMAS_PAGAMENTO[p.forma], profs[p.profissional_id]?.nome].filter(Boolean).join(' · ')}
                        </p>
                      </div>
                      <p className="font-semibold text-slate-900">{reais(p.valor)}</p>
                      {opera && <button onClick={() => remover(p)} className="rounded-full p-1.5 text-slate-300 hover:bg-red-50 hover:text-red-500" aria-label="Apagar"><Trash2 className="size-4" /></button>}
                    </div>
                  ))}
                </Cartao>
              </>
            )
          )}

          {aba === 'receber' && (
            !dados.aReceber.length ? <Nada texto="Tudo recebido. Nenhum atendimento em aberto neste mês." /> : (
              <Cartao className="divide-y divide-slate-100">
                {dados.aReceber.map((a) => (
                  <div key={a.id} className="px-4 py-3">
                    <div className="flex items-center gap-3">
                      <span className="grid size-9 shrink-0 place-items-center rounded-xl bg-amber-50 text-amber-600"><Clock3 className="size-4" /></span>
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium text-slate-800">{a.cliente?.nome}</p>
                        <p className="truncate text-xs text-slate-500">{[dataHora(a.inicio), a.servico?.nome, profs[a.profissional_id]?.nome].filter(Boolean).join(' · ')}</p>
                      </div>
                      <p className="font-semibold text-slate-900">{reais(a.saldo)}</p>
                      {opera && recebendo !== a.id && <Botao variante="agua" className="h-9 px-3" onClick={() => setRecebendo(a.id)}>Receber</Botao>}
                    </div>
                    {recebendo === a.id && (
                      <div className="mt-3">
                        <FormRecebimento agendamento={a} sugerido={a.saldo} aoCancelar={() => setRecebendo(null)} aoSalvar={() => { setRecebendo(null); recarregar() }} />
                      </div>
                    )}
                  </div>
                ))}
              </Cartao>
            )
          )}

          {aba === 'profissionais' && (
            !rel.por_profissional.length ? <Nada texto="Nenhum profissional cadastrado." /> : (
              <Cartao className="overflow-x-auto">
                <table className="w-full min-w-[480px] text-sm">
                  <thead>
                    <tr className="border-b border-slate-100 text-left text-xs uppercase tracking-wide text-slate-400">
                      <th className="px-4 py-3 font-semibold">Profissional</th>
                      <th className="px-3 py-3 text-right font-semibold">Atendidos</th>
                      <th className="px-3 py-3 text-right font-semibold">Faltas</th>
                      <th className="px-4 py-3 text-right font-semibold">Recebido</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {rel.por_profissional.map((p) => (
                      <tr key={p.id}>
                        <td className="px-4 py-3"><span className="flex items-center gap-2 font-medium text-slate-800"><span className="size-2.5 rounded-full" style={{ background: p.cor }} />{p.nome}</span></td>
                        <td className="px-3 py-3 text-right text-slate-700">{p.atendidos}</td>
                        <td className="px-3 py-3 text-right text-slate-700">{p.faltas}</td>
                        <td className="px-4 py-3 text-right font-semibold text-slate-900">{reais(p.faturamento)}</td>
                      </tr>
                    ))}
                  </tbody>
                  <tfoot>
                    <tr className="border-t border-slate-200 font-semibold">
                      <td className="px-4 py-3 text-slate-800">Total</td>
                      <td className="px-3 py-3 text-right">{rel.por_profissional.reduce((t, p) => t + p.atendidos, 0)}</td>
                      <td className="px-3 py-3 text-right">{rel.por_profissional.reduce((t, p) => t + p.faltas, 0)}</td>
                      <td className="px-4 py-3 text-right">{reais(rel.por_profissional.reduce((t, p) => t + Number(p.faturamento), 0))}</td>
                    </tr>
                  </tfoot>
                </table>
                <p className="flex items-center gap-1.5 border-t border-slate-100 px-4 py-2 text-xs text-slate-400"><UserRound className="size-3.5" /> Recebimentos avulsos sem profissional entram só no total do mês.</p>
              </Cartao>
            )
          )}
        </div>
      )}

      {cad && <PainelAvulso aberto={!!avulso} cad={cad} aoFechar={() => setAvulso(null)} aoSalvar={recarregar} />}
    </div>
  )
}

function Indicador({ rotulo, valor, detalhe, destaque }) {
  return (
    <Cartao className={cx('p-4', destaque && 'border-transparent bg-gradient-to-br from-marca-700 to-agua-600 text-white')}>
      <p className={cx('text-xs', destaque ? 'text-marca-50' : 'text-slate-500')}>{rotulo}</p>
      <p className={cx('mt-1 text-xl font-bold', !destaque && 'text-slate-900')}>{valor}</p>
      {detalhe && <p className={cx('text-xs', destaque ? 'text-marca-50' : 'text-slate-400')}>{detalhe}</p>}
    </Cartao>
  )
}

function Nada({ texto }) {
  return <p className="rounded-2xl border border-dashed border-slate-300 p-6 text-center text-sm text-slate-500">{texto}</p>
}

function PainelAvulso({ aberto, cad, aoFechar, aoSalvar }) {
  const s = useSessao()
  const avisar = useAviso()
  const [f, setF] = useState(null)
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)

  if (aberto && !f) {
    setF({ unidade_id: cad.unidades[0]?.id ?? '', profissional_id: '', cliente: null, valor: '', forma: 'pix', dia: isoDia(new Date()), descricao: '' })
  }
  if (!aberto && f) setF(null)
  if (!aberto || !f) return null

  async function salvar(e) {
    e.preventDefault()
    setErro('')
    const valor = numeroBR(f.valor)
    if (!valor || Number.isNaN(valor) || valor <= 0) return setErro('Informe um valor maior que zero.')
    const agora = new Date()
    const quando = deIso(f.dia, `${agora.getHours()}:${agora.getMinutes()}`)
    setSalvando(true)
    try {
      ok(await supabase.from('pagamentos').insert({
        empresa_id: s.empresa.id, unidade_id: f.unidade_id, profissional_id: f.profissional_id || null, cliente_id: f.cliente?.id ?? null,
        valor, forma: f.forma, recebido_em: quando.toISOString(), descricao: f.descricao || null, registrado_por: s.usuario.id,
      }))
      avisar('Recebimento lançado')
      aoSalvar()
      aoFechar()
    } catch (err) {
      setErro(mensagemErro(err))
    } finally {
      setSalvando(false)
    }
  }

  return (
    <Painel aberto={aberto} aoFechar={aoFechar} titulo="Lançar recebimento"
      rodape={
        <div className="flex gap-2">
          <Botao variante="secundario" className="flex-1" onClick={aoFechar}>Cancelar</Botao>
          <Botao className="flex-1" type="submit" form="form-avulso" carregando={salvando}>Salvar</Botao>
        </div>
      }>
      <form id="form-avulso" onSubmit={salvar} className="space-y-4">
        <p className="text-sm text-slate-500">Para venda de produto, pacote ou pagamento que não está ligado a um horário da agenda. Para receber um atendimento, abra-o na agenda ou na aba “A receber”.</p>
        {cad.unidades.length > 1 && (
          <Campo rotulo="Unidade">
            <Selecao value={f.unidade_id} onChange={(e) => setF({ ...f, unidade_id: e.target.value, profissional_id: '' })}>
              {cad.unidades.map((u) => <option key={u.id} value={u.id}>{u.nome}</option>)}
            </Selecao>
          </Campo>
        )}
        <div className="grid grid-cols-2 gap-3">
          <Campo rotulo="Valor (R$)"><Entrada inputMode="decimal" required placeholder="0,00" value={f.valor} onChange={(e) => setF({ ...f, valor: e.target.value })} /></Campo>
          <Campo rotulo="Forma">
            <Selecao value={f.forma} onChange={(e) => setF({ ...f, forma: e.target.value })}>
              {Object.entries(FORMAS_PAGAMENTO).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </Selecao>
          </Campo>
        </div>
        <Campo rotulo="Data"><Entrada type="date" required value={f.dia} onChange={(e) => setF({ ...f, dia: e.target.value })} /></Campo>
        <Campo rotulo="Descrição"><Entrada placeholder="Ex.: Kit clareamento, pacote 5 sessões" value={f.descricao} onChange={(e) => setF({ ...f, descricao: e.target.value })} /></Campo>
        <Campo rotulo="Profissional (opcional)">
          <Selecao value={f.profissional_id} onChange={(e) => setF({ ...f, profissional_id: e.target.value })}>
            <option value="">Nenhum</option>
            {profissionaisDaUnidade(cad, f.unidade_id).map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
          </Selecao>
        </Campo>
        <Campo rotulo="Paciente (opcional)">
          <BuscaPaciente empresaId={s.empresa.id} valor={f.cliente} aoEscolher={(c) => setF({ ...f, cliente: c })} />
        </Campo>
        <Alerta>{erro}</Alerta>
      </form>
    </Painel>
  )
}

import { Link } from 'react-router-dom'
import { Building2, TrendingUp, Clock, AlertTriangle, Lock, Plus, ChevronRight, Sparkles } from 'lucide-react'
import { Botao, Cabecalho, Cartao, Carregando, Etiqueta } from '../../components/ui.jsx'
import { supabase } from '../../lib/supabase.js'
import { ok, useDados } from '../../lib/useDados.js'
import { STATUS_ASSINATURA, diasRestantes, reais } from '../../lib/formato.js'

export default function AdminVisaoGeral() {
  const { dados, carregando } = useDados(async () => {
    const [empresas, planos] = await Promise.all([
      supabase.rpc('admin_listar_empresas'),
      supabase.from('planos').select('*').order('ordem'),
    ])
    return { empresas: ok(empresas), planos: ok(planos) }
  }, [])

  if (carregando || !dados) return <Carregando />
  const { empresas, planos } = dados
  const por = (st) => empresas.filter((e) => e.status_assinatura === st)
  const ativas = por('ativa')
  const mrr = ativas.reduce((t, e) => t + Number(e.preco_mensal), 0)
  const potencial = por('teste').reduce((t, e) => t + Number(e.preco_mensal), 0)
  const trintaDias = Date.now() - 30 * 864e5
  const novas = empresas.filter((e) => new Date(e.criado_em).getTime() >= trintaDias).length
  const testesAcabando = por('teste')
    .map((e) => ({ ...e, dias: diasRestantes(e.teste_ate) }))
    .filter((e) => e.dias != null && e.dias <= 3)
    .sort((a, b) => a.dias - b.dias)
  const porPlano = planos.map((p) => ({ ...p, total: empresas.filter((e) => e.plano_codigo === p.codigo && !['cancelada'].includes(e.status_assinatura)).length }))
  const maxPlano = Math.max(1, ...porPlano.map((p) => p.total))

  const kpis = [
    { rotulo: 'Receita mensal (ativas)', valor: reais(mrr), icone: TrendingUp, cor: 'text-agua-600 bg-agua-50' },
    { rotulo: 'Empresas ativas', valor: ativas.length, icone: Building2, cor: 'text-marca-700 bg-marca-50' },
    { rotulo: 'Em teste', valor: por('teste').length, extra: potencial ? `${reais(potencial)} em potencial` : null, icone: Clock, cor: 'text-sky-600 bg-sky-50' },
    { rotulo: 'Inadimplentes', valor: por('inadimplente').length, icone: AlertTriangle, cor: 'text-amber-600 bg-amber-50' },
    { rotulo: 'Bloqueadas', valor: por('bloqueada').length, icone: Lock, cor: 'text-red-600 bg-red-50' },
    { rotulo: 'Novas em 30 dias', valor: novas, icone: Sparkles, cor: 'text-violet-600 bg-violet-50' },
  ]

  return (
    <div className="space-y-6">
      <Cabecalho titulo="Visão geral" subtitulo={`${empresas.length} empresas na plataforma`}
        acao={<Link to="/admin/empresas?nova=1"><Botao><Plus className="size-4" /> <span className="hidden sm:inline">Nova empresa</span></Botao></Link>} />

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-3">
        {kpis.map((k) => (
          <Cartao key={k.rotulo} className="p-4">
            <span className={`grid size-9 place-items-center rounded-xl ${k.cor}`}><k.icone className="size-5" /></span>
            <p className="mt-3 text-2xl font-bold text-slate-900">{k.valor}</p>
            <p className="text-xs text-slate-500">{k.rotulo}</p>
            {k.extra && <p className="mt-0.5 text-[11px] text-slate-400">{k.extra}</p>}
          </Cartao>
        ))}
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Cartao className="p-5">
          <h2 className="font-semibold text-slate-900">Empresas por plano</h2>
          <div className="mt-4 space-y-3">
            {porPlano.map((p) => (
              <div key={p.codigo}>
                <div className="mb-1 flex justify-between text-sm">
                  <span className="text-slate-700">{p.nome} <span className="text-slate-400">· {reais(p.preco_mensal)}</span></span>
                  <span className="font-semibold text-slate-900">{p.total}</span>
                </div>
                <div className="h-2.5 rounded-full bg-slate-100">
                  <div className="h-full rounded-full bg-gradient-to-r from-marca-600 to-agua-500" style={{ width: `${(p.total / maxPlano) * 100}%` }} />
                </div>
              </div>
            ))}
          </div>
        </Cartao>

        <Cartao className="p-5">
          <div className="flex items-center justify-between">
            <h2 className="font-semibold text-slate-900">Testes terminando</h2>
            <Link to="/admin/assinaturas" className="text-sm font-medium text-marca-700">Ver assinaturas</Link>
          </div>
          {!testesAcabando.length ? (
            <p className="mt-4 text-sm text-slate-500">Nenhum teste vence nos próximos 3 dias.</p>
          ) : (
            <ul className="mt-3 divide-y divide-slate-100">
              {testesAcabando.slice(0, 6).map((e) => (
                <li key={e.id} className="flex items-center gap-3 py-2.5">
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-medium text-slate-800">{e.nome}</span>
                    <span className="block truncate text-xs text-slate-500">{e.dono_email || e.convite_pendente}</span>
                  </span>
                  <Etiqueta className={e.dias <= 0 ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-800'}>
                    {e.dias <= 0 ? 'vencido' : `${e.dias} ${e.dias === 1 ? 'dia' : 'dias'}`}
                  </Etiqueta>
                </li>
              ))}
            </ul>
          )}
        </Cartao>
      </div>

      <Cartao className="p-5">
        <div className="flex items-center justify-between">
          <h2 className="font-semibold text-slate-900">Últimas empresas</h2>
          <Link to="/admin/empresas" className="text-sm font-medium text-marca-700">Ver todas</Link>
        </div>
        {!empresas.length ? (
          <p className="mt-4 text-sm text-slate-500">Nenhuma empresa ainda. Cadastre a primeira ou divulgue o link de teste grátis: <strong>/criar-conta</strong>.</p>
        ) : (
          <ul className="mt-3 divide-y divide-slate-100">
            {empresas.slice(0, 5).map((e) => {
              const st = STATUS_ASSINATURA[e.status_assinatura]
              return (
                <li key={e.id}>
                  <Link to={`/admin/empresas?id=${e.id}`} className="flex items-center gap-3 py-2.5">
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-sm font-medium text-slate-800">{e.nome}</span>
                      <span className="block text-xs text-slate-500">{e.plano_nome}</span>
                    </span>
                    <Etiqueta className={st.cor}>{st.rotulo}</Etiqueta>
                    <ChevronRight className="size-4 text-slate-300" />
                  </Link>
                </li>
              )
            })}
          </ul>
        )}
      </Cartao>
    </div>
  )
}

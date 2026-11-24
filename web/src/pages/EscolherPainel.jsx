import { useMemo, useState } from 'react'
import { Navigate, useNavigate } from 'react-router-dom'
import { Shield, Building2, ChevronRight, Search, ArrowLeft } from 'lucide-react'
import { Carregando, Entrada, Etiqueta, Logo, cx } from '../components/ui.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { supabase } from '../lib/supabase.js'
import { useDados } from '../lib/useDados.js'
import { STATUS_ASSINATURA } from '../lib/formato.js'

/** Tela do super-admin depois do login: abrir o painel da plataforma ou ver o sistema como um cliente. */
export default function EscolherPainel() {
  const s = useSessao()
  const navegar = useNavigate()
  const [etapa, setEtapa] = useState('modo')
  const [busca, setBusca] = useState('')

  const { dados: empresas, carregando } = useDados(async () => {
    if (!s.superAdmin) return []
    const { data } = await supabase.rpc('admin_listar_empresas')
    return data ?? []
  }, [s.superAdmin])

  const lista = useMemo(() => {
    const t = busca.toLowerCase()
    return (empresas ?? []).filter((e) => !t || e.nome.toLowerCase().includes(t) || (e.dono_email ?? '').includes(t))
  }, [empresas, busca])

  if (s.carregando) return <Carregando />
  if (!s.usuario) return <Navigate to="/entrar" replace />
  if (!s.superAdmin) return <Navigate to="/" replace />

  const abrirAdmin = () => {
    s.setModo('admin')
    navegar('/admin', { replace: true })
  }
  const abrirCliente = (id) => {
    s.setEmpresaId(id)
    s.setModo('cliente')
    navegar('/', { replace: true })
  }
  const minhas = new Set(s.vinculos.map((v) => v.empresa.id))
  const primeiroNome = (s.perfil?.nome || '').split(' ')[0]

  return (
    <div className="min-h-full bg-gradient-to-b from-marca-50 to-white px-5 py-8">
      <div className="mx-auto max-w-3xl">
        <Logo />
        {etapa === 'modo' ? (
          <>
            <h1 className="mt-10 text-2xl font-bold text-slate-900 md:text-3xl">Olá{primeiroNome ? `, ${primeiroNome}` : ''}! Qual painel você quer abrir?</h1>
            <p className="mt-1 text-slate-500">Você pode trocar a qualquer momento pelo menu.</p>
            <div className="mt-8 grid gap-4 md:grid-cols-2">
              <button onClick={abrirAdmin}
                className="group rounded-3xl border border-slate-200 bg-white p-6 text-left shadow-sm transition hover:border-marca-500 hover:shadow-md">
                <span className="grid size-12 place-items-center rounded-2xl bg-marca-700 text-white"><Shield className="size-6" /></span>
                <p className="mt-4 text-lg font-semibold text-slate-900">Painel da plataforma</p>
                <p className="mt-1 text-sm text-slate-500">Empresas, planos, assinaturas, bloqueios e histórico do Sistem Clinic.</p>
                <span className="mt-4 inline-flex items-center gap-1 text-sm font-semibold text-marca-700">Abrir <ChevronRight className="size-4 transition group-hover:translate-x-0.5" /></span>
              </button>
              <button onClick={() => setEtapa('empresa')}
                className="group rounded-3xl border border-slate-200 bg-white p-6 text-left shadow-sm transition hover:border-agua-500 hover:shadow-md">
                <span className="grid size-12 place-items-center rounded-2xl bg-agua-500 text-white"><Building2 className="size-6" /></span>
                <p className="mt-4 text-lg font-semibold text-slate-900">Painel do cliente</p>
                <p className="mt-1 text-sm text-slate-500">Veja e use o sistema exatamente como uma clínica vê, escolhendo a empresa.</p>
                <span className="mt-4 inline-flex items-center gap-1 text-sm font-semibold text-agua-600">Escolher empresa <ChevronRight className="size-4 transition group-hover:translate-x-0.5" /></span>
              </button>
            </div>
          </>
        ) : (
          <>
            <button onClick={() => setEtapa('modo')} className="mt-8 inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800">
              <ArrowLeft className="size-4" /> Voltar
            </button>
            <h1 className="mt-3 text-2xl font-bold text-slate-900">Ver o sistema como qual empresa?</h1>
            <div className="relative mt-5">
              <Search className="pointer-events-none absolute left-3.5 top-3.5 size-4 text-slate-400" />
              <Entrada className="pl-10" placeholder="Buscar empresa" value={busca} onChange={(e) => setBusca(e.target.value)} autoFocus />
            </div>
            <div className="mt-4 space-y-2">
              {carregando ? <Carregando /> : !lista.length ? (
                <div className="rounded-2xl border border-dashed border-slate-300 p-6 text-center text-sm text-slate-500">
                  Nenhuma empresa cadastrada ainda. Crie uma no{' '}
                  <button onClick={() => { s.setModo('admin'); navegar('/admin/empresas?nova=1') }} className="font-semibold text-marca-700 underline">painel da plataforma</button>
                  {' '}(por exemplo, uma empresa de demonstração).
                </div>
              ) : lista.map((e) => {
                const st = STATUS_ASSINATURA[e.status_assinatura]
                return (
                  <button key={e.id} onClick={() => abrirCliente(e.id)}
                    className="flex w-full items-center gap-3 rounded-2xl border border-slate-200 bg-white p-4 text-left hover:border-agua-500 hover:bg-agua-50/40">
                    <span className="grid size-10 place-items-center rounded-xl bg-agua-50 text-agua-600"><Building2 className="size-5" /></span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate font-medium text-slate-900">{e.nome}</span>
                      <span className="block truncate text-xs text-slate-500">{e.plano_nome} · {e.dono_email || e.convite_pendente || 'sem dono ainda'}</span>
                    </span>
                    {minhas.has(e.id) && <Etiqueta className="bg-marca-100 text-marca-700">sua</Etiqueta>}
                    <Etiqueta className={cx(st.cor)}>{st.rotulo}</Etiqueta>
                    <ChevronRight className="size-4 text-slate-400" />
                  </button>
                )
              })}
            </div>
          </>
        )}
      </div>
    </div>
  )
}

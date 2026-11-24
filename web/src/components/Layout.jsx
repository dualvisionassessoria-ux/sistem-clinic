import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import {
  Home, MapPin, UserRound, Scissors, Users, Building2, LogOut, Shield, ArrowLeftRight, CalendarDays,
  ContactRound, MessageCircle, Wallet, BarChart3, LayoutDashboard, Layers, CreditCard, History, Menu as IconeMenu, Eye,
} from 'lucide-react'
import { useSessao } from '../lib/sessao.jsx'
import { diasRestantes } from '../lib/formato.js'
import { Logo, cx } from './ui.jsx'

/** Menu do cliente, agrupado por frente de trabalho. `breve` = módulo das próximas etapas. */
export function gruposCliente(eDono) {
  return [
    {
      titulo: 'Atendimento',
      itens: [
        { para: '/', rotulo: 'Início', icone: Home, fim: true },
        { para: '/agenda', rotulo: 'Agenda', icone: CalendarDays },
        { para: '/pacientes', rotulo: 'Pacientes', icone: ContactRound },
      ],
    },
    {
      titulo: 'Rotina',
      itens: [{ rotulo: 'WhatsApp', icone: MessageCircle, breve: true }],
    },
    {
      titulo: 'Gestão',
      itens: [
        { para: '/financeiro', rotulo: 'Financeiro', icone: Wallet },
        { para: '/relatorios', rotulo: 'Relatórios', icone: BarChart3 },
      ],
    },
    {
      titulo: 'Cadastros',
      itens: [
        { para: '/unidades', rotulo: 'Unidades', icone: MapPin },
        { para: '/profissionais', rotulo: 'Profissionais', icone: UserRound },
        { para: '/servicos', rotulo: 'Serviços', icone: Scissors },
        ...(eDono ? [
          { para: '/equipe', rotulo: 'Equipe', icone: Users },
          { para: '/empresa', rotulo: 'Minha empresa', icone: Building2 },
        ] : []),
      ],
    },
  ]
}

const GRUPOS_ADMIN = [
  {
    titulo: 'Plataforma',
    itens: [
      { para: '/admin', rotulo: 'Visão geral', curto: 'Geral', icone: LayoutDashboard, fim: true },
      { para: '/admin/empresas', rotulo: 'Empresas', icone: Building2 },
      { para: '/admin/assinaturas', rotulo: 'Assinaturas', icone: CreditCard },
      { para: '/admin/planos', rotulo: 'Planos', icone: Layers },
      { para: '/admin/historico', rotulo: 'Histórico', icone: History },
    ],
  },
]

function AvisoAssinatura({ empresa }) {
  if (!empresa) return null
  const dias = diasRestantes(empresa.teste_ate)
  if (empresa.status_assinatura === 'teste' && dias != null) {
    return (
      <div className={cx('px-4 py-2 text-center text-sm', dias > 0 ? 'bg-agua-50 text-agua-700' : 'bg-amber-50 text-amber-800')}>
        {dias > 0
          ? `Período de teste: ${dias} ${dias === 1 ? 'dia restante' : 'dias restantes'}.`
          : 'Seu período de teste terminou. Fale conosco para ativar sua assinatura.'}
      </div>
    )
  }
  if (empresa.status_assinatura === 'inadimplente') {
    return (
      <div className="bg-amber-50 px-4 py-2 text-center text-sm text-amber-800">
        Há uma mensalidade em aberto. Regularize para evitar o bloqueio do sistema.
      </div>
    )
  }
  return null
}

function ItemLateral({ item }) {
  if (item.breve) {
    return (
      <div className="flex items-center gap-3 rounded-xl px-3 py-1.5 text-sm text-slate-400">
        <item.icone className="size-[18px]" /> {item.rotulo}
        <span className="ml-auto rounded-full bg-slate-100 px-2 text-[10px] font-medium">em breve</span>
      </div>
    )
  }
  return (
    <NavLink
      to={item.para}
      end={item.fim}
      className={({ isActive }) =>
        cx(
          'flex items-center gap-3 rounded-xl px-3 py-1.5 text-sm font-medium transition',
          isActive ? 'bg-marca-700 text-white shadow-sm' : 'text-slate-600 hover:bg-slate-100',
        )
      }
    >
      <item.icone className="size-[18px]" />
      {item.rotulo}
    </NavLink>
  )
}

export default function Layout({ admin, children }) {
  const s = useSessao()
  const navegar = useNavigate()
  const grupos = admin ? GRUPOS_ADMIN : gruposCliente(s.eDono)

  const itensCelular = admin
    ? GRUPOS_ADMIN[0].itens
    : [
        { para: '/', rotulo: 'Início', icone: Home, fim: true },
        { para: '/agenda', rotulo: 'Agenda', icone: CalendarDays },
        { para: '/pacientes', rotulo: 'Pacientes', icone: ContactRound },
        { para: '/financeiro', rotulo: 'Caixa', icone: Wallet },
        { para: '/menu', rotulo: 'Mais', icone: IconeMenu },
      ]

  const sair = async () => {
    await s.sair()
    navegar('/entrar')
  }
  const irParaAdmin = () => {
    s.setModo('admin')
    navegar('/admin')
  }
  const irParaCliente = () => navegar('/escolher-painel')

  return (
    <div className="min-h-full md:flex">
      {/* ----- menu lateral (computador) */}
      <aside className="hidden md:sticky md:top-0 md:flex md:h-dvh md:w-64 md:shrink-0 md:flex-col md:border-r md:border-slate-200 md:bg-white">
        <div className="px-5 pb-3 pt-4">
          <Logo />
          {admin && <p className="mt-1 text-xs font-medium uppercase tracking-wide text-marca-700">Painel da plataforma</p>}
        </div>
        {!admin && s.empresa && (
          <div className="mx-3 mb-2 rounded-2xl bg-marca-50 px-4 py-3">
            <p className="text-xs text-marca-700">{s.comoAdmin ? 'Vendo como cliente' : 'Empresa'}</p>
            <p className="truncate font-semibold text-slate-900">{s.empresa.nome}</p>
            <p className="text-xs text-slate-500">Plano {s.plano?.nome}</p>
          </div>
        )}
        <nav className="flex-1 space-y-3 overflow-y-auto px-3 pb-3">
          {grupos.map((g) => (
            <div key={g.titulo}>
              <p className="px-3 pb-1 text-[11px] font-semibold uppercase tracking-wider text-slate-400">{g.titulo}</p>
              <div className="space-y-0.5">
                {g.itens.map((i) => <ItemLateral key={i.rotulo} item={i} />)}
              </div>
            </div>
          ))}
        </nav>
        <div className="space-y-0.5 border-t border-slate-100 px-3 py-2">
          {s.superAdmin && !admin && (
            <button onClick={irParaAdmin} className="flex w-full items-center gap-3 rounded-xl px-3 py-2 text-sm text-slate-600 hover:bg-slate-100">
              <Shield className="size-4" /> Painel da plataforma
            </button>
          )}
          {s.superAdmin && admin && (
            <button onClick={irParaCliente} className="flex w-full items-center gap-3 rounded-xl px-3 py-2 text-sm text-slate-600 hover:bg-slate-100">
              <Eye className="size-4" /> Ver como cliente
            </button>
          )}
          {!s.superAdmin && s.vinculos.length > 1 && (
            <NavLink to="/escolher-empresa" className="flex items-center gap-3 rounded-xl px-3 py-2 text-sm text-slate-600 hover:bg-slate-100">
              <ArrowLeftRight className="size-4" /> Trocar empresa
            </NavLink>
          )}
          <button onClick={sair} className="flex w-full items-center gap-3 rounded-xl px-3 py-2 text-sm text-slate-600 hover:bg-slate-100">
            <LogOut className="size-4" /> Sair
          </button>
          <p className="truncate px-3 pt-1 text-xs text-slate-400">{s.usuario?.email}</p>
        </div>
      </aside>

      {/* ----- conteúdo */}
      <div className="flex min-h-full min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-30 flex items-center justify-between border-b border-slate-200 bg-white/90 px-4 py-3 backdrop-blur md:hidden">
          <div className="min-w-0">
            <Logo className="text-base" />
          </div>
          <div className="flex items-center gap-1">
            {s.superAdmin && (
              <button onClick={admin ? irParaCliente : irParaAdmin} className="rounded-full p-2 text-slate-500 hover:bg-slate-100"
                aria-label={admin ? 'Ver como cliente' : 'Painel da plataforma'}>
                {admin ? <Eye className="size-5" /> : <Shield className="size-5" />}
              </button>
            )}
            <button onClick={sair} className="rounded-full p-2 text-slate-500 hover:bg-slate-100" aria-label="Sair">
              <LogOut className="size-5" />
            </button>
          </div>
        </header>

        {s.comoAdmin && !admin && (
          <div className="flex flex-wrap items-center justify-center gap-x-3 gap-y-1 bg-marca-800 px-4 py-2 text-center text-sm text-white">
            <span className="flex items-center gap-1.5"><Eye className="size-4 text-agua-200" /> Você está vendo como cliente: <strong>{s.empresa?.nome}</strong></span>
            <button onClick={irParaCliente} className="rounded-full bg-white/15 px-3 py-0.5 text-xs font-medium hover:bg-white/25">Trocar empresa</button>
            <button onClick={irParaAdmin} className="rounded-full bg-white px-3 py-0.5 text-xs font-semibold text-marca-800 hover:bg-marca-50">Voltar ao painel</button>
          </div>
        )}
        {!admin && <AvisoAssinatura empresa={s.empresa} />}

        <main className="mx-auto w-full max-w-6xl flex-1 px-4 pb-28 pt-5 md:px-8 md:pb-10 md:pt-8">
          {children ?? <Outlet />}
        </main>

        {/* menu inferior (celular) */}
        <nav className="fixed inset-x-0 bottom-0 z-30 border-t border-slate-200 bg-white pb-safe md:hidden">
          <div className="grid" style={{ gridTemplateColumns: `repeat(${itensCelular.length}, minmax(0, 1fr))` }}>
            {itensCelular.map((i) => (
              <NavLink
                key={i.para}
                to={i.para}
                end={i.fim}
                className={({ isActive }) =>
                  cx('flex flex-col items-center gap-0.5 py-2 text-[11px] font-medium', isActive ? 'text-marca-700' : 'text-slate-500')
                }
              >
                {({ isActive }) => (
                  <>
                    <span className={cx('rounded-full px-3 py-1', isActive && 'bg-marca-50')}>
                      <i.icone className="size-5" />
                    </span>
                    {i.curto ?? i.rotulo}
                  </>
                )}
              </NavLink>
            ))}
          </div>
        </nav>
      </div>
    </div>
  )
}

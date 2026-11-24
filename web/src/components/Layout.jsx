import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { Home, MapPin, UserRound, Scissors, Users, Building2, LogOut, Shield, ArrowLeftRight, CalendarDays } from 'lucide-react'
import { useSessao } from '../lib/sessao.jsx'
import { diasRestantes } from '../lib/formato.js'
import { Logo, cx } from './ui.jsx'

function itensMenu(eDono) {
  const itens = [
    { para: '/', rotulo: 'Início', icone: Home, fim: true },
    { para: '/unidades', rotulo: 'Unidades', icone: MapPin },
    { para: '/profissionais', rotulo: 'Profissionais', icone: UserRound },
    { para: '/servicos', rotulo: 'Serviços', icone: Scissors },
  ]
  if (eDono) {
    itens.push({ para: '/equipe', rotulo: 'Equipe', icone: Users })
    itens.push({ para: '/empresa', rotulo: 'Empresa', icone: Building2 })
  }
  return itens
}

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

export default function Layout({ admin, children }) {
  const s = useSessao()
  const navegar = useNavigate()
  const itens = admin ? [{ para: '/admin', rotulo: 'Empresas', icone: Shield, fim: true }] : itensMenu(s.eDono)
  // no celular o menu inferior mostra até 5 itens
  const itensCelular = itens.slice(0, 5)

  const sair = async () => {
    await s.sair()
    navegar('/entrar')
  }

  return (
    <div className="min-h-full md:flex">
      {/* ----- menu lateral (computador) */}
      <aside className="hidden md:flex md:w-64 md:shrink-0 md:flex-col md:border-r md:border-slate-200 md:bg-white">
        <div className="px-5 py-5">
          <Logo />
        </div>
        {!admin && s.empresa && (
          <div className="mx-3 mb-3 rounded-2xl bg-marca-50 px-4 py-3">
            <p className="text-xs text-marca-700">Empresa</p>
            <p className="truncate font-semibold text-slate-900">{s.empresa.nome}</p>
            <p className="text-xs text-slate-500">Plano {s.plano?.nome}</p>
          </div>
        )}
        <nav className="flex-1 space-y-1 px-3">
          {itens.map((i) => (
            <NavLink
              key={i.para}
              to={i.para}
              end={i.fim}
              className={({ isActive }) =>
                cx(
                  'flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition',
                  isActive ? 'bg-marca-700 text-white' : 'text-slate-600 hover:bg-slate-100',
                )
              }
            >
              <i.icone className="size-5" />
              {i.rotulo}
            </NavLink>
          ))}
          {!admin && <div className="flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm text-slate-400">
            <CalendarDays className="size-5" /> Agenda <span className="ml-auto rounded-full bg-slate-100 px-2 text-[10px]">em breve</span>
          </div>}
        </nav>
        <div className="space-y-1 border-t border-slate-100 p-3">
          {s.superAdmin && !admin && (
            <NavLink to="/admin" className="flex items-center gap-3 rounded-xl px-3 py-2 text-sm text-slate-600 hover:bg-slate-100">
              <Shield className="size-4" /> Painel da plataforma
            </NavLink>
          )}
          {admin && s.vinculos.length > 0 && (
            <NavLink to="/" className="flex items-center gap-3 rounded-xl px-3 py-2 text-sm text-slate-600 hover:bg-slate-100">
              <Building2 className="size-4" /> Voltar para a empresa
            </NavLink>
          )}
          {s.vinculos.length > 1 && !admin && (
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
      <div className="flex min-h-full flex-1 flex-col">
        {/* topo (celular) */}
        <header className="sticky top-0 z-30 flex items-center justify-between border-b border-slate-200 bg-white/90 px-4 py-3 backdrop-blur md:hidden">
          <div className="min-w-0">
            <Logo className="text-base" />
          </div>
          <div className="flex items-center gap-1">
            {s.eDono && !admin && (
              <NavLink to="/empresa" className="rounded-full p-2 text-slate-500 hover:bg-slate-100" aria-label="Minha empresa">
                <Building2 className="size-5" />
              </NavLink>
            )}
            {s.superAdmin && !admin && (
              <NavLink to="/admin" className="rounded-full p-2 text-slate-500 hover:bg-slate-100" aria-label="Painel da plataforma">
                <Shield className="size-5" />
              </NavLink>
            )}
            {s.vinculos.length > 1 && !admin && (
              <NavLink to="/escolher-empresa" className="rounded-full p-2 text-slate-500 hover:bg-slate-100" aria-label="Trocar empresa">
                <ArrowLeftRight className="size-5" />
              </NavLink>
            )}
            <button onClick={sair} className="rounded-full p-2 text-slate-500 hover:bg-slate-100" aria-label="Sair">
              <LogOut className="size-5" />
            </button>
          </div>
        </header>

        {!admin && <AvisoAssinatura empresa={s.empresa} />}

        <main className="mx-auto w-full max-w-5xl flex-1 px-4 pb-28 pt-5 md:px-8 md:pb-10 md:pt-8">
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
                    {i.rotulo}
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

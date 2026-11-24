import { useEffect } from 'react'
import { Navigate, Route, Routes, useLocation } from 'react-router-dom'
import { useSessao } from './lib/sessao.jsx'
import { Carregando } from './components/ui.jsx'
import Layout from './components/Layout.jsx'
import Entrar from './pages/Entrar.jsx'
import CriarConta from './pages/CriarConta.jsx'
import EsqueciSenha from './pages/EsqueciSenha.jsx'
import NovaSenha from './pages/NovaSenha.jsx'
import Convite from './pages/Convite.jsx'
import EscolherEmpresa from './pages/EscolherEmpresa.jsx'
import Suspensa from './pages/Suspensa.jsx'
import Inicio from './pages/Inicio.jsx'
import Unidades from './pages/Unidades.jsx'
import Profissionais from './pages/Profissionais.jsx'
import Servicos from './pages/Servicos.jsx'
import Equipe from './pages/Equipe.jsx'
import MinhaEmpresa from './pages/MinhaEmpresa.jsx'
import EscolherPainel from './pages/EscolherPainel.jsx'
import Menu from './pages/Menu.jsx'
import Agenda from './pages/Agenda.jsx'
import Pacientes from './pages/Pacientes.jsx'
import Paciente from './pages/Paciente.jsx'
import Financeiro from './pages/Financeiro.jsx'
import Relatorios from './pages/Relatorios.jsx'
import AdminVisaoGeral from './pages/admin/AdminVisaoGeral.jsx'
import AdminEmpresas from './pages/admin/AdminEmpresas.jsx'
import AdminPlanos from './pages/admin/AdminPlanos.jsx'
import AdminAssinaturas from './pages/admin/AdminAssinaturas.jsx'
import AdminHistorico from './pages/admin/AdminHistorico.jsx'

/** Só deixa passar quem está logado e com uma empresa liberada aberta. */
function AreaEmpresa({ children }) {
  const s = useSessao()
  const local = useLocation()
  if (s.carregando) return <Carregando />
  if (!s.usuario) return <Navigate to="/entrar" state={{ de: local.pathname }} replace />
  if (s.recuperandoSenha) return <Navigate to="/nova-senha" replace />
  if (s.superAdmin) {
    // você escolhe a cada login qual painel abrir
    if (s.modo !== 'cliente') return <Navigate to={s.modo === 'admin' ? '/admin' : '/escolher-painel'} replace />
    if (!s.vinculo) return <Navigate to="/escolher-painel" replace />
  } else {
    if (!s.vinculos.length) return <Navigate to="/criar-conta" replace />
    if (!s.vinculo) return <Navigate to="/escolher-empresa" replace />
  }
  if (!s.comoAdmin && ['bloqueada', 'cancelada'].includes(s.empresa.status_assinatura)) return <Suspensa />
  return children
}

function AreaAdmin({ children }) {
  const s = useSessao()
  const { superAdmin, modo, setModo } = s
  useEffect(() => {
    if (superAdmin && modo !== 'admin') setModo('admin')
  }, [superAdmin, modo, setModo])
  if (s.carregando) return <Carregando />
  if (!s.usuario) return <Navigate to="/entrar" replace />
  if (!s.superAdmin) return <Navigate to="/" replace />
  return children
}

function SoDono({ children }) {
  const s = useSessao()
  return s.eDono ? children : <Navigate to="/" replace />
}

export default function App() {
  return (
    <Routes>
      <Route path="/entrar" element={<Entrar />} />
      <Route path="/criar-conta" element={<CriarConta />} />
      <Route path="/esqueci-senha" element={<EsqueciSenha />} />
      <Route path="/nova-senha" element={<NovaSenha />} />
      <Route path="/convite/:token" element={<Convite />} />
      <Route path="/escolher-empresa" element={<EscolherEmpresa />} />

      <Route path="/escolher-painel" element={<EscolherPainel />} />

      <Route path="/admin" element={<AreaAdmin><Layout admin /></AreaAdmin>}>
        <Route index element={<AdminVisaoGeral />} />
        <Route path="empresas" element={<AdminEmpresas />} />
        <Route path="planos" element={<AdminPlanos />} />
        <Route path="assinaturas" element={<AdminAssinaturas />} />
        <Route path="historico" element={<AdminHistorico />} />
      </Route>

      <Route element={<AreaEmpresa><Layout /></AreaEmpresa>}>
        <Route index element={<Inicio />} />
        <Route path="agenda" element={<Agenda />} />
        <Route path="pacientes" element={<Pacientes />} />
        <Route path="pacientes/:id" element={<Paciente />} />
        <Route path="financeiro" element={<Financeiro />} />
        <Route path="relatorios" element={<Relatorios />} />
        <Route path="unidades" element={<Unidades />} />
        <Route path="profissionais" element={<Profissionais />} />
        <Route path="servicos" element={<Servicos />} />
        <Route path="equipe" element={<SoDono><Equipe /></SoDono>} />
        <Route path="empresa" element={<SoDono><MinhaEmpresa /></SoDono>} />
        <Route path="menu" element={<Menu />} />
      </Route>

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}

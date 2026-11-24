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
import AdminEmpresas from './pages/admin/AdminEmpresas.jsx'

/** Só deixa passar quem está logado e com uma empresa liberada aberta. */
function AreaEmpresa({ children }) {
  const s = useSessao()
  const local = useLocation()
  if (s.carregando) return <Carregando />
  if (!s.usuario) return <Navigate to="/entrar" state={{ de: local.pathname }} replace />
  if (s.recuperandoSenha) return <Navigate to="/nova-senha" replace />
  if (!s.vinculos.length) return <Navigate to={s.superAdmin ? '/admin' : '/criar-conta'} replace />
  if (!s.vinculo) return <Navigate to="/escolher-empresa" replace />
  if (['bloqueada', 'cancelada'].includes(s.empresa.status_assinatura)) return <Suspensa />
  return children
}

function AreaAdmin({ children }) {
  const s = useSessao()
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

      <Route path="/admin" element={<AreaAdmin><Layout admin><AdminEmpresas /></Layout></AreaAdmin>} />

      <Route element={<AreaEmpresa><Layout /></AreaEmpresa>}>
        <Route index element={<Inicio />} />
        <Route path="unidades" element={<Unidades />} />
        <Route path="profissionais" element={<Profissionais />} />
        <Route path="servicos" element={<Servicos />} />
        <Route path="equipe" element={<SoDono><Equipe /></SoDono>} />
        <Route path="empresa" element={<SoDono><MinhaEmpresa /></SoDono>} />
      </Route>

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}

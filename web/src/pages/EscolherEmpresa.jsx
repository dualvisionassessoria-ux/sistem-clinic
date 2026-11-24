import { Navigate, useNavigate } from 'react-router-dom'
import { Building2, ChevronRight, Shield } from 'lucide-react'
import TelaAcesso from '../components/TelaAcesso.jsx'
import { Carregando, Etiqueta } from '../components/ui.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { PAPEIS, STATUS_ASSINATURA } from '../lib/formato.js'

export default function EscolherEmpresa() {
  const s = useSessao()
  const navegar = useNavigate()
  if (s.carregando) return <Carregando />
  if (!s.usuario) return <Navigate to="/entrar" replace />

  const abrir = (id) => {
    s.setEmpresaId(id)
    navegar('/', { replace: true })
  }

  return (
    <TelaAcesso titulo="Escolha a empresa" subtitulo="Você faz parte de mais de uma equipe.">
      <div className="space-y-3">
        {s.vinculos.map((v) => {
          const st = STATUS_ASSINATURA[v.empresa.status_assinatura]
          return (
            <button key={v.id} onClick={() => abrir(v.empresa.id)}
              className="flex w-full items-center gap-3 rounded-2xl border border-slate-200 bg-white p-4 text-left hover:border-marca-500 hover:bg-marca-50">
              <span className="grid size-11 place-items-center rounded-xl bg-marca-100 text-marca-700">
                {v.empresa.logo_url ? <img src={v.empresa.logo_url} alt="" className="size-11 rounded-xl object-cover" /> : <Building2 className="size-5" />}
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate font-semibold text-slate-900">{v.empresa.nome}</span>
                <span className="text-xs text-slate-500">{PAPEIS[v.papel]}</span>
              </span>
              {v.empresa.status_assinatura !== 'ativa' && <Etiqueta className={st.cor}>{st.rotulo}</Etiqueta>}
              <ChevronRight className="size-5 text-slate-400" />
            </button>
          )
        })}
        {s.superAdmin && (
          <button onClick={() => navegar('/admin')} className="flex w-full items-center gap-3 rounded-2xl border border-dashed border-slate-300 p-4 text-left text-slate-600 hover:bg-slate-50">
            <Shield className="size-5" /> Painel da plataforma
          </button>
        )}
      </div>
    </TelaAcesso>
  )
}

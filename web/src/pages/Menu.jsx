import { Link } from 'react-router-dom'
import { ChevronRight } from 'lucide-react'
import { Cartao } from '../components/ui.jsx'
import { gruposCliente } from '../components/Layout.jsx'
import { useSessao } from '../lib/sessao.jsx'

/** Menu completo no celular (aba "Mais"). */
export default function Menu() {
  const s = useSessao()
  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-xl font-bold text-slate-900">{s.empresa?.nome}</h1>
        <p className="text-sm text-slate-500">Plano {s.plano?.nome}</p>
      </div>
      {gruposCliente(s.eDono).map((g) => (
        <section key={g.titulo}>
          <h2 className="mb-2 px-1 text-xs font-semibold uppercase tracking-wider text-slate-400">{g.titulo}</h2>
          <Cartao className="divide-y divide-slate-100">
            {g.itens.map((i) => {
              const conteudo = (
                <>
                  <span className={`grid size-9 place-items-center rounded-xl ${i.breve ? 'bg-slate-100 text-slate-400' : 'bg-agua-50 text-agua-600'}`}>
                    <i.icone className="size-5" />
                  </span>
                  <span className={`flex-1 text-sm font-medium ${i.breve ? 'text-slate-400' : 'text-slate-800'}`}>{i.rotulo}</span>
                  {i.breve ? <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[10px] text-slate-500">em breve</span> : <ChevronRight className="size-4 text-slate-300" />}
                </>
              )
              return i.breve
                ? <div key={i.rotulo} className="flex items-center gap-3 px-4 py-3">{conteudo}</div>
                : <Link key={i.rotulo} to={i.para} className="flex items-center gap-3 px-4 py-3 active:bg-slate-50">{conteudo}</Link>
            })}
          </Cartao>
        </section>
      ))}
    </div>
  )
}

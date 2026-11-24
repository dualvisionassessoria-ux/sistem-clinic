import { Link } from 'react-router-dom'
import { MapPin, UserRound, Scissors, Users, CheckCircle2, Circle, CalendarDays, ChevronRight } from 'lucide-react'
import { Cartao, Carregando } from '../components/ui.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { supabase } from '../lib/supabase.js'
import { useDados } from '../lib/useDados.js'
import { PAPEIS, limite } from '../lib/formato.js'

async function contar(tabela, empresaId) {
  const { count } = await supabase.from(tabela).select('*', { count: 'exact', head: true }).eq('empresa_id', empresaId).eq('ativo', true)
  return count ?? 0
}

export default function Inicio() {
  const s = useSessao()
  const empresaId = s.empresa.id
  const { dados, carregando } = useDados(async () => {
    const [unidades, profissionais, servicos, equipe] = await Promise.all([
      contar('unidades', empresaId), contar('profissionais', empresaId), contar('servicos', empresaId), contar('membros', empresaId),
    ])
    const { count: comJornada } = await supabase.from('jornadas').select('*', { count: 'exact', head: true }).eq('empresa_id', empresaId)
    return { unidades, profissionais, servicos, equipe, comJornada: comJornada ?? 0 }
  }, [empresaId])

  const primeiroNome = (s.perfil?.nome || '').split(' ')[0]
  const hora = new Date().getHours()
  const saudacao = hora < 12 ? 'Bom dia' : hora < 18 ? 'Boa tarde' : 'Boa noite'

  const cartoes = dados && [
    { para: '/unidades', rotulo: 'Unidades', valor: dados.unidades, max: s.plano?.limite_unidades, icone: MapPin },
    { para: '/profissionais', rotulo: 'Profissionais', valor: dados.profissionais, max: s.plano?.limite_profissionais, icone: UserRound },
    { para: '/servicos', rotulo: 'Serviços', valor: dados.servicos, icone: Scissors },
    ...(s.eDono ? [{ para: '/equipe', rotulo: 'Usuários', valor: dados.equipe, max: s.plano?.limite_usuarios, icone: Users }] : []),
  ]

  const passos = dados && [
    { feito: dados.unidades > 0, texto: 'Confira o endereço e o horário da unidade', para: '/unidades' },
    { feito: dados.profissionais > 0, texto: 'Cadastre os profissionais', para: '/profissionais' },
    { feito: dados.servicos > 0, texto: 'Cadastre os serviços com duração e preço', para: '/servicos' },
    { feito: dados.comJornada > 0, texto: 'Defina a jornada de cada profissional', para: '/profissionais' },
    { feito: dados.equipe > 1, texto: 'Convide a recepção e os profissionais', para: '/equipe' },
  ]
  const feitos = passos?.filter((p) => p.feito).length ?? 0

  return (
    <div className="space-y-6">
      <div>
        <p className="text-sm text-slate-500">{saudacao}{primeiroNome ? `, ${primeiroNome}` : ''}</p>
        <h1 className="text-2xl font-bold text-slate-900">{s.empresa.nome}</h1>
        <p className="text-sm text-slate-500">{PAPEIS[s.papel] ?? 'Administrador'} · Plano {s.plano?.nome}</p>
      </div>

      {carregando ? <Carregando /> : (
        <>
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            {cartoes.map((c) => (
              <Link key={c.para} to={c.para}>
                <Cartao className="p-4 transition hover:border-marca-300 hover:shadow">
                  <c.icone className="size-5 text-agua-600" />
                  <p className="mt-3 text-2xl font-bold text-slate-900">{c.valor}</p>
                  <p className="text-xs text-slate-500">
                    {c.rotulo}{c.max !== undefined && <> · limite {limite(c.max)}</>}
                  </p>
                </Cartao>
              </Link>
            ))}
          </div>

          {s.eDono && feitos < passos.length && (
            <Cartao className="p-5">
              <div className="flex items-center justify-between">
                <h2 className="font-semibold text-slate-900">Primeiros passos</h2>
                <span className="text-sm text-slate-500">{feitos} de {passos.length}</span>
              </div>
              <div className="mt-3 h-2 overflow-hidden rounded-full bg-slate-100">
                <div className="h-full rounded-full bg-agua-500 transition-all" style={{ width: `${(feitos / passos.length) * 100}%` }} />
              </div>
              <ul className="mt-4 divide-y divide-slate-100">
                {passos.map((p) => (
                  <li key={p.texto}>
                    <Link to={p.para} className="flex items-center gap-3 py-3 text-sm">
                      {p.feito ? <CheckCircle2 className="size-5 text-agua-500" /> : <Circle className="size-5 text-slate-300" />}
                      <span className={p.feito ? 'text-slate-400 line-through' : 'text-slate-700'}>{p.texto}</span>
                      <ChevronRight className="ml-auto size-4 text-slate-300" />
                    </Link>
                  </li>
                ))}
              </ul>
            </Cartao>
          )}

          <Cartao className="flex items-center gap-4 bg-gradient-to-r from-marca-700 to-agua-600 p-5 text-white">
            <CalendarDays className="size-8 shrink-0 text-agua-100" />
            <div>
              <p className="font-semibold">Agenda chegando</p>
              <p className="text-sm text-marca-50">A próxima etapa traz a agenda por profissional e o cadastro de clientes.</p>
            </div>
          </Cartao>
        </>
      )}
    </div>
  )
}

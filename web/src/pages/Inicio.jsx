import { Link } from 'react-router-dom'
import { CheckCircle2, Circle, CalendarDays, ChevronRight, Cake, MessageCircle, Plus, Wallet, UserX, Users } from 'lucide-react'
import { Alerta, Botao, Cartao, Carregando } from '../components/ui.jsx'
import { StatusEtiqueta, useOpera } from '../components/Atendimento.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'
import { ok, useDados } from '../lib/useDados.js'
import { PAPEIS, linkWhatsApp, reais } from '../lib/formato.js'
import { deIso, diaLongo, horaDe, inicioDia, inicioMes, somarDias } from '../lib/agenda.js'

async function contar(tabela, empresaId, extra = (q) => q) {
  const { count } = await extra(supabase.from(tabela).select('*', { count: 'exact', head: true }).eq('empresa_id', empresaId))
  return count ?? 0
}

export default function Inicio() {
  const s = useSessao()
  const opera = useOpera()
  const empresaId = s.empresa.id
  const { dados, carregando, erro } = useDados(async () => {
    const hoje = inicioDia(new Date())
    const [agHoje, rel, clientes, unidades, profissionais, servicos, equipe, jornadas] = await Promise.all([
      supabase.from('agendamentos').select('id, inicio, status, profissional_id, cliente:clientes(nome), servico:servicos(nome), profissional:profissionais(nome, cor_agenda)')
        .eq('empresa_id', empresaId).gte('inicio', hoje.toISOString()).lt('inicio', somarDias(hoje, 1).toISOString()).neq('status', 'cancelado').order('inicio'),
      supabase.rpc('relatorio_periodo', { p_empresa: empresaId, p_inicio: inicioMes(hoje).toISOString(), p_fim: somarDias(hoje, 1).toISOString() }),
      supabase.from('clientes').select('id, nome, telefone, data_nascimento').eq('empresa_id', empresaId).eq('ativo', true).not('data_nascimento', 'is', null).limit(5000),
      contar('unidades', empresaId, (q) => q.eq('ativo', true)),
      contar('profissionais', empresaId, (q) => q.eq('ativo', true)),
      contar('servicos', empresaId, (q) => q.eq('ativo', true)),
      contar('membros', empresaId, (q) => q.eq('ativo', true)),
      contar('jornadas', empresaId),
    ])
    const d = new Date()
    const aniversariantes = (clientes.data ?? []).filter((c) => {
      if (!c.data_nascimento) return false
      const n = deIso(c.data_nascimento)
      return n.getDate() === d.getDate() && n.getMonth() === d.getMonth()
    })
    return { hoje: ok(agHoje), rel: rel.data, aniversariantes, unidades, profissionais, servicos, equipe, jornadas }
  }, [empresaId])

  const primeiroNome = (s.perfil?.nome || '').split(' ')[0]
  const h = new Date().getHours()
  const saudacao = h < 12 ? 'Bom dia' : h < 18 ? 'Boa tarde' : 'Boa noite'

  const passos = dados && [
    { feito: dados.unidades > 0, texto: 'Confira o endereço e o horário da unidade', para: '/unidades' },
    { feito: dados.profissionais > 0, texto: 'Cadastre os profissionais', para: '/profissionais' },
    { feito: dados.servicos > 0, texto: 'Cadastre os serviços com duração e preço', para: '/servicos' },
    { feito: dados.jornadas > 0, texto: 'Defina a jornada de cada profissional', para: '/profissionais' },
    { feito: dados.equipe > 1, texto: 'Convide a recepção e os profissionais', para: '/equipe' },
  ]
  const feitos = passos?.filter((p) => p.feito).length ?? 0
  const agora = Date.now()
  const proximos = dados?.hoje.filter((a) => ['agendado', 'confirmado'].includes(a.status) && new Date(a.inicio).getTime() > agora - 30 * 60000) ?? []
  const rel = dados?.rel

  return (
    <div className="space-y-6">
      <div className="flex items-end justify-between gap-3">
        <div>
          <p className="text-sm text-slate-500">{saudacao}{primeiroNome ? `, ${primeiroNome}` : ''} · {diaLongo(new Date())}</p>
          <h1 className="text-2xl font-bold text-slate-900">{s.empresa.nome}</h1>
          <p className="text-sm text-slate-500">{PAPEIS[s.papel] ?? 'Administrador'} · Plano {s.plano?.nome}</p>
        </div>
        {opera && <Link to="/agenda?novo=1" className="hidden md:block"><Botao><Plus className="size-4" /> Agendar</Botao></Link>}
      </div>

      {erro ? <Alerta>Não foi possível carregar o painel. {mensagemErro(erro)}</Alerta> : carregando || !dados ? <Carregando /> : (
        <>
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Numero para="/agenda" icone={CalendarDays} valor={dados.hoje.length} rotulo="Agendamentos hoje"
              detalhe={`${dados.hoje.filter((a) => a.status === 'confirmado').length} confirmados`} />
            {rel && <Numero para="/relatorios" icone={Users} valor={rel.agendamentos} rotulo="Agendamentos no mês" detalhe={`${rel.novos_clientes} pacientes novos`} />}
            {rel && <Numero para="/relatorios" icone={UserX} valor={`${rel.taxa_faltas}%`} rotulo="Faltas no mês" detalhe={`${rel.por_status?.faltou ?? 0} faltas`} />}
            {rel && <Numero para="/financeiro" icone={Wallet} valor={reais(rel.faturamento)} rotulo="Recebido no mês" detalhe={`${reais(rel.a_receber)} a receber`} />}
          </div>

          <div className="grid gap-5 lg:grid-cols-3">
            <Cartao className="lg:col-span-2">
              <div className="flex items-center justify-between border-b border-slate-100 px-5 py-4">
                <h2 className="font-semibold text-slate-900">Próximos atendimentos de hoje</h2>
                <Link to="/agenda" className="text-sm font-medium text-marca-700">Ver agenda</Link>
              </div>
              {!proximos.length ? (
                <p className="px-5 py-8 text-center text-sm text-slate-500">
                  {dados.hoje.length ? 'Nenhum atendimento pendente para o resto do dia.' : 'Nenhum agendamento para hoje.'}
                </p>
              ) : (
                <ul className="divide-y divide-slate-100">
                  {proximos.slice(0, 8).map((a) => (
                    <li key={a.id}>
                      <Link to="/agenda" className="flex items-center gap-3 px-5 py-3 hover:bg-slate-50">
                        <span className="w-12 shrink-0 text-sm font-bold text-slate-900">{horaDe(a.inicio)}</span>
                        <span className="h-8 w-1 shrink-0 rounded-full" style={{ background: a.profissional?.cor_agenda }} />
                        <span className="min-w-0 flex-1">
                          <span className="block truncate text-sm font-medium text-slate-800">{a.cliente?.nome}</span>
                          <span className="block truncate text-xs text-slate-500">{[a.servico?.nome, a.profissional?.nome].filter(Boolean).join(' · ')}</span>
                        </span>
                        <StatusEtiqueta status={a.status} />
                      </Link>
                    </li>
                  ))}
                </ul>
              )}
            </Cartao>

            <Cartao>
              <div className="flex items-center gap-2 border-b border-slate-100 px-5 py-4">
                <Cake className="size-5 text-pink-500" />
                <h2 className="font-semibold text-slate-900">Aniversariantes de hoje</h2>
              </div>
              {!dados.aniversariantes.length ? (
                <p className="px-5 py-8 text-center text-sm text-slate-500">Ninguém faz aniversário hoje.</p>
              ) : (
                <ul className="divide-y divide-slate-100">
                  {dados.aniversariantes.map((c) => (
                    <li key={c.id} className="flex items-center gap-3 px-5 py-3">
                      <Link to={`/pacientes/${c.id}`} className="min-w-0 flex-1 truncate text-sm font-medium text-slate-800 hover:text-marca-700">{c.nome}</Link>
                      {c.telefone && (
                        <a href={linkWhatsApp(`Feliz aniversário, ${c.nome.split(' ')[0]}! 🎉 Toda a equipe da ${s.empresa.nome} deseja um dia maravilhoso!`, c.telefone)}
                          target="_blank" rel="noreferrer" className="rounded-full p-2 text-emerald-600 hover:bg-emerald-50" aria-label="Parabenizar pelo WhatsApp">
                          <MessageCircle className="size-4" />
                        </a>
                      )}
                    </li>
                  ))}
                </ul>
              )}
            </Cartao>
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
        </>
      )}
    </div>
  )
}

function Numero({ para, icone: Icone, valor, rotulo, detalhe }) {
  return (
    <Link to={para}>
      <Cartao className="h-full p-4 transition hover:border-marca-300 hover:shadow">
        <Icone className="size-5 text-agua-600" />
        <p className="mt-3 text-2xl font-bold text-slate-900">{valor}</p>
        <p className="text-xs text-slate-500">{rotulo}</p>
        {detalhe && <p className="text-xs text-slate-400">{detalhe}</p>}
      </Cartao>
    </Link>
  )
}

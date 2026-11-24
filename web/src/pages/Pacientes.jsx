import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Plus, Search, ContactRound, Cake, ChevronRight, Clock3, Users } from 'lucide-react'
import { Alerta, AreaTexto, Botao, Campo, Cartao, Carregando, Entrada, Etiqueta, Interruptor, Painel, Selecao, Vazio, cx, useAviso } from '../components/ui.jsx'
import { useOpera } from '../components/Atendimento.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'
import { ok, useDados } from '../lib/useDados.js'
import { data as dataBR } from '../lib/formato.js'
import { deIso, iniciais, telefone } from '../lib/agenda.js'

export const ORIGENS_PACIENTE = ['Indicação', 'Instagram', 'Google', 'Facebook', 'Passou na frente', 'WhatsApp', 'Outro']

/** Campos da ficha do paciente (usado no cadastro e na edição). */
export function FormPaciente({ id, f, setF, aoEnviar, erro, somenteLeitura }) {
  const campo = (k) => (e) => setF((x) => ({ ...x, [k]: e.target.value }))
  return (
    <form id={id} onSubmit={aoEnviar} className="space-y-4">
      <fieldset disabled={somenteLeitura} className="space-y-4">
        <Campo rotulo="Nome completo"><Entrada required minLength={2} value={f.nome} onChange={campo('nome')} /></Campo>
        <div className="grid grid-cols-2 gap-3">
          <Campo rotulo="WhatsApp" dica="Com DDD."><Entrada inputMode="tel" value={f.telefone} onChange={campo('telefone')} placeholder="(11) 99999-9999" /></Campo>
          <Campo rotulo="Nascimento"><Entrada type="date" value={f.data_nascimento} onChange={campo('data_nascimento')} /></Campo>
        </div>
        <div className="grid grid-cols-2 gap-3">
          <Campo rotulo="E-mail"><Entrada type="email" value={f.email} onChange={campo('email')} /></Campo>
          <Campo rotulo="CPF"><Entrada inputMode="numeric" value={f.documento} onChange={campo('documento')} /></Campo>
        </div>
        <div className="grid grid-cols-2 gap-3">
          <Campo rotulo="Gênero">
            <Selecao value={f.genero} onChange={campo('genero')}>
              <option value="">Não informado</option>
              <option>Feminino</option><option>Masculino</option><option>Outro</option>
            </Selecao>
          </Campo>
          <Campo rotulo="Como conheceu">
            <Selecao value={f.origem} onChange={campo('origem')}>
              <option value="">Não informado</option>
              {ORIGENS_PACIENTE.map((o) => <option key={o}>{o}</option>)}
            </Selecao>
          </Campo>
        </div>
        <Campo rotulo="Endereço"><Entrada value={f.endereco} onChange={campo('endereco')} /></Campo>
        <Campo rotulo="Observações" dica="Alergias, preferências, cuidados. Só a equipe vê.">
          <AreaTexto rows={4} value={f.observacoes} onChange={campo('observacoes')} />
        </Campo>
        <Interruptor ligado={f.aceita_whatsapp} aoMudar={(v) => setF((x) => ({ ...x, aceita_whatsapp: v }))}
          rotulo="Recebe mensagens automáticas" descricao="Confirmações, lembretes, aniversário e campanhas pelo WhatsApp." disabled={somenteLeitura} />
      </fieldset>
      <Alerta>{erro}</Alerta>
    </form>
  )
}

export const pacienteVazio = () => ({
  nome: '', telefone: '', data_nascimento: '', email: '', documento: '', genero: '', origem: '', endereco: '', observacoes: '', aceita_whatsapp: true,
})

export function registroPaciente(f) {
  const v = (x) => (x?.trim?.() ? x.trim() : null)
  return {
    nome: f.nome.trim(), telefone: v(f.telefone), data_nascimento: f.data_nascimento || null, email: v(f.email), documento: v(f.documento),
    genero: v(f.genero), origem: v(f.origem), endereco: v(f.endereco), observacoes: v(f.observacoes), aceita_whatsapp: f.aceita_whatsapp,
  }
}

const FILTROS = [
  { id: 'todos', rotulo: 'Todos', icone: Users },
  { id: 'aniversario', rotulo: 'Aniversariantes do mês', icone: Cake },
  { id: 'sumidos', rotulo: 'Sem vir há 60 dias', icone: Clock3 },
]

export default function Pacientes() {
  const s = useSessao()
  const opera = useOpera()
  const avisar = useAviso()
  const navegar = useNavigate()
  const empresaId = s.empresa.id
  const [busca, setBusca] = useState('')
  const [filtro, setFiltro] = useState('todos')
  const [limite, setLimite] = useState(60)
  const [novo, setNovo] = useState(null)
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)

  const { dados, carregando, recarregar } = useDados(async () => {
    const r = await supabase.from('clientes')
      .select('id, nome, telefone, data_nascimento, ultima_visita_em, criado_em')
      .eq('empresa_id', empresaId).eq('ativo', true).order('nome').limit(5000)
    return ok(r)
  }, [empresaId])

  const mes = new Date().getMonth()
  const lista = useMemo(() => {
    let l = dados ?? []
    const t = busca.trim().toLowerCase()
    if (t) {
      const dig = t.replace(/\D/g, '')
      l = l.filter((c) => c.nome.toLowerCase().includes(t) || (dig.length >= 3 && (c.telefone ?? '').includes(dig)))
    }
    if (filtro === 'aniversario') {
      l = l.filter((c) => c.data_nascimento && deIso(c.data_nascimento).getMonth() === mes)
        .sort((a, b) => deIso(a.data_nascimento).getDate() - deIso(b.data_nascimento).getDate())
    }
    if (filtro === 'sumidos') {
      const corte = Date.now() - 60 * 86400000
      l = l.filter((c) => c.ultima_visita_em && new Date(c.ultima_visita_em).getTime() < corte)
        .sort((a, b) => new Date(a.ultima_visita_em) - new Date(b.ultima_visita_em))
    }
    return l
  }, [dados, busca, filtro, mes])

  async function salvar(e) {
    e.preventDefault()
    setErro('')
    setSalvando(true)
    try {
      const c = ok(await supabase.from('clientes').insert({ ...registroPaciente(novo), empresa_id: empresaId, criado_por: s.usuario.id }).select('id').single())
      avisar('Paciente cadastrado')
      setNovo(null)
      recarregar()
      navegar(`/pacientes/${c.id}`)
    } catch (err) {
      setErro(mensagemErro(err))
    } finally {
      setSalvando(false)
    }
  }

  if (carregando && !dados) return <Carregando />
  const hojeDia = new Date().getDate()

  return (
    <div>
      <div className="mb-5 flex items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold text-slate-900 md:text-2xl">Pacientes</h1>
          <p className="text-sm text-slate-500">{dados?.length ?? 0} cadastrados</p>
        </div>
        {opera && <Botao onClick={() => { setErro(''); setNovo(pacienteVazio()) }}><Plus className="size-4" /> <span className="hidden sm:inline">Novo paciente</span></Botao>}
      </div>

      <div className="relative mb-3">
        <Search className="pointer-events-none absolute left-3.5 top-3.5 size-4 text-slate-400" />
        <Entrada className="pl-10" placeholder="Buscar por nome ou telefone" value={busca} onChange={(e) => { setBusca(e.target.value); setLimite(60) }} />
      </div>
      <div className="-mx-4 mb-4 flex gap-2 overflow-x-auto px-4 pb-1 md:mx-0 md:px-0">
        {FILTROS.map((fl) => (
          <button key={fl.id} onClick={() => { setFiltro(fl.id); setLimite(60) }}
            className={cx('flex shrink-0 items-center gap-1.5 rounded-full border px-3 py-1.5 text-sm',
              filtro === fl.id ? 'border-marca-600 bg-marca-700 text-white' : 'border-slate-200 bg-white text-slate-600 hover:bg-slate-50')}>
            <fl.icone className="size-4" /> {fl.rotulo}
          </button>
        ))}
      </div>

      {!dados?.length ? (
        <Vazio icone={ContactRound} titulo="Nenhum paciente ainda" texto="Cadastre aqui ou direto ao marcar um horário na agenda."
          acao={opera && <Botao onClick={() => setNovo(pacienteVazio())}><Plus className="size-4" /> Cadastrar paciente</Botao>} />
      ) : !lista.length ? (
        <p className="py-10 text-center text-sm text-slate-500">Nenhum paciente encontrado.</p>
      ) : (
        <>
          <Cartao className="divide-y divide-slate-100">
            {lista.slice(0, limite).map((c) => {
              const nasc = c.data_nascimento && deIso(c.data_nascimento)
              const aniversarioHoje = nasc && nasc.getMonth() === mes && nasc.getDate() === hojeDia
              return (
                <Link key={c.id} to={`/pacientes/${c.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-slate-50">
                  <span className="grid size-10 shrink-0 place-items-center rounded-full bg-agua-50 text-sm font-semibold text-agua-700">{iniciais(c.nome)}</span>
                  <span className="min-w-0 flex-1">
                    <span className="flex items-center gap-2">
                      <span className="truncate font-medium text-slate-900">{c.nome}</span>
                      {aniversarioHoje && <Etiqueta className="bg-pink-100 text-pink-700"><Cake className="mr-1 size-3" />Hoje</Etiqueta>}
                    </span>
                    <span className="block truncate text-xs text-slate-500">
                      {[telefone(c.telefone),
                        filtro === 'aniversario' && nasc ? `${String(nasc.getDate()).padStart(2, '0')}/${String(nasc.getMonth() + 1).padStart(2, '0')} · faz ${new Date().getFullYear() - nasc.getFullYear()} anos` : null,
                        c.ultima_visita_em ? `última visita ${dataBR(c.ultima_visita_em)}` : null].filter(Boolean).join(' · ')}
                    </span>
                  </span>
                  <ChevronRight className="size-4 text-slate-300" />
                </Link>
              )
            })}
          </Cartao>
          {lista.length > limite && (
            <div className="mt-3 text-center">
              <Botao variante="secundario" onClick={() => setLimite((l) => l + 100)}>Mostrar mais ({lista.length - limite})</Botao>
            </div>
          )}
        </>
      )}

      <Painel aberto={!!novo} aoFechar={() => setNovo(null)} titulo="Novo paciente"
        rodape={
          <div className="flex gap-2">
            <Botao variante="secundario" className="flex-1" onClick={() => setNovo(null)}>Cancelar</Botao>
            <Botao className="flex-1" type="submit" form="form-paciente" carregando={salvando}>Cadastrar</Botao>
          </div>
        }>
        {novo && <FormPaciente id="form-paciente" f={novo} setF={setNovo} aoEnviar={salvar} erro={erro} />}
      </Painel>
    </div>
  )
}

import { useEffect, useMemo, useRef, useState } from 'react'
import {
  Smartphone, QrCode, RefreshCw, Unplug, CheckCircle2, Lock, Send, Bot, MessageCircle, ArrowDownLeft, ArrowUpRight, Megaphone, Users,
} from 'lucide-react'
import { Alerta, AreaTexto, Botao, Campo, Cartao, Carregando, Entrada, Etiqueta, Interruptor, Selecao, Vazio, cx, useAviso } from '../components/ui.jsx'
import { useCadastros } from '../components/Atendimento.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'
import { ok, useDados } from '../lib/useDados.js'
import { dataHora, telefone } from '../lib/agenda.js'

const ABAS = [['conexao', 'Conexão'], ['automacoes', 'Mensagens automáticas'], ['campanhas', 'Campanhas'], ['historico', 'Histórico']]

const MODELOS = {
  confirmacao: { titulo: 'Confirmação de horário', desc: 'Pede para o paciente responder SIM ou NÃO. A resposta muda o status na agenda sozinha.', campo: 'horas', rotuloCampo: 'Horas antes', recurso: 'lembretes_whatsapp' },
  lembrete: { titulo: 'Lembrete', desc: 'Aviso curto pouco antes do horário.', campo: 'horas', rotuloCampo: 'Horas antes', recurso: 'lembretes_whatsapp' },
  resposta_sim: { titulo: 'Resposta ao SIM', desc: 'Enviada quando o paciente confirma.', recurso: 'lembretes_whatsapp' },
  resposta_nao: { titulo: 'Resposta ao NÃO', desc: 'Enviada quando o paciente cancela pelo WhatsApp.', recurso: 'lembretes_whatsapp' },
  pos_atendimento: { titulo: 'Pós-atendimento e avaliação no Google', desc: 'Agradece e pede avaliação. Precisa do link de avaliação cadastrado na unidade.', campo: 'horas', rotuloCampo: 'Horas depois', recurso: 'avaliacao_google' },
  aniversario: { titulo: 'Aniversário', desc: 'Parabéns no dia do aniversário do paciente.', campo: 'horas', rotuloCampo: 'Enviar a partir das (hora)', recurso: 'campanhas' },
  retorno: { titulo: 'Convite de retorno', desc: 'Para quem não volta há algum tempo e não tem nada marcado.', campo: 'dias', rotuloCampo: 'Dias sem vir', recurso: 'campanhas' },
}
const ORDEM = ['confirmacao', 'lembrete', 'resposta_sim', 'resposta_nao', 'pos_atendimento', 'aniversario', 'retorno']

const VARIAVEIS = ['primeiro_nome', 'nome', 'data', 'hora', 'dia_semana', 'servico', 'profissional', 'unidade', 'endereco', 'empresa', 'link_avaliacao']
const VARS_CLIENTE = ['primeiro_nome', 'nome', 'empresa']

const PLANO_DO_RECURSO = { avaliacao_google: 'Profissional', campanhas: 'Profissional', marcacao_whatsapp: 'Premium' }

const EXEMPLO = {
  nome: 'Maria Souza', primeiro_nome: 'Maria', data: '26/11', hora: '14:30', dia_semana: 'quarta-feira', servico: 'Limpeza',
  profissional: 'Dra. Ana', unidade: 'Centro', endereco: 'Rua das Flores, 120', link_avaliacao: 'https://g.page/r/...',
}
const renderizar = (t, vars) => t.replace(/\{\{(\w+)\}\}/g, (m, k) => vars[k] ?? m)

/** Mostra o texto como o WhatsApp mostra (*negrito* e _itálico_). */
function BalaoWhats({ texto }) {
  const partes = texto.split(/(\*[^*\n]+\*|_[^_\n]+_)/g)
  return (
    <div className="max-w-sm whitespace-pre-line rounded-2xl rounded-tl-sm bg-[#DCF8C6] px-3 py-2 text-sm text-slate-800 shadow-sm">
      {partes.map((p, i) => (p.startsWith('*') && p.endsWith('*') ? <b key={i}>{p.slice(1, -1)}</b>
        : p.startsWith('_') && p.endsWith('_') ? <i key={i}>{p.slice(1, -1)}</i> : p))}
    </div>
  )
}

async function chamarFuncao(corpo) {
  const { data, error } = await supabase.functions.invoke('whatsapp', { body: corpo })
  if (error) {
    let msg = error.message
    try { msg = (await error.context.json()).erro ?? msg } catch { /* sem corpo */ }
    if (/Failed to send a request|FunctionsFetchError/i.test(msg)) msg = 'A função do WhatsApp ainda não foi publicada no Supabase.'
    throw new Error(msg)
  }
  return data
}

export default function WhatsApp() {
  const s = useSessao()
  const [aba, setAba] = useState('conexao')
  const recursos = s.plano?.recursos ?? {}
  return (
    <div>
      <div className="mb-4">
        <h1 className="text-xl font-bold text-slate-900 md:text-2xl">WhatsApp</h1>
        <p className="text-sm text-slate-500">Confirmações, lembretes, avaliações e marcação automática</p>
      </div>
      <div className="-mx-4 mb-5 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0">
        <div className="flex gap-1 rounded-xl bg-slate-100 p-1">
          {ABAS.map(([k, r]) => (
            <button key={k} onClick={() => setAba(k)}
              className={cx('whitespace-nowrap rounded-lg px-3 py-2 text-sm font-medium', aba === k ? 'bg-white text-marca-700 shadow-sm' : 'text-slate-500')}>{r}</button>
          ))}
        </div>
      </div>
      {aba === 'conexao' && <Conexao recursos={recursos} />}
      {aba === 'automacoes' && <Automacoes recursos={recursos} />}
      {aba === 'campanhas' && <Campanhas recursos={recursos} />}
      {aba === 'historico' && <Historico />}
    </div>
  )
}

/* ------------------------------------------------------------------ conexão por unidade */
function Conexao({ recursos }) {
  const s = useSessao()
  const { dados: cad } = useCadastros(s.empresa.id)
  const { dados: instancias, recarregar } = useDados(async () => ok(await supabase.from('whatsapp_instancias').select('*').eq('empresa_id', s.empresa.id)), [s.empresa.id])
  if (!cad || !instancias) return <Carregando />
  return (
    <div className="space-y-4">
      {cad.unidades.map((u) => (
        <CartaoConexao key={u.id} unidade={u} instancia={instancias.find((i) => i.unidade_id === u.id)} aoMudar={recarregar} />
      ))}
      <Cartao className="flex items-start gap-4 p-5">
        <span className={cx('grid size-11 shrink-0 place-items-center rounded-2xl', recursos.marcacao_whatsapp ? 'bg-agua-50 text-agua-600' : 'bg-slate-100 text-slate-400')}><Bot className="size-5" /></span>
        <div className="min-w-0">
          <p className="flex flex-wrap items-center gap-2 font-semibold text-slate-900">
            Marcação pelo WhatsApp
            {recursos.marcacao_whatsapp ? <Etiqueta className="bg-emerald-100 text-emerald-700">Ativa</Etiqueta> : <Etiqueta className="bg-marca-100 text-marca-700">Plano Premium</Etiqueta>}
          </p>
          <p className="mt-1 text-sm text-slate-500">
            Quando o paciente manda mensagem, o atendimento automático mostra um menu: marcar horário (escolhe serviço, profissional, dia e horário livre),
            ver ou cancelar os próprios horários, ou falar com a recepção (aí o robô fica quieto por 12 horas).
            Os horários marcados entram direto na agenda, com a etiqueta “via WhatsApp”. Só aparecem os serviços marcados como “disponível para marcar pelo WhatsApp”.
          </p>
        </div>
      </Cartao>
    </div>
  )
}

function CartaoConexao({ unidade, instancia, aoMudar }) {
  const s = useSessao()
  const avisar = useAviso()
  const [qr, setQr] = useState(null)
  const [codigo, setCodigo] = useState(null)
  const [ocupado, setOcupado] = useState('')
  const [erro, setErro] = useState('')
  const [status, setStatus] = useState(instancia?.status ?? 'desconectado')
  const tentativas = useRef(0)

  useEffect(() => { setStatus(instancia?.status ?? 'desconectado') }, [instancia?.status])

  // enquanto o QR está na tela, consulta a conexão a cada 4 segundos
  useEffect(() => {
    if (!qr) return
    tentativas.current = 0
    const t = setInterval(async () => {
      tentativas.current++
      try {
        const r = await chamarFuncao({ acao: 'status', unidade_id: unidade.id })
        if (r.status === 'conectado') {
          setQr(null); setStatus('conectado'); avisar('WhatsApp conectado!'); aoMudar()
        }
      } catch { /* tenta de novo */ }
      if (tentativas.current > 40) { setQr(null); setErro('O QR Code expirou. Clique em conectar de novo.') }
    }, 4000)
    return () => clearInterval(t)
  }, [qr]) // eslint-disable-line react-hooks/exhaustive-deps

  async function agir(acao) {
    setErro('')
    setOcupado(acao)
    try {
      const r = await chamarFuncao({ acao, unidade_id: unidade.id })
      if (r.erro === 'nao_configurado') {
        setErro('O servidor de WhatsApp (Evolution API) ainda não foi configurado na plataforma. Veja o passo a passo de instalação.')
      } else {
        setStatus(r.status)
        setQr(r.qr ?? null)
        setCodigo(r.codigo ?? null)
        if (acao === 'desconectar') avisar('WhatsApp desconectado')
        if (r.status === 'conectado' && acao !== 'status') avisar('WhatsApp conectado!')
        aoMudar()
      }
    } catch (e) {
      setErro(mensagemErro(e))
    } finally {
      setOcupado('')
    }
  }

  const ST = {
    conectado: ['Conectado', 'bg-emerald-100 text-emerald-700'],
    conectando: ['Aguardando leitura do QR Code', 'bg-amber-100 text-amber-800'],
    desconectado: ['Desconectado', 'bg-slate-100 text-slate-600'],
  }[status]

  return (
    <Cartao className="p-5">
      <div className="flex flex-wrap items-start gap-4">
        <span className={cx('grid size-11 shrink-0 place-items-center rounded-2xl', status === 'conectado' ? 'bg-emerald-50 text-emerald-600' : 'bg-slate-100 text-slate-400')}>
          <Smartphone className="size-5" />
        </span>
        <div className="min-w-0 flex-1">
          <p className="font-semibold text-slate-900">{unidade.nome}</p>
          <div className="mt-1 flex flex-wrap items-center gap-2 text-sm text-slate-500">
            <Etiqueta className={ST[1]}>{ST[0]}</Etiqueta>
            {status === 'conectado' && instancia?.numero && <span className="whitespace-nowrap">{telefone(instancia.numero)}</span>}
          </div>
        </div>
        <div className="flex w-full flex-wrap items-center justify-end gap-2 sm:w-auto">
          <button onClick={() => agir('status')} className="rounded-full p-2.5 text-slate-400 hover:bg-slate-100" aria-label="Atualizar situação">
            <RefreshCw className={cx('size-4', ocupado === 'status' && 'animate-spin')} />
          </button>
          {s.eDono && status !== 'conectado' && (
            <Botao variante="agua" carregando={ocupado === 'conectar'} onClick={() => agir('conectar')}><QrCode className="size-4" /> {qr ? 'Novo QR Code' : 'Conectar'}</Botao>
          )}
          {s.eDono && status === 'conectado' && (
            <Botao variante="perigo" carregando={ocupado === 'desconectar'} onClick={() => window.confirm('Desconectar este WhatsApp? As mensagens automáticas param até conectar de novo.') && agir('desconectar')}>
              <Unplug className="size-4" /> Desconectar
            </Botao>
          )}
        </div>
      </div>
      {erro && <div className="mt-4"><Alerta>{erro}</Alerta></div>}
      {qr && (
        <div className="mt-5 flex flex-col items-center gap-4 rounded-2xl bg-slate-50 p-5 md:flex-row md:items-start">
          <img src={qr.startsWith('data:') ? qr : `data:image/png;base64,${qr}`} alt="QR Code para conectar o WhatsApp" className="size-56 rounded-xl bg-white p-2 shadow-sm" />
          <ol className="list-decimal space-y-2 pl-5 text-sm text-slate-700">
            <li>No celular da unidade, abra o <b>WhatsApp</b> (de preferência o WhatsApp Business).</li>
            <li>Toque em <b>Configurações</b> (ou nos três pontinhos) e depois em <b>Aparelhos conectados</b>.</li>
            <li>Toque em <b>Conectar um aparelho</b> e aponte a câmera para este QR Code.</li>
            <li>Pronto. Esta tela atualiza sozinha quando conectar.</li>
            {codigo && <li>Sem câmera? Use “Conectar com número de telefone” e digite o código <b className="font-mono">{codigo}</b>.</li>}
          </ol>
        </div>
      )}
      {status === 'conectado' && (
        <p className="mt-4 flex items-center gap-2 text-sm text-emerald-700"><CheckCircle2 className="size-4" /> As mensagens automáticas desta unidade saem por este número.</p>
      )}
    </Cartao>
  )
}

/* ------------------------------------------------------------------ textos automáticos */
function Automacoes({ recursos }) {
  const s = useSessao()
  const { dados, carregando, recarregar } = useDados(async () => ok(await supabase.from('modelos_mensagem').select('*').eq('empresa_id', s.empresa.id)), [s.empresa.id])
  if (carregando && !dados) return <Carregando />
  const porTipo = Object.fromEntries((dados ?? []).map((m) => [m.tipo, m]))
  return (
    <div className="space-y-4">
      <Alerta tipo="info">
        Use as variáveis entre chaves, como <b>{'{{primeiro_nome}}'}</b> e <b>{'{{hora}}'}</b>. O sistema troca pelo dado de cada paciente.
        *Asteriscos* deixam o texto em negrito no WhatsApp. As mensagens só saem para quem tem telefone e está marcado para receber mensagens automáticas.
      </Alerta>
      {ORDEM.filter((t) => porTipo[t]).map((t) => (
        <EditorModelo key={t} modelo={porTipo[t]} info={MODELOS[t]} liberado={!!recursos[MODELOS[t].recurso]} podeEditar={s.eDono} aoSalvar={recarregar} />
      ))}
    </div>
  )
}

function EditorModelo({ modelo, info, liberado, podeEditar, aoSalvar }) {
  const s = useSessao()
  const avisar = useAviso()
  const [f, setF] = useState(modelo)
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState('')
  const area = useRef(null)
  useEffect(() => { setF(modelo) }, [modelo])
  const mudou = f.texto !== modelo.texto || f.ativo !== modelo.ativo || f.horas !== modelo.horas || f.dias !== modelo.dias
  const vars = ['aniversario', 'retorno'].includes(modelo.tipo) ? VARS_CLIENTE : VARIAVEIS

  function inserir(v) {
    const el = area.current
    const ini = el?.selectionStart ?? f.texto.length
    const fim = el?.selectionEnd ?? f.texto.length
    const novo = f.texto.slice(0, ini) + `{{${v}}}` + f.texto.slice(fim)
    setF({ ...f, texto: novo })
    requestAnimationFrame(() => { el?.focus(); el?.setSelectionRange(ini + v.length + 4, ini + v.length + 4) })
  }

  async function salvar(dados = f) {
    setErro('')
    setSalvando(true)
    try {
      ok(await supabase.from('modelos_mensagem').update({
        texto: dados.texto, ativo: dados.ativo, horas: dados.horas === '' ? null : dados.horas, dias: dados.dias === '' ? null : dados.dias,
      }).eq('id', modelo.id))
      avisar('Mensagem salva')
      aoSalvar()
    } catch (e) {
      setErro(mensagemErro(e))
    } finally {
      setSalvando(false)
    }
  }

  return (
    <Cartao className={cx('p-5', !liberado && 'opacity-70')}>
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="flex flex-wrap items-center gap-2 font-semibold text-slate-900">
            {info.titulo}
            {!liberado && <Etiqueta className="bg-marca-100 text-marca-700"><Lock className="mr-1 size-3" />Plano {PLANO_DO_RECURSO[info.recurso]}</Etiqueta>}
          </p>
          <p className="text-sm text-slate-500">{info.desc}</p>
        </div>
        <div className="shrink-0">
          <Interruptor ligado={f.ativo} disabled={!podeEditar || !liberado}
            aoMudar={(v) => { const n = { ...f, ativo: v }; setF(n); salvar(n) }} />
        </div>
      </div>
      {liberado && (
        <div className="mt-4 grid gap-4 lg:grid-cols-2">
          <div className="space-y-3">
            {info.campo && (
              <Campo rotulo={info.rotuloCampo} className="max-w-48">
                <Entrada type="number" disabled={!podeEditar} min={info.campo === 'dias' ? 7 : 0} max={info.campo === 'dias' ? 730 : 72}
                  value={f[info.campo] ?? ''} onChange={(e) => setF({ ...f, [info.campo]: e.target.value === '' ? '' : Number(e.target.value) })} />
              </Campo>
            )}
            <AreaTexto ref={area} rows={6} disabled={!podeEditar} value={f.texto} onChange={(e) => setF({ ...f, texto: e.target.value })} />
            {podeEditar && (
              <div className="flex flex-wrap gap-1.5">
                {vars.map((v) => (
                  <button key={v} type="button" onClick={() => inserir(v)} className="rounded-full bg-slate-100 px-2.5 py-1 font-mono text-[11px] text-slate-600 hover:bg-marca-50 hover:text-marca-700">{`{{${v}}}`}</button>
                ))}
              </div>
            )}
            <Alerta>{erro}</Alerta>
            {podeEditar && mudou && (
              <div className="flex gap-2">
                <Botao variante="secundario" onClick={() => setF(modelo)}>Desfazer</Botao>
                <Botao carregando={salvando} onClick={() => salvar()}>Salvar</Botao>
              </div>
            )}
          </div>
          <div className="rounded-2xl bg-[#ECE5DD] p-4">
            <p className="mb-2 text-xs font-medium text-slate-500">Como o paciente vê</p>
            <BalaoWhats texto={renderizar(f.texto, { ...EXEMPLO, empresa: s.empresa.nome })} />
          </div>
        </div>
      )}
    </Cartao>
  )
}

/* ------------------------------------------------------------------ campanhas */
const PUBLICOS = [
  ['todos', 'Todos os pacientes'],
  ['sumidos', 'Quem não vem há um tempo'],
  ['aniversariantes_mes', 'Aniversariantes do mês'],
  ['nunca_vieram', 'Cadastrados que nunca vieram'],
]

function Campanhas({ recursos }) {
  const s = useSessao()
  const avisar = useAviso()
  const [f, setF] = useState({ nome: '', publico: 'sumidos', dias: 60, texto: 'Oi, {{primeiro_nome}}! Aqui é da {{empresa}}. ' })
  const [total, setTotal] = useState(null)
  const [enviando, setEnviando] = useState(false)
  const [erro, setErro] = useState('')
  const { dados: historico, recarregar } = useDados(async () => {
    if (!s.eDono) return []
    return ok(await supabase.from('campanhas').select('*').eq('empresa_id', s.empresa.id).order('criado_em', { ascending: false }).limit(20))
  }, [s.empresa.id, s.eDono])

  useEffect(() => {
    if (!s.eDono || !recursos.campanhas) return
    let ativo = true
    setTotal(null)
    const t = setTimeout(async () => {
      const { data } = await supabase.rpc('contar_publico_campanha', { p_empresa: s.empresa.id, p_publico: f.publico, p_dias: Number(f.dias) || 60 })
      if (ativo) setTotal(data ?? 0)
    }, 300)
    return () => { ativo = false; clearTimeout(t) }
  }, [f.publico, f.dias, s.empresa.id, s.eDono, recursos.campanhas])

  if (!recursos.campanhas) {
    return <Vazio icone={Megaphone} titulo="Campanhas no plano Profissional" texto="Mande uma mensagem para grupos de pacientes: quem sumiu, aniversariantes do mês, todos." />
  }
  if (!s.eDono) return <Vazio icone={Lock} titulo="Só o dono envia campanhas" />

  async function enviar() {
    setErro('')
    if (!window.confirm(`Enviar esta mensagem para ${total} pacientes? Os envios saem aos poucos, cerca de 3 por minuto.`)) return
    setEnviando(true)
    try {
      const n = ok(await supabase.rpc('criar_campanha', { p_empresa: s.empresa.id, p_nome: f.nome, p_publico: f.publico, p_dias: Number(f.dias) || null, p_texto: f.texto }))
      avisar(`${n} mensagens na fila de envio`)
      setF((x) => ({ ...x, nome: '' }))
      recarregar()
    } catch (e) {
      setErro(mensagemErro(e))
    } finally {
      setEnviando(false)
    }
  }

  return (
    <div className="space-y-5">
      <Cartao className="p-5">
        <div className="grid gap-5 lg:grid-cols-2">
          <div className="space-y-4">
            <Campo rotulo="Nome da campanha"><Entrada placeholder="Ex.: Retorno de dezembro" value={f.nome} onChange={(e) => setF({ ...f, nome: e.target.value })} /></Campo>
            <div className="grid grid-cols-2 gap-3">
              <Campo rotulo="Para quem" className={f.publico === 'sumidos' ? '' : 'col-span-2'}>
                <Selecao value={f.publico} onChange={(e) => setF({ ...f, publico: e.target.value })}>
                  {PUBLICOS.map(([k, r]) => <option key={k} value={k}>{r}</option>)}
                </Selecao>
              </Campo>
              {f.publico === 'sumidos' && (
                <Campo rotulo="Sem vir há (dias)"><Entrada type="number" min={7} value={f.dias} onChange={(e) => setF({ ...f, dias: e.target.value })} /></Campo>
              )}
            </div>
            <Campo rotulo="Mensagem">
              <AreaTexto rows={6} value={f.texto} onChange={(e) => setF({ ...f, texto: e.target.value })} />
            </Campo>
            <div className="flex flex-wrap gap-1.5">
              {VARS_CLIENTE.map((v) => (
                <button key={v} type="button" onClick={() => setF({ ...f, texto: `${f.texto}{{${v}}}` })} className="rounded-full bg-slate-100 px-2.5 py-1 font-mono text-[11px] text-slate-600 hover:bg-marca-50">{`{{${v}}}`}</button>
              ))}
            </div>
            <Alerta>{erro}</Alerta>
            <div className="flex flex-wrap items-center gap-3">
              <Botao variante="agua" carregando={enviando} disabled={!total || f.texto.trim().length < 5} onClick={enviar}><Send className="size-4" /> Enviar campanha</Botao>
              <span className="flex items-center gap-1.5 text-sm text-slate-500"><Users className="size-4" /> {total == null ? 'Contando…' : `${total} pacientes`}</span>
            </div>
          </div>
          <div className="rounded-2xl bg-[#ECE5DD] p-4">
            <p className="mb-2 text-xs font-medium text-slate-500">Como o paciente vê</p>
            <BalaoWhats texto={renderizar(f.texto, { ...EXEMPLO, empresa: s.empresa.nome })} />
            <p className="mt-4 text-xs text-slate-500">Dica: mensagens curtas, pessoais e com um convite claro funcionam melhor. Evite mandar campanhas muitas vezes por mês para o número não ser denunciado como spam.</p>
          </div>
        </div>
      </Cartao>
      {historico?.length > 0 && (
        <Cartao className="divide-y divide-slate-100">
          {historico.map((c) => (
            <div key={c.id} className="flex items-center justify-between gap-3 px-4 py-3">
              <div className="min-w-0">
                <p className="truncate text-sm font-medium text-slate-800">{c.nome}</p>
                <p className="text-xs text-slate-500">{dataHora(c.criado_em)} · {PUBLICOS.find(([k]) => k === c.publico)?.[1]}</p>
              </div>
              <Etiqueta className="bg-agua-50 text-agua-700">{c.total} envios</Etiqueta>
            </div>
          ))}
        </Cartao>
      )}
    </div>
  )
}

/* ------------------------------------------------------------------ histórico de mensagens */
const ROTULO_TIPO = {
  confirmacao: 'Confirmação', lembrete: 'Lembrete', pos_atendimento: 'Avaliação', aniversario: 'Aniversário', retorno: 'Retorno',
  resposta_sim: 'Resposta SIM', resposta_nao: 'Resposta NÃO', campanha: 'Campanha', bot: 'Atendimento automático', entrada: 'Recebida',
}
const ST_MSG = {
  pendente: 'bg-slate-100 text-slate-600', enviando: 'bg-amber-100 text-amber-800', enviada: 'bg-emerald-100 text-emerald-700',
  erro: 'bg-red-100 text-red-700', recebida: 'bg-marca-100 text-marca-700',
}

function Historico() {
  const s = useSessao()
  const [filtro, setFiltro] = useState('')
  const { dados, carregando, recarregar } = useDados(async () => {
    let q = supabase.from('mensagens').select('id, tipo, direcao, telefone, texto, status, erro, criado_em, enviada_em, cliente:clientes(id, nome)')
      .eq('empresa_id', s.empresa.id).order('criado_em', { ascending: false }).limit(150)
    if (filtro === 'entrada') q = q.eq('direcao', 'entrada')
    else if (filtro === 'erro') q = q.eq('status', 'erro')
    else if (filtro === 'pendente') q = q.in('status', ['pendente', 'enviando'])
    return ok(await q)
  }, [s.empresa.id, filtro])
  const lista = useMemo(() => dados ?? [], [dados])

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <Selecao className="h-11 w-auto!" value={filtro} onChange={(e) => setFiltro(e.target.value)} aria-label="Filtro">
          <option value="">Todas as mensagens</option>
          <option value="entrada">Recebidas dos pacientes</option>
          <option value="pendente">Na fila</option>
          <option value="erro">Com erro</option>
        </Selecao>
        <button onClick={recarregar} className="rounded-full p-2.5 text-slate-400 hover:bg-slate-100" aria-label="Atualizar"><RefreshCw className="size-4" /></button>
      </div>
      {carregando && !dados ? <Carregando /> : !lista.length ? (
        <Vazio icone={MessageCircle} titulo="Nenhuma mensagem ainda" texto="Assim que o WhatsApp estiver conectado, tudo o que sair e chegar aparece aqui." />
      ) : (
        <Cartao className="divide-y divide-slate-100">
          {lista.map((m) => (
            <div key={m.id} className="flex gap-3 px-4 py-3">
              <span className={cx('mt-0.5 grid size-8 shrink-0 place-items-center rounded-full', m.direcao === 'entrada' ? 'bg-marca-50 text-marca-600' : 'bg-emerald-50 text-emerald-600')}>
                {m.direcao === 'entrada' ? <ArrowDownLeft className="size-4" /> : <ArrowUpRight className="size-4" />}
              </span>
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                  <span className="text-sm font-medium text-slate-800">{m.cliente?.nome ?? telefone(m.telefone)}</span>
                  <span className="text-xs text-slate-400">{ROTULO_TIPO[m.tipo]} · {dataHora(m.criado_em)}</span>
                  {m.direcao === 'saida' && <Etiqueta className={ST_MSG[m.status]}>{m.status}</Etiqueta>}
                </div>
                <p className="mt-0.5 line-clamp-3 whitespace-pre-line text-sm text-slate-600">{m.texto}</p>
                {m.erro && <p className="mt-0.5 text-xs text-red-600">{m.erro}</p>}
              </div>
            </div>
          ))}
        </Cartao>
      )}
    </div>
  )
}

// Sistem Clinic · Edge Function "whatsapp"
// Única ponte entre o sistema e a Evolution API. Três entradas:
//   POST /whatsapp                 → painel (usuário logado): conectar, status, desconectar
//   POST /whatsapp?acao=webhook    → eventos da Evolution API (mensagens recebidas, conexão)
//   POST /whatsapp?acao=ciclo      → agendador (pg_cron, a cada minuto): gera e envia a fila
//
// Segredos (Supabase → Edge Functions → Secrets):
//   EVOLUTION_URL       ex.: https://evolution.seudominio.com.br
//   EVOLUTION_API_KEY   chave global (AUTHENTICATION_API_KEY) da Evolution API
//   EVOLUTION_VERSAO    opcional: "1" se o servidor for da versão 1.x (padrão: 2)
// SUPABASE_URL, SUPABASE_ANON_KEY e SUPABASE_SERVICE_ROLE_KEY já existem nas Edge Functions.
// Publicar com "Verify JWT" DESLIGADO: o webhook e o agendador não mandam login;
// o painel é validado aqui dentro pelo próprio banco (RLS/RPC com o token do usuário).

import { createClient } from 'npm:@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const EVO_URL = (Deno.env.get('EVOLUTION_URL') ?? '').replace(/\/+$/, '')
const EVO_KEY = Deno.env.get('EVOLUTION_API_KEY') ?? ''
const EVO_V1 = Deno.env.get('EVOLUTION_VERSAO') === '1'

const admin = createClient(SUPABASE_URL, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } })

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const resposta = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })
const esperar = (ms: number) => new Promise((r) => setTimeout(r, ms))

// ------------------------------------------------------------------ Evolution API
async function evo(caminho: string, metodo = 'GET', corpo?: unknown) {
  const r = await fetch(EVO_URL + caminho, {
    method: metodo,
    headers: { 'Content-Type': 'application/json', apikey: EVO_KEY },
    body: corpo === undefined ? undefined : JSON.stringify(corpo),
  })
  const texto = await r.text()
  let json: any
  try { json = JSON.parse(texto) } catch { json = { bruto: texto } }
  return { ok: r.ok, status: r.status, json }
}

const EVENTOS = ['MESSAGES_UPSERT', 'CONNECTION_UPDATE', 'QRCODE_UPDATED']

function configWebhook(url: string) {
  return EVO_V1
    ? { url, enabled: true, webhook_by_events: false, webhook_base64: false, events: EVENTOS }
    : { webhook: { enabled: true, url, byEvents: false, base64: false, events: EVENTOS } }
}

async function enviarTexto(instancia: string, numero: string, texto: string) {
  const corpo = EVO_V1
    ? { number: numero, options: { delay: 1200, presence: 'composing' }, textMessage: { text: texto } }
    : { number: numero, text: texto, delay: 1200 }
  const r = await evo(`/message/sendText/${encodeURIComponent(instancia)}`, 'POST', corpo)
  const id = r.json?.key?.id ?? null
  return { ok: r.ok, erro: r.ok ? null : `${r.status} ${JSON.stringify(r.json).slice(0, 300)}`, id }
}

function estadoParaStatus(estado?: string) {
  if (estado === 'open') return 'conectado'
  if (estado === 'connecting') return 'conectando'
  return 'desconectado'
}

async function numeroDaInstancia(nome: string) {
  const r = await evo(`/instance/fetchInstances?instanceName=${encodeURIComponent(nome)}`)
  const item = Array.isArray(r.json) ? r.json[0] : r.json
  const dono = item?.ownerJid ?? item?.owner ?? item?.instance?.owner ?? item?.instance?.wuid ?? ''
  return String(dono).split('@')[0].replace(/\D/g, '') || null
}

// ------------------------------------------------------------------ envio de um lote
async function enviarLote(lista: { id: string; nome_instancia: string; telefone: string; texto: string }[]) {
  let enviadas = 0
  for (const m of lista) {
    try {
      const r = await enviarTexto(m.nome_instancia, m.telefone, m.texto)
      await admin.rpc('whatsapp_resultado_envio', { p_id: m.id, p_ok: r.ok, p_erro: r.erro, p_id_externo: r.id })
      if (r.ok) enviadas++
    } catch (e) {
      await admin.rpc('whatsapp_resultado_envio', { p_id: m.id, p_ok: false, p_erro: String(e) })
    }
    await esperar(1500) // ritmo humano para não bloquear o número
  }
  return enviadas
}

// ------------------------------------------------------------------ painel (usuário logado)
async function painel(req: Request) {
  const auth = req.headers.get('Authorization') ?? ''
  if (!auth.startsWith('Bearer ')) return resposta({ erro: 'Faça login novamente.' }, 401)
  const { acao, unidade_id } = await req.json().catch(() => ({}))
  if (!unidade_id) return resposta({ erro: 'Unidade não informada.' }, 400)

  const usuario = createClient(SUPABASE_URL, ANON, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } })
  const gerir = acao === 'conectar' || acao === 'desconectar'
  const { data, error } = await usuario.rpc('whatsapp_acesso_instancia', { p_unidade: unidade_id, p_gerir: gerir })
  if (error) return resposta({ erro: error.message }, 403)
  const inst = data?.[0]
  if (!inst) return resposta({ status: 'desconectado' })
  if (!EVO_URL || !EVO_KEY) return resposta({ status: inst.status, erro: 'nao_configurado' })

  if (acao === 'desconectar') {
    await evo(`/instance/logout/${encodeURIComponent(inst.nome_instancia)}`, 'DELETE')
    await admin.rpc('whatsapp_atualizar_conexao', { p_instancia: inst.id, p_status: 'desconectado' })
    return resposta({ status: 'desconectado' })
  }

  // situação atual na Evolution
  let estado = await evo(`/instance/connectionState/${encodeURIComponent(inst.nome_instancia)}`)
  const existe = estado.ok

  if (acao === 'conectar') {
    const { data: token } = await admin.rpc('whatsapp_segredo_instancia', { p_instancia: inst.id })
    const urlWebhook = `${SUPABASE_URL}/functions/v1/whatsapp?acao=webhook&token=${token}`
    if (!existe) {
      const criar = await evo('/instance/create', 'POST', {
        instanceName: inst.nome_instancia,
        qrcode: true,
        integration: 'WHATSAPP-BAILEYS',
        ...(EVO_V1 ? { webhook: urlWebhook, webhook_by_events: false, events: EVENTOS } : configWebhook(urlWebhook)),
      })
      if (!criar.ok) return resposta({ erro: `Evolution API recusou a criação (${criar.status}). Confira EVOLUTION_URL e EVOLUTION_API_KEY.` }, 502)
    } else {
      await evo(`/webhook/set/${encodeURIComponent(inst.nome_instancia)}`, 'POST', configWebhook(urlWebhook))
    }
    estado = await evo(`/instance/connectionState/${encodeURIComponent(inst.nome_instancia)}`)
    if ((estado.json?.instance?.state ?? estado.json?.state) === 'open') {
      await admin.rpc('whatsapp_atualizar_conexao', { p_instancia: inst.id, p_status: 'conectado', p_numero: await numeroDaInstancia(inst.nome_instancia) })
      return resposta({ status: 'conectado' })
    }
    const qr = await evo(`/instance/connect/${encodeURIComponent(inst.nome_instancia)}`)
    await admin.rpc('whatsapp_atualizar_conexao', { p_instancia: inst.id, p_status: 'conectando' })
    const base64 = qr.json?.base64 ?? qr.json?.qrcode?.base64 ?? null
    return resposta({ status: 'conectando', qr: base64, codigo: qr.json?.pairingCode ?? null })
  }

  // status
  if (!existe) {
    if (inst.status !== 'desconectado') await admin.rpc('whatsapp_atualizar_conexao', { p_instancia: inst.id, p_status: 'desconectado' })
    return resposta({ status: 'desconectado' })
  }
  const status = estadoParaStatus(estado.json?.instance?.state ?? estado.json?.state)
  const numero = status === 'conectado' ? await numeroDaInstancia(inst.nome_instancia) : null
  await admin.rpc('whatsapp_atualizar_conexao', { p_instancia: inst.id, p_status: status, p_numero: numero })
  return resposta({ status, numero })
}

// ------------------------------------------------------------------ webhook da Evolution
function textoDaMensagem(msg: any): string {
  const m = msg?.message ?? {}
  return (
    m.conversation ?? m.extendedTextMessage?.text ?? m.buttonsResponseMessage?.selectedDisplayText ??
    m.listResponseMessage?.title ?? m.templateButtonReplyMessage?.selectedDisplayText ??
    m.imageMessage?.caption ?? m.videoMessage?.caption ?? ''
  )
}

function telefoneDaMensagem(msg: any): string | null {
  const k = msg?.key ?? {}
  let jid: string = k.remoteJid ?? ''
  if (jid.endsWith('@g.us') || jid === 'status@broadcast') return null
  if (jid.endsWith('@lid')) jid = k.remoteJidAlt ?? k.senderPn ?? msg?.senderPn ?? ''
  const tel = jid.split('@')[0].replace(/\D/g, '')
  return tel.length >= 10 ? tel : null
}

async function webhook(url: URL, req: Request) {
  const token = url.searchParams.get('token') ?? ''
  const { data } = await admin.rpc('whatsapp_instancia_por_token', { p_token: token })
  const inst = data?.[0]
  if (!inst) return resposta({ erro: 'token inválido' }, 401)

  const corpo = await req.json().catch(() => ({}))
  const evento = String(corpo.event ?? '').toLowerCase().replace(/_/g, '.')

  if (evento === 'connection.update') {
    const status = estadoParaStatus(corpo.data?.state)
    const numero = String(corpo.data?.wuid ?? corpo.sender ?? '').split('@')[0] || null
    await admin.rpc('whatsapp_atualizar_conexao', { p_instancia: inst.id, p_status: status, p_numero: status === 'conectado' ? numero : null })
    return resposta({ ok: true })
  }

  if (evento === 'messages.upsert') {
    const lista = Array.isArray(corpo.data) ? corpo.data : (corpo.data?.messages ?? [corpo.data])
    for (const msg of lista) {
      if (!msg || msg.key?.fromMe) continue
      const tel = telefoneDaMensagem(msg)
      const texto = textoDaMensagem(msg)
      if (!tel || !texto) continue
      const { data: respostas, error } = await admin.rpc('whatsapp_processar_entrada', {
        p_instancia: inst.id, p_telefone: tel, p_nome: msg.pushName ?? null, p_texto: texto, p_id_externo: msg.key?.id ?? null,
      })
      if (error) { console.error('processar_entrada', error.message); continue }
      for (const r of respostas ?? []) {
        const env = await enviarTexto(r.nome_instancia, tel, r.texto)
        await admin.rpc('whatsapp_resultado_envio', { p_id: r.id, p_ok: env.ok, p_erro: env.erro, p_id_externo: env.id })
      }
    }
  }
  return resposta({ ok: true })
}

// ------------------------------------------------------------------ agendador (pg_cron)
async function ciclo(req: Request) {
  const { segredo } = await req.json().catch(() => ({}))
  if (!EVO_URL || !EVO_KEY) return resposta({ erro: 'nao_configurado' })
  const { data, error } = await admin.rpc('whatsapp_ciclo', { p_segredo: segredo ?? '', p_limite: 25 })
  if (error) return resposta({ erro: error.message }, 403)
  const enviadas = await enviarLote(data ?? [])
  return resposta({ lote: data?.length ?? 0, enviadas })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  const url = new URL(req.url)
  try {
    const acao = url.searchParams.get('acao')
    if (acao === 'webhook') return await webhook(url, req)
    if (acao === 'ciclo') return await ciclo(req)
    return await painel(req)
  } catch (e) {
    console.error(e)
    return resposta({ erro: String((e as Error)?.message ?? e) }, 500)
  }
})

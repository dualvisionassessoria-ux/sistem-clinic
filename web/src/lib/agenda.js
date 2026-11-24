// Utilitários de data/hora e rótulos da agenda. As datas são tratadas no fuso do navegador
// (a recepção usa o sistema no mesmo fuso da unidade).

export const STATUS_AGENDAMENTO = {
  agendado: { rotulo: 'Agendado', cor: 'bg-marca-100 text-marca-700', ponto: '#2563EB' },
  confirmado: { rotulo: 'Confirmado', cor: 'bg-agua-100 text-agua-700', ponto: '#14B8A6' },
  atendido: { rotulo: 'Atendido', cor: 'bg-emerald-100 text-emerald-700', ponto: '#10B981' },
  faltou: { rotulo: 'Faltou', cor: 'bg-amber-100 text-amber-800', ponto: '#F59E0B' },
  cancelado: { rotulo: 'Cancelado', cor: 'bg-slate-200 text-slate-600', ponto: '#94A3B8' },
}

export const FORMAS_PAGAMENTO = {
  pix: 'Pix',
  dinheiro: 'Dinheiro',
  cartao_credito: 'Cartão de crédito',
  cartao_debito: 'Cartão de débito',
  convenio: 'Convênio',
  outro: 'Outro',
}

export const ORIGENS = { painel: 'Painel', whatsapp: 'WhatsApp', online: 'Online' }

const p2 = (n) => String(n).padStart(2, '0')

/** 'AAAA-MM-DD' no fuso local */
export const isoDia = (d) => `${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())}`

/** Date local a partir de 'AAAA-MM-DD' (+ 'HH:MM' opcional) */
export function deIso(dia, hhmm = '00:00') {
  const [a, m, d] = dia.split('-').map(Number)
  const [h, mi] = hhmm.split(':').map(Number)
  return new Date(a, m - 1, d, h, mi)
}

export function somarDias(d, n) {
  const r = new Date(d)
  r.setDate(r.getDate() + n)
  return r
}

export function inicioDia(d) {
  const r = new Date(d)
  r.setHours(0, 0, 0, 0)
  return r
}

/** Semana começando na segunda-feira */
export function inicioSemana(d) {
  const r = inicioDia(d)
  const dow = r.getDay()
  return somarDias(r, dow === 0 ? -6 : 1 - dow)
}

export const inicioMes = (d) => new Date(d.getFullYear(), d.getMonth(), 1)
export const fimMes = (d) => new Date(d.getFullYear(), d.getMonth() + 1, 1)

export const horaDe = (v) => {
  const d = new Date(v)
  return `${p2(d.getHours())}:${p2(d.getMinutes())}`
}

/** minutos desde 00:00 */
export const minutosDe = (v) => {
  const d = new Date(v)
  return d.getHours() * 60 + d.getMinutes()
}

export const minParaHora = (m) => `${p2(Math.floor(m / 60))}:${p2(m % 60)}`

export const mesmoDia = (a, b) => isoDia(new Date(a)) === isoDia(new Date(b))

const fmtLongo = new Intl.DateTimeFormat('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })
const fmtCurto = new Intl.DateTimeFormat('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit' })
const fmtMes = new Intl.DateTimeFormat('pt-BR', { month: 'long', year: 'numeric' })

const maiuscula = (t) => t.charAt(0).toUpperCase() + t.slice(1)
export const diaLongo = (d) => maiuscula(fmtLongo.format(new Date(d)))
export const diaCurto = (d) => maiuscula(fmtCurto.format(new Date(d)).replace('.', ''))
export const nomeMes = (d) => maiuscula(fmtMes.format(new Date(d)))

export function dataHora(v) {
  const d = new Date(v)
  return `${d.toLocaleDateString('pt-BR')} às ${horaDe(d)}`
}

export function idade(nascimento) {
  if (!nascimento) return null
  const n = deIso(nascimento)
  const h = new Date()
  let i = h.getFullYear() - n.getFullYear()
  if (h.getMonth() < n.getMonth() || (h.getMonth() === n.getMonth() && h.getDate() < n.getDate())) i--
  return i
}

/** Telefone salvo como 5511999998888 → (11) 99999-8888 */
export function telefone(t) {
  if (!t) return ''
  const d = String(t).replace(/\D/g, '').replace(/^55(?=\d{10,11}$)/, '')
  if (d.length === 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`
  if (d.length === 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`
  return t
}

/** Converte "1.234,50" ou "150" em número; NaN se inválido */
export const numeroBR = (v) => Number(String(v ?? '').trim().replace(/\./g, '').replace(',', '.') || 0)
export const paraCampo = (n) => (n == null ? '' : String(Number(n).toFixed(2)).replace('.', ','))

export const iniciais = (nome = '') =>
  nome.trim().split(/\s+/).filter(Boolean).slice(0, 2).map((p) => p[0].toUpperCase()).join('')

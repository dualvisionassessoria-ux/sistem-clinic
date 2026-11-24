export const DIAS = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado']
export const DIAS_CURTOS = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb']

export const PAPEIS = { dono: 'Dono', recepcao: 'Recepção', profissional: 'Profissional' }

export const SEGMENTOS = {
  odontologia: 'Odontologia',
  clinica: 'Clínica',
  estetica: 'Estética',
  salao: 'Salão de beleza',
  outro: 'Outro',
}

export const STATUS_ASSINATURA = {
  teste: { rotulo: 'Em teste', cor: 'bg-agua-100 text-agua-700' },
  ativa: { rotulo: 'Ativa', cor: 'bg-emerald-100 text-emerald-700' },
  inadimplente: { rotulo: 'Inadimplente', cor: 'bg-amber-100 text-amber-800' },
  bloqueada: { rotulo: 'Bloqueada', cor: 'bg-red-100 text-red-700' },
  cancelada: { rotulo: 'Cancelada', cor: 'bg-slate-200 text-slate-600' },
}

const moeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })
export const reais = (v) => moeda.format(Number(v || 0))

export const data = (v) => (v ? new Date(v).toLocaleDateString('pt-BR') : '')

export const hora = (t) => (t ? String(t).slice(0, 5) : '')

export function duracao(min) {
  const m = Number(min || 0)
  if (m < 60) return `${m} min`
  const h = Math.floor(m / 60)
  const r = m % 60
  return r ? `${h}h${String(r).padStart(2, '0')}` : `${h}h`
}

export function diasRestantes(ate) {
  if (!ate) return null
  return Math.ceil((new Date(ate).getTime() - Date.now()) / 86400000)
}

export const limite = (n) => (n == null ? 'Ilimitado' : n)

export const CORES = ['#2563EB', '#14B8A6', '#8B5CF6', '#EC4899', '#F59E0B', '#EF4444', '#10B981', '#0EA5E9', '#64748B']

export function linkWhatsApp(texto, numero = '') {
  return `https://wa.me/${numero}?text=${encodeURIComponent(texto)}`
}

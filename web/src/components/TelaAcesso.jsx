import { Logo } from './ui.jsx'
import { CalendarCheck, MessageCircle, ShieldCheck } from 'lucide-react'

/** Moldura das telas de login/cadastro: painel da marca no computador, cartão simples no celular. */
export default function TelaAcesso({ titulo, subtitulo, children, largo }) {
  return (
    <div className="min-h-full bg-white md:grid md:grid-cols-[1fr_1.1fr]">
      <div className="relative hidden overflow-hidden bg-gradient-to-br from-marca-800 via-marca-700 to-agua-600 p-12 text-white md:flex md:flex-col">
        <Logo claro className="text-xl" />
        <div className="mt-auto max-w-md">
          <h2 className="text-3xl font-bold leading-tight">A agenda da sua clínica organizada, do celular ao consultório.</h2>
          <ul className="mt-8 space-y-4 text-marca-50">
            <li className="flex gap-3"><CalendarCheck className="size-5 shrink-0 text-agua-200" /> Agenda por profissional e unidade</li>
            <li className="flex gap-3"><MessageCircle className="size-5 shrink-0 text-agua-200" /> Confirmação e lembretes automáticos no WhatsApp</li>
            <li className="flex gap-3"><ShieldCheck className="size-5 shrink-0 text-agua-200" /> Dados de cada empresa protegidos e separados</li>
          </ul>
        </div>
        <div className="pointer-events-none absolute -right-24 -top-24 size-80 rounded-full bg-agua-300/20 blur-3xl" />
      </div>
      <div className="flex min-h-full flex-col px-5 py-8 md:justify-center md:px-12">
        <div className={`mx-auto w-full ${largo ? 'max-w-xl' : 'max-w-sm'}`}>
          <div className="mb-8 md:hidden">
            <Logo />
          </div>
          <h1 className="text-2xl font-bold text-slate-900">{titulo}</h1>
          {subtitulo && <p className="mt-1 text-sm text-slate-500">{subtitulo}</p>}
          <div className="mt-6">{children}</div>
        </div>
      </div>
    </div>
  )
}

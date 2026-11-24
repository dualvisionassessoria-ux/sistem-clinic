import { Lock } from 'lucide-react'
import { Botao, Logo } from '../components/ui.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { linkWhatsApp } from '../lib/formato.js'

export default function Suspensa() {
  const s = useSessao()
  const numero = import.meta.env.VITE_SUPORTE_WHATSAPP || ''
  const cancelada = s.empresa?.status_assinatura === 'cancelada'
  return (
    <div className="grid min-h-full place-items-center bg-slate-50 px-5 py-10">
      <div className="w-full max-w-md text-center">
        <Logo className="justify-center" />
        <div className="mt-8 rounded-3xl border border-slate-200 bg-white p-8 shadow-sm">
          <div className="mx-auto grid size-14 place-items-center rounded-2xl bg-red-50 text-red-600">
            <Lock className="size-7" />
          </div>
          <h1 className="mt-4 text-xl font-bold text-slate-900">{cancelada ? 'Assinatura cancelada' : 'Assinatura suspensa'}</h1>
          <p className="mt-2 text-sm text-slate-600">
            O acesso da <strong>{s.empresa?.nome}</strong> está {cancelada ? 'encerrado' : 'temporariamente bloqueado'}. Seus dados continuam guardados com segurança.
            {s.eDono ? ' Fale com a gente para regularizar e liberar o sistema na hora.' : ' Avise o responsável pela empresa.'}
          </p>
          <div className="mt-6 space-y-2">
            {s.eDono && numero.length > 4 && (
              <a href={linkWhatsApp(`Olá! Quero regularizar a assinatura da ${s.empresa?.nome} no Sistem Clinic.`, numero)} target="_blank" rel="noreferrer">
                <Botao variante="agua" className="w-full">Falar no WhatsApp</Botao>
              </a>
            )}
            {s.vinculos.length > 1 && (
              <Botao variante="secundario" className="w-full" onClick={() => { s.setEmpresaId(null); window.location.href = '/escolher-empresa' }}>
                Trocar de empresa
              </Botao>
            )}
            <Botao variante="fantasma" className="w-full" onClick={() => s.sair()}>Sair</Botao>
          </div>
        </div>
      </div>
    </div>
  )
}

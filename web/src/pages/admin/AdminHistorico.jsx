import { History } from 'lucide-react'
import { Cabecalho, Cartao, Carregando, Vazio } from '../../components/ui.jsx'
import { supabase } from '../../lib/supabase.js'
import { ok, useDados } from '../../lib/useDados.js'
import { STATUS_ASSINATURA } from '../../lib/formato.js'

function descrever(h) {
  const d = h.dados || {}
  switch (h.acao) {
    case 'empresa_criada':
      return d.origem === 'admin' ? `Empresa cadastrada pelo painel (plano ${d.plano})` : `Empresa criada pelo site (plano ${d.plano}, teste grátis)`
    case 'status_assinatura':
      return `Assinatura: ${STATUS_ASSINATURA[d.de]?.rotulo ?? d.de} → ${STATUS_ASSINATURA[d.para]?.rotulo ?? d.para}`
    case 'plano_alterado':
      return `Plano alterado para ${d.plano}`
    default:
      return h.acao
  }
}

export default function AdminHistorico() {
  const { dados, carregando } = useDados(async () => ok(await supabase.rpc('admin_historico', { p_limite: 200 })), [])
  if (carregando || !dados) return <Carregando />
  return (
    <div className="space-y-5">
      <Cabecalho titulo="Histórico" subtitulo="Últimas 200 ações importantes na plataforma" />
      {!dados.length ? <Vazio icone={History} titulo="Nada registrado ainda" /> : (
        <Cartao className="divide-y divide-slate-100">
          {dados.map((h) => (
            <div key={h.id} className="flex gap-3 px-4 py-3">
              <span className="mt-1.5 size-2 shrink-0 rounded-full bg-agua-500" />
              <div className="min-w-0 flex-1">
                <p className="text-sm text-slate-800"><strong>{h.empresa_nome ?? 'Empresa removida'}</strong> · {descrever(h)}</p>
                <p className="text-xs text-slate-400">
                  {new Date(h.criado_em).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })}
                  {h.usuario_email && ` · por ${h.usuario_email}`}
                </p>
              </div>
            </div>
          ))}
        </Cartao>
      )}
    </div>
  )
}

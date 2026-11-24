import { useEffect, useState } from 'react'
import { Check, X } from 'lucide-react'
import { Alerta, Botao, Cabecalho, Campo, Cartao, Entrada, Etiqueta, Selecao, useAviso } from '../components/ui.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'
import { SEGMENTOS, STATUS_ASSINATURA, data, diasRestantes, limite, reais } from '../lib/formato.js'

const RECURSOS = [
  ['lembretes_whatsapp', 'Confirmação 24h e lembrete 2h no WhatsApp'],
  ['textos_editaveis', 'Textos das mensagens editáveis'],
  ['financeiro', 'Financeiro por atendimento'],
  ['avaliacao_google', 'Pedido de avaliação no Google'],
  ['campanhas', 'Campanhas de retorno e aniversário'],
  ['relatorios_completos', 'Relatórios por profissional e dashboard completo'],
  ['marcacao_whatsapp', 'Marcação pelo WhatsApp'],
  ['marcacao_ia', 'Atendimento com IA'],
]

export default function MinhaEmpresa() {
  const s = useSessao()
  const avisar = useAviso()
  const e = s.empresa
  const [form, setForm] = useState({ nome: e.nome, segmento: e.segmento, documento: '', telefone: '', logo_url: e.logo_url ?? '' })
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)

  useEffect(() => {
    supabase.from('empresas').select('documento, telefone').eq('id', e.id).single().then(({ data: d }) =>
      setForm((f) => ({ ...f, documento: d?.documento ?? '', telefone: d?.telefone ?? '' })),
    )
  }, [e.id])

  const campo = (k) => (ev) => setForm((f) => ({ ...f, [k]: ev.target.value }))

  async function salvar(ev) {
    ev.preventDefault()
    setErro('')
    setSalvando(true)
    const { error } = await supabase.from('empresas').update({
      nome: form.nome.trim(),
      segmento: form.segmento,
      documento: form.documento || null,
      telefone: form.telefone || null,
      logo_url: form.logo_url || null,
    }).eq('id', e.id)
    setSalvando(false)
    if (error) return setErro(mensagemErro(error))
    avisar('Dados salvos')
    s.recarregar()
  }

  const st = STATUS_ASSINATURA[e.status_assinatura]
  const dias = diasRestantes(e.teste_ate)
  const p = s.plano

  return (
    <div className="space-y-6">
      <Cabecalho titulo="Minha empresa" subtitulo="Dados cadastrais e assinatura" />

      <div className="grid gap-6 lg:grid-cols-[1fr_22rem]">
        <Cartao className="p-5">
          <form onSubmit={salvar} className="space-y-4">
            <Campo rotulo="Nome da empresa"><Entrada required minLength={2} value={form.nome} onChange={campo('nome')} /></Campo>
            <div className="grid gap-4 sm:grid-cols-2">
              <Campo rotulo="Segmento">
                <Selecao value={form.segmento} onChange={campo('segmento')}>
                  {Object.entries(SEGMENTOS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </Selecao>
              </Campo>
              <Campo rotulo="CNPJ ou CPF"><Entrada inputMode="numeric" value={form.documento} onChange={campo('documento')} /></Campo>
            </div>
            <Campo rotulo="Telefone / WhatsApp principal"><Entrada type="tel" value={form.telefone} onChange={campo('telefone')} /></Campo>
            <Campo rotulo="Endereço da logo (URL)" dica="Por enquanto, cole o link de uma imagem. O envio de arquivo chega numa próxima versão.">
              <Entrada type="url" value={form.logo_url} onChange={campo('logo_url')} placeholder="https://…" />
            </Campo>
            <Alerta>{erro}</Alerta>
            <Botao type="submit" carregando={salvando}>Salvar alterações</Botao>
          </form>
        </Cartao>

        <Cartao className="overflow-hidden">
          <div className="bg-gradient-to-br from-marca-700 to-agua-600 p-5 text-white">
            <div className="flex items-center justify-between">
              <p className="text-sm text-marca-100">Seu plano</p>
              <Etiqueta className="bg-white/20 text-white">{st.rotulo}</Etiqueta>
            </div>
            <p className="mt-1 text-2xl font-bold">{p?.nome}</p>
            <p className="text-marca-50">{reais(p?.preco_mensal)}/mês</p>
            {e.status_assinatura === 'teste' && dias != null && (
              <p className="mt-2 text-sm text-agua-100">{dias > 0 ? `Teste grátis até ${data(e.teste_ate)}` : 'Período de teste encerrado'}</p>
            )}
          </div>
          <div className="space-y-3 p-5 text-sm">
            <div className="grid grid-cols-3 gap-2 text-center">
              {[['Unidades', p?.limite_unidades], ['Profissionais', p?.limite_profissionais], ['Usuários', p?.limite_usuarios]].map(([r, v]) => (
                <div key={r} className="rounded-xl bg-slate-50 p-2">
                  <p className="font-bold text-slate-900">{limite(v)}</p>
                  <p className="text-[11px] text-slate-500">{r}</p>
                </div>
              ))}
            </div>
            <ul className="space-y-1.5">
              {RECURSOS.map(([k, r]) => {
                const tem = !!p?.recursos?.[k]
                return (
                  <li key={k} className={`flex gap-2 ${tem ? 'text-slate-700' : 'text-slate-400'}`}>
                    {tem ? <Check className="size-4 shrink-0 text-agua-600" /> : <X className="size-4 shrink-0" />} {r}
                  </li>
                )
              })}
            </ul>
            <p className="pt-2 text-xs text-slate-500">Para mudar de plano, fale com o suporte do Sistem Clinic.</p>
          </div>
        </Cartao>
      </div>
    </div>
  )
}

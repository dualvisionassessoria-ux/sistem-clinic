import { useState } from 'react'
import { Check, X, Pencil } from 'lucide-react'
import { Alerta, Botao, Cabecalho, Campo, Cartao, Carregando, Entrada, Etiqueta, Interruptor, Painel, useAviso } from '../../components/ui.jsx'
import { supabase, mensagemErro } from '../../lib/supabase.js'
import { ok, useDados } from '../../lib/useDados.js'
import { limite, reais } from '../../lib/formato.js'

export const RECURSOS = [
  ['agenda', 'Agenda e bloqueios'],
  ['clientes', 'Cadastro de clientes'],
  ['lembretes_whatsapp', 'Confirmação 24h e lembrete 2h no WhatsApp'],
  ['textos_editaveis', 'Textos das mensagens editáveis'],
  ['financeiro', 'Financeiro por atendimento'],
  ['avaliacao_google', 'Pedido de avaliação no Google'],
  ['campanhas', 'Campanhas de retorno e aniversário'],
  ['relatorios_completos', 'Relatórios e dashboard completo'],
  ['marcacao_whatsapp', 'Marcação pelo WhatsApp (menu)'],
  ['marcacao_ia', 'Marcação pelo WhatsApp com IA'],
]

const numOuNulo = (v) => (v === '' || v == null ? null : Number(v))

export default function AdminPlanos() {
  const avisar = useAviso()
  const [edicao, setEdicao] = useState(null)
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)

  const { dados, carregando, recarregar } = useDados(async () => {
    const [planos, empresas] = await Promise.all([
      supabase.from('planos').select('*').order('ordem'),
      supabase.rpc('admin_listar_empresas'),
    ])
    return { planos: ok(planos), empresas: ok(empresas) }
  }, [])

  function abrir(p) {
    setErro('')
    setEdicao({
      ...p,
      preco: String(p.preco_mensal).replace('.', ','),
      lu: p.limite_unidades ?? '',
      lp: p.limite_profissionais ?? '',
      lus: p.limite_usuarios ?? '',
      recursos: { ...p.recursos },
    })
  }

  async function salvar(e) {
    e.preventDefault()
    setErro('')
    const preco = Number(String(edicao.preco).replace(/\./g, '').replace(',', '.'))
    if (Number.isNaN(preco) || preco < 0) return setErro('Preço inválido.')
    setSalvando(true)
    const { error } = await supabase.from('planos').update({
      nome: edicao.nome.trim(),
      descricao: edicao.descricao || null,
      preco_mensal: preco,
      limite_unidades: numOuNulo(edicao.lu),
      limite_profissionais: numOuNulo(edicao.lp),
      limite_usuarios: numOuNulo(edicao.lus),
      recursos: edicao.recursos,
      ativo: edicao.ativo,
    }).eq('id', edicao.id)
    setSalvando(false)
    if (error) return setErro(mensagemErro(error))
    avisar('Plano atualizado')
    setEdicao(null)
    recarregar()
  }

  if (carregando || !dados) return <Carregando />
  const contagem = (codigo) => dados.empresas.filter((e) => e.plano_codigo === codigo && e.status_assinatura !== 'cancelada').length

  return (
    <div className="space-y-5">
      <Cabecalho titulo="Planos" subtitulo="Preços, limites e recursos de cada plano. Mudanças valem na hora para todas as empresas do plano." />
      <div className="grid gap-4 lg:grid-cols-3">
        {dados.planos.map((p) => (
          <Cartao key={p.id} className={`flex flex-col overflow-hidden ${!p.ativo ? 'opacity-60' : ''}`}>
            <div className="border-b border-slate-100 p-5">
              <div className="flex items-center justify-between">
                <p className="text-lg font-semibold text-slate-900">{p.nome}</p>
                {!p.ativo ? <Etiqueta className="bg-slate-100 text-slate-500">Oculto</Etiqueta> : <Etiqueta className="bg-marca-50 text-marca-700">{contagem(p.codigo)} empresas</Etiqueta>}
              </div>
              <p className="mt-1 text-2xl font-bold text-marca-700">{reais(p.preco_mensal)}<span className="text-sm font-normal text-slate-500">/mês</span></p>
              {p.descricao && <p className="mt-1 text-sm text-slate-500">{p.descricao}</p>}
            </div>
            <div className="grid grid-cols-3 gap-2 p-4 text-center">
              {[['Unidades', p.limite_unidades], ['Profissionais', p.limite_profissionais], ['Usuários', p.limite_usuarios]].map(([r, v]) => (
                <div key={r} className="rounded-xl bg-slate-50 p-2">
                  <p className="font-bold text-slate-900">{limite(v)}</p>
                  <p className="text-[11px] text-slate-500">{r}</p>
                </div>
              ))}
            </div>
            <ul className="flex-1 space-y-1.5 px-5 pb-4 text-sm">
              {RECURSOS.map(([k, r]) => (
                <li key={k} className={`flex gap-2 ${p.recursos?.[k] ? 'text-slate-700' : 'text-slate-300'}`}>
                  {p.recursos?.[k] ? <Check className="size-4 shrink-0 text-agua-600" /> : <X className="size-4 shrink-0" />} {r}
                </li>
              ))}
            </ul>
            <div className="p-4 pt-0">
              <Botao variante="secundario" className="w-full" onClick={() => abrir(p)}><Pencil className="size-4" /> Editar plano</Botao>
            </div>
          </Cartao>
        ))}
      </div>

      <Painel aberto={!!edicao} aoFechar={() => setEdicao(null)} titulo={`Editar ${edicao?.nome ?? ''}`}
        rodape={<Botao className="w-full" form="form-plano" type="submit" carregando={salvando}>Salvar plano</Botao>}>
        {edicao && (
          <form id="form-plano" onSubmit={salvar} className="space-y-4">
            <div className="grid grid-cols-2 gap-3">
              <Campo rotulo="Nome"><Entrada required value={edicao.nome} onChange={(e) => setEdicao((f) => ({ ...f, nome: e.target.value }))} /></Campo>
              <Campo rotulo="Preço mensal (R$)"><Entrada inputMode="decimal" required value={edicao.preco} onChange={(e) => setEdicao((f) => ({ ...f, preco: e.target.value }))} /></Campo>
            </div>
            <Campo rotulo="Descrição curta"><Entrada value={edicao.descricao ?? ''} onChange={(e) => setEdicao((f) => ({ ...f, descricao: e.target.value }))} /></Campo>
            <div>
              <p className="mb-1.5 text-sm font-medium text-slate-700">Limites <span className="font-normal text-slate-400">(vazio = ilimitado)</span></p>
              <div className="grid grid-cols-3 gap-3">
                {[['lu', 'Unidades'], ['lp', 'Profissionais'], ['lus', 'Usuários']].map(([k, r]) => (
                  <Campo key={k} rotulo={<span className="text-xs text-slate-500">{r}</span>}>
                    <Entrada type="number" min={1} value={edicao[k]} placeholder="∞" onChange={(e) => setEdicao((f) => ({ ...f, [k]: e.target.value }))} />
                  </Campo>
                ))}
              </div>
            </div>
            <div>
              <p className="mb-1 text-sm font-medium text-slate-700">Recursos incluídos</p>
              <div className="divide-y divide-slate-100">
                {RECURSOS.map(([k, r]) => (
                  <Interruptor key={k} rotulo={r} ligado={!!edicao.recursos[k]}
                    aoMudar={(v) => setEdicao((f) => ({ ...f, recursos: { ...f.recursos, [k]: v } }))} />
                ))}
              </div>
            </div>
            <div className="border-t border-slate-100 pt-2">
              <Interruptor rotulo="Plano disponível para novas assinaturas" descricao="Desligado: some da página de cadastro, mas quem já tem continua."
                ligado={edicao.ativo} aoMudar={(v) => setEdicao((f) => ({ ...f, ativo: v }))} />
            </div>
            <Alerta tipo="info">Reduzir um limite não apaga nada: empresas acima do novo limite só não conseguem cadastrar mais.</Alerta>
            <Alerta>{erro}</Alerta>
          </form>
        )}
      </Painel>
    </div>
  )
}

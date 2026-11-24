import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { CheckCircle2, Clock, AlertTriangle, Lock, ChevronRight } from 'lucide-react'
import { Botao, Cabecalho, Cartao, Carregando, Etiqueta, cx, useAviso } from '../../components/ui.jsx'
import { supabase, mensagemErro } from '../../lib/supabase.js'
import { ok, useDados } from '../../lib/useDados.js'
import { STATUS_ASSINATURA, data, diasRestantes, linkWhatsApp, reais } from '../../lib/formato.js'

/** Fila de trabalho das assinaturas: o que precisa de ação hoje. */
export default function AdminAssinaturas() {
  const avisar = useAviso()
  const [ocupado, setOcupado] = useState(null)
  const { dados: empresas, carregando, recarregar } = useDados(async () => ok(await supabase.rpc('admin_listar_empresas')), [])

  const grupos = useMemo(() => {
    const es = (empresas ?? []).map((e) => ({ ...e, dias: diasRestantes(e.teste_ate) }))
    return [
      { chave: 'vencidos', titulo: 'Testes vencidos', icone: AlertTriangle, cor: 'text-red-600 bg-red-50',
        texto: 'O teste acabou e a empresa ainda não pagou. Ative, marque como inadimplente ou bloqueie.',
        lista: es.filter((e) => e.status_assinatura === 'teste' && e.dias != null && e.dias <= 0) },
      { chave: 'acabando', titulo: 'Testes terminando (até 3 dias)', icone: Clock, cor: 'text-amber-600 bg-amber-50',
        texto: 'Bom momento para entrar em contato e converter.',
        lista: es.filter((e) => e.status_assinatura === 'teste' && e.dias != null && e.dias > 0 && e.dias <= 3) },
      { chave: 'inadimplentes', titulo: 'Inadimplentes', icone: AlertTriangle, cor: 'text-amber-700 bg-amber-50',
        texto: 'Continuam usando com aviso no topo, até você bloquear.',
        lista: es.filter((e) => e.status_assinatura === 'inadimplente') },
      { chave: 'bloqueadas', titulo: 'Bloqueadas', icone: Lock, cor: 'text-slate-600 bg-slate-100',
        texto: 'Sem acesso. Os dados continuam guardados.',
        lista: es.filter((e) => e.status_assinatura === 'bloqueada') },
      { chave: 'emteste', titulo: 'Demais em teste', icone: Clock, cor: 'text-sky-600 bg-sky-50',
        lista: es.filter((e) => e.status_assinatura === 'teste' && (e.dias == null || e.dias > 3)) },
      { chave: 'ativas', titulo: 'Ativas', icone: CheckCircle2, cor: 'text-agua-600 bg-agua-50',
        lista: es.filter((e) => e.status_assinatura === 'ativa') },
    ]
  }, [empresas])

  async function mudar(e, status, dias) {
    setOcupado(e.id + status)
    const teste = dias ? new Date(Math.max(Date.now(), new Date(e.teste_ate || Date.now()).getTime()) + dias * 864e5).toISOString() : null
    const { error } = await supabase.rpc('definir_status_assinatura', { p_empresa: e.id, p_status: status, p_teste_ate: teste })
    setOcupado(null)
    if (error) return avisar(mensagemErro(error), 'erro')
    avisar(dias ? `Teste estendido por ${dias} dias` : `${e.nome}: ${STATUS_ASSINATURA[status].rotulo.toLowerCase()}`)
    recarregar()
  }

  if (carregando || !empresas) return <Carregando />
  const mrr = empresas.filter((e) => e.status_assinatura === 'ativa').reduce((t, e) => t + Number(e.preco_mensal), 0)
  const emRisco = empresas.filter((e) => e.status_assinatura === 'inadimplente').reduce((t, e) => t + Number(e.preco_mensal), 0)

  const acoes = (e) => {
    const b = (status, rotulo, variante = 'secundario', dias) => (
      <Botao key={rotulo} variante={variante} className="h-8 px-3 text-xs" carregando={ocupado === e.id + status}
        onClick={() => mudar(e, status, dias)}>{rotulo}</Botao>
    )
    const st = e.status_assinatura
    return [
      st !== 'ativa' && b('ativa', 'Ativar', 'agua'),
      st === 'teste' && b('teste', '+7 dias', 'secundario', 7),
      ['teste', 'ativa'].includes(st) && b('inadimplente', 'Inadimplente'),
      st !== 'bloqueada' && st !== 'ativa' && b('bloqueada', 'Bloquear', 'perigo'),
    ].filter(Boolean)
  }

  return (
    <div className="space-y-6">
      <Cabecalho titulo="Assinaturas" subtitulo={`Receita ativa ${reais(mrr)}/mês${emRisco ? ` · ${reais(emRisco)} em atraso` : ''}`} />
      <Cartao className="p-4 text-sm text-slate-600">
        A cobrança automática ainda não está ligada. Por enquanto, confirme os pagamentos e mude o status aqui. Quando o gateway (ex.: Asaas) for integrado, isso passa a acontecer sozinho.
      </Cartao>

      {grupos.filter((g) => g.lista.length).length === 0 && (
        <Cartao className="p-8 text-center text-sm text-slate-500">Nenhuma assinatura ainda.</Cartao>
      )}

      {grupos.filter((g) => g.lista.length).map((g) => (
        <section key={g.chave}>
          <div className="mb-2 flex items-center gap-2">
            <span className={cx('grid size-7 place-items-center rounded-lg', g.cor)}><g.icone className="size-4" /></span>
            <h2 className="font-semibold text-slate-900">{g.titulo}</h2>
            <span className="text-sm text-slate-400">{g.lista.length}</span>
          </div>
          {g.texto && <p className="mb-2 text-sm text-slate-500">{g.texto}</p>}
          <Cartao className="divide-y divide-slate-100">
            {g.lista.map((e) => (
              <div key={e.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
                <Link to={`/admin/empresas?id=${e.id}`} className="min-w-0 flex-1">
                  <p className="flex items-center gap-1 truncate font-medium text-slate-900">{e.nome} <ChevronRight className="size-3.5 text-slate-300" /></p>
                  <p className="truncate text-xs text-slate-500">
                    {e.plano_nome} · {reais(e.preco_mensal)}
                    {e.status_assinatura === 'teste' && e.teste_ate && ` · teste até ${data(e.teste_ate)}`}
                    {e.bloqueada_em && ` · bloqueada em ${data(e.bloqueada_em)}`}
                  </p>
                  {(e.dono_email || e.telefone) && (
                    <p className="truncate text-xs text-slate-400">
                      {e.dono_email}
                      {e.telefone && <> · <a className="text-agua-600" target="_blank" rel="noreferrer" href={linkWhatsApp(`Olá! Aqui é do Sistem Clinic, sobre a assinatura da ${e.nome}.`, e.telefone.replace(/\D/g, '').replace(/^(?!55)/, '55'))}>WhatsApp</a></>}
                    </p>
                  )}
                </Link>
                <Etiqueta className={STATUS_ASSINATURA[e.status_assinatura].cor}>{STATUS_ASSINATURA[e.status_assinatura].rotulo}</Etiqueta>
                <div className="flex w-full flex-wrap gap-1.5 sm:w-auto">{acoes(e)}</div>
              </div>
            ))}
          </Cartao>
        </section>
      ))}
    </div>
  )
}

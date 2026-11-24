import { useMemo, useState } from 'react'
import { Building2, Search, Settings2 } from 'lucide-react'
import { Alerta, Botao, Cabecalho, Campo, Cartao, Carregando, Entrada, Etiqueta, Painel, Selecao, Vazio, cx, useAviso } from '../../components/ui.jsx'
import { supabase, mensagemErro } from '../../lib/supabase.js'
import { ok, useDados } from '../../lib/useDados.js'
import { SEGMENTOS, STATUS_ASSINATURA, data, diasRestantes, reais } from '../../lib/formato.js'

const FILTROS = [['todas', 'Todas'], ['teste', 'Em teste'], ['ativa', 'Ativas'], ['inadimplente', 'Inadimplentes'], ['bloqueada', 'Bloqueadas'], ['cancelada', 'Canceladas']]

export default function AdminEmpresas() {
  const avisar = useAviso()
  const [filtro, setFiltro] = useState('todas')
  const [busca, setBusca] = useState('')
  const [edicao, setEdicao] = useState(null)
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)

  const { dados, carregando, recarregar } = useDados(async () => {
    const [empresas, planos] = await Promise.all([
      supabase.rpc('admin_listar_empresas'),
      supabase.from('planos').select('*').order('ordem'),
    ])
    return { empresas: ok(empresas), planos: ok(planos) }
  }, [])

  const lista = useMemo(() => {
    const termo = busca.toLowerCase()
    return (dados?.empresas ?? []).filter(
      (e) => (filtro === 'todas' || e.status_assinatura === filtro) &&
        (!termo || e.nome.toLowerCase().includes(termo) || (e.dono_email ?? '').includes(termo)),
    )
  }, [dados, filtro, busca])

  const resumo = useMemo(() => {
    const es = dados?.empresas ?? []
    const pagantes = es.filter((e) => e.status_assinatura === 'ativa')
    return {
      total: es.length,
      ativas: pagantes.length,
      teste: es.filter((e) => e.status_assinatura === 'teste').length,
      inadimplentes: es.filter((e) => e.status_assinatura === 'inadimplente').length,
      mrr: pagantes.reduce((s, e) => s + Number(e.preco_mensal), 0),
    }
  }, [dados])

  async function salvar(ev) {
    ev.preventDefault()
    setErro('')
    setSalvando(true)
    try {
      if (edicao.plano_novo !== edicao.plano_codigo) {
        ok(await supabase.rpc('definir_plano_empresa', { p_empresa: edicao.id, p_plano_codigo: edicao.plano_novo }))
      }
      const teste = edicao.status_novo === 'teste' && edicao.teste_novo ? new Date(`${edicao.teste_novo}T23:59:59`).toISOString() : null
      if (edicao.status_novo !== edicao.status_assinatura || teste) {
        ok(await supabase.rpc('definir_status_assinatura', { p_empresa: edicao.id, p_status: edicao.status_novo, p_teste_ate: teste }))
      }
      avisar('Empresa atualizada')
      setEdicao(null)
      recarregar()
    } catch (err) {
      setErro(mensagemErro(err))
    } finally {
      setSalvando(false)
    }
  }

  if (carregando || !dados) return <Carregando />

  return (
    <div className="space-y-5">
      <Cabecalho titulo="Empresas" subtitulo="Painel da plataforma Sistem Clinic" />

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {[
          ['Empresas', resumo.total],
          ['Ativas (pagantes)', resumo.ativas],
          ['Em teste', resumo.teste],
          ['Receita mensal', reais(resumo.mrr)],
        ].map(([r, v]) => (
          <Cartao key={r} className="p-4">
            <p className="text-xl font-bold text-slate-900">{v}</p>
            <p className="text-xs text-slate-500">{r}</p>
          </Cartao>
        ))}
      </div>
      {resumo.inadimplentes > 0 && <Alerta tipo="aviso">{resumo.inadimplentes} empresa(s) inadimplente(s) aguardando ação.</Alerta>}

      <div className="flex flex-col gap-3 md:flex-row md:items-center">
        <div className="relative flex-1">
          <Search className="pointer-events-none absolute left-3.5 top-3.5 size-4 text-slate-400" />
          <Entrada className="pl-10" placeholder="Buscar por nome ou e-mail do dono" value={busca} onChange={(e) => setBusca(e.target.value)} />
        </div>
        <div className="-mx-4 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0">
          {FILTROS.map(([k, v]) => (
            <button key={k} onClick={() => setFiltro(k)}
              className={cx('whitespace-nowrap rounded-full px-3 py-1.5 text-sm', filtro === k ? 'bg-marca-700 text-white' : 'bg-white text-slate-600 border border-slate-200')}>{v}</button>
          ))}
        </div>
      </div>

      {!lista.length ? <Vazio icone={Building2} titulo="Nenhuma empresa encontrada" /> : (
        <Cartao className="divide-y divide-slate-100">
          {lista.map((e) => {
            const st = STATUS_ASSINATURA[e.status_assinatura]
            const dias = diasRestantes(e.teste_ate)
            return (
              <div key={e.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium text-slate-900">{e.nome}</p>
                  <p className="truncate text-xs text-slate-500">
                    {e.dono_email} · {SEGMENTOS[e.segmento]} · desde {data(e.criado_em)}
                  </p>
                  <p className="text-xs text-slate-400">{e.unidades} unid. · {e.profissionais} prof. · {e.usuarios} usuários</p>
                </div>
                <div className="text-right">
                  <p className="text-sm font-medium text-slate-700">{e.plano_nome}</p>
                  <p className="text-xs text-slate-400">{reais(e.preco_mensal)}</p>
                </div>
                <div className="w-28 text-right">
                  <Etiqueta className={st.cor}>{st.rotulo}</Etiqueta>
                  {e.status_assinatura === 'teste' && dias != null && (
                    <p className={cx('mt-0.5 text-[11px]', dias <= 0 ? 'text-red-600' : 'text-slate-400')}>{dias > 0 ? `${dias} dias` : 'teste vencido'}</p>
                  )}
                </div>
                <button aria-label="Gerenciar" className="rounded-full p-2 text-slate-500 hover:bg-slate-100"
                  onClick={() => { setErro(''); setEdicao({ ...e, plano_novo: e.plano_codigo, status_novo: e.status_assinatura, teste_novo: '' }) }}>
                  <Settings2 className="size-5" />
                </button>
              </div>
            )
          })}
        </Cartao>
      )}

      <Painel aberto={!!edicao} aoFechar={() => setEdicao(null)} titulo={edicao?.nome}
        rodape={<Botao className="w-full" form="form-admin" type="submit" carregando={salvando}>Salvar</Botao>}>
        {edicao && (
          <form id="form-admin" onSubmit={salvar} className="space-y-4">
            <p className="text-sm text-slate-500">Dono: {edicao.dono_email}</p>
            <Campo rotulo="Plano">
              <Selecao value={edicao.plano_novo} onChange={(e) => setEdicao((f) => ({ ...f, plano_novo: e.target.value }))}>
                {dados.planos.map((p) => <option key={p.codigo} value={p.codigo}>{p.nome} · {reais(p.preco_mensal)}</option>)}
              </Selecao>
            </Campo>
            <Campo rotulo="Status da assinatura" dica="Bloqueada ou cancelada: a equipe da empresa perde o acesso na hora.">
              <Selecao value={edicao.status_novo} onChange={(e) => setEdicao((f) => ({ ...f, status_novo: e.target.value }))}>
                {Object.entries(STATUS_ASSINATURA).map(([k, v]) => <option key={k} value={k}>{v.rotulo}</option>)}
              </Selecao>
            </Campo>
            {edicao.status_novo === 'teste' && (
              <Campo rotulo="Teste até" dica={edicao.teste_ate ? `Atual: ${data(edicao.teste_ate)}` : undefined}>
                <Entrada type="date" value={edicao.teste_novo} onChange={(e) => setEdicao((f) => ({ ...f, teste_novo: e.target.value }))} />
              </Campo>
            )}
            {['bloqueada', 'cancelada'].includes(edicao.status_novo) && edicao.status_novo !== edicao.status_assinatura && (
              <Alerta tipo="aviso">Ao salvar, {edicao.usuarios} usuário(s) da {edicao.nome} perdem o acesso imediatamente.</Alerta>
            )}
            <Alerta>{erro}</Alerta>
          </form>
        )}
      </Painel>
    </div>
  )
}

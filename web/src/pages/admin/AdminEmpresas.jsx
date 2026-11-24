import { useEffect, useMemo, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { Building2, Search, Settings2, Plus, Eye, Copy, Share2, MapPin, UserRound, Users, Scissors } from 'lucide-react'
import { Alerta, Botao, Cabecalho, Campo, Cartao, Carregando, Entrada, Etiqueta, Painel, Selecao, Vazio, cx, useAviso } from '../../components/ui.jsx'
import { supabase, mensagemErro } from '../../lib/supabase.js'
import { useSessao } from '../../lib/sessao.jsx'
import { ok, useDados } from '../../lib/useDados.js'
import { SEGMENTOS, STATUS_ASSINATURA, data, diasRestantes, linkWhatsApp, reais } from '../../lib/formato.js'

const FILTROS = [['todas', 'Todas'], ['teste', 'Em teste'], ['ativa', 'Ativas'], ['inadimplente', 'Inadimplentes'], ['bloqueada', 'Bloqueadas'], ['cancelada', 'Canceladas']]
const linkConvite = (token) => `${window.location.origin}/convite/${token}`

export default function AdminEmpresas() {
  const s = useSessao()
  const avisar = useAviso()
  const navegar = useNavigate()
  const [params, setParams] = useSearchParams()
  const [filtro, setFiltro] = useState('todas')
  const [busca, setBusca] = useState('')
  const [edicao, setEdicao] = useState(null)
  const [nova, setNova] = useState(null)
  const [conviteGerado, setConviteGerado] = useState(null)
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)

  const { dados, carregando, recarregar } = useDados(async () => {
    const [empresas, planos] = await Promise.all([
      supabase.rpc('admin_listar_empresas'),
      supabase.from('planos').select('*').order('ordem'),
    ])
    return { empresas: ok(empresas), planos: ok(planos) }
  }, [])

  // atalhos vindos da visão geral: ?nova=1 abre o cadastro, ?id= abre a empresa
  useEffect(() => {
    if (!dados) return
    if (params.get('nova')) abrirNova()
    const id = params.get('id')
    if (id) {
      const e = dados.empresas.find((x) => x.id === id)
      if (e) abrirEdicao(e)
    }
    if (params.get('nova') || id) setParams({}, { replace: true })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dados])

  const lista = useMemo(() => {
    const termo = busca.toLowerCase()
    return (dados?.empresas ?? []).filter(
      (e) => (filtro === 'todas' || e.status_assinatura === filtro) &&
        (!termo || e.nome.toLowerCase().includes(termo) || (e.dono_email ?? '').includes(termo) || (e.convite_pendente ?? '').includes(termo)),
    )
  }, [dados, filtro, busca])

  function abrirNova() {
    setErro('')
    setConviteGerado(null)
    setNova({ nome: '', segmento: 'odontologia', plano: 'profissional', email: '', unidade: '', telefone: '', documento: '', status: 'teste', dias: 7 })
  }

  function abrirEdicao(e) {
    setErro('')
    setConviteGerado(null)
    setEdicao({ ...e, plano_novo: e.plano_codigo, status_novo: e.status_assinatura, teste_novo: '', email_convite: e.convite_pendente || '' })
  }

  function verComoCliente(id) {
    s.setEmpresaId(id)
    s.setModo('cliente')
    navegar('/')
  }

  async function copiar(token) {
    try {
      await navigator.clipboard.writeText(linkConvite(token))
      avisar('Link copiado')
    } catch {
      window.prompt('Copie o link:', linkConvite(token))
    }
  }

  async function criar(ev) {
    ev.preventDefault()
    setErro('')
    setSalvando(true)
    const { data: r, error } = await supabase.rpc('admin_criar_empresa', {
      p_nome: nova.nome,
      p_segmento: nova.segmento,
      p_plano_codigo: nova.plano,
      p_email_dono: nova.email || null,
      p_nome_unidade: nova.unidade || null,
      p_telefone: nova.telefone || null,
      p_documento: nova.documento || null,
      p_status: nova.status,
      p_dias_teste: Number(nova.dias) || 7,
    })
    setSalvando(false)
    if (error) return setErro(mensagemErro(error))
    avisar('Empresa criada')
    recarregar()
    const linha = r?.[0]
    if (linha?.token) setConviteGerado({ token: linha.token, email: nova.email, empresa: nova.nome, empresaId: linha.empresa_id })
    else setNova(null)
  }

  async function gerarConvite() {
    setErro('')
    const { data: token, error } = await supabase.rpc('admin_convite_dono', { p_empresa: edicao.id, p_email: edicao.email_convite })
    if (error) return setErro(mensagemErro(error))
    setConviteGerado({ token, email: edicao.email_convite, empresa: edicao.nome })
    recarregar()
  }

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

  const blocoConvite = conviteGerado && (
    <div className="space-y-3 rounded-2xl border border-agua-200 bg-agua-50 p-4">
      <p className="text-sm text-agua-800">
        Link de acesso do dono (<strong>{conviteGerado.email}</strong>), válido por 30 dias. Envie para ele criar a senha:
      </p>
      <p className="break-all rounded-lg bg-white px-3 py-2 font-mono text-xs text-slate-700">{linkConvite(conviteGerado.token)}</p>
      <div className="flex gap-2">
        <Botao type="button" variante="secundario" className="flex-1" onClick={() => copiar(conviteGerado.token)}><Copy className="size-4" /> Copiar</Botao>
        <a className="flex-1" target="_blank" rel="noreferrer"
          href={linkWhatsApp(`Olá! A ${conviteGerado.empresa} já está no Sistem Clinic. Crie sua senha por este link: ${linkConvite(conviteGerado.token)}`)}>
          <Botao type="button" variante="agua" className="w-full"><Share2 className="size-4" /> WhatsApp</Botao>
        </a>
      </div>
    </div>
  )

  if (carregando || !dados) return <Carregando />

  return (
    <div className="space-y-5">
      <Cabecalho titulo="Empresas" subtitulo={`${dados.empresas.length} cadastradas`}
        acao={<Botao onClick={abrirNova}><Plus className="size-4" /> <span className="hidden sm:inline">Nova empresa</span></Botao>} />

      <div className="flex flex-col gap-3 lg:flex-row lg:items-center">
        <div className="relative flex-1">
          <Search className="pointer-events-none absolute left-3.5 top-3.5 size-4 text-slate-400" />
          <Entrada className="pl-10" placeholder="Buscar por nome ou e-mail do dono" value={busca} onChange={(e) => setBusca(e.target.value)} />
        </div>
        <div className="-mx-4 flex gap-1 overflow-x-auto px-4 lg:mx-0 lg:px-0">
          {FILTROS.map(([k, v]) => {
            const n = k === 'todas' ? dados.empresas.length : dados.empresas.filter((e) => e.status_assinatura === k).length
            return (
              <button key={k} onClick={() => setFiltro(k)}
                className={cx('whitespace-nowrap rounded-full px-3 py-1.5 text-sm', filtro === k ? 'bg-marca-700 text-white' : 'border border-slate-200 bg-white text-slate-600')}>
                {v} <span className={filtro === k ? 'text-marca-100' : 'text-slate-400'}>{n}</span>
              </button>
            )
          })}
        </div>
      </div>

      {!lista.length ? (
        <Vazio icone={Building2} titulo={dados.empresas.length ? 'Nenhuma empresa neste filtro' : 'Nenhuma empresa cadastrada'}
          texto={dados.empresas.length ? undefined : 'Cadastre uma empresa aqui ou compartilhe o link de teste grátis (/criar-conta).'}
          acao={!dados.empresas.length && <Botao onClick={abrirNova}><Plus className="size-4" /> Cadastrar empresa</Botao>} />
      ) : (
        <Cartao className="divide-y divide-slate-100">
          {lista.map((e) => {
            const st = STATUS_ASSINATURA[e.status_assinatura]
            const dias = diasRestantes(e.teste_ate)
            return (
              <div key={e.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
                <button onClick={() => abrirEdicao(e)} className="min-w-0 flex-1 text-left">
                  <p className="truncate font-medium text-slate-900">{e.nome}</p>
                  <p className="truncate text-xs text-slate-500">
                    {e.dono_email || (e.convite_pendente ? `convite enviado para ${e.convite_pendente}` : 'sem dono')} · {SEGMENTOS[e.segmento]} · desde {data(e.criado_em)}
                  </p>
                  <p className="text-xs text-slate-400">{e.unidades} unid. · {e.profissionais} prof. · {e.servicos} serv. · {e.usuarios} usuários</p>
                </button>
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
                <div className="flex">
                  <button aria-label="Ver como cliente" title="Ver como cliente" className="rounded-full p-2 text-slate-500 hover:bg-agua-50 hover:text-agua-600" onClick={() => verComoCliente(e.id)}>
                    <Eye className="size-5" />
                  </button>
                  <button aria-label="Gerenciar" title="Gerenciar" className="rounded-full p-2 text-slate-500 hover:bg-slate-100" onClick={() => abrirEdicao(e)}>
                    <Settings2 className="size-5" />
                  </button>
                </div>
              </div>
            )
          })}
        </Cartao>
      )}

      {/* ---- nova empresa */}
      <Painel aberto={!!nova} aoFechar={() => setNova(null)} titulo="Nova empresa"
        rodape={conviteGerado
          ? <Botao className="w-full" variante="secundario" onClick={() => setNova(null)}>Concluir</Botao>
          : <Botao className="w-full" form="form-nova" type="submit" carregando={salvando}>Criar empresa</Botao>}>
        {nova && (conviteGerado ? (
          <div className="space-y-4">
            <Alerta tipo="sucesso">Empresa <strong>{conviteGerado.empresa}</strong> criada.</Alerta>
            {blocoConvite}
            <Botao variante="fantasma" className="w-full" onClick={() => verComoCliente(conviteGerado.empresaId)}><Eye className="size-4" /> Ver como cliente</Botao>
          </div>
        ) : (
          <form id="form-nova" onSubmit={criar} className="space-y-4">
            <Campo rotulo="Nome da empresa"><Entrada required minLength={2} value={nova.nome} onChange={(e) => setNova((f) => ({ ...f, nome: e.target.value }))} /></Campo>
            <div className="grid grid-cols-2 gap-3">
              <Campo rotulo="Segmento">
                <Selecao value={nova.segmento} onChange={(e) => setNova((f) => ({ ...f, segmento: e.target.value }))}>
                  {Object.entries(SEGMENTOS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </Selecao>
              </Campo>
              <Campo rotulo="Plano">
                <Selecao value={nova.plano} onChange={(e) => setNova((f) => ({ ...f, plano: e.target.value }))}>
                  {dados.planos.map((p) => <option key={p.codigo} value={p.codigo}>{p.nome}</option>)}
                </Selecao>
              </Campo>
            </div>
            <Campo rotulo="E-mail do dono" dica="Gera um link para ele criar a senha. Deixe vazio para uma empresa de demonstração.">
              <Entrada type="email" value={nova.email} onChange={(e) => setNova((f) => ({ ...f, email: e.target.value }))} />
            </Campo>
            <div className="grid grid-cols-2 gap-3">
              <Campo rotulo="WhatsApp"><Entrada type="tel" value={nova.telefone} onChange={(e) => setNova((f) => ({ ...f, telefone: e.target.value }))} /></Campo>
              <Campo rotulo="CNPJ/CPF"><Entrada value={nova.documento} onChange={(e) => setNova((f) => ({ ...f, documento: e.target.value }))} /></Campo>
            </div>
            <Campo rotulo="Primeira unidade"><Entrada value={nova.unidade} placeholder="Unidade principal" onChange={(e) => setNova((f) => ({ ...f, unidade: e.target.value }))} /></Campo>
            <div className="grid grid-cols-2 gap-3">
              <Campo rotulo="Status inicial">
                <Selecao value={nova.status} onChange={(e) => setNova((f) => ({ ...f, status: e.target.value }))}>
                  <option value="teste">Em teste</option>
                  <option value="ativa">Ativa</option>
                </Selecao>
              </Campo>
              {nova.status === 'teste' && (
                <Campo rotulo="Dias de teste"><Entrada type="number" min={1} max={90} value={nova.dias} onChange={(e) => setNova((f) => ({ ...f, dias: e.target.value }))} /></Campo>
              )}
            </div>
            <Alerta>{erro}</Alerta>
          </form>
        ))}
      </Painel>

      {/* ---- gerenciar empresa */}
      <Painel aberto={!!edicao} aoFechar={() => setEdicao(null)} titulo={edicao?.nome}
        rodape={<Botao className="w-full" form="form-admin" type="submit" carregando={salvando}>Salvar alterações</Botao>}>
        {edicao && (
          <form id="form-admin" onSubmit={salvar} className="space-y-5">
            <div className="grid grid-cols-4 gap-2 text-center">
              {[[MapPin, edicao.unidades, 'unid.'], [UserRound, edicao.profissionais, 'prof.'], [Scissors, edicao.servicos, 'serv.'], [Users, edicao.usuarios, 'usuários']].map(([I, n, r]) => (
                <div key={r} className="rounded-xl bg-slate-50 p-2">
                  <I className="mx-auto size-4 text-slate-400" />
                  <p className="font-bold text-slate-900">{n}</p>
                  <p className="text-[11px] text-slate-500">{r}</p>
                </div>
              ))}
            </div>
            <div className="text-sm text-slate-600">
              <p>Dono: <strong>{edicao.dono_email || '—'}</strong></p>
              {edicao.documento && <p>Documento: {edicao.documento}</p>}
              {edicao.telefone && <p>Telefone: {edicao.telefone}</p>}
              <p>Cadastrada em {data(edicao.criado_em)}</p>
            </div>
            <Botao type="button" variante="secundario" className="w-full" onClick={() => verComoCliente(edicao.id)}><Eye className="size-4" /> Ver como cliente</Botao>

            <div className="space-y-4 border-t border-slate-100 pt-4">
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
            </div>

            {!edicao.dono_email && (
              <div className="space-y-3 border-t border-slate-100 pt-4">
                <p className="text-sm font-medium text-slate-700">Acesso do dono</p>
                <div className="flex gap-2">
                  <Entrada type="email" placeholder="e-mail do dono" value={edicao.email_convite} onChange={(e) => setEdicao((f) => ({ ...f, email_convite: e.target.value }))} />
                  <Botao type="button" variante="secundario" onClick={gerarConvite} disabled={!edicao.email_convite}>Gerar link</Botao>
                </div>
                {blocoConvite}
              </div>
            )}
            <Alerta>{erro}</Alerta>
          </form>
        )}
      </Painel>
    </div>
  )
}

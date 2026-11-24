import { useState } from 'react'
import { UserPlus, Copy, Share2, Trash2, Pencil, Clock } from 'lucide-react'
import { Alerta, Botao, Cabecalho, Campo, Cartao, Carregando, Entrada, Etiqueta, Interruptor, Marcador, Painel, Selecao, cx, useAviso } from '../components/ui.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'
import { ok, useDados } from '../lib/useDados.js'
import { PAPEIS, data, linkWhatsApp, limite } from '../lib/formato.js'

const DESCRICAO_PAPEL = {
  dono: 'Acesso total: cadastros, equipe, financeiro e configurações.',
  recepcao: 'Agenda e clientes das unidades escolhidas.',
  profissional: 'Vê a própria agenda e os clientes que atende.',
}

const linkConvite = (token) => `${window.location.origin}/convite/${token}`

export default function Equipe() {
  const s = useSessao()
  const avisar = useAviso()
  const empresaId = s.empresa.id
  const [convidando, setConvidando] = useState(null)
  const [editando, setEditando] = useState(null)
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)

  const { dados, carregando, recarregar } = useDados(async () => {
    const [membros, convites, unidades, profissionais] = await Promise.all([
      supabase.from('membros').select('*, perfil:perfis(nome, email, telefone), unidades:membro_unidades(unidade_id)').eq('empresa_id', empresaId).order('criado_em'),
      supabase.from('convites').select('*').eq('empresa_id', empresaId).is('aceito_em', null).order('criado_em', { ascending: false }),
      supabase.from('unidades').select('id, nome').eq('empresa_id', empresaId).eq('ativo', true).order('criado_em'),
      supabase.from('profissionais').select('id, nome, membro_id').eq('empresa_id', empresaId).eq('ativo', true).order('nome'),
    ])
    return { membros: ok(membros), convites: ok(convites), unidades: ok(unidades), profissionais: ok(profissionais) }
  }, [empresaId])

  async function copiar(token) {
    try {
      await navigator.clipboard.writeText(linkConvite(token))
      avisar('Link copiado')
    } catch {
      window.prompt('Copie o link do convite:', linkConvite(token))
    }
  }

  function compartilhar(c) {
    const texto = `Olá! Você foi convidado(a) para a equipe da ${s.empresa.nome} no Sistem Clinic. Acesse para criar sua senha: ${linkConvite(c.token)}`
    if (navigator.share) navigator.share({ title: 'Convite Sistem Clinic', text: texto }).catch(() => {})
    else window.open(linkWhatsApp(texto), '_blank')
  }

  async function enviarConvite(e) {
    e.preventDefault()
    setErro('')
    setSalvando(true)
    const { data: token, error } = await supabase.rpc('convidar_usuario', {
      p_empresa: empresaId,
      p_email: convidando.email,
      p_papel: convidando.papel,
      p_unidade_ids: convidando.todas ? [] : convidando.unidades,
      p_todas_unidades: convidando.papel === 'dono' || convidando.todas,
      p_profissional_id: convidando.papel === 'profissional' && convidando.profissional ? convidando.profissional : null,
    })
    setSalvando(false)
    if (error) return setErro(mensagemErro(error))
    setConvidando(null)
    await recarregar()
    copiar(token)
  }

  async function cancelarConvite(id) {
    const { error } = await supabase.from('convites').delete().eq('id', id)
    if (error) return avisar(mensagemErro(error), 'erro')
    avisar('Convite cancelado')
    recarregar()
  }

  async function salvarMembro(e) {
    e.preventDefault()
    setErro('')
    setSalvando(true)
    try {
      ok(await supabase.from('membros').update({
        papel: editando.papel,
        todas_unidades: editando.papel === 'dono' || editando.todas_unidades,
        ativo: editando.ativo,
      }).eq('id', editando.id))
      ok(await supabase.rpc('definir_unidades_membro', { p_membro: editando.id, p_unidade_ids: editando.unidadesSel }))
      avisar('Acesso atualizado')
      setEditando(null)
      recarregar()
      if (editando.user_id === s.usuario.id) s.recarregar()
    } catch (err) {
      setErro(mensagemErro(err))
    } finally {
      setSalvando(false)
    }
  }

  if (carregando || !dados) return <Carregando />
  const { membros, convites, unidades, profissionais } = dados
  const nomeUnidade = Object.fromEntries(unidades.map((u) => [u.id, u.nome]))
  const ativos = membros.filter((m) => m.ativo).length
  const pendentes = convites.filter((c) => new Date(c.expira_em) > new Date()).length
  const lim = s.plano?.limite_usuarios
  const noLimite = lim != null && ativos + pendentes >= lim

  const unidadesDoMembro = (m) =>
    m.papel === 'dono' || m.todas_unidades ? 'Todas as unidades' : m.unidades.map((u) => nomeUnidade[u.unidade_id]).filter(Boolean).join(', ') || 'Nenhuma unidade'

  const seletorUnidades = (estado, setEstado, chaveTodas, chaveLista) => (
    <div className="space-y-2">
      <Interruptor ligado={estado[chaveTodas]} aoMudar={(v) => setEstado((f) => ({ ...f, [chaveTodas]: v }))} rotulo="Todas as unidades" descricao="Inclui unidades criadas no futuro." />
      {!estado[chaveTodas] && unidades.map((u) => (
        <Marcador key={u.id} rotulo={u.nome} marcado={estado[chaveLista].includes(u.id)}
          aoMudar={(m) => setEstado((f) => ({ ...f, [chaveLista]: m ? [...f[chaveLista], u.id] : f[chaveLista].filter((x) => x !== u.id) }))} />
      ))}
    </div>
  )

  return (
    <div className="space-y-6">
      <Cabecalho
        titulo="Equipe"
        subtitulo={`${ativos + pendentes} de ${limite(lim)} usuários no plano ${s.plano?.nome}`}
        acao={
          <Botao disabled={noLimite} onClick={() => { setErro(''); setConvidando({ email: '', papel: 'recepcao', todas: unidades.length === 1, unidades: [], profissional: '' }) }}>
            <UserPlus className="size-4" /> <span className="hidden sm:inline">Convidar</span>
          </Botao>
        }
      />
      {noLimite && <Alerta tipo="info">Você chegou ao limite de usuários do plano. Desative alguém ou faça upgrade para convidar mais.</Alerta>}

      <Cartao className="divide-y divide-slate-100">
        {membros.map((m) => (
          <div key={m.id} className={cx('flex items-center gap-3 px-4 py-3', !m.ativo && 'opacity-50')}>
            <span className="grid size-10 shrink-0 place-items-center rounded-full bg-marca-100 text-sm font-semibold text-marca-700">
              {(m.perfil?.nome || m.perfil?.email || '?').slice(0, 1).toUpperCase()}
            </span>
            <div className="min-w-0 flex-1">
              <p className="truncate font-medium text-slate-900">
                {m.perfil?.nome || m.perfil?.email}
                {m.user_id === s.usuario.id && <span className="ml-1 text-xs font-normal text-slate-400">(você)</span>}
              </p>
              <p className="truncate text-xs text-slate-500">{m.perfil?.email} · {unidadesDoMembro(m)}</p>
            </div>
            <Etiqueta className={m.papel === 'dono' ? 'bg-marca-100 text-marca-700' : m.papel === 'recepcao' ? 'bg-agua-100 text-agua-700' : 'bg-violet-100 text-violet-700'}>
              {m.ativo ? PAPEIS[m.papel] : 'Inativo'}
            </Etiqueta>
            <button aria-label="Editar acesso" className="rounded-full p-2 text-slate-500 hover:bg-slate-100"
              onClick={() => { setErro(''); setEditando({ ...m, unidadesSel: m.unidades.map((u) => u.unidade_id) }) }}>
              <Pencil className="size-4" />
            </button>
          </div>
        ))}
      </Cartao>

      {convites.length > 0 && (
        <section>
          <h2 className="mb-2 text-sm font-semibold text-slate-700">Convites pendentes</h2>
          <Cartao className="divide-y divide-slate-100">
            {convites.map((c) => {
              const expirado = new Date(c.expira_em) < new Date()
              return (
                <div key={c.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
                  <Clock className="size-5 shrink-0 text-slate-300" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-medium text-slate-800">{c.email}</p>
                    <p className="text-xs text-slate-500">{PAPEIS[c.papel]} · {expirado ? 'expirou' : `válido até ${data(c.expira_em)}`}</p>
                  </div>
                  <div className="flex gap-1">
                    {!expirado && <>
                      <Botao variante="secundario" className="h-9 px-3" onClick={() => copiar(c.token)}><Copy className="size-4" /> <span className="hidden sm:inline">Copiar link</span></Botao>
                      <Botao variante="agua" className="h-9 px-3" onClick={() => compartilhar(c)}><Share2 className="size-4" /> <span className="hidden sm:inline">Enviar</span></Botao>
                    </>}
                    <button aria-label="Cancelar convite" onClick={() => cancelarConvite(c.id)} className="rounded-full p-2 text-slate-400 hover:bg-red-50 hover:text-red-600">
                      <Trash2 className="size-4" />
                    </button>
                  </div>
                </div>
              )
            })}
          </Cartao>
          <p className="mt-2 text-xs text-slate-500">Envie o link pelo WhatsApp. A pessoa cria a senha com o mesmo e-mail do convite.</p>
        </section>
      )}

      {/* ---- convidar */}
      <Painel aberto={!!convidando} aoFechar={() => setConvidando(null)} titulo="Convidar para a equipe"
        rodape={<Botao className="w-full" form="form-convite" type="submit" carregando={salvando}><UserPlus className="size-4" /> Gerar convite</Botao>}>
        {convidando && (
          <form id="form-convite" onSubmit={enviarConvite} className="space-y-5">
            <Campo rotulo="E-mail da pessoa">
              <Entrada type="email" required value={convidando.email} onChange={(e) => setConvidando((f) => ({ ...f, email: e.target.value }))} />
            </Campo>
            <div>
              <p className="mb-2 text-sm font-medium text-slate-700">Papel</p>
              <div className="grid gap-2">
                {Object.entries(PAPEIS).map(([k, v]) => (
                  <label key={k} className={cx('flex cursor-pointer gap-3 rounded-xl border p-3', convidando.papel === k ? 'border-marca-500 bg-marca-50' : 'border-slate-200')}>
                    <input type="radio" name="papel" className="mt-1 accent-marca-700" checked={convidando.papel === k} onChange={() => setConvidando((f) => ({ ...f, papel: k }))} />
                    <span><span className="block text-sm font-medium">{v}</span><span className="block text-xs text-slate-500">{DESCRICAO_PAPEL[k]}</span></span>
                  </label>
                ))}
              </div>
            </div>
            {convidando.papel === 'profissional' && (
              <Campo rotulo="Qual profissional é esta pessoa?" dica="Liga o login à agenda do profissional.">
                <Selecao value={convidando.profissional} onChange={(e) => setConvidando((f) => ({ ...f, profissional: e.target.value }))}>
                  <option value="">Escolha…</option>
                  {profissionais.filter((p) => !p.membro_id).map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
                </Selecao>
              </Campo>
            )}
            {convidando.papel !== 'dono' && (
              <div>
                <p className="mb-2 text-sm font-medium text-slate-700">Unidades que pode acessar</p>
                {seletorUnidades(convidando, setConvidando, 'todas', 'unidades')}
              </div>
            )}
            <Alerta>{erro}</Alerta>
          </form>
        )}
      </Painel>

      {/* ---- editar membro */}
      <Painel aberto={!!editando} aoFechar={() => setEditando(null)} titulo="Editar acesso"
        rodape={<Botao className="w-full" form="form-membro" type="submit" carregando={salvando}>Salvar</Botao>}>
        {editando && (
          <form id="form-membro" onSubmit={salvarMembro} className="space-y-5">
            <div className="rounded-xl bg-slate-50 p-3">
              <p className="font-medium text-slate-900">{editando.perfil?.nome || editando.perfil?.email}</p>
              <p className="text-sm text-slate-500">{editando.perfil?.email}</p>
            </div>
            <Campo rotulo="Papel">
              <Selecao value={editando.papel} onChange={(e) => setEditando((f) => ({ ...f, papel: e.target.value }))}>
                {Object.entries(PAPEIS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </Selecao>
            </Campo>
            {editando.papel !== 'dono' && (
              <div>
                <p className="mb-2 text-sm font-medium text-slate-700">Unidades</p>
                {seletorUnidades(editando, setEditando, 'todas_unidades', 'unidadesSel')}
              </div>
            )}
            <Interruptor ligado={editando.ativo} aoMudar={(v) => setEditando((f) => ({ ...f, ativo: v }))}
              rotulo="Acesso ativo" descricao="Desative para bloquear o login desta pessoa na empresa." />
            <Alerta>{erro}</Alerta>
          </form>
        )}
      </Painel>

    </div>
  )
}

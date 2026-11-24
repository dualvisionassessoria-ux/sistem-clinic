import { useMemo, useState } from 'react'
import { Plus, UserRound, Pencil, X, MapPin, Scissors } from 'lucide-react'
import { Alerta, Botao, Cabecalho, Campo, Cartao, Carregando, Entrada, Etiqueta, Interruptor, Marcador, Painel, Vazio, cx, useAviso } from '../components/ui.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'
import { ok, useDados } from '../lib/useDados.js'
import { CORES, DIAS_CURTOS, hora } from '../lib/formato.js'

const ABAS = [['dados', 'Dados'], ['unidades', 'Unidades e jornada'], ['servicos', 'Serviços']]

export default function Profissionais() {
  const s = useSessao()
  const avisar = useAviso()
  const empresaId = s.empresa.id
  const [edicao, setEdicao] = useState(null)
  const [aba, setAba] = useState('dados')
  const [unidadeJornada, setUnidadeJornada] = useState(null)
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)

  const { dados, carregando, recarregar } = useDados(async () => {
    const [profissionais, unidades, servicos] = await Promise.all([
      supabase.from('profissionais')
        .select('*, unidades:profissional_unidades(unidade_id), jornadas(*), servicos:servico_profissionais(servico_id), membro:membros(id, perfil:perfis(email))')
        .eq('empresa_id', empresaId).order('nome'),
      supabase.from('unidades').select('id, nome, ativo').eq('empresa_id', empresaId).order('criado_em'),
      supabase.from('servicos').select('id, nome, categoria, duracao_min, ativo').eq('empresa_id', empresaId).order('nome'),
    ])
    return { profissionais: ok(profissionais), unidades: ok(unidades), servicos: ok(servicos) }
  }, [empresaId])

  const nomeUnidade = useMemo(() => Object.fromEntries((dados?.unidades ?? []).map((u) => [u.id, u.nome])), [dados])

  function abrir(p) {
    setErro('')
    setAba('dados')
    const base = p ?? { nome: '', especialidade: '', registro: '', telefone: '', email: '', cor_agenda: CORES[0], ativo: true, unidades: [], jornadas: [], servicos: [] }
    const unidadesSel = p ? p.unidades.map((x) => x.unidade_id) : dados.unidades.length === 1 ? [dados.unidades[0].id] : []
    // jornada: { [unidade_id]: { [dia]: [{inicio, fim}] } }
    const jornada = {}
    for (const j of base.jornadas) {
      jornada[j.unidade_id] ??= {}
      ;(jornada[j.unidade_id][j.dia_semana] ??= []).push({ inicio: hora(j.inicio), fim: hora(j.fim) })
    }
    setEdicao({
      ...base,
      unidadesSel,
      servicosSel: base.servicos.map((x) => x.servico_id),
      jornada,
    })
    setUnidadeJornada(unidadesSel[0] ?? null)
  }

  const campo = (k) => (e) => setEdicao((f) => ({ ...f, [k]: e.target.value }))

  function alternar(lista, id, marcado) {
    setEdicao((f) => {
      const atual = new Set(f[lista])
      marcado ? atual.add(id) : atual.delete(id)
      return { ...f, [lista]: [...atual] }
    })
    if (lista === 'unidadesSel' && marcado && !unidadeJornada) setUnidadeJornada(id)
  }

  function mudarJornada(unidade, dia, fn) {
    setEdicao((f) => {
      const j = structuredClone(f.jornada)
      j[unidade] ??= {}
      j[unidade][dia] = fn(j[unidade][dia] ?? [])
      return { ...f, jornada: j }
    })
  }

  function copiarParaSemana(unidade, diaOrigem) {
    setEdicao((f) => {
      const j = structuredClone(f.jornada)
      const origem = j[unidade]?.[diaOrigem] ?? []
      for (let d = 1; d <= 5; d++) j[unidade][d] = structuredClone(origem)
      return { ...f, jornada: j }
    })
  }

  async function salvar(e) {
    e.preventDefault()
    setErro('')
    // validação da jornada
    for (const u of edicao.unidadesSel) {
      for (const [dia, faixas] of Object.entries(edicao.jornada[u] ?? {})) {
        const ordenadas = [...faixas].sort((a, b) => a.inicio.localeCompare(b.inicio))
        for (let i = 0; i < ordenadas.length; i++) {
          if (ordenadas[i].fim <= ordenadas[i].inicio) return setErro(`${nomeUnidade[u]}, ${DIAS_CURTOS[dia]}: o fim precisa ser depois do início.`)
          if (i > 0 && ordenadas[i].inicio < ordenadas[i - 1].fim) return setErro(`${nomeUnidade[u]}, ${DIAS_CURTOS[dia]}: há horários sobrepostos.`)
        }
      }
    }
    setSalvando(true)
    try {
      const registro = {
        empresa_id: empresaId,
        nome: edicao.nome.trim(),
        especialidade: edicao.especialidade || null,
        registro: edicao.registro || null,
        telefone: edicao.telefone || null,
        email: edicao.email || null,
        cor_agenda: edicao.cor_agenda,
        ativo: edicao.ativo,
      }
      const prof = edicao.id
        ? ok(await supabase.from('profissionais').update(registro).eq('id', edicao.id).select().single())
        : ok(await supabase.from('profissionais').insert(registro).select().single())

      const pid = prof.id
      ok(await supabase.from('profissional_unidades').delete().eq('profissional_id', pid))
      ok(await supabase.from('jornadas').delete().eq('profissional_id', pid))
      ok(await supabase.from('servico_profissionais').delete().eq('profissional_id', pid))

      if (edicao.unidadesSel.length) {
        ok(await supabase.from('profissional_unidades').insert(
          edicao.unidadesSel.map((u) => ({ empresa_id: empresaId, profissional_id: pid, unidade_id: u })),
        ))
      }
      const jornadas = edicao.unidadesSel.flatMap((u) =>
        Object.entries(edicao.jornada[u] ?? {}).flatMap(([dia, faixas]) =>
          faixas.map((f) => ({ empresa_id: empresaId, profissional_id: pid, unidade_id: u, dia_semana: Number(dia), inicio: f.inicio, fim: f.fim })),
        ),
      )
      if (jornadas.length) ok(await supabase.from('jornadas').insert(jornadas))
      if (edicao.servicosSel.length) {
        ok(await supabase.from('servico_profissionais').insert(
          edicao.servicosSel.map((sid) => ({ empresa_id: empresaId, servico_id: sid, profissional_id: pid })),
        ))
      }
      avisar(edicao.id ? 'Profissional atualizado' : 'Profissional cadastrado')
      setEdicao(null)
      recarregar()
    } catch (err) {
      setErro(mensagemErro(err))
    } finally {
      setSalvando(false)
    }
  }

  if (carregando || !dados) return <Carregando />
  const { profissionais, unidades, servicos } = dados
  const ativos = profissionais.filter((p) => p.ativo).length
  const limite = s.plano?.limite_profissionais
  const noLimite = limite != null && ativos >= limite

  return (
    <div>
      <Cabecalho
        titulo="Profissionais"
        subtitulo={limite != null ? `${ativos} de ${limite} no plano ${s.plano.nome}` : `${ativos} ativos`}
        acao={s.eDono && (
          <Botao onClick={() => abrir(null)} disabled={noLimite}>
            <Plus className="size-4" /> <span className="hidden sm:inline">Novo profissional</span>
          </Botao>
        )}
      />
      {noLimite && s.eDono && <div className="mb-4"><Alerta tipo="info">Seu plano permite {limite} profissionais ativos. Faça upgrade para cadastrar mais.</Alerta></div>}

      {!profissionais.length ? (
        <Vazio icone={UserRound} titulo="Nenhum profissional ainda" texto="Cadastre quem atende para montar a agenda."
          acao={s.eDono && <Botao onClick={() => abrir(null)}><Plus className="size-4" /> Cadastrar profissional</Botao>} />
      ) : (
        <div className="grid gap-3 md:grid-cols-2">
          {profissionais.map((p) => (
            <Cartao key={p.id} className={cx('p-4', !p.ativo && 'opacity-60')}>
              <div className="flex items-start gap-3">
                <span className="grid size-11 shrink-0 place-items-center rounded-full text-sm font-bold text-white" style={{ background: p.cor_agenda }}>
                  {p.nome.split(' ').map((x) => x[0]).slice(0, 2).join('').toUpperCase()}
                </span>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <h2 className="truncate font-semibold text-slate-900">{p.nome}</h2>
                    {!p.ativo && <Etiqueta className="bg-slate-100 text-slate-500">Inativo</Etiqueta>}
                  </div>
                  <p className="truncate text-sm text-slate-500">{[p.especialidade, p.registro].filter(Boolean).join(' · ') || 'Sem especialidade'}</p>
                  <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-500">
                    <span className="flex items-center gap-1"><MapPin className="size-3.5" />{p.unidades.map((u) => nomeUnidade[u.unidade_id]).filter(Boolean).join(', ') || 'Sem unidade'}</span>
                    <span className="flex items-center gap-1"><Scissors className="size-3.5" />{p.servicos.length} serviços</span>
                    {p.membro?.perfil?.email && <span className="text-agua-600">Tem acesso ao sistema</span>}
                  </div>
                </div>
                {s.eDono && (
                  <button onClick={() => abrir(p)} className="rounded-full p-2 text-slate-500 hover:bg-slate-100" aria-label="Editar"><Pencil className="size-4" /></button>
                )}
              </div>
            </Cartao>
          ))}
        </div>
      )}

      <Painel
        aberto={!!edicao}
        aoFechar={() => setEdicao(null)}
        titulo={edicao?.id ? 'Editar profissional' : 'Novo profissional'}
        rodape={
          <div className="flex gap-2">
            <Botao variante="secundario" className="flex-1" onClick={() => setEdicao(null)}>Cancelar</Botao>
            <Botao className="flex-1" form="form-prof" type="submit" carregando={salvando}>Salvar</Botao>
          </div>
        }
      >
        {edicao && (
          <form id="form-prof" onSubmit={salvar}>
            <div className="sticky -top-4 z-10 -mx-5 mb-4 flex gap-1 overflow-x-auto bg-white px-5 pb-2 pt-1">
              {ABAS.map(([k, v]) => (
                <button key={k} type="button" onClick={() => setAba(k)}
                  className={cx('whitespace-nowrap rounded-full px-3.5 py-1.5 text-sm font-medium', aba === k ? 'bg-marca-700 text-white' : 'bg-slate-100 text-slate-600')}>{v}</button>
              ))}
            </div>

            <div className={aba === 'dados' ? 'space-y-4' : 'hidden'}>
              <Campo rotulo="Nome"><Entrada required minLength={2} value={edicao.nome} onChange={campo('nome')} placeholder="Ex.: Dra. Ana Souza" /></Campo>
              <div className="grid grid-cols-2 gap-3">
                <Campo rotulo="Especialidade"><Entrada value={edicao.especialidade ?? ''} onChange={campo('especialidade')} placeholder="Ortodontia" /></Campo>
                <Campo rotulo="Registro"><Entrada value={edicao.registro ?? ''} onChange={campo('registro')} placeholder="CRO 12345" /></Campo>
              </div>
              <Campo rotulo="Celular"><Entrada type="tel" value={edicao.telefone ?? ''} onChange={campo('telefone')} /></Campo>
              <Campo rotulo="E-mail"><Entrada type="email" value={edicao.email ?? ''} onChange={campo('email')} /></Campo>
              <div>
                <p className="mb-2 text-sm font-medium text-slate-700">Cor na agenda</p>
                <div className="flex flex-wrap gap-2">
                  {CORES.map((c) => (
                    <button key={c} type="button" onClick={() => setEdicao((f) => ({ ...f, cor_agenda: c }))}
                      className={cx('size-9 rounded-full ring-offset-2 transition', edicao.cor_agenda === c && 'ring-2 ring-slate-900')} style={{ background: c }} aria-label={c} />
                  ))}
                </div>
              </div>
              {edicao.id && <Interruptor ligado={edicao.ativo} aoMudar={(v) => setEdicao((f) => ({ ...f, ativo: v }))} rotulo="Profissional ativo" descricao="Inativos não aparecem para agendamento." />}
              {!edicao.id && <p className="text-xs text-slate-500">Para o profissional entrar no sistema e ver a própria agenda, convide-o depois em Equipe.</p>}
            </div>

            <div className={aba === 'unidades' ? 'space-y-4' : 'hidden'}>
              <div>
                <p className="mb-2 text-sm font-medium text-slate-700">Atende em</p>
                <div className="grid gap-2">
                  {unidades.filter((u) => u.ativo).map((u) => (
                    <Marcador key={u.id} rotulo={u.nome} marcado={edicao.unidadesSel.includes(u.id)} aoMudar={(m) => alternar('unidadesSel', u.id, m)} />
                  ))}
                </div>
              </div>
              {edicao.unidadesSel.length > 0 && (
                <div>
                  <p className="mb-2 text-sm font-medium text-slate-700">Jornada de trabalho</p>
                  {edicao.unidadesSel.length > 1 && (
                    <div className="mb-3 flex flex-wrap gap-1">
                      {edicao.unidadesSel.map((u) => (
                        <button key={u} type="button" onClick={() => setUnidadeJornada(u)}
                          className={cx('rounded-lg px-3 py-1 text-sm', unidadeJornada === u ? 'bg-agua-100 font-medium text-agua-700' : 'text-slate-500')}>{nomeUnidade[u]}</button>
                      ))}
                    </div>
                  )}
                  {unidadeJornada && edicao.unidadesSel.includes(unidadeJornada) && (
                    <div className="divide-y divide-slate-100 rounded-xl border border-slate-200">
                      {DIAS_CURTOS.map((rotulo, dia) => {
                        const faixas = edicao.jornada[unidadeJornada]?.[dia] ?? []
                        return (
                          <div key={dia} className="px-3 py-2.5">
                            <div className="flex items-center justify-between">
                              <span className={cx('text-sm font-medium', faixas.length ? 'text-slate-800' : 'text-slate-400')}>{rotulo}</span>
                              <div className="flex items-center gap-3">
                                {dia === 1 && faixas.length > 0 && (
                                  <button type="button" onClick={() => copiarParaSemana(unidadeJornada, 1)} className="text-xs text-marca-700">Copiar para seg–sex</button>
                                )}
                                <button type="button" className="text-xs font-medium text-agua-600"
                                  onClick={() => mudarJornada(unidadeJornada, dia, (l) => [...l, l.length ? { inicio: '14:00', fim: '18:00' } : { inicio: '08:00', fim: '12:00' }])}>
                                  + horário
                                </button>
                              </div>
                            </div>
                            {faixas.map((f, i) => (
                              <div key={i} className="mt-2 flex items-center gap-2">
                                <input type="time" value={f.inicio} className="h-9 min-w-0 flex-1 rounded-lg border border-slate-300 px-2"
                                  onChange={(e) => mudarJornada(unidadeJornada, dia, (l) => l.map((x, k) => (k === i ? { ...x, inicio: e.target.value } : x)))} />
                                <span className="text-slate-400">às</span>
                                <input type="time" value={f.fim} className="h-9 min-w-0 flex-1 rounded-lg border border-slate-300 px-2"
                                  onChange={(e) => mudarJornada(unidadeJornada, dia, (l) => l.map((x, k) => (k === i ? { ...x, fim: e.target.value } : x)))} />
                                <button type="button" aria-label="Remover" className="rounded-full p-1.5 text-slate-400 hover:bg-slate-100"
                                  onClick={() => mudarJornada(unidadeJornada, dia, (l) => l.filter((_, k) => k !== i))}><X className="size-4" /></button>
                              </div>
                            ))}
                          </div>
                        )
                      })}
                    </div>
                  )}
                  <p className="mt-2 text-xs text-slate-500">Use dois horários no mesmo dia para marcar o intervalo de almoço.</p>
                </div>
              )}
            </div>

            <div className={aba === 'servicos' ? 'space-y-2' : 'hidden'}>
              {!servicos.length ? (
                <p className="text-sm text-slate-500">Cadastre serviços primeiro na tela Serviços.</p>
              ) : servicos.filter((sv) => sv.ativo).map((sv) => (
                <Marcador key={sv.id} rotulo={sv.nome} detalhe={sv.categoria} marcado={edicao.servicosSel.includes(sv.id)} aoMudar={(m) => alternar('servicosSel', sv.id, m)} />
              ))}
            </div>

            <div className="mt-4"><Alerta>{erro}</Alerta></div>
          </form>
        )}
      </Painel>
    </div>
  )
}

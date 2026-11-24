import { useMemo, useState } from 'react'
import { Plus, Scissors, Pencil, Clock, MessageCircle, Search } from 'lucide-react'
import { Alerta, AreaTexto, Botao, Cabecalho, Campo, Cartao, Carregando, Entrada, Etiqueta, Interruptor, Marcador, Painel, Vazio, cx, useAviso } from '../components/ui.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'
import { ok, useDados } from '../lib/useDados.js'
import { CORES, duracao, reais } from '../lib/formato.js'

const DURACOES = [15, 20, 30, 40, 45, 60, 75, 90, 120, 150, 180, 240]

export default function Servicos() {
  const s = useSessao()
  const avisar = useAviso()
  const empresaId = s.empresa.id
  const [edicao, setEdicao] = useState(null)
  const [busca, setBusca] = useState('')
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)

  const { dados, carregando, recarregar } = useDados(async () => {
    const [servicos, profissionais] = await Promise.all([
      supabase.from('servicos').select('*, profissionais:servico_profissionais(profissional_id)').eq('empresa_id', empresaId).order('categoria', { nullsFirst: false }).order('nome'),
      supabase.from('profissionais').select('id, nome, cor_agenda, ativo').eq('empresa_id', empresaId).order('nome'),
    ])
    return { servicos: ok(servicos), profissionais: ok(profissionais) }
  }, [empresaId])

  const grupos = useMemo(() => {
    const lista = (dados?.servicos ?? []).filter((sv) => sv.nome.toLowerCase().includes(busca.toLowerCase()))
    const mapa = new Map()
    for (const sv of lista) {
      const cat = sv.categoria || 'Sem categoria'
      if (!mapa.has(cat)) mapa.set(cat, [])
      mapa.get(cat).push(sv)
    }
    return [...mapa.entries()]
  }, [dados, busca])

  const categorias = useMemo(() => [...new Set((dados?.servicos ?? []).map((x) => x.categoria).filter(Boolean))], [dados])

  function abrir(sv) {
    setErro('')
    setEdicao(
      sv
        ? { ...sv, preco: String(sv.preco).replace('.', ','), profsSel: sv.profissionais.map((p) => p.profissional_id) }
        : { nome: '', categoria: '', descricao: '', duracao_min: 30, preco: '', intervalo_apos_min: 0, cor: CORES[1], agendavel_whatsapp: true, ativo: true,
            profsSel: dados.profissionais.filter((p) => p.ativo).map((p) => p.id) },
    )
  }

  const campo = (k) => (e) => setEdicao((f) => ({ ...f, [k]: e.target.value }))

  async function salvar(e) {
    e.preventDefault()
    setErro('')
    const preco = Number(String(edicao.preco || '0').replace(/\./g, '').replace(',', '.'))
    if (Number.isNaN(preco) || preco < 0) return setErro('Preço inválido.')
    setSalvando(true)
    try {
      const registro = {
        empresa_id: empresaId,
        nome: edicao.nome.trim(),
        categoria: edicao.categoria?.trim() || null,
        descricao: edicao.descricao || null,
        duracao_min: Number(edicao.duracao_min),
        preco,
        intervalo_apos_min: Number(edicao.intervalo_apos_min || 0),
        cor: edicao.cor,
        agendavel_whatsapp: edicao.agendavel_whatsapp,
        ativo: edicao.ativo,
      }
      const sv = edicao.id
        ? ok(await supabase.from('servicos').update(registro).eq('id', edicao.id).select().single())
        : ok(await supabase.from('servicos').insert(registro).select().single())
      ok(await supabase.from('servico_profissionais').delete().eq('servico_id', sv.id))
      if (edicao.profsSel.length) {
        ok(await supabase.from('servico_profissionais').insert(
          edicao.profsSel.map((pid) => ({ empresa_id: empresaId, servico_id: sv.id, profissional_id: pid })),
        ))
      }
      avisar(edicao.id ? 'Serviço atualizado' : 'Serviço criado')
      setEdicao(null)
      recarregar()
    } catch (err) {
      setErro(mensagemErro(err))
    } finally {
      setSalvando(false)
    }
  }

  if (carregando || !dados) return <Carregando />
  const nomesProf = Object.fromEntries(dados.profissionais.map((p) => [p.id, p]))

  return (
    <div>
      <Cabecalho
        titulo="Serviços"
        subtitulo={`${dados.servicos.filter((x) => x.ativo).length} ativos`}
        acao={s.eDono && <Botao onClick={() => abrir(null)}><Plus className="size-4" /> <span className="hidden sm:inline">Novo serviço</span></Botao>}
      />

      {dados.servicos.length > 6 && (
        <div className="relative mb-4">
          <Search className="pointer-events-none absolute left-3.5 top-3.5 size-4 text-slate-400" />
          <Entrada className="pl-10" placeholder="Buscar serviço" value={busca} onChange={(e) => setBusca(e.target.value)} />
        </div>
      )}

      {!dados.servicos.length ? (
        <Vazio icone={Scissors} titulo="Nenhum serviço cadastrado" texto="Cadastre o que a empresa oferece, com duração e preço."
          acao={s.eDono && <Botao onClick={() => abrir(null)}><Plus className="size-4" /> Cadastrar serviço</Botao>} />
      ) : (
        <div className="space-y-6">
          {grupos.map(([cat, lista]) => (
            <section key={cat}>
              <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400">{cat}</h2>
              <Cartao className="divide-y divide-slate-100">
                {lista.map((sv) => (
                  <button key={sv.id} disabled={!s.eDono} onClick={() => abrir(sv)}
                    className={cx('flex w-full items-center gap-3 px-4 py-3 text-left', s.eDono && 'hover:bg-slate-50', !sv.ativo && 'opacity-50')}>
                    <span className="h-10 w-1.5 shrink-0 rounded-full" style={{ background: sv.cor || '#CBD5E1' }} />
                    <span className="min-w-0 flex-1">
                      <span className="flex items-center gap-2">
                        <span className="truncate font-medium text-slate-900">{sv.nome}</span>
                        {!sv.ativo && <Etiqueta className="bg-slate-100 text-slate-500">Inativo</Etiqueta>}
                      </span>
                      <span className="flex flex-wrap items-center gap-x-3 text-xs text-slate-500">
                        <span className="flex items-center gap-1"><Clock className="size-3.5" />{duracao(sv.duracao_min)}</span>
                        {sv.agendavel_whatsapp && <span className="flex items-center gap-1 text-agua-600"><MessageCircle className="size-3.5" />WhatsApp</span>}
                        <span className="flex -space-x-1">
                          {sv.profissionais.slice(0, 4).map((p) => nomesProf[p.profissional_id] && (
                            <span key={p.profissional_id} className="size-4 rounded-full ring-2 ring-white" style={{ background: nomesProf[p.profissional_id].cor_agenda }} title={nomesProf[p.profissional_id].nome} />
                          ))}
                        </span>
                      </span>
                    </span>
                    <span className="font-semibold text-slate-800">{reais(sv.preco)}</span>
                    {s.eDono && <Pencil className="size-4 text-slate-300" />}
                  </button>
                ))}
              </Cartao>
            </section>
          ))}
        </div>
      )}

      <Painel
        aberto={!!edicao}
        aoFechar={() => setEdicao(null)}
        titulo={edicao?.id ? 'Editar serviço' : 'Novo serviço'}
        rodape={
          <div className="flex gap-2">
            <Botao variante="secundario" className="flex-1" onClick={() => setEdicao(null)}>Cancelar</Botao>
            <Botao className="flex-1" form="form-servico" type="submit" carregando={salvando}>Salvar</Botao>
          </div>
        }
      >
        {edicao && (
          <form id="form-servico" onSubmit={salvar} className="space-y-4">
            <Campo rotulo="Nome do serviço"><Entrada required minLength={2} value={edicao.nome} onChange={campo('nome')} placeholder="Ex.: Limpeza dental" /></Campo>
            <Campo rotulo="Categoria" dica="Opcional. Agrupa os serviços na lista.">
              <Entrada list="categorias" value={edicao.categoria ?? ''} onChange={campo('categoria')} placeholder="Ex.: Prevenção" />
              <datalist id="categorias">{categorias.map((c) => <option key={c} value={c} />)}</datalist>
            </Campo>
            <div className="grid grid-cols-2 gap-3">
              <Campo rotulo="Duração">
                <select value={edicao.duracao_min} onChange={campo('duracao_min')} className="h-11 w-full rounded-xl border border-slate-300 bg-white px-3">
                  {[...new Set([...DURACOES, Number(edicao.duracao_min)])].sort((a, b) => a - b).map((d) => <option key={d} value={d}>{duracao(d)}</option>)}
                </select>
              </Campo>
              <Campo rotulo="Preço (R$)">
                <Entrada inputMode="decimal" value={edicao.preco} onChange={campo('preco')} placeholder="0,00" />
              </Campo>
            </div>
            <Campo rotulo="Intervalo depois (min)" dica="Tempo para limpeza/preparo antes do próximo cliente.">
              <Entrada type="number" min={0} max={240} step={5} value={edicao.intervalo_apos_min} onChange={campo('intervalo_apos_min')} />
            </Campo>
            <Campo rotulo="Descrição"><AreaTexto rows={2} value={edicao.descricao ?? ''} onChange={campo('descricao')} /></Campo>
            <div>
              <p className="mb-2 text-sm font-medium text-slate-700">Cor</p>
              <div className="flex flex-wrap gap-2">
                {CORES.map((c) => (
                  <button key={c} type="button" onClick={() => setEdicao((f) => ({ ...f, cor: c }))}
                    className={cx('size-8 rounded-full ring-offset-2', edicao.cor === c && 'ring-2 ring-slate-900')} style={{ background: c }} aria-label={c} />
                ))}
              </div>
            </div>
            <div>
              <p className="mb-2 text-sm font-medium text-slate-700">Quem atende</p>
              {!dados.profissionais.length ? <p className="text-sm text-slate-500">Nenhum profissional cadastrado ainda.</p> : (
                <div className="grid gap-2">
                  {dados.profissionais.filter((p) => p.ativo).map((p) => (
                    <Marcador key={p.id} rotulo={p.nome} marcado={edicao.profsSel.includes(p.id)}
                      aoMudar={(m) => setEdicao((f) => ({ ...f, profsSel: m ? [...f.profsSel, p.id] : f.profsSel.filter((x) => x !== p.id) }))} />
                  ))}
                </div>
              )}
            </div>
            <Interruptor ligado={edicao.agendavel_whatsapp} aoMudar={(v) => setEdicao((f) => ({ ...f, agendavel_whatsapp: v }))}
              rotulo="Disponível para marcar pelo WhatsApp" descricao="Aparece no menu de marcação automática (plano Premium)." />
            {edicao.id && <Interruptor ligado={edicao.ativo} aoMudar={(v) => setEdicao((f) => ({ ...f, ativo: v }))} rotulo="Serviço ativo" />}
            <Alerta>{erro}</Alerta>
          </form>
        )}
      </Painel>
    </div>
  )
}

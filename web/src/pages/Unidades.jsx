import { useState } from 'react'
import { MapPin, Plus, Phone, Clock, Star, Pencil } from 'lucide-react'
import { Alerta, Botao, Cabecalho, Campo, Cartao, Carregando, Entrada, Etiqueta, Interruptor, Painel, Vazio, useAviso } from '../components/ui.jsx'
import { useSessao } from '../lib/sessao.jsx'
import { supabase, mensagemErro } from '../lib/supabase.js'
import { ok, useDados } from '../lib/useDados.js'
import { DIAS, DIAS_CURTOS, hora } from '../lib/formato.js'

const UFS = 'AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO'.split(' ')

function horariosVazios() {
  return DIAS.map((_, d) => ({ dia_semana: d, aberto: d >= 1 && d <= 5, abre: '08:00', fecha: d === 6 ? '12:00' : '18:00' }))
}

function resumoHorario(horarios) {
  const porDia = Object.fromEntries(horarios.map((h) => [h.dia_semana, `${hora(h.abre)}–${hora(h.fecha)}`]))
  if (!horarios.length) return 'Sem horário definido'
  // agrupa dias seguidos com o mesmo horário: "Seg–Sex 08:00–18:00 · Sáb 08:00–12:00"
  const partes = []
  let d = 0
  while (d < 7) {
    if (!porDia[d]) { d++; continue }
    let fim = d
    while (fim + 1 < 7 && porDia[fim + 1] === porDia[d]) fim++
    partes.push(`${DIAS_CURTOS[d]}${fim > d ? `–${DIAS_CURTOS[fim]}` : ''} ${porDia[d]}`)
    d = fim + 1
  }
  return partes.join(' · ')
}

export default function Unidades() {
  const s = useSessao()
  const avisar = useAviso()
  const empresaId = s.empresa.id
  const [edicao, setEdicao] = useState(null)
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)

  const { dados: unidades, carregando, recarregar } = useDados(async () =>
    ok(await supabase.from('unidades').select('*, horarios:horarios_unidade(*)').eq('empresa_id', empresaId).order('criado_em')),
  [empresaId])

  function abrir(u) {
    setErro('')
    if (!u) {
      setEdicao({ nome: '', telefone: '', endereco: '', cidade: '', uf: '', link_avaliacao_google: '', ativo: true, horarios: horariosVazios() })
      return
    }
    const horarios = horariosVazios().map((h) => {
      const existente = u.horarios.find((x) => x.dia_semana === h.dia_semana)
      return existente ? { ...h, aberto: true, abre: hora(existente.abre), fecha: hora(existente.fecha) } : { ...h, aberto: false }
    })
    setEdicao({ ...u, horarios })
  }

  const campo = (k) => (e) => setEdicao((f) => ({ ...f, [k]: e.target.value }))
  const mudarHorario = (d, k, v) =>
    setEdicao((f) => ({ ...f, horarios: f.horarios.map((h) => (h.dia_semana === d ? { ...h, [k]: v } : h)) }))

  async function salvar(e) {
    e.preventDefault()
    setErro('')
    const invalido = edicao.horarios.find((h) => h.aberto && h.fecha <= h.abre)
    if (invalido) return setErro(`${DIAS[invalido.dia_semana]}: o horário de fechar precisa ser depois do de abrir.`)
    setSalvando(true)
    try {
      const registro = {
        empresa_id: empresaId,
        nome: edicao.nome.trim(),
        telefone: edicao.telefone || null,
        endereco: edicao.endereco || null,
        cidade: edicao.cidade || null,
        uf: edicao.uf || null,
        link_avaliacao_google: edicao.link_avaliacao_google || null,
        ativo: edicao.ativo,
      }
      const unidade = edicao.id
        ? ok(await supabase.from('unidades').update(registro).eq('id', edicao.id).select().single())
        : ok(await supabase.from('unidades').insert(registro).select().single())

      ok(await supabase.from('horarios_unidade').delete().eq('unidade_id', unidade.id))
      const linhas = edicao.horarios
        .filter((h) => h.aberto)
        .map((h) => ({ empresa_id: empresaId, unidade_id: unidade.id, dia_semana: h.dia_semana, abre: h.abre, fecha: h.fecha }))
      if (linhas.length) ok(await supabase.from('horarios_unidade').insert(linhas))

      avisar(edicao.id ? 'Unidade atualizada' : 'Unidade criada')
      setEdicao(null)
      recarregar()
    } catch (err) {
      setErro(mensagemErro(err))
    } finally {
      setSalvando(false)
    }
  }

  const ativas = unidades?.filter((u) => u.ativo).length ?? 0
  const limite = s.plano?.limite_unidades
  const noLimite = limite != null && ativas >= limite

  return (
    <div>
      <Cabecalho
        titulo="Unidades"
        subtitulo={limite != null ? `${ativas} de ${limite} no plano ${s.plano.nome}` : `${ativas} ativas`}
        acao={s.eDono && (
          <Botao onClick={() => abrir(null)} disabled={noLimite} title={noLimite ? 'Limite do plano atingido' : undefined}>
            <Plus className="size-4" /> <span className="hidden sm:inline">Nova unidade</span>
          </Botao>
        )}
      />
      {noLimite && s.eDono && (
        <div className="mb-4"><Alerta tipo="info">Seu plano permite {limite} {limite === 1 ? 'unidade' : 'unidades'}. Para abrir outra, faça upgrade do plano.</Alerta></div>
      )}

      {carregando ? <Carregando /> : !unidades?.length ? (
        <Vazio icone={MapPin} titulo="Nenhuma unidade visível" texto="Peça ao responsável para liberar o acesso às unidades." />
      ) : (
        <div className="grid gap-3 md:grid-cols-2">
          {unidades.map((u) => (
            <Cartao key={u.id} className="p-4">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <h2 className="truncate font-semibold text-slate-900">{u.nome}</h2>
                    {!u.ativo && <Etiqueta className="bg-slate-100 text-slate-500">Inativa</Etiqueta>}
                  </div>
                  {(u.endereco || u.cidade) && (
                    <p className="mt-0.5 truncate text-sm text-slate-500">{[u.endereco, u.cidade, u.uf].filter(Boolean).join(', ')}</p>
                  )}
                </div>
                {s.eDono && (
                  <button onClick={() => abrir(u)} className="rounded-full p-2 text-slate-500 hover:bg-slate-100" aria-label="Editar">
                    <Pencil className="size-4" />
                  </button>
                )}
              </div>
              <div className="mt-3 space-y-1.5 text-sm text-slate-600">
                {u.telefone && <p className="flex items-center gap-2"><Phone className="size-4 text-slate-400" /> {u.telefone}</p>}
                <p className="flex items-start gap-2"><Clock className="mt-0.5 size-4 shrink-0 text-slate-400" /> <span>{resumoHorario(u.horarios)}</span></p>
                {u.link_avaliacao_google && (
                  <p className="flex items-center gap-2"><Star className="size-4 text-amber-400" /> Link de avaliação configurado</p>
                )}
              </div>
            </Cartao>
          ))}
        </div>
      )}

      <Painel
        aberto={!!edicao}
        aoFechar={() => setEdicao(null)}
        titulo={edicao?.id ? 'Editar unidade' : 'Nova unidade'}
        rodape={
          <div className="flex gap-2">
            <Botao variante="secundario" className="flex-1" onClick={() => setEdicao(null)}>Cancelar</Botao>
            <Botao className="flex-1" form="form-unidade" type="submit" carregando={salvando}>Salvar</Botao>
          </div>
        }
      >
        {edicao && (
          <form id="form-unidade" onSubmit={salvar} className="space-y-4">
            <Campo rotulo="Nome da unidade"><Entrada required minLength={2} value={edicao.nome} onChange={campo('nome')} placeholder="Ex.: Centro" /></Campo>
            <Campo rotulo="Telefone / WhatsApp"><Entrada type="tel" value={edicao.telefone ?? ''} onChange={campo('telefone')} /></Campo>
            <Campo rotulo="Endereço"><Entrada value={edicao.endereco ?? ''} onChange={campo('endereco')} placeholder="Rua, número, bairro" /></Campo>
            <div className="grid grid-cols-[1fr_6rem] gap-3">
              <Campo rotulo="Cidade"><Entrada value={edicao.cidade ?? ''} onChange={campo('cidade')} /></Campo>
              <Campo rotulo="UF">
                <select value={edicao.uf ?? ''} onChange={campo('uf')} className="h-11 w-full rounded-xl border border-slate-300 bg-white px-2">
                  <option value="">–</option>
                  {UFS.map((uf) => <option key={uf}>{uf}</option>)}
                </select>
              </Campo>
            </div>
            <Campo rotulo="Link de avaliação no Google" dica="Usado na mensagem pós-atendimento (planos Profissional e Premium).">
              <Entrada type="url" value={edicao.link_avaliacao_google ?? ''} onChange={campo('link_avaliacao_google')} placeholder="https://g.page/r/..." />
            </Campo>

            <div>
              <p className="mb-2 text-sm font-medium text-slate-700">Horário de funcionamento</p>
              <div className="divide-y divide-slate-100 rounded-xl border border-slate-200">
                {edicao.horarios.map((h) => (
                  <div key={h.dia_semana} className="flex items-center gap-2 px-3 py-2">
                    <label className="flex w-24 shrink-0 items-center gap-2 text-sm">
                      <input type="checkbox" className="size-4 accent-marca-700" checked={h.aberto} onChange={(e) => mudarHorario(h.dia_semana, 'aberto', e.target.checked)} />
                      {DIAS_CURTOS[h.dia_semana]}
                    </label>
                    {h.aberto ? (
                      <div className="flex flex-1 items-center gap-2">
                        <input type="time" value={h.abre} onChange={(e) => mudarHorario(h.dia_semana, 'abre', e.target.value)} className="h-9 min-w-0 flex-1 rounded-lg border border-slate-300 px-2" />
                        <span className="text-slate-400">às</span>
                        <input type="time" value={h.fecha} onChange={(e) => mudarHorario(h.dia_semana, 'fecha', e.target.value)} className="h-9 min-w-0 flex-1 rounded-lg border border-slate-300 px-2" />
                      </div>
                    ) : <span className="text-sm text-slate-400">Fechado</span>}
                  </div>
                ))}
              </div>
            </div>

            {edicao.id && (
              <Interruptor ligado={edicao.ativo} aoMudar={(v) => setEdicao((f) => ({ ...f, ativo: v }))} rotulo="Unidade ativa" descricao="Unidades inativas somem da agenda, mas o histórico fica guardado." />
            )}
            <Alerta>{erro}</Alerta>
          </form>
        )}
      </Painel>
    </div>
  )
}

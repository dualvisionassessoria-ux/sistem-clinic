import { createContext, useCallback, useContext, useEffect, useState } from 'react'
import { X, Loader2, CheckCircle2, AlertCircle } from 'lucide-react'

export function cx(...c) {
  return c.filter(Boolean).join(' ')
}

/* ------------------------------------------------------------------ botões */
const VARIANTES = {
  primario: 'bg-marca-700 text-white hover:bg-marca-800 active:bg-marca-900 shadow-sm',
  secundario: 'bg-white text-slate-700 border border-slate-300 hover:bg-slate-50',
  agua: 'bg-agua-500 text-white hover:bg-agua-600 shadow-sm',
  perigo: 'bg-white text-red-600 border border-red-200 hover:bg-red-50',
  fantasma: 'text-slate-600 hover:bg-slate-100',
}

export function Botao({ variante = 'primario', carregando, className, children, ...props }) {
  return (
    <button
      {...props}
      disabled={props.disabled || carregando}
      className={cx(
        'inline-flex items-center justify-center gap-2 rounded-xl px-4 h-11 text-sm font-semibold transition',
        'disabled:opacity-60 disabled:cursor-not-allowed focus:outline-none focus-visible:ring-2 focus-visible:ring-marca-500 focus-visible:ring-offset-2',
        VARIANTES[variante],
        className,
      )}
    >
      {carregando && <Loader2 className="size-4 animate-spin" />}
      {children}
    </button>
  )
}

/* ------------------------------------------------------------------ campos */
export function Campo({ rotulo, dica, erro, children, className }) {
  return (
    <label className={cx('block', className)}>
      {rotulo && <span className="block text-sm font-medium text-slate-700 mb-1.5">{rotulo}</span>}
      {children}
      {dica && !erro && <span className="block text-xs text-slate-500 mt-1">{dica}</span>}
      {erro && <span className="block text-xs text-red-600 mt-1">{erro}</span>}
    </label>
  )
}

const BASE_INPUT =
  'w-full h-11 rounded-xl border border-slate-300 bg-white px-3.5 text-slate-800 placeholder:text-slate-400 ' +
  'focus:outline-none focus:ring-2 focus:ring-marca-500/40 focus:border-marca-500 disabled:bg-slate-100'

export function Entrada({ className, ...props }) {
  return <input {...props} className={cx(BASE_INPUT, className)} />
}

export function Selecao({ className, children, ...props }) {
  return (
    <select {...props} className={cx(BASE_INPUT, 'pr-8', className)}>
      {children}
    </select>
  )
}

export function AreaTexto({ className, ...props }) {
  return <textarea {...props} className={cx(BASE_INPUT, 'h-auto py-2.5 min-h-20', className)} />
}

export function Interruptor({ ligado, aoMudar, rotulo, descricao, disabled }) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={() => aoMudar(!ligado)}
      className="flex w-full items-center justify-between gap-4 py-2 text-left disabled:opacity-60"
    >
      <span>
        <span className="block text-sm font-medium text-slate-700">{rotulo}</span>
        {descricao && <span className="block text-xs text-slate-500">{descricao}</span>}
      </span>
      <span
        className={cx(
          'relative inline-flex h-6 w-11 shrink-0 rounded-full transition',
          ligado ? 'bg-agua-500' : 'bg-slate-300',
        )}
      >
        <span
          className={cx(
            'absolute top-0.5 size-5 rounded-full bg-white shadow transition',
            ligado ? 'left-5.5' : 'left-0.5',
          )}
        />
      </span>
    </button>
  )
}

export function Marcador({ marcado, aoMudar, rotulo, detalhe, disabled }) {
  return (
    <label className={cx('flex items-center gap-3 rounded-xl border px-3 py-2.5 cursor-pointer transition',
      marcado ? 'border-marca-500 bg-marca-50' : 'border-slate-200 bg-white hover:bg-slate-50',
      disabled && 'opacity-60 cursor-not-allowed')}>
      <input
        type="checkbox"
        className="size-4 accent-marca-700"
        checked={!!marcado}
        disabled={disabled}
        onChange={(e) => aoMudar(e.target.checked)}
      />
      <span className="min-w-0">
        <span className="block text-sm text-slate-800 truncate">{rotulo}</span>
        {detalhe && <span className="block text-xs text-slate-500 truncate">{detalhe}</span>}
      </span>
    </label>
  )
}

/* ------------------------------------------------------------------ layout */
export function Cartao({ className, children, ...props }) {
  return (
    <div {...props} className={cx('rounded-2xl border border-slate-200 bg-white shadow-sm', className)}>
      {children}
    </div>
  )
}

export function Cabecalho({ titulo, subtitulo, acao }) {
  return (
    <div className="flex items-start justify-between gap-3 mb-5">
      <div className="min-w-0">
        <h1 className="text-xl md:text-2xl font-bold text-slate-900">{titulo}</h1>
        {subtitulo && <p className="text-sm text-slate-500 mt-0.5">{subtitulo}</p>}
      </div>
      {acao}
    </div>
  )
}

export function Etiqueta({ className, children }) {
  return (
    <span className={cx('inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium', className)}>
      {children}
    </span>
  )
}

export function Vazio({ icone: Icone, titulo, texto, acao }) {
  return (
    <Cartao className="p-8 text-center">
      {Icone && (
        <div className="mx-auto mb-3 grid size-12 place-items-center rounded-2xl bg-agua-50 text-agua-600">
          <Icone className="size-6" />
        </div>
      )}
      <p className="font-semibold text-slate-800">{titulo}</p>
      {texto && <p className="text-sm text-slate-500 mt-1">{texto}</p>}
      {acao && <div className="mt-4">{acao}</div>}
    </Cartao>
  )
}

export function Carregando({ texto = 'Carregando…' }) {
  return (
    <div className="flex items-center justify-center gap-2 py-16 text-slate-500">
      <Loader2 className="size-5 animate-spin" /> {texto}
    </div>
  )
}

export function Alerta({ tipo = 'erro', children }) {
  const estilos = {
    erro: 'bg-red-50 text-red-700 border-red-200',
    aviso: 'bg-amber-50 text-amber-800 border-amber-200',
    info: 'bg-marca-50 text-marca-800 border-marca-200',
    sucesso: 'bg-agua-50 text-agua-700 border-agua-200',
  }
  if (!children) return null
  return <div className={cx('rounded-xl border px-3.5 py-2.5 text-sm', estilos[tipo])}>{children}</div>
}

/* ------------------------------------------------------------------ painel lateral / folha inferior */
export function Painel({ aberto, aoFechar, titulo, children, rodape }) {
  useEffect(() => {
    if (!aberto) return
    const esc = (e) => e.key === 'Escape' && aoFechar()
    document.addEventListener('keydown', esc)
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', esc)
      document.body.style.overflow = ''
    }
  }, [aberto, aoFechar])

  if (!aberto) return null
  return (
    <div className="fixed inset-0 z-50 flex items-end md:items-stretch md:justify-end">
      <div className="absolute inset-0 bg-slate-900/40" onClick={aoFechar} />
      <div
        role="dialog"
        aria-modal="true"
        className="relative flex max-h-[92dvh] w-full flex-col rounded-t-3xl bg-white shadow-xl md:max-h-none md:h-full md:max-w-lg md:rounded-none md:rounded-l-3xl"
      >
        <div className="flex items-center justify-between border-b border-slate-100 px-5 py-4">
          <h2 className="text-lg font-semibold text-slate-900">{titulo}</h2>
          <button onClick={aoFechar} className="rounded-full p-2 text-slate-500 hover:bg-slate-100" aria-label="Fechar">
            <X className="size-5" />
          </button>
        </div>
        <div className="flex-1 overflow-y-auto px-5 py-4">{children}</div>
        {rodape && <div className="border-t border-slate-100 px-5 py-3 pb-safe">{rodape}</div>}
      </div>
    </div>
  )
}

/* ------------------------------------------------------------------ avisos (toast) */
const AvisoCtx = createContext(() => {})
export const useAviso = () => useContext(AvisoCtx)

export function ProvedorAvisos({ children }) {
  const [itens, setItens] = useState([])
  const avisar = useCallback((texto, tipo = 'sucesso') => {
    const id = Math.random()
    setItens((l) => [...l, { id, texto, tipo }])
    setTimeout(() => setItens((l) => l.filter((i) => i.id !== id)), 3500)
  }, [])
  return (
    <AvisoCtx.Provider value={avisar}>
      {children}
      <div className="pointer-events-none fixed inset-x-0 top-3 z-[60] flex flex-col items-center gap-2 px-4">
        {itens.map((i) => (
          <div
            key={i.id}
            className={cx(
              'pointer-events-auto flex max-w-md items-center gap-2 rounded-xl px-4 py-3 text-sm font-medium shadow-lg',
              i.tipo === 'erro' ? 'bg-red-600 text-white' : 'bg-slate-900 text-white',
            )}
          >
            {i.tipo === 'erro' ? <AlertCircle className="size-4" /> : <CheckCircle2 className="size-4 text-agua-300" />}
            {i.texto}
          </div>
        ))}
      </div>
    </AvisoCtx.Provider>
  )
}

/* ------------------------------------------------------------------ logo */
export function Logo({ className, claro }) {
  return (
    <span className={cx('inline-flex items-center gap-2 font-bold tracking-tight', className)}>
      <svg viewBox="0 0 64 64" className="size-8 shrink-0" aria-hidden="true">
        <rect width="64" height="64" rx="16" fill={claro ? '#ffffff' : '#1D4ED8'} />
        <path d="M32 16v32M16 32h32" stroke={claro ? '#14B8A6' : '#5EEAD4'} strokeWidth="8" strokeLinecap="round" />
      </svg>
      <span className={claro ? 'text-white' : 'text-slate-900'}>
        Sistem <span className={claro ? 'text-agua-200' : 'text-agua-600'}>Clinic</span>
      </span>
    </span>
  )
}

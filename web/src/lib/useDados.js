import { useCallback, useEffect, useState } from 'react'

/** Executa uma função de carga e expõe { dados, carregando, erro, recarregar }. */
export function useDados(carga, deps = []) {
  const [estado, setEstado] = useState({ dados: null, carregando: true, erro: null })
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const executar = useCallback(carga, deps)
  const recarregar = useCallback(async () => {
    setEstado((e) => ({ ...e, carregando: true }))
    try {
      const dados = await executar()
      setEstado({ dados, carregando: false, erro: null })
    } catch (erro) {
      setEstado({ dados: null, carregando: false, erro })
    }
  }, [executar])
  useEffect(() => { recarregar() }, [recarregar])
  return { ...estado, recarregar }
}

/** Lança o erro do Supabase, se houver, e devolve os dados. */
export function ok({ data, error }) {
  if (error) throw error
  return data
}

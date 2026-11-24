import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { supabase } from './supabase'

const SessaoCtx = createContext(null)
export const useSessao = () => useContext(SessaoCtx)

const CHAVE_EMPRESA = 'sc_empresa_atual'
export const CHAVE_CONVITE = 'sc_convite_pendente'

function ler(chave) {
  try { return localStorage.getItem(chave) } catch { return null }
}
function gravar(chave, valor) {
  try { valor == null ? localStorage.removeItem(chave) : localStorage.setItem(chave, valor) } catch { /* sem storage */ }
}

/**
 * Guarda a sessão do Supabase, o perfil, os vínculos com empresas e a
 * empresa aberta no momento. Também conclui ações que ficaram pendentes
 * enquanto o usuário confirmava o e-mail (criar empresa / aceitar convite).
 */
export function ProvedorSessao({ children }) {
  const [sessao, setSessao] = useState(undefined) // undefined = carregando
  const [recuperandoSenha, setRecuperandoSenha] = useState(false)
  const [vinculos, setVinculos] = useState(null)
  const [superAdmin, setSuperAdmin] = useState(false)
  const [empresaId, setEmpresaIdEstado] = useState(() => ler(CHAVE_EMPRESA))
  const [perfil, setPerfil] = useState(null)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSessao(data.session ?? null))
    const { data } = supabase.auth.onAuthStateChange((evento, s) => {
      if (evento === 'PASSWORD_RECOVERY') setRecuperandoSenha(true)
      setSessao(s ?? null)
    })
    return () => data.subscription.unsubscribe()
  }, [])

  const usuario = sessao?.user ?? null

  const carregar = useCallback(async () => {
    if (!usuario) {
      setVinculos(null)
      setPerfil(null)
      setSuperAdmin(false)
      return
    }

    // 1) pendências de cadastro (feitas antes da confirmação do e-mail)
    const pendente = usuario.user_metadata?.empresa_pendente
    const convite = ler(CHAVE_CONVITE)
    if (convite) {
      const { error } = await supabase.rpc('aceitar_convite', { p_token: convite })
      if (!error) gravar(CHAVE_CONVITE, null)
    }

    const consultar = () =>
      supabase
        .from('membros')
        .select(
          'id, papel, todas_unidades, empresa:empresas(id, nome, segmento, status_assinatura, teste_ate, logo_url, cor_marca, plano:planos(*))',
        )
        .eq('user_id', usuario.id)
        .eq('ativo', true)

    let { data: lista } = await consultar()

    if (pendente && (!lista || lista.length === 0)) {
      const { data: novaId, error } = await supabase.rpc('criar_empresa', {
        p_nome: pendente.nome,
        p_segmento: pendente.segmento,
        p_plano_codigo: pendente.plano,
        p_nome_unidade: pendente.unidade || null,
        p_telefone: pendente.telefone || null,
      })
      if (!error) {
        await supabase.auth.updateUser({ data: { empresa_pendente: null } })
        gravar(CHAVE_EMPRESA, novaId)
        setEmpresaIdEstado(novaId)
        ;({ data: lista } = await consultar())
      }
    } else if (pendente) {
      await supabase.auth.updateUser({ data: { empresa_pendente: null } })
    }

    const [{ data: adm }, { data: pf }] = await Promise.all([
      supabase.rpc('sou_super_admin'),
      supabase.from('perfis').select('*').eq('id', usuario.id).maybeSingle(),
    ])
    setSuperAdmin(!!adm)
    setPerfil(pf)
    setVinculos((lista ?? []).filter((v) => v.empresa))
  }, [usuario])

  useEffect(() => {
    if (sessao !== undefined) carregar()
  }, [sessao, carregar])

  const setEmpresaId = useCallback((id) => {
    gravar(CHAVE_EMPRESA, id)
    setEmpresaIdEstado(id)
  }, [])

  // empresa atual: a escolhida, ou a única que o usuário tem
  const vinculo = useMemo(() => {
    if (!vinculos?.length) return null
    return vinculos.find((v) => v.empresa.id === empresaId) ?? (vinculos.length === 1 ? vinculos[0] : null)
  }, [vinculos, empresaId])

  const sair = useCallback(async () => {
    await supabase.auth.signOut()
    gravar(CHAVE_EMPRESA, null)
    setEmpresaIdEstado(null)
  }, [])

  const valor = {
    carregando: sessao === undefined || (usuario && vinculos === null),
    sessao,
    usuario,
    perfil,
    superAdmin,
    vinculos: vinculos ?? [],
    vinculo,
    empresa: vinculo?.empresa ?? null,
    plano: vinculo?.empresa?.plano ?? null,
    papel: vinculo?.papel ?? null,
    eDono: vinculo?.papel === 'dono' || superAdmin,
    setEmpresaId,
    recarregar: carregar,
    recuperandoSenha,
    setRecuperandoSenha,
    sair,
  }
  return <SessaoCtx.Provider value={valor}>{children}</SessaoCtx.Provider>
}

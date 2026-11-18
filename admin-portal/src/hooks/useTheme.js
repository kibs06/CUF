import { useCallback, useEffect, useState } from 'react'

// The profile menu's dark-mode switch. A choice is remembered in localStorage;
// no choice means "follow the OS", which also means the portal flips at dusk
// without the admin touching anything.
const KEY = 'cufmai-admin-theme'

const systemDark = () =>
  typeof window !== 'undefined' &&
  !!window.matchMedia?.('(prefers-color-scheme: dark)').matches

function readChoice() {
  try {
    const stored = localStorage.getItem(KEY)
    return stored === 'light' || stored === 'dark' ? stored : 'system'
  } catch {
    return 'system'
  }
}

/** Paint the theme onto <html>. Mirrored by the inline script in index.html,
 *  which runs before first paint so a dark reload never flashes cream. */
export function applyTheme(choice) {
  const dark = choice === 'dark' || (choice === 'system' && systemDark())
  document.documentElement.classList.toggle('dark', dark)
  document.documentElement.style.colorScheme = dark ? 'dark' : 'light'
  return dark
}

export function useTheme() {
  const [choice, setChoice] = useState(readChoice)
  const [isDark, setIsDark] = useState(
    () => typeof document !== 'undefined' && document.documentElement.classList.contains('dark'),
  )

  useEffect(() => {
    setIsDark(applyTheme(choice))
    try {
      if (choice === 'system') localStorage.removeItem(KEY)
      else localStorage.setItem(KEY, choice)
    } catch {
      // Private mode: the theme still applies to this session.
    }
  }, [choice])

  // Follow the OS while no explicit choice is stored.
  useEffect(() => {
    const query = window.matchMedia?.('(prefers-color-scheme: dark)')
    if (!query) return undefined
    const onChange = () => {
      if (readChoice() === 'system') setIsDark(applyTheme('system'))
    }
    query.addEventListener('change', onChange)
    return () => query.removeEventListener('change', onChange)
  }, [])

  const toggle = useCallback(() => {
    setChoice((current) =>
      current === 'dark' || (current === 'system' && systemDark()) ? 'light' : 'dark',
    )
  }, [])

  return { choice, setChoice, isDark, toggle }
}

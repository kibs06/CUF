export default function AvatarInitials({ name, email, size = 'md' }) {
  const sizes = { sm: 'h-8 w-8 text-xs', md: 'h-10 w-10 text-sm', lg: 'h-12 w-12' }
  const initials = (() => {
    const source = name || email || '?'
    const parts = source.trim().split(/\s+/)
    if (parts.length >= 2) return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
    return source.slice(0, 2).toUpperCase()
  })()

  return (
    <div
      className={`flex shrink-0 items-center justify-center rounded-full bg-primary/15 font-medium text-primary ${sizes[size]}`}
    >
      {initials}
    </div>
  )
}

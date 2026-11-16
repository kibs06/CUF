import { useEffect, useState } from 'react'

const SIZES = {
  sm: 'h-8 w-8 text-xs',
  md: 'h-10 w-10 text-sm',
  lg: 'h-12 w-12',
}

export default function AvatarInitials({ name, email, src, size = 'md' }) {
  const [imageFailed, setImageFailed] = useState(false)
  const sizeClasses = SIZES[size] ?? SIZES.md
  const initials = (() => {
    const source = name || email || '?'
    const parts = source.trim().split(/\s+/)
    if (parts.length >= 2) return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
    return source.slice(0, 2).toUpperCase()
  })()

  useEffect(() => {
    setImageFailed(false)
  }, [src])

  if (src && !imageFailed) {
    return (
      <img
        src={src}
        alt={name ? `${name}'s profile picture` : 'Profile picture'}
        loading="lazy"
        onError={() => setImageFailed(true)}
        className={`shrink-0 rounded-full bg-canvas object-cover ${sizeClasses}`}
      />
    )
  }

  return (
    <div
      className={`flex shrink-0 items-center justify-center rounded-full bg-primary/15 font-medium text-primary ${sizeClasses}`}
    >
      {initials}
    </div>
  )
}

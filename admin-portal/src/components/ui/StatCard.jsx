import { motion, useReducedMotion } from 'framer-motion'

const TONES = {
  primary: { bar: 'bg-primary', wash: 'from-primary/10', badge: 'bg-primary text-white', hover: 'hover:shadow-primary/20' },
  accent: { bar: 'bg-accent', wash: 'from-accent/10', badge: 'bg-accent text-[#12413D]', hover: 'hover:shadow-accent/20' },
  pending: { bar: 'bg-pending', wash: 'from-pending/10', badge: 'bg-pending text-white', hover: 'hover:shadow-pending/20' },
  error: { bar: 'bg-error', wash: 'from-error/10', badge: 'bg-error text-white', hover: 'hover:shadow-error/20' },
  neutral: { bar: 'bg-gray-400', wash: 'from-gray-400/20', badge: 'bg-gray-500 text-white', hover: 'hover:shadow-gray-500/20' },
}

export default function StatCard({
  icon,
  label,
  value,
  highlight = false,
  iconBg = 'rgba(139,90,43,0.1)',
  iconColor = '#8B5A2B',
  children,
  tone,
  Icon,
  sparkline,
}) {
  const reduceMotion = useReducedMotion()
  const t = tone ? TONES[tone] : null

  return (
    <motion.div
      whileHover={reduceMotion ? undefined : { y: -3 }}
      transition={{ type: 'spring', stiffness: 320, damping: 24 }}
      className={`relative overflow-hidden rounded-2xl border border-[#D9D0C7] bg-white p-6 shadow-sm transition-shadow hover:shadow-lg ${
        highlight ? 'ring-2 ring-[#E8A020]/40' : ''
      } ${t ? `bg-gradient-to-br ${t.wash} to-white ${t.hover}` : ''}`}
    >
      {/* Left accent bar */}
      {t && <div className={`absolute inset-y-0 left-0 w-1 ${t.bar}`} />}

      <div className="flex items-start justify-between gap-4">
        {t && Icon ? (
          <div className={`mb-4 flex h-12 w-12 items-center justify-center rounded-full shadow-sm ${t.badge}`}>
            <Icon size={20} strokeWidth={2} />
          </div>
        ) : (
          <div
            className="mb-4 flex h-12 w-12 items-center justify-center rounded-xl"
            style={{ background: iconBg }}
          >
            <span style={{ color: iconColor }} className="text-lg">
              {icon}
            </span>
          </div>
        )}
        {sparkline}
      </div>

      {/* Number in JetBrains Mono */}
      <p className="mb-1 font-mono text-3xl font-bold text-[#3B2314]">{children ?? value}</p>

      {/* Label */}
      <p className="text-sm font-medium text-[#6B5C4E]">{label}</p>
    </motion.div>
  )
}

import { AnimatePresence, motion, useReducedMotion } from 'motion/react'

const SIZES = {
  md: 'max-w-lg',
  xl: 'max-w-2xl',
}

export default function Modal({ open, onClose, title, children, footer, size = 'md' }) {
  const reduce = useReducedMotion()

  return (
    <AnimatePresence>
      {open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <motion.div
            className="absolute inset-0 bg-secondary/40"
            initial={reduce ? false : { opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={reduce ? undefined : { opacity: 0 }}
            transition={{ duration: 0.15 }}
            onClick={onClose}
          />
          <motion.div
            className={`relative z-10 w-full ${SIZES[size]} max-h-[85vh] overflow-y-auto rounded-2xl border border-border bg-surface p-6 shadow-xl`}
            initial={reduce ? false : { opacity: 0, scale: 0.96, y: 10 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={reduce ? undefined : { opacity: 0, scale: 0.96, y: 10 }}
            transition={{ type: 'spring', bounce: 0.08, duration: 0.22 }}
          >
            <div className="mb-4 flex items-start justify-between gap-4">
              <h2 className="font-display text-xl font-bold text-secondary">{title}</h2>
              <button
                type="button"
                onClick={onClose}
                className="rounded-lg px-2 py-1 text-secondary/60 hover:bg-border/40"
              >
                ✕
              </button>
            </div>
            <div>{children}</div>
            {footer && <div className="mt-6 flex justify-end gap-3">{footer}</div>}
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  )
}

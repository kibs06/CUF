import { useEffect } from 'react'
import { Eye, Image, Link2, Download, FileUp, Sparkles, Trash2 } from 'lucide-react'

// ─── The 3D shelf's right-click menu ───────────────────────────────
//
// A card's buttons cover the one thing an admin does daily (look at the
// model). Everything else lives here: photos, the file itself, its link, a
// replacement upload for a wrong live file — and at the bottom, behind its
// own confirm, the delete. The menu is positioned at the cursor and clamped
// into the viewport, so a card at the page's edge still opens a fully
// visible menu.
//
// `menu` is `{ entry, x, y } | null`. Every choice reports back through
// `onPick(action, entry)` and the page owns what happens next — the menu
// never downloads, copies, uploads, or deletes anything itself.

const MENU_WIDTH = 232

const items = [
  { action: 'view', label: 'View 3D', Icon: Eye, hint: 'Open the model viewer' },
  { action: 'photos', label: 'View product photos', Icon: Image, hint: 'All of the product’s pictures' },
  {
    action: 'download',
    label: 'Download .glb for editing',
    Icon: Download,
    hint: 'Edit in Blender, re-upload as a new version',
  },
  { action: 'copy', label: 'Copy public link', Icon: Link2, hint: 'The file customers download' },
  {
    action: 'upload-ar',
    label: 'Upload AR effect (.deepar)',
    Icon: Sparkles,
    // Filled in per product below: live version when there is one.
    hint: 'The Studio file customers fit in',
  },
  {
    action: 'replace',
    label: 'Replace live model…',
    Icon: FileUp,
    hint: 'Publish the fixed file as a new version',
  },
]

export default function ModelledProductMenu({ menu, onPick, onClose }) {
  // Escape closes; a second right-click elsewhere moves the menu rather than
  // stacking one (the page re-sets `menu` on every contextmenu event).
  useEffect(() => {
    if (!menu) return undefined
    const onKey = (e) => {
      if (e.key === 'Escape') onClose?.()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [menu, onClose])

  if (!menu) return null

  const left = Math.max(8, Math.min(menu.x, window.innerWidth - MENU_WIDTH - 8))
  const top = Math.max(8, Math.min(menu.y, window.innerHeight - items.length * 44 - 64))

  const choose = (action) => {
    onPick?.(action, menu.entry)
  }

  return (
    <div className="fixed inset-0 z-50" onContextMenu={(e) => e.preventDefault()}>
      <div className="absolute inset-0" onClick={() => onClose?.()} onContextMenu={() => onClose?.()} />
      <div
        role="menu"
        aria-label={`Actions for ${menu.entry?.name ?? 'this product'}`}
        className="absolute overflow-hidden rounded-xl border border-[#D9D0C7] bg-white py-1 shadow-xl"
        style={{ left, top, width: MENU_WIDTH }}
      >
        {items.map(({ action, label, Icon, hint }) => {
          // The AR row names the live version when there is one, so the admin
          // can see at a glance whether this upload replaces or introduces.
          const text =
            action === 'upload-ar' && menu.ar
              ? `Live: v${menu.ar.version} — replaces it`
              : hint
          return (
            <button
              key={action}
              type="button"
              role="menuitem"
              title={text}
              onClick={() => choose(action)}
              className="flex w-full items-center gap-3 px-4 py-2.5 text-left transition-colors hover:bg-[#F5F0EB]"
            >
              <Icon size={15} className="shrink-0 text-[#8B5A2B]" />
              <span>
                <span className="block text-sm font-medium text-[#3B2314]">{label}</span>
                <span className="block text-[11px] text-[#6B5C4E]">{text}</span>
              </span>
            </button>
          )
        })}
        <div className="my-1 border-t border-[#F5F0EB]" />
        <button
          type="button"
          role="menuitem"
          title="Remove the file and its row — asks first"
          onClick={() => choose('delete')}
          className="flex w-full items-center gap-3 px-4 py-2.5 text-left transition-colors hover:bg-red-50"
        >
          <Trash2 size={15} className="shrink-0 text-[#D64545]" />
          <span>
            <span className="block text-sm font-semibold text-[#D64545]">Delete live model…</span>
            <span className="block text-[11px] text-[#6B5C4E]">Version and file, with confirm</span>
          </span>
        </button>
      </div>
    </div>
  )
}

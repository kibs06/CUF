import 'highcharts/esm/modules/exporting.js'
import 'highcharts/esm/modules/offline-exporting.js'

let openMenu = null

function closeMenu() {
  if (openMenu) {
    openMenu.remove()
    openMenu = null
  }
  document.removeEventListener('click', onDocClick, true)
  document.removeEventListener('keydown', onKeyDown, true)
}

function onDocClick(e) {
  if (openMenu && !openMenu.contains(e.target)) closeMenu()
}

function onKeyDown(e) {
  if (e.key === 'Escape') closeMenu()
}

function toCsv(rows) {
  return rows
    .map((row) =>
      row
        .map((cell) => {
          const s = String(cell ?? '')
          return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
        })
        .join(','),
    )
    .join('\n')
}

const MENU_STYLE = {
  position: 'fixed',
  zIndex: '9999',
  minWidth: '210px',
  padding: '6px',
  background: '#fff',
  border: '1px solid #D9D0C7',
  borderRadius: '12px',
  boxShadow: '0 12px 32px rgba(59, 35, 20, 0.18)',
  fontFamily: 'DM Sans, sans-serif',
  fontSize: '13px',
  color: '#3B2314',
}

const ITEM_STYLE = {
  display: 'flex',
  alignItems: 'center',
  width: '100%',
  padding: '8px 10px',
  border: '0',
  borderRadius: '8px',
  background: 'transparent',
  color: 'inherit',
  font: 'inherit',
  textAlign: 'left',
  cursor: 'pointer',
}

function menuItem(label, onSelect, { keepOpen = false } = {}) {
  const btn = document.createElement('button')
  btn.type = 'button'
  btn.textContent = label
  Object.assign(btn.style, ITEM_STYLE)
  btn.addEventListener('mouseenter', () => {
    btn.style.background = '#F5EFE6'
  })
  btn.addEventListener('mouseleave', () => {
    btn.style.background = 'transparent'
  })
  btn.addEventListener('click', () => {
    onSelect(btn)
    if (!keepOpen) closeMenu()
  })
  return btn
}

function separator() {
  const hr = document.createElement('div')
  hr.style.height = '1px'
  hr.style.margin = '5px 4px'
  hr.style.background = '#E7DDCF'
  return hr
}

/**
 * Attaches a right-click menu to an imperative Highcharts instance.
 * Returns a detach function for effect cleanup.
 */
export function attachChartContextMenu(chart, { filename, getCsvRows }) {
  const container = chart.container

  const handleContextMenu = (e) => {
    e.preventDefault()
    closeMenu()

    const menu = document.createElement('div')
    Object.assign(menu.style, MENU_STYLE)
    menu.setAttribute('role', 'menu')

    menu.appendChild(
      menuItem('Download PNG', () => chart.exportChart({ type: 'image/png', filename })),
    )
    menu.appendChild(
      menuItem('Download JPEG', () => chart.exportChart({ type: 'image/jpeg', filename })),
    )
    menu.appendChild(
      menuItem('Download SVG', () => chart.exportChart({ type: 'image/svg+xml', filename })),
    )
    menu.appendChild(
      menuItem('Download PDF', () => chart.exportChart({ type: 'application/pdf', filename })),
    )
    menu.appendChild(separator())
    menu.appendChild(menuItem('Print chart', () => chart.print()))
    menu.appendChild(
      menuItem('View fullscreen', () => {
        if (document.fullscreenElement) {
          document.exitFullscreen?.()
        } else {
          container.requestFullscreen?.()
        }
      }),
    )

    const is3D = chart.options.chart.options3d?.enabled !== false
    menu.appendChild(
      menuItem(is3D ? 'Switch to 2D view' : 'Switch to 3D view', () => {
        chart.update({ chart: { options3d: { enabled: !is3D } } })
      }),
    )
    menu.appendChild(
      menuItem(
        'Copy data as CSV',
        (btn) => {
          const original = btn.textContent
          navigator.clipboard
            ?.writeText(toCsv(getCsvRows()))
            .then(() => {
              btn.textContent = 'Copied to clipboard'
              setTimeout(() => {
                btn.textContent = original
              }, 1400)
            })
            .catch(() => {
              btn.textContent = 'Copy failed'
              setTimeout(() => {
                btn.textContent = original
              }, 1400)
            })
        },
        { keepOpen: true },
      ),
    )

    document.body.appendChild(menu)
    const rect = menu.getBoundingClientRect()
    menu.style.left = `${Math.max(8, Math.min(e.clientX, window.innerWidth - rect.width - 8))}px`
    menu.style.top = `${Math.max(8, Math.min(e.clientY, window.innerHeight - rect.height - 8))}px`

    openMenu = menu
    document.addEventListener('click', onDocClick, true)
    document.addEventListener('keydown', onKeyDown, true)
  }

  container.addEventListener('contextmenu', handleContextMenu)
  return () => {
    container.removeEventListener('contextmenu', handleContextMenu)
    if (openMenu && container.contains(openMenu)) closeMenu()
  }
}

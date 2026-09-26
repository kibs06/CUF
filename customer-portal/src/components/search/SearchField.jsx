import { useEffect, useMemo, useRef, useState } from 'react'
import { Command, Layers, Package, Search, Tag, X } from 'lucide-react'

import { useProducts } from '../../hooks/useCatalog'
import { searchPanelRows, SEARCH_PANEL_ROW } from '../../lib/searchRules'

/** How a panel row is drawn: an icon and the word for what it is. */
const ROW_KINDS = {
  [SEARCH_PANEL_ROW.query]: { Icon: Search, label: null },
  [SEARCH_PANEL_ROW.category]: { Icon: Layers, label: 'Category' },
  [SEARCH_PANEL_ROW.tag]: { Icon: Tag, label: 'Tag' },
  [SEARCH_PANEL_ROW.product]: { Icon: Package, label: 'Product' },
}

/** The collapsed pill: a 40px circle, the same square as the header's buttons. */
const COLLAPSED = 'w-10'

/**
 * The header's search: a pill the width of the magnifier that opens into a
 * field, with the suggestion panel under it.
 *
 * The shell is Lightswind UI's `ExpandableSearch` — an icon that expands into
 * the input, with focus management, a clear button, a `⌘K` hint and a collapse
 * when the customer clicks away with nothing typed. It is a port, not a copy,
 * and the differences are all this codebase's rules rather than taste:
 *
 *  1. **CSS, not a spring.** The published version animates its width with
 *     Framer Motion (`stiffness: 400, damping: 30`). Here the width is two
 *     Tailwind classes and a `transition-[width]` on the project's own
 *     `ease-out-cubic` curve — the same substitution the rest of the portal
 *     makes, for the two reasons "Animations must fail open" gives: a class is
 *     the element's *natural* state, so a transition that never runs costs the
 *     slide and not the field, and every duration and curve in the portal comes
 *     from `transitions.js`. The visible difference is that the published spring
 *     overshoots slightly and this does not.
 *  2. **One control at every size, centred from `lg` up.** The published
 *     component is a desktop search; the portal's header had a field on desktop
 *     and a separate expanding row on a phone. Both are now this pill, which
 *     the header `lg`-and-up grid centres and which, below `lg`, takes the
 *     whole row while open — on a 390px row there is no room for a field *and* a
 *     header. That is also why the open width is `w-full` below `lg`, `22rem`
 *     from `lg` and `26rem` from `xl`: the pill fills whatever it has been given
 *     rather than being a fixed width with 70px of nothing beside it. The
 *     published component opens to `18rem`, and 288px is uncomfortably tight in
 *     a bar whose middle track is `1fr auto 1fr` — long enough only for the
 *     placeholder, which is how a search field ends up looking like a button.
 *  3. **`⌘K` is real.** The published badge is decoration. Here `⌘K` (or
 *     `Ctrl-K` off a Mac) opens and focuses the field, so the hint tells the
 *     truth — and the hint is hidden below `md`, where there is no keyboard to
 *     press it on.
 *  4. **Escape is layered, and `⌘K` is not the only way in.** Escape closes the
 *     suggestion panel first and the field only on a second press, because
 *     throwing away what someone typed is not what they meant by "close this".
 *  5. **`type="text"`, not `type="search"`.** A search input draws the
 *     browser's own ✕ once there is text in it, so a customer who typed a letter
 *     saw **two ✕ in the same pill** — the browser's, which does not clear the
 *     panel, does not return focus to the field and is a different size in every
 *     engine, next to ours, which does all three.
 *
 *     Hiding it with `input[type='search']::-webkit-search-cancel-button`
 *     (`appearance: none`, in `index.css`) is the usual fix and it is still
 *     there as the site-wide guard — but this field does not rely on it, because
 *     a pseudo-element override cannot be checked and this one cannot fail: with
 *     no `type="search"` there is nothing for the engine to draw. The two things
 *     `type="search"` was doing are said outright instead — `inputMode` and
 *     `enterKeyHint` for the mobile keyboard's own "search" key, and `role` +
 *     the `aria-*` set below (which this input already carried, so the role was
 *     never the implicit one).
 *
 * The suggestion panel itself is unchanged (`product_search_screen.dart`, via
 * `searchSuggestionsFor`): the typed query first, then the catalog's own
 * categories, tags and products ranked by `searchRules.js`, derived from the
 * catalog already in memory, so a keystroke still costs no request. Five
 * behaviours in it are load-bearing:
 *
 *  1. **The catalog is fetched only while a panel is actually needed.** This
 *     component sits in the header, so it renders on every page;
 *     `useProducts({ enabled })` keeps the query asleep until the customer has
 *     typed something, and the shared cache is read after that.
 *  2. **The panel is focus-safe.** It closes on a click outside and on Escape
 *     using the same `pointerdown` listener as `AccountMenu` rather than
 *     `blur`: a blur handler fires before the click lands, so the row would
 *     close before it could be chosen. Rows use `onMouseDown` +
 *     `preventDefault` for the same reason — focus never leaves the input.
 *  3. **Keyboard first.** ArrowDown/ArrowUp move the highlight, Enter runs it
 *     (or the typed query when nothing is highlighted), Escape closes. The
 *     input is the only focusable element in the open state: the collapsed
 *     trigger is swapped out, and `aria-activedescendant` points at the
 *     highlighted option, which is the combobox pattern rather than a list of
 *     focusable rows a Tab press would have to walk.
 *  4. **Everything that appears does so with CSS and unmounts on close**
 *     (`.drop-enter`, `.pop-enter`), like every other overlay here — no exit
 *     animation, and nothing left mounted over the page taking clicks it should
 *     not. See "Animations must fail open" in the README.
 *  5. **Submitting collapses the pill.** The search runs on `/shop?q=…`, and on
 *     a phone the open pill *is* the header, so leaving it open would leave the
 *     customer on a page whose header had no logo and no cart. The query stays
 *     in the field, so reopening shows what was searched and the clear button
 *     is one press away.
 */
export default function SearchField({
  id,
  className = '',
  placeholder = 'Search shoes, sandals, makers…',
  onSubmit,
  onExpandedChange,
}) {
  const [query, setQuery] = useState('')
  const [expanded, setExpanded] = useState(false)
  const [open, setOpen] = useState(false)
  const [activeIndex, setActiveIndex] = useState(-1)
  const [refocusTrigger, setRefocusTrigger] = useState(false)
  const containerRef = useRef(null)
  const inputRef = useRef(null)
  const triggerRef = useRef(null)

  const trimmed = query.trim()
  const showing = open && trimmed.length > 0

  const productsQuery = useProducts({ enabled: showing })
  const rows = useMemo(
    () => (showing ? searchPanelRows(query, productsQuery.data ?? []) : []),
    [showing, query, productsQuery.data],
  )

  /* The header needs to know: below `md` an open pill takes the whole row. */
  useEffect(() => {
    onExpandedChange?.(expanded)
  }, [expanded, onExpandedChange])

  /* Opening is always followed by the cursor being in the field. */
  useEffect(() => {
    if (expanded) inputRef.current?.focus()
  }, [expanded])

  /* `⌘K` / `Ctrl-K`: what the badge promises, actually wired. */
  useEffect(() => {
    const onKeyDown = (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault()
        setExpanded(true)
      }
    }
    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [])

  const collapse = ({ focusTrigger = false } = {}) => {
    setExpanded(false)
    setOpen(false)
    setActiveIndex(-1)
    if (focusTrigger) setRefocusTrigger(true)
  }

  /*
    Focus moves back to the pill on the render *after* the collapse, not inside
    the handler: while the handler runs the pill is still the previous render's
    field, so `triggerRef` is null and the focus would land on `<body>` — which
    is a keyboard customer's place in the page, thrown away by pressing Escape.
  */
  useEffect(() => {
    if (expanded || !refocusTrigger) return
    triggerRef.current?.focus()
    setRefocusTrigger(false)
  }, [expanded, refocusTrigger])

  /*
    A click outside: the panel always goes, and the pill goes too — but only
    when it is empty. Collapsing a field with something typed in it throws away
    the customer's words to save the width of the field.
  */
  useEffect(() => {
    if (!showing && !expanded) return undefined

    const onPointerDown = (event) => {
      if (containerRef.current?.contains(event.target)) return
      setOpen(false)
      if (trimmed.length === 0) collapse()
    }

    document.addEventListener('pointerdown', onPointerDown)
    return () => document.removeEventListener('pointerdown', onPointerDown)
  }, [showing, expanded, trimmed])

  /** Move the highlight, opening the panel first so ArrowDown alone works. */
  const move = (step) => {
    if (rows.length === 0) return
    setOpen(true)
    setActiveIndex((current) => {
      const next = current + step
      if (next < 0) return -1
      return next > rows.length - 1 ? rows.length - 1 : next
    })
  }

  const run = (term) => {
    const value = String(term ?? '').trim()
    setOpen(false)
    setActiveIndex(-1)
    if (value) setQuery(value)
    collapse()
    onSubmit?.(value)
  }

  const onKeyDown = (event) => {
    if (event.key === 'ArrowDown') {
      event.preventDefault()
      move(1)
    } else if (event.key === 'ArrowUp') {
      event.preventDefault()
      move(-1)
    } else if (event.key === 'Escape') {
      // The panel first, and only then the field: Escape while the panel is up
      // must not also throw away what the customer typed.
      if (open) {
        event.preventDefault()
        setOpen(false)
        setActiveIndex(-1)
      } else {
        collapse({ focusTrigger: true })
      }
    } else if (event.key === 'Enter') {
      if (activeIndex >= 0 && rows[activeIndex]) {
        event.preventDefault()
        run(rows[activeIndex].term)
      }
      // Otherwise the form submits, which runs the typed query.
    }
  }

  const clear = () => {
    setQuery('')
    setOpen(false)
    setActiveIndex(-1)
    inputRef.current?.focus()
  }

  const listId = `${id}-suggestions`
  /* A Mac keyboard says ⌘; every other one says Ctrl. The badge has to match
     the key the listener above is actually listening for. */
  const isMac =
    typeof navigator !== 'undefined' &&
    /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent)

  return (
    <div
      ref={containerRef}
      className={`relative flex h-10 shrink-0 items-center transition-[width] duration-300 ease-out-cubic ${
        expanded ? 'w-full lg:w-[22rem] xl:w-[26rem]' : COLLAPSED
      } ${className}`}
    >
      {expanded ? (
        /* ── Open: the field, with the panel under it ─────────────────────── */
        <form
          role="search"
          onSubmit={(event) => {
            event.preventDefault()
            run(trimmed)
          }}
          className="relative flex h-10 w-full items-center rounded-full border border-hairline bg-subtle/70 transition-colors duration-200 ease-out-cubic focus-within:bg-raised"
        >
          <label htmlFor={id} className="sr-only">
            Search products
          </label>

          <Search
            size={16}
            strokeWidth={2}
            aria-hidden="true"
            className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted"
          />

          <input
            id={id}
            ref={inputRef}
            type="text"
            inputMode="search"
            enterKeyHint="search"
            value={query}
            onChange={(event) => {
              setQuery(event.target.value)
              setOpen(true)
              setActiveIndex(-1)
            }}
            onFocus={() => {
              if (trimmed.length > 0) setOpen(true)
            }}
            onKeyDown={onKeyDown}
            placeholder={placeholder}
            autoComplete="off"
            role="combobox"
            aria-expanded={showing}
            aria-controls={listId}
            aria-autocomplete="list"
            aria-activedescendant={
              activeIndex >= 0 ? `${id}-option-${activeIndex}` : undefined
            }
            className="h-10 w-full rounded-full bg-transparent pl-9 pr-10 text-sm text-ink placeholder:text-muted"
          />

          {trimmed.length > 0 ? (
            <button
              type="button"
              onClick={clear}
              aria-label="Clear search"
              className="pop-enter absolute right-1 flex h-8 w-8 items-center justify-center rounded-full text-muted transition-colors duration-200 ease-out-cubic hover:bg-subtle hover:text-ink"
            >
              <X size={16} strokeWidth={2} />
            </button>
          ) : (
            <span
              aria-hidden="true"
              className="pop-enter pointer-events-none absolute right-3 hidden items-center gap-1 rounded border border-hairline bg-raised px-1.5 py-0.5 text-[10px] font-medium text-muted md:flex"
            >
              {isMac ? <Command size={11} strokeWidth={2} /> : <span>Ctrl</span>}
              <span>K</span>
            </span>
          )}

          {showing && rows.length > 0 && (
            <ul
              id={listId}
              role="listbox"
              aria-label="Search suggestions"
              className="drop-enter absolute inset-x-0 top-full z-50 mt-2 overflow-hidden rounded-card border border-hairline bg-raised shadow-card-lift"
            >
              {rows.map((row, index) => {
                const { Icon, label } = ROW_KINDS[row.kind] ?? ROW_KINDS.product
                const active = index === activeIndex

                return (
                  <li
                    key={`${row.kind}:${row.term}`}
                    id={`${id}-option-${index}`}
                    role="option"
                    aria-selected={active}
                    /*
                      Not a button: in the combobox pattern the input keeps focus
                      and owns the active option, so the row is only clickable —
                      and `preventDefault` on mousedown is what stops the click's
                      own focus change from closing the panel before it lands.
                    */
                    onMouseDown={(event) => event.preventDefault()}
                    onClick={() => run(row.term)}
                    onMouseEnter={() => setActiveIndex(index)}
                    className={`flex cursor-pointer items-center gap-2.5 px-3.5 py-2.5 text-sm transition-colors duration-200 ${
                      active ? 'bg-subtle text-ink' : 'text-muted-strong'
                    }`}
                  >
                    <Icon
                      size={15}
                      strokeWidth={2}
                      className={`shrink-0 ${active ? 'text-clay-ink' : 'text-muted'}`}
                    />
                    <span className="min-w-0 flex-1 truncate">
                      {row.kind === SEARCH_PANEL_ROW.query
                        ? `Search for “${row.term}”`
                        : row.term}
                    </span>
                    {label && (
                      <span className="shrink-0 text-[11px] uppercase tracking-[0.08em] text-muted">
                        {label}
                      </span>
                    )}
                  </li>
                )
              })}
            </ul>
          )}
        </form>
      ) : (
        /*
          ── Closed: a 40px circle, and the width transition is on it ────────

          The pill's width is two classes rather than an animated style, so the
          closed state is the element's own layout: if the transition never
          runs, the customer gets a field that appears instantly instead of a
          field that never appears.
        */
        <button
          ref={triggerRef}
          type="button"
          onClick={() => setExpanded(true)}
          aria-label="Search products"
          aria-expanded={false}
          aria-controls={id}
          className="inline-flex h-10 w-full items-center justify-center rounded-full border border-transparent bg-subtle/70 text-muted transition-colors duration-200 ease-out-cubic hover:border-hairline hover:bg-subtle hover:text-ink"
        >
          <Search size={16} strokeWidth={2} />
        </button>
      )}
    </div>
  )
}

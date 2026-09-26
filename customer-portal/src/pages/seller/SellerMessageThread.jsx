import { useEffect, useId, useMemo, useRef, useState } from 'react'
import { Link, useOutletContext, useParams } from 'react-router-dom'
import { ArrowLeft, CheckCheck, MessageSquareOff, SendHorizontal } from 'lucide-react'

import MessageBubble from '../../components/messages/MessageBubble.jsx'
import EmptyState from '../../components/ui/EmptyState'
import { useAuth } from '../../hooks/useAuth.jsx'
import {
  useSellerMessageActions,
  useStoreConversation,
  useStoreThreadMessages,
} from '../../hooks/useSellerMessages.js'
import { getInitials } from '../../lib/constants.js'
import ThreadHistoryNotice from '../../components/messages/ThreadHistoryNotice.jsx'
import {
  SELLER_SENDER_TYPE,
  isMine,
  messageDayKey,
  messageDayLabel,
  readReceiptFor,
  sellerConversationName,
  sortMessages,
  threadHistoryState,
} from '../../lib/sellerMessages.js'

/**
 * One thread with one customer, and the composer that answers it.
 *
 * The seller's half of `/messages/:conversationId`, and the same page in every
 * way that matters: the composer is pinned to the bottom and sends on Enter with
 * Shift+Enter for a newline, sending is optimistic under a temporary id that
 * `mergeMessage` replaces rather than duplicates, and the customer's messages are
 * marked read through the `mark_conversation_read` RPC with `reader_role =
 * 'seller'` — never a table UPDATE, because there is no UPDATE policy on
 * `messages` and an UPDATE that matches nothing returns `200 OK`.
 *
 * Three things are the seller's own:
 *
 *  1. **The header is a person.** A customer's thread header is a store with a
 *     "Visit workshop" link; this one is a customer's name and initials, and the
 *     only page it could sensibly link to is an order — of which there may be
 *     several, so it links to none of them. Guessing one would be worse than the
 *     cross-reference that actually exists: the orders list, searchable.
 *  2. **The receipt is about the shop's reply.** `readReceiptFor(messages,
 *     'seller')` answers "has the customer read what I said", which is the only
 *     reading of a receipt that tells a seller anything.
 *  3. **What the customer was told.** The footnote names the two places a reply
 *     actually lands — the app and e-mail — because a seller answering from a
 *     desktop has no other way to know whether the customer will ever see it.
 *
 * ## It is also the inside of the side panel
 *
 * `embedded` says the same thread is being drawn in the side panel's column —
 * whose width the seller sets — rather than on its own page, and it changes
 * three things, all of them layout: the page
 * padding and centring come off, the back link points at the inbox *list* the
 * panel is holding rather than at a route, and the message list takes the height
 * it is given instead of capping itself at `52vh` — a cap that makes no sense
 * inside a panel whose own height is already the viewport's.
 *
 * `conversationId` moves from the URL to a prop for the panel (there is no route
 * inside it); the page keeps reading `useParams`, which is what makes a pasted
 * `/seller/messages/<id>` still work.
 *
 * ## `storeId` is a prop here, and that is not the same mistake
 *
 * Every other seller page reads the store from the shell's outlet context. This
 * component cannot, because the panel is **not inside** `<Outlet>` — it is a
 * sibling of `<main>`, which is the only way a pinned panel can be a real column
 * beside the page. `useOutletContext` there returns `null`, and the previous
 * version destructured `store` straight off it: opening a thread in the panel
 * threw, and a throw outside `<main>` takes the ErrorBoundary with it, so it was
 * the whole shell and not just the panel. The panel already has the id (and
 * passes it to the two lists), so it passes it here too; the page's own render
 * still goes through the outlet context as before.
 */
export default function SellerMessageThread({
  conversationId: embeddedConversationId,
  embedded = false,
  onBack,
  storeId: storeIdProp,
}) {
  const params = useParams()
  const conversationId = embeddedConversationId ?? params.conversationId
  const { store } = useOutletContext() ?? {}
  const storeId = storeIdProp ?? store?.id ?? null
  const { user } = useAuth()

  const conversationQuery = useStoreConversation(conversationId)
  const messagesQuery = useStoreThreadMessages(conversationId)
  const { send, remove } = useSellerMessageActions(storeId)

  const [draft, setDraft] = useState('')
  const [problem, setProblem] = useState(null)
  /*
    An id per instance, because this component can be mounted twice at once: the
    panel can be showing a thread while the page behind it is `/seller/messages/
    <another id>`. Two elements sharing one `id` is invalid, and the label's
    `htmlFor` would silently attach to whichever came first.
  */
  const draftId = `seller-message-draft-${useId()}`
  const listRef = useRef(null)
  const inputRef = useRef(null)

  const conversation = conversationQuery.data
  const name = conversation ? sellerConversationName(conversation) : 'this customer'
  const messages = useMemo(
    () => sortMessages(messagesQuery.data ?? []),
    [messagesQuery.data],
  )
  const receipt = readReceiptFor(messages, SELLER_SENDER_TYPE)
  /*
    Which of the four things this thread is: a conversation, an empty one, a read
    that did not happen, or a read that did not happen while realtime kept
    delivering. `isError` is the only honest source for that — RLS answers
    `200 []` for a denied read, so an empty list on its own proves nothing.
  */
  const history = threadHistoryState({
    isError: messagesQuery.isError,
    count: messages.length,
  })

  /*
    Keep the newest message in view. `messages.length` rather than the array, so
    this does not re-scroll when an optimistic bubble is replaced by the stored
    row (a new array, the same length).
  */
  useEffect(() => {
    const node = listRef.current
    if (node) node.scrollTop = node.scrollHeight
  }, [messages.length])

  const onSend = async (event) => {
    event?.preventDefault?.()
    const body = draft.trim()
    if (!body || send.isPending) return

    setProblem(null)
    setDraft('')
    try {
      await send.mutateAsync({ conversationId, body })
    } catch (error) {
      // Give the words back rather than losing them to a failed request.
      setDraft(body)
      setProblem(error?.message ?? 'That reply could not be sent.')
    }
  }

  if (conversationQuery.isLoading) {
    return (
      <div className={embedded ? 'p-4' : 'mx-auto max-w-3xl px-4 py-10 sm:px-6 lg:px-8'}>
        <div className="shimmer h-4 w-32" />
        <div className="shimmer mt-6 h-16 rounded-card" />
        <div className="shimmer mt-6 h-80 rounded-card" />
      </div>
    )
  }

  if (conversationQuery.isError || !conversation) {
    return (
      <div className={embedded ? 'p-4' : 'mx-auto max-w-2xl px-4 py-16 sm:px-6'}>
        <EmptyState
          Icon={MessageSquareOff}
          title="That conversation is not available"
          description="It may have been removed, or it belongs to another store."
          action={
            embedded ? (
              <button type="button" onClick={onBack} className="btn btn-primary">
                Back to your messages
              </button>
            ) : (
              <Link to="/seller/messages" className="btn btn-primary">
                Back to your messages
              </Link>
            )
          }
        />
      </div>
    )
  }

  /*
    Two containers, one body. On the page the column is centred and the whole
    thing scrolls with the document; in the panel it fills the height it is
    given and the *messages* scroll, so the composer stays where it was put.
  */
  const shell = embedded
    ? 'flex h-full min-h-0 flex-col px-4 pb-4 pt-1'
    : 'mx-auto flex max-w-3xl flex-col px-4 py-8 sm:px-6 lg:px-8'

  return (
    <div className={shell}>
      {embedded ? (
        <button
          type="button"
          onClick={onBack}
          className="inline-flex shrink-0 items-center gap-2 self-start text-xs font-semibold text-muted transition-colors duration-200 hover:text-ink"
        >
          <ArrowLeft size={14} strokeWidth={2} />
          All messages
        </button>
      ) : (
        <Link
          to="/seller/messages"
          className="inline-flex items-center gap-2 text-xs font-semibold text-muted transition-colors duration-200 hover:text-ink"
        >
          <ArrowLeft size={14} strokeWidth={2} />
          All messages
        </Link>
      )}

      <header className="mt-4 flex items-center gap-3 border-b border-hairline pb-4">
        <span
          aria-hidden="true"
          className={`num flex shrink-0 items-center justify-center rounded-full bg-clay/10 text-sm font-semibold text-clay-ink ${
            embedded ? 'h-9 w-9' : 'h-11 w-11'
          }`}
        >
          {getInitials(name)}
        </span>
        <div className="min-w-0 flex-1">
          <h1
            className={`truncate font-display font-semibold text-ink ${
              embedded ? 'text-lg' : 'text-xl'
            }`}
          >
            {name}
          </h1>
          <p className="mt-0.5 truncate text-xs text-muted">
            {conversation.last_message_at
              ? 'Customer · in this thread since ' + new Date(conversation.created_at).toLocaleDateString('en-PH', { day: 'numeric', month: 'short', year: 'numeric' })
              : 'Customer · no messages yet'}
          </p>
        </div>
      </header>

      {/* ── The thread ────────────────────────────────────────────── */}
      <div
        ref={listRef}
        className={
          embedded
            ? 'mt-4 min-h-0 flex-1 overflow-y-auto pr-1'
            : 'mt-5 max-h-[52vh] min-h-[16rem] flex-1 overflow-y-auto pr-1'
        }
      >
        {messagesQuery.isLoading ? (
          <div className="space-y-3">
            {Array.from({ length: 3 }).map((_, index) => (
              <div key={index} className="shimmer h-16 rounded-card" />
            ))}
          </div>
        ) : history === 'failed' ? (
          /*
            Nothing loaded and the read errored, so this is NOT an empty thread:
            saying "say hello" here describes a conversation that may be months
            deep as a greeting opportunity. See `ThreadHistoryNotice`.
          */
          <ThreadHistoryNotice
            state="failed"
            onRetry={() => messagesQuery.refetch()}
          />
        ) : messages.length > 0 ? (
          <>
            {/* The history is missing but the live messages are not: the strip
                goes ABOVE them, because throwing them away would take away the
                only messages the seller has. */}
            <ThreadHistoryNotice
              state={history}
              onRetry={() => messagesQuery.refetch()}
              className="mb-3"
            />
            <ul className="space-y-1.5">
            {messages.map((message, index) => {
              const previous = messages[index - 1]
              const newDay = messageDayKey(previous?.created_at) !== messageDayKey(message.created_at)

              return (
                <li key={message.id}>
                  {newDay && (
                    <p className="my-4 text-center text-[11px] uppercase tracking-[0.12em] text-muted">
                      {messageDayLabel(message.created_at)}
                    </p>
                  )}
                  <MessageBubble
                    message={message}
                    mine={isMine(message, SELLER_SENDER_TYPE)}
                    onDelete={() => remove.mutate({ conversationId, messageId: message.id })}
                  />
                </li>
              )
            })}
            </ul>
          </>
        ) : (
          <div className="flex h-full flex-col items-center justify-center py-10 text-center">
            <span className="mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-clay/10">
              <SendHorizontal size={20} strokeWidth={1.75} className="text-clay-ink" />
            </span>
            <p className="font-display text-lg font-semibold text-ink">
              Say hello to {name}
            </p>
            <p className="mt-1 max-w-sm text-sm leading-relaxed text-muted">
              They opened this thread and have not written yet. A line about
              sizing or turnaround is usually what they are waiting for.
            </p>
          </div>
        )}
      </div>

      {/* ── The composer ──────────────────────────────────────────── */}
      <div className="mt-4 shrink-0 border-t border-hairline pt-4">
        {/*
          The receipt sits under the shop's own last message: "Read" only means
          something about words the seller said. `readReceiptFor` returns null
          when the customer has the last word.
        */}
        {receipt !== null && (
          <p className="mb-2 flex items-center justify-end gap-1.5 text-[11px] text-muted">
            <CheckCheck size={13} strokeWidth={2} className={receipt ? 'text-olive' : ''} />
            {receipt ? 'Read' : 'Sent'}
          </p>
        )}

        {problem && (
          <p
            role="alert"
            className="mb-3 rounded-field border border-crimson/30 bg-crimson/[0.07] px-3 py-2 text-xs text-ink"
          >
            {problem}
          </p>
        )}

        <form onSubmit={onSend} className="flex items-end gap-2">
          <label htmlFor={draftId} className="sr-only">
            Your reply
          </label>
          <textarea
            id={draftId}
            ref={inputRef}
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={(event) => {
              // Enter sends, Shift+Enter starts a new line — the app's chat box.
              if (event.key === 'Enter' && !event.shiftKey) {
                event.preventDefault()
                onSend()
              }
            }}
            rows={2}
            placeholder={`Reply to ${name}…`}
            className="min-h-[3.25rem] w-full resize-none rounded-field border border-card-edge bg-raised px-4 py-3 text-sm text-ink placeholder:text-muted focus:border-clay focus:outline-none focus:ring-2 focus:ring-clay/25"
          />
          <button
            type="submit"
            disabled={!draft.trim() || send.isPending}
            className="btn btn-primary h-[3.25rem] shrink-0 px-4"
          >
            <SendHorizontal size={16} strokeWidth={2} />
            <span className="sr-only">Send reply</span>
          </button>
        </form>
      </div>

      {user?.email && (
        <p className="mt-3 text-[11px] leading-relaxed text-muted">
          Your reply reaches {name} in the CUFMAI app and by e-mail, and it is
          signed with this shop&rsquo;s name.
        </p>
      )}
    </div>
  )
}

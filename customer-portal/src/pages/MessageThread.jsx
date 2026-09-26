import { useEffect, useMemo, useRef, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { motion } from 'motion/react'
import { ArrowLeft, CheckCheck, MessageSquareOff, SendHorizontal, Store } from 'lucide-react'

import MessageBubble from '../components/messages/MessageBubble.jsx'
import ThreadHistoryNotice from '../components/messages/ThreadHistoryNotice.jsx'
import EmptyState from '../components/ui/EmptyState'
import StoreAvatar from '../components/ui/StoreAvatar'
import { fadeUp, staggerChildren } from '../components/motion/transitions'
import { useAuth } from '../hooks/useAuth.jsx'
import { useConversation, useMessageActions, useMessages } from '../hooks/useMessages.js'
import {
  CUSTOMER_SENDER_TYPE,
  isMine,
  messageDayKey,
  messageDayLabel,
  readReceiptFor,
  sortMessages,
  threadHistoryState,
} from '../lib/messages.js'

/**
 * One thread with one maker.
 *
 * ## The composer is the whole point
 *
 * Everything else on this page is a rendering of data; the composer is the only
 * thing the customer came to do. So it is pinned to the bottom of the column,
 * focused when the page opens from "Message the maker", and it sends on Enter —
 * with Shift+Enter for a newline, because a customer describing a repair will
 * want one.
 *
 * ## Sending is optimistic, and the bubble says so
 *
 * A chat that waits a round trip before the customer's own words appear reads
 * as broken. The bubble is drawn immediately, under a temporary id, and
 * `useMessageActions` swaps it for the stored row when Postgres answers. The
 * realtime channel echoes that same insert back, and `mergeMessage` replaces
 * rather than duplicates — which is exactly why that fold is a tested pure
 * function and not a `setState` in a callback.
 *
 * ## Messages from the maker are marked read
 *
 * On open, and again whenever a reply arrives, the thread calls the
 * `mark_conversation_read` RPC — never a table UPDATE, because there is no
 * UPDATE policy on `messages` and an UPDATE that matches nothing returns
 * `200 OK`. That is the same silent-no-op trap `orders.js` documents.
 *
 * ## What an attachment looks like here
 *
 * A maker who sent a photo from the app sent a **signed** storage URL with a
 * year on it, so it renders straight from `attachment_url`. The portal has no
 * upload path at all: taking the photo is the phone's job, and the private
 * bucket's INSERT policy keys on the app's own upload flow.
 */
export default function MessageThread() {
  const { conversationId } = useParams()
  const { user } = useAuth()

  const conversationQuery = useConversation(conversationId)
  const messagesQuery = useMessages(conversationId)
  const { send, remove } = useMessageActions()

  const [draft, setDraft] = useState('')
  const [problem, setProblem] = useState(null)
  const listRef = useRef(null)
  const inputRef = useRef(null)

  const conversation = conversationQuery.data
  const store = conversation?.store ?? null
  const messages = useMemo(
    () => sortMessages(messagesQuery.data ?? []),
    [messagesQuery.data],
  )
  const receipt = readReceiptFor(messages, CUSTOMER_SENDER_TYPE)
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
      setProblem(error?.message ?? 'That message could not be sent.')
    }
  }

  if (conversationQuery.isLoading) {
    return (
      <div className="mx-auto max-w-3xl px-4 py-10 sm:px-6 lg:px-8">
        <div className="shimmer h-4 w-32" />
        <div className="shimmer mt-6 h-16 rounded-card" />
        <div className="shimmer mt-6 h-80 rounded-card" />
      </div>
    )
  }

  if (conversationQuery.isError || !conversation) {
    return (
      <div className="mx-auto max-w-2xl px-4 py-16 sm:px-6">
        <EmptyState
          Icon={MessageSquareOff}
          title="That conversation is not available"
          description="It may have been removed, or it belongs to another account."
          action={
            <Link to="/messages" className="btn btn-primary">
              Back to your messages
            </Link>
          }
        />
      </div>
    )
  }

  const name = store?.name ?? 'this maker'

  return (
    <div className="mx-auto flex max-w-3xl flex-col px-4 py-8 sm:px-6 lg:px-8">
      <Link
        to="/messages"
        className="inline-flex items-center gap-2 text-xs font-semibold text-muted transition-colors duration-200 hover:text-ink"
      >
        <ArrowLeft size={14} strokeWidth={2} />
        All messages
      </Link>

      <header className="mt-5 flex items-center gap-4 border-b border-hairline pb-5">
        <StoreAvatar store={store} size={44} />
        <div className="min-w-0 flex-1">
          <h1 className="truncate font-display text-xl font-semibold text-ink">{name}</h1>
          <p className="mt-0.5 truncate text-xs text-muted">
            {store?.location ?? 'Workshop' }
          </p>
        </div>
        {store?.id && (
          <Link
            to={`/makers/${store.id}`}
            className="btn btn-outline shrink-0 text-xs"
          >
            <Store size={14} strokeWidth={2} />
            <span className="hidden sm:inline">Visit workshop</span>
          </Link>
        )}
      </header>

      {/* ── The thread ────────────────────────────────────────────── */}
      <div
        ref={listRef}
        className="mt-5 max-h-[52vh] min-h-[16rem] flex-1 overflow-y-auto pr-1"
      >
        {messagesQuery.isLoading ? (
          <div className="space-y-3">
            {Array.from({ length: 3 }).map((_, index) => (
              <div key={index} className="shimmer h-16 rounded-card" />
            ))}
          </div>
        ) : history === 'failed' ? (
          /* A read that errored is not an empty thread — see
             `ThreadHistoryNotice` for what that mistake costs. */
          <ThreadHistoryNotice state="failed" onRetry={() => messagesQuery.refetch()} />
        ) : messages.length > 0 ? (
          <>
            {/* The history is missing but the live messages are not, so the
                strip goes above them rather than replacing them. */}
            <ThreadHistoryNotice
              state={history}
              onRetry={() => messagesQuery.refetch()}
              className="mb-3"
            />
          <motion.ul
            variants={staggerChildren(0.02)}
            initial="hidden"
            animate="show"
            className="space-y-1.5"
          >
            {messages.map((message, index) => {
              const previous = messages[index - 1]
              const newDay = messageDayKey(previous?.created_at) !== messageDayKey(message.created_at)
              const mine = isMine(message, CUSTOMER_SENDER_TYPE)

              return (
                <motion.li key={message.id} variants={fadeUp}>
                  {newDay && (
                    <p className="my-4 text-center text-[11px] uppercase tracking-[0.12em] text-muted">
                      {messageDayLabel(message.created_at)}
                    </p>
                  )}
                  <MessageBubble
                    message={message}
                    mine={mine}
                    onDelete={() =>
                      remove.mutate({ conversationId, messageId: message.id })
                    }
                  />
                </motion.li>
              )
            })}
          </motion.ul>
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
              Ask about a size, a colour, or a pair you would like made. They will
              get it in the app.
            </p>
          </div>
        )}
      </div>

      {/* ── The composer ──────────────────────────────────────────── */}
      <div className="mt-4 border-t border-hairline pt-4">
        {/*
          The receipt sits under the customer's own last message: `Read` only
          makes sense about something they said. `readReceiptFor` returns null
          when the maker has the last word.
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
          <label htmlFor="message-draft" className="sr-only">
            Your message
          </label>
          <textarea
            id="message-draft"
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
            placeholder={`Message ${name}…`}
            className="min-h-[3.25rem] w-full resize-none rounded-field border border-card-edge bg-raised px-4 py-3 text-sm text-ink placeholder:text-muted focus:border-clay focus:outline-none focus:ring-2 focus:ring-clay/25"
          />
          <button
            type="submit"
            disabled={!draft.trim() || send.isPending}
            className="btn btn-primary h-[3.25rem] shrink-0 px-4"
          >
            <SendHorizontal size={16} strokeWidth={2} />
            <span className="sr-only">Send message</span>
          </button>
        </form>
      </div>

      {user?.email && (
        <p className="mt-3 text-[11px] leading-relaxed text-muted">
          Replies also reach {user.email} and the CUFMAI app.
        </p>
      )}
    </div>
  )
}

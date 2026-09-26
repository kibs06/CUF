import { ImageOff, Trash2 } from 'lucide-react'

import { messageAttachment, messageRelativeTime, messageText } from '../../lib/messageRules.js'

/**
 * One message in a thread — the same bubble on both sides of a conversation.
 *
 * Extracted from the customer's thread when the seller's was built, because a
 * bubble is not a customer or a seller thing: it is a body, an optional
 * attachment, a timestamp, and which side of the column it sits on. Building a
 * second one for the seller would have been a second copy of the one piece of
 * this feature that both parties look at the most.
 *
 * ## What is `mine`
 *
 * `mine` is passed in rather than derived here, because the answer depends on
 * who is reading: the same row is the right-hand clay bubble for the seller who
 * wrote it and the left-hand raised one for the customer who received it. The
 * callers get it from `isMine(message, readerType)`, which reads `sender_type`
 * — never `sender_id`, because a deleted account nulls the id while the type
 * survives.
 *
 * ## The delete control
 *
 * Only on the reader's own messages, and only on hover or keyboard focus: RLS
 * permits deleting your own, and housekeeping is not something to offer on a
 * message you are still reading. The whole bubble is `group`-scoped, so the
 * hover target is the message rather than the page.
 */
export default function MessageBubble({ message, mine, onDelete }) {
  const text = messageText(message)
  const attachment = messageAttachment(message)
  const pending = Boolean(message.pending)

  return (
    <div className={`group flex items-end gap-2 ${mine ? 'justify-end' : 'justify-start'}`}>
      {mine && !pending && (
        <button
          type="button"
          onClick={onDelete}
          title="Delete this message"
          className="mb-1 flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-muted opacity-0 transition-opacity duration-200 hover:bg-crimson/10 hover:text-crimson group-hover:opacity-100 focus-visible:opacity-100"
        >
          <Trash2 size={13} strokeWidth={2} />
          <span className="sr-only">Delete this message</span>
        </button>
      )}

      <div
        className={`max-w-[min(34rem,80%)] rounded-card px-4 py-2.5 text-sm leading-relaxed shadow-card ${
          mine ? 'bg-clay text-ink-inverse' : 'border border-hairline bg-raised text-ink'
        } ${pending ? 'opacity-70' : ''}`}
      >
        {attachment && <Attachment attachment={attachment} />}

        {text && <p className={attachment ? 'mt-2' : ''}>{text}</p>}

        <p className={`num mt-1 text-[11px] ${mine ? 'text-ink-inverse/70' : 'text-muted'}`}>
          {pending ? 'Sending…' : messageRelativeTime(message.created_at)}
        </p>
      </div>
    </div>
  )
}

/**
 * A photo or a video sent from the app.
 *
 * `attachment_url` is already signed and long-lived, so there is nothing to
 * resolve here — but the *video* case has no player in the portal, and a
 * `video` element with no controls would be worse than a link, so a video
 * renders as its thumbnail (or a labelled link) and opens in a new tab.
 */
export function Attachment({ attachment }) {
  if (attachment.type === 'video') {
    return (
      <a
        href={attachment.url}
        target="_blank"
        rel="noreferrer"
        className="block overflow-hidden rounded-product border border-hairline"
      >
        {attachment.thumbnailUrl ? (
          <img
            src={attachment.thumbnailUrl}
            alt=""
            loading="lazy"
            className="h-40 w-full object-cover"
          />
        ) : (
          <span className="flex h-24 items-center justify-center gap-2 bg-subtle text-xs text-muted-strong">
            <ImageOff size={14} strokeWidth={2} />
            Open the video
          </span>
        )}
      </a>
    )
  }

  return (
    <a href={attachment.url} target="_blank" rel="noreferrer" className="block">
      <img
        src={attachment.url}
        alt="Photo sent in this conversation"
        loading="lazy"
        className="max-h-64 w-full rounded-product border border-hairline object-cover"
      />
    </a>
  )
}

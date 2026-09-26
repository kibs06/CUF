import { useRef, useState } from 'react'
import { Camera, Loader2, Trash2 } from 'lucide-react'

import { useAuth } from '../../hooks/useAuth.jsx'
import { getInitials } from '../../lib/constants'
import { avatarFileError } from '../../lib/profile'

/**
 * The customer's profile photo.
 *
 * Uploads the moment a file is chosen, like the app does, rather than holding a
 * pending file until Save. Two reasons: the row and the file would otherwise
 * have to be committed together by two different services (Storage and
 * Postgres) that cannot be made transactional, and a customer who picks a photo
 * and then abandons the page has, with the deferred version, silently lost it.
 *
 * The file input is hidden and driven by the button because a native
 * `<input type="file">` cannot be styled to match anything, and a bare unstyled
 * control in the middle of the card is the one element that would give the page
 * away as a form.
 */
/**
 * `onChanged` fires after the row's `avatar_url` moves, so the form above can
 * drop its "your details are saved" line. Without it, removing a photo leaves a
 * stale save confirmation sitting on screen that has nothing to do with what
 * just happened.
 */
export default function AvatarUpload({ onChanged }) {
  const { profile, uploadAvatar, removeAvatar } = useAuth()
  const inputRef = useRef(null)

  const [pending, setPending] = useState(false)
  const [problem, setProblem] = useState(null)
  const [done, setDone] = useState(false)

  const name = profile?.full_name || profile?.email || ''
  // Verbatim: the `?t=` stamp was written when the file was uploaded, and
  // re-stamping during render would change the string every pass.
  const avatarUrl = profile?.avatar_url || null

  const onPick = async (event) => {
    const file = event.target.files?.[0]
    // Reset the input straight away: without this, choosing the same file again
    // after a failure fires no change event at all, and the retry looks broken.
    event.target.value = ''

    setDone(false)
    const localProblem = avatarFileError(file)
    if (localProblem) {
      setProblem(localProblem)
      return
    }

    setProblem(null)
    setPending(true)
    try {
      await uploadAvatar(file)
      setDone(true)
      onChanged?.()
    } catch (error) {
      setProblem(
        error?.message ?? 'We could not upload that photo. Please try again.',
      )
    } finally {
      setPending(false)
    }
  }

  const onRemove = async () => {
    setDone(false)
    setProblem(null)
    setPending(true)
    try {
      await removeAvatar()
      onChanged?.()
    } catch (error) {
      setProblem(
        error?.message ?? 'We could not remove that photo. Please try again.',
      )
    } finally {
      setPending(false)
    }
  }

  return (
    <div>
      <div className="flex items-center gap-5">
        <div className="relative h-20 w-20 shrink-0 overflow-hidden rounded-full border border-hairline bg-subtle">
          {avatarUrl ? (
            <img
              src={avatarUrl}
              alt=""
              className="h-full w-full object-cover"
              decoding="async"
            />
          ) : (
            <span
              aria-hidden="true"
              className="num flex h-full items-center justify-center text-xl font-semibold text-clay-ink"
            >
              {getInitials(name)}
            </span>
          )}

          {pending && (
            <span className="absolute inset-0 flex items-center justify-center bg-scrim">
              <Loader2
                size={20}
                className="animate-spin text-ink-inverse"
                strokeWidth={2}
              />
            </span>
          )}
        </div>

        <div className="min-w-0">
          <p className="text-sm font-semibold text-ink">Profile photo</p>
          <p className="mt-0.5 text-xs leading-relaxed text-muted">
            JPG, PNG or WebP, up to 5 MB. Shown beside your name in the app and
            on this site.
          </p>

          <div className="mt-3 flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={() => inputRef.current?.click()}
              disabled={pending}
              className="btn btn-outline px-3 py-2 text-xs"
            >
              <Camera size={14} strokeWidth={2} />
              {avatarUrl ? 'Change photo' : 'Add a photo'}
            </button>

            {avatarUrl && (
              <button
                type="button"
                onClick={onRemove}
                disabled={pending}
                className="inline-flex items-center gap-1.5 rounded-field px-3 py-2 text-xs font-semibold text-muted transition-colors duration-200 hover:text-crimson"
              >
                <Trash2 size={14} strokeWidth={2} />
                Remove
              </button>
            )}
          </div>

          <input
            ref={inputRef}
            type="file"
            accept="image/jpeg,image/png,image/webp"
            onChange={onPick}
            className="sr-only"
            aria-label="Choose a profile photo"
          />
        </div>
      </div>

      {done && !pending && (
        <p role="status" className="mt-3 text-xs font-semibold text-olive">
          Photo updated.
        </p>
      )}
      {problem && (
        <p
          role="alert"
          className="mt-3 rounded-field border border-crimson/30 bg-crimson/[0.07] px-3 py-2 text-xs leading-relaxed text-ink"
        >
          {problem}
        </p>
      )}
    </div>
  )
}

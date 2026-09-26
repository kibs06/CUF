/**
 * Cancel a thread's in-flight read — but never its **first** one.
 *
 * ## Why the distinction matters
 *
 * Every optimistic write in a chat (send, delete) starts by cancelling the
 * thread's query. The reason is sound: a revalidation that was already on the
 * wire can land *after* the optimistic bubble and overwrite it with the server's
 * older list, so the message someone just typed disappears for a round trip.
 *
 * But `cancelQueries` on a query that has never resolved is a different act, and
 * the difference is not cosmetic — it is the whole history of the conversation:
 *
 *  * The first load is the only thing that fetches the messages that were there
 *    **before** the thread was opened.
 *  * Postgres Realtime keeps working regardless, so a cancelled first load does
 *    not leave a visibly broken screen — it leaves a thread that fills up from
 *    the bottom as messages arrive, looking perfectly complete while everything
 *    older than the mount is silently absent.
 *  * React Query does not re-run a cancelled query on its own; it comes back on
 *    the next trigger (a refocus, a remount), so the gap can persist for as long
 *    as the tab is open.
 *
 * There is nothing to protect from the cancellation in that case either: with no
 * data on screen, an arriving refetch cannot clobber an optimistic bubble that is
 * the only content there is.
 *
 * ## How the two are told apart
 *
 * By whether the query has ever produced data. React Query keeps that on the
 * query state, and `undefined` is the honest test — an empty thread is `[]`, not
 * `undefined`, and an empty thread *should* have its revalidation cancelled like
 * any other, because there is technically nothing to lose and a stale "no
 * messages yet" is exactly the thing an optimistic send is meant to replace.
 *
 * Awaited like `cancelQueries` itself: the caller is about to write the cache, and
 * a cancel that has not settled is a cancel that can still overwrite it.
 */
export async function cancelThreadRefetch(queryClient, queryKey) {
  if (queryClient.getQueryState(queryKey)?.data === undefined) return
  await queryClient.cancelQueries({ queryKey })
}

import { useCallback, useEffect, useRef } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import {
  CUSTOMER_SENDER_TYPE,
  buildOutgoingMessage,
  deleteMessage,
  fetchConversation,
  fetchConversations,
  fetchMessages,
  fetchUnreadThreadCount,
  findOrCreateConversation,
  markConversationRead,
  mergeMessage,
  needsMarkRead,
  sendMessage,
  subscribeToConversation,
  subscribeToInbox,
} from '../lib/messages.js'
import { supabase } from '../lib/supabase.js'
import { cancelThreadRefetch } from './threadQuery.js'
import { useAuth } from './useAuth.jsx'

/**
 * The inbox, the thread, the badge and every write — the portal's messaging
 * data plane.
 *
 * ## Three cache keys, and what each is for
 *
 *  * `['conversations', userId]` — the inbox list, with a per-thread unread
 *    count. Also where the badge's number comes from once the inbox is open.
 *  * `['conversations-unread', userId]` — the badge alone, for the header on
 *    pages that never show the list.
 *  * `['messages', conversationId]` — one thread's messages.
 *
 * The two inbox keys are invalidated together on every write so a badge can
 * never disagree with the list it is badging, which is the same pairing
 * `useNotifications` uses for the same reason.
 *
 * ## Realtime is a subscription, not a poll
 *
 * `messages` and `conversations` are both in the `supabase_realtime`
 * publication, so the thread and the inbox update themselves. The subscription
 * folds each event through `mergeMessage` (pure and tested) instead of
 * refetching the thread per message: a refetch per keystroke of the other
 * party's chat would be a request per message, and it flashes the list.
 *
 * The channel is created once per conversation id and removed on unmount. Both
 * mounts in `React.StrictMode` are handled by removing the channel in the
 * cleanup — React runs effect, cleanup, effect, and only the second channel
 * survives.
 */

/** The customer's threads, newest activity first, with unread counts. */
export function useConversations() {
  const { user } = useAuth()
  const userId = user?.id ?? null
  const queryClient = useQueryClient()

  const query = useQuery({
    queryKey: ['conversations', userId],
    queryFn: () => fetchConversations(userId),
    enabled: Boolean(userId),
  })

  /*
    The inbox listens to `conversations` rather than to `messages`: the trigger
    already moves `last_message_at` on every insert, so "this thread changed" is
    exactly the event the list needs.
  */
  useEffect(() => {
    if (!userId) return undefined

    const channel = subscribeToInbox(userId, () => {
      queryClient.invalidateQueries({ queryKey: ['conversations', userId] })
      queryClient.invalidateQueries({ queryKey: ['conversations-unread', userId] })
    })

    return () => {
      if (channel) supabaseRemove(channel)
    }
  }, [userId, queryClient])

  return query
}

/**
 * The badge's number — threads with something unread.
 *
 * Separate from `useConversations` because the header renders it on every page,
 * and the inbox query carries a store join for every thread.
 */
export function useUnreadThreadCount() {
  const { user } = useAuth()
  const userId = user?.id ?? null

  return useQuery({
    queryKey: ['conversations-unread', userId],
    queryFn: () => fetchUnreadThreadCount(userId),
    enabled: Boolean(userId),
  })
}

/** One thread's header: the store, and when it was last active. */
export function useConversation(conversationId) {
  const { user } = useAuth()
  const userId = user?.id ?? null

  return useQuery({
    queryKey: ['conversation', conversationId],
    queryFn: () => fetchConversation(conversationId),
    // The header is only worth fetching once there is someone to fetch it for:
    // RLS would return nothing at all to an anonymous caller.
    enabled: Boolean(conversationId && userId),
  })
}

/**
 * One thread's messages, live.
 *
 * Also marks the thread read — but only when there is something to mark, and
 * only once per arrival. `needsMarkRead` gates the round trip and a ref guards
 * against a second call while the first is in flight, because a thread that
 * re-renders on every realtime event would otherwise fire a write per message
 * per render.
 */
export function useMessages(conversationId) {
  const { user } = useAuth()
  const userId = user?.id ?? null
  const queryClient = useQueryClient()
  const queryKey = ['messages', conversationId]
  const markingRef = useRef(false)

  const query = useQuery({
    queryKey,
    queryFn: () => fetchMessages(conversationId),
    enabled: Boolean(conversationId && userId),
  })

  const messageCount = query.data?.length ?? 0
  const needsRead = needsMarkRead(query.data, CUSTOMER_SENDER_TYPE)

  useEffect(() => {
    if (!conversationId || !userId) return undefined

    const channel = subscribeToConversation(conversationId, ({ eventType, row }) => {
      queryClient.setQueryData(queryKey, (current) => mergeMessage(current, { eventType, row }))
      // A new message can move the thread up the inbox and change the badge.
      queryClient.invalidateQueries({ queryKey: ['conversations', userId] })
      queryClient.invalidateQueries({ queryKey: ['conversations-unread', userId] })
    })

    return () => {
      if (channel) supabaseRemove(channel)
    }
    /*
      The dependency list stops at the id on purpose: the channel must not be
      torn down and re-created every time a message arrives, so nothing derived
      from the query data belongs here. `queryKey` is rebuilt per render, which
      is why the stable pieces (id, user, client) are the ones named.
    */
  }, [conversationId, userId, queryClient])

  useEffect(() => {
    if (!conversationId || !userId || !needsRead || markingRef.current) return

    markingRef.current = true
    markConversationRead(conversationId, CUSTOMER_SENDER_TYPE)
      .then(() => {
        // The thread's rows are now read on the server; say so locally without
        // a second read of the whole thread.
        queryClient.setQueryData(queryKey, (current) =>
          (current ?? []).map((message) =>
            message.sender_type === CUSTOMER_SENDER_TYPE ? message : { ...message, is_read: true },
          ),
        )
        queryClient.invalidateQueries({ queryKey: ['conversations', userId] })
        queryClient.invalidateQueries({ queryKey: ['conversations-unread', userId] })
      })
      .catch(() => {
        // A failed mark-read is not worth an error banner: the messages are
        // still on screen, and the next open tries again.
      })
      .finally(() => {
        markingRef.current = false
      })
  }, [conversationId, needsRead, queryClient, queryKey, userId])

  /*
    The tab regaining focus is the safety net for the two things realtime cannot
    deliver: a DELETE (no replica identity on `messages`) and events that
    happened while the socket was down. Same rule the notification feed uses.
  */
  useEffect(() => {
    if (!conversationId) return undefined

    const onFocus = () => {
      queryClient.invalidateQueries({ queryKey })
    }

    window.addEventListener('focus', onFocus)
    return () => window.removeEventListener('focus', onFocus)
  }, [conversationId, queryClient, queryKey])

  return query
}

/**
 * Every write messaging can make.
 *
 * `start` is the odd one out and is not a message: it finds or creates the
 * thread and hands back its id, which is what the maker page's "Message the
 * maker" button needs. Sending, deleting and the read calls all invalidate the
 * inbox and the badge afterwards, because each of them changes the answer to
 * "does this thread need me".
 */
export function useMessageActions() {
  const { user } = useAuth()
  const userId = user?.id ?? null
  const queryClient = useQueryClient()

  /** Both inbox keys, together, always. */
  const invalidateInbox = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ['conversations', userId] })
    queryClient.invalidateQueries({ queryKey: ['conversations-unread', userId] })
  }, [queryClient, userId])

  /**
   * Send a message into a thread.
   *
   * Optimistic, and deliberately so: a chat that waits a round trip before the
   * customer's own words appear reads as broken, and the words are the one
   * thing the client already knows for certain. The optimistic bubble is marked
   * `pending` and carried under a `optimistic-` id, which `mergeMessage`
   * replaces (not duplicates) when the real row arrives from Postgres Realtime
   * or from this mutation's response.
   */
  const send = useMutation({
    mutationFn: ({ conversationId, body, orderReferenceId = null }) => {
      const row = buildOutgoingMessage({
        conversationId,
        customerId: userId,
        body,
        orderReferenceId,
      })
      if (!row) throw new Error('Write something first.')
      return sendMessage(row)
    },
    onMutate: async ({ conversationId, body, orderReferenceId = null }) => {
      const queryKey = ['messages', conversationId]
      await cancelThreadRefetch(queryClient, queryKey)
      const previous = queryClient.getQueryData(queryKey)
      const trimmed = String(body ?? '').trim()

      if (trimmed) {
        queryClient.setQueryData(queryKey, (current) =>
          mergeMessage(current, {
            eventType: 'INSERT',
            row: {
              id: `optimistic-${Date.now()}`,
              conversation_id: conversationId,
              sender_id: userId,
              sender_type: CUSTOMER_SENDER_TYPE,
              body: trimmed,
              order_reference_id: orderReferenceId,
              is_read: false,
              created_at: new Date().toISOString(),
              pending: true,
            },
          }),
        )
      }

      return { previous, queryKey }
    },
    onError: (_error, _variables, context) => {
      if (context?.previous !== undefined) {
        queryClient.setQueryData(context.queryKey, context.previous)
      }
    },
    onSuccess: (row, variables) => {
      if (!row) return
      const queryKey = ['messages', variables.conversationId]
      // Drop the optimistic copy and put the stored row in its place, so the
      // bubble that stays on screen is the one the database actually has.
      queryClient.setQueryData(queryKey, (current) =>
        mergeMessage(
          (current ?? []).filter((message) => !message?.pending),
          { eventType: 'INSERT', row },
        ),
      )
      invalidateInbox()
    },
  })

  /** Delete one of the customer's own messages — removed for both sides. */
  const remove = useMutation({
    mutationFn: ({ messageId }) => deleteMessage(messageId),
    onMutate: async ({ conversationId, messageId }) => {
      const queryKey = ['messages', conversationId]
      await cancelThreadRefetch(queryClient, queryKey)
      const previous = queryClient.getQueryData(queryKey)

      queryClient.setQueryData(queryKey, (current) =>
        mergeMessage(current, { eventType: 'DELETE', row: { id: messageId } }),
      )

      return { previous, queryKey }
    },
    onError: (_error, _variables, context) => {
      if (context?.previous !== undefined) {
        queryClient.setQueryData(context.queryKey, context.previous)
      }
    },
    onSettled: invalidateInbox,
  })

  /**
   * Find the thread with this maker, or open one.
   *
   * Invalidates the inbox afterwards: a brand-new thread has no messages yet
   * and still belongs at the top of the list (that is the `nullsFirst` rule),
   * so a customer who starts a conversation from a maker page and then goes to
   * `/messages` finds it waiting.
   */
  const start = useMutation({
    mutationFn: ({ storeId }) => findOrCreateConversation({ storeId, customerId: userId }),
    onSuccess: invalidateInbox,
  })

  return { send, remove, start }
}

/**
 * Remove a channel.
 *
 * Extracted only so the two cleanups read the same. `removeChannel` unsubscribes
 * and reaps the socket, and it is what keeps `StrictMode`'s double mount from
 * leaving a duplicate subscription behind (effect → cleanup → effect).
 */
function supabaseRemove(channel) {
  supabase.removeChannel(channel)
}

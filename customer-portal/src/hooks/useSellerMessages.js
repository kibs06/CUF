import { useCallback, useEffect, useRef } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import {
  SELLER_SENDER_TYPE,
  buildStoreMessage,
  deleteStoreMessage,
  fetchStoreConversation,
  fetchStoreConversations,
  fetchStoreMessages,
  fetchStoreUnreadThreadCount,
  markStoreConversationRead,
  mergeMessage,
  needsMarkRead,
  sendStoreMessage,
  subscribeToConversation,
} from '../lib/sellerMessages.js'
import { supabase } from '../lib/supabase.js'
import { cancelThreadRefetch } from './threadQuery.js'
import { useAuth } from './useAuth.jsx'

/**
 * The seller's inbox, threads, badge and every write — the seller portal's
 * messaging data plane.
 *
 * A sibling of `useMessages` rather than a role flag on it. Four things differ
 * and each one changes a *query* rather than a render:
 *
 *  1. the rows are found by `store_id`, not `customer_id`;
 *  2. the thread header names a person (`customer_name`) where the customer's
 *     names a store;
 *  3. unread means the customer's messages, not the maker's;
 *  4. replies are inserted by the seller, which the INSERT policy keys on.
 *
 * Folding those into one hook would mean four branches on every call site
 * reading a query that is already the most delicate in the portal, and the
 * customer's path — which is live and correct — would be the thing at risk.
 *
 * ## Four cache keys, and what each is for
 *
 *  * `['seller-conversations', storeId]` — the inbox, with a per-thread unread
 *    count. Also where the badge's number comes from once the inbox is open.
 *  * `['seller-conversations-unread', storeId]` — the badge alone, for the bar
 *    on pages that never show the list.
 *  * `['seller-conversation', conversationId]` — one thread's header.
 *  * `['seller-messages', conversationId]` — one thread's messages.
 *
 * The two inbox keys are invalidated together on every write so a badge can
 * never disagree with the list it is badging — the same pairing the notification
 * hooks use, for the same reason.
 *
 * ## Realtime is a subscription, not a poll
 *
 * `messages` and `conversations` were both added to the `supabase_realtime`
 * publication in the original messaging migration, so these subscriptions
 * actually fire. The inbox channel is opened by the **badge** hook, because the
 * bar mounts it on every seller page and the inbox itself does not; one channel
 * invalidating both inbox keys beats two racing to do the same. The thread
 * channel is per conversation, and it folds each event through `mergeMessage`
 * (pure, tested) rather than refetching — a refetch per incoming message would
 * be a request per message and would flash the list.
 */

/** This store's threads, newest activity first, with unread counts. */
export function useStoreConversations(storeId) {
  return useQuery({
    queryKey: ['seller-conversations', storeId ?? null],
    queryFn: () => fetchStoreConversations(storeId),
    enabled: Boolean(storeId),
  })
}

/**
 * The badge's number — threads with something unread.
 *
 * Separate from `useStoreConversations` because it is drawn on every page, and
 * the inbox query carries a row per customer who has ever written. The realtime
 * channel is not here but in the shell (`SellerLayout`'s `SellerRealtime`), for
 * the same reason the notification badge's is not: three components read this
 * number and only one of them should be opening a socket.
 */
export function useUnreadStoreThreadCount(storeId) {
  return useQuery({
    queryKey: ['seller-conversations-unread', storeId ?? null],
    queryFn: () => fetchStoreUnreadThreadCount(storeId),
    enabled: Boolean(storeId),
  })
}

/** One thread's header: the customer, and when they were last active. */
export function useStoreConversation(conversationId) {
  const { user } = useAuth()

  return useQuery({
    queryKey: ['seller-conversation', conversationId ?? null],
    queryFn: () => fetchStoreConversation(conversationId),
    // Only worth fetching once there is someone to fetch it for: RLS answers
    // nothing at all to anyone else.
    enabled: Boolean(conversationId && user?.id),
  })
}

/**
 * One thread's messages, live.
 *
 * Also marks the customer's messages read — but only when there is something to
 * mark, and only once per arrival. `needsMarkRead` gates the round trip and a
 * ref guards against a second call while the first is in flight, because a
 * thread that re-renders on every realtime event would otherwise fire a write
 * per message per render. The role is the seller's, so a seller opening their
 * own thread never marks their own replies read.
 */
export function useStoreThreadMessages(conversationId) {
  const { user } = useAuth()
  const userId = user?.id ?? null
  const queryClient = useQueryClient()
  const queryKey = ['seller-messages', conversationId]
  const markingRef = useRef(false)

  const query = useQuery({
    queryKey,
    queryFn: () => fetchStoreMessages(conversationId),
    enabled: Boolean(conversationId && userId),
  })

  const needsRead = needsMarkRead(query.data, SELLER_SENDER_TYPE)

  useEffect(() => {
    if (!conversationId || !userId) return undefined

    const channel = subscribeToConversation(conversationId, ({ eventType, row }) => {
      queryClient.setQueryData(queryKey, (current) => mergeMessage(current, { eventType, row }))
      /*
        A new message can move the thread up the inbox and change the badge.
        Invalidated by prefix, without a store id: this hook is given a
        conversation, not a store, and the prefix matches exactly the two inbox
        keys for whichever store this thread belongs to.
      */
      queryClient.invalidateQueries({ queryKey: ['seller-conversations'] })
      queryClient.invalidateQueries({ queryKey: ['seller-conversations-unread'] })
    })

    return () => {
      if (channel) supabase.removeChannel(channel)
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
    markStoreConversationRead(conversationId)
      .then(() => {
        // The rows are read on the server now; say so locally without a second
        // read of the whole thread.
        queryClient.setQueryData(queryKey, (current) =>
          (current ?? []).map((message) =>
            message.sender_type === SELLER_SENDER_TYPE ? message : { ...message, is_read: true },
          ),
        )
        queryClient.invalidateQueries({ queryKey: ['seller-conversations'] })
        queryClient.invalidateQueries({ queryKey: ['seller-conversations-unread'] })
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
    The tab regaining focus is the safety net for the one thing realtime cannot
    deliver: a DELETE (no replica identity on `messages`, so the event carries
    only a primary key and cannot be filtered by conversation). Same rule the
    customer's thread uses.
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
 * Every write the seller's inbox can make.
 *
 * `send` is optimistic, and deliberately so: a chat that waits a round trip
 * before the seller's own words appear reads as broken, and the words are the
 * one thing the client already knows for certain. The optimistic bubble is
 * marked `pending` and carried under an `optimistic-` id, which `mergeMessage`
 * replaces (not duplicates) when the real row arrives from Postgres Realtime or
 * from this mutation's response — the same mechanism, and the same pure fold,
 * as the customer's thread.
 */
export function useSellerMessageActions(storeId) {
  const { user } = useAuth()
  const sellerId = user?.id ?? null
  const queryClient = useQueryClient()

  /** Both inbox keys, together, always. */
  const invalidateInbox = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ['seller-conversations', storeId] })
    queryClient.invalidateQueries({ queryKey: ['seller-conversations-unread', storeId] })
  }, [queryClient, storeId])

  const send = useMutation({
    mutationFn: ({ conversationId, body, orderReferenceId = null }) => {
      const row = buildStoreMessage({ conversationId, sellerId, body, orderReferenceId })
      if (!row) throw new Error('Write something first.')
      return sendStoreMessage(row)
    },
    onMutate: async ({ conversationId, body, orderReferenceId = null }) => {
      const queryKey = ['seller-messages', conversationId]
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
              sender_id: sellerId,
              sender_type: SELLER_SENDER_TYPE,
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
      const queryKey = ['seller-messages', variables.conversationId]
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

  /** Delete one of the shop's own messages — removed for both sides. */
  const remove = useMutation({
    mutationFn: ({ messageId }) => deleteStoreMessage(messageId),
    onMutate: async ({ conversationId, messageId }) => {
      const queryKey = ['seller-messages', conversationId]
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

  return { send, remove }
}

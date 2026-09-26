import { useState } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'
import { motion } from 'motion/react'
import {
  ArrowLeft,
  Banknote,
  CreditCard,
  MapPin,
  MessageSquare,
  PackageX,
  Store,
  XCircle,
} from 'lucide-react'

import EmptyState from '../components/ui/EmptyState'
import Reveal from '../components/ui/Reveal'
import OrderSummaryCard from '../components/checkout/OrderSummaryCard'
import OrderTimeline, { formatMoment } from '../components/orders/OrderTimeline'
import StatusPill from '../components/orders/StatusPill'
import CancelOrderDialog from '../components/orders/CancelOrderDialog'
import MessageMakerDialog from '../components/orders/MessageMakerDialog'
import Skeleton from '../components/ui/Skeleton'
import { fadeUp, staggerChildren } from '../components/motion/transitions'
import { useMessageActions } from '../hooks/useMessages.js'
import { useCancelOrder, useMyOrder } from '../hooks/useOrders.js'
import {
  cancelError,
  cancelPlan,
  fulfilmentLabel,
  isOpenOrder,
  isUnpaidOrder,
  orderLines,
  orderPieces,
  orderTimeline,
  orderTotals,
  shippingAddressLines,
  shortOrderRef,
} from '../lib/orders'
import { isOnlinePayment, paymentMethodLabel } from '../lib/checkout.js'
import { formatCurrency } from '../lib/constants.js'

/**
 * One order, in full.
 *
 * The page is arranged as a receipt and a status board side by side: what was
 * bought and where it is going on the left, what has happened to it and what
 * the customer can still do on the right. That split is the whole design — a
 * customer who has come back to check on an order wants the timeline, and one
 * who has come back to complain wants the lines and the address.
 */
export default function OrderDetail() {
  const { orderId } = useParams()
  const navigate = useNavigate()
  const location = useLocation()
  const { data: order, isLoading, isError, error } = useMyOrder(orderId)

  /*
    Set by the checkout when a **Cash on Pickup** order is placed, because that
    flow navigates here instead of to a payment page: the order already exists
    and there is nothing left to pay online. Read once, into local state, so a
    reload of the page does not keep re-announcing a confirmation.
  */
  const [justPlaced] = useState(() => location.state?.placed === 'cash')

  const [dialogOpen, setDialogOpen] = useState(false)
  const [messageOpen, setMessageOpen] = useState(false)
  const [outcome, setOutcome] = useState(null)
  const [problem, setProblem] = useState(null)
  const [messageProblem, setMessageProblem] = useState(null)
  const cancel = useCancelOrder()
  const { start, send } = useMessageActions()

  /**
   * Write to the maker about THIS order.
   *
   * Two requests and a redirect: find-or-create the one thread with this maker,
   * send the message tagged with the order, then hand the customer the thread —
   * which is where the answer will arrive. `start` is idempotent
   * (`UNIQUE(store_id, customer_id)`), so a customer who already wrote to them
   * about something else keeps that history.
   */
  const onSendMessage = async ({ body }) => {
    setMessageProblem(null)
    try {
      const conversationId = await start.mutateAsync({ storeId: order.store_id })
      await send.mutateAsync({ conversationId, body, orderReferenceId: order.id })
      setMessageOpen(false)
      navigate(`/messages/${conversationId}`)
    } catch (caught) {
      setMessageProblem(caught?.message ?? 'That message could not be sent.')
    }
  }

  const onConfirm = async ({ reason, details }) => {
    setProblem(null)
    try {
      const result = await cancel.mutateAsync({ orderId, reason, details })
      setDialogOpen(false)
      setOutcome(result.requested ? 'requested' : 'cancelled')
    } catch (caught) {
      const mapped = cancelError(caught)
      // A missing migration cannot be fixed by trying again, so the dialog
      // closes and the page says so once, instead of letting the customer
      // press the button a second time.
      if (mapped.notAvailable) {
        setDialogOpen(false)
        setOutcome(null)
        setProblem(mapped.message)
        return
      }
      setProblem(mapped.message)
    }
  }

  if (isLoading) {
    return (
      <div className="mx-auto max-w-5xl px-4 py-10 sm:px-6 lg:px-8">
        <Skeleton className="h-4 w-28" />
        <Skeleton className="mt-6 h-9 w-64" />
        <div className="mt-9 grid gap-6 lg:grid-cols-[1fr_20rem]">
          <Skeleton className="h-96 rounded-card" />
          <Skeleton className="h-64 rounded-card" />
        </div>
      </div>
    )
  }

  if (isError || !order) {
    return (
      <div className="mx-auto max-w-2xl px-4 py-16 sm:px-6">
        <EmptyState
          Icon={PackageX}
          title={isError ? 'We could not load that order' : 'Order not found'}
          description={
            isError
              ? (error?.message ?? 'Please check your connection and try again.')
              : 'That order does not exist, or it belongs to another account.'
          }
          action={
            <Link to="/orders" className="btn btn-primary">
              Back to your orders
            </Link>
          }
        />
      </div>
    )
  }

  const lines = orderLines(order)
  const totals = orderTotals(order)
  const pieces = orderPieces(order)
  const plan = cancelPlan(order)
  const addressLines = shippingAddressLines(order.shipping_address)
  const timeline = orderTimeline(order)
  const unpaid = isUnpaidOrder(order.status)

  return (
    <div className="mx-auto max-w-5xl px-4 py-10 sm:px-6 lg:px-8">
      <Link
        to="/orders"
        className="inline-flex items-center gap-2 text-xs font-semibold text-muted transition-colors duration-200 hover:text-ink"
      >
        <ArrowLeft size={14} strokeWidth={2} />
        All orders
      </Link>

      <header className="mt-6 flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0">
          <p className="overline num">{shortOrderRef(order.id)}</p>
          <h1 className="mt-2 flex items-center gap-2 font-display text-3xl font-semibold text-ink">
            <Store size={20} strokeWidth={1.75} className="shrink-0 text-muted" />
            <span className="truncate">{order.store_name ?? 'The maker'}</span>
          </h1>
          <p className="mt-2 text-sm text-muted">
            {pieces} {pieces === 1 ? 'pair' : 'pairs'} ·{' '}
            {fulfilmentLabel(order)} ·{' '}
            <span>{paymentMethodLabel(order.payment_method)}</span> ·{' '}
            <time dateTime={order.created_at ?? undefined}>
              {formatMoment(order.created_at)}
            </time>
          </p>
        </div>

        <StatusPill status={order.status} className="mt-1" />
      </header>

      {/*
        The Cash on Pickup confirmation. The app shows a full "Order Confirmed"
        screen with the order id, total and payment type; here the order page is
        that screen, and this band is what makes the arrival read as a
        confirmation rather than as "you clicked a link". Nothing about the
        order is marked paid — it is `unpaid` on purpose, and paying is a
        conversation at the studio, not a button.
      */}
      {justPlaced && order.status === 'pending' && (
        <p
          role="status"
          className="mt-6 rounded-field border border-olive/35 bg-olive/[0.09] px-4 py-3 text-sm leading-relaxed text-ink"
        >
          Thank you — your order is with {order.store_name ?? 'the maker'}.
          Keep {' '}
          <span className="num font-semibold">
            {formatCurrency(orderTotals(order).total)}
          </span>{' '}
          in cash for when you collect it. You will get a notification at every
          step.
        </p>
      )}

      {outcome === 'cancelled' && (
        <p
          role="status"
          className="mt-6 rounded-field border border-hairline bg-subtle/70 px-4 py-3 text-sm text-ink"
        >
          This order is cancelled. Message the maker if you would like to order
          the same pair again.
        </p>
      )}
      {outcome === 'requested' && (
        <p
          role="status"
          className="mt-6 rounded-field border border-amber/35 bg-amber/[0.09] px-4 py-3 text-sm text-ink"
        >
          Your cancellation request has been sent. The maker will confirm or
          refuse it, and you will get a notification either way.
        </p>
      )}
      {problem && (
        <p
          role="alert"
          className="mt-6 rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 text-sm leading-relaxed text-ink"
        >
          {problem}
        </p>
      )}

      <div className="mt-9 grid gap-6 lg:grid-cols-[1fr_20rem] lg:gap-8">
        <motion.div
          variants={staggerChildren(0.05)}
          initial="hidden"
          animate="show"
          className="space-y-6"
        >
          <motion.div variants={fadeUp}>
            <OrderSummaryCard
              lines={lines}
              subtotal={totals.subtotal}
              deliveryFee={totals.deliveryFee}
              total={totals.total}
              totalLabel="Order total"
              note="What the maker charged, as recorded when the order was placed."
            />
          </motion.div>

          <motion.section
            variants={fadeUp}
            className="rounded-card border border-hairline bg-raised p-6 shadow-card"
          >
            <h2 className="flex items-center gap-2 font-display text-lg font-semibold text-ink">
              <MapPin size={16} strokeWidth={1.75} className="text-muted" />
              {order.fulfillment === 'delivery' ? 'Delivering to' : 'Workshop'}
            </h2>

            {addressLines.length > 0 ? (
              <address className="mt-3 not-italic text-sm leading-relaxed text-muted-strong">
                {addressLines.map((line) => (
                  <span key={line} className="block">
                    {line}
                  </span>
                ))}
              </address>
            ) : (
              <p className="mt-3 text-sm leading-relaxed text-muted-strong">
                {order.notes || (
                  <span className="text-muted">
                    No delivery address was recorded for this order.
                  </span>
                )}
              </p>
            )}

            {order.store_id && (
              <Link
                to={`/makers/${order.store_id}`}
                className="mt-4 inline-block text-xs font-semibold text-clay-ink underline-offset-4 hover:underline"
              >
                Visit the workshop
              </Link>
            )}
          </motion.section>
        </motion.div>

        <aside className="space-y-6 lg:sticky lg:top-24 lg:self-start">
          <Reveal className="rounded-card border border-hairline bg-raised p-6 shadow-card">
            <h2 className="font-display text-lg font-semibold text-ink">
              What happened
            </h2>
            <OrderTimeline entries={timeline} className="mt-5" />
          </Reveal>

          {unpaid && (
            <Reveal delay={0.05} className="rounded-card border border-amber/35 bg-amber/[0.08] p-5">
              <h2 className="flex items-center gap-2 text-sm font-semibold text-ink">
                <CreditCard size={15} strokeWidth={2} />
                Payment not finished
              </h2>
              <p className="mt-2 text-xs leading-relaxed text-muted-strong">
                This order is still waiting for its GCash payment. You can pick
                it up where you left off, or cancel it there.
              </p>
              <Link
                to={`/checkout/pay/${order.id}`}
                className="btn btn-primary mt-4 w-full"
              >
                Resume payment
              </Link>
            </Reveal>
          )}

          {/*
            Writing to the maker sits ABOVE cancelling: "where is my pair" is a
            far more common reason to open this page than "I want to cancel
            it", and the destructive control should not be the first thing
            under the timeline.
          */}
          {order.store_id && (
            <Reveal delay={0.08} className="rounded-card border border-hairline bg-raised p-5 shadow-card">
              <h2 className="text-sm font-semibold text-ink">Something to ask?</h2>
              <p className="mt-2 text-xs leading-relaxed text-muted">
                Write to {order.store_name ?? 'the maker'} about this order. It
                goes into your thread with them, tagged with the order.
              </p>
              <button
                type="button"
                onClick={() => {
                  setMessageProblem(null)
                  setMessageOpen(true)
                }}
                className="btn btn-outline mt-4 w-full"
              >
                <MessageSquare size={15} strokeWidth={2} />
                Message the maker
              </button>
            </Reveal>
          )}

          {/*
            A cash order is `unpaid` by design, and it is **not** the same state
            as "a GCash payment that never finished": there is no payment to
            resume, so this card states the amount and where to hand it over
            instead of offering a link. The GCash card above is driven by
            `isUnpaidOrder(order.status)`, which is `awaiting_payment` only — so
            the two can never both appear for one order.
          */}
          {!isOnlinePayment(order.payment_method) &&
            order.payment_status === 'unpaid' &&
            isOpenOrder(order.status) && (
              <Reveal delay={0.06} className="rounded-card border border-clay/25 bg-clay/[0.06] p-5">
                <h2 className="flex items-center gap-2 text-sm font-semibold text-ink">
                  <Banknote size={15} strokeWidth={2} />
                  Paying in cash
                </h2>
                <p className="mt-2 text-xs leading-relaxed text-muted-strong">
                  Pay{' '}
                  <span className="num font-semibold text-ink">
                    {formatCurrency(totals.total)}
                  </span>{' '}
                  to {order.store_name ?? 'the maker'} when you collect the pair.
                  Nothing is charged online, and the maker is told the order is
                  theirs to prepare.
                </p>
              </Reveal>
            )}

          {plan.allowed && (
            <Reveal delay={0.1} className="rounded-card border border-hairline bg-raised p-5 shadow-card">
              <h2 className="text-sm font-semibold text-ink">
                {plan.kind === 'request'
                  ? 'Need to cancel?'
                  : 'Changed your mind?'}
              </h2>
              <p className="mt-2 text-xs leading-relaxed text-muted">
                {plan.kind === 'request'
                  ? 'The maker has started work on this pair, so your request will go to them to approve.'
                  : 'Nothing has been made yet — cancelling here is immediate.'}
              </p>
              <button
                type="button"
                onClick={() => {
                  setProblem(null)
                  setDialogOpen(true)
                }}
                className="btn btn-outline mt-4 w-full hover:border-crimson/40 hover:text-crimson"
              >
                <XCircle size={15} strokeWidth={2} />
                Cancel order
              </button>
            </Reveal>
          )}

          {!plan.allowed && isOpenOrder(order.status) && plan.reason && (
            <Reveal delay={0.1} className="rounded-card border border-hairline bg-subtle/60 p-5">
              <p className="text-xs leading-relaxed text-muted-strong">
                {plan.reason}
              </p>
            </Reveal>
          )}
        </aside>
      </div>

      <MessageMakerDialog
        open={messageOpen}
        storeName={order.store_name ?? 'the maker'}
        orderStatus={order.status}
        pending={start.isPending || send.isPending}
        error={messageProblem}
        onClose={() => {
          setMessageOpen(false)
          setMessageProblem(null)
        }}
        onSend={onSendMessage}
      />

      <CancelOrderDialog
        open={dialogOpen}
        plan={plan}
        pending={cancel.isPending}
        error={problem}
        onClose={() => {
          setDialogOpen(false)
          setProblem(null)
        }}
        onConfirm={onConfirm}
      />
    </div>
  )
}

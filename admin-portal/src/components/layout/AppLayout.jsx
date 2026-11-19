import { useState } from 'react'
import { Outlet, useLocation } from 'react-router-dom'
import Sidebar from './Sidebar.jsx'
import TopBar from './TopBar.jsx'

const TITLES = {
  '/': 'Dashboard',
  '/users': 'Users',
  '/seller-applications': 'Seller Applications',
  '/products': 'Products',
  '/banners': 'Banners',
  '/model-requests': '3D Fitting Requests',
  '/orders': 'Orders',
  '/transactions': 'Transactions',
  '/reports': 'Reports',
  '/audit-logs': 'Audit Logs',
  '/analytics': 'Analytics',
  '/settings': 'Settings',
  // The three manual-GCash screens live inside the same shell as everything
  // else, so they need a real title here — without these entries the shell
  // falls back to 'Admin / CUFMAI admin workspace.' above their own heading.
  '/platform-payments': 'Platform GCash',
  '/payment-verification': 'Payment Verification',
  '/refunds': 'Replacements owed',
  '/payouts': 'Payouts',
}

const DESCRIPTIONS = {
  '/': 'What is happening across the store right now.',
  '/users': 'Customer and seller accounts, roles, and access.',
  '/seller-applications': 'Review new seller sign-ups and verification.',
  '/products': 'Catalog, pricing, and product availability.',
  '/banners': 'Home-screen hero banners and their schedule.',
  '/model-requests': 'Seller modelling requests and the live 3D shelf.',
  '/orders': 'Orders from placement through delivery.',
  '/transactions':
    'Paid sales from the POS and the app — plus whether each customer actually has their receipt, and how the payment was confirmed.',
  '/reports': 'Customer reports and the moderation queue.',
  '/audit-logs': 'Read-only trails of admin and seller activity.',
  '/analytics': 'Sales, order, and product trends over time.',
  '/settings': 'Your admin profile, password, and two-factor authentication.',
  '/platform-payments': 'The GCash account customers pay into, plus fees and payout rates.',
  '/payment-verification': 'Proofs from customers, and the money confirmed in the platform account.',
  '/refunds': 'Replacements owed to customers, and the refunds still to send from rejected payment proofs.',
  '/payouts': 'What each store is owed, and the transfers that settle it.',
}

export default function AppLayout() {
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const { pathname } = useLocation()
  const title = TITLES[pathname] ?? 'Admin'
  const subtitle = DESCRIPTIONS[pathname] ?? 'CUFMAI admin workspace.'

  return (
    <div className="admin-3d-shell flex min-h-screen bg-canvas">
      <Sidebar open={sidebarOpen} onClose={() => setSidebarOpen(false)} />
      <main className="flex-1 overflow-x-hidden p-4 lg:p-8 lg:pl-[calc(76px+2rem)]">
        <TopBar
          title={title}
          subtitle={subtitle}
          onMenuClick={() => setSidebarOpen(true)}
        />
        <Outlet />
      </main>
    </div>
  )
}

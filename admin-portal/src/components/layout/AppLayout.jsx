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
}

const DESCRIPTIONS = {
  '/': 'What is happening across the store right now.',
  '/users': 'Customer and seller accounts, roles, and access.',
  '/seller-applications': 'Review new seller sign-ups and verification.',
  '/products': 'Catalog, pricing, and product availability.',
  '/banners': 'Home-screen hero banners and their schedule.',
  '/model-requests': 'Seller modelling requests and the live 3D shelf.',
  '/orders': 'Orders from placement through delivery.',
  '/transactions': 'GCash payments, fees, and webhook events.',
  '/reports': 'Customer reports and the moderation queue.',
  '/audit-logs': 'Read-only trails of admin and seller activity.',
  '/analytics': 'Sales, order, and product trends over time.',
  '/settings': 'Your admin profile, password, and two-factor authentication.',
}

export default function AppLayout() {
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const { pathname } = useLocation()
  const title = TITLES[pathname] ?? 'Admin'
  const subtitle = DESCRIPTIONS[pathname] ?? 'SoleVision admin workspace.'

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

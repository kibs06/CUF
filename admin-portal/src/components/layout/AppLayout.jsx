import { useState } from 'react'
import { Outlet, useLocation } from 'react-router-dom'
import Sidebar from './Sidebar.jsx'
import TopBar from './TopBar.jsx'

const TITLES = {
  '/': 'Dashboard',
  '/users': 'Users',
  '/seller-applications': 'Seller Applications',
  '/products': 'Products',
  '/orders': 'Orders',
  '/transactions': 'Transactions',
  '/analytics': 'Analytics',
  '/settings': 'Settings',
}

export default function AppLayout() {
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const { pathname } = useLocation()
  const title = TITLES[pathname] ?? 'Admin'

  return (
    <div className="flex min-h-screen bg-surface">
      <Sidebar open={sidebarOpen} onClose={() => setSidebarOpen(false)} />
      <main className="flex-1 overflow-x-hidden p-4 lg:p-8">
        <TopBar title={title} onMenuClick={() => setSidebarOpen(true)} />
        <Outlet />
      </main>
    </div>
  )
}

import { useState } from 'react'
import { Outlet, useLocation } from 'react-router-dom'
import Sidebar from './Sidebar.jsx'
import TopBar from './TopBar.jsx'

const TITLES = {
  '/': 'Dashboard',
  '/users': 'Users',
  '/seller-applications': 'Seller Applications',
  '/products': 'Products',
  '/model-requests': '3D Fitting Requests',
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
    <div className="flex min-h-screen bg-canvas">
      <Sidebar open={sidebarOpen} onClose={() => setSidebarOpen(false)} />
      <main className="flex-1 overflow-x-hidden p-4 lg:p-8 lg:pl-[calc(76px+2rem)]">
        <TopBar title={title} onMenuClick={() => setSidebarOpen(true)} />
        <Outlet />
      </main>
    </div>
  )
}

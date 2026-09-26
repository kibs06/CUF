import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

import App from './App.jsx'
import { AuthProvider } from './hooks/useAuth.jsx'
import { CartProvider } from './hooks/useCart.jsx'
import { ThemeProvider } from './hooks/useTheme.jsx'
import './index.css'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // A storefront's catalog changes when a seller publishes something, not
      // second to second. A minute of staleness saves a refetch on every
      // back-navigation, and the cache still renders instantly while a
      // background refetch happens.
      staleTime: 60_000,
      retry: 1,
    },
  },
})

/*
  Provider order, outermost first:

    ThemeProvider     owns a class on <html>, so it depends on nothing
    QueryClientProvider  the cache every data hook reads
    BrowserRouter     the URL
    AuthProvider      the session, and the profile the rest of the app reads
    CartProvider      the cart, which is keyed by the signed-in account and so
                      must sit inside AuthProvider
*/
ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <ThemeProvider>
      <QueryClientProvider client={queryClient}>
        <BrowserRouter>
          <AuthProvider>
            <CartProvider>
              <App />
            </CartProvider>
          </AuthProvider>
        </BrowserRouter>
      </QueryClientProvider>
    </ThemeProvider>
  </React.StrictMode>,
)

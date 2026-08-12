import { useMemo, useState } from 'react'
import { Search, ShoppingBag, Store, Shield } from 'lucide-react'
import { useUsers } from '../hooks/useUsers.js'
import UserSection from '../components/users/UserSection.jsx'
import UserDetailModal from '../components/users/UserDetailModal.jsx'

function UsersSkeleton() {
  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
      {[0, 1].map((i) => (
        <div key={i} className="overflow-hidden rounded-2xl border border-[#D9D0C7] bg-white">
          <div className="h-16 animate-pulse bg-[#F5F0EB]" />
          {[...Array(3)].map((_, j) => (
            <div key={j} className="flex items-center gap-4 border-t border-[#F5F0EB] px-5 py-4">
              <div className="h-10 w-10 flex-shrink-0 animate-pulse rounded-full bg-[#E8DDD5]" />
              <div className="flex-1 space-y-2">
                <div className="h-4 w-32 animate-pulse rounded bg-[#E8DDD5]" />
                <div className="h-3 w-48 animate-pulse rounded bg-[#E8DDD5]" />
              </div>
              <div className="h-6 w-16 animate-pulse rounded-full bg-[#E8DDD5]" />
            </div>
          ))}
        </div>
      ))}
    </div>
  )
}

export default function Users() {
  const { data, isLoading, isError, error } = useUsers()
  const [activeTab, setActiveTab] = useState('All')
  const [statusFilter, setStatusFilter] = useState('All')
  const [search, setSearch] = useState('')
  const [selectedUser, setSelectedUser] = useState(null)

  const { customers = [], sellers = [], admins = [] } = data ?? {}

  const q = search.trim().toLowerCase()

  // Filter by name/email and account status (active vs suspended).
  const filterList = (list) => {
    let out = list
    if (q) {
      out = out.filter(
        (u) => u.full_name?.toLowerCase().includes(q) || u.email?.toLowerCase().includes(q),
      )
    }
    if (statusFilter === 'Active') out = out.filter((u) => !u.suspended)
    if (statusFilter === 'Suspended') out = out.filter((u) => !!u.suspended)
    return out
  }

  const filteredCustomers = useMemo(() => filterList(customers), [customers, q, statusFilter])
  const filteredSellers = useMemo(() => filterList(sellers), [sellers, q, statusFilter])
  const filteredAdmins = useMemo(() => filterList(admins), [admins, q, statusFilter])

  const tabs = [
    { key: 'All', color: 'bg-[#8B5A2B] text-white shadow-sm' },
    { key: 'Customers', color: 'bg-amber-500 text-white shadow-sm', count: customers.length },
    { key: 'Sellers', color: 'bg-[#4ECDC4] text-white shadow-sm', count: sellers.length },
    { key: 'Admins', color: 'bg-[#D64545] text-white shadow-sm', count: admins.length },
  ]

  return (
    <div className="space-y-6">
      {/* Tab bar + Search + Status filter */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap items-center gap-2">
          {tabs.map((tab) => (
            <button
              key={tab.key}
              type="button"
              onClick={() => setActiveTab(tab.key)}
              className={`rounded-xl px-4 py-2 text-sm font-semibold transition-all ${
                activeTab === tab.key
                  ? tab.color
                  : 'border border-[#D9D0C7] bg-white text-[#6B5C4E] hover:bg-[#F5F0EB]'
              }`}
            >
              {tab.key}
              {tab.key !== 'All' && (
                <span
                  className={`ml-2 font-mono text-xs ${
                    activeTab === tab.key ? 'text-white/80' : 'text-[#6B5C4E]'
                  }`}
                >
                  {tab.count}
                </span>
              )}
            </button>
          ))}

          {/* Status filter chips */}
          <span className="mx-1 h-6 w-px bg-[#D9D0C7]" />
          {['All', 'Active', 'Suspended'].map((status) => (
            <button
              key={status}
              type="button"
              onClick={() => setStatusFilter(status)}
              className={`rounded-full px-3 py-1.5 text-xs font-semibold transition-all ${
                statusFilter === status
                  ? status === 'Suspended'
                    ? 'bg-[#D64545] text-white'
                    : 'bg-[#3B2314] text-white'
                  : 'border border-[#D9D0C7] bg-white text-[#6B5C4E] hover:bg-[#F5F0EB]'
              }`}
            >
              {status}
            </button>
          ))}
        </div>

        <div className="relative min-w-[260px]">
          <Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-[#6B5C4E]" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search name or email..."
            className="w-full rounded-xl border border-[#D9D0C7] bg-white py-2.5 pl-9 pr-4 text-sm text-[#3B2314] placeholder-[#6B5C4E] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
          />
        </div>
      </div>

      {/* Loading */}
      {isLoading && <UsersSkeleton />}

      {/* Error */}
      {isError && (
        <div className="rounded-2xl border border-[#D9D0C7] bg-white p-8 text-center">
          <p className="text-sm text-[#D64545]">{error.message}</p>
        </div>
      )}

      {/* Content */}
      {!isLoading && !isError && (
        <>
          {/* All tab — side by side */}
          {activeTab === 'All' && (
            <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
              <UserSection
                title="Customers"
                color="amber"
                icon={<ShoppingBag size={16} />}
                users={filteredCustomers}
                emptyMessage="No customers yet"
                onView={setSelectedUser}
              />
              <UserSection
                title="Sellers"
                color="teal"
                icon={<Store size={16} />}
                users={filteredSellers}
                emptyMessage="No approved sellers yet"
                showSellerStatus
                onView={setSelectedUser}
              />
            </div>
          )}

          {activeTab === 'All' && admins.length > 0 && (
            <div>
              <UserSection
                title="Admins"
                color="red"
                icon={<Shield size={16} />}
                users={filteredAdmins}
                emptyMessage="No admins"
                onView={setSelectedUser}
              />
            </div>
          )}

          {/* Single tab view */}
          {activeTab !== 'All' && (
            <UserSection
              title={activeTab}
              color={
                activeTab === 'Customers'
                  ? 'amber'
                  : activeTab === 'Sellers'
                    ? 'teal'
                    : 'red'
              }
              icon={
                activeTab === 'Customers' ? (
                  <ShoppingBag size={16} />
                ) : activeTab === 'Sellers' ? (
                  <Store size={16} />
                ) : (
                  <Shield size={16} />
                )
              }
              users={
                activeTab === 'Customers'
                  ? filteredCustomers
                  : activeTab === 'Sellers'
                    ? filteredSellers
                    : filteredAdmins
              }
              showSellerStatus={activeTab === 'Sellers'}
              emptyMessage={`No ${activeTab.toLowerCase()} found`}
              onView={setSelectedUser}
            />
          )}
        </>
      )}

      {/* User detail modal */}
      <UserDetailModal
        user={selectedUser}
        onClose={() => setSelectedUser(null)}
      />
    </div>
  )
}

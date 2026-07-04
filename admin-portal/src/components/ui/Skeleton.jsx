export default function Skeleton({ className = '' }) {
  return <div className={`animate-pulse rounded-lg bg-[#E8DDD5] ${className}`} />
}

export function StatCardSkeleton() {
  return (
    <div className="rounded-2xl border border-[#D9D0C7] bg-white p-6">
      <Skeleton className="mb-4 h-12 w-12 rounded-xl" />
      <Skeleton className="mb-2 h-8 w-16" />
      <Skeleton className="h-4 w-24" />
    </div>
  )
}

export function TableSkeleton({ rows = 5, cols = 5 }) {
  return (
    <div className="overflow-hidden rounded-2xl border border-[#D9D0C7] bg-white">
      <div className="bg-[#F5F0EB] px-6 py-4">
        <div className="flex gap-4">
          {Array.from({ length: cols }).map((_, j) => (
            <Skeleton key={j} className="h-3 flex-1 rounded" />
          ))}
        </div>
      </div>
      <div className="divide-y divide-[#F5F0EB]">
        {Array.from({ length: rows }).map((_, i) => (
          <div key={i} className="flex items-center gap-4 px-6 py-4">
            {Array.from({ length: cols }).map((__, j) => (
              <Skeleton key={j} className="h-4 flex-1 rounded" />
            ))}
          </div>
        ))}
      </div>
    </div>
  )
}

export function ChartSkeleton() {
  return <Skeleton className="h-64 w-full rounded-2xl" />
}

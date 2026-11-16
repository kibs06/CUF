export default function Skeleton({ className = '' }) {
  return <div className={`animate-pulse rounded-lg bg-faint ${className}`} />
}

export function StatCardSkeleton() {
  return (
    <div className="rounded-xl border border-border bg-white px-4 py-3.5">
      <Skeleton className="h-3 w-20" />
      <Skeleton className="mt-3 h-6 w-24" />
      <Skeleton className="mt-2.5 h-3 w-28" />
    </div>
  )
}

export function TableSkeleton({ rows = 5, cols = 5 }) {
  return (
    <div className="overflow-hidden rounded-xl border border-border bg-white">
      <div className="border-b border-border bg-canvas/60 px-4 py-2.5">
        <div className="flex gap-4">
          {Array.from({ length: cols }).map((_, j) => (
            <Skeleton key={j} className="h-3 flex-1 rounded" />
          ))}
        </div>
      </div>
      <div className="divide-y divide-border">
        {Array.from({ length: rows }).map((_, i) => (
          <div key={i} className="flex items-center gap-4 px-4 py-3.5">
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
  return <Skeleton className="h-64 w-full rounded-xl" />
}

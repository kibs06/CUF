export default function StatCard({ icon, label, value, highlight = false, iconBg = 'rgba(139,90,43,0.1)', iconColor = '#8B5A2B' }) {
  return (
    <div
      className={`rounded-2xl border border-[#D9D0C7] bg-white p-6 shadow-sm transition-shadow hover:shadow-md ${
        highlight ? 'ring-2 ring-[#E8A020]/40' : ''
      }`}
    >
      {/* Icon with colored background */}
      <div
        className="mb-4 flex h-12 w-12 items-center justify-center rounded-xl"
        style={{ background: iconBg }}
      >
        <span style={{ color: iconColor }} className="text-lg">{icon}</span>
      </div>

      {/* Number in JetBrains Mono */}
      <p className="font-mono text-3xl font-bold text-[#3B2314] mb-1">{value}</p>

      {/* Label */}
      <p className="text-sm font-medium text-[#6B5C4E]">{label}</p>
    </div>
  )
}

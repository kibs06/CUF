export default function DataTable({ columns, rows, rowKey = 'id', onRowClick, emptyMessage = 'No data' }) {
  if (!rows?.length) {
    return (
      <div className="flex flex-col items-center justify-center rounded-2xl border border-[#D9D0C7] bg-white px-6 py-16 text-center">
        <p className="text-sm text-[#6B5C4E]">{emptyMessage}</p>
      </div>
    )
  }

  return (
    <div className="overflow-x-auto rounded-2xl border border-[#D9D0C7] bg-white shadow-sm">
      <table className="min-w-full text-left text-sm">
        <thead className="bg-[#F5F0EB]">
          <tr>
            {columns.map((col) => (
              <th
                key={col.key}
                className="whitespace-nowrap px-6 py-4 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]"
              >
                {col.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-[#F5F0EB]">
          {rows.map((row) => (
            <tr
              key={row[rowKey]}
              onClick={onRowClick ? () => onRowClick(row) : undefined}
              className={`transition-colors hover:bg-[#FBF8F5] ${
                onRowClick ? 'cursor-pointer' : ''
              }`}
            >
              {columns.map((col) => (
                <td key={col.key} className="whitespace-nowrap px-6 py-4">
                  {col.render ? col.render(row) : row[col.key]}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

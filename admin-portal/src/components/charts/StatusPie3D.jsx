import { useEffect, useRef } from 'react'
// ESM builds default-export the composed Highcharts namespace,
// so 3D + accessibility register by import (no init call).
import Highcharts from 'highcharts/esm/highcharts-3d.js'
import 'highcharts/esm/modules/accessibility.js'
import { attachChartContextMenu } from './chartContextMenu.js'

function humanizeStatus(value) {
  const s = String(value ?? '').replace(/_/g, ' ')
  return s.charAt(0).toUpperCase() + s.slice(1)
}

/**
 * Orders-by-status rendered as a Highcharts 3D pie, mirroring the
 * options3d reference (alpha 45, depth 35, selectable slices,
 * name data-labels, percentage tooltips). The largest slice renders
 * sliced/selected, like Xiaomi in the reference.
 */
export default function StatusPie3D({ data, colors }) {
  const mountRef = useRef(null)
  const signature = JSON.stringify(data)

  useEffect(() => {
    const rows = JSON.parse(signature)
    if (!mountRef.current || rows.length === 0) return undefined

    const max = Math.max(...rows.map((r) => r.value))
    const points = rows.map((r) => ({
      name: humanizeStatus(r.name),
      y: r.value,
      ...(r.value === max ? { sliced: true, selected: true } : {}),
    }))

    const chart = Highcharts.chart(mountRef.current, {
      chart: {
        type: 'pie',
        backgroundColor: 'transparent',
        options3d: {
          enabled: true,
          alpha: 45,
          beta: 0,
        },
        style: { fontFamily: 'DM Sans, sans-serif' },
      },
      title: { text: null },
      credits: { enabled: false },
      exporting: { buttons: { contextButton: { enabled: false } } },
      accessibility: {
        point: { valueSuffix: ' orders' },
      },
      tooltip: {
        pointFormat: '{series.name}: <b>{point.y} ({point.percentage:.1f}%)</b>',
      },
      plotOptions: {
        pie: {
          allowPointSelect: true,
          cursor: 'pointer',
          depth: 35,
          colors,
          dataLabels: {
            enabled: true,
            format: '{point.name}',
            style: { color: '#3B2314', fontWeight: '600' },
          },
        },
      },
      series: [
        {
          type: 'pie',
          name: 'Orders',
          data: points,
        },
      ],
    })

    const detachMenu = attachChartContextMenu(chart, {
      filename: 'orders-by-status',
      getCsvRows: () => [
        ['Status', 'Orders'],
        ...rows.map((r) => [humanizeStatus(r.name), r.value]),
      ],
    })

    return () => {
      detachMenu()
      chart.destroy()
    }
  }, [signature, colors])

  return <div ref={mountRef} role="img" aria-label="Orders by status, 3D pie chart" />
}

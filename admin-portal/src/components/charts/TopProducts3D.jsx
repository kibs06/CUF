import { useEffect, useRef } from 'react'
import Highcharts from 'highcharts/esm/highcharts-3d.js'
import 'highcharts/esm/modules/accessibility.js'
import { attachChartContextMenu } from './chartContextMenu.js'

/**
 * Top products rendered as a Highcharts 3D column chart, mirroring the
 * options3d reference (alpha 15, beta 15, depth 50, viewDistance 25,
 * column depth 25, category axis, no legend). Columns are colored per
 * product from the warm palette; the tooltip also names the seller.
 */
const PALETTE = ['#8B5A2B', '#C49A6C', '#E8A020', '#4ECDC4', '#3B82F6', '#8B5CF6', '#D64545', '#6B8E5A', '#B4654A', '#8A7CA8']

export default function TopProducts3D({ items }) {
  const mountRef = useRef(null)
  const signature = JSON.stringify(items)

  useEffect(() => {
    const rows = JSON.parse(signature)
    if (!mountRef.current || rows.length === 0) return undefined

    const chart = Highcharts.chart(mountRef.current, {
      chart: {
        type: 'column',
        backgroundColor: 'transparent',
        options3d: {
          enabled: true,
          alpha: 15,
          beta: 15,
          depth: 50,
          viewDistance: 25,
        },
        style: { fontFamily: 'DM Sans, sans-serif' },
      },
      title: { text: null },
      credits: { enabled: false },
      exporting: { buttons: { contextButton: { enabled: false } } },
      accessibility: {
        point: { valueSuffix: ' units' },
      },
      xAxis: {
        type: 'category',
        labels: {
          rotation: -25,
          style: { fontSize: '11px', color: '#6B5C4E' },
        },
      },
      yAxis: {
        title: { enabled: false },
        labels: { style: { fontSize: '11px', color: '#6B5C4E' } },
      },
      tooltip: {
        headerFormat: '<b>{point.key}</b><br>',
        pointFormat: 'Units sold: <b>{point.y}</b><br>Seller: {point.custom.store}',
      },
      legend: { enabled: false },
      plotOptions: {
        column: {
          depth: 25,
          colorByPoint: true,
          colors: PALETTE,
          dataLabels: {
            enabled: true,
            format: '{point.y}',
            style: { color: '#3B2314', fontWeight: '600' },
          },
        },
      },
      series: [
        {
          name: 'Units sold',
          data: rows.map((item) => ({
            name: item.name,
            y: item.count,
            custom: { store: item.store ?? '—' },
          })),
        },
      ],
    })

    const detachMenu = attachChartContextMenu(chart, {
      filename: 'top-products',
      getCsvRows: () => [
        ['Product', 'Units sold', 'Seller'],
        ...rows.map((item) => [item.name, item.count, item.store ?? '—']),
      ],
    })

    return () => {
      detachMenu()
      chart.destroy()
    }
  }, [signature])

  return <div ref={mountRef} role="img" aria-label="Top products by units sold, 3D column chart" />
}

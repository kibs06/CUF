import { motion } from 'motion/react'

import ProductCard from './ProductCard'
import { staggerChildren } from '../motion/transitions'

/**
 * The product grid.
 *
 * The stagger lives on this container and the entrance variants live on the
 * card, which is what lets a filtered grid animate only the tiles that actually
 * changed: motion keys off React's keys, so tiles that survive a category
 * change stay put while the new ones walk in. Re-animating the whole grid on
 * every filter click looks busy and costs the customer time they are trying to
 * save.
 *
 * Column counts step with the viewport (2 → 3 → 4) rather than staying at the
 * app's fixed two: a desktop storefront showing two huge tiles is the reason
 * the phone layout was not simply stretched to fit here.
 */
export default function ProductGrid({ products, className = '' }) {
  return (
    <motion.div
      variants={staggerChildren()}
      initial="hidden"
      animate="show"
      className={`grid grid-cols-2 gap-x-4 gap-y-6 sm:gap-x-5 md:grid-cols-3 xl:grid-cols-4 ${className}`}
    >
      {products.map((product) => (
        <ProductCard key={product.id} product={product} />
      ))}
    </motion.div>
  )
}

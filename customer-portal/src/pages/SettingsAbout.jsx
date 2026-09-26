import { Link } from 'react-router-dom'
import { ArrowLeft, BadgeCheck, Hammer, ScrollText, Users } from 'lucide-react'

import Reveal from '../components/ui/Reveal'

/**
 * About CUFMAI.
 *
 * The copy is the association's own, carried across from
 * `lib/screens/shared/about_cufmai_screen.dart` — the same four sections, the
 * same paragraphs. It is worth knowing that it is *copied*: this text describes
 * an organization, so it is the one kind of content where the two clients
 * disagreeing would be a factual problem rather than a styling one.
 *
 * The only edit is the sentence that says "this app": on the web the customer
 * is reading the storefront, and starting that paragraph with "this app" would
 * be the tell that the page was written for something else.
 */
const SECTIONS = [
  {
    Icon: Users,
    title: 'Who We Are',
    paragraphs: [
      'CUFMAI (Carcar United Footwear Manufacturers Association, Inc.) is a manufacturers\u2019 association based in Carcar City, Cebu, Philippines — long known as the "Footwear Capital of the South." Shoemaking is a generations-old heritage craft in Carcar, centered in the barangays of Poblacion 3, Liburon, and Valladolid.',
      'CUFMAI was formally organized in 2004 to unite the town\u2019s independent shoemakers into a single body, turning a scattered craft tradition into an organized local industry.',
    ],
  },
  {
    Icon: Hammer,
    title: 'What We Do',
    paragraphs: [
      'Bulk purchasing of raw materials — leather and other supplies — so member manufacturers can access lower costs than buying individually.',
      'Shared production facilities and equipment, including cutting, stitching, and sole-pressing machinery, that member manufacturers can use to produce faster and more consistently.',
      'A shared retail and display center in Barangay Valladolid where member manufacturers sell their footwear under one roof.',
      'Advocacy and coordination with government agencies like DTI to bring training, funding, and market access to local shoemakers.',
    ],
  },
  {
    Icon: BadgeCheck,
    title: 'Our Members',
    paragraphs: [
      'CUFMAI\u2019s members are independent, DTI-registered shoe and sandal manufacturers based in Carcar City, most concentrated in Barangay Valladolid. Membership is limited to manufacturers who are formally registered, pay local taxes, and follow the association\u2019s by-laws — a deliberate choice to keep membership made up of legitimate, accountable businesses.',
    ],
  },
  {
    Icon: ScrollText,
    title: 'Our Heritage, Our Future',
    paragraphs: [
      'Carcar\u2019s shoemaking tradition has faced real challenges in recent years — competition from cheap imported footwear and a shift toward online shopping have made things harder for many local manufacturers.',
      'This storefront exists to help meet that shift head-on: giving CUFMAI\u2019s member manufacturers a direct digital storefront to reach customers who now shop online, while keeping the craftsmanship, heritage, and community behind every pair rooted in Carcar.',
    ],
  },
]

export default function SettingsAbout() {
  return (
    <div className="mx-auto max-w-2xl px-4 py-10 sm:px-6 lg:px-8">
      <Link
        to="/settings"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-muted transition-colors duration-200 hover:text-ink"
      >
        <ArrowLeft size={14} strokeWidth={2} />
        Settings
      </Link>

      <header className="mt-4">
        <p className="overline">Legal</p>
        <h1 className="mt-2 font-display text-3xl font-semibold text-ink">
          About CUFMAI
        </h1>
        <p className="mt-2 text-sm text-muted">
          Organized 2004 · Carcar City, Cebu
        </p>
      </header>

      <div className="mt-8 space-y-4">
        {SECTIONS.map(({ Icon, title, paragraphs }, index) => (
          <Reveal
            key={title}
            delay={Math.min(index * 0.05, 0.2)}
            className="rounded-card border border-hairline bg-raised p-6 shadow-card"
          >
            <div className="flex items-center gap-3">
              <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-premium bg-clay/10">
                <Icon size={18} className="text-clay-ink" strokeWidth={1.75} />
              </span>
              <h2 className="font-display text-xl font-semibold text-ink">
                {title}
              </h2>
            </div>

            <div className="mt-4 space-y-3">
              {paragraphs.map((paragraph) => (
                <p
                  key={paragraph.slice(0, 24)}
                  className="text-sm leading-relaxed text-muted-strong"
                >
                  {paragraph}
                </p>
              ))}
            </div>
          </Reveal>
        ))}
      </div>

      <footer className="mt-10 border-t border-hairline pt-6 text-xs leading-relaxed text-muted">
        <p className="font-semibold text-muted-strong">
          Carcar United Footwear Manufacturers Association, Inc.
        </p>
        <p className="mt-1">Carcar City, Cebu, Philippines</p>
      </footer>
    </div>
  )
}

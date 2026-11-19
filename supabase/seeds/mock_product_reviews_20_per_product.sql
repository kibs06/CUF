-- ══════════════════════════════════════════════════════════════════
-- MOCK PRODUCT REVIEWS — 40 reviewers, 20 reviews for every product
-- Date: 2026-11-19
-- ══════════════════════════════════════════════════════════════════
-- WHAT THIS DOES
--   • Creates 40 mock customer accounts whose emails read like ordinary
--     Gmail addresses. No password is set, so none of them can actually
--     sign in — they exist only to own a review.
--   • Gives EVERY product exactly 20 reviews. `reviews` needs a real
--     order_item_id, so each product gets one mock order carrying twenty
--     line items (one per review).
--   • Ratings are 3, 4 or 5 only (the brief: random 3-5, no 1-2 stars).
--     The text mixes English, Tagalog and Bisaya and includes both
--     glowing reviews and disappointed ones (the 3-star band).
--   • Adds the social layer on top: helpful / not-helpful votes (the
--     thumbs on each card), discussion comments under reviews, and ONE
--     pinned review per product (the seller spotlight).
--   • Makes each product's SOLD counter equal its review count, so the
--     card reads "20 reviews • 20 sold" instead of "20 reviews • 2 sold".
--     Sold is `SUM(order_items.quantity)` over paid, non-cancelled orders,
--     so this is done with one paid mock order per product whose single
--     line carries the missing units. ⚠️ Those paid orders DO count in
--     seller revenue / sales analytics — see the note at section 4c.
--   • Writes to public.reviews — the table the app reads
--     (ReviewService.getReviews) — so each product page shows the
--     reviewer name, stars, date and comment. products.avg_rating /
--     review_count and stores.rating are refreshed by the existing
--     triggers on that table.
--
-- WHAT IT DELIBERATELY DOES NOT DO
--   • No stock movement: the inventory trigger is switched off for this
--     transaction, because mock line items must never take real stock.
--     (Orders do count as sales — see section 4c.)
--   • No notifications: the order-insert bell trigger only fires for
--     'pending' orders.
--   • No seller replies (the discussion is customer-to-customer).
--   • No 1- or 2-star reviews.
--
-- HOW TO RUN
--   Supabase Dashboard → SQL Editor → paste this whole file → Run.
--   or:
--     supabase db query --linked -f supabase/seeds/mock_product_reviews_20_per_product.sql
--   Safe to re-run: every row gets a deterministic id and inserts with
--   ON CONFLICT DO NOTHING, so a second run changes nothing.
--
-- TO UNDO
--   See the CLEANUP block at the bottom of this file.
-- ══════════════════════════════════════════════════════════════════

begin;

create extension if not exists "pgcrypto";

-- ─────────────────────────────────────────────────────────────────
-- 1. THE FORTY REVIEWERS
--    Names are the class list from the brief, in natural "First Last"
--    order so they read like real Gmail accounts.
-- ─────────────────────────────────────────────────────────────────
drop table if exists _mock_reviewers;
create temp table _mock_reviewers (
  idx       int primary key,
  full_name text not null,
  email     text not null unique
) on commit drop;

insert into _mock_reviewers (idx, full_name, email) values
  (1,  'Keith Vincent Abalo',      'keithvincent.abalo@gmail.com'),
  (2,  'Maria Xhyrra Abalo',       'mariaxhyrra.abalo@gmail.com'),
  (3,  'Steven Balasabas',         'steven.balasabas@gmail.com'),
  (4,  'Angel Mae Briones',        'angelmae.briones@gmail.com'),
  (5,  'Jhonel Vincent Cabardo',   'jhonelvincent.cabardo@gmail.com'),
  (6,  'Lovely Cacayan',           'lovely.cacayan@gmail.com'),
  (7,  'Jennifer Jean Caparida',   'jenniferjean.caparida@gmail.com'),
  (8,  'Mark Clyde Castillote',    'markclyde.castillote@gmail.com'),
  (9,  'Kurt Andrei Dugaduga',     'kurtandrei.dugaduga@gmail.com'),
  (10, 'Joshua Mark Encabo',       'joshuamark.encabo@gmail.com'),
  (11, 'Quizzel Espinosa',         'quizzel.espinosa@gmail.com'),
  (12, 'Ludemae Flores',           'ludemae.flores@gmail.com'),
  (13, 'Ian Geraldez',             'ian.geraldez@gmail.com'),
  (14, 'Jessa Iyas',               'jessa.iyas@gmail.com'),
  (15, 'Shaine Jayme',             'shaine.jayme@gmail.com'),
  (16, 'Juls Frederick Laborte',   'julsfrederick.laborte@gmail.com'),
  (17, 'Krisha Mae Laput',         'krishamae.laput@gmail.com'),
  (18, 'Mitch Maria Paula Larumbe','mitchmariapaula.larumbe@gmail.com'),
  (19, 'Sylvan Niño Vee Mangubat', 'sylvanino.mangubat@gmail.com'),
  (20, 'Jherico Maurin',           'jherico.maurin@gmail.com'),
  (21, 'Kimberly Miranda',         'kimberly.miranda@gmail.com'),
  (22, 'Roljune Monterona',        'roljune.monterona@gmail.com'),
  (23, 'Mc Gerald Von Rich Nebril','mcgeraldvonrich.nebril@gmail.com'),
  (24, 'Bea Dolly Nicor',          'beadolly.nicor@gmail.com'),
  (25, 'Donald Obeso',             'donald.obeso@gmail.com'),
  (26, 'Gwen Paragoso',            'gwen.paragoso@gmail.com'),
  (27, 'Rhamces Pecidas',          'rhamces.pecidas@gmail.com'),
  (28, 'Christian Jade Pesiao',    'christianjade.pesiao@gmail.com'),
  (29, 'Cassandra Jade Ponce',     'cassandrajade.ponce@gmail.com'),
  (30, 'Althea Angela Ponte',      'altheaangela.ponte@gmail.com'),
  (31, 'Mark June Repunte',        'markjune.repunte@gmail.com'),
  (32, 'Ria Grace Requinto',       'riagrace.requinto@gmail.com'),
  (33, 'Maria Ina Ricablanca',     'mariaina.ricablanca@gmail.com'),
  (34, 'Christian Salinas',        'christian.salinas@gmail.com'),
  (35, 'Ryan Dave Sasuman',        'ryandave.sasuman@gmail.com'),
  (36, 'Leira Mae Señor',          'leira.mae.senor@gmail.com'),
  (37, 'Loui Tajanlangit',         'loui.tajanlangit@gmail.com'),
  (38, 'Roegie Tapic',             'roegie.tapic@gmail.com'),
  (39, 'Dave Carl Ubas',           'davecarl.ubas@gmail.com');

-- ─────────────────────────────────────────────────────────────────
-- 2. LOGIN ACCOUNTS (auth.users + auth.identities)
--    Password is NULL on purpose: a mock reviewer must not be a door
--    into the app.
-- ─────────────────────────────────────────────────────────────────
do $seed$
declare
  v_instance_id uuid;
begin
  select id into v_instance_id from auth.instances limit 1;

  insert into auth.users (
    instance_id, id, aud, role,
    email, encrypted_password, email_confirmed_at,
    created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    is_super_admin, confirmation_sent_at
  )
  select
    v_instance_id,
    md5('sole-mock-reviewer:' || r.idx)::uuid,
    'authenticated', 'authenticated',
    r.email,
    null,
    now(),
    now() - interval '400 days', now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', r.full_name),
    false, now()
  from _mock_reviewers r
  on conflict do nothing;

  insert into auth.identities (
    provider_id, user_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  )
  select
    u.id::text, u.id,
    jsonb_build_object('sub', u.id::text, 'email', u.email),
    'email', null, now(), now()
  from auth.users u
  join _mock_reviewers r on r.email = u.email
  on conflict (provider, provider_id) do nothing;
end
$seed$;

-- ─────────────────────────────────────────────────────────────────
-- 3. PROFILES (the name the review card shows)
-- ─────────────────────────────────────────────────────────────────
insert into public.profiles (id, full_name, email, role)
select u.id, r.full_name, r.email, 'customer'
from _mock_reviewers r
join auth.users u on u.email = r.email
on conflict do nothing;

-- ─────────────────────────────────────────────────────────────────
-- 4a. KEEP MOCK LINE ITEMS OUT OF INVENTORY
--     order_items carries a trigger that takes stock for EVERY inserted
--     line, whatever the parent order's status. Mock reviews must never
--     move real stock, so that one trigger is switched off for this
--     transaction and put back in section 4g. If anything fails, the
--     rollback restores it together with the data.
-- ─────────────────────────────────────────────────────────────────
do $seed$
declare
  v_trigger text;
begin
  for v_trigger in
    select t.tgname
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'order_items'
      and not t.tgisinternal
      and t.tgfoid = to_regprocedure('public.decrement_inventory_on_order()')
  loop
    execute format('alter table public.order_items disable trigger %I', v_trigger);
  end loop;
end
$seed$;

-- ─────────────────────────────────────────────────────────────────
-- 4b. TWENTY REVIEWS PER PRODUCT
--    One 'cancelled' mock order per product carries the twenty line
--    items; each line item then owns exactly one review.
--    Ratings and comments are derived from a hash of (product,
--    reviewer), so a re-run reproduces the same rows instead of
--    reshuffling the page.
-- ─────────────────────────────────────────────────────────────────
do $seed$
declare
  v_product   record;
  v_reviewer  record;
  v_buyer_id  uuid;
  v_reviewer_id uuid;
  v_order_id  uuid;
  v_item_id   uuid;
  v_review_id uuid;
  v_idx       int;
  v_i         int;
  v_hash      bigint;
  v_rating    int;
  v_comment   text;
  v_order_ts  timestamptz;
  v_review_ts timestamptz;
  v_sizes     text[] := array['6', '7', '8', '9', '10', '11'];

  -- 5-star: delighted, English / Tagalog / Bisaya
  v_good5 text[] := array[
    'Sobrang worth it! The leather is soft and the stitching is clean. Fits true to size.',
    'Ang ganda ng quality! Mas maganda pa sa picture. Sulit ang bayad.',
    'Nindot kaayo ang sapatos! Comfortable kaayo bisag tibuok adlaw maglakaw.',
    'Ordered on Monday, arrived Wednesday. Packaging was neat and it smells like real leather.',
    'Sakto ang size 8 nako. Very comfortable, wala koy blisters bisag bag-o pa.',
    'Grabe ang craftsmanship. You can really tell it was handmade. Will order again.',
    'Gipangita nako ni nga design dugay na. Perfect kaayo ang fit, dili sakit sa tiil.',
    'Bought this for my graduation and got compliments all day. Worth every peso.',
    'Ang gaan suotin at hindi mainit sa paa. Perfect for everyday office wear.',
    'Legit leather. Two months in, it still looks new. Very happy with this purchase.',
    'Customer service replied within minutes and helped me pick the right size.',
    'Dili ka magmahay. Barato na, lig-on pa. Ako na pud gipalitan akong igsoon.',
    'The color is exactly like the photos. The sole is thick but still flexible.',
    'Best purchase this year. Fits perfectly and the finish is very neat.',
    'Sulit talaga. I wore it to a wedding and everyone asked where I bought it.',
    'Mas comfortable pa ni sa branded shoes nga akong gisul-ob sa una. Highly recommended.',
    'Delivery was fast, the item was well packed, and the size chart was accurate.',
    'Ang lambot ng leather, walang masakit kahit bagong suot. Five stars!',
    'Perfect fit for wide feet. Finally found a pair that does not squeeze my toes.',
    'Gusto nako ang detalye sa tahi. Klaro kaayo ang quality sa pagkahimo.',
    'Very satisfied. I ordered a second pair in black the same week.',
    'Ang ganda ng kulay at hindi dumudulas kahit umuulan. Worth it.',
    'Nindot og humot pa ang bag-ong sapatos. Dili bug-at sa tiil.',
    'This is my third order from this shop. Consistent quality every time.',
    'Napaka-pulido ng pagkakagawa. Even the inside lining is soft. Thank you, seller!',
    'Sulit gyud kaayo! Gwapo kaayo sa tiil ug sakto ang sukod. Mopalit ko usab.'
  ];

  -- 4-star: happy with one small complaint
  v_good4 text[] := array[
    'Nice quality for the price. Medyo masikip lang sa first wear pero okay na after a few days.',
    'Maganda ang sapatos, though the delivery took five days instead of the promised three.',
    'Comfortable and true to size. Sana may mas maraming color options.',
    'Lig-on ug gwapo ang sapatos. Medyo dako lang og gamay ang size 9 para nako.',
    'Good leather and neat stitching. The box arrived slightly dented but the pair was fine.',
    'Sulit sa presyo. Ang sole lang medyo gahi sa sugod, pero humok ra kadugayan.',
    'Fit is good and it looks premium. I just wish the insole had more cushion.',
    'Okay ang quality. Mas maganda sana kung may free shoe bag.',
    'Nice pair overall. Medyo nihit ang stock sa akong size, mao nalang ang napalit nako.',
    'Comfortable for walking. The color is a little darker than the photo pero gwapo gihapon.',
    'Solid craftsmanship. The laces feel a bit thin, but that is easy to replace.',
    'Happy with the purchase. Delivery to Cebu took a week, but the seller kept me updated.',
    'Bagay kaayo sa akong uniform sa trabaho. Ang packaging lang ang pwede pa ma-improve.',
    'Good buy. Medyo mahal ang shipping pero worth naman ang item.',
    'Quality is better than expected. The size runs half a size small, so order up.',
    'Comfortable after breaking in. The first two days medyo masakit sa likod ng ankle.',
    'Ganda ng gawa. Sana lang may mas malaking size para sa mga wide feet.',
    'Maayos ang pagkakatahi at matibay ang sole. Medyo mabigat lang compared sa iba.',
    'Works well for daily use. The smell of the dye lingered for a couple of days.',
    'Nice shoes and fast reply from the seller. A bit pricey for a local brand but okay.'
  ];

  -- 3-star: the disappointed band (the "bad" reviews)
  v_low3 text[] := array[
    'Medyo nadisappoint ako. The color is different from the photo and the fit is loose.',
    'Dili ko ganahan sa quality sa sole. Nagsugod na og buak after two weeks.',
    'The size chart is not accurate. I ordered 8 but it feels like a 9.',
    'Okay lang, nothing special. Medyo mahal para sa quality na nakuha ko.',
    'The stitching near the toe already came loose on the second wear. Disappointing.',
    'Late ang delivery ng five days and walang update from the seller.',
    'Medyo sakit sa tiil kung maglakaw og dugay. Dili siya para sa whole-day use.',
    'The leather looks synthetic up close. Not what I expected for this price.',
    'Maluwag ang fit bisag sakto ang size nga gipili nako. Kinahanglan pa og thicker socks.',
    'The item arrived with a small scratch on the side. Hindi na ako nag-reklamo kasi nagamit ko na.',
    'Average quality. Klaro kaayo ang glue sa kilid, pwede pa ma-improve.',
    'Hoping for better packaging. The box was crushed and the shoes had creases.',
    'Dili ko sure kung tinuod nga leather. Medyo plastic ang feeling sa upper.',
    'The insole is too thin. Ramdam ko ang semento kung maglakaw.',
    'Sakto lang sa presyo pero hindi ko na uulitin. Medyo masikip sa wide feet.',
    'Naguba ang tahi sa usa ka semana. Sayang kay gwapo unta ang design.',
    'The left shoe had uneven color. The seller offered a partial refund, but it was still a hassle.',
    'Comfortable at first, pero nangalisod ko after a few hours. Not for long walks.'
  ];
begin
  -- An existing customer carries the mock orders (any mock profile will do).
  select p.id into v_buyer_id
  from public.profiles p
  join _mock_reviewers r on r.email = p.email
  order by r.idx
  limit 1;

  if v_buyer_id is null then
    raise exception 'Mock reviewers are missing — run section 1-3 first.';
  end if;

  for v_product in
    select pr.id, pr.store_id, pr.price
    from public.products pr
    where pr.store_id is not null
    order by pr.id
  loop
    v_order_id := md5('sole-mock-review-order:' || v_product.id::text)::uuid;
    v_order_ts := now() - interval '10 days'
                  - (interval '1 day' * (abs(hashtext(v_product.id::text)) % 240));

    -- One order, twenty line items. 'cancelled' + 'unpaid' keeps it out
    -- of every sales, stock and payout number while still satisfying the
    -- reviews -> order / order_item foreign keys.
    insert into public.orders (
      id, customer_id, store_id, status, total_amount,
      payment_method, payment_status, fulfillment, notes, created_at
    ) values (
      v_order_id, v_buyer_id, v_product.store_id, 'cancelled',
      round(coalesce(v_product.price, 0) * 20, 2),
      'cash', 'unpaid', 'pickup',
      'Mock review seed — not a real order.',
      v_order_ts
    )
    on conflict (id) do nothing;

    for v_i in 0..19 loop
      -- Walk the thirty-nine reviewers in steps of five (coprime with
      -- 39), so each product gets a different but stable set of twenty
      -- people.
      v_idx := ((abs(hashtext(v_product.id::text)) + v_i * 5) % 39) + 1;
      select * into v_reviewer from _mock_reviewers where idx = v_idx;

      select p.id into v_reviewer_id
      from public.profiles p
      where p.email = v_reviewer.email;

      continue when v_reviewer_id is null;

      -- Rating 3, 4 or 5, weighted like a healthy storefront: about
      -- half five-star, three in ten four-star, two in ten disappointed
      -- three-star. Then a comment from that band.
      v_hash := abs(hashtext(v_product.id::text || ':' || v_idx::text))::bigint;
      v_rating := case
                    when (v_hash % 10) < 5 then 5
                    when (v_hash % 10) < 8 then 4
                    else 3
                  end;

      if v_rating = 5 then
        v_comment := v_good5[1 + ((v_hash / 7) % array_length(v_good5, 1))::int];
      elsif v_rating = 4 then
        v_comment := v_good4[1 + ((v_hash / 7) % array_length(v_good4, 1))::int];
      else
        v_comment := v_low3[1 + ((v_hash / 7) % array_length(v_low3, 1))::int];
      end if;

      v_review_ts := v_order_ts
                     + (interval '1 day' * (v_i % 6))
                     + (interval '3 hours' * (v_i % 5));

      v_item_id   := md5('sole-mock-review-item:'   || v_product.id::text || ':' || v_idx::text)::uuid;
      v_review_id := md5('sole-mock-review-review:' || v_product.id::text || ':' || v_idx::text)::uuid;

      insert into public.order_items (
        id, order_id, product_id, size, quantity, unit_price
      ) values (
        v_item_id, v_order_id, v_product.id,
        v_sizes[1 + (v_i % array_length(v_sizes, 1))],
        1, coalesce(v_product.price, 0)
      )
      on conflict (id) do nothing;

      insert into public.reviews (
        id, order_id, order_item_id, product_id, customer_id, store_id,
        rating, comment, created_at, updated_at
      ) values (
        v_review_id, v_order_id, v_item_id, v_product.id, v_reviewer_id,
        v_product.store_id, v_rating, v_comment, v_review_ts, v_review_ts
      )
      on conflict (id) do nothing;
    end loop;
  end loop;
end
$seed$;

-- ─────────────────────────────────────────────────────────────────
-- 4c. SOLD COUNTER = REVIEW COUNT
--     The card shows "N reviews • M sold", and sold is the live sum of
--     order_items.quantity over paid, non-cancelled orders. The review
--     orders above are 'cancelled' so they stay out of that sum, and this
--     section adds ONE paid mock order per product whose single line
--     carries exactly `review_count - real_units_sold` units.
--
--     ⚠️ TRADE-OFF, STATED PLAINLY: those orders are real sales rows, so
--     they also appear in seller revenue, Sales Reports and payouts. The
--     note marker lets CLEANUP remove them in one statement.
-- ─────────────────────────────────────────────────────────────────
do $seed$
declare
  v_product   record;
  v_reviews   bigint;
  v_real_sold bigint;
  v_needed    bigint;
  v_buyer_id  uuid;
  v_order_id  uuid;
  v_item_id   uuid;
  v_order_ts  timestamptz;
begin
  select p.id into v_buyer_id
  from public.profiles p
  join _mock_reviewers r on r.email = p.email
  order by r.idx
  limit 1;

  if v_buyer_id is null then
    raise exception 'Mock reviewers are missing — run sections 1-3 first.';
  end if;

  for v_product in
    select pr.id, pr.store_id, pr.price
    from public.products pr
    where pr.store_id is not null
    order by pr.id
  loop
    select count(*) into v_reviews
    from public.reviews rv
    where rv.product_id = v_product.id;

    continue when v_reviews = 0;

    -- Units already sold by REAL orders (both mock order kinds excluded).
    select coalesce(sum(oi.quantity), 0) into v_real_sold
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where oi.product_id = v_product.id
      and o.status <> 'cancelled'
      and o.payment_status = 'paid'
      and o.notes is distinct from 'Mock review seed — not a real order.'
      and o.notes is distinct from 'Mock sold-count seed — not a real order.';

    v_needed := v_reviews - v_real_sold;
    continue when v_needed <= 0;

    v_order_id := md5('sole-mock-sold-order:' || v_product.id::text)::uuid;
    v_item_id  := md5('sole-mock-sold-item:'  || v_product.id::text)::uuid;
    v_order_ts := now() - interval '45 days'
                  - (interval '1 day' * (abs(hashtext(v_product.id::text)) % 200));

    insert into public.orders (
      id, customer_id, store_id, status, total_amount,
      payment_method, payment_status, fulfillment, notes, created_at
    ) values (
      v_order_id, v_buyer_id, v_product.store_id, 'received',
      round(coalesce(v_product.price, 0) * v_needed, 2),
      'cash', 'paid', 'pickup',
      'Mock sold-count seed — not a real order.',
      v_order_ts
    )
    on conflict (id) do update set
      total_amount = excluded.total_amount,
      created_at   = excluded.created_at;

    insert into public.order_items (
      id, order_id, product_id, size, quantity, unit_price
    ) values (
      v_item_id, v_order_id, v_product.id, '9', v_needed::int,
      coalesce(v_product.price, 0)
    )
    on conflict (id) do update set
      quantity   = excluded.quantity,
      unit_price = excluded.unit_price;
  end loop;
end
$seed$;

-- ─────────────────────────────────────────────────────────────────
-- 4d. LIKES (review_votes — the thumbs on each card)
--     Each mock review gets 0-6 votes from OTHER mock reviewers (never
--     the author), about four in five of them helpful. Counts on the
--     reviews row are kept by the existing trigger.
-- ─────────────────────────────────────────────────────────────────
insert into public.review_votes (review_id, user_id, is_helpful, created_at)
select
  m.review_id,
  v.id,
  ((m.h + m.slot * 7) % 5) <> 0,
  least(now() - interval '1 hour', m.created_at + interval '2 days')
from (
  select
    r.id                      as review_id,
    r.customer_id             as author_id,
    r.created_at,
    abs(hashtext(r.id::text)::bigint) as h,
    g.i                       as slot
  from public.reviews r
  join public.orders o on o.id = r.order_id
  cross join generate_series(1, 6) as g(i)
  where o.notes = 'Mock review seed — not a real order.'
    and g.i <= (abs(hashtext(r.id::text)::bigint) % 7)
) m
join lateral (
  select p.id
  from public.profiles p
  join _mock_reviewers rv on rv.email = p.email
  order by p.id
  offset ((m.h + m.slot * 13) % 39)
  limit 1
) v on true
where v.id <> m.author_id
on conflict (review_id, user_id) do nothing;

-- ─────────────────────────────────────────────────────────────────
-- 4e. DISCUSSION (review_comments — flat thread under the review)
--     Roughly two in three reviews get a thread of one or two replies
--     from other mock customers. Deterministic ids, so a re-run adds
--     nothing.
-- ─────────────────────────────────────────────────────────────────
insert into public.review_comments (
  id, review_id, user_id, comment, created_at, updated_at
)
select
  md5('sole-mock-review-comment:' || r.id::text || ':' || c.slot)::uuid,
  r.id,
  v.id,
  (array[
    'Same experience here. Mine has held up well after months of daily use.',
    'Saan ka nakabili ng size 9? Sold out na kasi sa akin.',
    'Naa pa ba ni nga design? Ganahan ko moorder usab.',
    'Thanks for the honest review. Very helpful before I ordered.',
    'Ilang days bago na-deliver sa Cebu? Planning to order this week.',
    'Naa koy parehas ani, lig-on gyud. Sulit ang bayad.',
    'Legit ba ni nga leather? Nagduha-duha pa ko moorder.',
    'Agree! The fit was spot on for me too.',
    'Seller replied fast when I asked about sizing. Recommended.',
    'Sorry to hear that. Did the seller offer a replacement?',
    'Ako pud, medyo masikip sa first wear pero okay na karon.',
    'Is the sole soft enough for long walks?',
    'Nag-order ko gahapon, hoping parehas og quality sa imoha.',
    'Nice photos! The color looks better in person pala.'
  ])[1 + ((abs(hashtext(r.id::text)::bigint) + c.slot * 5) % 14)::int],
  least(now() - interval '30 minutes', r.created_at + interval '1 day' * c.slot),
  least(now() - interval '30 minutes', r.created_at + interval '1 day' * c.slot)
from public.reviews r
join public.orders o on o.id = r.order_id
cross join generate_series(1, 2) as c(slot)
join lateral (
  select p.id
  from public.profiles p
  join _mock_reviewers rv on rv.email = p.email
  order by p.id
  offset ((abs(hashtext(r.id::text)::bigint) + c.slot * 17) % 39)
  limit 1
) v on true
where o.notes = 'Mock review seed — not a real order.'
  and (abs(hashtext(r.id::text)::bigint) % 3) <> 0
  and c.slot <= 1 + (abs(hashtext(r.id::text)::bigint) % 2)
  and v.id <> r.customer_id
on conflict (id) do nothing;

-- ─────────────────────────────────────────────────────────────────
-- 4f. PINNED REVIEW (the seller spotlight)
--     One pinned review per product: the most-liked 5-star one. The pin
--     guard trigger (seller/admin only) is switched off for these rows
--     and restored in 4g; a product that already has a pin is left alone.
-- ─────────────────────────────────────────────────────────────────
do $seed$
declare
  v_trigger text;
begin
  for v_trigger in
    select t.tgname
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'reviews'
      and not t.tgisinternal
      and t.tgfoid = to_regprocedure('public.guard_review_pin()')
  loop
    execute format('alter table public.reviews disable trigger %I', v_trigger);
  end loop;
end
$seed$;

update public.reviews r
set is_pinned = true
where r.id = (
    select r2.id
    from public.reviews r2
    join public.orders o2 on o2.id = r2.order_id
    where r2.product_id = r.product_id
      and o2.notes = 'Mock review seed — not a real order.'
    order by r2.rating desc, r2.helpful_count desc, r2.created_at desc
    limit 1
  )
  and not exists (
    select 1 from public.reviews r3
    where r3.product_id = r.product_id and r3.is_pinned
  );

-- ─────────────────────────────────────────────────────────────────
-- 4g. PUT THE GUARDED TRIGGERS BACK
--     Disabled triggers still appear in pg_trigger (tgenabled = 'D'), so
--     the same lookups find them again and re-enable every one.
-- ─────────────────────────────────────────────────────────────────
do $seed$
declare
  v_trigger text;
begin
  for v_trigger in
    select t.tgname
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'order_items'
      and not t.tgisinternal
      and t.tgfoid = to_regprocedure('public.decrement_inventory_on_order()')
  loop
    execute format('alter table public.order_items enable trigger %I', v_trigger);
  end loop;

  for v_trigger in
    select t.tgname
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'reviews'
      and not t.tgisinternal
      and t.tgfoid = to_regprocedure('public.guard_review_pin()')
  loop
    execute format('alter table public.reviews enable trigger %I', v_trigger);
  end loop;
end
$seed$;

-- ─────────────────────────────────────────────────────────────────
-- 5. VERIFY
-- ─────────────────────────────────────────────────────────────────
select
  pr.name                                          as product,
  pr.review_count                                  as reviews_on_card,
  pr.avg_rating                                    as avg_rating,
  coalesce(ps.units_sold, 0)                       as sold,
  (select count(*) from public.review_votes v
     join public.reviews r on r.id = v.review_id
    where r.product_id = pr.id)                    as likes,
  (select count(*) from public.review_comments c
     join public.reviews r on r.id = c.review_id
    where r.product_id = pr.id)                    as comments,
  (select count(*) from public.reviews r
    where r.product_id = pr.id and r.is_pinned)    as pinned
from public.products pr
left join public.product_sales() ps on ps.product_id = pr.id::text
group by pr.id, pr.name, pr.review_count, pr.avg_rating, ps.units_sold
order by pr.name;

commit;

-- ══════════════════════════════════════════════════════════════════
-- CLEANUP — uncomment and run to remove everything this file created.
-- Reviews and order items go with the mock orders (ON DELETE CASCADE);
-- the accounts go last, and their profiles cascade too.
-- ══════════════════════════════════════════════════════════════════
-- begin;
-- delete from public.orders
--  where notes in ('Mock review seed — not a real order.',
--                 'Mock sold-count seed — not a real order.');
-- delete from auth.users
--  where email like '%@gmail.com'
--    and id in (
--      select id from public.profiles
--       where role = 'customer'
--         and full_name in (
--           'Keith Vincent Abalo', 'Maria Xhyrra Abalo', 'Steven Balasabas',
--           'Angel Mae Briones', 'Jhonel Vincent Cabardo', 'Lovely Cacayan',
--           'Jennifer Jean Caparida', 'Mark Clyde Castillote',
--           'Kurt Andrei Dugaduga', 'Joshua Mark Encabo', 'Quizzel Espinosa',
--           'Ludemae Flores', 'Ian Geraldez', 'Jessa Iyas', 'Shaine Jayme',
--           'Juls Frederick Laborte', 'Krisha Mae Laput',
--           'Mitch Maria Paula Larumbe', 'Sylvan Niño Vee Mangubat',
--           'Jherico Maurin', 'Kimberly Miranda', 'Roljune Monterona',
--           'Mc Gerald Von Rich Nebril', 'Bea Dolly Nicor', 'Donald Obeso',
--           'Gwen Paragoso', 'Rhamces Pecidas', 'Christian Jade Pesiao',
--           'Cassandra Jade Ponce', 'Althea Angela Ponte', 'Mark June Repunte',
--           'Ria Grace Requinto', 'Maria Ina Ricablanca', 'Christian Salinas',
--           'Ryan Dave Sasuman', 'Leira Mae Señor', 'Loui Tajanlangit',
--           'Roegie Tapic', 'Dave Carl Ubas'
--         )
--    );
-- select public.refresh_store_rating_stats(id) from public.stores;
-- commit;

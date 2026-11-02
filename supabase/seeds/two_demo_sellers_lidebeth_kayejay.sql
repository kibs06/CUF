-- ══════════════════════════════════════════════════════════════════
-- DEMO SELLER SEED — Lidebeth Shoes Trading + Kaye-Jay Footware Store
-- ══════════════════════════════════════════════════════════════════
-- WHAT THIS DOES:
--   Creates 2 approved seller accounts (auth.users + profiles)
--   plus 1 store each (one-store-per-seller rule respected).
--
-- HOW TO RUN:
--   1. Open Supabase Dashboard → SQL Editor (or `supabase db execute`).
--   2. Paste & run this whole file. Safe to re-run (idempotent).
--   3. Log in with the credentials below.
--
-- ✏️ EDIT ME — all placeholder info lives in Section 0. Change names,
--   emails, phones, passwords, store details there and re-run.
--   (Password hashes in Section 1 are derived from the Section 0
--   passwords, so you only ever edit Section 0.)
--
-- DEMO LOGINS (change after first login!):
--   lidebeth.shoestrading@gmail.com   /  Lidebeth123!
--   kayejay.footware@gmail.com        /  KayeJay123!
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- SECTION 0 — ✏️ EDIT ME: seller info (invented placeholders)
-- ─────────────────────────────────────────────────────────────────
-- Seller 1
--   Owner name : Lidebeth Ramos
--   Store name : Lidebeth Shoes Trading
--   Email      : lidebeth.shoestrading@gmail.com
--   Phone      : +63 932 123 4567
--   Password   : Lidebeth123!
--   Location   : Poblacion III, Carcar City, Cebu
--   Tagline    : Quality leather shoes, proudly made in Carcar
--
-- Seller 2  (kept your "Footware" spelling — fix to "Footwear" if you like)
--   Owner name : Kaye Jay Dela Cruz
--   Store name : Kaye-Jay Footware Store
--   Email      : kayejay.footware@gmail.com
--   Phone      : +63 945 987 6543
--   Password   : KayeJay123!
--   Location   : Poblacion I, Carcar City, Cebu
--   Tagline    : Affordable everyday footwear for the whole family

-- ─────────────────────────────────────────────────────────────────
-- SECTION 1 — auth.users (login accounts)
-- ─────────────────────────────────────────────────────────────────
-- NOTE: needs pgcrypto for crypt(). Supabase ships it in every project.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DO $$
DECLARE
  v_instance_id uuid;
BEGIN
  SELECT id INTO v_instance_id FROM auth.instances LIMIT 1;

  -- Seller 1 auth account
  INSERT INTO auth.users (
    instance_id, id, aud, role,
    email, encrypted_password, email_confirmed_at,
    created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    is_super_admin, confirmation_sent_at, recovery_sent_at
  ) VALUES (
    v_instance_id,
    '11111111-1111-4111-8111-111111111111',
    'authenticated', 'authenticated',
    'lidebeth.shoestrading@gmail.com',
    crypt('Lidebeth123!', gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Lidebeth Ramos"}',
    false, now(), now()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    encrypted_password = EXCLUDED.encrypted_password,
    email_confirmed_at = now(),
    updated_at = now();

  -- Seller 2 auth account
  INSERT INTO auth.users (
    instance_id, id, aud, role,
    email, encrypted_password, email_confirmed_at,
    created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    is_super_admin, confirmation_sent_at, recovery_sent_at
  ) VALUES (
    v_instance_id,
    '22222222-2222-4222-8222-222222222222',
    'authenticated', 'authenticated',
    'kayejay.footware@gmail.com',
    crypt('KayeJay123!', gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Kaye Jay Dela Cruz"}',
    false, now(), now()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    encrypted_password = EXCLUDED.encrypted_password,
    email_confirmed_at = now(),
    updated_at = now();

  -- Keep auth.identities in sync (required for email login on some setups)
  INSERT INTO auth.identities (
    provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) VALUES
    ('11111111-1111-4111-8111-111111111111',
     '11111111-1111-4111-8111-111111111111',
     jsonb_build_object('sub', '11111111-1111-4111-8111-111111111111',
                        'email', 'lidebeth.shoestrading@gmail.com'),
     'email', now(), now(), now()),
    ('22222222-2222-4222-8222-222222222222',
     '22222222-2222-4222-8222-222222222222',
     jsonb_build_object('sub', '22222222-2222-4222-8222-222222222222',
                        'email', 'kayejay.footware@gmail.com'),
     'email', now(), now(), now())
  ON CONFLICT (provider, provider_id) DO UPDATE SET
    identity_data = EXCLUDED.identity_data,
    updated_at = now();
END $$;

-- ─────────────────────────────────────────────────────────────────
-- SECTION 2 — profiles (approved sellers)
-- ─────────────────────────────────────────────────────────────────
INSERT INTO public.profiles (
  id, full_name, email, phone,
  role, seller_status,
  store_name, store_description, store_location,
  birthday, gender
) VALUES
  ('11111111-1111-4111-8111-111111111111',
   'Lidebeth Ramos',
   'lidebeth.shoestrading@gmail.com',
   '+63 932 123 4567',
   'seller', 'approved',
   'Lidebeth Shoes Trading',
   'Quality leather shoes and sandals, proudly handcrafted in Carcar City, Cebu.',
   'Poblacion III, Carcar City, Cebu',
   '1988-05-14', 'Female'),
  ('22222222-2222-4222-8222-222222222222',
   'Kaye Jay Dela Cruz',
   'kayejay.footware@gmail.com',
   '+63 945 987 6543',
   'seller', 'approved',
   'Kaye-Jay Footware Store',
   'Affordable everyday footwear for the whole family — slippers, sandals, and school shoes.',
   'Poblacion I, Carcar City, Cebu',
   '1995-09-02', 'Female')
ON CONFLICT (id) DO UPDATE SET
  full_name = EXCLUDED.full_name,
  email = EXCLUDED.email,
  phone = EXCLUDED.phone,
  role = 'seller',
  seller_status = 'approved',
  store_name = EXCLUDED.store_name,
  store_description = EXCLUDED.store_description,
  store_location = EXCLUDED.store_location,
  birthday = EXCLUDED.birthday,
  gender = EXCLUDED.gender;

-- ─────────────────────────────────────────────────────────────────
-- SECTION 3 — stores (one per seller)
-- ─────────────────────────────────────────────────────────────────
INSERT INTO public.stores (
  id, name, tagline, description, location,
  brand_color, rating, is_open, is_active, owner_id
) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'Lidebeth Shoes Trading',
   'Quality leather shoes, proudly made in Carcar',
   'Quality leather shoes and sandals, proudly handcrafted in Carcar City, Cebu. Visit our store for fitting and made-to-order pairs.',
   'Poblacion III, Carcar City, Cebu',
   '#8B5A2B', 5.0, true, true,
   '11111111-1111-4111-8111-111111111111'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
   'Kaye-Jay Footware Store',
   'Affordable everyday footwear for the whole family',
   'Affordable everyday footwear for the whole family — slippers, sandals, and school shoes at friendly prices.',
   'Poblacion I, Carcar City, Cebu',
   '#2B6B8B', 5.0, true, true,
   '22222222-2222-4222-8222-222222222222')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  tagline = EXCLUDED.tagline,
  description = EXCLUDED.description,
  location = EXCLUDED.location,
  brand_color = EXCLUDED.brand_color,
  is_open = EXCLUDED.is_open,
  is_active = EXCLUDED.is_active,
  owner_id = EXCLUDED.owner_id;

-- ─────────────────────────────────────────────────────────────────
-- SECTION 4 — verify
-- ─────────────────────────────────────────────────────────────────
SELECT p.full_name AS owner, p.email, p.phone, p.role, p.seller_status,
       s.name AS store, s.location
FROM public.profiles p
LEFT JOIN public.stores s ON s.owner_id = p.id
WHERE p.id IN ('11111111-1111-4111-8111-111111111111',
               '22222222-2222-4222-8222-222222222222')
ORDER BY p.full_name;

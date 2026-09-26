import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseAnonKey) {
  console.warn('Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY in .env')
}

// The anon key, exactly as the Flutter app ships it. Every read below is
// subject to the same Row-Level Security the app is: this client is never
// privileged, so the portal cannot see anything a customer should not.
export const supabase = createClient(
  supabaseUrl ?? '',
  supabaseAnonKey ?? '',
)

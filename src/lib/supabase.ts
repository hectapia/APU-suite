import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || '';
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';

if (!supabaseUrl || !supabaseAnonKey) {
  // Helpful development warning if credentials haven't been provided in .env
  console.warn(
    'Supabase environment variables (NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY) are missing. Check your .env file.'
  );
}

/**
 * Public client for client components and unprivileged operations
 */
export const supabase = createClient(supabaseUrl, supabaseAnonKey);

/**
 * Admin client for server-side API routes and edge functions requiring service_role bypass
 */
export function getServiceSupabase() {
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceKey) {
    throw new Error('SUPABASE_SERVICE_ROLE_KEY is required for service operations.');
  }
  return createClient(supabaseUrl, serviceKey);
}

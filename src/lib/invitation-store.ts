import { supabaseAdmin } from './supabase-admin';

export interface StoredInvitation {
  id_invitation: string;
  id_event: number;
  id_provider?: number | null;
  invited_email: string;
  token: string;
  expires_at: string;
  is_accepted: boolean;
  accepted_at?: string | null;
  created_at: string;
  event?: any;
  provider?: any;
}

// Global in-memory cache shared across Next.js API requests (survives during server lifetime)
declare global {
  // eslint-disable-next-line no-var
  var __APU_INVITATIONS_CACHE__: Map<string, StoredInvitation> | undefined;
}

function getCache(): Map<string, StoredInvitation> {
  if (!global.__APU_INVITATIONS_CACHE__) {
    global.__APU_INVITATIONS_CACHE__ = new Map<string, StoredInvitation>();
  }
  return global.__APU_INVITATIONS_CACHE__;
}

/**
 * Register or update an invitation in the cache
 */
export function recordInvitationInStore(inv: StoredInvitation) {
  const cache = getCache();
  cache.set(inv.token, inv);
}

/**
 * Find an invitation by token with dual-layer resolution:
 * 1. Supabase database table `event_invitation` (without fragile PostgREST joins)
 * 2. In-memory / fallback cache
 */
export async function getInvitationByToken(token: string): Promise<StoredInvitation | null> {
  const normalizedToken = token.trim();
  const cache = getCache();

  // 1. Attempt lookup in Supabase
  try {
    const { data: dbInv, error: dbErr } = await supabaseAdmin
      .from('event_invitation')
      .select('*')
      .eq('token', normalizedToken)
      .limit(1)
      .maybeSingle();

    if (!dbErr && dbInv) {
      const inv: StoredInvitation = {
        ...dbInv,
        invited_email: dbInv.invited_email.toLowerCase(),
      };

      // Hydrate Event
      if (dbInv.id_event) {
        try {
          const { data: evData } = await supabaseAdmin
            .from('event')
            .select('*')
            .eq('id_event', dbInv.id_event)
            .limit(1)
            .maybeSingle();

          if (evData) {
            // Fetch client name if available
            if (evData.id_client) {
              const { data: clData } = await supabaseAdmin
                .from('client')
                .select('client_name')
                .eq('id_client', evData.id_client)
                .maybeSingle();
              evData.client = clData || { client_name: 'PEMEX Exploración y Producción' };
            }
            inv.event = evData;
          }
        } catch {
          // ignore
        }
      }

      // Hydrate Provider
      if (dbInv.id_provider) {
        try {
          const { data: provData } = await supabaseAdmin
            .from('provider')
            .select('*')
            .eq('id_provider', dbInv.id_provider)
            .limit(1)
            .maybeSingle();
          if (provData) inv.provider = provData;
        } catch {
          // ignore
        }
      }

      // Sync to cache
      cache.set(normalizedToken, inv);
      return inv;
    }
  } catch (err) {
    console.warn('Database query warning in getInvitationByToken:', err);
  }

  // 2. Check in-memory / fallback cache
  if (cache.has(normalizedToken)) {
    return cache.get(normalizedToken)!;
  }

  // 3. Check if token matches standard demo/provider patterns
  for (const inv of cache.values()) {
    if (inv.token === normalizedToken || normalizedToken.includes(inv.token)) {
      return inv;
    }
  }

  return null;
}

/**
 * Find invitations by email
 */
export async function getInvitationsByEmail(email: string): Promise<StoredInvitation[]> {
  const normalizedEmail = email.trim().toLowerCase();
  const cache = getCache();
  const results: StoredInvitation[] = [];

  // Check database
  try {
    const { data: dbInvs } = await supabaseAdmin
      .from('event_invitation')
      .select('*')
      .ilike('invited_email', normalizedEmail)
      .order('created_at', { ascending: false });

    if (dbInvs && dbInvs.length > 0) {
      for (const row of dbInvs) {
        const inv: StoredInvitation = { ...row, invited_email: row.invited_email.toLowerCase() };
        results.push(inv);
        cache.set(row.token, inv);
      }
    }
  } catch {
    // fallback to cache
  }

  // Check cache
  for (const inv of cache.values()) {
    if (inv.invited_email.toLowerCase() === normalizedEmail) {
      if (!results.some((r) => r.token === inv.token)) {
        results.push(inv);
      }
    }
  }

  return results;
}

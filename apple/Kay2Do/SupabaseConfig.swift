import Foundation

/// Your Supabase project's details (Supabase → Project Settings → API), the
/// same two values as web/config.js. The publishable (anon) key is meant to be public: the
/// row-level security in supabase/schema.sql is what keeps each list private.
///
/// Leave these blank to paste them into the app the first time it opens
/// instead; they're then kept on that device.
enum SupabaseConfig {
    static let url = "https://twdhmugbmvqpahjaambj.supabase.co"
    static let anonKey = "sb_publishable_3X4ZM9rvKuU5s7MFdbF4Hw_aEh1zB5N"
}

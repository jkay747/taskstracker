import Foundation

/// Your Supabase project's details (Supabase → Project Settings → API), the
/// same two values as web/config.js. The publishable (anon) key is meant to be public: the
/// row-level security in supabase/schema.sql is what keeps each list private.
///
/// Leave these blank to paste them into the app the first time it opens
/// instead; they're then kept on that device.
enum SupabaseConfig {
    static let url = "https://qgeyztbxylsuihpzpnlb.supabase.co"
    static let anonKey = "sb_publishable_vEhP3QStrD7gKUtI3uBMXw_wFZbh1M2"
}

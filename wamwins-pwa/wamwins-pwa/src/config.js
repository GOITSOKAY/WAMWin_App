/* WAMWins cloud connection. Fill in both values from Supabase: Project Settings > API.
   Leave them empty to run the app on this device only (no account sync). */
window.W = Object.assign(window.W || {}, { CONFIG: {
  supabaseUrl: '',      // e.g. 'https://abcdefghijk.supabase.co'
  supabaseAnonKey: ''   // the "anon" / "publishable" key (safe to ship in the app; data is protected by row-level security)
}});

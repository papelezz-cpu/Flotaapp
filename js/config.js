// ── SUPABASE CLIENT ───────────────────────────────────
const { createClient } = supabase;

const sb = createClient(
  'https://xnyqsewaluezkkrlyhxg.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhueXFzZXdhbHVlemtrcmx5aHhnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYwOTMzMTcsImV4cCI6MjA5MTY2OTMxN30.1WSfnJgMM1EPehd3fIMfDTUZqD8hEfhd8xYFCynBMhA',
  { auth: { storage: window.sessionStorage } }
);

// URL de la Edge Function para gestión de usuarios
const FN_URL = 'https://xnyqsewaluezkkrlyhxg.supabase.co/functions/v1/gestionar-usuario';
const FN_NOTIFICACION = 'https://xnyqsewaluezkkrlyhxg.supabase.co/functions/v1/enviar-notificacion';

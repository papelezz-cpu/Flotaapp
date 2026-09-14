// ── SUPABASE CLIENT ────────────────────────────────────
// ⚠ AMBIENTE DE PRUEBAS (rama dev) — apunta a portgo-pruebas, NUNCA a
// producción. Este archivo se queda fijo por rama a propósito: al pasar
// cambios de dev a main, config.js NUNCA se arrastra (main conserva el
// suyo), así que las credenciales de las dos ramas no se cruzan.
const { createClient } = supabase;

const sb = createClient(
  'https://xskgnudiznryhgagxadu.supabase.co',
  'sb_publishable_Nkc1GRJ0nfaRfrnsSRG4qQ_n66HVSEg',
  { auth: { storage: window.sessionStorage, persistSession: true } }
);

// URL de la Edge Function para gestión de usuarios
const FN_URL = 'https://xskgnudiznryhgagxadu.supabase.co/functions/v1/gestionar-usuario';
const FN_NOTIFICACION = 'https://xskgnudiznryhgagxadu.supabase.co/functions/v1/enviar-notificacion';

// Contacto de soporte
const SOPORTE_EMAIL = 'soporte@portgo.mx';
const SOPORTE_TEL   = '800-767-8461';

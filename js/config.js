// ── SUPABASE CLIENT ───────────────────────────────────
const { createClient } = supabase;

const sb = createClient(
  'https://xnyqsewaluezkkrlyhxg.supabase.co',
  'sb_publishable_Y02FH1PJFo3TsNqS6eLaXQ_URS7LEsk',
  { auth: { storage: window.sessionStorage, persistSession: true } }
);

// URL de la Edge Function para gestión de usuarios
const FN_URL = 'https://xnyqsewaluezkkrlyhxg.supabase.co/functions/v1/gestionar-usuario';
const FN_NOTIFICACION = 'https://xnyqsewaluezkkrlyhxg.supabase.co/functions/v1/enviar-notificacion';

// Contacto de soporte
const SOPORTE_EMAIL = 'soporte@portgo.mx';
const SOPORTE_TEL   = '800-767-8461';

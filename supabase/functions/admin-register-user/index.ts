import { withSupabase } from 'npm:@supabase/server@1.6.0';

type Profile = {
  rol: string; activo: boolean; empleado_activo: boolean;
  empleado_es_demo: boolean; empleado_pos_id: string | null;
  administrador_efectivo: boolean;
};
type ReadTable<Row extends Record<string, unknown>> = {
  Row: Row; Insert: never; Update: never; Relationships: [];
};
type Database = {
  public: {
    Tables: {
      usuarios: ReadTable<{ id: number; usuario: string }>;
      sucursales: ReadTable<{ id: string; activo: boolean; empresa_id: string }>;
    };
    Views: Record<string, never>;
    Functions: {
      login_mi_perfil: { Args: Record<string, never>; Returns: Profile[] };
      login_completar_alta: {
        Args: { p_actor: string; p_auth_uid: string; p_operacion: string;
          p_nombre: string; p_email: string; p_rol: string;
          p_sucursal: string | null; p_cancelar?: boolean };
        Returns: string;
      };
    };
  };
};

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const reply = (status: number, message: string, success = false, state?: string) =>
  Response.json({ success, message, state }, { status, headers: cors });

// PostgreSQL details can include entire rows; SMTP errors can include recipients.
// Keep known diagnostics and omit arbitrary server text, even on thrown errors.
function diagnosticText(value: unknown): string | null {
  if (typeof value !== 'string' || !value) return null;
  if (value === 'It could refer to either a PL/pgSQL variable or a table column.') return value;
  // Identifiers from our schema are safe; never include arbitrary identifiers or key values.
  const dbObject = value.match(/^(permission denied for (?:table|schema|sequence|function)|column reference) "?(usuarios|empleados_pos|inventario_admins|sucursales|usuarios_id_seq|auth|public|users|id|usuario_id|auth_uid|sucursal_id|login_completar_alta)"?( is ambiguous)?$/i);
  if (dbObject) return value;
  if (/^(Solo backend|Cuenta Auth no encontrada|Operacion no corresponde a esta cuenta|Asociacion existente requiere revision|Cuenta con autorizacion existente; no se elimina|Administrador no autorizado|Datos de alta invalidos|Sucursal no habilitada|Correo ya asociado|Error sending confirmation email|Email rate limit exceeded|Failed to fetch|fetch failed)$/i.test(value)) return value;
  const pattern = /^(duplicate key value violates unique constraint|insert or update on table|new row for relation|null value in column|column reference|permission denied for (?:table|schema|sequence|function)|invalid input syntax for type|Key \((?:id|usuario_id|auth_uid|sucursal_id|user_id)\)|Failing row contains|Perhaps you meant to reference|Could not find the function|Could not choose the best candidate function)/i;
  const prefix = value.match(pattern)?.[0];
  return prefix ? prefix + ' […]' : '[texto omitido]';
}

function logFailure(stage: string, error: unknown) {
  const e = (error && typeof error === 'object' ? error : {}) as Record<string, unknown>;
  const code = typeof e.code === 'string' &&
    /^(?:[0-9A-Z]{5}|PGRST\d{3}|over_email_send_rate_limit|email_address_not_authorized|email_provider_disabled|unexpected_failure|validation_failed)$/.test(e.code)
    ? e.code : null;
  console.error(stage, { code, message: diagnosticText(e.message),
    details: diagnosticText(e.details), hint: diagnosticText(e.hint) });
}

// Deployment gate, NOT a live SMTP/delivery check. Enable only after reviewing
// SMTP sender/credentials, Auth email confirmation, templates and exact redirect
// allowlist in the Dashboard. The function cannot inspect SMTP with a user JWT.
// Leave unset until that manual review; no account may be created beforehand.
function confirmationRedirect(): string | null {
  if (Deno.env.get('TEXAS_AUTH_EMAIL_CONFIG_VERIFIED') !== 'true') return null;
  const redirect = Deno.env.get('TEXAS_AUTH_REDIRECT_URL');
  try {
    const allowed: unknown = JSON.parse(Deno.env.get('TEXAS_AUTH_ALLOWED_REDIRECTS') ?? '[]');
    if (!redirect || !Array.isArray(allowed) || !allowed.includes(redirect)) return null;
    const url = new URL(redirect);
    if (url.username || url.password || url.search || url.hash) return null;
    if (redirect !== 'texasburger://auth/callback' && url.protocol !== 'https:') return null;
    return redirect;
  } catch { return null; }
}

// No client-supplied actor, IDs, redirect URLs or confirmation flags are accepted.
const handler = withSupabase<Database>({ auth: 'user' }, async (req, ctx) => {
  if (req.method !== 'POST') return reply(405, 'Método no permitido.');
  const { supabase, supabaseAdmin } = ctx;
  // getUser also checks the account with Auth, in addition to JWT verification.
  const identity = await supabase.auth.getUser();
  if (identity.error || !identity.data.user) return reply(401, 'Inicia sesión nuevamente.');
  const actor = identity.data.user.id;
  const profile = await supabase.rpc('login_mi_perfil');
  const p = profile.data?.length === 1 ? profile.data[0] : null;
  if (profile.error || !p || p.rol !== 'admin' || p.activo !== true ||
      p.empleado_activo !== true || p.empleado_es_demo !== false ||
      !p.empleado_pos_id || p.administrador_efectivo !== true) {
    return reply(403, 'Se requiere un administrador activo con empleado y autorización remota.');
  }
  const redirect = confirmationRedirect();
  if (!redirect) return reply(503, 'Registro bloqueado: falta revisar SMTP, confirmación y destinos de retorno en Supabase. No se creó ninguna cuenta.');
  let input: unknown;
  try { input = await req.json(); } catch { return reply(400, 'Solicitud inválida.'); }
  if (!input || typeof input !== 'object' || Array.isArray(input)) return reply(400, 'Solicitud inválida.');
  const fields = input as Record<string, unknown>;
  const name = typeof fields.name === 'string' ? fields.name.trim() : '';
  const email = typeof fields.email === 'string' ? fields.email.trim().toLowerCase() : '';
  const password = fields.password;
  const role = typeof fields.role === 'string' ? fields.role : '';
  const branch = fields.branch_id ?? null;
  if (!name || name.length > 255 || email.length > 255 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
      typeof password !== 'string' || password.length < 8 || password.length > 128 ||
      !['admin', 'cajero'].includes(role) || (role === 'cajero' && !branch) ||
      (branch !== null && (typeof branch !== 'string' || !branch))) {
    return reply(400, 'Revisa nombre, correo, contraseña (8–128 caracteres), rol y sucursal.');
  }
  if (branch !== null) {
    const b = await supabaseAdmin.from('sucursales').select('id')
      .eq('id', branch).eq('activo', true).eq('empresa_id', 'texas_burger').maybeSingle();
    if (b.error || !b.data) return reply(400, 'Sucursal no habilitada.');
  }
  // Early exact match; the transactional RPC also checks case-insensitive legacy matches.
  const existing = await supabaseAdmin.from('usuarios').select('id')
    .eq('usuario', email).limit(1);
  if (existing.error) return reply(503, 'No se pudo verificar el alta.');
  if (existing.data?.length) return reply(409, 'El correo ya tiene una cuenta. No se modificó.');
  const operation = crypto.randomUUID();
  let created;
  try {
    created = await supabaseAdmin.auth.admin.createUser({
      email, password, email_confirm: false,
      app_metadata: { texas_alta_operacion: operation, texas_alta_actor: actor },
    });
  } catch {
    return reply(503, `No se confirmó la creación. No repitas el alta sin revisión. Referencia: ${operation}`);
  }
  if (created.error || !created.data.user) {
    if (!created.error || !created.error.status || created.error.status >= 500) {
      return reply(503, `Auth no confirmó el resultado. Requiere revisión antes de repetir el alta. Referencia: ${operation}`);
    }
    return reply(409, 'Auth no permitió crear la cuenta: comprueba si el correo existe o si la contraseña cumple la política. No se modificaron cuentas existentes.');
  }
  const args = {
    p_actor: actor, p_auth_uid: created.data.user.id, p_operacion: operation,
    p_nombre: name, p_email: email, p_rol: role, p_sucursal: branch,
  };
  let complete = false;
  try {
    const result = await supabaseAdmin.rpc('login_completar_alta', args);
    complete = !result.error && result.data === 'complete';
    if (result.error) logFailure('login_completar_alta', result.error);
    else if (!complete) console.error('login_completar_alta: resultado inesperado',
      { result: result.data === 'cancelled' ? 'cancelled' : result.data === null ? null : typeof result.data });
  } catch (error) { logFailure('login_completar_alta', error); }
  if (!complete) {
    try {
      // Same DB lock as finalization. Never deletes a committed or preexisting profile.
      const compensation = await supabaseAdmin.rpc('login_completar_alta', { ...args, p_cancelar: true });
      if (compensation.error) logFailure('login_completar_alta: compensación', compensation.error);
      if (!compensation.error && compensation.data === 'cancelled') {
        return reply(422, 'No se pudo asociar el perfil. Se canceló únicamente la cuenta recién creada.');
      }
      complete = !compensation.error && compensation.data === 'complete';
      if (!compensation.error && !complete) console.error('login_completar_alta: resultado inesperado de compensación');
    } catch (error) { logFailure('login_completar_alta: compensación', error); }
    if (!complete) return reply(503, `Alta pendiente de revisión. No la repitas. Referencia: ${operation}`);
  }
  // One mechanism: initial password + confirmation; no automatic verification.
  // Supabase Auth's official implementation finds an existing unconfirmed user
  // and calls sendConfirmation, without requiring confirmation_sent_at:
  // https://github.com/supabase/auth/blob/master/internal/api/resend.go
  // invite.go, in contrast, can reuse an existing unconfirmed account. Do not
  // replace createUser with invite without preserving exclusive operation ownership.
  try {
    const sent = await supabaseAdmin.auth.resend({ type: 'signup', email,
      options: { emailRedirectTo: redirect } });
    if (!sent.error) {
      // An accepted request does not prove inbox delivery or account activation.
      return reply(200,
        'Usuario registrado correctamente. Se solicitó el envío del correo de confirmación. El empleado deberá confirmar su correo antes de iniciar sesión.',
        true, 'pending_confirmation');
    }
    logFailure('auth.resend', sent.error);
  } catch (error) { logFailure('auth.resend', error); }
  return reply(409,
    `Usuario y empleado registrados, pero no se confirmó el envío del correo. La cuenta NO está habilitada. Revisa SMTP y reenvía la confirmación; no repitas el alta. Referencia: ${operation}`,
    false, 'confirmation_send_unconfirmed');
});

// OPTIONS carries no JWT; all actual requests go through user authentication.
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
  try {
    const response = await handler(req);
    const headers = new Headers(response.headers);
    for (const [key, value] of Object.entries(cors)) headers.set(key, value);
    return new Response(response.body, { status: response.status, headers });
  } catch {
    return reply(503, 'No se confirmó la operación. Revisa el estado antes de repetirla.');
  }
});

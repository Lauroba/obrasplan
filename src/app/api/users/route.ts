import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { action } = body;
    const supabase = createAdminClient();

    // ---- CREATE USER ----
    if (action === "create") {
      const { nombre, perfil, telefono, email, password, role, rol_id, foto_url } = body;
      if (!nombre || !email || !password) {
        return NextResponse.json({ error: "Nombre, email y contraseña son obligatorios" }, { status: 400 });
      }

      // 1. Create auth user
      const { data: authData, error: authError } = await supabase.auth.admin.createUser({
        email, password, email_confirm: true,
      });
      if (authError) return NextResponse.json({ error: `Error auth: ${authError.message}` }, { status: 400 });
      const authId = authData.user.id;

      // 2. Create recurso_humano
      const { data: recurso, error: recursoError } = await supabase
        .from("recursos_humanos")
        .insert({ nombre, perfil: perfil || null, telefono: telefono || null, email, foto_url: foto_url || null, activo: true } as any)
        .select().single();
      if (recursoError) {
        await supabase.auth.admin.deleteUser(authId);
        return NextResponse.json({ error: `Error recurso: ${recursoError.message}` }, { status: 400 });
      }

      // 3. Create users profile — incluir role correcto segun rol_id si es admin
      const { error: profileError } = await (supabase.from("users") as any)
        .insert({ id: authId, email, nombre, role: role || "partes", rol_id: rol_id || null, recurso_id: recurso.id, activo: true });
      if (profileError) {
        await (supabase.from("recursos_humanos") as any).delete().eq("id", recurso.id);
        await supabase.auth.admin.deleteUser(authId);
        return NextResponse.json({ error: `Error perfil: ${profileError.message}` }, { status: 400 });
      }

      // 4. Auditoria
      await (supabase.from("audit_log") as any).insert({
        accion: "crear", entidad: "users", modulo: "usuarios",
        descripcion: `Usuario creado: ${email}`, resultado: "exito", origen: "api_route",
      });

      return NextResponse.json({ success: true, recurso_id: recurso.id, user_id: authId });
    }

    // ---- UPDATE USER ----
    if (action === "update") {
      const { recurso_id, nombre, perfil, telefono, email, password, role, rol_id, foto_url } = body;
      if (!recurso_id) return NextResponse.json({ error: "recurso_id obligatorio" }, { status: 400 });

      // Update recurso_humano
      await (supabase.from("recursos_humanos") as any).update({
        nombre, perfil: perfil || null, telefono: telefono || null, email, foto_url: foto_url || null,
      }).eq("id", recurso_id);

      // Find linked user
      const { data: userRow } = await supabase.from("users").select("id").eq("recurso_id", recurso_id).single();
      if (userRow) {
        // Actualizar perfil (role + rol_id siempre juntos)
        await (supabase.from("users") as any).update({
          nombre,
          email,
          role: role || "partes",
          rol_id: rol_id || null,
        }).eq("id", userRow.id);

        // Actualizar email en Auth si cambio
        await supabase.auth.admin.updateUserById(userRow.id, { email });

        // Cambiar contraseña SOLO si se proporcionó una nueva (minimo 6 chars)
        if (password && password.trim().length >= 6) {
          const { error: pwErr } = await supabase.auth.admin.updateUserById(userRow.id, { password: password.trim() });
          if (pwErr) {
            return NextResponse.json({ error: `Error al cambiar contraseña: ${pwErr.message}` }, { status: 400 });
          }
          // Auditoria de cambio de contraseña — SIN guardar la contraseña
          await (supabase.from("audit_log") as any).insert({
            accion: "editar", entidad: "users", modulo: "usuarios",
            entidad_id: userRow.id,
            descripcion: `Contraseña cambiada por admin para: ${email}`,
            resultado: "exito", origen: "api_route",
          });
        }

        // Auditoria de actualización general
        await (supabase.from("audit_log") as any).insert({
          accion: "editar", entidad: "users", modulo: "usuarios",
          entidad_id: userRow.id,
          descripcion: `Perfil actualizado: ${email} — rol: ${role || "partes"}`,
          resultado: "exito", origen: "api_route",
        });

      } else if (email && password && password.trim().length >= 6) {
        // No auth user exists — crear uno nuevo
        const { data: authData, error: authError } = await supabase.auth.admin.createUser({
          email, password: password.trim(), email_confirm: true,
        });
        if (!authError && authData?.user) {
          await (supabase.from("users") as any).insert({
            id: authData.user.id, email, nombre,
            role: role || "partes",
            rol_id: rol_id || null,
            recurso_id, activo: true,
          });
        }
      }

      return NextResponse.json({ success: true });
    }

    // ---- RESET PASSWORD (enviar email de recuperación) ----
    // Accion alternativa: el admin puede enviar un email de reset en vez de cambiar directamente
    if (action === "send_reset") {
      const { email } = body;
      if (!email) return NextResponse.json({ error: "Email obligatorio" }, { status: 400 });
      // Usamos el cliente de Supabase con la service role pero el reset link
      // se genera para que el usuario lo reciba y cambie por su cuenta
      const { error } = await supabase.auth.resetPasswordForEmail(email);
      if (error) return NextResponse.json({ error: error.message }, { status: 400 });
      await (supabase.from("audit_log") as any).insert({
        accion: "editar", entidad: "users", modulo: "usuarios",
        descripcion: `Email de recuperación de contraseña enviado a: ${email}`,
        resultado: "exito", origen: "api_route",
      });
      return NextResponse.json({ success: true });
    }

    // ---- TOGGLE ACCESS ----
    if (action === "toggle_access") {
      const { recurso_id, activo } = body;
      const { data: userRow } = await supabase.from("users").select("id, email").eq("recurso_id", recurso_id).single();
      if (userRow) {
        await (supabase.from("users") as any).update({ activo }).eq("id", userRow.id);
        // Banear o desbanear en Supabase Auth
        if (!activo) {
          await supabase.auth.admin.updateUserById(userRow.id, { ban_duration: "876600h" });
        } else {
          await supabase.auth.admin.updateUserById(userRow.id, { ban_duration: "none" });
        }
        await (supabase.from("audit_log") as any).insert({
          accion: "editar", entidad: "users", modulo: "usuarios",
          entidad_id: userRow.id,
          descripcion: `Acceso ${activo ? "activado" : "desactivado"} para: ${(userRow as any).email}`,
          resultado: "exito", origen: "api_route",
        });
      }
      await (supabase.from("recursos_humanos") as any).update({ activo }).eq("id", recurso_id);
      return NextResponse.json({ success: true });
    }

    // ---- SYNC ALL USERS ----
    // IMPORTANTE: sync NUNCA cambia contraseñas de usuarios existentes.
    // Solo crea perfiles faltantes o vincula los que no estén enlazados.
    if (action === "sync") {
      const { data: recursos } = await supabase.from("recursos_humanos").select("*");
      const { data: authUsers } = await supabase.auth.admin.listUsers();
      const { data: profiles } = await supabase.from("users").select("id, recurso_id, email, role, rol_id");

      const profileRecursoIds = new Set((profiles || []).map((p: any) => p.recurso_id).filter(Boolean));

      let created = 0;
      let linked = 0;
      let errors: string[] = [];

      for (const recurso of (recursos || [])) {
        if (!recurso.email) continue;
        const email = recurso.email.toLowerCase();

        // Buscar si existe auth user
        const existingAuth = (authUsers?.users || []).find((u: any) => u.email?.toLowerCase() === email);

        if (!existingAuth) {
          // Solo crear si no existe en Auth. Contraseña temporal — el usuario debe cambiarla.
          const tempPass = "TempObrasPlan2024!";
          const { data: newAuth, error: authErr } = await supabase.auth.admin.createUser({
            email: recurso.email,
            password: tempPass,
            email_confirm: true,
          });
          if (authErr) {
            errors.push(`${recurso.nombre}: ${authErr.message}`);
            continue;
          }
          if (!profileRecursoIds.has(recurso.id)) {
            await (supabase.from("users") as any).insert({
              id: newAuth.user.id,
              email: recurso.email,
              nombre: recurso.nombre,
              role: "partes",
              recurso_id: recurso.id,
              activo: recurso.activo,
            });
          }
          created++;
        } else {
          // Auth existe — solo vincular perfil si falta, SIN tocar contraseña
          if (!profileRecursoIds.has(recurso.id)) {
            const existingProfile = (profiles || []).find((p: any) => p.id === existingAuth.id);
            if (existingProfile) {
              await (supabase.from("users") as any).update({ recurso_id: recurso.id }).eq("id", existingAuth.id);
            } else {
              await (supabase.from("users") as any).insert({
                id: existingAuth.id,
                email: recurso.email,
                nombre: recurso.nombre,
                role: "partes",
                recurso_id: recurso.id,
                activo: recurso.activo,
              });
            }
            linked++;
          }
        }
      }

      const msg = `Sincronización completada: ${created} usuarios nuevos creados, ${linked} vinculados${errors.length > 0 ? `, ${errors.length} errores` : ""}.${created > 0 ? " Los nuevos usuarios deben cambiar su contraseña temporal." : ""}`;

      return NextResponse.json({ success: true, created, linked, errors, message: msg });
    }

    return NextResponse.json({ error: "Acción no válida" }, { status: 400 });
  } catch (err: any) {
    return NextResponse.json({ error: err.message || "Error interno" }, { status: 500 });
  }
}
import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { action } = body;
    const supabase = createAdminClient();

    // ---- CREATE USER ----
    if (action === "create") {
      const { nombre, perfil, telefono, email, password, role, foto_url } = body;
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

      // 3. Create users profile
      const { error: profileError } = await (supabase.from("users") as any)
        .insert({ id: authId, email, nombre, role: role || "partes", recurso_id: recurso.id, activo: true });
      if (profileError) {
        await (supabase.from("recursos_humanos") as any).delete().eq("id", recurso.id);
        await supabase.auth.admin.deleteUser(authId);
        return NextResponse.json({ error: `Error perfil: ${profileError.message}` }, { status: 400 });
      }

      return NextResponse.json({ success: true, recurso_id: recurso.id, user_id: authId });
    }

    // ---- UPDATE USER ----
    if (action === "update") {
      const { recurso_id, nombre, perfil, telefono, email, password, role, foto_url } = body;
      if (!recurso_id) return NextResponse.json({ error: "recurso_id obligatorio" }, { status: 400 });

      // Update recurso
      await (supabase.from("recursos_humanos") as any).update({
        nombre, perfil: perfil || null, telefono: telefono || null, email, foto_url: foto_url || null,
      }).eq("id", recurso_id);

      // Find linked user
      const { data: userRow } = await supabase.from("users").select("id").eq("recurso_id", recurso_id).single();
      if (userRow) {
        await (supabase.from("users") as any).update({ nombre, email, role: role || "partes" }).eq("id", userRow.id);
        await supabase.auth.admin.updateUserById(userRow.id, { email });
        if (password && password.length >= 6) {
          await supabase.auth.admin.updateUserById(userRow.id, { password });
        }
      } else if (email && password && password.length >= 6) {
        // No auth user exists - create one
        const { data: authData, error: authError } = await supabase.auth.admin.createUser({
          email, password, email_confirm: true,
        });
        if (!authError && authData?.user) {
          await (supabase.from("users") as any).insert({
            id: authData.user.id, email, nombre, role: role || "partes", recurso_id, activo: true,
          });
        }
      }

      return NextResponse.json({ success: true });
    }

    // ---- TOGGLE ACCESS ----
    if (action === "toggle_access") {
      const { recurso_id, activo } = body;
      const { data: userRow } = await supabase.from("users").select("id").eq("recurso_id", recurso_id).single();
      if (userRow) {
        await (supabase.from("users") as any).update({ activo }).eq("id", userRow.id);
        if (!activo) await supabase.auth.admin.updateUserById(userRow.id, { ban_duration: "876600h" });
        else await supabase.auth.admin.updateUserById(userRow.id, { ban_duration: "none" });
      }
      await (supabase.from("recursos_humanos") as any).update({ activo }).eq("id", recurso_id);
      return NextResponse.json({ success: true });
    }

    // ---- SYNC ALL USERS ----
    if (action === "sync") {
      const { data: recursos } = await supabase.from("recursos_humanos").select("*");
      const { data: authUsers } = await supabase.auth.admin.listUsers();
      const { data: profiles } = await supabase.from("users").select("id, recurso_id, email");

      const authEmails = new Set((authUsers?.users || []).map((u: any) => u.email?.toLowerCase()));
      const profileRecursoIds = new Set((profiles || []).map((p: any) => p.recurso_id).filter(Boolean));

      let created = 0;
      let linked = 0;
      let errors: string[] = [];

      for (const recurso of (recursos || [])) {
        if (!recurso.email) continue;
        const email = recurso.email.toLowerCase();

        // Check if auth user exists
        const existingAuth = (authUsers?.users || []).find((u: any) => u.email?.toLowerCase() === email);

        if (!existingAuth) {
          // Create auth user with default password
          const defaultPass = "Loynek2026!";
          const { data: newAuth, error: authErr } = await supabase.auth.admin.createUser({
            email: recurso.email, password: defaultPass, email_confirm: true,
          });
          if (authErr) {
            errors.push(`${recurso.nombre}: ${authErr.message}`);
            continue;
          }
          // Create profile
          if (!profileRecursoIds.has(recurso.id)) {
            await (supabase.from("users") as any).insert({
              id: newAuth.user.id, email: recurso.email, nombre: recurso.nombre,
              role: "partes", recurso_id: recurso.id, activo: recurso.activo,
            });
          }
          created++;
        } else {
          // Auth exists but maybe no profile linked
          if (!profileRecursoIds.has(recurso.id)) {
            const existingProfile = (profiles || []).find((p: any) => p.id === existingAuth.id);
            if (existingProfile) {
              // Profile exists but not linked to recurso
              await (supabase.from("users") as any).update({ recurso_id: recurso.id }).eq("id", existingAuth.id);
            } else {
              // No profile at all
              await (supabase.from("users") as any).insert({
                id: existingAuth.id, email: recurso.email, nombre: recurso.nombre,
                role: "partes", recurso_id: recurso.id, activo: recurso.activo,
              });
            }
            linked++;
          }
        }
      }

      return NextResponse.json({
        success: true,
        created,
        linked,
        errors,
        message: `Sincronización completada: ${created} creados, ${linked} vinculados${errors.length > 0 ? `, ${errors.length} errores` : ""}. Contraseña por defecto: Loynek2026!`,
      });
    }

    return NextResponse.json({ error: "Acción no válida" }, { status: 400 });
  } catch (err: any) {
    return NextResponse.json({ error: err.message || "Error interno" }, { status: 500 });
  }
}

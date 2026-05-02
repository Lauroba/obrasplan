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
        email,
        password,
        email_confirm: true,
      });

      if (authError) {
        return NextResponse.json({ error: `Error al crear usuario: ${authError.message}` }, { status: 400 });
      }

      const authId = authData.user.id;

      // 2. Create recurso_humano
      const { data: recurso, error: recursoError } = await supabase
        .from("recursos_humanos")
        .insert({ nombre, perfil: perfil || null, telefono: telefono || null, email, foto_url: foto_url || null, activo: true })
        .select()
        .single();

      if (recursoError) {
        // Rollback: delete auth user
        await supabase.auth.admin.deleteUser(authId);
        return NextResponse.json({ error: `Error al crear recurso: ${recursoError.message}` }, { status: 400 });
      }

      // 3. Create users profile linked to recurso
      const { error: profileError } = await supabase
        .from("users")
        .insert({ id: authId, email, nombre, role: role || "partes", recurso_id: recurso.id, activo: true });

      if (profileError) {
        // Rollback
        await supabase.from("recursos_humanos").delete().eq("id", recurso.id);
        await supabase.auth.admin.deleteUser(authId);
        return NextResponse.json({ error: `Error al crear perfil: ${profileError.message}` }, { status: 400 });
      }

      return NextResponse.json({ success: true, recurso_id: recurso.id, user_id: authId });
    }

    // ---- UPDATE USER ----
    if (action === "update") {
      const { recurso_id, nombre, perfil, telefono, email, password, role, foto_url } = body;

      if (!recurso_id) return NextResponse.json({ error: "recurso_id es obligatorio" }, { status: 400 });

      // Update recurso_humano
      await supabase.from("recursos_humanos").update({
        nombre, perfil: perfil || null, telefono: telefono || null, email, foto_url: foto_url || null,
      }).eq("id", recurso_id);

      // Find linked user
      const { data: userRow } = await supabase.from("users").select("id").eq("recurso_id", recurso_id).single();

      if (userRow) {
        // Update user profile
        await supabase.from("users").update({ nombre, email, role: role || "partes" } as any).eq("id", userRow.id);

        // Update auth email if changed
        await supabase.auth.admin.updateUserById(userRow.id, { email });

        // Update password if provided
        if (password && password.length >= 6) {
          await supabase.auth.admin.updateUserById(userRow.id, { password });
        }
      }

      return NextResponse.json({ success: true });
    }

    // ---- TOGGLE ACCESS ----
    if (action === "toggle_access") {
      const { recurso_id, activo } = body;

      // Find linked user
      const { data: userRow } = await supabase.from("users").select("id").eq("recurso_id", recurso_id).single();

      if (userRow) {
        // Update user active flag
        await supabase.from("users").update({ activo } as any).eq("id", userRow.id);

        // Ban/unban in auth
        if (!activo) {
          await supabase.auth.admin.updateUserById(userRow.id, { ban_duration: "876600h" }); // ~100 years
        } else {
          await supabase.auth.admin.updateUserById(userRow.id, { ban_duration: "none" });
        }
      }

      // Update recurso activo
      await supabase.from("recursos_humanos").update({ activo } as any).eq("id", recurso_id);

      return NextResponse.json({ success: true });
    }

    return NextResponse.json({ error: "Acción no válida" }, { status: 400 });
  } catch (err: any) {
    return NextResponse.json({ error: err.message || "Error interno" }, { status: 500 });
  }
}

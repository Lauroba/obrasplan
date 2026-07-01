#Requires -Version 5.1
# fix-toggle-access-duplicados.ps1
# Corrige el error "JSON object requested, multiple (or no) rows returned"
# al desactivar acceso. Causa: hay usuarios con mas de una fila en
# public.users para el mismo recurso_id (duplicados antiguos, igual que
# tuvimos con Sergio, Patricia y ahora Jon).
#
# La API ya no usa maybeSingle() (que falla con 2+ filas). Ahora toma
# todas las filas, usa la mas reciente, y deja constancia del duplicado
# en audit_log para poder limpiarlo despues con SQL.

$ErrorActionPreference = "Stop"
$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
if (-not (Test-Path $RepoPath)) { Write-Host "ERROR" -ForegroundColor Red; exit 1 }
Set-Location $RepoPath
Write-Host "" ; Write-Host "==> Escribiendo route.ts" -ForegroundColor Cyan

$dst = "src\app\api\users\route.ts"
$content = @'
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

    // ---- DELETE USER (fisico) ----
    // Solo permite borrado fisico si el usuario NO tiene historial vinculado
    // (partes_diarios.created_by es RESTRICT -> el DELETE fallaria igualmente,
    // pero comprobamos antes para dar un mensaje claro y no intentar un borrado
    // parcial que deje datos inconsistentes).
    if (action === "delete") {
      const { recurso_id } = body;
      if (!recurso_id) return NextResponse.json({ error: "recurso_id obligatorio" }, { status: 400 });

      const { data: recurso } = await supabase.from("recursos_humanos").select("id, nombre, email").eq("id", recurso_id).single();
      if (!recurso) return NextResponse.json({ error: "Recurso no encontrado" }, { status: 404 });

      const { data: userRow } = await supabase.from("users").select("id, email").eq("recurso_id", recurso_id).maybeSingle();

      // Comprobar historial vinculado antes de borrar nada
      const blocking: string[] = [];

      if (userRow) {
        const { count: partesCount } = await supabase
          .from("partes_diarios").select("id", { count: "exact", head: true }).eq("created_by", userRow.id);
        if ((partesCount || 0) > 0) blocking.push(`${partesCount} parte(s) diario(s) creado(s)`);

        const { count: movCount } = await supabase
          .from("movimientos_almacen").select("id", { count: "exact", head: true }).eq("created_by", userRow.id);
        if ((movCount || 0) > 0) blocking.push(`${movCount} movimiento(s) de almacén registrado(s)`);
      }

      const { count: trabajadorCount } = await supabase
        .from("parte_trabajadores").select("id", { count: "exact", head: true }).eq("recurso_id", recurso_id);
      if ((trabajadorCount || 0) > 0) blocking.push(`${trabajadorCount} presencia(s) en partes diarios`);

      const { count: asigCount } = await supabase
        .from("asignaciones").select("id", { count: "exact", head: true })
        .eq("recurso_tipo", "humano").eq("recurso_id", recurso_id);
      if ((asigCount || 0) > 0) blocking.push(`${asigCount} asignación(es) en el planificador`);

      if (userRow) {
        const { count: checklistCount } = await supabase
          .from("checklists").select("id", { count: "exact", head: true }).eq("created_by", userRow.id);
        if ((checklistCount || 0) > 0) blocking.push(`${checklistCount} checklist(s) creado(s)`);

        const { count: checklistItemCount } = await supabase
          .from("checklist_items").select("id", { count: "exact", head: true }).eq("completado_por", userRow.id);
        if ((checklistItemCount || 0) > 0) blocking.push(`${checklistItemCount} item(s) de checklist completado(s)`);

        const { count: notaCreCount } = await supabase
          .from("planificador_notas").select("id", { count: "exact", head: true }).eq("created_by", userRow.id);
        const { count: notaUpdCount } = await supabase
          .from("planificador_notas").select("id", { count: "exact", head: true }).eq("updated_by", userRow.id);
        if ((notaCreCount || 0) + (notaUpdCount || 0) > 0) blocking.push(`${(notaCreCount || 0) + (notaUpdCount || 0)} nota(s) del planificador`);

        const { count: conflictoCount } = await supabase
          .from("conflictos_revisados").select("id", { count: "exact", head: true }).eq("revisado_por", userRow.id);
        if ((conflictoCount || 0) > 0) blocking.push(`${conflictoCount} conflicto(s) revisado(s)`);

        const { count: tareaCompCount } = await supabase
          .from("tareas").select("id", { count: "exact", head: true }).eq("completada_by", userRow.id);
        if ((tareaCompCount || 0) > 0) blocking.push(`${tareaCompCount} tarea(s) completada(s) por este usuario`);

        const { count: georadarCount } = await supabase
          .from("georadar_pasadas").select("id", { count: "exact", head: true }).eq("created_by", userRow.id);
        if ((georadarCount || 0) > 0) blocking.push(`${georadarCount} pasada(s) de georadar`);
      }

      if (blocking.length > 0) {
        return NextResponse.json({
          error: `No se puede eliminar: este usuario tiene historial vinculado (${blocking.join(", ")}). Usa "Desactivar acceso" en su lugar para conservar la trazabilidad.`,
          blocked: true,
          details: blocking,
        }, { status: 409 });
      }

      // Sin historial vinculado: borrado fisico seguro.
      // Orden importante: primero Auth (lo mas dificil de revertir/mas propenso
      // a fallar por constraints internas de Supabase no siempre visibles
      // desde el esquema public), y solo si funciona se borra el resto.
      if (userRow) {
        const { error: authDelErr } = await supabase.auth.admin.deleteUser(userRow.id);

        if (authDelErr) {
          // FALLBACK AUTOMATICO: si Supabase no permite el borrado fisico
          // (error interno "Database error deleting user", frecuente cuando
          // hay tablas del esquema auth -- identities, sessions, mfa_factors --
          // con registros para ese usuario), no dejamos al usuario en error:
          // lo desactivamos de forma segura, que es el resultado funcional
          // equivalente (pierde acceso por completo).
          await supabase.auth.admin.updateUserById(userRow.id, { ban_duration: "876600h" });
          await (supabase.from("users") as any).update({ activo: false }).eq("id", userRow.id);
          await (supabase.from("recursos_humanos") as any).update({ activo: false }).eq("id", recurso_id);

          await (supabase.from("audit_log") as any).insert({
            accion: "editar", entidad: "users", modulo: "usuarios",
            entidad_id: userRow.id,
            descripcion: `Eliminación física no disponible (${authDelErr.message}). Usuario desactivado como alternativa: ${recurso.email || recurso.nombre}`,
            resultado: "exito", origen: "api_route",
          });

          return NextResponse.json({
            success: true,
            fallback: true,
            message: `No fue posible eliminar físicamente el usuario de Supabase Auth (limitación interna de Supabase). En su lugar, se ha desactivado por completo: ya no puede acceder a la aplicación. Su historial y registro permanecen, pero sin acceso.`,
          });
        }

        // Auth borrado con exito -> el perfil de public.users se borra
        // automaticamente por el ON DELETE CASCADE, pero lo forzamos
        // explicitamente por si acaso.
        await (supabase.from("users") as any).delete().eq("id", userRow.id);
      }

      // Borrar el recurso humano
      const { error: recursoDelErr } = await (supabase.from("recursos_humanos") as any).delete().eq("id", recurso_id);
      if (recursoDelErr) {
        return NextResponse.json({ error: `Usuario eliminado de Auth y de la app, pero no se pudo borrar el recurso humano: ${recursoDelErr.message}` }, { status: 500 });
      }

      // 4. Auditoria
      await (supabase.from("audit_log") as any).insert({
        accion: "eliminar", entidad: "users", modulo: "usuarios",
        descripcion: `Usuario eliminado completamente (app + servidor Auth): ${recurso.email || recurso.nombre}`,
        resultado: "exito", origen: "api_route",
      });

      return NextResponse.json({ success: true });
    }

    // ---- TOGGLE ACCESS ----
    if (action === "toggle_access") {
      const { recurso_id, activo } = body;
      if (!recurso_id) return NextResponse.json({ error: "recurso_id obligatorio" }, { status: 400 });

      // select() en vez de maybeSingle(): si hay duplicados (mismo recurso_id
      // en varias filas de users, un problema de datos antiguo), no queremos
      // que la llamada falle por completo -- tomamos la fila mas reciente
      // y avisamos del duplicado en el mensaje de auditoria.
      const { data: userRows, error: userFindErr } = await supabase
        .from("users").select("id, email, created_at").eq("recurso_id", recurso_id)
        .order("created_at", { ascending: false });

      if (userFindErr) {
        return NextResponse.json({ error: `Error buscando el usuario vinculado: ${userFindErr.message}` }, { status: 500 });
      }

      const userRow = userRows && userRows.length > 0 ? userRows[0] : null;
      const hasDuplicates = (userRows?.length || 0) > 1;

      if (userRow) {
        const { error: updErr } = await (supabase.from("users") as any).update({ activo }).eq("id", userRow.id);
        if (updErr) {
          return NextResponse.json({ error: `No se pudo actualizar el perfil: ${updErr.message}` }, { status: 500 });
        }

        // Banear o desbanear en Supabase Auth
        const { error: banErr } = await supabase.auth.admin.updateUserById(
          userRow.id,
          { ban_duration: activo ? "none" : "876600h" }
        );
        if (banErr) {
          return NextResponse.json({ error: `Perfil actualizado pero no se pudo cambiar el acceso en Auth: ${banErr.message}` }, { status: 500 });
        }

        await (supabase.from("audit_log") as any).insert({
          accion: "editar", entidad: "users", modulo: "usuarios",
          entidad_id: userRow.id,
          descripcion: `Acceso ${activo ? "activado" : "desactivado"} para: ${(userRow as any).email}${hasDuplicates ? " (AVISO: hay perfiles duplicados para este recurso_id, se usó el más reciente)" : ""}`,
          resultado: "exito", origen: "api_route",
        });
      } else {
        // No hay perfil en public.users vinculado a este recurso -- no se puede
        // banear en Auth (no sabemos el id), pero al menos avisamos con claridad.
        return NextResponse.json({
          error: "Este trabajador no tiene un usuario de acceso vinculado en la tabla users (recurso_id no encontrado). No se puede activar/desactivar el acceso hasta que tenga un perfil de usuario.",
        }, { status: 404 });
      }

      const { error: recursoErr } = await (supabase.from("recursos_humanos") as any).update({ activo }).eq("id", recurso_id);
      if (recursoErr) {
        return NextResponse.json({ error: `Acceso actualizado pero no se pudo actualizar el recurso: ${recursoErr.message}` }, { status: 500 });
      }

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
'@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $RepoPath $dst), $content, $utf8NoBom)
Write-Host "    Escrito: $dst" -ForegroundColor Green

$ok = Select-String -Path "src\app\api\users\route.ts" -Pattern "hasDuplicates" -Quiet
if ($ok) { Write-Host "    OK: tolerante a duplicados" -ForegroundColor Green }
else { Write-Host "    ERROR" -ForegroundColor Red }
Write-Host ""
Write-Host "RECOMENDADO: ejecutar tambien fix-duplicado-jon.sql en Supabase" -ForegroundColor Yellow
Write-Host "para limpiar el duplicado real de Jon (la API ahora funciona pero" -ForegroundColor Yellow
Write-Host "el dato sucio sigue ahi hasta que lo limpies)." -ForegroundColor Yellow
Write-Host ""
Write-Host '  git add src\app\api\users\route.ts'
Write-Host '  git commit -m "fix: toggle_access tolerante a perfiles duplicados"'
Write-Host '  git push'

"use client";

import { useEffect } from "react";
import { useRouter, usePathname } from "next/navigation";
import { usePermissions } from "@/hooks/usePermissions";
import { useAuthStore } from "@/hooks/useAuth";

// Map URL paths to screen names
const PATH_TO_SCREEN: Record<string, string> = {
  "/dashboard": "dashboard",
  "/planificacion": "planificacion",
  "/obras": "obras",
  "/partes": "partes",
  "/aplicaciones/georadar": "apps_georadar",
  "/aplicaciones/georadar-v2": "apps_georadar_v2",
  "/maestros/recursos-humanos": "maestros_rrhh",
  "/almacen/articulos": "almacen_articulos",
  "/almacen/tipos-articulo": "almacen_tipos_articulo",
  "/almacen/almacenes": "almacen_almacenes",
  "/almacen/proveedores": "almacen_proveedores",
  "/almacen/movimientos": "almacen_movimientos",
  "/almacen/etiquetas": "almacen_etiquetas",
  "/maestros/vehiculos": "maestros_vehiculos",
  "/maestros/clientes": "maestros_clientes",
  "/maestros/estados-obra": "maestros_estados",
  "/maestros/tipos-trabajo": "maestros_tipos_trabajo",
  "/maestros/tipos-obra": "maestros_tipos_obra",
  "/maestros/contactos-leyna": "maestros_contactos_leyna",
  "/almacen/etiquetas": "almacen_etiquetas",
  "/logs": "logs",
  "/configuracion": "configuracion",
};

export function useRouteGuard() {
  const router = useRouter();
  const pathname = usePathname();
  const { user } = useAuthStore();
  const { canAccess, loaded } = usePermissions();

  useEffect(() => {
    if (!loaded || !user) return;

    // Find matching screen for current path
    const screen = Object.entries(PATH_TO_SCREEN).find(([path]) => pathname.startsWith(path))?.[1];
    if (!screen) return; // Unknown path, allow

    if (!canAccess(screen)) {
      router.replace("/dashboard");
    }
  }, [pathname, loaded, user, canAccess, router]);
}
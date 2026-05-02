"use client";

import { useEffect } from "react";
import { useRouter, usePathname } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { useAuthStore } from "@/hooks/useAuth";
import type { User } from "@/lib/types/database";

export default function AuthProvider({
  children,
}: {
  children: React.ReactNode;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const { setUser, setLoading } = useAuthStore();

  useEffect(() => {
    const supabase = createClient();

    const fetchUser = async () => {
      try {
        const {
          data: { session },
        } = await supabase.auth.getSession();

        if (!session) {
          setUser(null);
          setLoading(false);
          if (pathname !== "/login") {
            router.push("/login");
          }
          return;
        }

        // Fetch user profile
        const { data: profile } = await supabase
          .from("users")
          .select("*")
          .eq("id", session.user.id)
          .single();

        if (profile) {
          setUser(profile as User);
        } else {
          // First login — create profile
          try {
            const { count } = await supabase
              .from("users")
              .select("*", { count: "exact", head: true });

            const { data: created } = await (supabase.from("users") as any)
              .insert({
                id: session.user.id,
                email: session.user.email || "",
                nombre: session.user.email?.split("@")[0] || "Usuario",
                role: count === 0 ? "admin" : "partes",
                activo: true,
              })
              .select()
              .single();

            setUser((created as User) || null);
          } catch {
            setUser(null);
          }
        }

        setLoading(false);

        if (pathname === "/login") {
          router.push("/dashboard");
        }
      } catch {
        setUser(null);
        setLoading(false);
      }
    };

    fetchUser();

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === "SIGNED_OUT") {
        setUser(null);
        setLoading(false);
        router.push("/login");
      } else if (event === "SIGNED_IN") {
        fetchUser();
        // Log login - fire and forget, never blocks
        if (session?.user?.id) {
          supabase.rpc("log_user_login", {
            p_user_id: session.user.id,
            p_ip: null,
            p_user_agent: typeof navigator !== "undefined" ? navigator.userAgent : null,
          }).catch(() => {});
        }
      }
    });

    return () => subscription.unsubscribe();
  }, [pathname, router, setUser, setLoading]);

  return <>{children}</>;
}

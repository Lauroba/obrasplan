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
          if (pathname !== "/login") {
            router.push("/login");
          }
          return;
        }

        // Fetch user profile from our users table
        const { data: profile } = await supabase
          .from("users")
          .select("*")
          .eq("id", session.user.id)
          .single();

        if (profile) {
          setUser(profile as User);
        } else {
          // First login — create profile (admin by default for first user)
          const { count } = await supabase
            .from("users")
            .select("*", { count: "exact", head: true });

          const newUser: Partial<User> = {
            id: session.user.id,
            email: session.user.email || "",
            nombre: session.user.email?.split("@")[0] || "Usuario",
            role: count === 0 ? "admin" : "partes",
            activo: true,
          };

          const { data: created } = await supabase
            .from("users")
            .insert(newUser)
            .select()
            .single();

          setUser((created as User) || null);
        }

        if (pathname === "/login") {
          router.push("/dashboard");
        }
      } catch {
        setUser(null);
        setLoading(false);
      }
    };

    fetchUser();

    // Listen for auth changes
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange(async (event, session) => {
      if (event === "SIGNED_OUT") {
        setUser(null);
        router.push("/login");
      } else if (event === "SIGNED_IN") {
        fetchUser();
        // Log the login
        if (session?.user?.id) {
          try {
            await supabase.rpc("log_user_login", {
              p_user_id: session.user.id,
              p_ip: null,
              p_user_agent: typeof navigator !== "undefined" ? navigator.userAgent : null,
            });
          } catch (e) { /* ignore logging errors */ }
        }
      }
    });

    return () => subscription.unsubscribe();
  }, [pathname, router, setUser, setLoading]);

  return <>{children}</>;
}

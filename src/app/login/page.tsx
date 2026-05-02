"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { useRouter } from "next/navigation";
import Image from "next/image";
import { Eye, EyeOff, LogIn, Loader2 } from "lucide-react";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const router = useRouter();

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);

    try {
      const supabase = createClient();
      const { error: authError } = await supabase.auth.signInWithPassword({
        email,
        password,
      });

      if (authError) {
        if (authError.message.includes("Invalid login")) {
          setError("Email o contraseña incorrectos");
        } else {
          setError(authError.message);
        }
        return;
      }

      router.push("/dashboard");
    } catch {
      setError("Error de conexión. Inténtalo de nuevo.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex">
      {/* Left panel — Branding */}
      <div className="hidden lg:flex lg:w-1/2 bg-surface-950 relative overflow-hidden items-center justify-center">
        {/* Geometric background pattern */}
        <div className="absolute inset-0">
          <div className="absolute top-0 left-0 w-full h-full">
            <div className="absolute top-[-10%] right-[-5%] w-[500px] h-[500px] rounded-full bg-brand-600/10" />
            <div className="absolute bottom-[-15%] left-[-10%] w-[600px] h-[600px] rounded-full bg-brand-500/5" />
            <div className="absolute top-[40%] left-[30%] w-[300px] h-[300px] rounded-full bg-brand-700/8" />
          </div>
          {/* Grid pattern */}
          <div
            className="absolute inset-0 opacity-[0.03]"
            style={{
              backgroundImage: `linear-gradient(rgba(255,255,255,.1) 1px, transparent 1px),
                               linear-gradient(90deg, rgba(255,255,255,.1) 1px, transparent 1px)`,
              backgroundSize: "60px 60px",
            }}
          />
        </div>

        <div className="relative z-10 text-center px-12">
          <div className="w-28 h-28 mx-auto mb-8 relative">
            <Image src="/logo.png" alt="Loynek" fill className="object-contain" />
          </div>
          <h1 className="text-4xl font-display font-bold text-white mb-3">
            ObrasPlan
          </h1>
          <p className="text-surface-400 text-lg font-light">
            Planificación y gestión de obras
          </p>
          <div className="mt-12 flex items-center justify-center gap-8 text-surface-500">
            <div className="text-center">
              <p className="text-2xl font-display font-bold text-white">20+</p>
              <p className="text-xs mt-1">Obras simultáneas</p>
            </div>
            <div className="w-px h-10 bg-surface-700" />
            <div className="text-center">
              <p className="text-2xl font-display font-bold text-white">15</p>
              <p className="text-xs mt-1">Trabajadores</p>
            </div>
            <div className="w-px h-10 bg-surface-700" />
            <div className="text-center">
              <p className="text-2xl font-display font-bold text-white">50+</p>
              <p className="text-xs mt-1">Máquinas</p>
            </div>
          </div>
        </div>
      </div>

      {/* Right panel — Login form */}
      <div className="w-full lg:w-1/2 flex items-center justify-center p-8">
        <div className="w-full max-w-[400px]">
          {/* Mobile logo */}
          <div className="lg:hidden flex items-center gap-3 mb-10">
            <div className="w-10 h-10 relative">
              <Image src="/logo.png" alt="Loynek" fill className="object-contain" />
            </div>
            <div>
              <h1 className="font-display font-bold text-xl text-surface-900">
                ObrasPlan
              </h1>
              <p className="text-xs text-surface-400">Loynek Soluciones Técnicas</p>
            </div>
          </div>

          <div className="mb-8">
            <h2 className="text-2xl font-display font-bold text-surface-900">
              Iniciar sesión
            </h2>
            <p className="text-surface-500 mt-1.5">
              Accede a tu cuenta para gestionar las obras
            </p>
          </div>

          <form onSubmit={handleLogin} className="space-y-5">
            {error && (
              <div className="flex items-center gap-2 p-3.5 bg-red-50 border border-red-100 rounded-lg text-sm text-red-700 animate-fade-in">
                <svg className="w-4 h-4 shrink-0" fill="currentColor" viewBox="0 0 20 20">
                  <path
                    fillRule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z"
                    clipRule="evenodd"
                  />
                </svg>
                {error}
              </div>
            )}

            <div>
              <label className="block text-sm font-medium text-surface-700 mb-1.5">
                Email
              </label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoComplete="email"
                placeholder="tu@loynek.es"
                className="w-full px-4 py-2.5 bg-surface-50 border border-surface-200 rounded-lg text-sm
                           placeholder:text-surface-400
                           focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500
                           transition-all"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-surface-700 mb-1.5">
                Contraseña
              </label>
              <div className="relative">
                <input
                  type={showPassword ? "text" : "password"}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  autoComplete="current-password"
                  placeholder="••••••••"
                  className="w-full px-4 py-2.5 pr-11 bg-surface-50 border border-surface-200 rounded-lg text-sm
                             placeholder:text-surface-400
                             focus:outline-none focus:ring-2 focus:ring-brand-500/20 focus:border-brand-500
                             transition-all"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-surface-400 hover:text-surface-600 transition-colors"
                >
                  {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-brand-500 text-white
                         font-medium text-sm rounded-lg
                         hover:bg-brand-600 active:bg-brand-700
                         disabled:opacity-60 disabled:cursor-not-allowed
                         transition-all duration-150
                         focus:outline-none focus:ring-2 focus:ring-brand-500/30 focus:ring-offset-2"
            >
              {loading ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <LogIn className="w-4 h-4" />
              )}
              {loading ? "Accediendo..." : "Acceder"}
            </button>
          </form>

          <p className="text-center text-xs text-surface-400 mt-8">
            Loynek Soluciones Técnicas © {new Date().getFullYear()}
          </p>
        </div>
      </div>
    </div>
  );
}

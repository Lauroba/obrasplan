"use client";

import { useState, useRef, useEffect } from "react";
import { createClient } from "@/lib/supabase/client";
import { Camera, Loader2, X } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface PhotoUploadProps {
  currentUrl?: string | null;
  folder: string;
  entityId?: string;
  size?: "sm" | "md" | "lg";
  onUploaded: (url: string) => void;
  onRemoved?: () => void;
  className?: string;
}

const SIZES = { sm: "w-12 h-12", md: "w-20 h-20", lg: "w-28 h-28" };
const ICON_SIZES = { sm: "w-4 h-4", md: "w-6 h-6", lg: "w-8 h-8" };

export default function PhotoUpload({
  currentUrl, folder, entityId, size = "md", onUploaded, onRemoved, className
}: PhotoUploadProps) {
  const [uploading, setUploading] = useState(false);
  const [preview, setPreview] = useState<string | null>(currentUrl || null);
  const inputRef = useRef<HTMLInputElement>(null);
  const supabase = createClient();

  // Sync preview when currentUrl prop changes (modal reopen)
  useEffect(() => {
    setPreview(currentUrl || null);
  }, [currentUrl]);

  const handleFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (ev) => setPreview(ev.target?.result as string);
    reader.readAsDataURL(file);

    setUploading(true);
    try {
      const ext = file.name.split(".").pop() || "jpg";
      const path = `${folder}/${entityId || "new"}_${Date.now()}.${ext}`;
      if (currentUrl) {
        const oldPath = currentUrl.split("/avatars/")[1];
        if (oldPath) await supabase.storage.from("avatars").remove([oldPath]);
      }
      const { error } = await supabase.storage.from("avatars").upload(path, file, { upsert: true });
      if (error) { alert("Error al subir: " + error.message); setUploading(false); return; }
      const { data: urlData } = supabase.storage.from("avatars").getPublicUrl(path);
      onUploaded(urlData.publicUrl);
    } catch { alert("Error al subir foto"); }
    setUploading(false);
    if (inputRef.current) inputRef.current.value = "";
  };

  const handleRemove = async () => {
    // Delete from storage if there's a current URL
    if (currentUrl) {
      try {
        const parts = currentUrl.split("/avatars/");
        if (parts[1]) {
          await supabase.storage.from("avatars").remove([decodeURIComponent(parts[1])]);
        }
      } catch (err) {
        console.error("Error deleting from storage:", err);
      }
    }
    setPreview(null);
    onRemoved?.();
  };

  return (
    <div className={cn("relative group", className)}>
      <div className={cn("rounded-full overflow-hidden bg-surface-100 flex items-center justify-center border-2 border-surface-200 cursor-pointer hover:border-brand-300 transition-colors", SIZES[size])}
        onClick={() => inputRef.current?.click()}>
        {uploading ? (
          <Loader2 className={cn("text-brand-500 animate-spin", ICON_SIZES[size])} />
        ) : preview ? (
          <img src={preview} alt="" className="w-full h-full object-cover" />
        ) : (
          <Camera className={cn("text-surface-400", ICON_SIZES[size])} />
        )}
      </div>
      {preview && !uploading && (
        <button type="button" onClick={handleRemove}
          className="absolute -top-1 -right-1 w-5 h-5 bg-red-500 text-white rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity shadow-sm">
          <X className="w-3 h-3" />
        </button>
      )}
      <input ref={inputRef} type="file" accept="image/*" className="hidden" onChange={handleFile} />
    </div>
  );
}

"use client";

import { useState, useRef, useEffect } from "react";
import { Mic, Square, Upload, Trash2, Play, Pause, Loader2, FileText, Languages } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { createClient } from "@/lib/supabase/client";

interface AudioRecorderProps {
  parteId: string;
  audios: { id: string; nombre_archivo: string; storage_path: string; duracion: number | null; created_at: string }[];
  onChanged: () => void;
  onTranscription: (audioLabel: string, text: string) => void;
  disabled?: boolean;
}

export default function AudioRecorder({ parteId, audios, onChanged, onTranscription, disabled }: AudioRecorderProps) {
  const supabase = createClient();
  const [recording, setRecording] = useState(false);
  const [recordTime, setRecordTime] = useState(0);
  const [uploading, setUploading] = useState(false);
  const [transcribing, setTranscribing] = useState<string | null>(null); // audioId or "new"
  const [playingId, setPlayingId] = useState<string | null>(null);
  const mediaRecorder = useRef<MediaRecorder | null>(null);
  const chunks = useRef<Blob[]>([]);
  const timerRef = useRef<NodeJS.Timeout | null>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => { return () => { if (timerRef.current) clearInterval(timerRef.current); }; }, []);

  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const recorder = new MediaRecorder(stream, { mimeType: MediaRecorder.isTypeSupported("audio/webm") ? "audio/webm" : "audio/mp4" });
      chunks.current = [];

      recorder.ondataavailable = (e) => { if (e.data.size > 0) chunks.current.push(e.data); };
      recorder.onstop = async () => {
        stream.getTracks().forEach((t) => t.stop());
        const blob = new Blob(chunks.current, { type: recorder.mimeType });
        const audioNum = audios.length + 1;
        const ext = recorder.mimeType.includes("webm") ? "webm" : "mp4";
        const fileName = `Audio_${audioNum}_${new Date().toISOString().slice(0, 10)}.${ext}`;
        await uploadAndTranscribe(blob, fileName, recordTime, audioNum);
      };

      mediaRecorder.current = recorder;
      recorder.start();
      setRecording(true);
      setRecordTime(0);
      timerRef.current = setInterval(() => setRecordTime((t) => t + 1), 1000);
    } catch (err) {
      alert("No se pudo acceder al micrófono. Permite el acceso en tu navegador.");
    }
  };

  const stopRecording = () => {
    if (mediaRecorder.current && recording) {
      mediaRecorder.current.stop();
      setRecording(false);
      if (timerRef.current) clearInterval(timerRef.current);
    }
  };

  const uploadAndTranscribe = async (blob: Blob, fileName: string, duration: number, audioNum: number) => {
    setUploading(true);
    const path = `partes/${parteId}/${Date.now()}_${fileName}`;
    const { error } = await supabase.storage.from("audios").upload(path, blob);
    if (error) { alert("Error al subir audio: " + error.message); setUploading(false); return; }
    await (supabase.from("parte_audios") as any).insert({
      parte_id: parteId, nombre_archivo: fileName, storage_path: path,
      duracion: duration, tamano: blob.size,
    });
    setUploading(false);
    onChanged();

    // Transcribe with Whisper
    setTranscribing("new");
    try {
      const formData = new FormData();
      formData.append("audio", blob, fileName);
      const res = await fetch("/api/transcribe", { method: "POST", body: formData });
      const data = await res.json();
      if (data.text) {
        onTranscription(`Audio ${audioNum}`, data.text);
      }
    } catch (err) {
      console.error("Transcription error:", err);
    }
    setTranscribing(null);
  };

  const transcribeExisting = async (audio: typeof audios[0], idx: number) => {
    setTranscribing(audio.id);
    try {
      // Download audio from Supabase
      const { data: signedData } = await supabase.storage.from("audios").createSignedUrl(audio.storage_path, 120);
      if (!signedData?.signedUrl) { setTranscribing(null); return; }

      const audioRes = await fetch(signedData.signedUrl);
      const audioBlob = await audioRes.blob();

      const formData = new FormData();
      formData.append("audio", audioBlob, audio.nombre_archivo || "audio.webm");
      const res = await fetch("/api/transcribe", { method: "POST", body: formData });
      const data = await res.json();
      if (data.text) {
        onTranscription(`Audio ${idx + 1}`, data.text);
      } else if (data.error) {
        alert("Error transcripción: " + data.error);
      }
    } catch (err: any) {
      alert("Error: " + err.message);
    }
    setTranscribing(null);
  };

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    const path = `partes/${parteId}/${Date.now()}_${file.name}`;
    const { error } = await supabase.storage.from("audios").upload(path, file);
    if (error) { alert("Error: " + error.message); setUploading(false); return; }
    await (supabase.from("parte_audios") as any).insert({
      parte_id: parteId, nombre_archivo: file.name, storage_path: path, tamano: file.size,
    });
    setUploading(false);
    if (fileInputRef.current) fileInputRef.current.value = "";
    onChanged();
  };

  const handleDelete = async (audio: typeof audios[0]) => {
    await supabase.storage.from("audios").remove([audio.storage_path]);
    await (supabase.from("parte_audios") as any).delete().eq("id", audio.id);
    onChanged();
  };

  const handlePlay = async (audio: typeof audios[0]) => {
    if (playingId === audio.id) {
      audioRef.current?.pause();
      setPlayingId(null);
      return;
    }
    const { data } = await supabase.storage.from("audios").createSignedUrl(audio.storage_path, 120);
    if (data?.signedUrl) {
      if (audioRef.current) audioRef.current.pause();
      const a = new Audio(data.signedUrl);
      a.onended = () => setPlayingId(null);
      a.play();
      audioRef.current = a;
      setPlayingId(audio.id);
    }
  };

  const formatTime = (s: number) => `${Math.floor(s / 60).toString().padStart(2, "0")}:${(s % 60).toString().padStart(2, "0")}`;

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <label className="text-sm font-medium text-surface-700">Audios</label>
        {!disabled && (
          <div className="flex items-center gap-2">
            <input ref={fileInputRef} type="file" accept="audio/*" className="hidden" onChange={handleFileUpload} />
            <button type="button" onClick={() => fileInputRef.current?.click()} disabled={uploading}
              className="flex items-center gap-1 px-2.5 py-1.5 text-[11px] font-medium text-surface-600 bg-surface-100 rounded-lg hover:bg-surface-200 disabled:opacity-60">
              <Upload className="w-3 h-3" /> Subir
            </button>
            {!recording ? (
              <button type="button" onClick={startRecording} disabled={uploading}
                className="flex items-center gap-1 px-2.5 py-1.5 text-[11px] font-medium text-white bg-red-500 rounded-lg hover:bg-red-600 disabled:opacity-60">
                <Mic className="w-3 h-3" /> Grabar
              </button>
            ) : (
              <button type="button" onClick={stopRecording}
                className="flex items-center gap-1 px-2.5 py-1.5 text-[11px] font-medium text-white bg-red-600 rounded-lg animate-pulse">
                <Square className="w-3 h-3" /> {formatTime(recordTime)} — Parar
              </button>
            )}
          </div>
        )}
      </div>

      {transcribing === "new" && (
        <div className="flex items-center gap-2 text-xs text-violet-600 bg-violet-50 px-3 py-2 rounded-lg">
          <Loader2 className="w-3.5 h-3.5 animate-spin" /> Transcribiendo audio con Whisper AI...
        </div>
      )}

      {uploading && <div className="flex items-center gap-2 text-sm text-surface-500"><Loader2 className="w-4 h-4 animate-spin" />Subiendo audio...</div>}

      {audios.length === 0 && !recording ? (
        <p className="text-xs text-surface-400 py-3 text-center">Sin audios. Graba y se transcribirá automáticamente con IA.</p>
      ) : (
        <div className="space-y-1.5">
          {audios.map((a, idx) => (
            <div key={a.id} className="flex items-center gap-3 p-2.5 bg-surface-50 rounded-lg border border-surface-100 group">
              <button type="button" onClick={() => handlePlay(a)} className={cn("w-8 h-8 rounded-full flex items-center justify-center shrink-0 transition-colors",
                playingId === a.id ? "bg-brand-500 text-white" : "bg-surface-200 text-surface-600 hover:bg-brand-100")}>
                {playingId === a.id ? <Pause className="w-3.5 h-3.5" /> : <Play className="w-3.5 h-3.5 ml-0.5" />}
              </button>
              <div className="flex-1 min-w-0">
                <p className="text-xs font-medium text-surface-900 truncate">Audio {idx + 1} — {a.nombre_archivo}</p>
                <p className="text-[10px] text-surface-400">
                  {a.duracion ? formatTime(a.duracion) : ""} · {new Date(a.created_at).toLocaleDateString("es-ES")}
                </p>
              </div>
              <div className="flex items-center gap-1">
                {/* Transcribe button */}
                <button type="button" onClick={() => transcribeExisting(a, idx)} disabled={transcribing === a.id}
                  className={cn("flex items-center gap-1 px-2 py-1 text-[10px] font-medium rounded-lg transition-colors",
                    transcribing === a.id ? "bg-violet-100 text-violet-600" : "text-violet-600 bg-violet-50 hover:bg-violet-100 opacity-0 group-hover:opacity-100")}>
                  {transcribing === a.id ? <Loader2 className="w-3 h-3 animate-spin" /> : <Languages className="w-3 h-3" />}
                  {transcribing === a.id ? "..." : "Transcribir"}
                </button>
                {!disabled && (
                  <button type="button" onClick={() => handleDelete(a)} className="p-1 rounded text-surface-300 hover:text-red-500 opacity-0 group-hover:opacity-100">
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

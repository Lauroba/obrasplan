// =============================================================================
// Tipos generados manualmente desde el esquema de base de datos.
// En producción, usar: npx supabase gen types typescript --local > database.ts
// =============================================================================

export type UserRole = "admin" | "lectura" | "partes";
export type ObraEstado = "planificada" | "en_curso" | "pausada" | "finalizada" | "cerrada";
export type FaseEstado = "pendiente" | "en_curso" | "completada";
export type RecursoTipo = "humano" | "maquinaria" | "vehiculo" | "material";
export type ParteEstado = "borrador" | "pendiente" | "aprobado" | "rechazado" | "firmado";
export type DocumentoTipo = "foto" | "pdf" | "documento";
export type DocumentoCategoria = "antes" | "durante" | "despues" | "general";
export type RecursoEstado = "disponible" | "en_uso" | "mantenimiento" | "baja";
export type AuditAccion = "crear" | "editar" | "eliminar" | "aprobar" | "rechazar" | "login" | "logout";
export type TareaPrioridad = "alta" | "media" | "baja";
export type TareaEstado = "pendiente" | "completada";

// --- Entidades principales ---

export interface User {
  id: string;
  email: string;
  nombre: string;
  role: UserRole;
  rol_id: string | null;
  recurso_id: string | null;
  avatar_url: string | null;
  activo: boolean;
  created_at: string;
  updated_at: string;
}

export interface Cliente {
  id: string;
  nombre: string;
  contacto: string | null;
  telefono: string | null;
  email: string | null;
  direccion: string | null;
  activo: boolean;
  created_at: string;
  updated_at: string;
}

export interface RecursoHumano {
  id: string;
  nombre: string;
  perfil: string | null;
  telefono: string | null;
  email: string | null;
  observaciones: string | null;
  foto_url: string | null;
  activo: boolean;
  created_at: string;
  updated_at: string;
}

export interface Maquinaria {
  id: string;
  nombre: string;
  tipo: string | null;
  estado: RecursoEstado;
  observaciones: string | null;
  foto_url: string | null;
  activo: boolean;
  created_at: string;
  updated_at: string;
}

export interface Vehiculo {
  id: string;
  nombre: string;
  matricula: string | null;
  tipo: string | null;
  estado: RecursoEstado;
  observaciones: string | null;
  foto_url: string | null;
  activo: boolean;
  created_at: string;
  updated_at: string;
}

export interface Material {
  id: string;
  nombre: string;
  tipo: string | null;
  unidad: string | null;
  observaciones: string | null;
  foto_url: string | null;
  activo: boolean;
  created_at: string;
  updated_at: string;
}

export interface EstadoObra {
  id: string;
  nombre: string;
  color: string;
  activo: boolean;
  created_at: string;
}

export interface Obra {
  id: string;
  nombre: string;
  cliente_id: string | null;
  ubicacion: string | null;
  fecha_inicio: string;
  fecha_fin: string | null;
  estado: ObraEstado;
  estado_obra_id: string | null;
  fase_actual: string | null;
  observaciones: string | null;
  color: string | null;
  archivada: boolean;
  orden_gantt: number;
  created_by: string | null;
  created_at: string;
  updated_at: string;
  // Joins
  cliente?: Cliente | null;
  estado_custom?: EstadoObra | null;
  fases?: ObraFase[];
  asignaciones?: Asignacion[];
}

export interface ObraFase {
  id: string;
  obra_id: string;
  nombre: string;
  fecha_inicio: string | null;
  fecha_fin: string | null;
  estado: FaseEstado;
  orden: number;
  observaciones: string | null;
  created_at: string;
  updated_at: string;
}

export interface Asignacion {
  id: string;
  obra_id: string;
  fase_id: string | null;
  recurso_tipo: RecursoTipo;
  recurso_id: string;
  fecha_inicio: string;
  fecha_fin: string;
  cantidad: number | null;
  unidad: string | null;
  observaciones: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
  // Joins
  obra?: Obra;
  recurso_humano?: RecursoHumano;
  maquinaria_ref?: Maquinaria;
  vehiculo_ref?: Vehiculo;
  material_ref?: Material;
}

export interface ParteDiario {
  id: string;
  obra_id: string | null;
  fecha: string;
  created_by: string;
  descripcion: string | null;
  incidencias: string | null;
  observaciones: string | null;
  estado: ParteEstado;
  firma_data: string | null;
  firma_cliente: string | null;
  jefe_obra: string | null;
  encargado_obra: string | null;
  responsable_empresa: string | null;
  direccion: string | null;
  localidad: string | null;
  provincia: string | null;
  aprobado_by: string | null;
  aprobado_at: string | null;
  motivo_rechazo: string | null;
  created_at: string;
  updated_at: string;
  // Joins
  obra?: Obra;
  user?: User;
  lineas?: ParteLinea[];
  trabajadores?: ParteTrabajador[];
  maquinaria_items?: ParteMaquinaria[];
  vehiculos_items?: ParteVehiculo[];
  materiales_items?: ParteMaterial[];
  documentos?: Documento[];
  audios?: ParteAudio[];
}

export interface TipoTrabajo {
  id: string;
  nombre: string;
  activo: boolean;
  created_at: string;
}

export interface ParteLinea {
  id: string;
  parte_id: string;
  orden: number;
  concepto: string;
  tipo_trabajo_id: string | null;
  fabricante: string | null;
  producto: string | null;
  unidades: string | null;
  cantidad: number | null;
  observaciones: string | null;
  created_at: string;
  tipo_trabajo?: TipoTrabajo;
}

export interface ParteAudio {
  id: string;
  parte_id: string;
  nombre_archivo: string;
  storage_path: string;
  duracion: number | null;
  tamano: number | null;
  uploaded_by: string | null;
  created_at: string;
}

export interface ParteTrabajador {
  id: string;
  parte_id: string;
  recurso_id: string;
  hora_entrada: string | null;
  hora_salida: string | null;
  observaciones: string | null;
  // Joins
  recurso?: RecursoHumano;
}

export interface ParteMaquinaria {
  id: string;
  parte_id: string;
  maquinaria_id: string;
  observaciones: string | null;
  maquinaria?: Maquinaria;
}

export interface ParteVehiculo {
  id: string;
  parte_id: string;
  vehiculo_id: string;
  observaciones: string | null;
  vehiculo?: Vehiculo;
}

export interface ParteMaterial {
  id: string;
  parte_id: string;
  material_id: string;
  cantidad: number;
  unidad: string | null;
  observaciones: string | null;
  material?: Material;
}

export interface TipoTarea {
  id: string;
  nombre: string;
  activo: boolean;
  created_at: string;
}

export interface Tarea {
  id: string;
  obra_id: string;
  descripcion: string;
  tipo_tarea_id: string | null;
  prioridad: TareaPrioridad;
  estado: TareaEstado;
  fecha_limite: string | null;
  asignado_a: string | null;
  comentario_cierre: string | null;
  completada_at: string | null;
  completada_by: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
  // Joins
  tipo_tarea?: TipoTarea;
  recurso_asignado?: RecursoHumano;
  obra?: Obra;
}

export interface Documento {
  id: string;
  obra_id: string;
  parte_id: string | null;
  nombre_archivo: string;
  tipo: DocumentoTipo;
  categoria: DocumentoCategoria;
  storage_path: string;
  tamano: number | null;
  mime_type: string | null;
  uploaded_by: string | null;
  created_at: string;
}

export interface AuditLog {
  id: string;
  user_id: string | null;
  accion: AuditAccion;
  entidad: string;
  entidad_id: string | null;
  valor_anterior: Record<string, unknown> | null;
  valor_nuevo: Record<string, unknown> | null;
  ip_address: string | null;
  user_agent: string | null;
  created_at: string;
  user?: User;
}

export interface Configuracion {
  id: string;
  clave: string;
  valor: Record<string, unknown>;
  updated_at: string;
}

// --- Tipos para conflictos ---

export interface Conflicto {
  conflicto_id: string;
  obra_id: string;
  obra_nombre: string;
  fecha_inicio: string;
  fecha_fin: string;
}

// --- Tipo para Supabase (simplificado para compatibilidad) ---

export interface Database {
  public: {
    Tables: {
      users: { Row: User; Insert: Partial<User> & Pick<User, "id" | "email" | "nombre">; Update: Partial<User> };
      clientes: { Row: Cliente; Insert: Partial<Cliente> & Pick<Cliente, "nombre">; Update: Partial<Cliente> };
      recursos_humanos: { Row: RecursoHumano; Insert: Partial<RecursoHumano> & Pick<RecursoHumano, "nombre">; Update: Partial<RecursoHumano> };
      maquinaria: { Row: Maquinaria; Insert: Partial<Maquinaria> & Pick<Maquinaria, "nombre">; Update: Partial<Maquinaria> };
      vehiculos: { Row: Vehiculo; Insert: Partial<Vehiculo> & Pick<Vehiculo, "nombre">; Update: Partial<Vehiculo> };
      materiales: { Row: Material; Insert: Partial<Material> & Pick<Material, "nombre">; Update: Partial<Material> };
      obras: { Row: Obra; Insert: Partial<Obra> & Pick<Obra, "nombre" | "fecha_inicio">; Update: Partial<Obra> };
      obra_fases: { Row: ObraFase; Insert: Partial<ObraFase> & Pick<ObraFase, "obra_id" | "nombre">; Update: Partial<ObraFase> };
      asignaciones: { Row: Asignacion; Insert: Partial<Asignacion> & Pick<Asignacion, "obra_id" | "recurso_tipo" | "recurso_id" | "fecha_inicio" | "fecha_fin">; Update: Partial<Asignacion> };
      partes_diarios: { Row: ParteDiario; Insert: Partial<ParteDiario> & Pick<ParteDiario, "obra_id" | "fecha" | "created_by">; Update: Partial<ParteDiario> };
      parte_trabajadores: { Row: ParteTrabajador; Insert: Partial<ParteTrabajador> & Pick<ParteTrabajador, "parte_id" | "recurso_id">; Update: Partial<ParteTrabajador> };
      parte_maquinaria: { Row: ParteMaquinaria; Insert: Partial<ParteMaquinaria> & Pick<ParteMaquinaria, "parte_id" | "maquinaria_id">; Update: Partial<ParteMaquinaria> };
      parte_vehiculos: { Row: ParteVehiculo; Insert: Partial<ParteVehiculo> & Pick<ParteVehiculo, "parte_id" | "vehiculo_id">; Update: Partial<ParteVehiculo> };
      parte_materiales: { Row: ParteMaterial; Insert: Partial<ParteMaterial> & Pick<ParteMaterial, "parte_id" | "material_id" | "cantidad">; Update: Partial<ParteMaterial> };
      documentos: { Row: Documento; Insert: Partial<Documento> & Pick<Documento, "obra_id" | "nombre_archivo" | "storage_path">; Update: Partial<Documento> };
      audit_log: { Row: AuditLog; Insert: Partial<AuditLog> & Pick<AuditLog, "accion" | "entidad">; Update: Partial<AuditLog> };
      configuracion: { Row: Configuracion; Insert: Partial<Configuracion> & Pick<Configuracion, "clave" | "valor">; Update: Partial<Configuracion> };
    };
    Functions: {
      check_asignacion_conflictos: {
        Args: { p_recurso_tipo: RecursoTipo; p_recurso_id: string; p_fecha_inicio: string; p_fecha_fin: string; p_exclude_id?: string };
        Returns: Conflicto[];
      };
      get_user_role: { Args: Record<string, never>; Returns: UserRole };
      get_user_recurso_id: { Args: Record<string, never>; Returns: string };
    };
    Enums: {
      user_role: UserRole;
      obra_estado: ObraEstado;
      fase_estado: FaseEstado;
      recurso_tipo: RecursoTipo;
      parte_estado: ParteEstado;
      documento_tipo: DocumentoTipo;
      documento_categoria: DocumentoCategoria;
      recurso_estado: RecursoEstado;
      audit_accion: AuditAccion;
    };
  };
}

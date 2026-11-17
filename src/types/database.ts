export type UserRole = 'ADMIN' | 'PROVIDER_ESTIMATOR' | 'AUDITOR' | 'CLIENT_VIEWER';
export type EventStatus = 'DRAFT' | 'OPEN' | 'IN_REVIEW' | 'AWARDED' | 'CLOSED';
export type ResourceType = 'LABOR' | 'EQUIPMENT';
export type CalculationMode = 'MULTIPLICATION' | 'DIVISION';
export type ApuStatus = 'PENDING' | 'IN_PROGRESS' | 'COMPLETED';
export type AuditAction = 'CREATE' | 'READ' | 'UPDATE' | 'DELETE' | 'DENIED';

export interface AuditLog {
  id_log: string;
  id_user?: string | null;
  user_role: string;
  action: AuditAction;
  entity_type: string;
  entity_id?: string | null;
  details?: Record<string, any>;
  ip_address?: string | null;
  user_agent?: string | null;
  created_at: string;
}

export interface EventProviderAssignment {
  id_assignment: string;
  id_event: number;
  id_provider: number;
  access_role: 'READ' | 'WRITE' | 'SUBMITTED';
  assigned_at: string;
}

export interface AppUser {
  id_user: string;
  email: string;
  full_name: string;
  role: UserRole;
  is_active: boolean;
  created_at: string;
}

export interface Client {
  id_client: number;
  client_name: string;
  client_department?: string;
  created_at: string;
}

export interface Provider {
  id_provider: number;
  tag_provider: string;
  provider_name: string;
  provider_representative?: string;
  provider_position?: string;
  contact_email?: string;
  created_at: string;
}

export interface Event {
  id_event: number;
  tag_event: string;
  event_type: string;
  event_description: string;
  id_client: number;
  status: EventStatus;
  submission_deadline?: string;
  created_at: string;
  client?: Client;
}

export interface EventInvitation {
  id_invitation: string;
  id_event: number;
  id_provider?: number;
  invited_email: string;
  token: string;
  expires_at: string;
  is_accepted: boolean;
  accepted_at?: string;
  created_at: string;
}

export interface Concept {
  id_concept: number;
  id_event: number;
  id_client: number;
  tag_concept: string;
  concept_header?: string;
  concept_description: string;
  concept_unit: string;
  concept_price?: number | null;
  concept_price_txt?: string | null;
  display_order?: number;
  created_at: string;
}

export interface CatalogMaterial {
  id_catalog_material: number;
  tag_catalog_material?: string;
  catalog_material_description: string;
  catalog_material_unit: string;
  catalog_material_brand?: string;
  catalog_material_model?: string;
  catalog_material_unit_price: number;
}

export interface CatalogLabor {
  id_catalog_labor: number;
  tag_catalog_labor?: string;
  catalog_labor_category: string;
  catalog_labor_unit: string;
  catalog_labor_unit_price: number;
}

export interface CatalogEquipment {
  id_catalog_equipment: number;
  tag_catalog_equipment?: string;
  catalog_equipment_description: string;
  catalog_equipment_unit: string;
  catalog_equipment_brand?: string;
  catalog_equipment_model?: string;
  catalog_equipment_year?: number;
  catalog_equipment_unit_price: number;
}

export interface ConceptPerformanceGroup {
  id_performance_group: string;
  id_concept: number;
  resource_type: ResourceType;
  performance_factor: number;
  performance_unit: string;
  calculation_mode: CalculationMode;
  notes?: string;
  created_at: string;
}

export interface ConceptApuIntegration {
  id_apu: string;
  id_concept: number;
  id_provider: number;
  pct_indirects: number;
  pct_financing: number;
  pct_utility: number;
  pct_safety_equipment: number;
  pct_hand_tools: number;
  apply_sfp: boolean;
  subtotal_materials: number;
  subtotal_labor: number;
  subtotal_equipment: number;
  subtotal_safety_tools: number;
  cost_direct_a: number;
  cost_indirect_b: number;
  cost_sum_c: number;
  cost_financing_d: number;
  cost_sum_e: number;
  cost_utility_f: number;
  cost_sum_g: number;
  cost_sfp: number;
  concept_price: number;
  concept_price_txt?: string;
  status: ApuStatus;
  updated_at: string;
}

export interface MaterialByConcept {
  id_material_by_concept: string;
  id_apu: string;
  id_concept: number;
  id_catalog_material?: number;
  material_description: string;
  unit: string;
  quantity: number;
  unit_price: number;
  total_price: number;
}

export interface LaborByConcept {
  id_labor_by_concept: string;
  id_apu: string;
  id_concept: number;
  id_performance_group?: string;
  id_catalog_labor?: number;
  category: string;
  unit: string;
  quantity: number;
  unit_price: number;
  total_price: number;
}

export interface EquipmentByConcept {
  id_equipment_by_concept: string;
  id_apu: string;
  id_concept: number;
  id_performance_group?: string;
  id_catalog_equipment?: number;
  equipment_description: string;
  unit: string;
  quantity: number;
  unit_price: number;
  total_price: number;
}

export interface EventDashboardView {
  id_event: number;
  tag_event: string;
  event_type: string;
  event_description: string;
  client_name: string;
  status: EventStatus;
  submission_deadline?: string;
  total_concepts: number;
  total_services: number;
  integrated_services_count: number;
  service_completion_percentage: number;
  total_parts: number;
  priced_parts_count: number;
  parts_completion_percentage: number;
  overall_completion_percentage: number;
}

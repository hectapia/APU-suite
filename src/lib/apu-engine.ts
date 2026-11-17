import { numberToWordsEs } from './number-to-words.ts';

export interface APUInputs {
  materialItems: Array<{ quantity: number; unitPrice: number }>;
  laborItems: Array<{ quantity: number; unitPrice: number }>;
  equipmentItems: Array<{ quantity: number; unitPrice: number }>;
  laborPerformanceFactor?: number;
  equipmentPerformanceFactor?: number;
  pctIndirects?: number; // default 0.1500 (15%)
  pctFinancing?: number; // default 0.0150 (1.5%)
  pctUtility?: number;   // default 0.1500 (15%)
  pctSafetyEquipment?: number; // default 0.0150 (1.5%)
  pctHandTools?: number;       // default 0.0300 (3.0%)
  applySfp?: boolean;          // default false
}

export interface APUOutputs {
  subtotalMaterials: number;
  subtotalLabor: number;
  subtotalEquipment: number;
  subtotalSafetyTools: number;
  costDirectA: number;
  costIndirectB: number;
  costSumC: number;
  costFinancingD: number;
  costSumE: number;
  costUtilityF: number;
  costSumG: number;
  costSfp: number;
  conceptPrice: number;
  conceptPriceTxt: string;
}

/**
 * Truncates / rounds a number to 2 decimal places to match Mexican public works standard math.
 */
export function roundCurr(val: number): number {
  return Math.floor((val + 0.0000001) * 100) / 100;
}

/**
 * Executes the full deterministic APU cascade from direct resources to final selling unit price.
 */
export function calculateAPU(inputs: APUInputs): APUOutputs {
  const {
    materialItems,
    laborItems,
    equipmentItems,
    laborPerformanceFactor = 1.0,
    equipmentPerformanceFactor = 1.0,
    pctIndirects = 0.15,
    pctFinancing = 0.015,
    pctUtility = 0.15,
    pctSafetyEquipment = 0.015,
    pctHandTools = 0.03,
    applySfp = false,
  } = inputs;

  // 1. Materials Subtotal
  const rawMatSum = materialItems.reduce(
    (acc, item) => acc + roundCurr(item.quantity * item.unitPrice),
    0
  );
  const subtotalMaterials = roundCurr(rawMatSum);

  // 2. Labor Subtotal (Crew daily cost * global performance yield)
  const rawLaborCrew = laborItems.reduce(
    (acc, item) => acc + roundCurr(item.quantity * item.unitPrice),
    0
  );
  const subtotalLabor = roundCurr(rawLaborCrew * laborPerformanceFactor);

  // 3. Equipment Subtotal (Hourly rates * global machinery yield)
  const rawEquipmentSum = equipmentItems.reduce(
    (acc, item) => acc + roundCurr(item.quantity * item.unitPrice),
    0
  );
  const subtotalEquipment = roundCurr(rawEquipmentSum * equipmentPerformanceFactor);

  // 4. Safety Equipment and Minor Hand Tools (Calculated on Labor Subtotal)
  const costSafety = roundCurr(pctSafetyEquipment * subtotalLabor);
  const costTools = roundCurr(pctHandTools * subtotalLabor);
  const subtotalSafetyTools = roundCurr(costSafety + costTools);

  // Direct Cost A = (1 + 2 + 3 + 4)
  const costDirectA = roundCurr(
    subtotalMaterials + subtotalLabor + subtotalEquipment + subtotalSafetyTools
  );

  // B = Indirects
  const costIndirectB = roundCurr(costDirectA * pctIndirects);

  // C = A + B
  const costSumC = roundCurr(costDirectA + costIndirectB);

  // D = Financing
  const costFinancingD = roundCurr(costSumC * pctFinancing);

  // E = C + D
  const costSumE = roundCurr(costSumC + costFinancingD);

  // F = Utility / Profit
  const costUtilityF = roundCurr(costSumE * pctUtility);

  // G = E + F
  const costSumG = roundCurr(costSumE + costUtilityF);

  // SFP 5 al millar (if applied: (G / 0.995) - G)
  let costSfp = 0;
  if (applySfp) {
    costSfp = roundCurr(costSumG / 0.995 - costSumG);
  }

  // Final Concept Unitary Selling Price
  const conceptPrice = roundCurr(costSumG + costSfp);
  const conceptPriceTxt = numberToWordsEs(conceptPrice);

  return {
    subtotalMaterials,
    subtotalLabor,
    subtotalEquipment,
    subtotalSafetyTools,
    costDirectA,
    costIndirectB,
    costSumC,
    costFinancingD,
    costSumE,
    costUtilityF,
    costSumG,
    costSfp,
    conceptPrice,
    conceptPriceTxt,
  };
}

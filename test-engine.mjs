// Verification test: Concept 480 from Abstract.xlsx
import { calculateAPU } from './src/lib/apu-engine.ts';

const concept480Inputs = {
  materialItems: [
    { quantity: 6, unitPrice: 211.31 }, // Kit de ligas y sellos
    { quantity: 2, unitPrice: 236.26 }, // Líquido limpiador
    { quantity: 1, unitPrice: 822.00 }, // Filtro separador
    { quantity: 1, unitPrice: 327.40 }, // Filtro primario
    { quantity: 1, unitPrice: 255.00 }, // Aditivo acondicionador
    { quantity: 1, unitPrice: 145.00 }, // Desengrasante dieléctrico
    { quantity: 1, unitPrice: 65.00 }   // Estopa de algodón
  ],
  laborItems: [
    { quantity: 1, unitPrice: 2946.22 }, // Operario especialista hidráulica
    { quantity: 1, unitPrice: 1089.29 }  // Ayudante
  ],
  equipmentItems: [
    { quantity: 1, unitPrice: 650.00 }, // Banco de pruebas
    { quantity: 1, unitPrice: 180.00 }, // Tina de ultrasonido
    { quantity: 1, unitPrice: 320.00 }, // Escáner diagnóstico
    { quantity: 1, unitPrice: 110.00 }, // Compresor aire
    { quantity: 1, unitPrice: 45.00 },  // Torquímetro
    { quantity: 1, unitPrice: 60.00 }   // Juego extractores
  ],
  laborPerformanceFactor: 1.0,
  equipmentPerformanceFactor: 1.0,
  pctIndirects: 0.15,
  pctFinancing: 0.015,
  pctUtility: 0.15,
  pctSafetyEquipment: 0.015,
  pctHandTools: 0.03,
  applySfp: false
};

const result = calculateAPU(concept480Inputs);
console.log('--- APU ENGINE VERIFICATION (Concept 480) ---');
console.log('Subtotal Materials (1) :', result.subtotalMaterials, 'Expected: 3354.78');
console.log('Subtotal Labor (2)     :', result.subtotalLabor, 'Expected: 4035.51');
console.log('Subtotal Equipment (3) :', result.subtotalEquipment, 'Expected: 1365.00');
console.log('Safety & Tools (4)     :', result.subtotalSafetyTools, 'Expected: 181.59');
console.log('Direct Cost A          :', result.costDirectA, 'Expected: 8936.88');
console.log('Indirects B (15%)      :', result.costIndirectB, 'Expected: 1340.53');
console.log('Subtotal C (A+B)       :', result.costSumC, 'Expected: 10277.41');
console.log('Financing D (1.5%)     :', result.costFinancingD, 'Expected: 154.16');
console.log('Subtotal E (C+D)       :', result.costSumE, 'Expected: 10431.57');
console.log('Utility F (15%)        :', result.costUtilityF, 'Expected: 1564.73');
console.log('Subtotal G (E+F)       :', result.costSumG, 'Expected: 11996.30');
console.log('Final Concept Price    :', result.conceptPrice, 'Expected: 11996.30');
console.log('Price in Words         :', result.conceptPriceTxt);

const match = result.conceptPrice === 11996.30;
if (match) {
  console.log('\n>>> SUCCESS: Exact penny-parity match with Abstract.xlsx DT-7 template! <<<');
} else {
  console.error('\n>>> ERROR: Mismatch detected! <<<');
  process.exit(1);
}

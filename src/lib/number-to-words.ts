/**
 * Converts a numeric amount to Mexican Spanish financial legal tender words.
 * Example: 11996.30 -> "( ONCE MIL NOVECIENTOS NOVENTA Y SEIS PESOS 30/100 M.N. )"
 */
function centenasEs(n: number): string {
  const c = Math.floor(n / 100);
  const d = Math.floor((n % 100) / 10);
  const u = n % 10;
  let res = '';

  // Centenas
  if (c === 1 && (d > 0 || u > 0)) res = 'CIENTO ';
  else if (c === 1) res = 'CIEN ';
  else if (c === 2) res = 'DOSCIENTOS ';
  else if (c === 3) res = 'TRESCIENTOS ';
  else if (c === 4) res = 'CUATROCIENTOS ';
  else if (c === 5) res = 'QUINIENTOS ';
  else if (c === 6) res = 'SEISCIENTOS ';
  else if (c === 7) res = 'SETECIENTOS ';
  else if (c === 8) res = 'OCHOCIENTOS ';
  else if (c === 9) res = 'NOVECIENTOS ';

  // Decenas y unidades
  const unidades = ['', 'UN', 'DOS', 'TRES', 'CUATRO', 'CINCO', 'SEIS', 'SIETE', 'OCHO', 'NUEVE'];

  if (d === 1) {
    if (u === 0) res += 'DIEZ';
    else if (u === 1) res += 'ONCE';
    else if (u === 2) res += 'DOCE';
    else if (u === 3) res += 'TRECE';
    else if (u === 4) res += 'CATORCE';
    else if (u === 5) res += 'QUINCE';
    else {
      const especiales = ['', '', '', '', '', '', 'DIECISEIS', 'DIECISIETE', 'DIECIOCHO', 'DIECINUEVE'];
      res += especiales[u];
    }
  } else if (d === 2) {
    if (u === 0) res += 'VEINTE';
    else res += 'VEINTI' + unidades[u];
  } else {
    const decenas = ['', '', '', 'TREINTA', 'CUARENTA', 'CINCUENTA', 'SESENTA', 'SETENTA', 'OCHENTA', 'NOVENTA'];
    if (d >= 3) res += decenas[d];
    if (d >= 3 && u > 0) res += ' Y ';
    if ((d === 0 || d >= 3) && u > 0) res += unidades[u];
  }

  return res.trim();
}

export function numberToWordsEs(amount: number | null | undefined): string {
  if (amount == null || amount === 0) {
    return '( CERO PESOS 00/100 M.N. )';
  }

  const intPart = Math.floor(amount);
  const decPart = Math.round((amount - intPart) * 100);

  let result = '';

  // Millones
  const millones = Math.floor(intPart / 1000000);
  if (millones === 1) {
    result += 'UN MILLON ';
  } else if (millones > 1) {
    result += centenasEs(millones) + ' MILLONES ';
  }

  // Miles
  const miles = Math.floor((intPart % 1000000) / 1000);
  if (miles === 1) {
    result += 'MIL ';
  } else if (miles > 1) {
    result += centenasEs(miles) + ' MIL ';
  }

  // Centenas y Unidades
  const centenas = intPart % 1000;
  if (centenas > 0) {
    result += centenasEs(centenas) + ' ';
  }

  const pesoWord = intPart === 1 ? 'PESO' : 'PESOS';
  const decStr = decPart.toString().padStart(2, '0');

  return `( ${result.trim()} ${pesoWord} ${decStr}/100 M.N. )`;
}

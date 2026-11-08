import { type LatLng, minutesFor, roadKm } from '../common/domain/geo';

/**
 * Otimizador local, igual ao fallback do app (sem malha viária):
 * vizinho mais próximo + 2-opt sobre haversine × 1,3. Funções puras.
 */

export interface OptimizerStop {
  id: string;
  latitude: number | null;
  longitude: number | null;
  /** Fica no índice atual entre as abertas. */
  locked?: boolean;
  /** Índice 0-based fixo. Vale mais que locked. */
  fixedPosition?: number | null;
}

type Located = OptimizerStop & LatLng;

function located(stop: OptimizerStop): stop is Located {
  return stop.latitude !== null && stop.longitude !== null;
}

/** Km pela ordem dada (paradas sem coordenada são puladas). */
export function pathKm(stops: OptimizerStop[], start?: LatLng | null, end?: LatLng | null): number {
  let km = 0;
  let prev: LatLng | null = start ?? null;
  for (const stop of stops) {
    if (!located(stop)) continue;
    if (prev) km += roadKm(prev, stop);
    prev = stop;
  }
  if (end && prev) km += roadKm(prev, end);
  return km;
}

export function nearestNeighbour(stops: Located[], start?: LatLng | null): Located[] {
  const remaining = [...stops];
  const order: Located[] = [];
  let current: LatLng | null = start ?? null;
  if (!current && remaining.length) {
    current = remaining.shift()!;
    order.push(current as Located);
  }
  while (remaining.length) {
    let best = 0;
    let bestKm = Infinity;
    for (let i = 0; i < remaining.length; i++) {
      const km = roadKm(current!, remaining[i]);
      if (km < bestKm) {
        bestKm = km;
        best = i;
      }
    }
    current = remaining.splice(best, 1)[0];
    order.push(current as Located);
  }
  return order;
}

/** 2-opt em caminho aberto (com início e fim opcionais). */
export function twoOpt(order: Located[], start?: LatLng | null, end?: LatLng | null, maxPasses = 50): Located[] {
  const route = [...order];
  const n = route.length;
  // Vizinhos fora do trecho: início (antes do índice 0) e fim (depois de n-1).
  const before = (i: number): LatLng | null => (i === 0 ? (start ?? null) : route[i - 1]);
  const after = (k: number): LatLng | null => (k === n - 1 ? (end ?? null) : route[k + 1]);
  const d = (a: LatLng | null, b: LatLng | null) => (a && b ? roadKm(a, b) : 0);
  for (let pass = 0; pass < maxPasses; pass++) {
    let improved = false;
    for (let i = 0; i < n - 1; i++) {
      for (let k = i + 1; k < n; k++) {
        // Inverter route[i..k] troca as arestas (antes,i) e (k,depois).
        const prev = before(i);
        const next = after(k);
        const delta = d(prev, route[k]) + d(route[i], next) - d(prev, route[i]) - d(route[k], next);
        if (delta < -1e-9) {
          route.splice(i, k - i + 1, ...route.slice(i, k + 1).reverse());
          improved = true;
        }
      }
    }
    if (!improved) break;
  }
  return route;
}

/**
 * Junta a ordem otimizada com as travas (porta de `applyLocks`,
 * lib/services/route_locks.dart): posição fixa primeiro, depois travadas no
 * índice atual, depois o resto na ordem otimizada.
 */
export function applyLocks(optimized: OptimizerStop[], current: OptimizerStop[]): OptimizerStop[] {
  const n = current.length;
  if (n === 0) return [];
  const slots: (OptimizerStop | null)[] = new Array(n).fill(null);
  const placed = new Set<string>();

  const nearestFree = (wanted: number): number => {
    const start = Math.min(Math.max(wanted, 0), n - 1);
    for (let d = 0; d < n; d++) {
      if (start + d < n && !slots[start + d]) return start + d;
      if (start - d >= 0 && !slots[start - d]) return start - d;
    }
    return -1;
  };
  const place = (item: OptimizerStop, wanted: number) => {
    const slot = nearestFree(wanted);
    if (slot >= 0) {
      slots[slot] = item;
      placed.add(item.id);
    }
  };

  const fixed = current
    .map((item, index) => ({ item, index }))
    .filter(({ item }) => item.fixedPosition !== null && item.fixedPosition !== undefined)
    .sort((a, b) => a.item.fixedPosition! - b.item.fixedPosition! || a.index - b.index);
  for (const { item } of fixed) place(item, item.fixedPosition!);
  current.forEach((item, index) => {
    if (!placed.has(item.id) && item.locked && (item.fixedPosition === null || item.fixedPosition === undefined)) {
      place(item, index);
    }
  });

  const currentIds = new Set(current.map((s) => s.id));
  const rest = optimized.filter((s) => currentIds.has(s.id) && !placed.has(s.id));
  const restIds = new Set(rest.map((s) => s.id));
  rest.push(...current.filter((s) => !placed.has(s.id) && !restIds.has(s.id)));
  let cursor = 0;
  const seen = new Set<string>();
  for (const item of rest) {
    if (seen.has(item.id)) continue;
    seen.add(item.id);
    while (cursor < n && slots[cursor]) cursor++;
    if (cursor >= n) break;
    slots[cursor] = item;
  }
  return slots.filter((s): s is OptimizerStop => s !== null);
}

export interface OptimizationResult {
  order: string[];
  baselineKm: number;
  optimizedKm: number;
  baselineMinutes: number;
  optimizedMinutes: number;
  /** Paradas sem coordenada: ficam no fim, na ordem atual. */
  unlocated: string[];
}

const round = (km: number) => Math.round(km * 100) / 100;

/**
 * Propõe uma ordem. Nunca piora: se a proposta (com travas) sair mais longa
 * que a atual, devolve a atual.
 */
export function optimize(
  current: OptimizerStop[],
  options: { start?: LatLng | null; end?: LatLng | null; speedKmh: number },
): OptimizationResult {
  const withCoords = current.filter(located);
  const unlocated = current.filter((s) => !located(s));
  const nn = nearestNeighbour(withCoords, options.start);
  const improved = twoOpt(nn, options.start, options.end);
  let proposal = applyLocks([...improved, ...unlocated], current);
  const baselineKm = pathKm(current, options.start, options.end);
  let optimizedKm = pathKm(proposal, options.start, options.end);
  if (optimizedKm > baselineKm) {
    proposal = current;
    optimizedKm = baselineKm;
  }
  return {
    order: proposal.map((s) => s.id),
    baselineKm: round(baselineKm),
    optimizedKm: round(optimizedKm),
    baselineMinutes: minutesFor(baselineKm, options.speedKmh),
    optimizedMinutes: minutesFor(optimizedKm, options.speedKmh),
    unlocated: unlocated.map((s) => s.id),
  };
}

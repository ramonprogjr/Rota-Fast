/** Distância em linha reta (km) entre dois pontos. */
export function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const r = 6371;
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** Fator de desvio da malha viária sobre a linha reta (mesmo do app sem ORS). */
export const ROAD_FACTOR = 1.3;

/** Velocidade média padrão (moto, AppConstants do app). */
export const DEFAULT_SPEED_KMH = 28;

export interface LatLng {
  latitude: number;
  longitude: number;
}

export function roadKm(a: LatLng, b: LatLng): number {
  return haversineKm(a.latitude, a.longitude, b.latitude, b.longitude) * ROAD_FACTOR;
}

export function minutesFor(km: number, speedKmh: number): number {
  return Math.round((km / speedKmh) * 60);
}

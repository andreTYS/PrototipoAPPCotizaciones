const MESES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];

export const pad = (n: number) => String(n).padStart(2, "0");

export const isoDate = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
/** El día de la caja es el de Perú (igual que en el servidor), aunque el teléfono tenga otra zona horaria. */
export const today = () => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" }).format(new Date());
export const daysAgo = (k: number) => {
  const [y, m, d] = today().split("-").map(Number);
  return isoDate(new Date(y, m - 1, d - k));
};

/** "YYYY-MM-DD" -> local Date (avoids the UTC shift of `new Date(iso)`). */
export const parseIso = (s: string) => {
  const [y, m, d] = s.split("-").map(Number);
  return new Date(y, (m || 1) - 1, d || 1);
};

/** Formats "S/ 48,250.00" (es-PE style). Implemented by hand: Hermes' Intl support varies by build. */
export const money = (n: number) => {
  const neg = n < 0;
  const [int, dec] = Math.abs(n).toFixed(2).split(".");
  return `${neg ? "-" : ""}S/ ${int.replace(/\B(?=(\d{3})+(?!\d))/g, ",")}.${dec}`;
};

/** "2026-09-28" -> "28 sep 2026" */
export const fdate = (s: string) => {
  if (!s) return "";
  const [y, m, d] = s.split("-");
  return `${+d} ${MESES[+m - 1]} ${y}`;
};

/** "2026-09-28" -> "28/09/2026" (what the date field displays). */
export const inputDate = (s: string) => {
  if (!s) return "";
  const [y, m, d] = s.split("-");
  return `${d}/${m}/${y}`;
};

export const num = (v: string | number) => parseFloat(String(v).replace(/,/g, "")) || 0;

/** Keeps digits and a single dot with at most two decimals. */
export const cleanAmt = (v: string) => {
  v = v.replace(/[^\d.]/g, "");
  const i = v.indexOf(".");
  if (i > -1) v = v.slice(0, i + 1) + v.slice(i + 1).replace(/\./g, "").slice(0, 2);
  return v;
};

export const clock = (d: Date) => `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;

const DIAS = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"];
/** "2026-10-22" -> "jue 22 oct 2026" */
export const fdateLarga = (s: string) => {
  if (!s) return "";
  const d = parseIso(s);
  return `${DIAS[d.getDay()]} ${fdate(s)}`;
};
/** Suma (o resta) días a una fecha ISO. */
export const sumarDias = (s: string, n: number) => {
  const d = parseIso(s);
  d.setDate(d.getDate() + n);
  return isoDate(d);
};

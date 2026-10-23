/**
 * Turns the raw OCR text of a Peruvian receipt (boleta, factura, ticket, voucher,
 * Yape/Plin or bank transfer screenshot) into egreso form fields.
 * Pure functions: no React Native imports, so it can be tested with plain Node.
 */
import type { Categoria, Egreso, Subcategoria } from "./data";
import { isoDate, pad } from "./format";

const strip = (s: string) => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
/** Lowercase, accent-free words separated by single spaces, padded so ` word ` lookups also match at the edges. */
const words = (s: string) => ` ${strip(s).replace(/[^a-z]+/g, " ").trim()} `;

// ---- Monto ------------------------------------------------------------------

const AMOUNT = /(?:s\/\.?|s\/|pen)?\s*(\d{1,3}(?:[.,\s]\d{3})+(?:[.,]\d{1,2})?|\d+[.,]\d{1,2}|\d+)(?!\d)/gi;

/** "1,240.00" / "1.240,00" / "215,50" / "S/ 680" -> number */
export function parseAmount(raw: string): number {
  let s = raw.replace(/[^\d.,]/g, "");
  const lastSep = Math.max(s.lastIndexOf("."), s.lastIndexOf(","));
  if (lastSep > -1 && s.length - lastSep - 1 <= 2) {
    s = s.slice(0, lastSep).replace(/[.,]/g, "") + "." + s.slice(lastSep + 1);
  } else {
    s = s.replace(/[.,]/g, "");
  }
  return parseFloat(s) || 0;
}

function amountsIn(line: string): { value: number; hasCurrency: boolean; hasDecimals: boolean }[] {
  const out: { value: number; hasCurrency: boolean; hasDecimals: boolean }[] = [];
  for (const m of line.matchAll(AMOUNT)) {
    const value = parseAmount(m[1]);
    if (value > 0 && value < 10_000_000) out.push({ value, hasCurrency: /s\/|pen/i.test(m[0]), hasDecimals: /[.,]\d{1,2}$/.test(m[1]) });
  }
  return out;
}

const TOTAL_LABEL = /(importe\s+total|total\s+a\s+pagar|total\s+pagado|monto\s+total|\btotal\b|yapeaste|plineaste|pagaste|monto\s+enviado|importe\s+enviado|\bmonto\b|\bimporte\b)/;
const NOT_TOTAL = /(sub\s*-?\s*total|op\.?\s*gravad|op\.?\s*exonerad|op\.?\s*inafect|\bigv\b|vuelto|descuento|redondeo|efectivo|recibido|cambio|\bisc\b|items?)/;

export function findMonto(lines: string[]): number {
  // 1. A "total"-like label with an amount on the same line or the next one; the last one wins
  //    (receipts list subtotals first and the final total at the bottom).
  let best = 0;
  lines.forEach((line, i) => {
    const l = strip(line);
    if (!TOTAL_LABEL.test(l) || NOT_TOTAL.test(l)) return;
    const here = amountsIn(line).filter((a) => a.hasDecimals || a.hasCurrency);
    const next = i + 1 < lines.length ? amountsIn(lines[i + 1]).filter((a) => a.hasDecimals || a.hasCurrency) : [];
    const pick = here.length ? here[here.length - 1] : next[0];
    if (pick) best = pick.value;
  });
  if (best) return best;

  // 2. Largest amount written with "S/".
  const withCurrency = lines.flatMap((l) => amountsIn(l).filter((a) => a.hasCurrency)).map((a) => a.value);
  if (withCurrency.length) return Math.max(...withCurrency);

  // 3. Largest amount with decimals, ignoring lines that look like IDs, phones or dates.
  const decimals = lines
    .filter((l) => !/(ruc|dni|tel|cel|n[°º]|nro|serie|operaci|\d{2}[/-]\d{2}[/-]\d{2,4})/i.test(l))
    .flatMap((l) => amountsIn(l).filter((a) => a.hasDecimals))
    .map((a) => a.value);
  return decimals.length ? Math.max(...decimals) : 0;
}

// ---- Fecha ------------------------------------------------------------------

const MONTHS: Record<string, number> = {
  ene: 1, enero: 1, feb: 2, febrero: 2, mar: 3, marzo: 3, abr: 4, abril: 4, may: 5, mayo: 5, jun: 6, junio: 6,
  jul: 7, julio: 7, ago: 8, agosto: 8, set: 9, sep: 9, sept: 9, setiembre: 9, septiembre: 9, oct: 10, octubre: 10,
  nov: 11, noviembre: 11, dic: 12, diciembre: 12,
};

function validDate(y: number, m: number, d: number, now: Date): string | null {
  if (y < 100) y += 2000;
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 2000) return null;
  const dt = new Date(y, m - 1, d);
  if (dt.getMonth() !== m - 1) return null; // e.g. 31/02
  const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
  if (dt > tomorrow) return null; // receipts are never from the future; likely a misread
  return `${y}-${pad(m)}-${pad(d)}`;
}

export function findFecha(lines: string[], now = new Date()): string {
  const candidates: { iso: string; labeled: boolean }[] = [];
  for (const line of lines) {
    const l = strip(line);
    const labeled = /fecha|emisi/.test(l);
    for (const m of l.matchAll(/\b(\d{4})[/.-](\d{1,2})[/.-](\d{1,2})\b/g)) {
      const iso = validDate(+m[1], +m[2], +m[3], now);
      if (iso) candidates.push({ iso, labeled });
    }
    for (const m of l.matchAll(/\b(\d{1,2})[/.-](\d{1,2})[/.-](\d{4}|\d{2})\b/g)) {
      const iso = validDate(+m[3], +m[2], +m[1], now);
      if (iso) candidates.push({ iso, labeled });
    }
    for (const m of l.matchAll(/\b(\d{1,2})\s*(?:de\s+)?([a-z]{3,10})\.?\s*(?:de[l]?\s+)?(\d{4})\b/g)) {
      const month = MONTHS[m[2]];
      const iso = month ? validDate(+m[3], month, +m[1], now) : null;
      if (iso) candidates.push({ iso, labeled });
    }
  }
  return (candidates.find((c) => c.labeled) ?? candidates[0])?.iso ?? isoDate(now);
}

// ---- Persona ----------------------------------------------------------------

const COMPANY = /(\bs\.?\s?a\.?\s?c\b|\be\.?\s?i\.?\s?r\.?\s?l\b|\bs\.?\s?r\.?\s?l\b|\bs\.?\s?a\.?\s?a\b|\bs\.a\.|\bsociedad|corporaci[oó]n|empresa|inversiones|comercial|ferreter[ií]a|distribuidora|grifo|servicentro|transportes|restaurant)/i;
const HEADER_NOISE = /(boleta|factura|electr[oó]nica|ticket|comprobante|venta|ruc|r\.u\.c|direcci|av\.|jr\.|calle|telf|tel[eé]fono|cel|www|http|@|fecha|hora|cliente|se[nñ]or|dni|serie|n[°º]|nro|total|igv|cajero|caja|representaci|impresa|sunat|autorizad|yape|plin|operaci|constancia|transferencia|^\W*$)/i;

export function findPersona(lines: string[]): string {
  // Yape / Plin / transfers: the recipient follows a label.
  for (let i = 0; i < lines.length; i++) {
    const l = strip(lines[i]);
    const m = lines[i].match(/(?:yapeaste\s+a|plineaste\s+a|enviado\s+a|destinatario|beneficiario|para|a nombre de|pagaste\s+a)\s*:?\s*(.*)$/i);
    if (m && /(yape|plin|envi|destin|benefic|para|nombre|pagaste)/.test(l)) {
      const same = cleanName(m[1]);
      if (same.length >= 3) return same;
      const next = lines[i + 1] ? cleanName(lines[i + 1]) : "";
      if (next.length >= 3 && /[a-z]{3}/i.test(next)) return next;
    }
  }
  // Explicit label.
  for (const line of lines) {
    const m = line.match(/(?:raz[oó]n\s+social|proveedor|emisor)\s*:?\s*(.+)$/i);
    if (m && cleanName(m[1]).length >= 3) return cleanName(m[1]);
  }
  // Header of a boleta/factura: the issuer's name sits at the top, usually before the RUC.
  const top = lines.slice(0, 8);
  const company = top.find((l) => COMPANY.test(l) && !/\b(ruc|r\.u\.c)\b/i.test(l));
  if (company) return cleanName(company);
  const firstName = top.find((l) => !HEADER_NOISE.test(l) && (l.match(/[a-záéíóúñ]/gi) ?? []).length >= 4 && !/\d{5,}/.test(l));
  return firstName ? cleanName(firstName) : "";
}

function cleanName(s: string) {
  return s.replace(/\s{2,}/g, " ").replace(/^[^\wÁÉÍÓÚÑáéíóúñ]+|[^\wÁÉÍÓÚÑáéíóúñ.)]+$/g, "").trim().slice(0, 60);
}

// ---- Ciudad -----------------------------------------------------------------

// The company works in Moquegua and Arequipa, so those win when a receipt mentions several cities.
const CITIES = [
  "Moquegua", "Arequipa", "Lima", "Trujillo", "Cusco", "Piura", "Chiclayo", "Huancayo", "Iquitos", "Tacna", "Ica", "Puno", "Juliaca",
  "Cajamarca", "Chimbote", "Huánuco", "Ayacucho", "Pucallpa", "Tarapoto", "Tumbes", "Ilo", "Huaraz", "Sullana",
  "Callao", "Chincha", "Pisco", "Abancay", "Puerto Maldonado", "Moyobamba", "Jaén", "Talara", "Huacho", "Barranca",
  "Huancavelica", "Cerro de Pasco", "Chachapoyas", "Nazca", "Paita", "Lambayeque", "Cañete", "Huaral",
];
// Lima districts that often appear in addresses instead of the city name.
const LIMA_DISTRICTS = [
  "Miraflores", "San Isidro", "Surco", "Santiago de Surco", "San Borja", "La Molina", "Ate", "Los Olivos", "San Juan de Lurigancho",
  "San Juan de Miraflores", "Villa El Salvador", "Villa Maria del Triunfo", "Comas", "Independencia", "San Martin de Porres",
  "Chorrillos", "Barranco", "Lince", "Jesus Maria", "Magdalena", "Pueblo Libre", "Brena", "La Victoria", "Cercado de Lima",
  "Rimac", "El Agustino", "Santa Anita", "Lurin", "Pachacamac", "Carabayllo", "Puente Piedra", "Chaclacayo", "Cieneguilla",
  "Surquillo", "San Luis", "San Miguel", "Punta Hermosa", "Ancon",
];

export function findCiudad(text: string): string {
  const t = words(text);
  for (const c of CITIES) if (t.includes(` ${strip(c)} `)) return c === "Callao" ? "Callao" : c;
  for (const d of LIMA_DISTRICTS) if (t.includes(` ${strip(d)} `)) return "Lima";
  return "";
}

// ---- Categoría y descripción ------------------------------------------------

type Keyworded = Exclude<Categoria, "Caja chica" | "Proveedores" | "Gastos fijos">;

const KEYWORDS: Record<Keyworded, string[]> = {
  Movilidad: ["combustible", "gasolina", "gasohol", "diesel", "petroleo", "grifo", "servicentro", "glp", "gnv", "taxi", "uber", "cabify", "didi", "indriver", "peaje", "pasaje", "estacionamiento", "primax", "repsol", "petroperu", "pecsa"],
  Material: ["cemento", "fierro", "acero", "ladrillo", "arena", "piedra", "agregado", "madera", "triplay", "pintura", "tubo", "pvc", "cable", "clavo", "alambre", "yeso", "mayolica", "ceramico", "ferreteria", "sodimac", "promart", "maestro", "calamina", "varilla", "concreto", "sika", "bolsa"],
  Equipos: ["alquiler", "mezcladora", "andamio", "compactadora", "vibradora", "taladro", "amoladora", "herramienta", "maquinaria", "equipo", "retroexcavadora", "generador", "martillo", "carretilla"],
  Fletes: ["flete", "carga", "traslado", "mudanza", "transportes", "transporte", "remision", "courier", "olva", "shalom", "encomienda"],
  Viáticos: ["restaurant", "restaurante", "menu", "almuerzo", "cena", "desayuno", "hotel", "hostal", "hospedaje", "polleria", "chifa", "cevicheria", "cafe", "alimentacion", "comida", "bebida", "gaseosa"],
  Oficina: ["papel", "utiles", "toner", "impresion", "fotocopia", "copias", "libreria", "tinta", "oficina", "archivador"],
};

/** Recurring costs: each subcategory has its own keywords. Proveedores and Caja chica are chosen by hand. */
const FIXED_KEYWORDS: Record<Subcategoria, string[]> = {
  Sueldos: ["planilla", "sueldo", "sueldos", "remuneracion", "jornal", "honorarios", "adelanto", "gratificacion", "cts", "pago de personal"],
  Alquiler: ["alquiler de local", "alquiler de oficina", "alquiler de terreno", "alquiler de almacen", "alquiler de deposito", "alquiler de departamento", "alquiler de casa", "alquiler mensual", "arrendamiento", "renta mensual"],
  Servicios: ["luz", "agua", "electricidad", "internet", "telefono", "telefonia", "sedapal", "seal", "enel", "luz del sur", "claro", "movistar", "entel", "bitel", "gas natural", "cable", "arbitrios", "servicio de agua", "servicio de luz"],
};

const hits = (t: string, words: string[]) => words.reduce((n, w) => n + (t.includes(` ${w} `) || t.includes(` ${w}s `) ? 1 : 0), 0);

export function findCategoria(text: string): Categoria | "" {
  const t = words(text);
  // Fixed costs are checked first so they win ties (e.g. "alquiler de local" also matches Equipos' "alquiler").
  const fixed = Object.values(FIXED_KEYWORDS).reduce((n, w) => n + hits(t, w), 0);
  let best: Categoria | "" = fixed > 0 ? "Gastos fijos" : "";
  let bestScore = fixed;
  for (const [cat, w] of Object.entries(KEYWORDS)) {
    const score = hits(t, w);
    if (score > bestScore) {
      best = cat as Categoria;
      bestScore = score;
    }
  }
  return best;
}

export function findSubcategoria(text: string): Subcategoria | "" {
  const t = words(text);
  let best: Subcategoria | "" = "";
  let bestScore = 0;
  for (const [sub, w] of Object.entries(FIXED_KEYWORDS)) {
    const score = hits(t, w);
    if (score > bestScore) {
      best = sub as Subcategoria;
      bestScore = score;
    }
  }
  return best;
}

export function findDescripcion(lines: string[], categoria: Categoria | "", persona: string, isTransfer: boolean): string {
  const keys = categoria === "Gastos fijos" ? Object.values(FIXED_KEYWORDS).flat() : categoria in KEYWORDS ? KEYWORDS[categoria as Keyworded] : [];
  // First product-like line that mentions a keyword of the detected category (skipping the issuer's name).
  const item = lines.find((line) => {
    const l = words(line);
    return line !== persona && !HEADER_NOISE.test(line) && keys.some((w) => l.includes(` ${w} `) || l.includes(` ${w}s `));
  });
  if (item) {
    const clean = item
      .replace(/(?:s\/\.?\s*)?\d{1,3}(?:[.,\s]\d{3})*[.,]\d{2}\b/gi, "") // prices
      .replace(/^\s*\d+(?:[.,]\d+)?\s*(?:und|unid|nIU|und\.|x)?\s+/i, "") // leading quantity
      .replace(/\s{2,}/g, " ")
      .trim();
    if (clean.length >= 3) return sentenceCase(clean).slice(0, 60);
  }
  if (isTransfer && persona) return `Transferencia a ${persona}`.slice(0, 60);
  return "";
}

const sentenceCase = (s: string) => (s === s.toUpperCase() ? s.charAt(0) + s.slice(1).toLowerCase() : s);

// ---- Todo junto ---------------------------------------------------------------

export function parseComprobante(lines: string[], now = new Date()): Egreso {
  const clean = lines.map((l) => l.trim()).filter(Boolean);
  const text = clean.join("\n");
  const isTransfer = /(yape|plin|transferencia|constancia de|operaci[oó]n exitosa|enviaste)/i.test(text);
  const monto = findMonto(clean);
  const persona = findPersona(clean);
  const categoria = findCategoria(text);
  const subcategoria = categoria === "Gastos fijos" ? findSubcategoria(text) : "";
  return {
    fecha: findFecha(clean, now),
    persona,
    desc: findDescripcion(clean, categoria, persona, isTransfer),
    ciudad: findCiudad(text),
    categoria,
    subcategoria,
    monto: monto > 0 ? monto.toFixed(2) : "",
  };
}

// ---- Filas a partir del OCR ------------------------------------------------------

export type OcrLine = { text: string; frame: { left: number; top: number; right: number; bottom: number } };

/**
 * ML Kit groups text in blocks, so a receipt's columns ("TOTAL:" on the left, "S/ 215.50" on
 * the right) come back far apart. Rebuild the visual rows: lines whose vertical centers are
 * within half a line height of each other are joined left-to-right.
 */
export function rowsFromLines(lines: OcrLine[]): string[] {
  const items = lines
    .filter((l) => l.text.trim())
    .map((l) => ({ text: l.text.trim(), left: l.frame.left, mid: (l.frame.top + l.frame.bottom) / 2, h: Math.max(1, l.frame.bottom - l.frame.top) }))
    .sort((a, b) => a.mid - b.mid);
  const rows: (typeof items)[] = [];
  for (const it of items) {
    const row = rows[rows.length - 1];
    if (row && Math.abs(row[0].mid - it.mid) <= Math.min(row[0].h, it.h) / 2) row.push(it);
    else rows.push([it]);
  }
  return rows.map((r) => r.sort((a, b) => a.left - b.left).map((x) => x.text).join(" "));
}

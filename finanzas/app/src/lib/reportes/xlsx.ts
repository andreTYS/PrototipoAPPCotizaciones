/**
 * Excel (.xlsx) legible: una hoja de resumen y una hoja por libro, con encabezados de color, importes con
 * formato de miles, filtros y fila de títulos congelada. Los totales son fórmulas SUBTOTAL: si se filtra
 * (por ejemplo, una sola categoría), el total se recalcula con lo que queda visible.
 */
import type { Alignment, Borders, Fill, Font, Worksheet } from "exceljs";
import { COMPROBANTE_LABEL, TIPO_FILA_LABEL, CIUDAD_LABEL } from "../caja/types";
import { categoriaTexto, nombreCiudades, periodoTexto, resumenPorDia, totalesReporte, type Reporte } from "./model";

const TEAL = "FF0E7490";
const TINT = "FFD8F3F4";
const LINE = "FFD5E0E8";
const INK = "FF0D2233";
const RED = "FFB93A3A";
const MONEY = '#,##0.00;[Red]-#,##0.00;;@'; // cero = celda vacía, como en el papel; negativo en rojo
const MONEY_CERO = '#,##0.00;[Red]-#,##0.00';

const borde: Partial<Borders> = { top: { style: "thin", color: { argb: LINE } }, bottom: { style: "thin", color: { argb: LINE } }, left: { style: "thin", color: { argb: LINE } }, right: { style: "thin", color: { argb: LINE } } };
const relleno = (argb: string): Fill => ({ type: "pattern", pattern: "solid", fgColor: { argb } });
const FUENTE = "Calibri";

function titulo(ws: Worksheet, texto: string, sub: string, columnas: number) {
  ws.mergeCells(1, 1, 1, columnas);
  ws.getCell(1, 1).value = texto;
  ws.getCell(1, 1).font = { name: FUENTE, size: 16, bold: true, color: { argb: "FFFFFFFF" } } as Font;
  ws.getCell(1, 1).fill = relleno(TEAL);
  ws.getCell(1, 1).alignment = { vertical: "middle", indent: 1 } as Partial<Alignment>;
  ws.getRow(1).height = 30;
  ws.mergeCells(2, 1, 2, columnas);
  ws.getCell(2, 1).value = sub;
  ws.getCell(2, 1).font = { name: FUENTE, size: 10.5, color: { argb: INK } } as Font;
  ws.getCell(2, 1).alignment = { vertical: "middle", indent: 1 } as Partial<Alignment>;
  ws.getRow(2).height = 20;
}

function encabezado(ws: Worksheet, fila: number, nombres: string[]) {
  const row = ws.getRow(fila);
  nombres.forEach((n, i) => {
    const c = row.getCell(i + 1);
    c.value = n;
    c.font = { name: FUENTE, size: 10, bold: true, color: { argb: "FFFFFFFF" } } as Font;
    c.fill = relleno(INK);
    c.alignment = { vertical: "middle", horizontal: i >= 0 && /ingreso|salida|saldo|recibido|gastado|egreso|total|n°|mov/i.test(n) ? "center" : "left", wrapText: true } as Partial<Alignment>;
    c.border = borde;
  });
  row.height = 32;
}

const anchos = (ws: Worksheet, xs: number[]) => xs.forEach((w, i) => (ws.getColumn(i + 1).width = w));

function pie(ws: Worksheet) {
  ws.pageSetup = { orientation: "landscape", paperSize: 9, fitToPage: true, fitToWidth: 1, fitToHeight: 0, margins: { left: 0.4, right: 0.4, top: 0.5, bottom: 0.5, header: 0.2, footer: 0.2 } };
  ws.headerFooter = { oddFooter: "&LICR Finanzas&CPágina &P de &N&R&D" };
}

export async function generarXlsx(r: Reporte): Promise<Uint8Array> {
  const ExcelJS = (await import("exceljs")).default;
  const wb = new ExcelJS.Workbook();
  wb.creator = "ICR Finanzas";
  wb.created = new Date(r.generado);
  const sub = `${nombreCiudades(r.ciudades)} · ${periodoTexto(r.desde, r.hasta)} · generado por ${r.usuario || "—"} el ${new Date(r.generado).toLocaleString("es-PE")}`;
  const T = totalesReporte(r);

  // ---- Resumen ----------------------------------------------------------------------------------
  const rs = wb.addWorksheet("Resumen", { views: [{ showGridLines: false }] });
  titulo(rs, "ICR Finanzas · Reporte de caja", sub, 10);
  let fila = 4;
  if (r.diaria) {
    rs.getCell(fila, 1).value = "CAJA DIARIA · resumen por día";
    rs.getCell(fila, 1).font = { name: FUENTE, size: 11, bold: true, color: { argb: TEAL } } as Font;
    fila++;
    encabezado(rs, fila, ["Fecha", "Ciudad", "Saldo anterior", "Ingresos", "Salidas", "Saldo final", "Cta. cte. ingresos", "Cta. cte. salidas", "Cta. cte. saldo final", "N° mov."]);
    const ini = fila + 1;
    for (const d of resumenPorDia(r.hojas)) {
      fila++;
      const row = rs.getRow(fila);
      row.values = [new Date(d.fecha + "T12:00:00"), CIUDAD_LABEL[d.ciudad], d.saldoAnterior, d.ingresos, d.salidas, d.saldoFinal, d.ctaIngresos, d.ctaSalidas, d.ctaFinal, d.movimientos];
      row.eachCell((c, n) => {
        c.border = borde;
        c.font = { name: FUENTE, size: 10 } as Font;
        if (n === 1) c.numFmt = "ddd dd/mm/yyyy";
        if (n >= 3 && n <= 9) c.numFmt = MONEY_CERO;
      });
      row.getCell(6).font = { name: FUENTE, size: 10, bold: true } as Font;
    }
    fila++;
    const tot = rs.getRow(fila);
    const suma = (col: string, v: number) => ({ formula: `SUBTOTAL(109,${col}${ini}:${col}${fila - 1})`, result: v });
    tot.values = ["TOTAL DEL PERIODO", "", "", suma("D", T.ingresos), suma("E", T.salidas), "", suma("G", T.ctaIngresos), suma("H", T.ctaSalidas), "", suma("J", T.movimientos)];
    tot.eachCell({ includeEmpty: true }, (c, n) => {
      if (n > 10) return;
      c.fill = relleno(TINT);
      c.border = borde;
      c.font = { name: FUENTE, size: 10, bold: true } as Font;
      if (n >= 3 && n <= 9) c.numFmt = MONEY_CERO;
    });
    fila += 2;
  }
  if (r.chica) {
    rs.getCell(fila, 1).value = "CAJA CHICA · resumen del periodo";
    rs.getCell(fila, 1).font = { name: FUENTE, size: 11, bold: true, color: { argb: TEAL } } as Font;
    fila++;
    encabezado(rs, fila, ["Ciudad", "", "Saldo anterior", "Recibido de caja diaria", "Gastado", "Saldo final"]);
    for (const c of r.chicas) {
      fila++;
      const row = rs.getRow(fila);
      row.values = [CIUDAD_LABEL[c.ciudad], "", c.saldoAnterior, c.recibido, c.gastado, c.saldoFinal];
      row.eachCell((cell, n) => {
        if (n > 6) return;
        cell.border = borde;
        cell.font = { name: FUENTE, size: 10, bold: n === 6 } as Font;
        if (n >= 3) cell.numFmt = MONEY_CERO;
      });
    }
    fila += 2;
  }
  if (r.desdeLocal) {
    rs.getCell(fila, 1).value = "⚠ Sin conexión: este reporte se armó con los datos guardados en este dispositivo y puede faltar lo que registraron otras personas.";
    rs.getCell(fila, 1).font = { name: FUENTE, size: 10, bold: true, color: { argb: RED } } as Font;
  }
  anchos(rs, [20, 12, 15, 15, 15, 15, 17, 17, 18, 9]);
  pie(rs);

  // ---- Caja diaria ------------------------------------------------------------------------------
  if (r.diaria) {
    const ws = wb.addWorksheet("Caja diaria", { views: [{ state: "frozen", ySplit: 4, xSplit: 0 }] });
    titulo(ws, "Caja diaria · movimientos", sub, 16);
    const cab = ["Fecha", "Ciudad", "N°", "Tipo", "Descripción", "Responsable", "Comprobante", "Ingreso efectivo", "Ingreso Yape/Transf.", "Salida efectivo", "Salida Yape/Transf.", "Cta. cte. ingreso", "Cta. cte. salida", "Categoría", "Mov. interno", "Fotos"];
    encabezado(ws, 4, cab);
    let n = 4;
    for (const h of r.hojas)
      h.filas.forEach((f, i) => {
        n++;
        const row = ws.getRow(n);
        row.values = [new Date(h.fecha + "T12:00:00"), CIUDAD_LABEL[h.ciudad], i + 1, TIPO_FILA_LABEL[f.tipo], f.descripcion, f.responsable, f.comprobante === "NINGUNO" ? "" : COMPROBANTE_LABEL[f.comprobante], f.caja_ingreso_efectivo, f.caja_ingreso_transf, f.caja_salida_efectivo, f.caja_salida_transf, f.cta_cte_ingreso, f.cta_cte_salida, categoriaTexto(f.categoria, f.subcategoria), f.interno ? "Sí" : "", f.adjuntos.length || ""];
        row.eachCell({ includeEmpty: true }, (c, k) => {
          if (k > 16) return;
          c.border = borde;
          c.font = { name: FUENTE, size: 10 } as Font;
          c.alignment = { vertical: "top", wrapText: k === 5 || k === 14 } as Partial<Alignment>;
          if (k === 1) c.numFmt = "dd/mm/yyyy";
          if (k >= 8 && k <= 13) c.numFmt = MONEY;
          if (k === 3 || k === 15 || k === 16) c.alignment = { vertical: "top", horizontal: "center" };
        });
      });
    if (n >= 5) {
      const t = (k: number) => r.hojas.reduce((a, h) => a + h.filas.reduce((b, f) => b + [f.caja_ingreso_efectivo, f.caja_ingreso_transf, f.caja_salida_efectivo, f.caja_salida_transf, f.cta_cte_ingreso, f.cta_cte_salida][k], 0), 0);
      const tot = ws.getRow(n + 1);
      const col = (L: string, k: number) => ({ formula: `SUBTOTAL(109,${L}5:${L}${n})`, result: Math.round(t(k) * 100) / 100 });
      tot.values = ["TOTAL", "", "", "", "", "", "", col("H", 0), col("I", 1), col("J", 2), col("K", 3), col("L", 4), col("M", 5)];
      for (let k = 1; k <= 16; k++) {
        const c = tot.getCell(k);
        c.fill = relleno(TINT);
        c.border = borde;
        c.font = { name: FUENTE, size: 10, bold: true } as Font;
        if (k >= 8 && k <= 13) c.numFmt = MONEY_CERO;
      }
      ws.autoFilter = { from: { row: 4, column: 1 }, to: { row: n, column: 16 } };
    } else {
      ws.getCell(5, 1).value = "No hay movimientos en este periodo.";
    }
    anchos(ws, [12, 11, 5, 9, 38, 16, 17, 14, 15, 14, 15, 14, 14, 24, 9, 7]);
    pie(ws);
    ws.pageSetup.printTitlesRow = "4:4";

    // ---- Responsable de caja de cada día --------------------------------------------------------
    const ob = wb.addWorksheet("Responsable de caja", { views: [{ state: "frozen", ySplit: 4 }] });
    titulo(ob, "Caja diaria · responsable de caja", sub, 3);
    encabezado(ob, 4, ["Fecha", "Ciudad", "Responsable de caja"]);
    let m = 4;
    for (const h of r.hojas) {
      m++;
      const row = ob.getRow(m);
      row.values = [new Date(h.fecha + "T12:00:00"), CIUDAD_LABEL[h.ciudad], h.responsable_caja];
      row.eachCell({ includeEmpty: true }, (c, k) => {
        if (k > 3) return;
        c.border = borde;
        c.font = { name: FUENTE, size: 10 } as Font;
        c.alignment = { vertical: "top", wrapText: true } as Partial<Alignment>;
        if (k === 1) c.numFmt = "dd/mm/yyyy";
      });
    }
    anchos(ob, [12, 11, 30]);
    pie(ob);
  }

  // ---- Caja chica -------------------------------------------------------------------------------
  if (r.chica) {
    const ws = wb.addWorksheet("Caja chica", { views: [{ state: "frozen", ySplit: 4 }] });
    titulo(ws, "Caja chica · movimientos", sub, 10);
    encabezado(ws, 4, ["Fecha", "Ciudad", "Tipo", "Descripción", "Persona", "Categoría", "Ingreso", "Egreso", "Saldo", "Fotos"]);
    let n = 4;
    for (const c of r.chicas)
      for (const mv of c.movs) {
        n++;
        const row = ws.getRow(n);
        row.values = [new Date(mv.fecha + "T12:00:00"), CIUDAD_LABEL[mv.ciudad], mv.tipo === "TRANSFERENCIA" ? "Envío desde caja diaria" : "Egreso", mv.descripcion, mv.persona, categoriaTexto(mv.categoria, mv.subcategoria), mv.tipo === "TRANSFERENCIA" ? mv.monto : "", mv.tipo === "EGRESO" ? mv.monto : "", mv.saldo, mv.adjuntos.length || ""];
        row.eachCell({ includeEmpty: true }, (cell, k) => {
          if (k > 10) return;
          cell.border = borde;
          cell.font = { name: FUENTE, size: 10, bold: k === 9 } as Font;
          cell.alignment = { vertical: "top", wrapText: k === 4 } as Partial<Alignment>;
          if (k === 1) cell.numFmt = "dd/mm/yyyy";
          if (k >= 7 && k <= 9) cell.numFmt = MONEY_CERO;
          if (k === 10) cell.alignment = { vertical: "top", horizontal: "center" };
        });
      }
    if (n >= 5) {
      const ing = r.chicas.reduce((a, c) => a + c.recibido, 0);
      const egr = r.chicas.reduce((a, c) => a + c.gastado, 0);
      const tot = ws.getRow(n + 1);
      tot.values = ["TOTAL", "", "", "", "", "", { formula: `SUBTOTAL(109,G5:G${n})`, result: Math.round(ing * 100) / 100 }, { formula: `SUBTOTAL(109,H5:H${n})`, result: Math.round(egr * 100) / 100 }];
      for (let k = 1; k <= 10; k++) {
        const c = tot.getCell(k);
        c.fill = relleno(TINT);
        c.border = borde;
        c.font = { name: FUENTE, size: 10, bold: true } as Font;
        if (k >= 7 && k <= 9) c.numFmt = MONEY_CERO;
      }
      ws.autoFilter = { from: { row: 4, column: 1 }, to: { row: n, column: 10 } };
    } else {
      ws.getCell(5, 1).value = "No hay movimientos en este periodo.";
    }
    anchos(ws, [12, 11, 22, 40, 16, 24, 13, 13, 14, 7]);
    pie(ws);
    ws.pageSetup.printTitlesRow = "4:4";
  }

  const buf = await wb.xlsx.writeBuffer();
  return new Uint8Array(buf as ArrayBuffer);
}

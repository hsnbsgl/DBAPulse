import { useEffect, useState } from 'react';
import { IconButton, MenuItem, Select, Stack, Tooltip, Typography } from '@mui/material';
import RefreshIcon from '@mui/icons-material/Refresh';
import * as XLSX from 'xlsx';

export const ALL_RECORDS = -1;

const refreshHandlers = new Map<string, () => void>();

export function useListRefresh(filename: string, handler: () => void) {
  useEffect(() => {
    refreshHandlers.set(filename, handler);
    return () => {
      if (refreshHandlers.get(filename) === handler) refreshHandlers.delete(filename);
    };
  }, [filename, handler]);
}

type ExportFormat = '' | 'xlsx' | 'csv' | 'txt' | 'pdf';

const asRecords = (rows: unknown[]) => rows.map(row => row && typeof row === 'object' ? row as Record<string, unknown> : { value: row });

const download = (filename: string, content: BlobPart, type: string) => {
  const url = URL.createObjectURL(new Blob([content], { type }));
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
};

const pdfEscape = (value: string) => value.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)');

const pdfLines = (rows: unknown[]) => {
  const records = asRecords(rows);
  if (!records.length) return ['No records'];
  return records.flatMap((record, index) => {
    const text = `${index + 1}. ${Object.entries(record).map(([key, value]) => `${key}: ${String(value ?? '')}`).join(' | ')}`;
    const chunks: string[] = [];
    for (let offset = 0; offset < text.length; offset += 110) chunks.push(text.slice(offset, offset + 110));
    return chunks;
  });
};

const createPdf = (rows: unknown[]) => {
  const lines = pdfLines(rows);
  const pageSize = 48;
  const pages = Array.from({ length: Math.max(1, Math.ceil(lines.length / pageSize)) }, (_, index) => lines.slice(index * pageSize, (index + 1) * pageSize));
  const pageObjectIds = pages.map((_, index) => 4 + index * 2);
  const contentObjectIds = pages.map((_, index) => 5 + index * 2);
  const objects: string[] = [];
  objects[1] = '<< /Type /Catalog /Pages 2 0 R >>';
  objects[2] = `<< /Type /Pages /Kids [${pageObjectIds.map(id => `${id} 0 R`).join(' ')}] /Count ${pages.length} >>`;
  objects[3] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';
  pages.forEach((page, index) => {
    const content = ['BT', '/F1 8 Tf', '36 756 Td', ...page.flatMap((line, lineIndex) => [lineIndex ? '0 -14 Td' : '', `(${pdfEscape(line)}) Tj`]), 'ET'].filter(Boolean).join('\n');
    objects[pageObjectIds[index]] = `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents ${contentObjectIds[index]} 0 R >>`;
    objects[contentObjectIds[index]] = `<< /Length ${content.length} >>\nstream\n${content}\nendstream`;
  });
  let pdf = '%PDF-1.4\n';
  const offsets = [0];
  for (let id = 1; id < objects.length; id += 1) {
    offsets[id] = pdf.length;
    pdf += `${id} 0 obj\n${objects[id]}\nendobj\n`;
  }
  const xref = pdf.length;
  pdf += `xref\n0 ${objects.length}\n0000000000 65535 f \n${offsets.slice(1).map(offset => `${String(offset).padStart(10, '0')} 00000 n `).join('\n')}\ntrailer\n<< /Size ${objects.length} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return pdf;
};

export const exportRows = (filename: string, rows: unknown[], format: Exclude<ExportFormat, ''>) => {
  const records = asRecords(rows);
  if (format === 'xlsx' || format === 'csv') {
    const worksheet = XLSX.utils.json_to_sheet(records);
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, 'Data');
    XLSX.writeFile(workbook, `${filename}.${format}`, { bookType: format === 'xlsx' ? 'xlsx' : 'csv' });
    return;
  }
  if (format === 'txt') {
    download(`${filename}.txt`, records.map(record => Object.entries(record).map(([key, value]) => `${key}: ${String(value ?? '')}`).join('\t')).join('\n'), 'text/plain;charset=utf-8');
    return;
  }
  download(`${filename}.pdf`, createPdf(rows), 'application/pdf');
};

export default function ListToolbar({ filename, rows, pageSize, onPageSizeChange, onRefresh, showPageSize = true }: { filename: string; rows: unknown[]; pageSize?: number; onPageSizeChange?: (size: number) => void; onRefresh?: () => void; showPageSize?: boolean }) {
  const [format, setFormat] = useState<ExportFormat>('');
  const handleExport = (value: ExportFormat) => {
    setFormat('');
    if (value) exportRows(filename, rows, value);
  };
  return <Stack direction="row" spacing={1} alignItems="center" justifyContent="flex-end" flexWrap="wrap" useFlexGap sx={{ my: 1 }}>
    {showPageSize && pageSize != null && onPageSizeChange && <><Typography variant="caption" color="text.secondary">Kayıt</Typography><Select size="small" value={pageSize} onChange={event => onPageSizeChange(Number(event.target.value))}>{[10, 20, 30, 40, 50].map(size => <MenuItem key={size} value={size}>{size}</MenuItem>)}<MenuItem value={ALL_RECORDS}>All records</MenuItem></Select></>}
    <Select size="small" displayEmpty value={format} onChange={event => handleExport(event.target.value as ExportFormat)} renderValue={value => value ? String(value).toUpperCase() : 'Export'}><MenuItem value="" disabled>Export format</MenuItem><MenuItem value="xlsx">Excel</MenuItem><MenuItem value="csv">CSV</MenuItem><MenuItem value="txt">TXT</MenuItem><MenuItem value="pdf">PDF</MenuItem></Select>
    <Tooltip title="Refresh"><IconButton size="small" aria-label="Refresh" onClick={() => onRefresh?.() ?? refreshHandlers.get(filename)?.()}><RefreshIcon fontSize="small" /></IconButton></Tooltip>
  </Stack>;
}

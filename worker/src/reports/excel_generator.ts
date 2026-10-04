import type {
  EventRow,
  EventSource,
  GenerateReportRequestBody,
  ReportOptions,
  ReportPreset,
  ReportStats,
  ShiftSummaryItem,
} from '../types';

// ==========================================
// 1. Shift Pairing & Aggregation
// ==========================================

export function cleanMarkdownForExcel(text?: string | null): string {
  if (!text) return '';
  return text
    .split('\n')
    .map((line) =>
      line
        .trim()
        .replace(/^#+\s*/, '')
        .replace(/^-\s*/, '• ')
        .replace(/\*\*(.*?)\*\*/g, '$1')
        .replace(/\*(.*?)\*/g, '$1')
    )
    .filter((l) => l.length > 0)
    .join('; ');
}

function escapeXml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

export function pairEventsIntoReportShifts(events: EventRow[]): ShiftSummaryItem[] {
  const sorted = [...events].sort(
    (a, b) => new Date(a.occurred_at_utc).getTime() - new Date(b.occurred_at_utc).getTime()
  );

  const shifts: ShiftSummaryItem[] = [];
  let pendingClockIn: EventRow | null = null;

  for (const event of sorted) {
    if (event.event_type === 'clock_in') {
      pendingClockIn = event;
    } else if (event.event_type === 'clock_out' && pendingClockIn !== null) {
      const inDate = new Date(pendingClockIn.occurred_at_utc);
      const outDate = new Date(event.occurred_at_utc);
      const diffMs = Math.max(0, outDate.getTime() - inDate.getTime());
      const durationMinutes = Math.round(diffMs / (1000 * 60));
      const hours = Math.floor(durationMinutes / 60);
      const mins = durationMinutes % 60;
      const hoursDecimal = Math.round((durationMinutes / 60) * 100) / 100;

      const dateStr = inDate.toISOString().slice(0, 10);
      const startTimeLocal = inDate.toISOString().slice(11, 16);
      const endTimeLocal = outDate.toISOString().slice(11, 16);

      const note = cleanMarkdownForExcel(event.note ?? pendingClockIn.note);

      shifts.push({
        date: dateStr,
        clockInUtc: pendingClockIn.occurred_at_utc,
        clockOutUtc: event.occurred_at_utc,
        startTimeLocal,
        endTimeLocal,
        durationMinutes,
        durationHoursDecimal: hoursDecimal,
        durationFormatted: `${hours}h ${mins}m`,
        note: note.length > 0 ? note : undefined,
        source: event.source as EventSource,
      });

      pendingClockIn = null;
    }
  }

  return shifts;
}

export function computeReportStats(shifts: ShiftSummaryItem[]): ReportStats {
  if (shifts.length === 0) {
    return {
      totalHours: 0,
      totalShifts: 0,
      totalDays: 0,
      averageShiftMinutes: 0,
      averageShiftFormatted: '0h 0m',
      longestShiftMinutes: 0,
      longestShiftFormatted: '0h 0m',
    };
  }

  const uniqueDays = new Set(shifts.map((s) => s.date)).size;
  const totalMinutes = shifts.reduce((acc, s) => acc + s.durationMinutes, 0);
  const totalHours = Math.round((totalMinutes / 60) * 100) / 100;
  const avgMinutes = Math.round(totalMinutes / shifts.length);
  const longestMinutes = Math.max(...shifts.map((s) => s.durationMinutes));

  const avgH = Math.floor(avgMinutes / 60);
  const avgM = avgMinutes % 60;
  const longH = Math.floor(longestMinutes / 60);
  const longM = longestMinutes % 60;

  return {
    totalHours,
    totalShifts: shifts.length,
    totalDays: uniqueDays,
    averageShiftMinutes: avgMinutes,
    averageShiftFormatted: `${avgH}h ${avgM}m`,
    longestShiftMinutes: longestMinutes,
    longestShiftFormatted: `${longH}h ${longM}m`,
  };
}

// ==========================================
// 2. OpenXML Document Generators
// ==========================================

function buildContentTypesXml(): string {
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>`;
}

function buildRelsXml(): string {
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>`;
}

function buildWorkbookRelsXml(): string {
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>`;
}

function buildWorkbookXml(sheetName: string = 'Work Hours Log'): string {
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="${escapeXml(sheetName)}" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>`;
}

function buildStylesXml(): string {
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="4">
    <font><name val="Calibri"/><sz val="11"/></font>
    <font><b/><name val="Calibri"/><sz val="11"/><color rgb="FFFFFFFF"/></font>
    <font><b/><name val="Calibri"/><sz val="11"/><color rgb="FF0F172A"/></font>
    <font><i/><name val="Calibri"/><sz val="10"/><color rgb="FF64748B"/></font>
  </fonts>
  <fills count="4">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF0F766E"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFF1F5F9"/></patternFill></fill>
  </fills>
  <borders count="2">
    <border><left/><right/><top/><bottom/></border>
    <border>
      <left style="thin"><color rgb="FFCBD5E1"/></left>
      <right style="thin"><color rgb="FFCBD5E1"/></right>
      <top style="thin"><color rgb="FFCBD5E1"/></top>
      <bottom style="thin"><color rgb="FFCBD5E1"/></bottom>
    </border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="6">
    <!-- 0: Standard Body -->
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" applyBorder="1"/>
    <!-- 1: Header: bold white on teal fill, centered -->
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
    <!-- 2: Total row: bold dark on light slate fill -->
    <xf numFmtId="0" fontId="2" fillId="3" borderId="1" applyFont="1" applyFill="1" applyBorder="1"/>
    <!-- 3: Number 0.00 right-aligned -->
    <xf numFmtId="2" fontId="0" fillId="0" borderId="1" applyNumberFormat="1" applyBorder="1"><alignment horizontal="right"/></xf>
    <!-- 4: Center aligned text (Date, Time) -->
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center"/></xf>
    <!-- 5: Total number 0.00 bold right-aligned on light slate fill -->
    <xf numFmtId="2" fontId="2" fillId="3" borderId="1" applyFont="1" applyFill="1" applyNumberFormat="1" applyBorder="1"><alignment horizontal="right"/></xf>
  </cellXfs>
</styleSheet>`;
}

export function buildWorksheetXml(
  shifts: ShiftSummaryItem[],
  stats: ReportStats,
  preset: ReportPreset,
  options: ReportOptions = {}
): string {
  const isFull = preset === 'full';
  const includeNotes = isFull || options.includeNotes === true;
  const includeSource = isFull || options.includeSource === true;
  const includeStats = isFull || options.includeStats === true;

  // Build column headers
  const columns: { label: string; width: number }[] = [
    { label: 'Date', width: 14 },
    { label: 'Start Time', width: 12 },
    { label: 'End Time', width: 12 },
    { label: 'Duration (Hours)', width: 16 },
  ];

  if (isFull) {
    columns.push({ label: 'Duration', width: 12 });
  }
  if (includeSource) {
    columns.push({ label: 'Source', width: 16 });
  }
  if (includeNotes) {
    columns.push({ label: 'Shift Notes', width: 40 });
  }

  // Column letters: A, B, C, D, E, F, G...
  const colLetter = (idx: number) => String.fromCharCode(65 + idx);

  let xml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <cols>`;

  columns.forEach((col, idx) => {
    xml += `\n    <col min="${idx + 1}" max="${idx + 1}" width="${col.width}" customWidth="1"/>`;
  });

  xml += `\n  </cols>\n  <sheetData>`;

  // Row 1: Header
  xml += `\n    <row r="1" ht="26" customHeight="1">`;
  columns.forEach((col, idx) => {
    xml += `\n      <c r="${colLetter(idx)}1" s="1" t="inlineStr"><is><t>${escapeXml(col.label)}</t></is></c>`;
  });
  xml += `\n    </row>`;

  // Shift rows
  shifts.forEach((shift, sIdx) => {
    const rowNum = sIdx + 2;
    xml += `\n    <row r="${rowNum}" ht="20" customHeight="1">`;
    // Col A: Date
    xml += `\n      <c r="A${rowNum}" s="4" t="inlineStr"><is><t>${escapeXml(shift.date)}</t></is></c>`;
    // Col B: Start
    xml += `\n      <c r="B${rowNum}" s="4" t="inlineStr"><is><t>${escapeXml(shift.startTimeLocal)}</t></is></c>`;
    // Col C: End
    xml += `\n      <c r="C${rowNum}" s="4" t="inlineStr"><is><t>${escapeXml(shift.endTimeLocal)}</t></is></c>`;
    // Col D: Duration (Hours Decimal)
    xml += `\n      <c r="D${rowNum}" s="3"><v>${shift.durationHoursDecimal.toFixed(2)}</v></c>`;

    let curCol = 4;
    if (isFull) {
      xml += `\n      <c r="${colLetter(curCol)}${rowNum}" s="4" t="inlineStr"><is><t>${escapeXml(shift.durationFormatted)}</t></is></c>`;
      curCol++;
    }
    if (includeSource) {
      xml += `\n      <c r="${colLetter(curCol)}${rowNum}" s="4" t="inlineStr"><is><t>${escapeXml(shift.source)}</t></is></c>`;
      curCol++;
    }
    if (includeNotes) {
      xml += `\n      <c r="${colLetter(curCol)}${rowNum}" s="0" t="inlineStr"><is><t>${escapeXml(shift.note ?? '')}</t></is></c>`;
      curCol++;
    }

    xml += `\n    </row>`;
  });

  // Total Summary Row
  const totalRowNum = shifts.length + 2;
  xml += `\n    <row r="${totalRowNum}" ht="22" customHeight="1">`;
  xml += `\n      <c r="A${totalRowNum}" s="2" t="inlineStr"><is><t>TOTAL</t></is></c>`;
  xml += `\n      <c r="B${totalRowNum}" s="2" t="inlineStr"><is><t>${shifts.length} Shifts</t></is></c>`;
  xml += `\n      <c r="C${totalRowNum}" s="2" t="inlineStr"><is><t>${stats.totalDays} Days</t></is></c>`;
  xml += `\n      <c r="D${totalRowNum}" s="5"><v>${stats.totalHours.toFixed(2)}</v></c>`;

  for (let c = 4; c < columns.length; c++) {
    xml += `\n      <c r="${colLetter(c)}${totalRowNum}" s="2" t="inlineStr"><is><t></t></is></c>`;
  }
  xml += `\n    </row>`;

  // Summary Statistics Section (if enabled)
  if (includeStats) {
    const statsStartRow = totalRowNum + 3;
    xml += `\n    <row r="${statsStartRow}" ht="24" customHeight="1">`;
    xml += `\n      <c r="A${statsStartRow}" s="1" t="inlineStr"><is><t>SUMMARY STATISTIC</t></is></c>`;
    xml += `\n      <c r="B${statsStartRow}" s="1" t="inlineStr"><is><t>VALUE</t></is></c>`;
    xml += `\n    </row>`;

    const statRows = [
      { label: 'Total Hours Worked', val: `${stats.totalHours.toFixed(2)} hrs` },
      { label: 'Total Working Days', val: `${stats.totalDays} days` },
      { label: 'Total Completed Shifts', val: `${stats.totalShifts}` },
      { label: 'Average Shift Length', val: stats.averageShiftFormatted },
      { label: 'Longest Shift', val: stats.longestShiftFormatted },
    ];

    statRows.forEach((item, idx) => {
      const r = statsStartRow + 1 + idx;
      xml += `\n    <row r="${r}" ht="20" customHeight="1">`;
      xml += `\n      <c r="A${r}" s="0" t="inlineStr"><is><t>${escapeXml(item.label)}</t></is></c>`;
      xml += `\n      <c r="B${r}" s="4" t="inlineStr"><is><t>${escapeXml(item.val)}</t></is></c>`;
      xml += `\n    </row>`;
    });
  }

  xml += `\n  </sheetData>\n</worksheet>`;
  return xml;
}

// ==========================================
// 3. Pure JavaScript ZIP Builder (Store Method)
// ==========================================

const CRC_TABLE = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
  let c = n;
  for (let k = 0; k < 8; k++) {
    c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  }
  CRC_TABLE[n] = c >>> 0;
}

export function computeCrc32(data: Uint8Array): number {
  let crc = -1;
  for (let i = 0; i < data.length; i++) {
    crc = (crc >>> 8) ^ CRC_TABLE[(crc ^ data[i]) & 0xff];
  }
  return (crc ^ -1) >>> 0;
}

interface ZipEntry {
  path: string;
  data: Uint8Array;
}

export function createZipBuffer(entries: ZipEntry[]): Uint8Array {
  const encoder = new TextEncoder();
  const fileRecords: {
    pathBytes: Uint8Array;
    data: Uint8Array;
    crc: number;
    offset: number;
  }[] = [];

  let totalSize = 0;

  // Calculate local headers size
  for (const entry of entries) {
    const pathBytes = encoder.encode(entry.path);
    const crc = computeCrc32(entry.data);
    fileRecords.push({
      pathBytes,
      data: entry.data,
      crc,
      offset: totalSize,
    });
    // 30 bytes header + path length + data length
    totalSize += 30 + pathBytes.length + entry.data.length;
  }

  const centralDirStartOffset = totalSize;
  let centralDirSize = 0;

  // Calculate central directory size
  for (const record of fileRecords) {
    // 46 bytes header + path length
    centralDirSize += 46 + record.pathBytes.length;
  }

  // 22 bytes End of Central Directory
  totalSize += centralDirSize + 22;

  const buffer = new Uint8Array(totalSize);
  const view = new DataView(buffer.buffer);
  let pos = 0;

  // 1. Write Local File Headers & Data
  for (const record of fileRecords) {
    view.setUint32(pos, 0x04034b50, true); // Local header signature
    view.setUint16(pos + 4, 20, true); // Version needed to extract (2.0)
    view.setUint16(pos + 6, 0, true); // Flags
    view.setUint16(pos + 8, 0, true); // Compression: 0 = Store
    view.setUint16(pos + 10, 0, true); // Last mod time
    view.setUint16(pos + 12, 0, true); // Last mod date
    view.setUint32(pos + 14, record.crc, true); // CRC-32
    view.setUint32(pos + 18, record.data.length, true); // Compressed size
    view.setUint32(pos + 22, record.data.length, true); // Uncompressed size
    view.setUint16(pos + 26, record.pathBytes.length, true); // Filename length
    view.setUint16(pos + 28, 0, true); // Extra field length
    pos += 30;

    buffer.set(record.pathBytes, pos);
    pos += record.pathBytes.length;

    buffer.set(record.data, pos);
    pos += record.data.length;
  }

  // 2. Write Central Directory Headers
  for (const record of fileRecords) {
    view.setUint32(pos, 0x02014b50, true); // Central header signature
    view.setUint16(pos + 4, 20, true); // Version made by
    view.setUint16(pos + 6, 20, true); // Version needed to extract
    view.setUint16(pos + 8, 0, true); // Flags
    view.setUint16(pos + 10, 0, true); // Compression: 0 = Store
    view.setUint16(pos + 12, 0, true); // Last mod time
    view.setUint16(pos + 14, 0, true); // Last mod date
    view.setUint32(pos + 16, record.crc, true); // CRC-32
    view.setUint32(pos + 20, record.data.length, true); // Compressed size
    view.setUint32(pos + 24, record.data.length, true); // Uncompressed size
    view.setUint16(pos + 28, record.pathBytes.length, true); // Filename length
    view.setUint16(pos + 30, 0, true); // Extra field length
    view.setUint16(pos + 32, 0, true); // Comment length
    view.setUint16(pos + 34, 0, true); // Disk number start
    view.setUint16(pos + 36, 0, true); // Internal attributes
    view.setUint32(pos + 38, 0, true); // External attributes
    view.setUint32(pos + 42, record.offset, true); // Relative offset of local header
    pos += 46;

    buffer.set(record.pathBytes, pos);
    pos += record.pathBytes.length;
  }

  // 3. Write End of Central Directory Record (EOCD)
  view.setUint32(pos, 0x06054b50, true); // EOCD signature
  view.setUint16(pos + 4, 0, true); // Disk number
  view.setUint16(pos + 6, 0, true); // Disk with central directory
  view.setUint16(pos + 8, fileRecords.length, true); // Central entries on this disk
  view.setUint16(pos + 10, fileRecords.length, true); // Total central entries
  view.setUint32(pos + 12, centralDirSize, true); // Central directory size
  view.setUint32(pos + 16, centralDirStartOffset, true); // Central directory start offset
  view.setUint16(pos + 20, 0, true); // Comment length

  return buffer;
}

// ==========================================
// 4. Main Excel Generator Entry Point
// ==========================================

export function generateExcelWorkbook(
  events: EventRow[],
  request: GenerateReportRequestBody
): { buffer: Uint8Array; shifts: ShiftSummaryItem[]; stats: ReportStats } {
  const shifts = pairEventsIntoReportShifts(events);
  const stats = computeReportStats(shifts);

  const encoder = new TextEncoder();
  const entries: ZipEntry[] = [
    {
      path: '[Content_Types].xml',
      data: encoder.encode(buildContentTypesXml()),
    },
    {
      path: '_rels/.rels',
      data: encoder.encode(buildRelsXml()),
    },
    {
      path: 'xl/_rels/workbook.xml.rels',
      data: encoder.encode(buildWorkbookRelsXml()),
    },
    {
      path: 'xl/workbook.xml',
      data: encoder.encode(buildWorkbookXml('Work Hours')),
    },
    {
      path: 'xl/styles.xml',
      data: encoder.encode(buildStylesXml()),
    },
    {
      path: 'xl/worksheets/sheet1.xml',
      data: encoder.encode(buildWorksheetXml(shifts, stats, request.preset, request.options)),
    },
  ];

  const zip = createZipBuffer(entries);
  return { buffer: zip, shifts, stats };
}

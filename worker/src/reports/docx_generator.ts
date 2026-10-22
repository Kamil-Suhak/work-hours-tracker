import type { ContractProfile, EventRow, PlannedShiftItem } from '../types';
import { pairShifts, truncateToMinute } from '../status';
import { createZipBuffer, formatWarsawDate } from './excel_generator';

export interface DailyContractRow {
  date: string; // YYYY-MM-DD
  durationMinutes: number;
  durationCompact: string; // e.g. "8h0m"
}

function escapeXml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

export function formatCompactDuration(totalMinutes: number): string {
  const safeMinutes = Math.max(0, Math.floor(totalMinutes));
  const hours = Math.floor(safeMinutes / 60);
  const minutes = safeMinutes % 60;
  return `${hours}h${minutes}m`;
}

/**
 * Aggregates recorded D1 shifts and user-planned future shifts by Warsaw calendar date (YYYY-MM-DD)
 * for the specified target month (YYYY-MM).
 */
export function aggregateDailyContractHours(
  events: EventRow[],
  plannedShifts: PlannedShiftItem[] = [],
  monthString: string
): DailyContractRow[] {
  const sorted = [...events].sort(
    (a, b) => new Date(a.occurred_at_utc).getTime() - new Date(b.occurred_at_utc).getTime()
  );

  const minutesByDate = new Map<string, number>();

  for (const shift of pairShifts(sorted)) {
    const inDate = truncateToMinute(shift.clockIn.occurred_at_utc);
    const dateStr = formatWarsawDate(inDate);
    if (dateStr.slice(0, 7) !== monthString) continue;

    const durationMinutes = Math.floor(shift.durationSeconds / 60);
    if (durationMinutes > 0) {
      minutesByDate.set(dateStr, (minutesByDate.get(dateStr) ?? 0) + durationMinutes);
    }
  }

  for (const planned of plannedShifts) {
    const dateStr = planned.date.trim();
    if (dateStr.slice(0, 7) !== monthString) continue;
    const mins = Math.floor(planned.durationMinutes);
    if (mins > 0) {
      minutesByDate.set(dateStr, (minutesByDate.get(dateStr) ?? 0) + mins);
    }
  }

  return Array.from(minutesByDate.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([date, durationMinutes]) => ({
      date,
      durationMinutes,
      durationCompact: formatCompactDuration(durationMinutes),
    }));
}

/**
 * Unpacks a ZIP (.docx) buffer supporting Store (0) and Deflate-Raw (8) compression via Web Streams.
 */
export async function unzipBuffer(
  buf: Uint8Array
): Promise<{ path: string; data: Uint8Array }[]> {
  const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  const decoder = new TextDecoder();
  const entries: { path: string; data: Uint8Array }[] = [];

  // Locate End of Central Directory (EOCD) record from the end of the buffer
  let eocdPos = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) {
    if (view.getUint32(i, true) === 0x06054b50) {
      eocdPos = i;
      break;
    }
  }

  if (eocdPos === -1) {
    throw new Error('Invalid ZIP archive: End of Central Directory not found.');
  }

  const totalEntries = view.getUint16(eocdPos + 10, true);
  let cdPos = view.getUint32(eocdPos + 16, true);

  for (let i = 0; i < totalEntries; i++) {
    if (view.getUint32(cdPos, true) !== 0x02014b50) {
      throw new Error('Invalid ZIP Central Directory header signature.');
    }
    const compressionMethod = view.getUint16(cdPos + 10, true);
    const compressedSize = view.getUint32(cdPos + 20, true);
    const nameLen = view.getUint16(cdPos + 28, true);
    const extraLen = view.getUint16(cdPos + 30, true);
    const commentLen = view.getUint16(cdPos + 32, true);
    const localHeaderOffset = view.getUint32(cdPos + 42, true);

    const path = decoder.decode(buf.subarray(cdPos + 46, cdPos + 46 + nameLen));
    cdPos += 46 + nameLen + extraLen + commentLen;

    const localNameLen = view.getUint16(localHeaderOffset + 26, true);
    const localExtraLen = view.getUint16(localHeaderOffset + 28, true);
    const dataStart = localHeaderOffset + 30 + localNameLen + localExtraLen;
    const rawSlice = buf.subarray(dataStart, dataStart + compressedSize);

    let data: Uint8Array;
    if (compressionMethod === 0) {
      data = new Uint8Array(rawSlice);
    } else if (compressionMethod === 8) {
      const ds = new DecompressionStream('deflate-raw');
      const writer = ds.writable.getWriter();
      await writer.write(rawSlice);
      await writer.close();

      const reader = ds.readable.getReader();
      const chunks: Uint8Array[] = [];
      let totalLen = 0;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        chunks.push(value);
        totalLen += value.length;
      }
      data = new Uint8Array(totalLen);
      let offset = 0;
      for (const chunk of chunks) {
        data.set(chunk, offset);
        offset += chunk.length;
      }
    } else {
      throw new Error(`Unsupported ZIP compression method: ${compressionMethod}`);
    }

    entries.push({ path, data });
  }

  return entries;
}

/**
 * Reads width and height in pixels from a PNG buffer's IHDR header, falling back to 300x100.
 */
export function getPngDimensions(pngBytes: Uint8Array): { width: number; height: number } {
  if (
    pngBytes.length >= 24 &&
    pngBytes[0] === 0x89 &&
    pngBytes[1] === 0x50 &&
    pngBytes[2] === 0x4e &&
    pngBytes[3] === 0x47
  ) {
    const view = new DataView(pngBytes.buffer, pngBytes.byteOffset, pngBytes.byteLength);
    const width = view.getUint32(16, false);
    const height = view.getUint32(20, false);
    if (width > 0 && height > 0) {
      return { width, height };
    }
  }
  return { width: 300, height: 100 };
}

function fitEmuDimensions(
  widthPx: number,
  heightPx: number,
  maxWidthEmu: number,
  maxHeightEmu: number
): { cx: number; cy: number } {
  const ratio = widthPx / heightPx;
  let cx = maxWidthEmu;
  let cy = Math.round(cx / ratio);
  if (cy > maxHeightEmu) {
    cy = maxHeightEmu;
    cx = Math.round(cy * ratio);
  }
  return { cx, cy };
}

function buildInlineSignatureDrawingXml(
  relId: string,
  cx: number,
  cy: number,
  docPrId: number
): string {
  return `<w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="${cx}" cy="${cy}" /><wp:effectExtent l="0" t="0" r="0" b="0" /><wp:docPr id="${docPrId}" name="Signature ${docPrId}" descr="Signature" /><wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1" /></wp:cNvGraphicFramePr><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="${docPrId}" name="signature.png" /><pic:cNvPicPr><a:picLocks noChangeAspect="1" noChangeArrowheads="1" /></pic:cNvPicPr></pic:nvPicPr><pic:blipFill><a:blip r:embed="${relId}" /><a:stretch><a:fillRect /></a:stretch></pic:blipFill><pic:spPr bwMode="auto"><a:xfrm><a:off x="0" y="0" /><a:ext cx="${cx}" cy="${cy}" /></a:xfrm><a:prstGeom prst="rect"><a:avLst /></a:prstGeom><a:noFill /><a:ln><a:noFill /></a:ln></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing>`;
}

function extractParagraphText(pXml: string): string {
  return [...pXml.matchAll(/<w:t\b[^>]*>([\s\S]*?)<\/w:t>/g)].map((m) => m[1]).join('');
}

function replaceParagraphRuns(pXml: string, newRunsXml: string): string {
  const pOpenMatch = pXml.match(/^<w:p\b[^>]*>/);
  const pPrMatch = pXml.match(/<w:pPr>[\s\S]*?<\/w:pPr>/);
  const openTag = pOpenMatch ? pOpenMatch[0] : '<w:p>';
  const pPr = pPrMatch ? pPrMatch[0] : '';
  return `${openTag}${pPr}${newRunsXml}</w:p>`;
}

function replaceCellParagraphRuns(tcXml: string, newRunsXml: string, centerAlign = true): string {
  return tcXml.replace(/<w:p\b[^>]*>[\s\S]*?<\/w:p>/, (pXml) => {
    const pOpenMatch = pXml.match(/^<w:p\b[^>]*>/);
    let pPrMatch = pXml.match(/<w:pPr>[\s\S]*?<\/w:pPr>/)?.[0] ?? '<w:pPr><w:jc w:val="center" /></w:pPr>';
    if (centerAlign && pPrMatch.includes('<w:jc ')) {
      pPrMatch = pPrMatch.replace(/<w:jc\b[^>]*\/>/, '<w:jc w:val="center" />');
    }
    return `${pOpenMatch ? pOpenMatch[0] : '<w:p>'}${pPrMatch}${newRunsXml}</w:p>`;
  });
}

export async function generateContractDocx(params: {
  templateDocxBytes: Uint8Array;
  signaturePngBytes: Uint8Array;
  profile: ContractProfile;
  dailyRows: DailyContractRow[];
  issueDateWarsaw: string;
}): Promise<Uint8Array> {
  const { templateDocxBytes, signaturePngBytes, profile, dailyRows, issueDateWarsaw } = params;
  const entries = await unzipBuffer(templateDocxBytes);
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  const { width, height } = getPngDimensions(signaturePngBytes);
  // Table cell signature size (~2.3cm x 0.45cm max)
  const cellSigSize = fitEmuDimensions(width, height, 850_000, 180_000);
  // Rachunek footer signature size (~3.2cm x 0.8cm max)
  const footerSigSize = fitEmuDimensions(width, height, 1_150_000, 290_000);

  const sigRelId = 'rIdSignatureImg';
  const grossPln =
    profile.grossAmountPln ?? Math.round(profile.hourlyRatePln * profile.monthlyHours * 100) / 100;
  const issuePlace = profile.issuePlace?.trim() || 'Mielec';
  const monthlyHoursText = `${profile.monthlyHours}h 0m`;

  for (const entry of entries) {
    if (entry.path === '[Content_Types].xml') {
      let xml = decoder.decode(entry.data);
      if (!xml.includes('Extension="png"')) {
        xml = xml.replace(
          /<Types\b[^>]*>/,
          (match) => `${match}<Default Extension="png" ContentType="image/png" />`
        );
      }
      entry.data = encoder.encode(xml);
    } else if (entry.path === 'word/_rels/document.xml.rels') {
      let xml = decoder.decode(entry.data);
      if (!xml.includes(sigRelId)) {
        xml = xml.replace(
          '</Relationships>',
          `<Relationship Id="${sigRelId}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/signature.png" /></Relationships>`
        );
      }
      entry.data = encoder.encode(xml);
    } else if (entry.path === 'word/document.xml') {
      let docXml = decoder.decode(entry.data);

      // 1. Populate the 23-row attendance table (Załącznik)
      docXml = docXml.replace(/<w:tbl>[\s\S]*?<\/w:tbl>/, (tblXml) => {
        let rowIndex = -1;
        return tblXml.replace(/<w:tr\b[^>]*>[\s\S]*?<\/w:tr>/g, (trXml) => {
          rowIndex++;
          if (rowIndex === 0) {
            return trXml; // Keep header row unchanged
          }
          const dayRow = dailyRows[rowIndex - 1];
          let cellIndex = -1;
          return trXml.replace(/<w:tc>[\s\S]*?<\/w:tc>/g, (tcXml) => {
            cellIndex++;
            if (!dayRow) {
              return replaceCellParagraphRuns(tcXml, '');
            }
            if (cellIndex === 0) {
              return replaceCellParagraphRuns(
                tcXml,
                `<w:r><w:rPr><w:rFonts w:ascii="Trebuchet MS" w:hAnsi="Trebuchet MS" /><w:sz w:val="18" /><w:szCs w:val="18" /></w:rPr><w:t>${escapeXml(dayRow.date)}</w:t></w:r>`
              );
            }
            if (cellIndex === 1) {
              return replaceCellParagraphRuns(
                tcXml,
                `<w:r><w:rPr><w:rFonts w:ascii="Trebuchet MS" w:hAnsi="Trebuchet MS" /><w:sz w:val="18" /><w:szCs w:val="18" /></w:rPr><w:t>${escapeXml(dayRow.durationCompact)}</w:t></w:r>`
              );
            }
            if (cellIndex === 2) {
              return replaceCellParagraphRuns(
                tcXml,
                `<w:r>${buildInlineSignatureDrawingXml(sigRelId, cellSigSize.cx, cellSigSize.cy, 100 + rowIndex)}</w:r>`
              );
            }
            // Columns 3 (Uwagi) and 4 (Podpis zleceniodawcy) remain empty
            return replaceCellParagraphRuns(tcXml, '');
          });
        });
      });

      // 2. Populate paragraphs outside the table (Page 1 headers & Page 2 Rachunek)
      docXml = docXml.replace(/<w:p\b[^>]*>[\s\S]*?<\/w:p>/g, (pXml) => {
        const text = extractParagraphText(pXml).trim();

        // Page 1: "…………………………………………………………. r."
        if (text.startsWith('…') && text.endsWith('r.')) {
          return replaceParagraphRuns(
            pXml,
            `<w:r><w:rPr><w:rFonts w:ascii="Trebuchet MS" w:hAnsi="Trebuchet MS" /><w:b /><w:sz w:val="22" /><w:szCs w:val="22" /></w:rPr><w:t>${escapeXml(profile.contractDate)} r.</w:t></w:r>`
          );
        }

        // Page 1: "Nazwisko i imię Zleceniobiorcy: …"
        if (text.startsWith('Nazwisko i imię Zleceniobiorcy:')) {
          return replaceParagraphRuns(
            pXml,
            `<w:r><w:rPr><w:rFonts w:ascii="Trebuchet MS" w:hAnsi="Trebuchet MS" /><w:b /><w:sz w:val="24" /><w:szCs w:val="24" /></w:rPr><w:t xml:space="preserve">Nazwisko i imię Zleceniobiorcy: ${escapeXml(profile.contractorName)}</w:t></w:r>`
          );
        }

        // Page 2: "Wystawiony przez: …"
        if (text.startsWith('Wystawiony przez:')) {
          return replaceParagraphRuns(
            pXml,
            `<w:r><w:rPr><w:rFonts w:ascii="Trebuchet MS" w:hAnsi="Trebuchet MS" /><w:sz w:val="24" /><w:szCs w:val="24" /></w:rPr><w:t xml:space="preserve">Wystawiony przez: </w:t></w:r><w:r><w:rPr><w:rFonts w:ascii="Trebuchet MS" w:hAnsi="Trebuchet MS" /><w:b /><w:sz w:val="24" /><w:szCs w:val="24" /></w:rPr><w:t>${escapeXml(profile.contractorName)}</w:t></w:r>`
          );
        }

        // Page 2: "Za wykonanie prac wyszczególnionych w umowie zlecenia z dnia …"
        if (text.startsWith('Za wykonanie prac wyszczególnionych w umowie zlecenia z dnia')) {
          return replaceParagraphRuns(
            pXml,
            `<w:r><w:rPr><w:rFonts w:ascii="Trebuchet MS" w:hAnsi="Trebuchet MS" /><w:sz w:val="24" /><w:szCs w:val="24" /></w:rPr><w:t xml:space="preserve">Za wykonanie prac wyszczególnionych w umowie zlecenia z dnia </w:t></w:r><w:r><w:rPr><w:rFonts w:ascii="Trebuchet MS" w:hAnsi="Trebuchet MS" /><w:b /><w:sz w:val="24" /><w:szCs w:val="24" /></w:rPr><w:t>${escapeXml(profile.contractDate)} r.</w:t></w:r>`
          );
        }

        // Page 2: "Liczba godzin wykonywania zlecenia: …"
        if (text.startsWith('Liczba godzin wykonywania zlecenia:')) {
          return replaceParagraphRuns(
            pXml,
            `<w:r><w:rPr><w:szCs w:val="24" /></w:rPr><w:t xml:space="preserve">Liczba godzin wykonywania zlecenia: </w:t></w:r><w:r><w:rPr><w:b /><w:szCs w:val="24" /></w:rPr><w:t>${escapeXml(monthlyHoursText)}</w:t></w:r>`
          );
        }

        // Page 2: "Stawka godzinowa: …"
        if (text.startsWith('Stawka godzinowa')) {
          return replaceParagraphRuns(
            pXml,
            `<w:r><w:rPr><w:szCs w:val="24" /></w:rPr><w:t xml:space="preserve">Stawka godzinowa: </w:t></w:r><w:r><w:rPr><w:b /><w:szCs w:val="24" /></w:rPr><w:t>${escapeXml(String(profile.hourlyRatePln))} PLN</w:t></w:r>`
          );
        }

        // Page 2: "Wnioskuję o wypłatę wynagrodzenia w kwocie brutto:  … PLN"
        if (text.startsWith('Wnioskuję o wypłatę wynagrodzenia w kwocie brutto:')) {
          return replaceParagraphRuns(
            pXml,
            `<w:r><w:rPr><w:szCs w:val="24" /></w:rPr><w:t xml:space="preserve">Wnioskuję o wypłatę wynagrodzenia w kwocie brutto: </w:t></w:r><w:r><w:rPr><w:b /><w:szCs w:val="24" /></w:rPr><w:t>${escapeXml(String(grossPln))} PLN</w:t></w:r>`
          );
        }

        // Page 2: Dotted signature & issue place line containing tabs ("…………\t\t\t\t\t…………")
        if (text.startsWith('…………') && pXml.includes('<w:tab')) {
          const tabsXml = '<w:r><w:tab /></w:r>'.repeat(5);
          return replaceParagraphRuns(
            pXml,
            `<w:r><w:rPr><w:rFonts w:ascii="Trebuchet MS" w:hAnsi="Trebuchet MS" /><w:sz w:val="20" /><w:szCs w:val="20" /></w:rPr><w:t>${escapeXml(issuePlace)}, ${escapeXml(issueDateWarsaw)}</w:t></w:r>${tabsXml}<w:r>${buildInlineSignatureDrawingXml(sigRelId, footerSigSize.cx, footerSigSize.cy, 250)}</w:r>`
          );
        }

        return pXml;
      });

      entry.data = encoder.encode(docXml);
    }
  }

  entries.push({
    path: 'word/media/signature.png',
    data: signaturePngBytes,
  });

  return createZipBuffer(entries);
}

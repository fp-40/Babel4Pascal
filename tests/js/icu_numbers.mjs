// Writes test vectors for babel.numbers from ICU, through Node's
// Intl.NumberFormat, a second reference besides tests/numbers/reference.jsonl
// (localized signs and digits, plural of the number shown). Node's ICU has its own CLDR version (node -p process.versions),
// so some results differ because the data differ; tests/js/README.md
// explains how the comparison is read.
//
// Usage: node tests/js/icu_numbers.mjs OUT.jsonl
import { writeFileSync } from 'node:fs';

const LOCALES = ['en', 'en-IN', 'de', 'de-CH', 'fr', 'fr-CA', 'es', 'es-PE', 'es-MX', 'pt-BR', 'it',
  'nl', 'sv', 'fi', 'nb', 'da', 'pl', 'ru', 'uk', 'cs', 'tr', 'el', 'hu', 'ro', 'ar', 'ar-EG',
  'ar-SA', 'fa', 'he', 'ur', 'hi', 'bn', 'mr', 'ne', 'ta', 'th', 'my', 'ja', 'ko', 'zh',
  'zh-Hant', 'id', 'vi', 'sw', 'ca', 'lt', 'bg', 'sr', 'hr', 'zu'];
const NUMBERS = ['0', '1', '-1', '2', '5', '12', '0.5', '1.5', '-1.5', '1234', '-1234.5', '12345.678',
  '0.001', '1000000', '-9876543.21', '21', '22', '101', '1.25', '0.000123'];
const CURRENCIES = ['USD', 'EUR', 'JPY', 'PEN', 'INR'];

const out = [];
const tag = (l) => l.replace(/-/g, '_');
function add(op, args, f) {
  try {
    out.push({ op, args, expect: f() });
  } catch (e) {
    out.push({ op, args, error: e.name });
  }
}
const base = { roundingMode: 'halfEven' };
for (const loc of LOCALES) {
  for (const n of NUMBERS) {
    add('icu_decimal', [n, tag(loc)], () =>
      new Intl.NumberFormat(loc, { ...base, maximumFractionDigits: 3 }).format(n));
    add('icu_percent', [n, tag(loc)], () =>
      new Intl.NumberFormat(loc, { ...base, style: 'percent' }).format(n));
    for (const cur of CURRENCIES) {
      add('icu_currency', [n, cur, tag(loc), 'standard'], () =>
        new Intl.NumberFormat(loc, { ...base, style: 'currency', currency: cur }).format(n));
      add('icu_currency', [n, cur, tag(loc), 'accounting'], () =>
        new Intl.NumberFormat(loc, { ...base, style: 'currency', currency: cur, currencySign: 'accounting' }).format(n));
      add('icu_currency', [n, cur, tag(loc), 'name'], () =>
        new Intl.NumberFormat(loc, { ...base, style: 'currency', currency: cur, currencyDisplay: 'name' }).format(n));
    }
  }
  for (const n of ['999', '1000', '1234', '1500', '12345', '999999', '1000000', '1234567', '-1234567', '1000000000']) {
    for (const display of ['short', 'long']) {
      add('icu_compact', [n, tag(loc), display], () =>
        new Intl.NumberFormat(loc, { ...base, notation: 'compact', compactDisplay: display,
          maximumFractionDigits: 0 }).format(n));
    }
  }
}
writeFileSync(process.argv[2], out.map((o) => JSON.stringify(o)).join('\n') + '\n');
console.log(`${out.length} vectors written to ${process.argv[2]} (ICU ${process.versions.icu}, CLDR ${process.versions.cldr})`);

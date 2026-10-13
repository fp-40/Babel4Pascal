/* icu_lists_units - writes test vectors for babel.lists and babel.units
   from ICU4C (the reference implementation of CLDR), one JSON object per
   line, in the format of the other vector files (op, args, expect):

   - icu_list [items, style, locale]: ulistfmt (and, or, units; wide,
     short, narrow), with CLDR's style names ('standard-short', 'or',
     'unit-narrow');
   - icu_unit [value, unit, length, locale]: unumf with the skeleton
     'unit/<core unit id> unit-width-...' (long: full-name);
   - icu_unit_per [value, unit, per-unit, length, locale]: the same with
     'unit/<unit>-per-<per-unit>'.

   Values are decimal strings; numbers use the locale's default numbering
   system.

   Build and run (needs the ICU development headers):
     gcc -O2 tests/icu/icu_lists_units.c -o build/bin/icu_lists_units -licui18n -licuuc
     build/bin/icu_lists_units > build/vectors/icu_lists_units.jsonl */
#include <stdio.h>
#include <string.h>
#include <unicode/ulistformatter.h>
#include <unicode/unumberformatter.h>
#include <unicode/ustring.h>
#include <unicode/ulocdata.h>

static const char *LOCALES[] = {"en", "en_GB", "en_IN", "de", "fr", "fr_CA", "es", "es_MX", "pt",
  "pt_PT", "it", "nl", "sv", "pl", "ru", "uk", "cs", "tr", "el", "ar", "ar_EG", "fa", "he", "hi",
  "bn", "th", "ja", "ko", "zh", "zh_Hant", "id", "vi", "sw", "fi", "da", "ca", "cy", "ga", "lt",
  "sl", "ro", "my", "am", "zu", NULL};

/* lists: up to 5 items, NULL-terminated sets */
static const char *ITEMS[][6] = {
  {"A", "B", NULL}, {"A", "B", "C", NULL}, {"A", "B", "C", "D", NULL},
  {"A", "B", "C", "D", "E", NULL}, {"agua", "hielo", NULL}, {"siete", "ocho", NULL},
  {"uno", "otro", "hora", NULL}, {"Paris", "London", NULL},
  {"\xd7\x99\xd7\xa8\xd7\x95\xd7\xa9\xd7\x9c\xd7\x99\xd7\x9d", "Tel Aviv", NULL},
  {"\xd7\x9c\xd7\x95\xd7\x93", "\xd7\x99\xd7\xa8\xd7\x95\xd7\xa9\xd7\x9c\xd7\x99\xd7\x9d", NULL},
  {NULL}};
static const char *STYLES[] = {"standard", "standard-short", "standard-narrow", "or", "or-short",
  "or-narrow", "unit", "unit-short", "unit-narrow", NULL};
static const UListFormatterType TYPES[] = {ULISTFMT_TYPE_AND, ULISTFMT_TYPE_AND, ULISTFMT_TYPE_AND,
  ULISTFMT_TYPE_OR, ULISTFMT_TYPE_OR, ULISTFMT_TYPE_OR, ULISTFMT_TYPE_UNITS, ULISTFMT_TYPE_UNITS,
  ULISTFMT_TYPE_UNITS};
static const UListFormatterWidth WIDTHS[] = {ULISTFMT_WIDTH_WIDE, ULISTFMT_WIDTH_SHORT,
  ULISTFMT_WIDTH_NARROW, ULISTFMT_WIDTH_WIDE, ULISTFMT_WIDTH_SHORT, ULISTFMT_WIDTH_NARROW,
  ULISTFMT_WIDTH_WIDE, ULISTFMT_WIDTH_SHORT, ULISTFMT_WIDTH_NARROW};

static const char *UNITS[] = {"length-meter", "length-kilometer", "length-mile", "length-foot",
  "length-inch", "length-centimeter", "duration-hour", "duration-minute", "duration-second",
  "duration-day", "duration-week", "duration-month", "duration-year", "duration-millisecond",
  "mass-gram", "mass-kilogram", "mass-pound", "mass-tonne", "volume-liter", "volume-milliliter",
  "volume-gallon", "volume-cup", "temperature-celsius", "temperature-fahrenheit",
  "temperature-kelvin", "digital-byte", "digital-kilobyte", "digital-megabyte",
  "digital-gigabyte", "digital-terabyte", "digital-bit", "concentr-percent", "concentr-permille",
  "area-square-meter", "area-square-kilometer", "area-hectare", "area-acre", "volume-cubic-meter",
  "speed-kilometer-per-hour", "speed-meter-per-second", "speed-mile-per-hour",
  "consumption-liter-per-100-kilometer", "consumption-mile-per-gallon", "energy-kilowatt-hour",
  "power-watt", "electric-volt", "frequency-hertz", "angle-degree", "angle-radian",
  "acceleration-g-force", "energy-calorie", "energy-kilocalorie", "graphics-pixel", "graphics-em",
  NULL};
static const char *VALUES[] = {"0", "1", "2", "3", "5", "11", "21", "100", "1234", "1.5", "0.5",
  "2.25", "-1", "-2.5", "1.0", "12345.678", NULL};
static const char *PER[][2] = {{"length-kilometer", "duration-hour"}, {"length-meter",
  "duration-second"}, {"length-mile", "duration-hour"}, {"volume-liter", "length-kilometer"},
  {"mass-gram", "length-meter"}, {"mass-kilogram", "area-square-meter"}, {"digital-byte",
  "duration-second"}, {NULL, NULL}};
static const char *LENGTHS[] = {"long", "short", "narrow", NULL};
static const char *WIDTH_SKEL[] = {"unit-width-full-name", "unit-width-short", "unit-width-narrow"};

static void json_utf8(const char *s) {
  putchar('"');
  for (const char *p = s; *p; p++) {
    if (*p == '"' || *p == '\\') { putchar('\\'); putchar(*p); }
    else if ((unsigned char)*p < 0x20) printf("\\u%04x", *p);
    else putchar(*p);
  }
  putchar('"');
}

static void json_ustr(const UChar *s) {
  char buf[4096];
  UErrorCode e = U_ZERO_ERROR;
  u_strToUTF8(buf, sizeof buf, NULL, s, -1, &e);
  json_utf8(buf);
}

static void unit_case(const char *op, const char *value, const char *unit, const char *per,
                      int w, const char *loc) {
  char skel[256];
  UChar uskel[256], out[1024];
  UErrorCode e = U_ZERO_ERROR;
  /* CLDR's core unit ids ('unit/liter', 'unit/meter-per-second'): ICU
     78 fails on 'measure-unit/volume-liter' (U_INTERNAL_PROGRAM_ERROR) */
  if (per)
    snprintf(skel, sizeof skel, "unit/%s-per-%s %s", strchr(unit, '-') + 1, strchr(per, '-') + 1,
             WIDTH_SKEL[w]);
  else
    snprintf(skel, sizeof skel, "unit/%s %s", strchr(unit, '-') + 1, WIDTH_SKEL[w]);
  u_uastrcpy(uskel, skel);
  UNumberFormatter *f = unumf_openForSkeletonAndLocale(uskel, -1, loc, &e);
  UFormattedNumber *r = unumf_openResult(&e);
  unumf_formatDecimal(f, value, -1, r, &e);
  unumf_resultToString(r, out, 1024, &e);
  printf("{\"op\": \"%s\", \"args\": [", op);
  json_utf8(value);
  printf(", \"%s\", ", unit);
  if (per) printf("\"%s\", ", per);
  printf("\"%s\", \"%s\"]", LENGTHS[w], loc);
  if (U_FAILURE(e)) printf(", \"error\": \"%s\"}\n", u_errorName(e));
  else { printf(", \"expect\": "); json_ustr(out); printf("}\n"); }
  unumf_closeResult(r);
  unumf_close(f);
}

int main(void) {
  for (const char **loc = LOCALES; *loc; loc++) {
    for (int s = 0; STYLES[s]; s++) {
      UErrorCode e = U_ZERO_ERROR;
      UListFormatter *lf = ulistfmt_openForType(*loc, TYPES[s], WIDTHS[s], &e);
      for (int k = 0; ITEMS[k][0]; k++) {
        UChar ubuf[6][128];
        const UChar *strs[6];
        int32_t lens[6];
        int n = 0;
        for (; ITEMS[k][n]; n++) {
          UErrorCode e2 = U_ZERO_ERROR;
          u_strFromUTF8(ubuf[n], 128, &lens[n], ITEMS[k][n], -1, &e2);
          strs[n] = ubuf[n];
        }
        UChar out[1024];
        UErrorCode e3 = e;
        ulistfmt_format(lf, strs, lens, n, out, 1024, &e3);
        printf("{\"op\": \"icu_list\", \"args\": [[");
        for (int i = 0; i < n; i++) { if (i) printf(", "); json_utf8(ITEMS[k][i]); }
        printf("], \"%s\", \"%s\"]", STYLES[s], *loc);
        if (U_FAILURE(e3)) printf(", \"error\": \"%s\"}\n", u_errorName(e3));
        else { printf(", \"expect\": "); json_ustr(out); printf("}\n"); }
      }
      ulistfmt_close(lf);
    }
    for (int w = 0; w < 3; w++) {
      for (const char **u = UNITS; *u; u++)
        for (const char **v = VALUES; *v; v++)
          unit_case("icu_unit", *v, *u, NULL, w, *loc);
      for (int p = 0; PER[p][0]; p++)
        for (const char **v = VALUES; *v; v++)
          unit_case("icu_unit_per", *v, PER[p][0], PER[p][1], w, *loc);
    }
  }
  UVersionInfo cldr; char vs[32]; UErrorCode e = U_ZERO_ERROR;
  ulocdata_getCLDRVersion(cldr, &e); u_versionToString(cldr, vs);
  fprintf(stderr, "ICU vectors written (CLDR %s)\n", vs);
  return 0;
}

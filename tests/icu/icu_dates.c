/* icu_dates - writes test vectors for babel.dates from ICU4C (the
   reference implementation of CLDR), one JSON object per line, in the
   format of the other vector files (op, args, expect).

   Build and run (needs the ICU development headers):
     gcc -O2 tests/icu/icu_dates.c -o build/bin/icu_dates -licui18n -licuuc
     build/bin/icu_dates > build/vectors/icu_dates.jsonl

   The system ICU has its own CLDR version (u_getVersion; the data
   version is printed to stderr); see tests/icu/README.md. */
#include <stdio.h>
#include <string.h>
#include <unicode/udat.h>
#include <unicode/udatpg.h>
#include <unicode/ureldatefmt.h>
#include <unicode/ucal.h>
#include <unicode/ustring.h>
#include <unicode/uclean.h>
#include <unicode/ulocdata.h>

static const char *LOCALES[] = {"en", "en_GB", "en_IN", "de", "fr", "fr_CA", "es", "es_PE", "es_MX",
  "pt_BR", "it", "nl", "sv", "pl", "ru", "uk", "cs", "tr", "el", "ar", "ar_EG", "fa", "he", "hi",
  "bn", "th", "ja", "ko", "zh", "zh_Hant", "id", "vi", "sw", "fi", "da", "ca", NULL};
static const char *ZONES[] = {"UTC", "Europe/Madrid", "America/New_York", "America/Lima",
  "Asia/Kolkata", "America/St_Johns", "Australia/Lord_Howe", "Asia/Kathmandu", "Europe/London",
  "Asia/Tokyo", "America/Los_Angeles", "America/Vancouver", "Europe/Dublin", NULL};
static const int INSTANTS[][6] = {{2026, 10, 13, 14, 30, 5}, {2026, 1, 1, 0, 0, 0},
  {2026, 7, 4, 23, 59, 59}, {2025, 12, 31, 6, 7, 8}, {2026, 3, 29, 1, 0, 0}};
static const char *PATTERNS[] = {"z", "zzzz", "O", "OOOO", "v", "vvvv", "V", "VV", "VVV", "VVVV",
  "Z", "ZZZZ", "ZZZZZ", "X", "XXX", "x", "xxx", "h:mm B", "h:mm BBBB", "h:mm BBBBB", "h:mm a",
  "EEEE d MMMM y G", "QQQ QQQQ qqqq", "w Y W", "e ee eee c ccc", "D F", "SSS", "K k H h",
  "LLL LLLL MMMMM", "yy", NULL};
static const char *SKELETONS[] = {"yMd", "yMMMd", "yMMMMd", "yMMMMEEEEd", "MMMd", "MMMMd", "MEd",
  "yMMM", "yMMMM", "Hm", "hm", "Hms", "jm", "jms", "Bhm", "yQQQ", "MMMMEd", "GyMMMd", "Ehm", NULL};

static void json_str(const UChar *s) {
  char buf[2048];
  UErrorCode e = U_ZERO_ERROR;
  u_strToUTF8(buf, sizeof buf, NULL, s, -1, &e);
  putchar('"');
  for (const char *p = buf; *p; p++) {
    if (*p == '"' || *p == '\\') { putchar('\\'); putchar(*p); }
    else if ((unsigned char)*p < 0x20) printf("\\u%04x", *p);
    else putchar(*p);
  }
  putchar('"');
}

static double instant_ms(const int *a) {
  UErrorCode e = U_ZERO_ERROR;
  UChar utc[4]; u_uastrcpy(utc, "UTC");
  UCalendar *c = ucal_open(utc, -1, "en", UCAL_GREGORIAN, &e);
  ucal_clear(c);
  ucal_setDateTime(c, a[0], a[1] - 1, a[2], a[3], a[4], a[5], &e);
  double ms = ucal_getMillis(c, &e);
  ucal_close(c);
  return ms;
}

static void args_instant(const int *a) {
  printf("[%d,%d,%d,%d,%d,%d,0]", a[0], a[1], a[2], a[3], a[4], a[5]);
}

static void emit(const char *op, UDateFormat *f, double ms, UErrorCode e) {
  UChar out[1024];
  (void)op;
  if (U_FAILURE(e)) { printf(", \"error\": \"%s\"}\n", u_errorName(e)); return; }
  udat_format(f, ms, out, 1024, NULL, &e);
  printf(", \"expect\": "); json_str(out); printf("}\n");
}

int main(void) {
  UChar uz[64], upat[256], best[256];
  for (const char **loc = LOCALES; *loc; loc++) {
    /* the Gregorian calendar, which babel.dates uses (fa defaults to the
       Persian one in ICU) */
    char gloc[64];
    snprintf(gloc, sizeof gloc, "%s@calendar=gregorian", *loc);
    for (int i = 0; i < 5; i++) {
      double ms = instant_ms(INSTANTS[i]);
      for (const char **zone = ZONES; *zone; zone++) {
        u_uastrcpy(uz, *zone);
        for (const char **pat = PATTERNS; *pat; pat++) {
          UErrorCode e = U_ZERO_ERROR;
          u_uastrcpy(upat, *pat);
          UDateFormat *f = udat_open(UDAT_PATTERN, UDAT_PATTERN, gloc, uz, -1, upat, -1, &e);
          printf("{\"op\": \"icu_pattern\", \"args\": ["); args_instant(INSTANTS[i]);
          printf(", \"%s\", ", *zone); json_str(upat); printf(", \"%s\"]", *loc);
          emit("icu_pattern", f, ms, e);
          if (f) udat_close(f);
        }
      }
      const char *styles[] = {"full", "long", "medium", "short"};
      const UDateFormatStyle ustyles[] = {UDAT_FULL, UDAT_LONG, UDAT_MEDIUM, UDAT_SHORT};
      const char *zones3[] = {"America/Lima", "Europe/Madrid", "Asia/Kolkata"};
      for (int z = 0; z < 3; z++) {
        u_uastrcpy(uz, zones3[z]);
        for (int s = 0; s < 4; s++) {
          const UDateFormatStyle ds[3] = {ustyles[s], UDAT_NONE, ustyles[s]};
          const UDateFormatStyle ts[3] = {UDAT_NONE, ustyles[s], ustyles[s]};
          const char *kinds[3] = {"date", "time", "datetime"};
          for (int k = 0; k < 3; k++) {
            UErrorCode e = U_ZERO_ERROR;
            UDateFormat *f = udat_open(ts[k], ds[k], gloc, uz, -1, NULL, 0, &e);
            printf("{\"op\": \"icu_style\", \"args\": ["); args_instant(INSTANTS[i]);
            printf(", \"%s\", \"%s\", \"%s\", \"%s\"]", zones3[z], kinds[k], styles[s], *loc);
            emit("icu_style", f, ms, e);
            if (f) udat_close(f);
          }
        }
        UErrorCode pe = U_ZERO_ERROR;
        UDateTimePatternGenerator *g = udatpg_open(gloc, &pe);
        for (const char **sk = SKELETONS; *sk; sk++) {
          UErrorCode e = U_ZERO_ERROR;
          UChar usk[64]; u_uastrcpy(usk, *sk);
          udatpg_getBestPattern(g, usk, -1, best, 256, &e);
          UDateFormat *f = U_SUCCESS(e) ? udat_open(UDAT_PATTERN, UDAT_PATTERN, gloc, uz, -1, best, -1, &e) : NULL;
          printf("{\"op\": \"icu_skeleton\", \"args\": [\"%s\", ", *sk); args_instant(INSTANTS[i]);
          printf(", \"%s\", \"%s\"]", zones3[z], *loc);
          emit("icu_skeleton", f, ms, e);
          if (f) udat_close(f);
        }
        udatpg_close(g);
      }
    }
    /* relative times */
    const char *units[] = {"second", "minute", "hour", "day", "week", "month", "year"};
    const URelativeDateTimeUnit uunits[] = {UDAT_REL_UNIT_SECOND, UDAT_REL_UNIT_MINUTE,
      UDAT_REL_UNIT_HOUR, UDAT_REL_UNIT_DAY, UDAT_REL_UNIT_WEEK, UDAT_REL_UNIT_MONTH, UDAT_REL_UNIT_YEAR};
    const long secs[] = {1, 60, 3600, 86400, 604800, 2592000, 31536000};
    const char *rstyles[] = {"long", "short", "narrow"};
    const UDateRelativeDateTimeFormatterStyle urstyles[] = {UDAT_STYLE_LONG, UDAT_STYLE_SHORT, UDAT_STYLE_NARROW};
    const int values[] = {-3, -1, 1, 2, 5};
    for (int u = 0; u < 7; u++)
      for (int s = 0; s < 3; s++)
        for (int v = 0; v < 5; v++) {
          UErrorCode e = U_ZERO_ERROR;
          URelativeDateTimeFormatter *r = ureldatefmt_open(*loc, NULL, urstyles[s], UDISPCTX_CAPITALIZATION_NONE, &e);
          UChar out[256];
          ureldatefmt_formatNumeric(r, values[v], uunits[u], out, 256, &e);
          printf("{\"op\": \"icu_relative\", \"args\": [%ld, \"%s\", \"%s\", \"%s\"]",
                 values[v] * secs[u], units[u], rstyles[s], *loc);
          if (U_FAILURE(e)) printf(", \"error\": \"%s\"}\n", u_errorName(e));
          else { printf(", \"expect\": "); json_str(out); printf("}\n"); }
          ureldatefmt_close(r);
        }
  }
  UVersionInfo cldr; char vs[32]; UErrorCode e = U_ZERO_ERROR;
  ulocdata_getCLDRVersion(cldr, &e); u_versionToString(cldr, vs);
  fprintf(stderr, "ICU vectors written (CLDR %s)\n", vs);
  return 0;
}

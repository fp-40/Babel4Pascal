"""Read the CLDR XML release (the cldr-common-<version>.zip of unicode.org,
extracted) into Python dicts: one dict of global data and one sparse dict
per locale.

The dicts have the same keys and values as the global.dat and
locale-data/*.dat files of Python Babel 2.18.0 (plus the keys listed in
EXTRA_GLOBAL_KEYS, which Babel does not have), which its
scripts/import_cldr.py builds from the same XML release. This module
follows that script rule by rule (which elements are skipped as drafts or
alternates, how aliases are recorded, which numbering systems are kept),
so that the Pascal library formats exactly as Babel does. Differences in
representation, all reversible:

- number and date patterns are kept as their pattern strings (Babel
  stores parsed NumberPattern and DateTimePattern objects);
- a plural rule is a list of [category, condition] pairs, the condition
  as written in CLDR without its samples (Babel stores a parsed
  PluralRule);
- tuples are lists, and sets do not occur.

tools/check_import.py compares the output with the .dat files of an
installed Babel.

Babel's import_cldr.py is Copyright (C) 2007-2011 Edgewall Software,
2013-2026 the Babel team, BSD-3-Clause; see tools/cldrgen/NOTICE.
"""
import collections
import os
import re
from xml.etree import ElementTree

from .model import Alias

# Data that Babel does not import (babel.numbers uses it to follow CLDR).
EXTRA_GLOBAL_KEYS = {'numbering_system_digits', 'time_data', 'primary_zones',
                     'metazone_golden_zones', 'zone_bcp47'}
EXTRA_LOCALE_KEYS = {'min_grouping_digits', 'currency_spacing', 'numbering_system_formats',
                     'gmt_formats', 'datetime_formats_at_time', 'date_field_aliases'}

WEEKDAYS = {'mon': 0, 'tue': 1, 'wed': 2, 'thu': 3, 'fri': 4, 'sat': 5, 'sun': 6}

NAME_RE = re.compile(r"^\w+$")
TYPE_ATTR_RE = re.compile(r"^\w+\[@type='(.*?)'\]$")

NAME_MAP = {
    'dateFormats': 'date_formats',
    'dateTimeFormats': 'datetime_formats',
    'eraAbbr': 'abbreviated',
    'eraNames': 'wide',
    'eraNarrow': 'narrow',
    'timeFormats': 'time_formats',
}

# Date pattern letters (Babel's dates.PATTERN_CHARS keys).
PATTERN_CHARS = set("GyYuQqMLwWdDFgEecabBhHKkmsSAzZOvVxX")


def _parse(path):
    return ElementTree.parse(path)


def _drop_unconfirmed(tree):
    """Remove the elements of unconfirmed or provisional status (and what
    they contain), as ICU does: their values are inherited from the parent
    locale instead (fr's short 'TU' for UTC is unconfirmed). Babel imports
    them. Contributed and approved data stay."""
    parents = {child: parent for parent in tree.iter() for child in parent}
    for elem in [e for e in tree.iter() if e.attrib.get('draft') in ('unconfirmed', 'provisional')]:
        parent = parents.get(elem)
        if parent is None or elem not in list(parent):
            continue        # already removed with an ancestor
        parent.remove(elem)
        # a container left empty goes too (a dateFormatLength whose only
        # pattern was unconfirmed), so that the parent's value is used
        while parent in parents and len(parent) == 0 and not (parent.text or '').strip():
            grand = parents[parent]
            grand.remove(parent)
            parent = grand


def _text(elem):
    buf = [elem.text or '']
    for child in elem:
        buf.append(_text(child))
    buf.append(elem.tail or '')
    return ''.join(filter(None, buf)).strip()


def _translate_alias(ctxt, path):
    keys = list(ctxt)
    for part in path.split('/'):
        if part == '..':
            keys.pop()
        else:
            match = TYPE_ATTR_RE.match(part)
            if match:
                keys.append(match.group(1))
            else:
                assert NAME_RE.match(part), part
                keys.append(NAME_MAP.get(part, part))
    return keys


def _parse_currency_date(s):
    if not s:
        return None
    parts = s.split('-', 2)
    return [int(p) for p in parts + [1] * (3 - len(parts))]


def _currency_sort_key(tup):
    code, start, end, tender = tup
    return int(not tender), tuple(start) if start else (1, 1, 1)


def _extract_plural_rules(path):
    """{locale: [[category, condition], ...]}. The samples that follow the
    condition ('@integer 1, 21, ...') are dropped, as Babel's parser does."""
    rules_by_locale = {}
    for elem in _parse(path).findall('.//plurals/pluralRules'):
        rules = [[rule.attrib['count'], str(rule.text).split('@', 1)[0].strip()]
                 for rule in elem.findall('pluralRule')]
        for locale in elem.attrib['locales'].split():
            rules_by_locale[locale] = rules
    return rules_by_locale


def _time_to_seconds_past_midnight(time_expr):
    if time_expr is None:
        return None
    if time_expr.count(":") == 1:
        time_expr += ":00"
    hour, minute, second = (int(p, 10) for p in time_expr.split(":"))
    return hour * 3600 + minute * 60 + second


def _is_draft_or_alt(elem):
    return 'draft' in elem.attrib or 'alt' in elem.attrib


def _should_skip_elem(elem, type=None, dest=None):
    """A draft or alternate element is skipped when dest is not given or
    already holds its type."""
    return _is_draft_or_alt(elem) and (dest is None or type in dest)


def _should_skip_number_elem(elem):
    """Only the Latin numbering system is imported (as in Babel)."""
    return elem.get('numberSystem', 'latn') != 'latn'


def _import_type_text(dest, elem, type=None, *, allow_variant_and_draft_fallback=True):
    if type is None:
        type = elem.attrib['type']
    if type in dest:
        return
    if not allow_variant_and_draft_fallback and _is_draft_or_alt(elem):
        return
    dest[type] = _text(elem)


# --- date patterns (Babel's dates.tokenize_pattern and friends) -------------

def tokenize_date_pattern(pattern):
    result = []
    quotebuf = None
    charbuf = []
    fieldchar = ''
    fieldnum = 0

    for char in pattern.replace("''", '\0'):
        if quotebuf is None:
            if char == "'":
                if fieldchar:
                    result.append(('field', (fieldchar, fieldnum)))
                    fieldchar, fieldnum = '', 0
                elif charbuf:
                    result.append(('chars', ''.join(charbuf).replace('\0', "'")))
                    charbuf = []
                quotebuf = []
            elif char in PATTERN_CHARS:
                if charbuf:
                    result.append(('chars', ''.join(charbuf).replace('\0', "'")))
                    charbuf = []
                if char == fieldchar:
                    fieldnum += 1
                else:
                    if fieldchar:
                        result.append(('field', (fieldchar, fieldnum)))
                    fieldchar, fieldnum = char, 1
            else:
                if fieldchar:
                    result.append(('field', (fieldchar, fieldnum)))
                    fieldchar, fieldnum = '', 0
                charbuf.append(char)
        else:
            if char == "'":
                charbuf.extend(quotebuf)
                quotebuf = None
            else:
                quotebuf.append(char)

    if fieldchar:
        result.append(('field', (fieldchar, fieldnum)))
    elif charbuf:
        result.append(('chars', ''.join(charbuf).replace('\0', "'")))
    return result


def untokenize_date_pattern(tokens):
    output = []
    for tok_type, tok_value in tokens:
        if tok_type == 'field':
            output.append(tok_value[0] * tok_value[1])
        elif not any(ch in PATTERN_CHARS for ch in tok_value):
            output.append(tok_value)
        else:
            output.append("'%s'" % tok_value.replace("'", "''"))
    return ''.join(output)


def split_interval_pattern(pattern):
    seen_fields = set()
    parts = [[]]
    for tok_type, tok_value in tokenize_date_pattern(pattern):
        if tok_type == 'field':
            if tok_value[0] in seen_fields:
                parts.append([])
                seen_fields.clear()
            seen_fields.add(tok_value[0])
        parts[-1].append((tok_type, tok_value))
    return [untokenize_date_pattern(tokens) for tokens in parts]


# --- global data -------------------------------------------------------------

def parse_global(srcdir):
    sup_dir = os.path.join(srcdir, 'supplemental')
    sup = _parse(os.path.join(sup_dir, 'supplementalData.xml'))
    g = {}
    with open(os.path.join(srcdir, 'dtd', 'ldml.dtd'), encoding='utf-8') as f:
        match = re.search(r'<!ATTLIST version cldrVersion CDATA #FIXED "(.+?)"', f.read())
    if not match:
        raise ValueError('no CLDR version in dtd/ldml.dtd')
    g['cldr'] = {'version': match.group(1)}
    territory_zones = g.setdefault('territory_zones', {})
    zone_aliases = g.setdefault('zone_aliases', {})
    zone_territories = g.setdefault('zone_territories', {})
    win_mapping = g.setdefault('windows_zone_mapping', {})
    language_aliases = g.setdefault('language_aliases', {})
    territory_aliases = g.setdefault('territory_aliases', {})
    script_aliases = g.setdefault('script_aliases', {})
    variant_aliases = g.setdefault('variant_aliases', {})
    likely_subtags = g.setdefault('likely_subtags', {})
    territory_currencies = g.setdefault('territory_currencies', {})
    parent_exceptions = g.setdefault('parent_exceptions', {})
    all_currencies = collections.defaultdict(set)
    currency_fractions = g.setdefault('currency_fractions', {})
    territory_languages = g.setdefault('territory_languages', {})

    bcp47_timezone = _parse(os.path.join(srcdir, 'bcp47', 'timezone.xml'))
    sup_windows_zones = _parse(os.path.join(sup_dir, 'windowsZones.xml'))
    sup_metadata = _parse(os.path.join(sup_dir, 'supplementalMetadata.xml'))
    sup_likely = _parse(os.path.join(sup_dir, 'likelySubtags.xml'))

    zone_territory_map = {}
    for map_zone in sup_windows_zones.findall('.//windowsZones/mapTimezones/mapZone'):
        if map_zone.attrib.get('territory') == '001':
            win_mapping[map_zone.attrib['other']] = map_zone.attrib['type'].split()[0]
        for tzid in str(map_zone.attrib['type']).split():
            zone_territory_map[tzid] = str(map_zone.attrib['territory'])
    for key_elem in bcp47_timezone.findall('.//keyword/key'):
        if key_elem.attrib['name'] == 'tz':
            for elem in key_elem.findall('type'):
                if 'deprecated' in elem.attrib:
                    continue
                aliases = str(elem.attrib['alias']).split()
                # The canonical IANA name when CLDR gives one (CLDR's own
                # canonical ids are often older names: Asia/Calcutta).
                tzid = elem.attrib.get('iana') or aliases[0]
                # windowsZones may name the zone by any of its aliases.
                territory = next((zone_territory_map[c] for c in (tzid, *aliases)
                                  if c in zone_territory_map), '001')
                territory_zones.setdefault(territory, []).append(tzid)
                zone_territories[tzid] = territory
                for alias in aliases:
                    if alias != tzid:
                        zone_aliases[alias] = tzid
            break

    meta_zones = g.setdefault('meta_zones', {})
    tzsup = _parse(os.path.join(sup_dir, 'metaZones.xml'))
    for elem in tzsup.findall('.//timezone'):
        for child in elem.findall('usesMetazone'):
            if 'to' not in child.attrib:
                meta_zones[elem.attrib['type']] = child.attrib['mzone']

    for alias in sup_metadata.findall('.//alias/languageAlias'):
        if '_' in alias.attrib['type']:
            continue
        language_aliases[alias.attrib['type']] = alias.attrib['replacement']
    for alias in sup_metadata.findall('.//alias/territoryAlias'):
        territory_aliases[alias.attrib['type']] = alias.attrib['replacement'].split()
    for alias in sup_metadata.findall('.//alias/scriptAlias'):
        script_aliases[alias.attrib['type']] = alias.attrib['replacement']
    for alias in sup_metadata.findall('.//alias/variantAlias'):
        repl = alias.attrib.get('replacement')
        if repl:
            variant_aliases[alias.attrib['type']] = repl

    for likely_subtag in sup_likely.findall('.//likelySubtags/likelySubtag'):
        likely_subtags[likely_subtag.attrib['from']] = likely_subtag.attrib['to']

    for region in sup.findall('.//currencyData/region'):
        region_code = region.attrib['iso3166']
        region_currencies = []
        for currency in region.findall('./currency'):
            cur_code = currency.attrib['iso4217']
            region_currencies.append([
                cur_code,
                _parse_currency_date(currency.attrib.get('from')),
                _parse_currency_date(currency.attrib.get('to')),
                currency.attrib.get('tender', 'true') == 'true',
            ])
            all_currencies[cur_code].add(region_code)
        region_currencies.sort(key=_currency_sort_key)
        territory_currencies[region_code] = region_currencies
    g['all_currencies'] = {code: sorted(regions) for code, regions in all_currencies.items()}

    # Only unqualified parentLocales blocks; parent "root" (localeRules=
    # "nonlikelyScript") is applied at load time.
    for parent_block in sup.findall('.//parentLocales'):
        if parent_block.attrib.get('component'):
            continue
        for paternity in parent_block.findall('./parentLocale'):
            parent = paternity.attrib['parent']
            if parent == 'root':
                continue
            for child in paternity.attrib['locales'].split():
                parent_exceptions[child] = parent

    for fraction in sup.findall('.//currencyData/fractions/info'):
        digits = int(fraction.attrib['digits'])
        rounding = int(fraction.attrib['rounding'])
        currency_fractions[fraction.attrib['iso4217']] = [
            digits,
            rounding,
            int(fraction.attrib.get('cashDigits', digits)),
            int(fraction.attrib.get('cashRounding', rounding)),
        ]

    # Not in Babel: the digits of each numeric numbering system, so that
    # numbers can be written in the locale's digits.
    digits = g.setdefault('numbering_system_digits', {})
    for ns in _parse(os.path.join(sup_dir, 'numberingSystems.xml')).findall('.//numberingSystem'):
        if ns.attrib.get('type') == 'numeric':
            digits[ns.attrib['id']] = ns.attrib['digits']

    # Not in Babel: the primary zone of countries with several zones
    # (Europe/Madrid for ES: 'Spain Time'), the golden zone of each
    # metazone per territory (for partial location names), and the short
    # BCP 47 id of each zone (the V field: 'usnyc').
    primary = g.setdefault('primary_zones', {})
    for elem in tzsup.findall('.//primaryZones/primaryZone'):
        primary[elem.attrib['iso3166']] = elem.text
    golden = g.setdefault('metazone_golden_zones', {})
    for elem in tzsup.findall('.//mapTimezones/mapZone'):
        golden.setdefault(elem.attrib['other'], {})[elem.attrib['territory']] = elem.attrib['type']
    bcp47 = g.setdefault('zone_bcp47', {})
    for key_elem in bcp47_timezone.findall('.//keyword/key'):
        if key_elem.attrib['name'] == 'tz':
            for elem in key_elem.findall('type'):
                if 'deprecated' in elem.attrib:
                    continue
                for alias in str(elem.attrib.get('alias', '')).split():
                    bcp47.setdefault(alias, elem.attrib['name'])
                iana = elem.attrib.get('iana')
                if iana:
                    bcp47.setdefault(iana, elem.attrib['name'])

    # Not in Babel: the hour cycles of each region or locale (for the
    # skeleton characters j, J and C).
    time_data = g.setdefault('time_data', {})
    for hours in sup.findall('.//timeData/hours'):
        for region in hours.attrib['regions'].split():
            time_data[region] = {'preferred': hours.attrib['preferred'],
                                 'allowed': hours.attrib['allowed']}

    for territory in sup.findall('.//territoryInfo/territory'):
        languages = {}
        for language in territory.findall('./languagePopulation'):
            languages[language.attrib['type']] = {
                'population_percent': float(language.attrib['populationPercent']),
                'official_status': language.attrib.get('officialStatus'),
            }
        territory_languages[territory.attrib['type']] = languages
    return g


# --- per-locale data ---------------------------------------------------------

class LocaleImporter:
    """Holds the supplemental data shared by every locale and imports one
    locale file at a time (import_locale)."""

    def __init__(self, srcdir, babel_compat=False):
        """babel_compat: reproduce Babel 2.18's data exactly, including the
        errors corrected here (see _parse_calendar_datetime_skeletons), to
        compare the importer with Babel's pickles."""
        self.srcdir = srcdir
        self.babel_compat = babel_compat
        sup_dir = os.path.join(srcdir, 'supplemental')
        self.sup = _parse(os.path.join(sup_dir, 'supplementalData.xml'))
        self.day_period_rules = _parse_day_period_rules(_parse(os.path.join(sup_dir, 'dayPeriods.xml')))
        regions = {}
        for elem in self.sup.findall('.//territoryContainment/group'):
            regions[elem.attrib['type']] = elem.attrib['contains'].split()
        # The same (order-dependent) resolution as Babel's importer.
        self.territory_containment = {}
        for group, territory_list in sorted(regions.items()):
            for territory in territory_list:
                containers = self.territory_containment.setdefault(territory, set())
                if group in self.territory_containment:
                    containers |= self.territory_containment[group]
                containers.add(group)
        self.likely_subtags = {elem.attrib['from']: elem.attrib['to'] for elem in
                               _parse(os.path.join(sup_dir, 'likelySubtags.xml'))
                               .findall('.//likelySubtags/likelySubtag')}
        self.plural_rules = _extract_plural_rules(os.path.join(sup_dir, 'plurals.xml'))
        self.ordinal_rules = _extract_plural_rules(os.path.join(sup_dir, 'ordinals.xml'))

    def locale_names(self):
        """Every locale of the release (the stems of main/*.xml), root first."""
        names = [os.path.splitext(f)[0] for f in os.listdir(os.path.join(self.srcdir, 'main'))
                 if f.endswith('.xml')]
        names.remove('root')
        return ['root'] + sorted(names)

    def import_locale(self, name):
        tree = _parse(os.path.join(self.srcdir, 'main', name + '.xml'))
        if not self.babel_compat:
            _drop_unconfirmed(tree)
        language = None
        elem = tree.find('.//identity/language')
        if elem is not None:
            language = elem.attrib['type']
        territory = '001'
        elem = tree.find('.//identity/territory')
        if elem is not None:
            territory = elem.attrib['type']
        regions = self.territory_containment.get(territory, [])
        locale_id = '_'.join(filter(None, [language, territory != '001' and territory or None]))

        data = {'locale_id': locale_id}
        if locale_id in self.plural_rules:
            data['plural_form'] = self.plural_rules[locale_id]
        if locale_id in self.ordinal_rules:
            data['ordinal_form'] = self.ordinal_rules[locale_id]
        if locale_id in self.day_period_rules:
            data['day_period_rules'] = self.day_period_rules[locale_id]

        _parse_locale_display_names(data, tree, is_global='_' not in locale_id)
        _parse_list_patterns(data, tree)
        # The week of a locale without a region is its likely region's (en:
        # US, Sunday), as CLDR specifies and ICU does; Babel used the
        # world's (Monday).
        week_territory, week_regions = territory, regions
        if not self.babel_compat and territory == '001' and name != 'root':
            # by the full name first: zh_Hant is TW, zh is CN
            likely = self.likely_subtags.get(name, self.likely_subtags.get(locale_id, '')).split('_')
            if len(likely) >= 2 and re.fullmatch(r'[A-Z]{2}|[0-9]{3}', likely[-1]):
                week_territory = likely[-1]
                week_regions = self.territory_containment.get(week_territory, [])
        _parse_dates(data, tree, self.sup, week_regions, week_territory, self.babel_compat)
        for calendar in tree.findall('.//calendars/calendar'):
            if calendar.attrib['type'] != 'gregorian':
                continue
            _parse_calendar_context(data, calendar, 'months', 'month', int)
            _parse_calendar_context(data, calendar, 'days', 'day', WEEKDAYS.__getitem__)
            _parse_calendar_context(data, calendar, 'quarters', 'quarter', int)
            _parse_calendar_eras(data, calendar)
            _parse_calendar_periods(data, calendar)
            _parse_calendar_formats(data, calendar, 'dateFormats', 'dateFormatLength',
                                    'date_formats', 'dateFormat/pattern')
            _parse_calendar_formats(data, calendar, 'timeFormats', 'timeFormatLength',
                                    'time_formats', 'timeFormat/pattern')
            _parse_calendar_datetime_skeletons(data, calendar, self.babel_compat)
            _parse_interval_formats(data, calendar, self.babel_compat)
        _parse_number_symbols(data, tree)
        _parse_numbering_systems(data, tree)
        _parse_decimal_formats(data, tree)
        _parse_simple_number_formats(data, tree, 'scientificFormats', './scientificFormatLength',
                                     'scientific_formats', 'scientificFormat/pattern')
        _parse_simple_number_formats(data, tree, 'percentFormats', './/percentFormatLength',
                                     'percent_formats', 'percentFormat/pattern')
        _parse_currency_formats(data, tree)
        _parse_number_extras(data, tree)
        _parse_date_extras(data, tree)
        _parse_currency_unit_patterns(data, tree)
        _parse_currency_names(data, tree)
        _parse_unit_patterns(data, tree)
        _parse_date_fields(data, tree)
        for elem in tree.findall('.//layout/orientation/characterOrder'):
            data['character_order'] = elem.text
        measurement_systems = data.setdefault('measurement_systems', {})
        for elem in tree.findall('.//measurementSystemNames/measurementSystemName'):
            type = elem.attrib['type']
            if not _should_skip_elem(elem, type, measurement_systems):
                _import_type_text(measurement_systems, elem, type=type)
        return data


def _parse_day_period_rules(tree):
    day_periods = {}
    for ruleset in tree.findall('.//dayPeriodRuleSet'):
        ruleset_type = ruleset.attrib.get('type')  # None or "selection"
        for rules in ruleset.findall('dayPeriodRules'):
            locales = rules.attrib['locales'].split()
            for rule in rules.findall('dayPeriodRule'):
                type = rule.attrib['type']
                if type in ('am', 'pm'):
                    continue
                compact = {}
                for key in ('after', 'at', 'before', 'from', 'to'):
                    value = _time_to_seconds_past_midnight(rule.attrib.get(key))
                    if value is not None:
                        compact[key] = value
                for locale in locales:
                    day_periods.setdefault(locale, {}).setdefault(ruleset_type, {}) \
                        .setdefault(type, []).append(compact)
    return day_periods


def _parse_locale_display_names(data, tree, *, is_global):
    for key, path in (('territories', './/territories/territory'),
                      ('languages', './/languages/language'),
                      ('variants', './/variants/variant'),
                      ('scripts', './/scripts/script')):
        dest = data.setdefault(key, {})
        for elem in tree.findall(path):
            _import_type_text(dest, elem, allow_variant_and_draft_fallback=is_global)


def _parse_list_patterns(data, tree):
    list_patterns = data.setdefault('list_patterns', {})
    for list_pattern_el in tree.findall('.//listPatterns/listPattern'):
        pattern_type = list_pattern_el.attrib.get('type', 'standard')
        for part in list_pattern_el.findall('listPatternPart'):
            list_patterns.setdefault(pattern_type, {})[part.attrib['type']] = _text(part)


def _parse_dates(data, tree, sup, regions, territory, babel_compat=False):
    week_data = data.setdefault('week_data', {})
    supelem = sup.find('.//weekData')
    for tag, key, convert in (('minDays', 'min_days', None),
                              ('firstDay', 'first_day', 'day'),
                              ('weekendStart', 'weekend_start', 'day'),
                              ('weekendEnd', 'weekend_end', 'day')):
        for elem in supelem.findall(tag):
            if _should_skip_elem(elem):
                continue
            territories = elem.attrib['territories'].split()
            if territory in territories or any(r in territories for r in regions):
                week_data[key] = int(elem.attrib['count']) if convert is None \
                    else WEEKDAYS[elem.attrib['day']]
        # A territory not listed has the world's value (CLDR); Babel left
        # the key out, so fr_CA inherited fr's minimal days (4, not 1).
        if not babel_compat and key not in week_data:
            for elem in supelem.findall(tag):
                if not _should_skip_elem(elem) and '001' in elem.attrib['territories'].split():
                    week_data[key] = int(elem.attrib['count']) if convert is None \
                        else WEEKDAYS[elem.attrib['day']]

    zone_formats = data.setdefault('zone_formats', {})
    for tag, key, convert in (
            ('gmtFormat', 'gmt', lambda s: s.replace('{0}', '%s')),
            ('regionFormat', 'region', lambda s: s.replace('{0}', '%s')),
            ('fallbackFormat', 'fallback', lambda s: s.replace('{0}', '%(0)s').replace('{1}', '%(1)s')),
            ('fallbackRegionFormat', 'fallback_region',
             lambda s: s.replace('{0}', '%(0)s').replace('{1}', '%(1)s'))):
        for elem in tree.findall('.//timeZoneNames/' + tag):
            # the plain regionFormat; Babel took the first one, which in
            # fr_CA is the daylight variant ('{0} (heure avancée)')
            if not _should_skip_elem(elem) and (babel_compat or 'type' not in elem.attrib):
                zone_formats[key] = convert(str(elem.text))
                break

    for key, tag in (('time_zones', 'zone'), ('meta_zones', 'metazone')):
        dest = data.setdefault(key, {})
        for elem in tree.findall('.//timeZoneNames/' + tag):
            info = {}
            city = elem.findtext('exemplarCity')
            if city:
                info['city'] = str(city)
            for child in elem.findall('long/*'):
                info.setdefault('long', {})[child.tag] = str(child.text)
            for child in elem.findall('short/*'):
                info.setdefault('short', {})[child.tag] = str(child.text)
            dest[elem.attrib['type']] = info


def _parse_calendar_context(data, calendar, key, item_tag, convert_type):
    """months, days and quarters: {context: {width: {index: name}}}."""
    dest = data.setdefault(key, {})
    singular = item_tag
    for ctxt in calendar.findall(f'{key}/{singular}Context'):
        ctxt_type = ctxt.attrib['type']
        ctxts = dest.setdefault(ctxt_type, {})
        for width in ctxt.findall(f'{singular}Width'):
            width_type = width.attrib['type']
            widths = ctxts.setdefault(width_type, {})
            for elem in width:
                if elem.tag == item_tag:
                    _import_type_text(widths, elem, convert_type(elem.attrib['type']))
                elif elem.tag == 'alias':
                    ctxts[width_type] = Alias(_translate_alias([key, ctxt_type, width_type],
                                                               elem.attrib['path']))


def _parse_calendar_eras(data, calendar):
    eras = data.setdefault('eras', {})
    for width in calendar.findall('eras/*'):
        width_type = NAME_MAP[width.tag]
        widths = eras.setdefault(width_type, {})
        for elem in width:
            if elem.tag == 'era':
                _import_type_text(widths, elem, type=int(elem.attrib.get('type')))
            elif elem.tag == 'alias':
                eras[width_type] = Alias(_translate_alias(['eras', width_type], elem.attrib['path']))


def _parse_calendar_periods(data, calendar):
    periods = data.setdefault('day_periods', {})
    for ctx in calendar.findall('dayPeriods/dayPeriodContext'):
        for width in ctx.findall('dayPeriodWidth'):
            dest = periods.setdefault(ctx.attrib['type'], {}).setdefault(width.attrib['type'], {})
            for day_period in width.findall('dayPeriod'):
                if 'alt' not in day_period.attrib:
                    dest[day_period.attrib['type']] = str(day_period.text)


def _parse_calendar_formats(data, calendar, container_tag, length_tag, key, pattern_path):
    """date_formats and time_formats: {length: pattern}.

    As in Babel, an alias element replaces the local variable only, so it
    never reaches the data (root's formats have no alias)."""
    formats = data.setdefault(key, {})
    for container in calendar.findall(container_tag):
        for elem in container:
            if elem.tag == length_tag:
                type = elem.attrib.get('type')
                if _should_skip_elem(elem, type, formats):
                    continue
                formats[type] = str(elem.findtext(pattern_path))
            elif elem.tag == 'alias':
                formats = Alias(_translate_alias([key], elem.attrib['path']))


def _parse_calendar_datetime_skeletons(data, calendar, babel_compat=False):
    """datetime_formats and datetime_skeletons. Babel takes every
    dateFormatItem, so an alternate (alt="ascii": 'h:mm a' for 'h:mm\u202fa'
    in en; alt="variant") that follows the item replaces it; here
    alternates are skipped, as ICU does, unless babel_compat."""
    datetime_formats = data.setdefault('datetime_formats', {})
    datetime_skeletons = data.setdefault('datetime_skeletons', {})
    for container in calendar.findall('dateTimeFormats'):
        for elem in container:
            if elem.tag == 'dateTimeFormatLength':
                type = elem.attrib.get('type')
                if _should_skip_elem(elem, type, datetime_formats):
                    continue
                datetime_formats[type] = str(elem.findtext('dateTimeFormat/pattern'))
            elif elem.tag == 'alias':
                datetime_formats = Alias(_translate_alias(['datetime_formats'], elem.attrib['path']))
            elif elem.tag == 'availableFormats':
                for skeleton in elem.findall('dateFormatItem'):
                    if not babel_compat and 'alt' in skeleton.attrib:
                        continue
                    datetime_skeletons[skeleton.attrib['id']] = str(skeleton.text)


def _parse_interval_formats(data, calendar, babel_compat=False):
    """interval_formats; alternate differences skipped as for skeletons."""
    interval_formats = data.setdefault('interval_formats', {})
    for elem in calendar.findall('dateTimeFormats/intervalFormats/*'):
        if 'draft' in elem.attrib:
            continue
        if elem.tag == 'intervalFormatFallback':
            interval_formats[None] = elem.text
        elif elem.tag == 'intervalFormatItem':
            skel_data = interval_formats.setdefault(elem.attrib['id'], {})
            for item_sub in elem:
                if item_sub.tag != 'greatestDifference':
                    raise NotImplementedError(f'{item_sub.tag}({item_sub.attrib!r})')
                if not babel_compat and 'alt' in item_sub.attrib:
                    continue
                skel_data[item_sub.attrib['id']] = split_interval_pattern(item_sub.text)


def _parse_number_symbols(data, tree):
    number_symbols = data.setdefault('number_symbols', {})
    for system_elem in tree.findall('.//numbers/symbols'):
        number_system = system_elem.get('numberSystem')
        if not number_system:
            continue
        for symbol in system_elem.findall('./*'):
            if _should_skip_elem(symbol):
                continue
            number_symbols.setdefault(number_system, {})[symbol.tag] = str(symbol.text)


def _parse_numbering_systems(data, tree):
    node = tree.find('.//numbers/defaultNumberingSystem')
    if node is not None:
        data['default_numbering_system'] = node.text
    numbering_systems = data.setdefault('numbering_systems', {})
    # Babel tests the element's truth value (`find(...) or []`): an element
    # with no children counts as absent.
    node = tree.find('.//numbers/otherNumberingSystems')
    if node is not None and len(node):
        for system in node:
            numbering_systems[system.tag] = system.text


def _parse_decimal_formats(data, tree):
    decimal_formats = data.setdefault('decimal_formats', {})
    for df_elem in tree.findall('.//decimalFormats'):
        if _should_skip_number_elem(df_elem):
            continue
        for elem in df_elem.findall('./decimalFormatLength'):
            length_type = elem.attrib.get('type')
            if _should_skip_elem(elem, length_type, decimal_formats):
                continue
            if elem.findall('./alias'):
                continue
            for pattern_el in elem.findall('./decimalFormat/pattern'):
                pattern_type = pattern_el.attrib.get('type')
                pattern = str(pattern_el.text)
                if pattern_type:
                    compact = data.setdefault('compact_decimal_formats', {})
                    compact.setdefault(length_type, {}) \
                        .setdefault(pattern_el.attrib['count'], {})[pattern_type] = pattern
                else:
                    decimal_formats[length_type] = pattern


def _parse_simple_number_formats(data, tree, container_tag, length_path, key, pattern_path):
    """scientific_formats and percent_formats: {length: pattern}."""
    formats = data.setdefault(key, {})
    for container in tree.findall('.//' + container_tag):
        if _should_skip_number_elem(container):
            continue
        for elem in container.findall(length_path):
            type = elem.attrib.get('type')
            if _should_skip_elem(elem, type, formats):
                continue
            formats[type] = str(elem.findtext(pattern_path))


def _parse_currency_formats(data, tree):
    currency_formats = data.setdefault('currency_formats', {})
    for currency_format in tree.findall('.//currencyFormats'):
        if _should_skip_number_elem(currency_format):
            continue
        for length_elem in currency_format.findall('./currencyFormatLength'):
            curr_length_type = length_elem.attrib.get('type')
            for elem in length_elem.findall('currencyFormat'):
                type = elem.attrib.get('type')
                if _should_skip_elem(elem, type, currency_formats):
                    continue
                for child in elem.iter():
                    if child.tag == 'alias':
                        currency_formats[type] = Alias(_translate_alias(
                            ['currency_formats', elem.attrib['type']], child.attrib['path']))
                    elif child.tag == 'pattern':
                        if child.attrib.get('draft') or child.attrib.get('alt'):
                            continue
                        pattern_type = child.attrib.get('type')
                        pattern = str(child.text)
                        if pattern_type:
                            compact = data.setdefault('compact_currency_formats', {})
                            compact.setdefault(curr_length_type, {}) \
                                .setdefault(child.attrib['count'], {})[pattern_type] = pattern
                        else:
                            currency_formats[type] = pattern


def _parse_number_extras(data, tree):
    """Not in Babel: minimumGroupingDigits, and the currencySpacing of the
    Latin numbering system (only root has one in CLDR 47)."""
    for elem in tree.findall('.//numbers/minimumGroupingDigits'):
        if elem.attrib.get('draft') in ('unconfirmed', 'provisional') or 'alt' in elem.attrib:
            continue
        data['min_grouping_digits'] = int(elem.text)
    for formats in tree.findall('.//currencyFormats'):
        if _should_skip_number_elem(formats):
            continue
        spacing = formats.find('currencySpacing')
        if spacing is None or spacing.find('alias') is not None:
            continue
        dest = {}
        for side in ('beforeCurrency', 'afterCurrency'):
            elem = spacing.find(side)
            if elem is not None:
                dest[side] = {child.tag: child.text or '' for child in elem}
        if dest:
            data['currency_spacing'] = dest

    # The patterns of the other numbering systems ({system: {kind:
    # pattern}}): CLDR gives some their own (fa's arab and arabext currency
    # pattern has no space; bn's beng percent pattern groups by three). An
    # alias (to the latn patterns) adds nothing: latn is the fallback.
    by_system = {}
    for tag, length_path, pattern_path, kind in (
            ('decimalFormats', 'decimalFormatLength', 'decimalFormat/pattern', 'decimal'),
            ('percentFormats', 'percentFormatLength', 'percentFormat/pattern', 'percent'),
            ('scientificFormats', 'scientificFormatLength', 'scientificFormat/pattern', 'scientific')):
        for formats in tree.findall('.//numbers/' + tag):
            ns = formats.get('numberSystem', 'latn')
            if ns == 'latn' or formats.find('alias') is not None:
                continue
            for length in formats.findall(length_path):
                if 'type' in length.attrib or _is_draft_or_alt(length) or length.find('alias') is not None:
                    continue
                for pattern in length.findall(pattern_path):
                    if 'type' in pattern.attrib or _is_draft_or_alt(pattern):
                        continue
                    by_system.setdefault(ns, {}).setdefault(kind, str(pattern.text))
    for formats in tree.findall('.//numbers/currencyFormats'):
        ns = formats.get('numberSystem', 'latn')
        if ns == 'latn' or formats.find('alias') is not None:
            continue
        for length in formats.findall('currencyFormatLength'):
            if 'type' in length.attrib:
                continue
            for fmt in length.findall('currencyFormat'):
                kind = 'currency_' + fmt.attrib.get('type', 'standard')
                if _is_draft_or_alt(fmt) or fmt.find('alias') is not None:
                    continue
                for pattern in fmt.findall('pattern'):
                    if 'type' in pattern.attrib or _is_draft_or_alt(pattern):
                        continue
                    by_system.setdefault(ns, {}).setdefault(kind, str(pattern.text))
    if by_system:
        data['numbering_system_formats'] = by_system


def _parse_date_extras(data, tree):
    """Not in Babel: hourFormat and gmtZeroFormat (localized GMT), and the
    atTime variant of the Gregorian date-time patterns."""
    gmt = {}
    for tag, key in (('hourFormat', 'hour'), ('gmtZeroFormat', 'gmt_zero')):
        for elem in tree.findall('.//timeZoneNames/' + tag):
            if not _should_skip_elem(elem):
                gmt[key] = str(elem.text)
                break
    if gmt:
        data['gmt_formats'] = gmt
    for calendar in tree.findall('.//calendars/calendar'):
        if calendar.attrib['type'] != 'gregorian':
            continue
        at_time = {}
        for length in calendar.findall('dateTimeFormats/dateTimeFormatLength'):
            if _is_draft_or_alt(length):
                continue
            for fmt in length.findall('dateTimeFormat'):
                pattern = fmt.findtext('pattern')
                if fmt.attrib.get('type') == 'atTime' and not _is_draft_or_alt(fmt) and pattern:
                    at_time[length.attrib.get('type')] = str(pattern)
        if at_time:
            data['datetime_formats_at_time'] = at_time
    # Not in Babel: the aliases between relative-time fields
    # ('second-narrow' is 'second-short' in root), which Babel imports as
    # empty fields.
    aliases = {}
    for field in tree.findall('.//dates/fields/field'):
        alias = field.find('alias')
        if alias is not None:
            m = re.search(r"field\[@type='([^']+)'\]", alias.attrib['path'])
            if m:
                aliases[field.attrib['type']] = m.group(1)
    if aliases:
        data['date_field_aliases'] = aliases


def _parse_currency_unit_patterns(data, tree):
    currency_unit_patterns = data.setdefault('currency_unit_patterns', {})
    for elem in tree.findall('.//currencyFormats'):
        if _should_skip_number_elem(elem):
            continue
        for unit_pattern in elem.findall('./unitPattern'):
            currency_unit_patterns[unit_pattern.attrib['count']] = str(unit_pattern.text)


def _parse_currency_names(data, tree):
    currency_names = data.setdefault('currency_names', {})
    currency_names_plural = data.setdefault('currency_names_plural', {})
    currency_symbols = data.setdefault('currency_symbols', {})
    for elem in tree.findall('.//currencies/currency'):
        code = elem.attrib['type']
        for name in elem.findall('displayName'):
            if 'draft' in name.attrib and code in currency_names:
                continue
            if 'count' in name.attrib:
                currency_names_plural.setdefault(code, {})[name.attrib['count']] = str(name.text)
            else:
                currency_names[code] = str(name.text)
        for symbol in elem.findall('symbol'):
            if 'draft' in symbol.attrib or 'choice' in symbol.attrib:
                continue
            if symbol.attrib.get('alt'):
                continue
            currency_symbols[code] = str(symbol.text)


def _parse_unit_patterns(data, tree):
    unit_patterns = data.setdefault('unit_patterns', {})
    compound_patterns = data.setdefault('compound_unit_patterns', {})
    unit_display_names = data.setdefault('unit_display_names', {})
    for elem in tree.findall('.//units/unitLength'):
        length = elem.attrib['type']
        for unit in elem.findall('unit'):
            unit_type = unit.attrib['type']
            dest = unit_patterns.setdefault(unit_type, {}).setdefault(length, {})
            for pattern in unit.findall('unitPattern'):
                if pattern.attrib.get('case', 'nominative') != 'nominative':
                    continue
                dest[pattern.attrib['count']] = _text(pattern)
            per_unit_pat = unit.find('perUnitPattern')
            if per_unit_pat is not None:
                dest['per'] = _text(per_unit_pat)
            display_name = unit.find('displayName')
            if display_name is not None:
                unit_display_names.setdefault(unit_type, {})[length] = _text(display_name)
        for unit in elem.findall('compoundUnit'):
            info = {}
            variations = {}
            for child in unit:
                if child.attrib.get('case', 'nominative') != 'nominative':
                    continue
                if child.tag == 'unitPrefixPattern':
                    info['prefix'] = _text(child)
                elif child.tag == 'compoundUnitPattern':
                    variations[None] = _text(child)
                elif child.tag == 'compoundUnitPattern1':
                    variations[child.attrib.get('count')] = _text(child)
            if variations:
                values = set(variations.values())
                if len(values) == 1:
                    info['compound'] = next(iter(values))
                else:
                    info['compound_variations'] = variations
            compound_patterns.setdefault(unit.attrib['type'], {})[length] = info


def _parse_date_fields(data, tree):
    date_fields = data.setdefault('date_fields', {})
    for elem in tree.findall('.//dates/fields/field'):
        field_type = elem.attrib['type']
        date_fields.setdefault(field_type, {})
        for rel_time in elem.findall('relativeTime'):
            for pattern in rel_time.findall('relativeTimePattern'):
                date_fields[field_type].setdefault(rel_time.attrib['type'], {})[
                    pattern.attrib['count']] = str(pattern.text)

"""Locale inheritance and the choice of locales to generate."""
import os


def _script_of(name):
    """The script subtag of a 'lang_Script' identifier, else None."""
    parts = name.split('_')
    if len(parts) == 2 and len(parts[1]) == 4 and parts[1].isalpha():
        return parts[1].title()
    return None


def parent_of(name, global_data):
    """The locale whose data `name` inherits, as Babel's localedata.load
    finds it: an explicit CLDR parentLocale; root for a 'lang_Script'
    locale whose script is not the language's likely script; else the
    identifier without its last subtag; root for a language alone."""
    if name == 'root':
        return None
    parent = global_data['parent_exceptions'].get(name)
    if parent:
        return parent
    script = _script_of(name)
    if script:
        lang = name.split('_')[0]
        likely = global_data['likely_subtags'].get(lang)
        if likely and _script_of('_'.join(likely.split('_')[:2])) != script:
            return 'root'
    parts = name.split('_')
    return 'root' if len(parts) == 1 else '_'.join(parts[:-1])


def chain(name, global_data):
    """name, its parent, ..., up to (and without) root."""
    while name != 'root':
        yield name
        name = parent_of(name, global_data)


def read_coverage_levels(srcdir):
    """{locale: level} from common/properties/coverageLevels.txt."""
    levels = {}
    with open(os.path.join(srcdir, 'properties', 'coverageLevels.txt'), encoding='utf-8') as f:
        for line in f:
            if line.startswith('#') or ';' not in line:
                continue
            loc, level = (p.strip() for p in line.split(';')[:2])
            levels[loc] = level
    return levels


def modern_locales(all_names, srcdir, global_data):
    """The locales whose nearest ancestor (or themselves) listed in
    coverageLevels.txt has level 'modern'."""
    levels = read_coverage_levels(srcdir)
    selected = []
    for name in all_names:
        if name == 'root':
            continue
        level = next((levels[c] for c in chain(name, global_data) if c in levels), None)
        if level == 'modern':
            selected.append(name)
    return selected


def with_ancestors(names, global_data):
    """names plus every locale they inherit from, root first, then sorted."""
    out = {'root'}
    for name in names:
        out.update(chain(name, global_data))
    return ['root'] + sorted(out - {'root'})

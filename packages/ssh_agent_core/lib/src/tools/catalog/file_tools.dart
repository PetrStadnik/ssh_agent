import 'common.dart';

const _pathHelp =
    'Absolute path, path relative to the current directory, or ~/...; '
    '* and ? wildcards are allowed.';

String _gnuFind(String gnu, String fallback) => fill(r'''if find / -maxdepth 0 -printf '' >/dev/null 2>&1; then
@GNU@
else
@FALLBACK@
fi''', {'GNU': gnu, 'FALLBACK': fallback});

final List<ToolDefinition> fileTools = [
  ToolDefinition(
    name: 'ls',
    category: ToolCategory.files,
    summary: 'Výpis adresáře (ls -la) s oprávněními, vlastníkem a časy',
    description:
        'List a directory like `ls -la`: permissions, owner, group, size in '
        'bytes and full modification time. Use directory_itself=true to show '
        'the entry of the directory itself (ls -ld).',
    params: [
      ToolParam.string('path', _pathHelp, defaultValue: '.'),
      ToolParam.boolean('all', 'Include hidden entries (-a).',
          defaultValue: true),
      ToolParam.string('sort', 'Sort order.',
          enumValues: ['name', 'time', 'size'], defaultValue: 'name'),
      ToolParam.boolean('recursive', 'List subdirectories recursively (-R).',
          defaultValue: false),
      ToolParam.boolean(
          'directory_itself', 'Show the directory entry itself (-d).',
          defaultValue: false),
      ToolParam.integer('max_lines', 'Maximum number of output lines.',
          defaultValue: 400, min: 10, max: 5000),
    ],
    script: (a) {
      final flags = StringBuffer('-l');
      if (a.flag('all')) flags.write('a');
      if (a.str('sort') == 'time') flags.write('t');
      if (a.str('sort') == 'size') flags.write('S');
      if (a.flag('recursive')) flags.write('R');
      if (a.flag('directory_itself')) flags.write('d');
      return fill(r'''if ls --time-style=full-iso -d / >/dev/null 2>&1; then
  ls @FLAGS@ --time-style=full-iso -- @P@
else
  ls @FLAGS@ -- @P@
fi @LIMIT@''', {
        'FLAGS': flags.toString(),
        'P': a.path('path'),
        'LIMIT': limit(a.integer('max_lines')),
      });
    },
  ),
  ToolDefinition(
    name: 'tree',
    category: ToolCategory.files,
    summary: 'Stromová struktura adresáře do zadané hloubky',
    description:
        'Show the directory structure (files and subdirectories) up to a '
        'depth, one path per line, directories end with "/".',
    params: [
      ToolParam.string('path', 'Directory.', defaultValue: '.'),
      ToolParam.integer('depth', 'Maximum depth.',
          defaultValue: 2, min: 1, max: 8),
      ToolParam.boolean('dirs_only', 'Show only directories.',
          defaultValue: false),
      ToolParam.integer('max_entries', 'Maximum number of entries.',
          defaultValue: 300, min: 10, max: 3000),
    ],
    timeout: const Duration(seconds: 60),
    script: (a) {
      final p = a.path('path', allowGlob: false);
      final depth = a.integer('depth');
      final dirsOnly = a.flag('dirs_only');
      final lim = limit(a.integer('max_entries'));
      final gnu = dirsOnly
          ? "find $p -mindepth 1 -maxdepth $depth -type d -printf '%p/\\n' | sort $lim"
          : "find $p -mindepth 1 -maxdepth $depth \\( -type d -printf '%p/\\n' \\) -o -printf '%p\\n' | sort $lim";
      final plain =
          'find $p -mindepth 1 -maxdepth $depth${dirsOnly ? ' -type d' : ''} | sort $lim';
      return _gnuFind(gnu, plain);
    },
  ),
  ToolDefinition(
    name: 'stat',
    category: ToolCategory.files,
    summary: 'Metadata souboru: časy změn, vlastník, oprávnění, velikost',
    description:
        'Show file metadata (`stat`): size, owner, permissions and timestamps. '
        'Modify = last content change, Change = last metadata change '
        '(permissions/owner/rename), Access = last read, Birth = creation '
        '(if the filesystem records it). Best tool for "when was X changed".',
    params: [ToolParam.string('path', _pathHelp, required: true)],
    script: (a) {
      final raw = a.str('path');
      final p = a.path('path');
      if (hasGlob(raw)) return 'stat -- $p';
      return fill(r'''stat -- @P@ || exit 1
printf 'Resolved path: '; readlink -f -- @P@ || echo '?'
true''', {'P': p});
    },
  ),
  ToolDefinition(
    name: 'file_type',
    category: ToolCategory.files,
    summary: 'Typ souboru (text, binárka, archiv, ...)',
    description: 'Detect the type of a file (`file`): text, ELF binary, '
        'archive, image, symlink...',
    params: [ToolParam.string('path', _pathHelp, required: true)],
    script: (a) => fill(r'''if command -v file >/dev/null 2>&1; then
  file -- @P@
else
  stat -c '%n: %F' -- @P@
fi''', {'P': a.path('path')}),
  ),
  ToolDefinition(
    name: 'cat',
    category: ToolCategory.files,
    summary: 'Obsah souboru (s limitem velikosti)',
    description:
        'Print the content of a text file (like `cat`), limited to max_bytes. '
        'For big files prefer head, tail, read_lines or grep.',
    params: [
      ToolParam.string('path', 'File path (no wildcards).', required: true),
      ToolParam.integer('max_bytes', 'Maximum number of bytes to return.',
          defaultValue: 16000, min: 100, max: 200000),
    ],
    binaryCheck: true,
    script: (a) => fill(r'''if [ -d @P@ ]; then echo 'This is a directory - use ls.' >&2; exit 1; fi
size=$(wc -c < @P@ | tr -d ' ') || exit 1
head -c @MAX@ < @P@
if [ "$size" -gt @MAX@ ]; then
  printf '\n\n[... file has %s bytes, only the first @MAX@ bytes are shown. Use read_lines, tail or grep for the rest.]\n' "$size"
fi''', {
      'P': a.path('path', allowGlob: false),
      'MAX': '${a.integer('max_bytes')}',
    }),
  ),
  ToolDefinition(
    name: 'head',
    category: ToolCategory.files,
    summary: 'Prvních N řádků souboru',
    description: 'Print the first N lines of a file (`head -n`).',
    params: [
      ToolParam.string('path', _pathHelp, required: true),
      ToolParam.integer('lines', 'Number of lines.',
          defaultValue: 40, min: 1, max: 3000),
    ],
    binaryCheck: true,
    script: (a) => 'head -n ${a.integer('lines')} -- ${a.path('path')}',
  ),
  ToolDefinition(
    name: 'tail',
    category: ToolCategory.files,
    summary: 'Posledních N řádků souboru (např. logu)',
    description:
        'Print the last N lines of a file (`tail -n`), ideal for log files.',
    params: [
      ToolParam.string('path', _pathHelp, required: true),
      ToolParam.integer('lines', 'Number of lines.',
          defaultValue: 40, min: 1, max: 3000),
    ],
    binaryCheck: true,
    script: (a) => 'tail -n ${a.integer('lines')} -- ${a.path('path')}',
  ),
  ToolDefinition(
    name: 'read_lines',
    category: ToolCategory.files,
    summary: 'Konkrétní rozsah řádků souboru s čísly řádků',
    description:
        'Print lines start_line..end_line of a file with line numbers, e.g. '
        'around a match found by grep (max 2000 lines at once).',
    params: [
      ToolParam.string('path', 'File path (no wildcards).', required: true),
      ToolParam.integer('start_line', 'First line (1-based).',
          required: true, min: 1),
      ToolParam.integer('end_line', 'Last line (inclusive).',
          required: true, min: 1),
    ],
    binaryCheck: true,
    script: (a) {
      final start = a.integer('start_line');
      var end = a.integer('end_line');
      if (end < start) {
        throw ToolArgumentException('end_line must be >= start_line.');
      }
      if (end - start > 2000) end = start + 2000;
      return fill(
          r'''awk -v s=@S@ -v e=@E@ 'NR>=s && NR<=e {printf "%6d  %s\n", NR, $0} NR>e {exit}' < @P@''',
          {
            'S': '$start',
            'E': '$end',
            'P': a.path('path', allowGlob: false),
          });
    },
  ),
  ToolDefinition(
    name: 'wc',
    category: ToolCategory.files,
    summary: 'Počet řádků, slov a bajtů',
    description: 'Count lines, words and bytes of files (`wc`).',
    params: [ToolParam.string('path', _pathHelp, required: true)],
    script: (a) => 'wc -l -w -c -- ${a.path('path')}',
  ),
  ToolDefinition(
    name: 'grep',
    category: ToolCategory.files,
    summary: 'Hledání textu v souborech (grep)',
    description:
        'Search file contents for a pattern (`grep -n`). Searches directories '
        'recursively by default and prints file:line:text. Binary files are '
        'skipped. Use mode=fixed for literal text.',
    params: [
      ToolParam.string('pattern', 'Text or regular expression to search for.',
          required: true),
      ToolParam.string('path', 'File or directory to search.',
          defaultValue: '.'),
      ToolParam.string('mode', 'Pattern syntax.',
          enumValues: ['fixed', 'basic', 'extended', 'perl'],
          defaultValue: 'extended'),
      ToolParam.boolean('ignore_case', 'Case-insensitive search.',
          defaultValue: false),
      ToolParam.boolean('recursive', 'Search directories recursively.',
          defaultValue: true),
      ToolParam.string('include',
          'Only search files whose name matches this glob, e.g. *.conf.'),
      ToolParam.integer('context_lines', 'Lines of context around matches.',
          defaultValue: 0, min: 0, max: 20),
      ToolParam.boolean('files_only', 'Only list names of matching files.',
          defaultValue: false),
      ToolParam.integer('max_results', 'Maximum number of output lines.',
          defaultValue: 150, min: 1, max: 3000),
    ],
    timeout: const Duration(seconds: 90),
    exitCodeMeaning: const {1: 'No matches found.'},
    script: (a) {
      final flags = <String>['-n', '-H', '-I'];
      if (a.flag('recursive')) flags.add('-r');
      if (a.flag('ignore_case')) flags.add('-i');
      switch (a.str('mode')) {
        case 'fixed':
          flags.add('-F');
        case 'extended':
          flags.add('-E');
        case 'perl':
          flags.add('-P');
      }
      final context = a.integer('context_lines');
      if (context > 0) flags.add('-C $context');
      if (a.flag('files_only')) flags.add('-l');
      if (a.has('include')) flags.add('--include=${a.quoted('include')}');
      return 'grep ${flags.join(' ')} -e ${a.quoted('pattern')} -- '
          '${a.path('path')} ${limit(a.integer('max_results'))}';
    },
  ),
  ToolDefinition(
    name: 'find',
    category: ToolCategory.files,
    summary: 'Vyhledání souborů podle jména, typu, vlastníka, času, velikosti',
    description:
        'Find files and directories (`find`) by name, type, owner, '
        'permissions, size or modification time. Combine filters as needed. '
        'Searching / can be slow - prefer a specific directory.',
    params: [
      ToolParam.string('path', 'Where to start.', defaultValue: '.'),
      ToolParam.string(
          'name', 'File name glob, case-sensitive, e.g. "*.log" or "config.php".'),
      ToolParam.string('iname', 'File name glob, case-insensitive.'),
      ToolParam.string('type', 'Entry type.',
          enumValues: ['file', 'directory', 'symlink']),
      ToolParam.string('user', 'Owned by this user.'),
      ToolParam.string('group', 'Owned by this group.'),
      ToolParam.string('perm',
          'Permission test as in find -perm, e.g. "-4000" (SUID), "-o+w" (world-writable), "644".'),
      ToolParam.string('size', 'Size test as in find -size, e.g. "+100M", "-1k".'),
      ToolParam.integer('modified_within_days', 'Modified in the last N days.',
          min: 0, max: 36500),
      ToolParam.integer(
          'modified_older_than_days', 'Modified more than N days ago.',
          min: 0, max: 36500),
      ToolParam.integer(
          'modified_within_minutes', 'Modified in the last N minutes.',
          min: 1, max: 1000000),
      ToolParam.string('newer_than', 'Modified more recently than this file.'),
      ToolParam.integer('max_depth', 'Maximum directory depth.',
          min: 0, max: 50),
      ToolParam.boolean('details',
          'Show details (permissions, owner, size, date) for each result.',
          defaultValue: false),
      ToolParam.integer('max_results', 'Maximum number of results.',
          defaultValue: 200, min: 1, max: 5000),
    ],
    timeout: const Duration(seconds: 120),
    script: (a) {
      final rawPath = a.str('path').trim();
      final parts = <String>['find', a.path('path')];
      if (a.has('max_depth')) parts.add('-maxdepth ${a.integer('max_depth')}');
      if (rawPath == '/') {
        parts.add(r'\( -path /proc -o -path /sys -o -path /dev -o -path /run \) -prune -o');
      }
      if (a.has('type')) {
        parts.add('-type ${{'file': 'f', 'directory': 'd', 'symlink': 'l'}[a.str('type')]}');
      }
      if (a.has('name')) parts.add('-name ${a.quoted('name')}');
      if (a.has('iname')) parts.add('-iname ${a.quoted('iname')}');
      if (a.has('user')) {
        parts.add('-user ${a.ident('user', userNamePattern, 'expected a user name')}');
      }
      if (a.has('group')) {
        parts.add('-group ${a.ident('group', userNamePattern, 'expected a group name')}');
      }
      if (a.has('perm')) {
        parts.add('-perm ${a.ident('perm', RegExp(r'^[-/]?([0-7]{3,4}|[ugoa]*[+=-]?[rwxXst]+(,[ugoa]*[+=-]?[rwxXst]+)*)$'), 'e.g. -4000, 644, -o+w')}');
      }
      if (a.has('size')) {
        parts.add('-size ${a.ident('size', RegExp(r'^[+-]?[0-9]+[cwbkMG]?$'), 'e.g. +100M')}');
      }
      if (a.has('modified_within_days')) {
        parts.add('-mtime -${a.integer('modified_within_days')}');
      }
      if (a.has('modified_older_than_days')) {
        parts.add('-mtime +${a.integer('modified_older_than_days')}');
      }
      if (a.has('modified_within_minutes')) {
        parts.add('-mmin -${a.integer('modified_within_minutes')}');
      }
      if (a.has('newer_than')) {
        parts.add('-newer ${a.path('newer_than', allowGlob: false)}');
      }
      parts.add(a.flag('details') ? '-ls' : '-print');
      return '${parts.join(' ')} ${limit(a.integer('max_results'))}';
    },
  ),
  ToolDefinition(
    name: 'recent_changes',
    category: ToolCategory.files,
    summary: 'Nedávno změněné soubory, seřazené od nejnovějších',
    description:
        'List files modified within the last N minutes/days under a '
        'directory, newest first, with time, owner, mode and size. Stays on '
        'one filesystem. Useful for "what changed recently".',
    params: [
      ToolParam.string('path', 'Directory to scan.', defaultValue: '/etc'),
      ToolParam.integer('within_days', 'Changed in the last N days.',
          defaultValue: 1, min: 1, max: 3650),
      ToolParam.integer('within_minutes',
          'Changed in the last N minutes (overrides within_days).',
          min: 1, max: 1000000),
      ToolParam.integer('max_results', 'Maximum number of results.',
          defaultValue: 100, min: 1, max: 3000),
    ],
    timeout: const Duration(seconds: 120),
    script: (a) {
      final minutes = a.intOrNull('within_minutes') ??
          a.integer('within_days') * 24 * 60;
      final p = a.path('path', allowGlob: false);
      final lim = limit(a.integer('max_results'));
      return _gnuFind(
        "find $p -xdev -type f -mmin -$minutes -printf '%T@ %TY-%Tm-%Td %TH:%TM %u:%g %m %s %p\\n' | sort -rn | cut -d' ' -f2- $lim",
        'find $p -xdev -type f -mmin -$minutes -ls $lim',
      );
    },
  ),
  ToolDefinition(
    name: 'du',
    category: ToolCategory.files,
    summary: 'Velikost adresářů (du), největší první',
    description:
        'Show disk usage of a directory and its subdirectories (`du -h`), '
        'largest first. Unreadable subdirectories are skipped.',
    params: [
      ToolParam.string('path', 'Directory.', defaultValue: '.'),
      ToolParam.integer('depth', 'Depth of subdirectories to summarise.',
          defaultValue: 1, min: 0, max: 5),
    ],
    timeout: const Duration(seconds: 120),
    script: (a) => fill(r'''[ -e @P@ ] || { echo 'No such file or directory' >&2; exit 1; }
du -h -x -d @D@ -- @P@ 2>/dev/null | sort -h -r @LIMIT@''', {
      'P': a.path('path', allowGlob: false),
      'D': '${a.integer('depth')}',
      'LIMIT': limit(60),
    }),
  ),
  ToolDefinition(
    name: 'disk_usage',
    category: ToolCategory.files,
    summary: 'Obsazení disků a připojené souborové systémy',
    description:
        'Show free/used space of mounted filesystems (`df -hT`) and '
        'optionally the list of mounts with options.',
    params: [
      ToolParam.boolean('include_mounts', 'Also list mounts and options.',
          defaultValue: false),
    ],
    script: (a) {
      final df = r'''df -hT -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null || df -h''';
      if (!a.flag('include_mounts')) return df;
      return '$df\necho\necho "--- mounts ---"\n'
          'findmnt -l -o TARGET,SOURCE,FSTYPE,OPTIONS --real 2>/dev/null || '
          r"grep -v -E ' (proc|sysfs|cgroup2?|tmpfs|devpts|mqueue|debugfs|tracefs|securityfs|pstore|bpf|configfs|fusectl|hugetlbfs|autofs|binfmt_misc) ' /proc/mounts";
    },
  ),
  ToolDefinition(
    name: 'checksum',
    category: ToolCategory.files,
    summary: 'Kontrolní součet souboru (sha256/md5/...)',
    description: 'Compute a checksum of files (sha256sum, sha1sum, md5sum, '
        'sha512sum) to compare or identify them.',
    params: [
      ToolParam.string('path', _pathHelp, required: true),
      ToolParam.string('algorithm', 'Hash algorithm.',
          enumValues: ['sha256', 'sha1', 'md5', 'sha512'],
          defaultValue: 'sha256'),
    ],
    timeout: const Duration(seconds: 90),
    script: (a) => '${a.str('algorithm')}sum -- ${a.path('path')}',
  ),
  ToolDefinition(
    name: 'diff',
    category: ToolCategory.files,
    summary: 'Rozdíly mezi dvěma soubory',
    description:
        'Compare two files or directories (`diff -u`). No output and exit '
        'code 0 means they are identical.',
    params: [
      ToolParam.string('path_a', 'First file.', required: true),
      ToolParam.string('path_b', 'Second file.', required: true),
    ],
    exitCodeMeaning: const {1: 'The files differ (see the diff).'},
    script: (a) =>
        'diff -u -- ${a.path('path_a', allowGlob: false)} ${a.path('path_b', allowGlob: false)} ${limit(500)}',
  ),
  ToolDefinition(
    name: 'binary_peek',
    category: ToolCategory.files,
    summary: 'Nahlédnutí do binárního souboru (hex / čitelné řetězce)',
    description:
        'Inspect a binary file: hex dump of a byte range (mode=hex) or the '
        'printable strings it contains (mode=strings).',
    params: [
      ToolParam.string('path', 'File path (no wildcards).', required: true),
      ToolParam.string('mode', 'What to show.',
          enumValues: ['hex', 'strings'], defaultValue: 'hex'),
      ToolParam.integer('offset', 'Start offset in bytes (hex mode).',
          defaultValue: 0, min: 0),
      ToolParam.integer('length', 'Number of bytes (hex mode).',
          defaultValue: 512, min: 16, max: 8192),
    ],
    script: (a) {
      final p = a.path('path', allowGlob: false);
      if (a.str('mode') == 'strings') {
        return fill(
            r'''head -c 4000000 < @P@ | tr -c '[:print:]' '\n' | grep -E '.{6,}' @LIMIT@''',
            {'P': p, 'LIMIT': limit(300)});
      }
      return fill(r'''od -A x -t x1z -v -j @O@ -N @L@ -- @P@ 2>/dev/null || od -A x -t x1 -v -j @O@ -N @L@ -- @P@''', {
        'P': p,
        'O': '${a.integer('offset')}',
        'L': '${a.integer('length')}',
      });
    },
  ),
  ToolDefinition(
    name: 'read_compressed',
    category: ToolCategory.files,
    summary: 'Čtení komprimovaných (rotovaných) logů .gz/.xz/.bz2/.zst',
    description:
        'Read a compressed file such as rotated logs (/var/log/syslog.2.gz), '
        'optionally filtered by a pattern. Works for .gz, .xz, .bz2, .zst '
        'and plain files.',
    params: [
      ToolParam.string('path', 'File path (no wildcards).', required: true),
      ToolParam.string('pattern',
          'Only lines matching this extended regular expression (case-insensitive).'),
      ToolParam.integer('lines', 'Maximum number of lines.',
          defaultValue: 100, min: 1, max: 3000),
      ToolParam.boolean('from_end', 'Show the last lines instead of the first.',
          defaultValue: false),
    ],
    timeout: const Duration(seconds: 90),
    exitCodeMeaning: const {1: 'No matching lines (or the file could not be read).'},
    binaryCheck: true,
    script: (a) {
      final raw = a.str('path').toLowerCase();
      final decompress = raw.endsWith('.gz') || raw.endsWith('.tgz')
          ? 'gzip -dc'
          : raw.endsWith('.bz2')
              ? 'bzip2 -dc'
              : raw.endsWith('.xz')
                  ? 'xz -dc'
                  : raw.endsWith('.zst')
                      ? 'zstd -dc'
                      : 'cat';
      final buf = StringBuffer('$decompress -- ${a.path('path', allowGlob: false)}');
      if (a.has('pattern')) buf.write(' | grep -i -E -e ${a.quoted('pattern')}');
      final n = a.integer('lines');
      buf.write(a.flag('from_end') ? ' | tail -n $n' : ' ${limit(n)}');
      return buf.toString();
    },
  ),
];

import re,json,pathlib
root=pathlib.Path(__file__).resolve().parents[2]
def strings(s):
 i=0
 while i<len(s):
  if s.startswith('//',i):
   p=s.find('\n',i); i=p if p>=0 else len(s); continue
  if s.startswith('/*',i):
   depth=1;i+=2
   while i<len(s) and depth:
    if s.startswith('/*',i):depth+=1;i+=2
    elif s.startswith('*/',i):depth-=1;i+=2
    else:i+=1
   continue
  if s[i]=='"':
   start=i;i+=1;parts=[];expr=[];chunk=''
   while i<len(s):
    if s.startswith('\\(',i):
     parts.append(chunk);chunk='';i+=2;a=i;d=1
     while i<len(s) and d:
      if s[i]=='"':
       # consume nested string, including its interpolations
       nxt=next(strings(s[i:]),None)
       i+=nxt[1] if nxt else 1
      elif s[i]=='(':d+=1;i+=1
      elif s[i]==')':d-=1;i+=1
      else:i+=1
     expr.append(s[a:i-1]);continue
    if s[i]=='\\':chunk+=s[i:i+2];i+=2;continue
    if s[i]=='"':i+=1;break
    chunk+=s[i];i+=1
   parts.append(chunk)
   template=''.join(p+('{'+str(n)+'}' if n<len(expr) else '') for n,p in enumerate(parts))
   template=template.replace('\\n','\n').replace('\\"','"').replace('\\t','\t').replace('\\\\','\\')
   yield start,i,template,expr
  else:i+=1

def scan(source):
 for a,b,text,args in strings(source):
  if re.search('[\u3400-\u9fff]',text): yield text
  for expression in args: yield from scan(expression)
def _blank(chars, start, end):
    chars[start:end] = ['\n' if c == '\n' else ' ' for c in chars[start:end]]


def _swift_code(source):
    """Mask literals/comments without changing offsets; keep interpolations for reference checks."""
    code = list(source)
    interpolations = []
    i = 0
    while i < len(source):
        if source.startswith('//', i):
            end = source.find('\n', i)
            end = len(source) if end < 0 else end
        elif source.startswith('/*', i):
            depth = 1
            end = i + 2
            while end < len(source) and depth:
                if source.startswith('/*', end):
                    depth += 1
                    end += 2
                elif source.startswith('*/', end):
                    depth -= 1
                    end += 2
                else:
                    end += 1
        elif source[i] == '"':
            _, length, _, arguments = next(strings(source[i:]))
            end = i + length
            interpolations.extend((i, expression) for expression in arguments)
        else:
            i += 1
            continue
        _blank(code, i, end)
        i = end
    return ''.join(code), interpolations


def _paired_end(code, start, opening, closing):
    depth = 1
    end = start + 1
    while end < len(code):
        if code[end] == opening:
            depth += 1
        elif code[end] == closing:
            depth -= 1
            if depth == 0:
                return end + 1
        end += 1
    return None


def _preview_ranges(code):
    ranges = []
    for match in re.finditer(r'#Preview\b', code):
        if ranges and match.start() < ranges[-1][1]:
            continue
        start = match.end()
        while start < len(code) and code[start].isspace():
            start += 1
        if start < len(code) and code[start] == '(':
            start = _paired_end(code, start, '(', ')')
            if start is None:
                continue
            while start < len(code) and code[start].isspace():
                start += 1
        if start >= len(code) or code[start] != '{':
            continue
        end = _paired_end(code, start, '{', '}')
        if end is None:
            continue
        # Widget previews also have named trailing closures such as contentStates.
        while trailing := re.match(r'\s*[A-Za-z_]\w*\s*:\s*\{', code[end:]):
            body = end + trailing.end() - 1
            trailing_end = _paired_end(code, body, '{', '}')
            if trailing_end is None:
                break
            end = trailing_end
        ranges.append((match.start(), end))
    return ranges


def _private_factories(code):
    private_scopes = []
    for match in re.finditer(r'\b(?:private|fileprivate)\s+(?:extension|struct|enum|class)\b[^{}]*\{', code):
        start = match.end() - 1
        end = _paired_end(code, start, '{', '}')
        if end is not None:
            private_scopes.append((start, end))
    modifiers = r'private|fileprivate|internal|public|open|package|static|class|final|override|mutating|nonmutating|nonisolated|dynamic'
    declarations = list(re.finditer(
        rf'\b(?P<modifiers>(?:(?:{modifiers})\s+)*)func\s+(?P<name>[A-Za-z_]\w*)\b', code))
    counts = {}
    for match in declarations:
        name = match['name']
        counts[name] = counts.get(name, 0) + 1
    factories = {}
    for match in declarations:
        name = match['name']
        flags = set(match['modifiers'].split())
        # Ambiguous names and externally visible/dynamic methods stay checked.
        if counts[name] != 1 or flags & {'internal', 'public', 'open', 'package', 'dynamic'}:
            continue
        private = bool(flags & {'private', 'fileprivate'}) or any(a < match.start() < b for a, b in private_scopes)
        if not private:
            continue
        parameters = code.find('(', match.end())
        if parameters < 0:
            continue
        header_end = _paired_end(code, parameters, '(', ')')
        if header_end is None:
            continue
        body = code.find('{', header_end)
        if body < 0 or re.search(r'[};]', code[header_end:body]):
            continue
        end = _paired_end(code, body, '{', '}')
        if end is not None:
            factories[name] = (match.start(), end, match.start('name'))
    return factories


def _references(code, interpolations):
    for match in re.finditer(r'[A-Za-z_]\w*', code):
        if not match.start() or code[match.start() - 1] != '#':
            yield match.start(), match[0]
    for offset, expression in interpolations:
        nested, arguments = _swift_code(expression)
        for _, name in _references(nested, arguments):
            yield offset, name


def _preview_helpers(code, interpolations, previews):
    factories = _private_factories(code)
    calls = {name: set() for name in factories}
    preview_roots, runtime_roots = set(), set()
    for position, name in _references(code, interpolations):
        if name not in factories or position == factories[name][2]:
            continue
        if any(a <= position < b for a, b in previews):
            preview_roots.add(name)
            continue
        owners = [owner for owner, (a, b, _) in factories.items() if a <= position < b]
        if owners:
            owner = min(owners, key=lambda item: factories[item][1] - factories[item][0])
            calls[owner].add(name)
        else:
            runtime_roots.add(name)

    def reachable(roots):
        seen = set()
        pending = list(roots)
        while pending:
            name = pending.pop()
            if name not in seen:
                seen.add(name)
                pending.extend(calls[name] - seen)
        return seen

    exclusive = reachable(preview_roots) - reachable(runtime_roots)
    return [(factories[name][0], factories[name][1]) for name in exclusive]


def without_previews(source):
    # Exempt only preview bodies and private helpers reachable exclusively from them.
    # DEBUG sections, unused helpers and helpers shared with application code stay checked.
    if '#Preview' not in source:
        return source
    code, interpolations = _swift_code(source)
    previews = _preview_ranges(code)
    if not previews:
        return source
    result = list(source)
    for start, end in previews + _preview_helpers(code, interpolations, previews):
        _blank(result, start, end)
    return ''.join(result)

def main():
 failures=[]
 for base in ['App','Watch','Widgets','Shared']:
  for file in (root/'OpenGYM-iOS'/base).rglob('*.swift'):
   for text in scan(without_previews(file.read_text())):failures.append(f'{file.relative_to(root)}: unlocalized Swift text: {text}')
 if failures:
  print('\n'.join(failures))
  raise SystemExit(1)
 print('No hardcoded Chinese in native application strings.')

if __name__=='__main__':main()

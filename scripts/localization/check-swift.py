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
failures=[]
for base in ['OpenGym','Shared']:
 for file in (root/'native-ios'/base).rglob('*.swift'):
  for text in scan(file.read_text()):failures.append(f'{file.relative_to(root)}: unlocalized Swift text: {text}')
if failures:
 print('\n'.join(failures))
 raise SystemExit(1)
print('No hardcoded Chinese in native application strings.')

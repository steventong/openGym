import { build } from 'esbuild';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
// The native bridge uses the same pure rules with the browser-free translation runtime.
const root = fileURLToPath(new URL('../', import.meta.url));
export const buildRules = (write = true) => build({absWorkingDir:root,entryPoints:['scripts/rules/entry.js'],bundle:true,format:'iife',globalName:'OpenGymRules',platform:'neutral',target:'es2020',minify:true,write,outfile:'OpenGym/Resources/web-rules.js',define:{'import.meta.env':'{}'},plugins:[{name:'native-i18n',setup(b){b.onResolve({filter:/\/i18n\.js$/},args=>({path:path.resolve(args.resolveDir,args.path.replace(/i18n\.js$/,'i18n-core.js'))}));}}]});
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await buildRules();

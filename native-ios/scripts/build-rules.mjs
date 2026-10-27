import { build } from 'esbuild';
import path from 'node:path';
// The native bridge uses the same pure rules with the browser-free translation runtime.
await build({entryPoints:['scripts/rules/entry.js'],bundle:true,format:'iife',globalName:'OpenGymRules',platform:'neutral',target:'es2020',minify:true,outfile:'OpenGym/Resources/web-rules.js',define:{'import.meta.env':'{}'},plugins:[{name:'native-i18n',setup(b){b.onResolve({filter:/\/i18n\.js$/},args=>({path:path.resolve(args.resolveDir,args.path.replace(/i18n\.js$/,'i18n-core.js'))}));}}]});

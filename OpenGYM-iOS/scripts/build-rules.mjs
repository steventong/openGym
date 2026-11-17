import { build } from 'esbuild';
import { fileURLToPath, pathToFileURL } from 'node:url';
// 规则源码全部在 scripts/rules 内（lib/ 为内置的纯规则，localization/ 为规则提示文案），不读取仓库外文件。
const root = fileURLToPath(new URL('../', import.meta.url));
export const buildRules = (write = true) => build({absWorkingDir:root,entryPoints:['scripts/rules/entry.js'],bundle:true,format:'iife',globalName:'OpenGymRules',platform:'neutral',target:'es2020',minify:true,write,outfile:'Resources/web-rules.js',define:{'import.meta.env':'{}'}});
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await buildRules();

import { build } from 'esbuild';
await build({
  entryPoints: ['examples/client/client.js'],
  bundle: true,
  outfile: 'tmp/demo/client.js',
  platform: 'browser',
  format: 'esm',
  sourcemap: true,
  define: { 'process.env.NODE_ENV': '"production"' },
});

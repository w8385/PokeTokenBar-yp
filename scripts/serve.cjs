const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');

// Serves the site like GitHub Pages: under /PokeTokenBar-yp/, folder index.html, 404.html for misses.
const root = path.resolve(__dirname, '..');
const prefix = '/PokeTokenBar-yp';
const types = {'.html':'text/html; charset=utf-8','.css':'text/css','.js':'text/javascript','.json':'application/json','.xml':'application/xml','.png':'image/png','.gif':'image/gif','.svg':'image/svg+xml','.ttf':'font/ttf','.txt':'text/plain; charset=utf-8','.md':'text/plain; charset=utf-8'};

function resolve(urlPath) {
  let p = decodeURIComponent(urlPath.split('?')[0]);
  if (p === prefix) return {redirect: prefix + '/'};
  if (p.startsWith(prefix + '/')) p = p.slice(prefix.length);
  const file = path.join(root, path.normalize(p));
  if (!file.startsWith(root)) return null;
  try {
    const stat = fs.statSync(file);
    if (stat.isDirectory()) {
      if (!p.endsWith('/')) return {redirect: urlPath.split('?')[0] + '/'};
      const index = path.join(file, 'index.html');
      return fs.existsSync(index) ? {file: index} : null;
    }
    return {file};
  } catch { return null; }
}

function createServer() {
  return http.createServer((req, res) => {
    const found = resolve(req.url);
    if (found?.redirect) {res.writeHead(301, {Location: found.redirect});return res.end();}
    const file = found?.file || path.join(root, '404.html');
    res.writeHead(found ? 200 : 404, {'Content-Type': types[path.extname(file)] || 'application/octet-stream'});
    fs.createReadStream(file).pipe(res);
  });
}

if (require.main === module) {
  const port = Number(process.env.PORT || 8765);
  createServer().listen(port, '127.0.0.1', () => console.log(`http://127.0.0.1:${port}${prefix}/`));
}

module.exports = {createServer, prefix};

// Every page of the site. `path` is the URL under the site root; `file` is the HTML on disk.
const origin = 'https://w8385.dev/PokeTokenBar-yp/';
const pages = [
  {id: 'home', path: '', file: 'index.html'},
  {id: 'usage', path: 'usage/', file: 'usage/index.html'},
  {id: 'growth', path: 'growth/', file: 'growth/index.html'},
  {id: 'collection', path: 'collection/', file: 'collection/index.html'},
  {id: 'battle', path: 'battle/', file: 'battle/index.html'},
  {id: 'items', path: 'items/', file: 'items/index.html'}
];
const notFound = {id: 'notfound', path: '404.html', file: '404.html'};

module.exports = {origin, pages, notFound, htmlFiles: [...pages, notFound].map(p => p.file)};

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const indexPath = path.join(root, 'index.html');
const assets = ['tokens.css', 'styles.css', 'app.js'];
const reference = new RegExp(`((?:href|src)=")(${assets.map(a => a.replace('.', '\\.')).join('|')})(?:\\?v=([^"]*))?"`, 'g');

function versionOf(asset) {
  return crypto.createHash('sha256').update(fs.readFileSync(path.join(root, asset))).digest('hex').slice(0, 8);
}

function stamp(html) {
  return html.replace(reference, (_, attr, asset) => `${attr}${asset}?v=${versionOf(asset)}"`);
}

function staleReferences(html) {
  const found = [...html.matchAll(reference)].map(([, , asset, version]) => ({asset, version, expected: versionOf(asset)}));
  const missing = assets.filter(asset => !found.some(f => f.asset === asset)).map(asset => ({asset, version: undefined, expected: 'linked'}));
  return [...found.filter(f => f.version !== f.expected), ...missing];
}

if (require.main === module) {
  fs.writeFileSync(indexPath, stamp(fs.readFileSync(indexPath, 'utf8')));
  console.log(assets.map(a => `${a}?v=${versionOf(a)}`).join(' '));
}

module.exports = {indexPath, staleReferences};

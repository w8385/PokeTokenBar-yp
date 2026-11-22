// Runs each scenario of scenarios.mjs in Pokémon Showdown and writes bot/tests/showdown/<name>.json: the scenario,
// the Pokémon's dex data the bot needs to build them, the move's events in order and the state it left.
// HP is recorded only as the sign of each change.
import {mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

import {SCENARIOS} from './scenarios.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const OUT = join(here, '..', '..', 'tests', 'showdown');
const SHOWDOWN = join(here, 'node_modules', 'pokemon-showdown');
const {Battle, Dex} = createRequire(import.meta.url)(join(SHOWDOWN, 'dist', 'sim'));
const COMMIT = JSON.parse(readFileSync(join(here, 'package.json'))).dependencies['pokemon-showdown'].split('/').pop();
const SEED = [1, 2, 3, 4];
const LEVEL = 50;
const DOLL_HP = {intact: 10000, fragile: 1};
const STATUS = {brn: 'burn', par: 'paralysis', psn: 'poison', tox: 'toxic', slp: 'sleep', frz: 'freeze'};
const STAT = {atk: 'attack', def: 'defense', spa: 'special_attack', spd: 'special_defense', spe: 'speed',
  accuracy: 'accuracy', evasion: 'evasion'};
const FORMS = {disguise: ['busted', 'Busted'], 'ice-face': ['noice', 'Noice']};
const VOLATILES = {substitute: 'substitute', leechseed: 'leech-seed'};

const id = slug => slug.replace(/-/g, '');
const slugOf = name => name.toLowerCase().replace(/['’.]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

function main() {
  rmSync(OUT, {recursive: true, force: true});
  mkdirSync(OUT, {recursive: true});
  for (const scenario of SCENARIOS) {
    const record = run(scenario);
    writeFileSync(join(OUT, `${scenario.name}.json`), compact(record) + '\n');
  }
  console.log(`${SCENARIOS.length} scenarios recorded with Showdown ${COMMIT} into ${OUT}`);
}

// JSON with every object or array that holds no other object or array on one line.
function compact(value, indent = '') {
  const flat = JSON.stringify(value);
  if (value === null || typeof value !== 'object' || !Object.values(value).some(v => v && typeof v === 'object')) {
    return flat.replace(/([:,])(?=["\d\[{tfn-])/g, '$1 ');
  }
  const inner = indent + '  ';
  const items = Array.isArray(value) ? value.map(v => inner + compact(v, inner))
    : Object.entries(value).map(([k, v]) => `${inner}${JSON.stringify(k)}: ${compact(v, inner)}`);
  const [open, close] = Array.isArray(value) ? ['[', ']'] : ['{', '}'];
  return `${open}\n${items.join(',\n')}\n${indent}${close}`;
}

function run(scenario) {
  const sides = [scenario.attacker, scenario.defender];
  const battle = new Battle({formatid: 'gen9customgame', seed: SEED});
  const chance = scenario.chance ?? true;
  battle.randomChance = (numerator, denominator) => numerator >= denominator || chance;
  // Secondary effects roll `random(100)` against their chance instead of calling randomChance.
  const random = battle.random.bind(battle);
  battle.random = (m, n) => (m === 100 && n === undefined ? (chance ? 0 : 99) : random(m, n));
  sides.forEach((spec, side) => battle.setPlayer(`p${side + 1}`, {name: `side${side}`, team: [set(spec, side)]}));
  battle.makeChoices('team 1', 'team 1');
  const mons = battle.sides.map(side => side.active[0]);
  setUp(battle, scenario, mons);
  const start = mons.map(mon => mon.hp);
  const from = battle.log.length;
  battle.actions.runMove(id(scenario.attacker.move), mons[0], 1);
  battle.clearActiveMove();
  battle.resolveFaints({checkWin: false});
  battle.eachEvent('Update');
  return {
    showdown: COMMIT,
    scenario,
    pokemon: sides.map(dexEntry),
    events: events(battle.log.slice(from), start),
    end: {
      sides: mons.map((mon, side) => state(mon, start[side], sides[side])),
      hazards: battle.sides.map(hazards),
      terrain: battle.field.terrain ? slugOf(battle.field.getTerrain().name) : null,
    },
  };
}

function set(spec, side) {
  return {
    name: `side${side}`, species: spec.species, item: spec.item ? id(spec.item) : '',
    ability: spec.ability ? id(spec.ability) : 'noability', moves: [spec.move ? id(spec.move) : 'splash'],
    level: LEVEL, gender: 'M', nature: 'Hardy',
    evs: {hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0},
    ivs: {hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31},
  };
}

function setUp(battle, scenario, mons) {
  [scenario.attacker, scenario.defender].forEach((spec, side) => {
    const mon = mons[side];
    mon.newlySwitched = false;
    if (spec.hp === 'half') mon.hp = Math.floor(mon.maxhp / 2);
    else if (typeof spec.hp === 'number') mon.hp = spec.hp;
    if (spec.substitute) {
      mon.addVolatile('substitute');
      mon.volatiles.substitute.hp = DOLL_HP[spec.substitute];
    }
    if (spec.seeded) mon.addVolatile('leechseed', mons[1 - side]);
  });
  (scenario.hazards ?? [{}, {}]).forEach((laid, side) => {
    for (const [hazard, layers] of Object.entries(laid)) {
      for (let layer = 0; layer < layers; layer++) battle.sides[side].addSideCondition(id(hazard), 'debug');
    }
  });
  if (scenario.terrain) battle.field.setTerrain(id(scenario.terrain), 'debug');
}

function dexEntry(spec) {
  const species = Dex.species.get(spec.species);
  const form = FORMS[spec.ability];
  const forms = form ? [{kind: form[0], ...dexStats(Dex.species.get(`${species.baseSpecies}-${form[1]}`))}] : [];
  return {name: species.name, ...dexStats(species), forms};
}

function dexStats(species) {
  const stats = species.baseStats;
  return {types: species.types.map(type => type.toLowerCase()), weight: Math.round(species.weightkg * 10),
    base: [stats.hp, stats.atk, stats.def, stats.spa, stats.spd, stats.spe]};
}

function state(mon, startHp, spec) {
  const boosts = Object.fromEntries(Object.entries(mon.boosts).filter(([, stages]) => stages).map(
    ([stat, stages]) => [STAT[stat], stages]));
  const form = FORMS[spec.ability];
  return {
    hp: Math.sign(mon.hp - startHp), fainted: mon.hp === 0, item: mon.item ? slugOf(mon.getItem().name) : null,
    status: STATUS[mon.status] ?? null, boosts,
    volatiles: Object.keys(mon.volatiles).filter(key => VOLATILES[key]).map(key => VOLATILES[key]).sort(),
    ability: mon.volatiles.gastroacid || mon.ability === 'noability' ? null : slugOf(mon.getAbility().name),
    types: mon.getTypes().map(type => type.toLowerCase()),
    form: form && mon.species.forme === form[1] ? form[0] : 'base',
  };
}

function hazards(side) {
  return Object.fromEntries(['stealthrock', 'spikes', 'toxicspikes', 'stickyweb']
    .filter(key => side.sideConditions[key])
    .map(key => [slugOf(Dex.conditions.get(key).name), side.sideConditions[key].layers ?? 1]));
}

// The protocol lines of the move as facts. A `|split|` line is followed by the exact line and the public one; only
// the exact one is kept.
function events(lines, start) {
  const facts = [];
  const hp = {...start};
  for (let index = 0; index < lines.length; index++) {
    if (lines[index].startsWith('|split|')) {
      lines.splice(index + 2, 1);
      continue;
    }
    const [, kind, who, ...rest] = lines[index].split('|');
    const side = who && /^p[12]/.test(who) ? Number(who[1]) - 1 : null;
    const from = rest.find(part => part.startsWith('[from]'))?.slice(7) ?? null;
    if (kind === '-damage' || kind === '-heal' || kind === '-sethp') {
      const now = Number(rest[0].split(/[/ ]/)[0]);
      if (now !== hp[side]) facts.push({side, kind: 'hp', sign: Math.sign(now - hp[side]), from});
      hp[side] = now;
    } else if (kind === '-enditem') {
      facts.push({side, kind: 'item', item: null, lost: slugOf(rest[0]), from});
    } else if (kind === '-item') {
      facts.push({side, kind: 'item', item: slugOf(rest[0]), from});
    } else if (kind === '-status') {
      facts.push({side, kind: 'status', status: STATUS[rest[0]], from});
    } else if (kind === '-curestatus') {
      facts.push({side, kind: 'status', status: null, from});
    } else if (kind === '-boost' || kind === '-unboost') {
      facts.push({side, kind: 'boost', stat: STAT[rest[0]], stages: Number(rest[1]) * (kind === '-boost' ? 1 : -1),
        from});
    } else if (kind === '-ability' || (kind === '-activate' && rest[0]?.startsWith('ability: '))) {
      facts.push({side, kind: 'ability', ability: slugOf(kind === '-ability' ? rest[0] : rest[0].slice(9))});
    } else if (kind === '-endability') {
      facts.push({side, kind: 'ability', ability: null});
    } else if (kind === '-start' || kind === '-end') {
      facts.push({side, kind: kind.slice(1), volatile: slugOf(rest[0].replace(/^move: /, ''))});
    } else if (kind === '-sidestart' || kind === '-sideend') {
      facts.push({side, kind: kind.slice(1), condition: slugOf(rest[0].replace(/^move: /, ''))});
    } else if (kind === '-fieldstart' || kind === '-fieldend') {
      facts.push({kind: kind.slice(1), condition: slugOf(who.replace(/^move: /, ''))});
    } else if (kind === '-immune' || kind === '-miss' || kind === '-fail' || kind === 'faint' || kind === '-crit') {
      facts.push({side, kind: kind.replace(/^-/, '')});
    } else if (kind === '-formechange' || kind === 'detailschange') {
      facts.push({side, kind: 'forme', species: rest[0].split(',')[0]});
    } else if (kind === '-typechange') {
      facts.push({side, kind: 'types', types: rest[0].toLowerCase().split('/')});
    }
  }
  return facts;
}

main();

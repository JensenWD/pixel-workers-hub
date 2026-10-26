// 16-bit desk scenes, one per session. Each layer is a 36×26 pixel grid. The desk, screens and bubbles are
// drawn once as SVG defs; the person is drawn per session from a look cast for it.
// Two-frame layers alternate in panel.css. Shared with panel.js as window.Sprites.
(() => {
'use strict'
const W = 36, H = 26
const colors = { W:'#b88657', w:'#9a6b43', v:'#74502f', m:'#3b3c38', M:'#5a5c55', q:'#1f2b24', Q:'#2b2e2a', R:'#41463f',
  g:'#8fd18f', y:'#e3c86e', b:'#8fb8e3', x:'#e0614a', G:'#6fcf7a', K:'#ddd6c6', k:'#b3ab99', n:'#3b2a20',
  C:'#7a7f76', c:'#5d625a', d:'#454840', u:'#f4efe4', U:'#cdc5b4', e:'#bdb5a5', f:'#fffaf0', a:'#b5452f', F:'#e2dac8', o:'#3a2c24' }

const blank = () => Array.from({ length:H }, () => Array(W).fill('.'))
const box = (g, x, y, w, h, c) => { for (let j = y; j < y + h; j++) for (let i = x; i < x + w; i++) g[j][i] = c; return g }
function art(g, x, y, rows) {
  rows.forEach((row, j) => [...row].forEach((c, i) => { if (c !== '.' && g[y + j]?.[x + i]) g[y + j][x + i] = c }))
  return g
}
// Sprites get a dark outline wherever they meet empty space, like a console character.
function outline(g) {
  const out = g.map(row => [...row])
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++)
    if (g[y][x] === '.' && [[1,0],[-1,0],[0,1],[0,-1]].some(([dx,dy]) => (g[y + dy]?.[x + dx] ?? '.') !== '.')) out[y][x] = 'o'
  return out
}
// One path per color.
function paths(g, palette = colors) {
  const runs = {}
  g.forEach((row, y) => { for (let x = 0; x < W;) { let n = 1; while (row[x + n] === row[x]) n++; if (row[x] !== '.') (runs[row[x]] ??= []).push(`M${x} ${y}h${n}v1h-${n}z`); x += n } })
  return Object.entries(runs).map(([c, d]) => `<path fill="${palette[c]}" d="${d.join('')}"/>`).join('')
}

// The screen's inside is 11×7 pixels centred on (28, 7); glyphs use odd sizes so they sit dead centre.
// Speech bubbles are 5×7 inside, with a 1px margin around their glyph and a tail toward the face.
const bubble = rows => outline(art(art(blank(), 15, 1, rows), 14, 8, ['.f', 'f']))
const layers = {
  base: () => {
    const g = blank()
    box(g, 0, 25, W, 1, 'F')
    box(g, 13, 15, 23, 1, 'W'); box(g, 13, 16, 23, 1, 'w'); box(g, 13, 17, 23, 1, 'v'); box(g, 17, 18, 2, 7, 'v'); box(g, 33, 18, 2, 7, 'v')
    box(g, 22, 3, 13, 10, 'm'); box(g, 22, 3, 13, 1, 'M'); box(g, 23, 4, 11, 7, 'q'); box(g, 27, 13, 3, 1, 'm'); box(g, 25, 14, 7, 1, 'M')
    box(g, 13, 14, 6, 1, 'K'); g[14][13] = 'k'
    box(g, 2, 11, 2, 9, 'c'); box(g, 2, 11, 1, 9, 'C'); box(g, 2, 20, 10, 1, 'C'); box(g, 2, 21, 10, 1, 'c')
    box(g, 6, 22, 2, 2, 'd'); box(g, 3, 24, 8, 1, 'd'); g[24][3] = g[24][10] = 'n'
    return g
  },
  code1: () => art(blank(), 24, 5, ['ggggg.yy', '', '.bbbbbb', '', 'yyy.gggg']),
  code2: () => art(blank(), 24, 5, ['.bbbbbb', '', 'yyy.gggg', '', 'ggggg.f']),
  check: () => art(blank(), 25, 5, ['.....GG', '....GG.', 'GG.GG..', '.GGG...', '..G....']),
  error: () => art(blank(), 26, 5, ['x...x', 'xx.xx', '.xxx.', 'xx.xx', 'x...x']),
  ask1: () => art(blank(), 24, 5, ['yyyyyy', '', '', '', 'g.ff']),
  ask2: () => art(blank(), 24, 5, ['yyyyyy', '', '', '', 'g']),
  dots1: () => art(blank(), 26, 7, ['..g']),
  dots2: () => art(blank(), 26, 7, ['g.g.g']),
  dim: () => art(blank(), 26, 7, ['MMMMM']),
  off: () => art(box(blank(), 23, 4, 11, 7, 'Q'), 28, 5, ['...RR', '..RR.', '.RR..']),
  alert: () => bubble(['fffff', 'ffaff', 'ffaff', 'ffaff', 'fffff', 'ffaff', 'fffff']),
  ask: () => bubble(['fffff', 'faaaf', 'fffaf', 'ffaaf', 'fffff', 'ffaff', 'fffff']),
  deskmug: () => outline(art(blank(), 20, 12, ['uuU', 'uuUU', 'uuU'])),
  steam1: () => art(blank(), 14, 4, ['e.', '.e', 'e.']),
  steam2: () => art(blank(), 14, 4, ['.e', 'e.', '.e']),
}
const spriteDefs = `<svg class="sprite-defs" aria-hidden="true" focusable="false"><defs>${Object.entries(layers).map(([id, draw]) => `<g id="px-${id}">${paths(draw())}</g>`).join('')}</defs></svg>`

// People. A look picks a hairstyle (the first four are men's, the rest women's), hair colour and clothes.
const face = ['..ssss...', '.ssssss..', 'ssssssss.', 'ssssssss.', 'sssSssis.', 'sssssssss', '.sssssss.', '...SSSS..']
const hairstyles = [
  { x:0, y:0, rows:['..hhhh...', '.hHHhhh..', 'hhhhhhhh.', 'hhhh', 'hhh', 'hhh', '.hh'] },
  { x:0, y:-1, rows:['...hhhh..', '..hHHhhh.', '.hhhhhhh.', 'hhhhhhh..', 'hhh', 'hhh', 'hh', '.h'] },
  { x:0, y:-1, rows:['.hhHhh...', 'hHhhHhhh.', 'hhhhhhhh.', 'hhHhhhhh.', 'hhhhh', 'hhh', 'hhh', '.hh'] },
  { x:0, y:3, rows:['hh', 'hh', 'hh', '.h'] },
  { x:0, y:0, rows:['..hhhh...', '.hHHhhh..', 'hhhhhhhh.', 'hhhhhh', 'hhhh', 'hhhh', 'hhhh', 'hhh', 'hhh', 'hhh', '.h'] },
  { x:-2, y:0, rows:['....hhhh', '...hHHhhh', '.thhhhhhhh', 'hhhhhh', 'hhhhh', 'hhhhh', 'hh.hh', 'hh', '.h'] },
  { x:0, y:0, rows:['..hhhh...', '.hHHhhh..', 'hhhhhhhh.', 'hhhhhhh', 'hhhh', 'hhhh', 'hhhhh', '.hhh'] },
  { x:-2, y:0, rows:['....hhhh', '...hHHhhh', '.hhhhhhhhh', 'hHhhhh', 'hhhhh', '.hhhh', '...hh'] },
]
// Everyone has the same emoji-yellow skin, so there is no blonde: it would blend into the face.
const skin = ['#f7c948', '#d9a72e']
const hairs = [['#2a2420','#453a33'], ['#4b3324','#6e4c34'], ['#9b968c','#c2bdb2'], ['#7a4a2a','#9a6640'], ['#9c4a2a','#c0663e']]
const shirts = ['#c2643f', '#4f7299', '#7a5f99', '#4d7a4f', '#c9952e', '#3f8a87', '#a8353a', '#d07a95', '#5b6470', '#7b7a3a']
const pants = [['#3d4b5e','#2f3a49'], ['#3a3a3c','#2b2b2d'], ['#9a8a62','#7d6f4d'], ['#5e4433','#4a3426'], ['#26262a','#1b1b1e']]
const skirts = ['#2f3a49', '#26262a', '#7a4a5a', '#5b6470', '#9a8a62']
const shoes = ['#3b2a20', '#26262a', '#e8e2d4', '#7a3b2a']
const tops = ['tee', 'hoodie', 'collar', 'stripes', 'jacket']

function random(seed) {
  let h = 2166136261
  for (const c of String(seed)) h = Math.imul(h ^ c.charCodeAt(0), 16777619)
  return n => { h = Math.imul(h ^ h >>> 15, 2246822507); h = Math.imul(h ^ h >>> 13, 3266489909); h ^= h >>> 16; return (h >>> 0) % n }
}
const unused = (i, n, used) => {
  if (used.size >= n) used.clear()
  for (let k = 0; k < n; k++) if (!used.has((i + k) % n)) return used.add((i + k) % n), (i + k) % n
}
// Each session keeps the same look across refreshes. Seeds are cast in order, so a later session never
// shares a hairstyle, shirt colour or outfit with an earlier one (or with a look already taken) until every
// option has been used once.
function cast(seeds, taken = []) {
  const styles = new Set(taken.map(l => l.style)), colours = new Set(taken.map(l => l.shirt)), outfits = new Set(taken.map(l => tops.indexOf(l.top)))
  return new Map(seeds.map(seed => {
    const r = random(seed), style = unused(r(hairstyles.length), hairstyles.length, styles), woman = style >= 4
    return [seed, { style, woman, shirt:unused(r(shirts.length), shirts.length, colours), hair:r(hairs.length),
      top:tops[unused(r(tops.length), tops.length, outfits)], pants:r(pants.length), shoes:r(shoes.length), glasses:!r(4),
      beard:!woman && r(3) === 0, skirt:woman && r(5) < 2 ? r(skirts.length) : null, tights:!r(2) }]
  }))
}

const shade = (hex, f) => '#' + [1,3,5].map(i => Math.round(parseInt(hex.slice(i, i + 2), 16) * f).toString(16).padStart(2, '0')).join('')
function palette(look) {
  const [s, S] = skin, [h, Hh] = hairs[look.hair], [p, P] = pants[look.pants], t = shirts[look.shirt], k = skirts[look.skirt ?? 0]
  const [L, J] = look.tights ? ['#3a3436', '#2a2527'] : [s, S]
  return { s, S, h, H:Hh, i:'#2d2b27', l:'#b5554f', b:'#cfe3ef', t, T:shade(t, .78), r:'#f4efe4', R:'#cdc5b4', p, P, k, K:shade(k, .78), L, J,
    n:shoes[look.shoes], o:'#3a2c24', u:'#f4efe4', U:'#cdc5b4' }
}
function head(g, look, y) {
  const hair = hairstyles[look.style]
  art(g, 4, y, face)
  art(g, 4 + hair.x, y + hair.y, hair.rows)
  if (look.beard) art(g, 7, y + 5, ['h', '.hhhhh', 'hhhh'])
  if (look.woman) g[y + 6][11] = 'l'
  if (look.glasses) art(g, 8, y + 4, ['ooo.b'])
}
function torso(g, look, y) {
  art(g, 5, y, ['.tttt.', 'Tttttt', 'Tttttt', 'Tttttt', 'Tttttt', 'Tttttt'])
  if (look.top === 'hoodie') { art(g, 4, y - 1, ['.TT', 'TTT']); art(g, 9, y + 1, ['r', 'r']); art(g, 7, y + 4, ['TTT']) }
  if (look.top === 'collar') art(g, 8, y, ['rr', '.r', '..', '.r'])
  if (look.top === 'stripes') { art(g, 5, y + 2, ['Rrrrrr']); art(g, 5, y + 4, ['Rrrrrr']) }
  if (look.top === 'jacket') art(g, 9, y, ['rr', '.r', '.r', '.r'])
}
function seated(look, arm) {
  const g = blank()
  torso(g, look, 12)
  if (look.skirt === null) { art(g, 5, 18, ['ppppppppp', 'PPPPPPPPp']); box(g, 12, 20, 1, 4, 'P'); box(g, 13, 20, 1, 4, 'p') }
  else { art(g, 5, 18, ['kkkkkkkL', 'KKKKKKKJ']); box(g, 12, 20, 1, 4, 'J'); box(g, 13, 20, 1, 4, 'L') }
  box(g, 12, 24, 4, 1, 'n')
  head(g, look, 4)
  return outline(arm(g))
}
function standing(look, arm) {
  const g = blank()
  torso(g, look, 10)
  if (look.skirt === null) { art(g, 5, 16, ['pppppp']); box(g, 6, 17, 2, 7, 'P'); box(g, 8, 17, 2, 7, 'p') }
  else { art(g, 5, 16, ['kkkkkk', 'kkkkkkk', 'KKKKKKK']); box(g, 6, 19, 2, 5, 'J'); box(g, 8, 19, 2, 5, 'L') }
  box(g, 6, 24, 5, 1, 'n')
  head(g, look, 2)
  return outline(arm(g))
}
const poses = {
  typing1: look => seated(look, g => art(g, 10, 13, ['ttssss'])),
  typing2: look => seated(look, g => art(g, 10, 12, ['....ss', 'ttss'])),
  idle: look => seated(look, g => art(g, 9, 13, ['.t', '.t', '.t', '.ss', '..ss'])),
  mug: look => seated(look, g => art(g, 10, 8, ['...uuU', '..suuU', '..suuU', '..s...', '..s...', 'tt....'])),
  stand: look => standing(look, g => art(g, 9, 11, ['.t', '.t', '.t', '.t', '.s', '.s'])),
  wave1: look => standing(look, g => art(g, 10, 3, ['...ss', '...ss', '...s', '...s', '...s', '...s', '..t', '.t', 't'])),
  wave2: look => standing(look, g => art(g, 10, 3, ['....ss', '....ss', '....s', '...s', '...s', '...s', '..t', '.t', 't'])),
}

// One scene per session status. A layer is static, or [frameA, frameB, speed] for a two-frame loop.
const scenes = {
  'working': ['base', ['code1','code2','fast'], ['typing1','typing2','fast']],
  'needs-input': ['base', ['ask1','ask2','slow'], ['wave1','wave2']],
  'failed': ['base', 'error', 'stand', 'alert'],
  'your-turn': ['base', 'check', 'mug', ['steam1','steam2','slow']],
  'ready': ['base', ['dots1','dots2','slow'], 'idle'],
  'unknown': ['base', 'dim', 'idle', 'ask'],
}
function agentScene(state, look = cast(['']).get('')) {
  const scene = scenes[state] || scenes.unknown
  const draw = (id, cls = '') => poses[id] ? `<g${cls}>${paths(poses[id](look), palette(look))}</g>` : `<use href="#px-${id}"${cls}/>`
  return `<svg class="agent-sprite" viewBox="0 0 ${W} ${H}" aria-hidden="true" focusable="false">${scene.map(layer => {
    if (!Array.isArray(layer)) return draw(layer)
    const speed = layer[2] ? ` px-${layer[2]}` : ''
    return draw(layer[0], ` class="px-a${speed}"`) + draw(layer[1], ` class="px-b${speed}"`)
  }).join('')}</svg>`
}

window.Sprites = { spriteDefs, cast, agentScene }
})()

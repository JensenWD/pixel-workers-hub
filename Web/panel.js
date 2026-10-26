'use strict'
// Script errors go to the app's log (Console.app, process PixelWorkersHub).
window.addEventListener('error', e => window.webkit?.messageHandlers?.app?.postMessage({ type:'error', message:`${e.message} (${e.filename?.split('/').pop()}:${e.lineno})` }))
// The menu-bar panel. The app hands it the session list (window.render) and it asks the app to do
// things through the "app" message handler: open a session's tab, fit the popover, show the options menu.
const { spriteDefs, cast, agentScene } = window.Sprites
const $ = id => document.getElementById(id)
const send = message => window.webkit?.messageHandlers?.app?.postMessage(message)
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' })[c])

const labels = { 'working':'Working', 'needs-input':'Needs you', 'your-turn':'Your turn', 'ready':'Ready', 'failed':'Failed', 'unknown':'Status unknown' }
const tallies = [['needs-input', 'need you', 'needs you'], ['failed', 'failed', 'failed'], ['working', 'working', 'working'], ['your-turn', 'your turn', 'your turn']]

// Everyone keeps their look while the app runs. A Claude Code process keeps its person through /clear, and
// someone joining never dresses like someone already at a desk.
const looks = new Map()
const lookKey = s => s.pid ? `pid:${s.pid}` : s.id
function lookFor(sessions) {
  const fresh = sessions.map(lookKey).filter(k => !looks.has(k))
  const taken = sessions.map(lookKey).filter(k => looks.has(k)).map(k => looks.get(k))
  for (const [k, look] of cast(fresh, taken)) looks.set(k, look)
  return s => looks.get(lookKey(s))
}

function ago(ms, now) {
  const minutes = Math.floor((now - ms) / 60000)
  if (minutes < 1) return 'just now'
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  return hours < 24 ? `${hours}h ago` : `${Math.floor(hours / 24)}d ago`
}

let shown = []
window.render = data => {
  document.documentElement.dataset.theme = data.theme || 'light'
  shown = data.sessions
  const look = lookFor(shown)
  const counts = tallies.map(([state, many, one]) => [shown.filter(s => s.status === state).length, many, one]).filter(([n]) => n)
  // Each count stays on one line when the tally wraps.
  $('tally').textContent = counts.map(([n, many, one]) => `${n} ${n === 1 ? one : many}`.replace(/ /g, '\u00a0')).join(' · ')
  const focused = document.activeElement?.dataset?.id
  $('list').innerHTML = shown.length ? shown.map(s => {
    const where = [s.project, s.terminal, s.since && ago(s.since, data.now)].filter(Boolean).join(' · ')
    return `<li><button class="row ${esc(s.status)}" type="button" data-id="${esc(s.id)}" title="Open in ${esc(s.terminal || 'its terminal')}">`
      + agentScene(s.status, look(s))
      + `<span class="copy"><span class="state ${esc(s.status)}"><span class="dot" aria-hidden="true"></span>${esc(labels[s.status] || labels.unknown)}</span>`
      + (s.name ? `<span class="title">${esc(s.name)}</span>` : '<span class="title untitled">Untitled session</span>')
      + `<span class="where">${esc(where)}</span></span></button></li>`
  }).join('') : `<li class="empty">No Claude Code sessions running.<small>${esc(data.error || 'Start claude in a terminal and it shows up here.')}</small></li>`
  if (focused) document.querySelector(`[data-id="${CSS.escape(focused)}"]`)?.focus()
  $('hooks').innerHTML = data.hooks === 'on' ? 'Detailed status on'
    : '<button class="link" type="button" data-action="hooks" title="Adds hooks to Claude Code’s settings so the panel can tell finished, needs-permission and failed apart">Turn on detailed status</button>'
  if (data.notice !== undefined) say(data.notice)
  fit()
}

function say(message, automation) {
  $('status').innerHTML = esc(message) + (automation ? ' <button class="link" type="button" data-action="automation">Open Settings</button>' : '')
  fit()
}
window.say = say

// The popover fits the page; the app keeps it within the screen.
let fitted = 0
function fit() {
  const height = Math.ceil(document.body.getBoundingClientRect().height)
  if (height !== fitted) { fitted = height; send({ type:'resize', height }) }
}

document.addEventListener('click', event => {
  const row = event.target.closest('[data-id]'), action = event.target.closest('[data-action]')?.dataset.action
  if (row) { say('Opening…'); send({ type:'focus', id:row.dataset.id }) }
  else if (action === 'hooks') send({ type:'hooks' })
  else if (action === 'automation') send({ type:'automation' })
  else if (event.target.closest('#options')) {
    const box = $('options').getBoundingClientRect()
    send({ type:'menu', x:box.left, y:box.bottom })
  }
})

document.addEventListener('keydown', event => {
  if (event.key === 'Escape') return send({ type:'close' })
  if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return
  const rows = [...document.querySelectorAll('.row')]
  if (!rows.length) return
  const at = rows.indexOf(document.activeElement)
  rows[event.key === 'ArrowDown' ? (at + 1) % rows.length : (at <= 0 ? rows.length - 1 : at - 1)].focus()
  event.preventDefault()
})

// Called by the app each time the popover opens.
window.opened = () => { say(''); document.querySelector('.row')?.focus() }

$('defs').innerHTML = spriteDefs
send({ type:'ready' })

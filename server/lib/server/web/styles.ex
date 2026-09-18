defmodule Server.Web.Styles do
  @moduledoc """
  The page's own CSS, over the palette's variables only — the TUI look the whole machine wears:
  monospace, black ground, a 1px structure border with its label inset, amber body, the cursor
  field for where you are, violet for what you picked (the palette law, 2026-09-10).
  """

  @css """
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--ground); color: var(--body); font: 15px/1.45 var(--font); }
  a { color: var(--key); text-decoration: none; }
  .frame { display: grid; grid-template-columns: 22rem 1fr; min-height: 100vh; }
  .rail { border-right: 1px solid var(--structure); padding: 1rem; background: var(--panel); }
  .main { padding: 1rem 1.5rem; max-width: 72rem; }
  .panel { border: 1px solid var(--structure); padding: .75rem 1rem 1rem; margin: 0 0 1rem; position: relative; }
  .panel > .label { position: absolute; top: -.7em; left: .75rem; background: var(--ground); padding: 0 .4em; color: var(--key); font-weight: bold; font-size: .85em; letter-spacing: .05em; }
  .ws { color: var(--key); font-weight: bold; margin: .5rem 0 .25rem; }
  .thread { display: block; padding: .15rem .4rem; color: var(--body); }
  .thread.root { font-weight: bold; }
  .thread.working { color: var(--live); }
  .thread.current { background: var(--cursor-field); color: var(--field-ink); }
  .thread .lead { color: var(--meta); }
  .thread .stage { color: var(--assistant); }
  .flag { background: var(--attention); color: var(--field-ink); padding: 0 .3em; font-weight: bold; }
  .crew { color: var(--attention); margin-top: .25rem; font-size: .9em; }
  h1 { font-size: 1.3em; margin: 0 0 .25rem; }
  .meta { color: var(--meta); }
  .msg { margin: .6rem 0; }
  .msg .who { font-weight: bold; }
  .msg .who.operator { color: var(--user-voice); }
  .msg .who.agent { color: var(--assistant-voice); }
  .msg .when { color: var(--inactive); font-size: .85em; margin-left: .5em; }
  .msg .body { white-space: pre-wrap; }
  .list { margin: 0; padding-left: 1.2em; }
  .ok { color: var(--live); } .bad { color: var(--alarm); } .warn { color: var(--warn); }
  form.compose { display: flex; gap: .5rem; margin-top: 1rem; }
  form.compose textarea { flex: 1; background: var(--card); color: var(--body); border: 1px solid var(--structure); font: inherit; padding: .5rem; min-height: 4.5em; }
  form.compose button { background: var(--cursor-field); color: var(--field-ink); border: 0; font: inherit; font-weight: bold; padding: 0 1rem; cursor: pointer; }
  ::selection { background: var(--sel-field); color: var(--sel-ink); }
  code { color: var(--key); }
  .nav { display: flex; gap: .75rem; margin-bottom: .75rem; padding-bottom: .5rem; border-bottom: 1px solid var(--structure); }
  .nav a.current { background: var(--cursor-field); color: var(--field-ink); padding: 0 .3em; }
  .row { padding: .15rem 0; }
  .row button, main > button { background: var(--card); color: var(--key); border: 1px solid var(--structure); font: inherit; padding: 0 .5rem; cursor: pointer; margin-left: .5rem; }
  .columns { display: grid; grid-template-columns: repeat(4, 1fr); gap: 1rem; }
  .prio { font-size: .8em; color: var(--meta); } .prio.high { color: var(--alarm); }
  """

  def css, do: @css
end

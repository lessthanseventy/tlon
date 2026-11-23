# Shipping Asterion to another computer

Asterion (the house) is built on this Linux machine for Windows and macOS. The art is Gridwright's bought packs: the
licence allows shipping it **inside a finished app** and forbids redistributing it as assets, and this repo is
public. So the builds and the art pack are written only to `~/.cache/tlon/house-dist/` (the task refuses to
write inside a git work tree) and are handed over **privately** (a message, a USB stick, a private share), never a
public link, never committed. The window keeps showing "Art by Gridwright".

## Build

    mise run house:art-pack                 # house-art.zip: only the files the house can open (-- --list to see them)
    mise run house:build -- windows         # or mac, linux, all (builds the art pack first)

Needs Godot's official export templates for the exact version (`godot --version`, now 4.7.2.stable) in
`~/.local/share/godot/export_templates/4.7.2.stable/`: `windows_release_x86_64.exe`, `macos.zip`,
`linux_release.x86_64`. The art is read from `TLON_ART_DIR` (default `~/projects/thatch/packs/x`).

Output, in `~/.cache/tlon/house-dist/`:

- `asterion-windows.zip`: one file, `asterion.exe`, the code and the art together (the art is raw files in
  the executable's embedded pck, so the file is large).
- `asterion-mac.zip`: `Asterion.app` (universal, Intel and Apple silicon), the art in its pck like the others,
  ad-hoc signed by the export (nothing is added to the app after it, which would break the seal).
- `asterion-linux.zip`: one file, `asterion`, the same as Windows, for a Linux machine.

The build stages a throwaway copy of `house/` under the dist dir, puts the pack's files in its `art/` with a
`keep` import each (so Godot neither imports them as textures nor drops them from the pck), and exports that.
`TLON_HOUSE_DIST` moves the dist dir (still outside any git work tree).

The house looks for its art in this order: `--art <folder or pack>`, the art inside the program, a
`house-art.zip` beside the program (also how a build made without art can be given
some), the `TLON_ART_DIR` folder, none (flat shapes, and it says so).

## What to hand over

The one zip for that computer. Nothing else: the list lives on that computer.

On its own list the house asks wttr.in for the weather by internet address about every half hour and sends
nothing else; "weather" in its settings names a town or switches it off.

## First run

Neither build is signed by a developer account: Windows and macOS warn about any program they do not know, and this build cannot be
notarized from Linux (that takes an Apple developer account and a Mac).

**Windows.** Unzip it anywhere it can stay (not the Downloads' temporary view of the zip: use "Extract
all"). Double-click `asterion.exe`. SmartScreen says "Windows protected your PC": click **More info**, then
**Run anyway**. If the zip came by browser download, right-click the zip first, Properties, tick Unblock, and the
warning does not come.

**macOS.** Unzip with Finder (double-click the zip), not a third-party tool, and drag `Asterion.app` to
Applications. The first time, right-click it, choose **Open**, then **Open** in the dialog (a double-click only
offers Cancel). If macOS says the app "is damaged", run these two lines once in Terminal (use the path it is
really at), then right-click, **Open** again:

    xattr -cr "/Applications/Asterion.app"
    codesign --force --deep --sign - "/Applications/Asterion.app"

Why: the app is ad-hoc signed here, not by an Apple developer account, and not notarized; the second line signs
it again on the Mac itself.

## Where it keeps its files

Godot's user data folder, named after the project, `Asterion`:

| OS | Folder |
| --- | --- |
| Windows | `%APPDATA%\Godot\app_userdata\Asterion\` (that is `C:\Users\<name>\AppData\Roaming\...`) |
| macOS | `~/Library/Application Support/Godot/app_userdata/Asterion/` |
| Linux | `~/.local/share/godot/app_userdata/Asterion/` |

There: `house_list.json` (the list, with `house_list.bak.json` beside it), `house_settings.json`,
`house_person.json` (who they are), `house_layout.json` (the room), `house_sound.json`, `house_found.json` and
the smaller ones. A list saved by the house is only ever replaced whole, and a copy is kept.

## Update

Replace the program: delete the old `asterion.exe` / `asterion` (Windows, Linux) or `Asterion.app` (Mac)
and unzip the new one. The list and settings are in the folder above, not in the app, so they stay.

## Move a list to a new computer

Quit the house on both. Copy the whole `Asterion` folder above (or just `house_list.json`, plus
`house_layout.json` and `house_person.json` for the room and who lives in it) from the old computer's user data
folder into the same place on the new one, then start it.

## From "the house"

The program was called "the house", so its folder was `the house` beside `Asterion`. The first start of
Asterion copies every file in it (the list, the Telegram pairing, the settings) into `Asterion` once, leaves
the old folder as it was, and never overwrites a file already there (`adopt.gd`).

## First run on a bare machine

With no tlon server, no `claude` program, no Telegram and no calendar, the first start finds no server and keeps
its own list with a few starter things; add, done, later and a ringing reminder, the weather (wttr.in, or off
in Settings, Connections) and the Telegram pairing code all work from there. Checked live on the Linux build
(a throwaway data folder, no server); the Windows and macOS builds are unverified until someone runs them.

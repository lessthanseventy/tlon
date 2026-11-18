# Shipping the house to another computer

The house is built on this Linux machine for Windows and macOS. The art is Gridwright's bought packs: the
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

- `the-house-windows.zip`: one file, `the-house.exe`, the code and the art together (the art is raw files in
  the executable's embedded pck, so the file is large).
- `the-house-mac.zip`: `the house.app` (universal, Intel and Apple silicon), with `house-art.zip` in
  `Contents/Resources`.
- `the-house-linux.zip`: one file, `the-house`, the same as Windows, for a Linux machine.

The build stages a throwaway copy of `house/` under the dist dir, puts the pack's files in its `art/` with a
`keep` import each (so Godot neither imports them as textures nor drops them from the pck), and exports that.
`TLON_HOUSE_DIST` moves the dist dir (still outside any git work tree).

The house looks for its art in this order: `--art <folder or pack>`, the art inside the program, a
`house-art.zip` beside the program (a Mac app: in Resources; also how a build made without art can be given
some), the `TLON_ART_DIR` folder, none (flat shapes, and it says so).

## What to hand over

The one zip for that computer. Nothing else: the list lives on that computer.

## First run

Neither build is signed: Windows and macOS warn about any program they do not know, and this build cannot be
notarized from Linux (that takes an Apple developer account and a Mac).

**Windows.** Unzip it anywhere it can stay (not the Downloads' temporary view of the zip: use "Extract
all"). Double-click `the-house.exe`. SmartScreen says "Windows protected your PC": click **More info**, then
**Run anyway**. If the zip came by browser download, right-click the zip first, Properties, tick Unblock, and the
warning does not come.

**macOS.** Unzip, drag `the house.app` to Applications (or leave it). Right-click it, choose **Open**, then
**Open** in the dialog (a double-click only offers Cancel the first time). If macOS says the app "is damaged" or
will not open at all, run this once in Terminal, then open it again:

    xattr -dr com.apple.quarantine "/Applications/the house.app"

(use the path it is really at). It is the same program, the quarantine mark a download carries is what is removed.

## Where it keeps its files

Godot's user data folder, named after the project, `the house`:

| OS | Folder |
| --- | --- |
| Windows | `%APPDATA%\Godot\app_userdata\the house\` (that is `C:\Users\<name>\AppData\Roaming\...`) |
| macOS | `~/Library/Application Support/Godot/app_userdata/the house/` |
| Linux | `~/.local/share/godot/app_userdata/the house/` |

There: `house_list.json` (the list, with `house_list.bak.json` beside it), `house_settings.json`,
`house_person.json` (who they are), `house_layout.json` (the room), `house_sound.json`, `house_found.json` and
the smaller ones. A list saved by the house is only ever replaced whole, and a copy is kept.

## Update

Replace the program: delete the old `the-house.exe` / `the-house` (Windows, Linux) or `the house.app` (Mac)
and unzip the new one. The list and settings are in the folder above, not in the app, so they stay.

## Move a list to a new computer

Quit the house on both. Copy the whole `the house` folder above (or just `house_list.json`, plus
`house_layout.json` and `house_person.json` for the room and who lives in it) from the old computer's user data
folder into the same place on the new one, then start it.

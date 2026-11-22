# Baran

Run Windows games on Linux. Double-click and go.

Baran keeps a list of your games, gives each one a desktop entry, and starts it
through whichever runtime fits. Proton, prefixes and runtimes are detected
automatically — there is nothing to configure before the first launch.

```sh
curl -fsSL https://raw.githubusercontent.com/keravyn-ops/baran/main/install.sh | bash
baran gui
```

## Three runtimes, one launcher

| Runtime | What it does | When to use it |
|---|---|---|
| `proton` | Plain Proton or umu-run | The normal case |
| `legion` | Runs the game inside a KVM virtual machine ([Legion](https://github.com/brcly/legion-kvm)) | Titles that dislike running directly on the host. **KVM stays available** — nothing is taken away from you |
| `linuwux` | [LinUwUx](https://github.com/brcly/linuwux-runtime) preload plus CPUID fault emulation | Titles whose anti-tamper code needs CPUID faulting, e.g. Phantom Blade Zero |

`auto` (the default) picks `legion` when a Legion binary and `/dev/kvm` are
available, otherwise `proton`. Set it per game:

```sh
baran run my-game --runtime linuxux   # once
baran add game.exe --runtime legion   # permanently
```

In the GUI the **Runtime** button cycles through the modes for the selected game,
**Edit** opens name, arguments, prefix, Proton and environment variables, and
**Setup** installs or builds the optional pieces without touching a terminal
yourself.

## Quick start

```sh
baran setup               # guided, step by step, each one verified
baran gui                 # window with your game list
baran add "/path/Game.exe"
baran scan --add          # or let it find games on your disk
baran run my-game
baran doctor              # what works, what is missing
```

Every game gets its own Wine prefix under `~/.local/share/baran/prefixes/<id>`,
so games cannot break each other.

## Installation

```sh
curl -fsSL https://raw.githubusercontent.com/keravyn-ops/baran/main/install.sh | bash
```

or manually:

```sh
git clone https://github.com/keravyn-ops/baran.git
install -m 755 baran/baran ~/.local/bin/baran
```

Needs Python 3.9+. The GUI uses GTK4 if present and falls back to zenity.
Nothing else is required for the `proton` runtime.

## Setting up the extra runtimes

Only needed if you want them. `baran setup --runtime linuwux` (or `legion`)
walks you through it and refuses to go on while something is missing; the
**Setup** button in the GUI does the same with a progress list.

### legion — keep KVM, run the game in a VM

Legion has no prebuilt binaries, so it must be built once. Needs rootless
Podman or Docker, about 25 GiB of disk and a few hours:

```sh
baran install-deps --legion   # podman
baran build-legion
```

Requirements afterwards: `/dev/kvm` (group `kvm`), a Wayland session and a host
Vulkan driver. Baran sizes the VM from your host RAM; override with
`baran settings legion_memory_mib 8192`.

### linuwux — CPUID faulting for anti-tamper titles

```sh
baran install-deps          # git, base-devel, Rust, DKMS, kernel headers
baran umip                  # UMIP must be off: add clearcpuid=514, reboot
baran build-linuwux         # builds LinUwUx
baran build-module --dkms   # only on AMD before Zen 4
```

`baran doctor` tells you which of these your CPU actually needs. Intel from 9th
gen and AMD Zen 4 onwards have native CPUID faulting and need no kernel module.

> **Warning:** the CPUID emulation module is an experimental out-of-tree module
> that claims AMD SVM for itself. While it is loaded, **KVM is unavailable**, and
> it taints the kernel. Baran unloads KVM before loading it and restores KVM
> afterwards. With `--dkms` it also survives kernel updates.

## Hypervisor / ARTIFACT builds

Some builds ship their own loader next to the executable: `artifact.dll`,
`coldloader.dll`, a `steam_settings/` folder, `Artifact_AMD` / `Artifact_Intel`.
Baran recognises those when you add the game, selects the `linuwux` runtime and
takes `STEAM_APPID` from the build. The notes below cost a long evening to find.

### Proton must be called the way Steam calls it

ProtonFixes only runs when Proton is invoked with the `waitforexitandrun` verb:

```python
def check_conditions() -> bool:
    return (... and 'waitforexitandrun' in sys.argv[1])
```

Starting a game with plain `proton run` silently skips every game specific fix
**and the whole FSR4 / upscaler setup**. Baran always uses `waitforexitandrun`.

### Do not start these games from Steam as well

Steam launches a shortcut with its own compatibility tool. That rewrites
`compatdata/<id>/version` and `config_info`, so the prefix now belongs to a
different Proton: the shader cache is thrown away, and on the next Baran start
the Proton recorded in the prefix is used instead of the one you configured.
Either launch only through Baran, or force the same build in Steam under
**Properties → Compatibility**.

### Frame generation mods break on older CPUs

OptiScaler with `MFGUnlocker.asi` and RTX frame generation mods inject
`dxgi.dll`, `winmm.dll`, `d3d12.dll` and `dbghelp.dll` into the prefix. On a
Zen 2 CPU this produced a hundred `0xC000001D` (illegal instruction) faults per
session and the mod terminated the game after a few seconds:

```
Session end: process exit (ExitProcess) after 7.9 s
  exit stack: #00 MFGUnlocker.asi+0xE7F3A ... #08 PBZ.exe
  0xC000001D (illegal instruction) at PBZ.exe+0x19BC53A0
```

A half installed OptiScaler is worse than none: ProtonFixes reported
`Failed to validate optiscaler files` and still logged `OptiScaler enabled`.
If a game dies seconds after the Vulkan device comes up, remove
`<prefix>/drive_c/windows/system32/umu/` and the injected DLLs.

Plain FSR4 does not need OptiScaler. `amdxcffx64.dll` is copied into the prefix
by ProtonFixes and upgrades FSR 3.1 titles on RDNA2 and newer.

### Removing injected DLLs: restore the real ones

`winmm.dll` and `dbghelp.dll` are genuine Windows libraries. Delete the
OptiScaler copies and Proton does **not** put them back; the game then starts,
never renders and exits after about 100 seconds. Restore them from Proton's
template and dereference the symlink, otherwise you install a dangling link:

```sh
P=.../compatibilitytools.d/<proton>/files/share/default_pfx/drive_c/windows/system32
cp -L "$P/winmm.dll"   "<prefix>/drive_c/windows/system32/winmm.dll"
cp -L "$P/dbghelp.dll" "<prefix>/drive_c/windows/system32/dbghelp.dll"
```

### gamescope is not automatically a win

A custom Proton may ask for it (`BC250_PACE off (not under gamescope)`), but on
the tested PS5 hardware wrapping the game in gamescope killed it after roughly
20 seconds, while the same build ran for minutes without it. Measure both with
`baran set <game> wrapper "gamescope -f -- "` before believing either.

### Measuring instead of guessing

MangoHud averages lie: a run that never leaves the menu still reports 60 FPS at
0 % GPU load. Check GPU load and VRAM alongside the frame rate, and judge
smoothness by the frametime maximum, not the average.

On the reference PS5 (2 GB VRAM carve-out, 12.9 GB RAM) the measured path was
47 FPS with a saturated VRAM pool and active swap, and 78 FPS once the frame
generation mods were gone and the system had been rebooted.

## Commands

| Command | Description |
|---|---|
| `gui` | Graphical interface (GTK4, zenity fallback) |
| `add <exe>` | Add a game, extract its icon, create a desktop entry |
| `list` | List games and their runtime |
| `run <id>` | Start a game (`--runtime`, `--print`, `--detach`, `--keep`) |
| `remove <id>` | Remove a game (`--purge` also deletes its prefix) |
| `scan` | Search the disk for games (`--add`) |
| `shortcut [id]` | (Re)create desktop entries |
| `setup` | Guided setup; a step unlocks only once the one before it passes |
| `doctor` | Check the environment |
| `install-deps` | Install build dependencies (Arch/CachyOS) |
| `umip` | How to disable UMIP on your bootloader |
| `prepare` / `unprepare` | Load / unload the CPUID module by hand |
| `build-linuwux` | Build and install LinUwUx (`--ref pr58`) |
| `build-module` | Build the CPUID module (`--dkms`) |
| `build-legion` | Build Legion-KVM |
| `install-proton` | Install Proton-CachyOS |
| `settings` | Show or change settings |

## Proton and prefixes

Baran reads `config_info` and `version` inside a prefix to find out which Proton
it belongs to, and uses exactly that one. Silently switching builds would make
Proton upgrade the prefix and throw away the shader cache.

Order of choice:

1. The game's own `proton` entry
2. `default_proton` from the settings
3. **The Proton recorded in the prefix**
4. Preference: Proton-CachyOS → GE-Proton → UMU → Experimental

If your choice differs from the prefix, `doctor` says so before you lose a cache.

## Troubleshooting

**No window when launching over SSH** — pass the session environment:

```sh
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 \
       DISPLAY=:0 XAUTHORITY=/run/user/1000/xauth_XXXXXX
```

**First start takes minutes at full CPU** — shader compilation, especially after
a Proton change. Let it finish.

**`wrong ELF class: ELFCLASS64`** — harmless. 32-bit helper processes cannot load
the 64-bit LinUwUx library; the game itself does.

**KVM gone after a crash** — `baran unprepare`.

**Module built for another kernel** — `baran build-module`, or use `--dkms` once
so DKMS rebuilds it automatically.

## Files

```
~/.config/baran/games.json        your games
~/.config/baran/settings.json     settings
~/.local/share/baran/prefixes/    one Wine prefix per game
~/.local/share/baran/legion       built Legion binary
~/.local/state/baran/logs/        launch logs (latest.log)
~/.local/share/applications/      desktop entries
```

## Tested

CachyOS and Arch Linux, kernel 7.3, GTK4 and zenity front ends, Proton-CachyOS,
GE-Proton and UMU-Proton. The `linuwux` runtime is verified on a PlayStation 5
running Arch (AMD Zen 2 "Oberon", KDE on Wayland) with LinUwUx PR #58 and
`clearcpuid=umip`, reaching gameplay in Phantom Blade Zero.

## Credits

Baran is only the launcher. The heavy lifting belongs to
[Proton](https://github.com/ValveSoftware/Proton),
[Proton-CachyOS](https://github.com/CachyOS/proton-cachyos),
[umu](https://github.com/Open-Wine-Components/umu-launcher),
[Legion-KVM](https://github.com/brcly/legion-kvm),
[LinUwUx](https://github.com/brcly/linuwux-runtime) and
[cpuid-fault-emulation](https://github.com/dnmodder/cpuid-fault-emulation).

Baran does not ship, obtain or modify game files.

## License

MIT

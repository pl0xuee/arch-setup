-- Personal Hyprland rules, installed by arch-setup.
--
-- Loaded from the bottom of ~/.config/hypr/hyprland.lua with a single dofile
-- line, rather than pasted into that file: hyprland.lua is yours to edit, and a
-- setup script that appends thirty lines to it every run — or worse, rewrites
-- it — is a script that eats your own changes. One line in, everything else
-- lives here where the next run can replace it wholesale.
--
-- This file is dofile'd, so it sees the same globals as hyprland.lua: `hl`,
-- `o` and `require`.

-- Steam tiles like a normal app.
-- Omarchy's default (default/hypr/apps/steam.lua) floats every window whose
-- class matches "steam". These rules load afterwards, so they win for the
-- windows they match, while dialogs and notification toasts keep floating.
o.window({ class = "^steam$", title = "^Steam$" }, { tile = true })
o.window({ class = "^steam$", title = "^Steam Big Picture Mode$" }, { tile = true })

-- StreamHub is a video player, so keep it fully opaque.
-- Omarchy tags every window "default-opacity" (0.985 active / 0.96 inactive) in
-- default/hypr/windows.lua. Drop the tag and pin opacity, the same way the
-- defaults opt out Steam, QEMU and DaVinci Resolve.
o.window("^streamhub", { tag = "-default-opacity", opacity = "1 1" })

-- Every X11 client draws at 1x, not Omarchy's 2x.
--
-- Omarchy's hypr/monitors.lua sets GDK_SCALE=2 (its omarchy_gdk_scale), which
-- suits the HiDPI laptop that default is written for. This line runs after it —
-- hyprland.lua requires hypr.monitors before it dofiles this file, and the last
-- hl.env for a name is the one that sticks — so Omarchy's own file can stay
-- stock and survive an omarchy refresh.
--
-- GDK_SCALE only ever reaches XWayland clients. Omarchy sets
-- xwayland:force_zero_scaling (default/hypr/envs.lua), so X clients are handed
-- physical pixels with no compositor scaling and have to scale themselves;
-- GDK_SCALE is the number this session hands them. Wayland-native GTK apps
-- ignore it — Nautilus renders pixel-identically at 1 and at 2.
--
-- At 2, every X11 client drew at twice the size it asked for. The Tauri
-- AppImages this repo installs — ConsoleVault, GridDown, Music AI Player — were
-- the visible casualties: linuxdeploy's GTK hook exports GDK_BACKEND=x11 inside
-- their AppRun, a workaround for a Wayland crash (tauri#8541), so they cannot
-- take the Wayland path that saves everything else. The Avalonia installers
-- (LoreRim, WotLK, GAMMA) never read GDK_SCALE and were already at 1, and Disc
-- Ripper is Qt on Wayland, which follows each monitor by itself.
--
-- 1 is exact on a monitor at scale 1 and about 20% small on one at 1.25. GTK on
-- X11 takes whole numbers only, so 1.25 is not on the menu and the alternative,
-- 2, was 60% too large there. Apps that want a different number pin it in their
-- own launcher — ~/.local/bin/streamhub sets 1.25, ~/.local/bin/steam sets 1 —
-- and those win over this.
hl.env("GDK_SCALE", "1")

-- Keep ~/.local/bin ahead of /usr/bin in the session PATH.
--
-- uwsm starts Hyprland without sourcing ~/.bashrc, so the graphical session
-- inherits a PATH where /usr/bin comes before ~/.local/bin -- the reverse of an
-- interactive shell. A bare "steam" resolves to /usr/bin/steam there, skipping
-- the ~/.local/bin/steam wrapper that pins the UI scale. Steam relaunches
-- itself by name after a client update or a "restart Steam", so every
-- self-restart dropped the wrapper and the UI changed size.
--
-- Omarchy's default/hypr/envs.lua builds PATH the same way, from the PATH
-- Hyprland was started with, which does not carry its own bin dir. Re-add it
-- here so this rebuild keeps Omarchy's commands first.
local user_paths = require("default.hypr.paths")
local path_head = { user_paths.omarchy_path .. "/bin", user_paths.home .. "/.local/bin" }

local path_entries = {}
for entry in (os.getenv("PATH") or "/usr/local/bin:/usr/bin"):gmatch("[^:]+") do
  local heads = false
  for _, dir in ipairs(path_head) do
    if entry == dir then heads = true end
  end
  if not heads then table.insert(path_entries, entry) end
end
for i = #path_head, 1, -1 do
  table.insert(path_entries, 1, path_head[i])
end
hl.env("PATH", table.concat(path_entries, ":"))

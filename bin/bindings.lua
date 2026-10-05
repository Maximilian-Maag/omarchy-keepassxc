-- Hyprland keybindings added by omarchy-keepassxc
-- Replaces the default 1Password binding with KeePassXC.
-- Sourced from hyprland.lua by install.sh.

-- Unbind 1Password binding
hl.unbind("SUPER + SHIFT + SLASH")

-- KeePassXC: launch or focus
o.bind("SUPER + SHIFT + SLASH", "Passwords", { launch = "keepassxc", focus = "^keepassxc$" })

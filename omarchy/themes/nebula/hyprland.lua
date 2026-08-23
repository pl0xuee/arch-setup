-- Nebula: cyan-glow -> dust-coral gradient borders, rounded corners.

local active_border_color = {
  colors = { "rgba(4fc3c7ee)", "rgba(9fd8c0ee)", "rgba(f0895aee)" },
  angle = 45,
}
local inactive_border_color = "rgb(14232f)"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },
  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },
  decoration = {
    rounding = 14,
    rounding_power = 2.4,

    shadow = {
      enabled = true,
      range = 22,
      render_power = 3,
      color = "rgba(030a12cc)",
      color_inactive = "rgba(030a1288)",
      offset = { 0, 4 },
    },
  },
})

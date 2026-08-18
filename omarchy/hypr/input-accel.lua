-- Turn off mouse acceleration. libinput's default profile is "adaptive", which
-- scales pointer movement by how fast you move the mouse; "flat" applies a
-- constant 1:1 factor, so physical distance always maps to the same cursor
-- distance. This is the libinput-supported way to do it — input.force_no_accel
-- bypasses libinput entirely and would also discard the sensitivity setting.
hl.config({
  input = {
    accel_profile = "flat",
  },
})

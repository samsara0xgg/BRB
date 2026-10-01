# dmgbuild settings for BRB.dmg (scripts/release.sh passes app and background with -D).
# The icon centres match DiskImage.app and DiskImage.applications in DiskImage.swift.
import os.path

app = defines["app"]  # noqa: F821, dmgbuild provides `defines`
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [os.path.basename(app)]
background = defines["background"]  # noqa: F821
window_rect = ((200, 140), (640, 428))  # 400 of content under the title bar
icon_size = 112
text_size = 13
icon_locations = {os.path.basename(app): (170, 200), "Applications": (470, 200)}
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
format = "UDZO"

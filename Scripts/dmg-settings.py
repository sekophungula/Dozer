# dmgbuild settings for Dozex.dmg. Called from Scripts/build.sh:
#   dmgbuild -s Scripts/dmg-settings.py -D app=build/Dozex.app -D background=build/background.tiff "Dozex" build/Dozex.dmg
# Icon positions must match the plates drawn by Scripts/make-dmg-background.swift.
import os.path

app = defines["app"]  # noqa: F821 (injected by dmgbuild)
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extension = [app_name]

background = defines["background"]  # noqa: F821
window_rect = ((200, 120), (660, 428))  # 400pt background + ~28pt title bar
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 96
text_size = 13
icon_locations = {
    app_name: (165, 190),
    "Applications": (495, 190),
}

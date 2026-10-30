"""Export only the client, excluding MCP, secrets, backend and user data."""
import shutil
from pathlib import Path
root=Path(__file__).resolve().parents[1];dest=root/'.staging/native';dest.mkdir(parents=True,exist_ok=True)
shutil.copytree(root/'native',dest/'native',dirs_exist_ok=True);shutil.copytree(root/'design',dest/'design',dirs_exist_ok=True)
# App icons from icon.svg. Installed icons used to fill the whole square and looked bigger than other apps:
# desktop/legacy icon gets a margin; Android gets an adaptive icon (dark background layer + artwork inside the
# launcher's safe zone, which masks and zooms the foreground).
svg=(root/'icon.svg').read_text()
head,body=svg[:svg.index('>',svg.index('<svg'))+1],svg[svg.index('>',svg.index('<svg'))+1:svg.rindex('</svg>')]
defs=body[body.index('<defs>'):body.index('</defs>')+7]
art=body.replace(defs,'')
art=art[art.index('<!-- Server Tab Stack'):art.index('<!-- Brand name')]  # the artwork, without container or text
(dest/'icon.svg').write_text(head+'<g transform="translate(51.2 51.2) scale(0.8)">'+body+'</g></svg>')
(dest/'icon_fg.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 432 432" width="432" height="432">'+defs
  +'<g transform="translate(88 90) scale(0.5)">'+art+'</g></svg>')
(dest/'icon_bg.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 432 432" width="432" height="432">'+defs
  +'<rect width="432" height="432" fill="url(#iconBg)"/></svg>')
(dest/'project.godot').write_text('''config_version=5
[application]
run/low_processor_mode=true
config/name="ThuêTab"
run/main_scene="res://native/Main.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")
config/icon="res://icon.svg"
boot_splash/show_image=false
boot_splash/bg_color=Color(0.0235, 0.0353, 0.0706, 1)
[display]
window/size/viewport_width=1280
window/size/viewport_height=800
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/handheld/orientation=6
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
environment/defaults/default_clear_color=Color(0.0235, 0.0353, 0.0706, 1)
textures/vram_compression/import_etc2_astc=true
''')
presets=[]
# File names match what /api/config "downloads" detects in data/downloads/ (by extension). iOS uses the web app (PWA).
OPTIONS={
  'Linux':'binary_format/embed_pck=true\n',
  'Windows':'binary_format/embed_pck=true\napplication/modify_resources=false\napplication/product_name="ThuêTab"\napplication/file_description="ThuêTab"\n',
  'Android':('package/unique_name="com.thuetab.app"\npackage/name="ThuêTab"\nversion/code=158\nversion/name="1.5.8"\n'
             'launcher_icons/main_192x192="res://icon.svg"\nlauncher_icons/adaptive_foreground_432x432="res://icon_fg.svg"\n'
             'launcher_icons/adaptive_background_432x432="res://icon_bg.svg"\n'
             'permissions/internet=true\npermissions/vibrate=true\ngradle_build/use_gradle_build=false\n'
             'architectures/arm64-v8a=true\narchitectures/armeabi-v7a=true\narchitectures/x86_64=false\n'
             'screen/immersive_mode=false\nscreen/support_small=true\nscreen/support_normal=true\nscreen/support_large=true\nscreen/support_xlarge=true\n'),
  'macOS':('application/bundle_identifier="com.thuetab.app"\napplication/short_version="1.5.8"\napplication/version="1.5.8"\n'
           'binary_format/architecture="universal"\ncodesign/codesign=1\nnotarization/notarization=0\n'),
}
for i,(name,platform,ext) in enumerate([('Linux','Linux','x86_64'),('Windows','Windows Desktop','exe'),('Android','Android','apk'),('macOS','macOS','zip')]):
    presets.append(f'''[preset.{i}]
name="{name}"
platform="{platform}"
runnable=true
export_filter="all_resources"
include_filter="design/*.json,design/fonts/*,native/*.json"
exclude_filter=""
export_path="../../exports/ThueTab-{name}.{ext}"
script_export_mode=2
[preset.{i}.options]
'''+OPTIONS[name])
(dest/'export_presets.cfg').write_text('\n'.join(presets));print(dest)

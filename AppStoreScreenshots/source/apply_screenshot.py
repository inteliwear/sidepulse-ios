"""Run with Blender --background --python apply_screenshot.py -- /absolute/path/screenshot.png"""
import bpy,sys
from pathlib import Path
O=Path(__file__).resolve().parents[1]
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
if len(args)!=1: raise SystemExit('Pass one portrait screenshot path after --')
path=Path(args[0]).expanduser().resolve()
if not path.is_file(): raise SystemExit(f'File not found: {path}')
for name in ['iphone-dot','iphone-dot-detail']:
 bpy.ops.wm.open_mainfile(filepath=str(O/'source'/f'{name}.blend'))
 image=bpy.data.images.load(str(path),check_existing=False)
 bpy.data.materials['SCREEN / App screenshot'].node_tree.nodes['REPLACE WITH APP SCREENSHOT'].image=image
 image.pack()
 bpy.context.scene.render.filepath=str(O/'renders'/f'{name}.png')
 bpy.ops.wm.save_as_mainfile(filepath=str(O/'source'/f'{name}.blend'))
 bpy.ops.render.render(write_still=True)

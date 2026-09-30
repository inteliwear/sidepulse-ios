"""Replace only the phone display with the real dark-mode app capture."""
import bpy
from pathlib import Path
O=Path(__file__).resolve().parents[1]
for name in ['dot-focus-1','dot-focus-2','dot-magnified']:
 bpy.ops.wm.open_mainfile(filepath=str(O/'source'/f'{name}.blend'))
 image=bpy.data.images.load(str(O/'screens/sidepulse-current-dark.png'));image.pack()
 bpy.data.materials['SCREEN / App screenshot'].node_tree.nodes['REPLACE WITH APP SCREENSHOT'].image=image
 s=bpy.context.scene
 s.cycles.samples=96
 s.render.filepath=str(O/'renders'/f'{name}-dark.png')
 bpy.ops.wm.save_as_mainfile(filepath=str(O/'source'/f'{name}-dark.blend'))
 bpy.ops.render.render(write_still=True)

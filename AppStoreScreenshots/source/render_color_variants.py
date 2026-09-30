"""Give each screenshot its own physical Dot glow and matching detail."""
import bpy
from pathlib import Path
O=Path(__file__).resolve().parents[1]
variants=[('01-shortcuts',1,(.025,.28,1)),('02-computer-status',2,(1,.19,.018)),('03-shortcuts',1,(.48,.045,1))]
for name,index,color in variants:
 for kind,source in [('main',f'dot-focus-{index}-dark'),('detail','dot-magnified-dark')]:
  bpy.ops.wm.open_mainfile(filepath=str(O/'source'/f'{source}.blend'))
  ramp=bpy.data.materials['Fine matte translucent diffuser'].node_tree.nodes['Color Ramp'].color_ramp
  for stop in ramp.elements:stop.color=(*color,1)
  for light in ['Warm LED spill','Blue LED spill']:bpy.data.objects[light].data.color=color
  s=bpy.context.scene;s.cycles.samples=96
  s.render.filepath=str(O/'renders'/f'{name}-{kind}.png')
  bpy.ops.wm.save_as_mainfile(filepath=str(O/'source'/f'{name}-{kind}.blend'))
  bpy.ops.render.render(write_still=True)

import bpy
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath='/Users/pero/pgit/sdstatus_bitbang/packaging/renders/dot-2026-09-13/sidepulse-dot-product.blend')
s=bpy.context.scene
s.render.resolution_x=2400;s.render.resolution_y=1920;s.render.resolution_percentage=100
s.cycles.samples=128;s.cycles.use_denoising=True
s.render.image_settings.color_mode='RGB'
s.render.film_transparent=False
bpy.data.objects['Background'].hide_render=False
m=bpy.data.materials['Studio gray'];m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.23,.23,.23,1)
s.world.node_tree.nodes['Background'].inputs[0].default_value=(.22,.22,.22,1)
cam=s.camera
for name,loc in [('angled',(16,-25,27)),('top',(0,0,50))]:
 cam.location=Vector(loc)*.001
 cam.rotation_euler=(Vector((0,.001,.003))-cam.location).to_track_quat('-Z','Y').to_euler()
 s.render.filepath=str(ROOT/'renders'/f'dot-{name}.png')
 bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'source'/f'dot-{name}.blend'))
 bpy.ops.render.render(write_still=True)

import bpy
from pathlib import Path
from mathutils import Vector
O=Path(__file__).resolve().parents[1]
for index in [1,2]:
 bpy.ops.wm.open_mainfile(filepath=str(O/'source'/f'minimal-{index}.blend'))
 s=bpy.context.scene;cam=s.camera
 cam.data.ortho_scale=.248
 cam.location+=cam.rotation_euler.to_quaternion()@Vector((.006,0,0))
 s.render.filepath=str(O/'renders'/f'dot-focus-{index}.png')
 bpy.ops.wm.save_as_mainfile(filepath=str(O/'source'/f'dot-focus-{index}.blend'))
 bpy.ops.render.render(write_still=True)
bpy.ops.wm.open_mainfile(filepath=str(O/'source/minimal-1.blend'))
s=bpy.context.scene;cam=s.camera
cam.location=(.016,-.028,.034);target=Vector((0,.0005,.0065));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=.028
s.render.resolution_x=1000;s.render.resolution_y=1000;s.render.resolution_percentage=100
s.render.filepath=str(O/'renders/dot-magnified.png')
bpy.ops.wm.save_as_mainfile(filepath=str(O/'source/dot-magnified.blend'))
bpy.ops.render.render(write_still=True)

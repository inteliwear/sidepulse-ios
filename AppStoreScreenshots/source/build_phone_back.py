import bpy,math
from pathlib import Path
from mathutils import Vector,Matrix
O=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(O/'source/dot-angled.blend'))
s=bpy.context.scene
# The phone source is stored in arbitrary units; normalize height to 150 mm.
before=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath='/Users/pero/Downloads/iphone-17-pro/source/iphone 17_4.glb')
new=set(bpy.data.objects)-before
scale=.150/4.0507021
R=Matrix(((-1,0,0,0),(0,0,1,0),(0,1,0,0),(0,0,0,1)))
T=Matrix.Translation((0,.0012+2.023909*scale,.00565)) @ R @ Matrix.Scale(scale,4)
for o in list(new):
 if o.type=='MESH':
  mw=T@o.matrix_world
  o.parent=None;o.matrix_world=mw;o.name='iPhone / '+o.name
for o in list(new):
 if o.type!='MESH':bpy.data.objects.remove(o,do_unlink=True)
# Orange anodized frame and a softer orange rear panel.
for name,color,metal,rough in [('Material.002',(.65,.105,.012,1),.55,.34),('Material.004',(.72,.18,.045,1),.8,.23),('Rim_Buttons',(.73,.17,.04,1),.8,.31)]:
 m=bpy.data.materials.get(name)
 if m:
  p=m.node_tree.nodes.get('Principled BSDF')
  for key in ['Base Color','Metallic','Roughness']:
   for l in list(p.inputs[key].links):m.node_tree.links.remove(l)
  p.inputs['Base Color'].default_value=color;p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
# Replace overly reflective imported lens coatings with dark optical glass.
for name in ['Screen_Glass','Camera_Pixel_Glass_002']:
 m=bpy.data.materials.get(name)
 if m:
  p=m.node_tree.nodes.get('Principled BSDF')
  for key,val in [('Base Color',(.004,.007,.012,1)),('Metallic',0),('Roughness',.18),('Alpha',1),('Transmission Weight',0)]:
   for l in list(p.inputs[key].links):m.node_tree.links.remove(l)
   p.inputs[key].default_value=val
  p.inputs['Coat Weight'].default_value=.03
  p.inputs['Specular IOR Level'].default_value=.08
# Keep the product geometry unchanged and align its connector to the phone port center.
port_z=.00565-.03654*scale
dz=port_z-(.001798+.004683)/2
for o in s.objects:
 if o.name.startswith('Actual '):o.location.z+=dz
# Rebalance studio illumination for the whole phone.
for name,loc,energy,size,target in [
 ('Key',(-.10,-.08,.25),.7,.22,(0,.06,0)),
 ('Fill',(.16,.09,.18),.4,.18,(0,.06,0)),
 ('Rim',(-.10,.22,.14),.5,.16,(0,.06,0))]:
 o=bpy.data.objects[name];o.location=loc;o.data.energy=energy;o.data.size=size;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
s.world.node_tree.nodes['Background'].inputs[1].default_value=.35
# Show a brighter, readable product glow at the scale of a complete phone.
m=bpy.data.materials['Fine matte translucent diffuser'];m.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value=1.25
for name in ['Warm LED spill','Blue LED spill']:
 o=bpy.data.objects[name];o.location.z+=dz;o.data.energy=.0028
s.cycles.samples=160;s.cycles.use_denoising=True;s.render.image_settings.color_mode='RGB'
s.render.resolution_x=1320;s.render.resolution_y=1760;s.render.resolution_percentage=100
cam=s.camera;cam.location=(.13,-.15,.31);target=Vector((0,.072,.004));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=.208
s.render.filepath=str(O/'renders/iphone-dot.png')
bpy.ops.wm.save_as_mainfile(filepath=str(O/'source/iphone-dot.blend'))
bpy.ops.render.render(write_still=True)
# Close view of the physical connection, retained as a secondary marketing asset.
cam.location=(.040,-.060,.065);target=Vector((0,.013,.003));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=.080
s.render.resolution_x=1600;s.render.resolution_y=1100;s.render.resolution_percentage=100
s.render.filepath=str(O/'renders/iphone-dot-detail.png')
bpy.ops.wm.save_as_mainfile(filepath=str(O/'source/iphone-dot-detail.blend'))
bpy.ops.render.render(write_still=True)

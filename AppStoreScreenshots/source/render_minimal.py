import bpy,math
from pathlib import Path
from mathutils import Vector,Matrix
O=Path(__file__).resolve().parents[1]
for index in [1,2]:
 bpy.ops.wm.open_mainfile(filepath=str(O/'source/iphone-dot.blend'))
 s=bpy.context.scene
 image=bpy.data.images.load(str(O/'screens/sidepulse-status.png'));image.pack()
 m=bpy.data.materials['SCREEN / App screenshot']
 m.node_tree.nodes['REPLACE WITH APP SCREENSHOT'].image=image
 em=m.node_tree.nodes.new('ShaderNodeEmission');em.inputs['Strength'].default_value=1.0
 m.node_tree.links.new(m.node_tree.nodes['REPLACE WITH APP SCREENSHOT'].outputs['Color'],em.inputs['Color'])
 m.node_tree.links.new(em.outputs[0],m.node_tree.nodes.get('Material Output').inputs['Surface'])
 # Use a clean screen surface above the imported glass, avoiding source-model overlaps.
 screen=bpy.data.objects['iPhone / SCREEN - replace screen-placeholder.png']
 pts=[screen.matrix_world@v.co for v in screen.data.vertices]
 xmin=min(v.x for v in pts);xmax=max(v.x for v in pts);ymin=min(v.y for v in pts);ymax=max(v.y for v in pts)
 # Follow the native glass outline instead of imposing a generic corner radius.
 points=sorted(set((round(v.x,7),round(v.y,7)) for v in pts))
 def cross(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
 lower=[]
 for point in points:
  while len(lower)>=2 and cross(lower[-2],lower[-1],point)<=1e-12:lower.pop()
  lower.append(point)
 upper=[]
 for point in reversed(points):
  while len(upper)>=2 and cross(upper[-2],upper[-1],point)<=1e-12:upper.pop()
  upper.append(point)
 outline=lower[:-1]+upper[:-1]
 def inset_polygon(poly,distance,z):
  result=[]
  for i,v in enumerate(poly):
   prev=Vector(poly[i-1]);cur=Vector(v);nxt=Vector(poly[(i+1)%len(poly)])
   e1=(cur-prev).normalized();e2=(nxt-cur).normalized()
   n1=Vector((-e1.y,e1.x));n2=Vector((-e2.y,e2.x));bisector=(n1+n2).normalized()
   q=cur+bisector*(distance/max(bisector.dot(n1),.01));result.append((q.x,q.y,z))
  return result
 verts=inset_polygon(outline,.0012,.01105)
 mesh=bpy.data.meshes.new('Screenshot surface - native matched corners');mesh.from_pydata(verts,[],[list(range(len(verts)))]);mesh.update()
 screen.data=mesh;screen.matrix_world=Matrix.Identity(4);mesh.materials.append(m)
 xmin=min(v[0] for v in verts);xmax=max(v[0] for v in verts);ymin=min(v[1] for v in verts);ymax=max(v[1] for v in verts)
 borderverts=inset_polygon(outline,.0004,.011)
 bm=bpy.data.meshes.new('Native matched display border');bm.from_pydata(borderverts,[],[list(range(len(borderverts)))]);bm.update()
 bo=bpy.data.objects.new('Display border',bm);s.collection.objects.link(bo);bm.materials.append(bpy.data.materials['Island black'])
 uv=mesh.uv_layers.new()
 for loop in mesh.loops:
  pt=mesh.vertices[loop.vertex_index].co;uv.data[loop.index].uv=((pt.x-xmin)/(xmax-xmin),(pt.y-ymin)/(ymax-ymin))
 # The captured iPhone screenshot already includes its Dynamic Island.
 bpy.data.objects['iPhone / Dynamic Island'].hide_render=True
 # Hide source front camera pieces so the screenshot's real status area is unobstructed.
 for name in ['iPhone / defaultMaterial.006','iPhone / defaultMaterial.007']:
  if name in bpy.data.objects:bpy.data.objects[name].hide_render=True
 bpy.data.materials['Studio gray'].node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.40,.40,.39,1)
 bpy.data.materials['Fine matte translucent diffuser'].node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value=.45
 for light in ['Warm LED spill','Blue LED spill']:bpy.data.objects[light].data.energy*=.4
 s.view_settings.view_transform='Standard';s.view_settings.look='None';s.view_settings.exposure=0
 cam=s.camera
 target=Vector((0,.073,.004))
 cam.location=(.027,-.075,.43) if index==1 else (-.018,-.035,.46)
 cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
 cam.data.ortho_scale=.225
 cam.location+=cam.rotation_euler.to_quaternion()@Vector((0,.015,0))
 s.render.resolution_x=1320;s.render.resolution_y=2868;s.render.resolution_percentage=100
 s.cycles.samples=160;s.render.image_settings.color_mode='RGB'
 s.render.filepath=str(O/'renders'/f'minimal-{index}.png')
 bpy.ops.wm.save_as_mainfile(filepath=str(O/'source'/f'minimal-{index}.blend'))
 bpy.ops.render.render(write_still=True)

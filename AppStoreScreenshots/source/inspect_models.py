import bpy,json
from pathlib import Path
from mathutils import Vector
O=Path(__file__).resolve().parent
models=['/Users/pero/Downloads/iphone_17_pro.glb','/Users/pero/Downloads/iphone_17_pro-2.glb','/Users/pero/Downloads/iphone-17-pro/source/iphone 17_4.glb']
for i,path in enumerate(models):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.import_scene.gltf(filepath=path)
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
 pts=[o.matrix_world@Vector(c) for o in meshes for c in o.bound_box]
 lo=Vector([min(p[k] for p in pts) for k in range(3)]);hi=Vector([max(p[k] for p in pts) for k in range(3)])
 print('MODEL',i,path,'bounds',list(lo),list(hi))
 for o in meshes:
  print(o.name, [round(v,5) for v in o.dimensions], 'center', [round(v,5) for v in sum((o.matrix_world@Vector(c) for c in o.bound_box),Vector())/8], [m.name for m in o.data.materials])
 bpy.ops.wm.save_as_mainfile(filepath=str(O/f'candidate-{i}.blend'))

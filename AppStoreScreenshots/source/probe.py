import bpy
from mathutils import Vector
bpy.ops.wm.open_mainfile(filepath='/Users/pero/pgit/sidepulse-ios/AppStoreScreenshots/source/dot-angled.blend')
for o in bpy.context.scene.objects:
 if o.type=='MESH' and o.name!='Background':
  pts=[o.matrix_world@Vector(c) for c in o.bound_box]
  print(o.name, 'min',[round(min(p[k] for p in pts),6) for k in range(3)],'max',[round(max(p[k] for p in pts),6) for k in range(3)])

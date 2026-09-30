import bpy
bpy.ops.wm.open_mainfile(filepath='/Users/pero/pgit/sidepulse-ios/AppStoreScreenshots/source/iphone-dot.blend')
for m in bpy.data.materials:
 if m.name in ['Material.002','Material.004','Rim_Buttons','Screen_Glass','Glass_Camera_Logo','Plastic','Camera_Pixel_Glass_002','Camera_Pixel__002']:
  print(m.name)
  for n in m.node_tree.nodes:
   if n.type=='BSDF_PRINCIPLED':
    print([(k,tuple(n.inputs[k].default_value) if n.inputs[k].type=='RGBA' else n.inputs[k].default_value, bool(n.inputs[k].links)) for k in ['Base Color','Roughness','Metallic','Emission Strength','Transmission Weight','Alpha']])

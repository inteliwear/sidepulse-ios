"""Render the established CAD-based Dot scene; run with Blender --background --python.

No product geometry is created, scaled, or modified. See the output README for provenance.
"""
import argparse
import sys
from pathlib import Path
import bpy
from mathutils import Vector

parser = argparse.ArgumentParser()
parser.add_argument('--scene', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--preview', action='store_true')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
args.output.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(args.scene))
s = bpy.context.scene
s.render.engine = 'CYCLES'
s.cycles.samples = 32 if args.preview else 128
s.cycles.use_denoising = True
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'METAL'
    prefs.get_devices()
    for device in prefs.devices:
        device.use = device.type == 'METAL'
    s.cycles.device = 'GPU'
except Exception:
    s.cycles.device = 'CPU'
s.render.image_settings.file_format = 'PNG'
s.render.image_settings.color_mode = 'RGBA'
s.render.resolution_percentage = 100
# Neutral tone mapping preserves saturated product colors better than AgX.
s.view_settings.view_transform = 'Khronos PBR Neutral'
s.world.node_tree.nodes['Background'].inputs[0].default_value = (.22, .22, .22, 1)
metal = bpy.data.materials['Brushed USB-C steel'].node_tree.nodes.get('Principled BSDF')
metal.inputs['Roughness'].default_value = .52
metal.inputs['Base Color'].default_value = (.46, .47, .48, 1)
frost = bpy.data.materials['Fine matte translucent diffuser']
bsdf = frost.node_tree.nodes.get('Principled BSDF')
bsdf.inputs['Roughness'].default_value = .62
bsdf.inputs['Transmission Weight'].default_value = .04
bsdf.inputs['Specular IOR Level'].default_value = .22
bsdf.inputs['Subsurface Weight'].default_value = .12
ramp = next(n for n in frost.node_tree.nodes if n.type == 'VALTORGB').color_ramp
bpy.data.materials['Studio gray'].node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value = (.24, .24, .24, 1)
cam = s.camera
background = bpy.data.objects['Background']

def lighting(left, right, strength=.5):
    ramp.elements[0].color = (*left, 1)
    ramp.elements[-1].color = (*right, 1)
    bsdf.inputs['Emission Strength'].default_value = strength
    for i, (name, color) in enumerate(zip(('Warm LED spill', 'Blue LED spill'), (left, right))):
        light = bpy.data.objects[name]
        light.data.color = color
        light.data.energy = .0015
        p = bpy.data.materials['LED ' + str(i + 1)].node_tree.nodes.get('Principled BSDF')
        p.inputs['Base Color'].default_value = (*color, 1)
        p.inputs['Emission Color'].default_value = (*color, 1)

def camera(view, icon=False):
    if view == 'top':
        cam.location = (0, .001, .05)
        cam.rotation_euler = (0, 0, 0)
        cam.data.ortho_scale = .019
    else:
        cam.location = Vector((16, -25, 30)) * .001
        cam.rotation_euler = (Vector((0, .001, .003)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        cam.data.ortho_scale = .017 if icon else .023

def render(name, size, transparent=False):
    s.render.resolution_x = s.render.resolution_y = size
    background.hide_render = transparent
    s.render.film_transparent = transparent
    s.render.filepath = str(args.output / (name + '.png'))
    bpy.ops.render.render(write_still=True)

lighting((1, .16, .008), (.005, .10, 1))
for view in ('top', 'angled'):
    camera(view)
    render('dot-' + view, 768 if args.preview else 1800)
    if not args.preview:
        render('dot-' + view + '-transparent', 1800, True)
if not args.preview:
    background.hide_render = False
    s.render.film_transparent = False
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output / 'sidepulse-dot-shortcuts.blend'))
    colors = {'Red': (1, .008, .012), 'Green': (.02, .8, .035), 'Blue': (.008, .045, 1),
              'Purple': (.65, .012, .8), 'Aqua': (.005, .65, .85), 'Ember': (1, .20, .006)}
    s.cycles.samples = 64
    camera('angled', icon=True)
    for mode, strength in (('Pulse', .35), ('Breathe', .55)):
        for name, color in colors.items():
            lighting(color, color, strength)
            render('Shortcut' + mode + 'Dot' + name, 512, True)

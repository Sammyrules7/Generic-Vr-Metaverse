"""Original Starlight Observatory art. Run with Blender --background --python.

Blender Z-up; glTF exporter converts to Godot Y-up. No external assets needed.
"""
import bpy
import math
import random
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Godot/observatory/assets"
random.seed(29)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def mat(name, color, metallic=0, emission=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metallic
    p.inputs['Roughness'].default_value = .65
    if emission:
        p.inputs['Emission Color'].default_value = (*color, 1)
        p.inputs['Emission Strength'].default_value = emission
    return m

stone = mat('Ivory limestone', (.56,.61,.64))
dark = mat('Midnight blue enamel', (.035,.085,.14), .45)
brass = mat('Brushed champagne brass', (.65,.39,.15), .65)
wood = mat('Warm cedar', (.25,.105,.055))
cushion = mat('Teal upholstery', (.045,.25,.27))
light = mat('Amber lantern', (1,.58,.19), emission=2)
cyan = mat('Celestial cyan', (.22,.8,1), emission=2)
rock = mat('Basalt', (.09,.13,.19))
leaf = mat('Alpine blue spruce', (.055,.19,.19))
mountains = [mat('Mountain haze '+str(i), (.075+i*.018,.11+i*.021,.19+i*.025)) for i in range(3)]
snow = mat('Moonlit snow', (.43,.58,.67))

def finish(o, name, material):
    o.name = name
    o.data.materials.append(material)
    return o

def cube(name, loc, scale, material, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o=bpy.context.object
    o.scale=scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod=o.modifiers.new('Soft crafted edges','BEVEL'); mod.width=bevel; mod.segments=2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(o,name,material)

def cyl(name, loc, radius, depth, material, vertices=48, top=None):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius if top is None else top, depth=depth, location=loc)
    return finish(bpy.context.object,name,material)

def beam(name, a, b, radius, material, vertices=12):
    a,b=Vector(a),Vector(b)
    o=cyl(name,(a+b)/2,radius,(b-a).length,material,vertices)
    o.rotation_mode='QUATERNION'; o.rotation_quaternion=(b-a).to_track_quat('Z','Y')
    return o

def arc(name, center, radius, z, start, end, width, height, material, segments=48):
    # Solid arc with a flat top; useful for seating, trim and guard walls.
    verts=[]
    for i in range(segments+1):
        a=start+(end-start)*i/segments
        for r,h in [(radius-width/2,z-height/2),(radius+width/2,z-height/2),(radius-width/2,z+height/2),(radius+width/2,z+height/2)]:
            verts.append((center[0]+r*math.cos(a),center[1]+r*math.sin(a),h))
    faces=[]
    for i in range(segments):
        a=i*4;b=a+4
        faces.extend([(a,b,b+1,a+1),(a+2,a+3,b+3,b+2),(a,a+2,b+2,b),(a+1,b+1,b+3,a+3)])
    faces.extend([(0,1,3,2),(segments*4,segments*4+2,segments*4+3,segments*4+1)])
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o)
    return finish(o,name,material)

# One continuous, level social floor. '-col' imports static trimesh collisions.
cyl('Foundation', (0,0,-.65),16.3,1.1,dark,96)
cyl('Promenade-col', (0,0,-.14),16,.28,stone,96)
for r in (15.85,14.8):
    arc('Perimeter brass inlay',(0,0),r,.012,0,math.tau,.045,.018,brass,96)
arc('Luminous rim',(0,0),16.32,-.28,0,math.tau,.045,.09,light,96)
cyl('Lounge wood inlay',(0,0,.017),6.0,.03,wood,96)
for r in (2.2,5.85):
    arc('Lounge orbit',(0,0),r,.04,0,math.tau,.045,.025,brass,96)
# Radial etched floor lines.
for i in range(24):
    a=i*math.tau/24
    beam('Stone seam',(6.1*math.cos(a),6.1*math.sin(a),.018),(14.7*math.cos(a),14.7*math.sin(a),.018),.012,dark,4)

# Safe outer balustrade, interrupted only by solid piers.
arc('Terrace parapet-col',(0,0),15.5,.43,0,math.tau,.27,.86,dark,96)
arc('Handrail-col',(0,0),15.5,1.08,0,math.tau,.18,.12,brass,96)
for i in range(32):
    a=i*math.tau/32;x,y=15.5*math.cos(a),15.5*math.sin(a)
    cyl('Baluster-col',(x,y,.8),.07,.6,brass,8)

# Curved conversation benches flank the globe, leaving broad approach routes.
for start in (-.52,math.pi-.52):
    arc('Curved bench-col',(0,0),4.15,.28,start,start+1.04,1.12,.56,wood,16)
    arc('Teal seat-col',(0,0),4.12,.61,start,start+1.04,1.12,.14,cushion,16)
    arc('Backrest-col',(0,0),4.68,1.0,start,start+1.04,.18,.8,dark,16)
    arc('Bench piping',(0,0),4.68,1.42,start,start+1.04,.2,.05,brass,16)

# Armillary pedestal; the moving globe is a native Godot node.
cyl('Globe plinth-col',(0,0,.15),1.25,.3,dark)
cyl('Globe pedestal-col',(0,0,.65),.52,1,stone,32,top=.32)
cyl('Globe pedestal collar',(0,0,1.13),.57,.12,brass)
arc('Globe halo base',(0,0),1.24,.32,0,math.tau,.04,.035,light)

# Open observatory: twelve pillars, an incomplete dome and a clear entrance.
cx,cy=0,8
cyl('Observatory floor',(cx,cy,.025),5.2,.045,dark,64)
for r in (4.8,5.1):
    arc('Observatory floor ring',(cx,cy),r,.055,0,math.tau,.06,.025,brass,64)
for i in range(12):
    a=math.tau*i/12
    if math.sin(a)<-.7: continue
    x,y=cx+5*math.cos(a),cy+5*math.sin(a)
    cyl('Column foot-col',(x,y,.18),.48,.36,stone,12)
    cyl('Observatory pillar-col',(x,y,2.3),.21,4.3,stone,12)
    cyl('Column capital',(x,y,4.45),.38,.25,brass,12)
    cyl('Pillar lantern',(x,y,3.5),.23,.32,light,12)
arc('Dome cornice',(cx,cy),5,4.7,0,math.tau,.4,.32,dark,72)
arc('Dome cornice gold',(cx,cy),5.22,4.68,0,math.tau,.055,.06,brass,72)
for i in range(12):
    a=math.tau*i/12
    for j in range(12):
        t1=j*math.pi/24;t2=(j+1)*math.pi/24
        a1=(cx+5*math.cos(t1)*math.cos(a),cy+5*math.cos(t1)*math.sin(a),4.85+4*math.sin(t1))
        a2=(cx+5*math.cos(t2)*math.cos(a),cy+5*math.cos(t2)*math.sin(a),4.85+4*math.sin(t2))
        beam('Celestial dome rib',a1,a2,.075,brass)
for h in (.35,.7,1.05):
    arc('Dome latitude',(cx,cy),5*math.cos(h),4.85+4*math.sin(h),0,math.tau,.055,.055,brass,72)
cyl('Dome finial',(cx,cy,9.05),.17,.65,light,12,top=0)

# Hero telescope, looking over the left skyline.
cyl('Telescope foundation-col',(0,8,.2),1.15,.4,stone,48)
cyl('Telescope pier-col',(0,8,1),.35,1.6,brass,24)
beam('Telescope axle',(-.75,8,1.9),(.75,8,1.9),.23,dark)
beam('Telescope barrel',(.8,7.65,1.7),(-1.7,8.75,3.65),.42,dark,48)
for t in (.05,.3,.9,1):
    a=Vector((.8,7.65,1.7)).lerp(Vector((-1.7,8.75,3.65)),t)
    b=a+Vector((-.11,.048,.086))
    beam('Telescope brass band',a,b,.46,brass,48)
beam('Telescope lens',(-1.71,8.754,3.658),(-1.73,8.763,3.675),.38,cyan,48)
beam('Eyepiece',(.8,7.65,1.7),(1.14,7.5,1.45),.13,brass,24)

# Terrace reading tables and paired stools.
for x,y in [(-10,0),(10,0),(-8,-9),(8,-9)]:
    cyl('Table foot-col',(x,y,.12),.55,.24,dark,24)
    cyl('Table stem-col',(x,y,.52),.09,.8,brass,12)
    cyl('Table top-col',(x,y,.94),.85,.1,wood,48)
    cyl('Table lantern',(x,y,1.13),.13,.28,light,12)
    for dy in (-1.45,1.45):
        cyl('Terrace stool-col',(x,y+dy,.27),.4,.54,dark,24)
        cyl('Terrace cushion-col',(x,y+dy,.57),.43,.12,cushion,24)

# Lanterns and stylized alpine trees frame the horizon.
for x,y in [(-12,-5),(12,-5),(-10,8),(10,8),(-5,13),(5,13)]:
    cyl('Planter-col',(x,y,.4),.85,.8,stone,12,top=1)
    cyl('Soil',(x,y,.81),.89,.03,rock,12)
    cyl('Spruce trunk-col',(x,y,1.9),.13,2.2,wood,8)
    for z,r in [(1.8,1.15),(2.5,.95),(3.2,.7),(3.8,.4)]:
        cyl('Spruce crown',(x,y,z),r,1.6,leaf,9,top=0)
for i in range(12):
    a=math.tau*i/12;x,y=14.9*math.cos(a),14.9*math.sin(a)
    cyl('Lantern bollard-col',(x,y,.65),.2,1.3,dark,8)
    cyl('Lantern window',(x,y,1.35),.18,.3,light,8)
    cyl('Lantern cap',(x,y,1.55),.28,.12,brass,8)

# Jagged, snow-capped ridges give the distant landscape distinct silhouettes.
cyl('Mountain beneath',(0,0,-7),7,13,rock,11,top=16)
def mountain(x,y,base,width,height,material):
    segments=9
    verts=[]
    rotation=random.random()*math.tau
    radii=[random.uniform(.72,1.28) for _ in range(segments)]
    for level,scale in [(0,1),(.4,.66),(.7,.34)]:
        for j in range(segments):
            a=j*math.tau/segments+rotation
            z=base+height*(level+random.uniform(-.055,.055))
            verts.append((x+math.cos(a)*width*scale*radii[j]+level*width*.15,y+math.sin(a)*width*scale*radii[j],z))
    verts.append((x+width*.21,y-width*.12,base+height))
    faces=[];snow_faces=[]
    for ring in range(2):
        for j in range(segments):
            a=ring*segments+j;b=ring*segments+(j+1)%segments
            faces.extend([(a,b,a+segments),(b,b+segments,a+segments)])
            snow_faces.extend([False,ring==1])
    for j in range(segments):
        faces.append((segments*2+j,segments*2+(j+1)%segments,segments*3));snow_faces.append(True)
    mesh=bpy.data.meshes.new('Alpine ridge');mesh.from_pydata(verts,[],faces);mesh.update()
    o=bpy.data.objects.new('Snow capped ridge',mesh);bpy.context.collection.objects.link(o)
    o.data.materials.append(material);o.data.materials.append(snow)
    for poly,is_snow in zip(mesh.polygons,snow_faces):poly.material_index=int(is_snow)

for i in range(38):
    a=i*math.tau/38+random.uniform(-.04,.04)
    radius=random.uniform(100,165)
    mountain(radius*math.cos(a),radius*math.sin(a),-27,random.uniform(16,31),random.uniform(40,76),mountains[i%3])

# Two unoccupied beacon outposts hint at a larger world beyond this home.
for x,y,z in [(-40,35,1),(48,57,5)]:
    cyl('Beacon outcrop',(x,y,z-6),2.7,12,rock,9,top=7)
    cyl('Outcrop crown',(x,y,z),7,.7,mountains[0],9)
    cyl('Beacon footing',(x,y,z+.6),2.8,.5,stone,12)
    for j in range(6):
        a=j*math.tau/6;px,py=x+2.2*math.cos(a),y+2.2*math.sin(a)
        cyl('Far beacon pillar',(px,py,z+3.7),.18,6,stone,8)
    arc('Far beacon cornice',(x,y),2.5,z+6.7,0,math.tau,.4,.3,brass,32)
    cyl('Far beacon roof',(x,y,z+7.9),2.9,2.2,dark,12,top=.15)
    cyl('Beacon flame',(x,y,z+4.1),.38,2.4,light,12,top=.1)
    cyl('Beacon spire',(x,y,z+9.5),.12,1.3,brass,8,top=0)
    for px,py,h in [(x-4,y+1,3.2),(x+3,y+3,4.3),(x-2,y-4,2.3)]:
        cyl('Far spruce trunk',(px,py,z+h*.3),.11,h*.6,wood,8)
        cyl('Far spruce crown',(px,py,z+h*.65),h*.35,h,leaf,8,top=0)

OUT.mkdir(parents=True,exist_ok=True)
# Save the modular, editable source before batching the export by material.
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'tools/observatory/starlight_observatory.blend'))
for material in list(bpy.data.materials):
    for collision in (False, True):
        objs=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.data.materials and o.data.materials[0]==material and ('-col' in o.name)==collision]
        if not objs: continue
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:o.select_set(True)
        bpy.context.view_layer.objects.active=objs[0]
        if len(objs)>1: bpy.ops.object.join()
        objs[0].name=material.name.replace(' ','_')+('-col' if collision else '')
        objs[0].data.name=objs[0].name
bpy.ops.export_scene.gltf(filepath=str(OUT/'observatory.glb'),export_format='GLB',export_cameras=False,export_lights=False,export_yup=True)
print('Observatory asset exported:',len(bpy.context.scene.objects),'objects')

"""Original grotto geology. Run with: nix shell nixpkgs#blender -c blender -b -t 2 --python ..."""
import bpy, math, random
from pathlib import Path
from mathutils import Vector
random.seed(1709)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
stone = bpy.data.materials.new('Moonwashed limestone')
stone.diffuse_color = (0.22, 0.29, 0.36, 1)

def rock(name, pos, scale, seed, sides=9, rings=5, flat_top=False):
    rng = random.Random(seed)
    verts, faces = [], []
    phase = rng.uniform(0, 6.28)
    for j in range(rings):
        t = j / (rings-1)
        radius = (0.68 + math.sin(t*math.pi)*0.32) * rng.uniform(.88,1.12)
        for i in range(sides):
            a = i*math.tau/sides + phase + rng.uniform(-.12,.12)
            r = .98 if flat_top and j == rings-1 else radius*rng.uniform(.85,1.14)
            # Blender Z up, Godot -Z forward.
            verts.append((pos[0]+math.cos(a)*r*scale[0], -pos[2]+math.sin(a)*r*scale[2], (pos[1]+scale[1]) if flat_top and j == rings-1 else pos[1]+(t-.5)*2*scale[1]+rng.uniform(-.07,.07)*scale[1]))
    faces.append(tuple(reversed(range(sides))))
    for j in range(rings-1):
        for i in range(sides):
            a=j*sides+i; b=j*sides+(i+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces.append(tuple((rings-1)*sides+i for i in range(sides)))
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.materials.append(stone); mesh.update()
    obj=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(obj)
    bevel=obj.modifiers.new('Eroded edges','BEVEL'); bevel.width=.09; bevel.segments=1
    obj.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return obj

# A rocky island rim contains the lagoon without concealing the sky.
rock('Island foundation',(0,-2.2,-2),(13.2,1.5,17.8),1800,32,4,True)
for i in range(44):
    a=math.tau*i/44
    x=12.0*math.cos(a); z=-2+16.2*math.sin(a)
    height=random.uniform(.75,1.6)
    rock('Lagoon rim',(x,height*.4-.2,z),(random.uniform(1.65,2.25),height,random.uniform(1.7,2.3)),2000+i)
# One asymmetric arch remains a landmark above the waterfall.
for i in range(13):
    a=math.pi*i/12
    rock('Natural moon arch',(6.8*math.cos(a),2.6+7.5*math.sin(a),-14.2),(1.45,1.5,1.7),600+i)
# Distant sea stacks establish scale and depth beyond the playable island.
for i,(x,z,h) in enumerate([(-58,-88,12),(-80,-120,17),(-46,-118,7),(62,-108,15),(83,-133,9),(44,-79,6),(-90,20,10),(100,34,13)]):
    rock('Distant sea stack',(x,h*.35-4,z),(h*.65,h,h*.7),2300+i)
# Shore rubble, avoiding the central path.
for i in range(65):
    side=random.choice([-1,1]); x=side*random.uniform(7.5,11.5); z=random.uniform(-13,10)
    rock('Shore boulder',(x,random.uniform(-.15,.25),z),(random.uniform(.5,1.5),random.uniform(.4,1),random.uniform(.5,1.5)),900+i)
# Flat, walkable landing and shrine terrace.
rock('Arrival terrace',(0,-.8,9),(8,1,4.8),1201,14,3,True)
rock('Sanctuary isle',(0,-.65,-7.3),(4.3,.85,3.3),1202,13,3,True)
# Continuous low stepping stones through the shallows.
for i in range(7):
    rock('Pilgrim causeway',(math.sin(i*.8)*1.1,-.12,5.4-i*1.65),(1.4,.32,1.17),1300+i,8,3,True)
# A spring-fed rock shelf holds the waterfall above the sanctuary.
for i in range(4):
    for j in range(3):
        rock('Spring cliff',(-3.8+i*2.5+random.uniform(-.3,.3),j*2.6+.5,-11.8+random.uniform(-.35,.35)),(1.8,1.7,2.1),1500+i*3+j)
rock('Spillway lip',(0,7.8,-10.2),(2.2,.5,1.2),1550)
out=Path(__file__).resolve().parents[1]/'models'/'grotto_geology.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',export_apply=True,export_cameras=False,export_lights=False)
print('Exported',out)

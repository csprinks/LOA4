import bpy, os
from mathutils import Matrix, Vector

OUT = r"E:/Godot Projects/Cloudforge/assets/models/grass/grass_props.glb"

PROPS = {
    "plant_b": "IMG_20180409_170136_376",
    "plant_c": "IMG_20180409_170136_376.003",
    "stem_a": "IMG_20180401_155603_713.001",
    "stem_b": "IMG_20180327_195344",
    "stem_c": "IMG_20180327_195424.001",
    "flower_dandelion": "Dandelions_1",
    "flower_daisy": "IMG_20180327_190302.000",
}

def clear_selection():
    for o in bpy.data.objects:
        o.select_set(False)

def simplify_material(m):
    if not m or not m.use_nodes:
        return
    img = None
    for n in m.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image:
            img = n.image
            break
    if img is None:
        return
    nt = m.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = img
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    nt.links.new(tex.outputs['Alpha'], bsdf.inputs['Alpha'])
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    m.blend_method = 'CLIP'
    m.alpha_threshold = 0.5
    m.use_backface_culling = False

OB_Y_PROPS = {"tuft_a", "tuft_b", "tuft_c", "tuft_d"}
VEL_PROPS = {"flower_dandelion", "flower_daisy"}

exp_coll = bpy.data.collections.new("GRASS_EXPORT")
bpy.context.scene.collection.children.link(exp_coll)

made = []
missing = []
for clean, src_name in PROPS.items():
    src = bpy.data.objects.get(src_name)
    if src is None:
        missing.append(src_name)
        continue
    dup = src.copy()
    dup.data = src.data.copy()
    dup.name = clean
    dup.data.name = clean
    exp_coll.objects.link(dup)

    # bound_box is cached and doesn't refresh after mesh.transform()
    def vbounds(me):
        vs = me.vertices
        mn = Vector((min(v.co.x for v in vs), min(v.co.y for v in vs), min(v.co.z for v in vs)))
        mx = Vector((max(v.co.x for v in vs), max(v.co.y for v in vs), max(v.co.z for v in vs)))
        return mn, mx

    dup.matrix_world = Matrix.Identity(4)
    dup.data.transform(src.matrix_world.copy())

    if clean in OB_Y_PROPS:
        # map +Y -> +Z: x'=x, y'=-z, z'=y
        M = Matrix([[1, 0, 0], [0, 0, -1], [0, 1, 0]])
        dup.data.transform(M.to_4x4())
    elif clean in VEL_PROPS:
        mn0, mx0 = vbounds(dup.data)
        order = sorted([0, 1, 2], key=lambda i: (mx0 - mn0)[i])  # smallest .. largest
        R = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]
        R[0][order[1]] = 1.0   # x' = middle
        R[1][order[0]] = 1.0   # y' = smallest (facing)
        R[2][order[2]] = 1.0   # z' = largest (up)
        M = Matrix(R)
        if M.determinant() < 0:
            R[1][order[0]] = -1.0
            M = Matrix(R)
        dup.data.transform(M.to_4x4())

    mn2, mx2 = vbounds(dup.data)
    cx = (mn2.x + mx2.x) * 0.5
    cy = (mn2.y + mx2.y) * 0.5
    dup.data.transform(Matrix.Translation(Vector((-cx, -cy, -mn2.z))))
    made.append((clean, round(mx2.z - mn2.z, 3)))

seen_mats = set()
for o in exp_coll.objects:
    for slot in o.material_slots:
        if slot.material and slot.material.name not in seen_mats:
            seen_mats.add(slot.material.name)
            simplify_material(slot.material)
print("simplified", len(seen_mats), "materials")

clear_selection()
for o in exp_coll.objects:
    o.select_set(True)
    bpy.context.view_layer.objects.active = o

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format='GLB',
    use_selection=True,
    export_yup=True,
    export_apply=True,
    export_materials='EXPORT',
    export_image_format='AUTO',
)
print("=== EXPORTED ===", OUT)
for n, h in made:
    print("  prop", n, "height(Z)=", h)
if missing:
    print("!!! MISSING:", missing)

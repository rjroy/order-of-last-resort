"""Small mesh and rig helpers for the two Last Wagon authoring sources."""

from math import cos, pi, sin
import bpy
from mathutils import Matrix, Quaternion, Vector


def pigment(name, dark, light, scale=7, roughness=.78, axis=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*light, 1)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    shader.inputs["Roughness"].default_value = roughness
    tex = nodes.new("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = scale
    tex.inputs["Detail"].default_value = 2.1
    uv = nodes.new("ShaderNodeTexCoord")
    coords = uv.outputs["Generated"]
    if axis:
        stretch = nodes.new("ShaderNodeVectorMath")
        stretch.operation = "MULTIPLY"
        stretch.inputs[1].default_value = axis
        links.new(coords, stretch.inputs[0])
        coords = stretch.outputs[0]
    links.new(coords, tex.inputs["Vector"])
    colors = nodes.new("ShaderNodeValToRGB")
    colors.color_ramp.elements[0].position = .21
    colors.color_ramp.elements[0].color = (*dark, 1)
    colors.color_ramp.elements[1].position = .79
    colors.color_ramp.elements[1].color = (*light, 1)
    links.new(tex.outputs["Fac"], colors.inputs[0])
    links.new(colors.outputs[0], shader.inputs["Base Color"])
    return mat


def axes(vector, right=(1, 0, 0)):
    """Bone frame with Y along the segment and X tracking the given side."""
    y = Vector(vector).normalized()
    x = Vector(right) - y * y.dot(Vector(right))
    if x.length < .005:
        right = min((Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))),
                    key=lambda a: abs(a.dot(y)))
        x = right - y * y.dot(right)
    x.normalize()
    z = x.cross(y)
    return Matrix((x, y, z)).transposed()


class Model:
    def __init__(self, name, specs, yaw=0):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        scene = bpy.context.scene
        scene.render.fps = 24
        scene.unit_settings.system = "METRIC"
        scene.render.resolution_x = scene.render.resolution_y = 360
        self.scene, self.name = scene, name
        self.yaw = self.scene_yaw = yaw
        self.groups = {}
        self.rig = bpy.data.objects.new(name + "_Rig", bpy.data.armatures.new(name + " • rig"))
        self.group("00 | Rig").objects.link(self.rig)
        bpy.context.view_layer.objects.active = self.rig
        self.rig.select_set(True)
        self.rig.show_in_front = True
        self.rig.data.display_type = "OCTAHEDRAL"
        bpy.ops.object.mode_set(mode="EDIT")
        for tag, start, end, parent, family, right in specs:
            b = self.rig.data.edit_bones.new(tag)
            b.head, b.tail = start, end
            b.align_roll(axes(Vector(end) - Vector(start), right).col[2])
            if parent:
                b.parent = self.rig.data.edit_bones[parent]
            self.rig.data.collections.get(family) or self.rig.data.collections.new(family)
        bpy.ops.object.mode_set(mode="OBJECT")
        for tag, _, _, _, family, _ in specs:
            self.rig.data.collections[family].assign(self.rig.data.bones[tag])
            self.rig.pose.bones[tag].rotation_mode = "QUATERNION"
        self.rig.animation_data_create()
        self.category = "01 | Geometry"

    def group(self, name):
        if name not in self.groups:
            self.groups[name] = bpy.data.collections.new(name)
            self.scene.collection.children.link(self.groups[name])
        return self.groups[name]

    def mount(self, obj, bone=None):
        self.group(self.category).objects.link(obj)
        if bone:
            obj.parent = self.rig
            obj.parent_type = "BONE"
            obj.parent_bone = bone
            b = self.rig.data.bones[bone]
            rest = b.matrix_local @ Matrix.Translation((0, b.length, 0))
            obj.matrix_parent_inverse = rest.inverted()
        return obj

    def mesh(self, name, points, faces, mat, bone, bevel=0, smooth=False, indices=None):
        data = bpy.data.meshes.new(name)
        data.from_pydata(points, [], faces)
        data.update()
        obj = self.mount(bpy.data.objects.new(name, data), bone)
        for m in mat if isinstance(mat, (tuple, list)) else [mat]:
            obj.data.materials.append(m)
        for p in data.polygons:
            p.use_smooth = smooth
            if indices:
                p.material_index = indices[p.index]
        if bevel:
            mod = obj.modifiers.new("Worn arris", "BEVEL")
            mod.width, mod.segments = bevel, 2
            mod.affect = "EDGES"
            mod.limit_method = "ANGLE"
            normal = obj.modifiers.new("Panel normals", "WEIGHTED_NORMAL")
            normal.keep_sharp = True
        return obj

    def profile(self, name, outlines, mat, bone, bevel=0, smooth=False, indices=None):
        """Bridge equal-count rings. Rings run counterclockwise along the axis."""
        count = len(outlines[0])
        faces = [tuple(reversed(range(count)))]
        for k in range(len(outlines) - 1):
            start = k * count
            for i in range(count):
                j = (i + 1) % count
                faces.append((start + i, start + j, start + j + count, start + i + count))
        faces.append(tuple(range(len(outlines) * count - count, len(outlines) * count)))
        return self.mesh(name, [p for row in outlines for p in row], faces, mat, bone,
                         bevel, smooth, indices)

    def loft(self, name, a, b, rings, mat, bone, *, sides=12, power=1, wobble=0, phase=0,
             bevel=0, smooth=True, right=(1, 0, 0)):
        """Loft asymmetric elliptical sections around a shaped centerline."""
        a, b = Vector(a), Vector(b)
        frame = axes(b - a, right)
        outlines = []
        for k, (t, rx, rz, *offs) in enumerate(rings):
            dx, dz = offs if offs else (0, 0)
            center = a.lerp(b, t) + frame @ Vector((dx, 0, dz))
            row = []
            for j in range(sides):
                angle = 2 * pi * j / sides + phase
                x, z = cos(angle), -sin(angle)
                u = 1 + wobble * (sin(j * 3.37 + .49 * k) + .54 * cos(j * 1.73 - k))
                row.append(center + frame @ Vector((rx * u * abs(x)**power * (1 if x >= 0 else -1),
                                                    0,
                                                    rz * u * abs(z)**power * (1 if z >= 0 else -1))))
            outlines.append(row)
        return self.profile(name, outlines, mat, bone, bevel, smooth)

    def spheroid(self, name, xyz, radii, mat, bone, *, rings=8, sides=16, wobble=.025,
                 power=1, tilt=None):
        origin = Vector(xyz)
        tilt = tilt or Matrix.Identity(3)
        outlines = []
        for i in range(rings+1):
            t = pi * (.025 + .95 * i / rings)
            for_ring = []
            for j in range(sides):
                a = 2 * pi * j / sides
                r = 1 + wobble * (sin(j*1.93+i*.54) + .45*cos(j*.78-i*.72))
                x, y = cos(a), sin(a)
                p = (radii[0]*sin(t)*r*abs(x)**power*(1 if x >= 0 else -1),
                     radii[1]*sin(t)*r*abs(y)**power*(1 if y >= 0 else -1),
                     -radii[2]*cos(t))
                for_ring.append(origin + tilt @ Vector(p))
            outlines.append(for_ring)
        return self.profile(name, outlines, mat, bone, smooth=True)

    def beam(self, name, a, b, start, end, mat, bone, bevel=.008):
        a, b = Vector(a), Vector(b)
        frame = axes(b-a)
        rows = []
        for p, (rx, rz) in ((a, start), (b, end)):
            rows.append([p + frame @ Vector((x * rx, 0, z * rz))
                         for x, z in [(-1, -1), (-1, 1), (1, 1), (1, -1)]])
        return self.profile(name, rows, mat, bone, bevel)

    def box(self, name, center, size, mat, bone, bevel=.008, rotation=None):
        center = Vector(center)
        corners = ((-1, -1), (1, -1), (1, 1), (-1, 1))
        rotation = rotation or Matrix.Identity(3)
        outlines = [[center + rotation @ Vector((x*size[0]/2, y*size[1]/2, z*size[2]/2))
                     for x, y in corners] for z in (-1, 1)]
        return self.profile(name, outlines, mat, bone, bevel)

    def line(self, name, points, radius, mat, bone, *, spline="POLY", closed=False):
        data = bpy.data.curves.new(name, "CURVE")
        data.dimensions, data.resolution_u, data.bevel_depth = "3D", 8, radius
        data.bevel_resolution = 1
        data.use_fill_caps = True
        path = data.splines.new(spline)
        if spline == "BEZIER":
            path.bezier_points.add(len(points) - 1)
            for p, v in zip(path.bezier_points, points):
                p.co = v
                p.handle_left_type = p.handle_right_type = "AUTO"
        else:
            path.points.add(len(points) - 1)
            for p, v in zip(path.points, points):
                p.co = (*v, 1)
        path.use_cyclic_u = closed
        obj = self.mount(bpy.data.objects.new(name, data), bone)
        obj.data.materials.append(mat)
        return obj

    def action(self, title, stop, markers=()):
        self.rig.animation_data.action = None
        for b in self.rig.pose.bones:
            b.matrix_basis = Matrix.Identity(4)
        a = bpy.data.actions.new(f"{self.name} | {title}")
        self.rig.animation_data.action = a
        a.use_fake_user = True
        a.use_frame_range = True
        a.frame_start, a.frame_end = 1, stop
        for label, f in markers:
            a.pose_markers.new(label).frame = f
        self.previous = {}
        return a

    def local_key(self, bone, frame, location=(0, 0, 0), rotation=None):
        b = self.rig.pose.bones[bone]
        b.location = location
        q = rotation if rotation is not None else Quaternion()
        if bone in self.previous:
            q.make_compatible(self.previous[bone])
        self.previous[bone] = q.copy()
        b.rotation_quaternion = q
        b.keyframe_insert("location", frame=frame, group=bone)
        b.keyframe_insert("rotation_quaternion", frame=frame, group=bone)

    def absolute_keys(self, frame, targets):
        matrices = {}
        for b in self.rig.data.bones:
            parent = b.parent
            if b.name not in targets:
                matrices[b.name] = (matrices[parent.name] @ parent.matrix_local.inverted()
                                    @ b.matrix_local) if parent else b.matrix_local
                continue
            p, rot = targets[b.name]
            mx = rot.to_4x4()
            mx.translation = p
            if parent:
                local = b.convert_local_to_pose(mx, b.matrix_local, invert=True,
                                                parent_matrix=matrices[parent.name],
                                                parent_matrix_local=parent.matrix_local)
            else:
                local = b.convert_local_to_pose(mx, b.matrix_local, invert=True)
            self.local_key(b.name, frame, local.translation, local.to_quaternion())
            matrices[b.name] = mx

    def save(self, path, ready, stop, details):
        self.rig.rotation_euler.z = self.yaw
        self.rig.animation_data.action = bpy.data.actions[f"{self.name} | {ready}"]
        self.scene.frame_end = stop
        self.scene.frame_set(1)
        self.scene["Status"] = "MODEL REVIEW CANDIDATE • no runtime approval"
        self.scene["Approved concept SHA-256"] = "7f57ebb14852b0dd1a832c3783abd31d937a3d2babb1e23aac0e2ebb75a913c6"
        self.scene["Authoring"] = details
        self.rig["Scale and facing"] = "Metres, Z up, -Y rig-local forward"
        self.rig.select_set(False)
        self.rig.select_set(True)
        bpy.context.view_layer.objects.active = self.rig
        # Give the reopened viewport a useful initial composition.
        from mathutils import Euler
        for screen in bpy.data.screens:
            for area in screen.areas:
                if area.type == "VIEW_3D":
                    space = area.spaces.active
                    space.overlay.show_floor = space.overlay.show_axis_x = space.overlay.show_axis_y = False
                    space.overlay.show_extras = False
                    space.region_3d.view_distance = 3.45
                    space.region_3d.view_location = (0, 0, .88)
                    space.region_3d.view_rotation = Euler((1.150829196, 0, -.435386419)).to_quaternion()
                    space.region_3d.view_perspective = "ORTHO"
                    space.shading.color_type = "MATERIAL"
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)

"""A corked cordial vial sized to the Dodger's left-hand grip."""

import bpy
from math import cos, sin, tau
from mathutils import Matrix, Vector


GRIP = "hand.L"
# The vial crosses the cupped palm and rests between the thumb and fingers.
GRIP_LOCAL = Matrix.Translation(Vector((0.006, 0.087, -0.041))) @ (
    Vector((1.0, -0.19, 0.16)).to_track_quat("Z", "Y").to_matrix().to_4x4()
)


def vial_for(scene):
    # Profile is (height, radius, material for the next band), in metres.
    # Low facets keep the amber body, dark neck, and light cork legible.
    profile = (
        (-.063, .020, 0), (-.056, .031, 0), (.014, .032, 0),
        (.028, .020, 1), (.038, .014, 1), (.046, .018, 2),
        (.053, .016, 2), (.073, .015, 2), (.078, .011, 2),
    )
    sides = 10
    verts = [
        (radius * cos(tau * i / sides), radius * sin(tau * i / sides), z)
        for z, radius, _ in profile for i in range(sides)
    ]
    faces = [tuple(reversed(range(sides)))]
    indices = [0]
    for row in range(len(profile) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            faces.append((row * sides + i, row * sides + j,
                          (row + 1) * sides + j, (row + 1) * sides + i))
            indices.append(profile[row][2])
    faces.append(tuple(range(len(verts) - sides, len(verts))))
    indices.append(2)
    mesh = bpy.data.meshes.new("Dodger's cordial vial")
    mesh.from_pydata(verts, [], faces)
    for title, color in (
        ("Honey amber", (.66, .25, .034)),
        ("Smoked neck", (.27, .113, .037)),
        ("Pale sealed cork", (.68, .46, .24)),
    ):
        material = bpy.data.materials.new(title)
        material.use_nodes = True
        material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*color, 1)
        mesh.materials.append(material)
    for face, index in zip(mesh.polygons, indices):
        face.material_index = index
    vial = bpy.data.objects.new(mesh.name, mesh)
    scene.collection.objects.link(vial)
    vial.hide_render = True
    return vial

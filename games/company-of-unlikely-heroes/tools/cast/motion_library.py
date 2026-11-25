"""Append local takes and detached kit without loading the library's scene."""


def append_actions_only(bpy, requested, paths):
    remaining = set(requested) - set(bpy.data.actions.keys())
    objects = set(bpy.data.objects.keys())
    for path in paths:
        with bpy.data.libraries.load(str(path), link=False) as (available, selected):
            names = remaining & set(available.actions)
            if not names:
                raise ValueError(f"{path}: no requested supplementary actions")
            selected.actions = sorted(names)
        if {a.name for a in selected.actions if a and a.library is None} != names:
            raise ValueError(f"{path}: failed to append requested Actions {sorted(names)}")
        remaining -= names
    if remaining or set(bpy.data.objects.keys()) != objects:
        raise ValueError(f"incomplete supplementary Actions or dependencies: {sorted(remaining)}")


def append_motion_library(bpy, scene, rig, library, takes, motion_path):
    existing_objects = set(bpy.data.objects.keys())
    existing_actions = set(bpy.data.actions.keys())
    missing_actions = sorted(set(takes) - existing_actions)
    collection = library["collection"]
    with bpy.data.libraries.load(str(motion_path), link=False) as (available, selected):
        if not missing_actions or not set(missing_actions) <= set(available.actions):
            raise ValueError(f"{motion_path}: missing supplementary Actions {missing_actions}")
        if collection not in available.collections or collection in bpy.data.collections:
            raise ValueError(f"{motion_path}: unavailable or duplicate kit {collection}")
        selected.actions = missing_actions.copy()
        selected.collections = [collection]
    kit = selected.collections[0]
    if kit is None or any(action is None for action in selected.actions):
        raise ValueError(f"{motion_path}: could not append all supplementary datablocks")
    kit_objects = {obj.name: obj for obj in kit.all_objects}
    if (set(bpy.data.objects.keys()) - existing_objects != kit_objects.keys()
            or set(bpy.data.actions.keys()) - existing_actions != set(missing_actions)):
        raise ValueError(f"{motion_path}: supplementary kit depends on external objects or Actions")
    if any(data.library for data in [kit, *selected.actions, *kit_objects.values()]):
        raise ValueError(f"{motion_path}: supplementary datablocks must be local after append")
    binding = library["attach_like"]
    for name, socket in binding.items():
        root, attachment = kit_objects[name], bpy.data.objects[socket]
        if (root.type != "EMPTY" or root.parent is not None or attachment.parent != rig
                or attachment.parent_type != "BONE"):
            raise ValueError(f"{motion_path}: invalid kit attachment {name} → {socket}")
        root.parent = rig
        root.parent_type = attachment.parent_type
        root.parent_bone = attachment.parent_bone
        root.matrix_parent_inverse = attachment.matrix_parent_inverse
        root.matrix_basis = attachment.matrix_basis
    scene.collection.children.link(kit)

"""Native name resolution and optional single-actor staging recipes."""
import json
import re
from pathlib import Path

ART = Path(__file__).resolve().parents[4] / ".lore/work/games/company-of-unlikely-heroes/art"
SUPPLEMENTS = Path(__file__).resolve().with_name("supplements")


def rig_name(role, master):
    actor = master.get("source_actor", role.title())
    return master.get("rig_name", f"{actor}_Rig")


def action_name(role, master, action):
    prefix = master.get("action_prefix", master.get("source_actor", role.title()))
    return f"{prefix} | {action}" if prefix else action


def manifest_supplements(master, shelf_sources=()):
    """List the extra approved sources separately from the primary model."""
    library = master.get("motion_library")
    sources = ([library] if library else []) + list(shelf_sources)
    return [{"source": "art/" + source["source"], "sha256": source["sha256"]} for source in sources]


def capture_config(master):
    size = master.get("capture_size", 320)
    if type(size) is not int or size < 320:
        raise ValueError("capture_size must be an integer of at least 320")
    if "capture_anchor" in master and "capture_anchor_x" in master:
        raise ValueError("use capture_anchor or capture_anchor_x, not both")
    anchor = master.get("capture_anchor", [master.get("capture_anchor_x", size // 2), size // 2 + 88])
    if len(anchor) != 2 or any(type(n) is not int or not 0 <= n < size for n in anchor):
        raise ValueError("capture_anchor must contain two pixel coordinates within the canvas")
    return size, list(anchor)


def release_prop_hidden(visible_frames, clip, frame):
    window = visible_frames.get(clip)
    return window is None or not window[0] <= frame <= window[1]


def prop_hidden_clips(visibility, clips):
    """Resolve a prop's optional clip allowlist or denylist."""
    if set(visibility) == {"only"}:
        listed = set(visibility["only"])
        hidden = clips - listed
    elif set(visibility) == {"except"}:
        listed = set(visibility["except"])
        hidden = listed
    else:
        raise ValueError("prop visibility needs either 'only' or 'except'")
    if unknown := listed - clips:
        raise ValueError(f"prop visibility for unknown takes {sorted(unknown)}")
    return hidden


def read_fragment(path, art=ART):
    fragment = json.loads(Path(path).read_text())
    if extra := fragment.get("extra_takes"):
        additional = json.loads((art / extra).read_text())
        if duplicate := fragment["takes"].keys() & additional.keys():
            raise ValueError(f"supplementary takes would replace {sorted(duplicate)}")
        fragment["takes"].update(additional)
    return fragment


def merge_fragment(masters, takes, releases, fragment):
    role = fragment["role"]
    if not isinstance(role, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", role):
        raise ValueError("fragment role must be a lowercase actor identifier")
    if role in masters or role in takes or role in releases:
        raise ValueError(f"fragment cannot replace registered role: {role}")
    masters, takes, releases = dict(masters), dict(takes), dict(releases)
    masters[role] = fragment["master"]
    takes[role] = fragment["takes"]
    if "release" in fragment:
        releases[role] = fragment["release"]
    return masters, takes, releases


def load_fragment(path, masters, takes, releases):
    if path is None:
        return masters, takes, releases
    fragment = read_fragment(path)
    role = fragment["role"]
    if role in masters:
        if (masters[role] == fragment["master"] and takes.get(role) == fragment["takes"]
                and releases.get(role) == fragment.get("release")):
            return masters, takes, releases
        raise ValueError(f"fragment differs from registered role: {role}")
    return merge_fragment(masters, takes, releases, fragment)


def load_registered(directory, masters, takes, releases, roles=None):
    directory = Path(directory)
    names = sorted(roles) if roles is not None else sorted(p.stem for p in directory.glob("*.json"))
    for role in names:
        path = directory / f"{role}.json"
        if not path.is_file():
            continue
        fragment = read_fragment(path)
        if fragment["role"] != role:
            raise ValueError(f"recipe filename does not match role: {path}")
        masters, takes, releases = merge_fragment(masters, takes, releases, fragment)
    return masters, takes, releases


def load_supplement(role, master, stock_takes, directory=SUPPLEMENTS):
    path = directory / f"{role}.json"
    if not path.is_file():
        return None
    spec = json.loads(path.read_text())
    takes = spec["takes"]
    if not takes or stock_takes.keys() & takes.keys():
        raise ValueError(f"{path}: supplementary takes must add distinct clip names")
    capture = {k: master[k] for k in ("source_actor", "rig_name", "action_prefix") if k in master}
    capture |= {k: spec[k] for k in ("action_prefix", "capture_size", "capture_anchor",
                                     "prop_visibility", "release_visible_frames") if k in spec}
    approved = {key: spec[key] for key in ("source", "sha256")}
    if spec["kind"] == "scene":
        capture.update(approved)
        action_sources = []
    elif spec["kind"] == "actions":
        capture.update({key: master[key] for key in ("source", "sha256")})
        action_sources = [approved, *spec.get("additional_actions", [])]
    else:
        raise ValueError(f"{path}: kind must be 'scene' or 'actions'")
    return capture, takes, spec.get("release"), action_sources

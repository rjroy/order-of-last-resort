"""Pose samples layered on the exact, unchanged native takes."""

from typing import NamedTuple


class PoseSample(NamedTuple):
    frame: int  # Drawing time on the derived 24 fps timeline.
    source: float  # Frame in the approved native action.
    turns: tuple = ()  # (bone, model-space X/Y/Z rotation in degrees)
    carried: tuple[str, str] | None = None  # (prop bone, grip bone)


class DerivedTake(NamedTuple):
    title: str
    source_action: str
    end: int  # Exclusive.
    poses: tuple[PoseSample, ...]
    loop: bool = False

    def take(self):
        return self.title, [pose.frame for pose in self.poses], self.end, self.loop

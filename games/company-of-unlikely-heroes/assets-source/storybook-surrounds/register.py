"""Register one native board surround using the shared Field aperture recipe."""

import argparse
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "storybook_field_registration", HERE.parent / "storybook-field" / "register.py"
)
field = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(field)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="native source PNG")
    parser.add_argument("output", type=Path, help="new registered PNG")
    args = parser.parse_args()
    if not args.source.is_file():
        parser.error(f"source does not exist: {args.source}")
    if args.output.exists():
        parser.error(f"refusing to overwrite: {args.output}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    field.register_surround(args.source, args.output)


if __name__ == "__main__":
    main()

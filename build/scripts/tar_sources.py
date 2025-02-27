import argparse
import os
import tarfile


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--exts', nargs='*', default=None)
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', required=True)

    return parser.parse_args()


def main():
    args = parse_args()

    py_srcs = []
    for root, _, files in os.walk(args.input):
        for f in files:
            if not args.exts or f.endswith(tuple(args.exts)):
                py_srcs.append(os.path.join(root, f))

    with tarfile.open(args.output, 'w') as out:
        for f in py_srcs:
            out.add(f, arcname=os.path.relpath(f, args.input))


if __name__ == '__main__':
    main()

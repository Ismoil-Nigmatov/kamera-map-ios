import json
import sys


def frame_line(frame, images):
    index = frame.get("imageIndex")
    image = images[index] if isinstance(index, int) and index < len(images) else {}
    name = image.get("name") or image.get("path", "?").rsplit("/", 1)[-1]
    symbol = frame.get("symbol", "?")
    offset = frame.get("symbolLocation", frame.get("imageOffset", 0))
    return f"    {name}  {symbol}  +{offset}"


for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as handle:
        handle.readline()
        try:
            body = json.loads(handle.read())
        except json.JSONDecodeError:
            print(f"== {path}: not a JSON crash report")
            continue

    print(f"== {path}")
    print("  exception:", json.dumps(body.get("exception")))
    print("  termination:", json.dumps(body.get("termination")))
    if body.get("asi"):
        print("  asi:", json.dumps(body["asi"], ensure_ascii=False)[:3000])

    images = body.get("usedImages", [])
    for frame_list_name in ("lastExceptionBacktrace",):
        frames = body.get(frame_list_name) or []
        if frames:
            print(f"  {frame_list_name}:")
            for frame in frames[:40]:
                print(frame_line(frame, images))

    crashed = next((thread for thread in body.get("threads", []) if thread.get("triggered")), None)
    if crashed:
        print(f"  crashed thread: {crashed.get('name') or crashed.get('queue') or '?'}")
        for frame in crashed.get("frames", [])[:50]:
            print(frame_line(frame, images))

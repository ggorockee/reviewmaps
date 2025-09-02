import sys
from ruamel.yaml import YAML
from pathlib import Path
import argparse


def ensure_path(dct, *keys):
    cur = dct
    for k in keys:
        if k not in cur or cur[k] is None:
            cur[k] = {}
        cur = cur[k]
    return cur

def update_image(file_path: str, service: str, new_tag: str, new_repo: str | None = None) -> bool:
    """
    values.yaml에서 {service}.image.tag (및 선택적으로 repository) 업데이트.
    변경이 있었으면 True, 아니면 False 반환.
    """
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.indent(mapping=2, sequence=4, offset=2)

    p = Path(file_path)
    if not p.exists():
        print(f"❌ Error: file not found: {file_path}")
        sys.exit(1)
        
    data = yaml.load(p.read_text(encoding="utf-8"))
    if data is None:
        data = {}
        
    image = ensure_path(data, service, "image")
    before_tag = image.get("tag")
    before_repo = image.get("repository")
    
    changed = False
    
    if new_repo is not None and new_repo != before_repo:
        image["repository"] = new_repo
        changed = True
        print(f"🔧 {service}.image.repository: {before_repo} -> {new_repo}")


    if new_tag != before_tag:
        image["tag"] = new_tag
        changed = True
        print(f"🔧 {service}.image.tag: {before_tag} -> {new_tag}")

    if changed:
        p.write_text("", encoding="utf-8")  # 일부 환경에서 퍼미션/인코딩 이슈 예방
        with p.open("w", encoding="utf-8") as f:
            yaml.dump(data, f)
        print(f"✅ Updated {file_path} for service='{service}'")
    else:
        print(f"⏭️  No change for {service} (tag/repository unchanged)")

    return changed


def parse_args():
    ap = argparse.ArgumentParser(
        description="Update {service}.image.tag (and optionally repository) in values.yaml"
    )
    ap.add_argument("file", help="path to values.yaml")
    ap.add_argument("service", help="service key (e.g., scrape, server, web, mobile)")
    ap.add_argument("tag", help="new image tag")
    ap.add_argument("--repo", help="(optional) new image repository", default=None)
    return ap.parse_args()


if __name__ == "__main__":
    args = parse_args()
    try:
        changed = update_image(args.file, args.service, args.tag, args.repo)
        # 변경 없으면 0, 변경 있으면 0로 종료 (CI가 실패로 보지 않도록)
        sys.exit(0)
    except KeyError as e:
        print(f"❌ Error: path missing - {e}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        sys.exit(1)

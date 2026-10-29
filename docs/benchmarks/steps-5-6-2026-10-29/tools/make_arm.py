"""Builds one benchmark arm under the scratchpad: app source from git archive, a local engine copy,
and a project that points at that engine. Never writes outside the given arm directory."""
import json, re, shutil, subprocess, sys, unicodedata
from pathlib import Path

SCRATCH = Path('/private/tmp/claude-501/-Users-pedoataidecordeiro-Developer-Verkeier/af5b1f83-2f13-4dc2-bdd1-390330f60fd3/scratchpad')
APP_REPO = Path.home() / 'Developer/Verkeier'
ENGINE_REPO = Path.home() / 'Developer/MobilitéitKit'

def main(arm: str, app_rev: str, engine_rev: str, engine_overlay: list[str]):
    arm_dir = Path(arm).resolve()
    assert SCRATCH in arm_dir.parents, arm_dir
    assert not arm_dir.exists(), f'{arm_dir} exists'
    app, engine = arm_dir / 'app', arm_dir / 'MobiliteitKit'
    app.mkdir(parents=True); engine.mkdir()
    subprocess.run(f'git -C "{APP_REPO}" archive {app_rev} | tar -x -C "{app}"', shell=True, check=True)
    subprocess.run(f'git -C "{ENGINE_REPO}" archive {engine_rev} | tar -x -C "{engine}"', shell=True, check=True)
    # Engine files taken from the working tree (relative paths, in the checkout's own spelling).
    nfc = lambda path: unicodedata.normalize('NFC', path.as_posix())
    archived = {nfc(p.relative_to(engine)): p for p in engine.rglob('*') if p.is_file()}
    for rel in engine_overlay:
        target = archived[unicodedata.normalize('NFC', rel)]
        shutil.copyfile(ENGINE_REPO / rel, target)
    for name in ['luxembourg-walking-manifest.json', 'luxembourg-walking-tiles.tar']:
        src = next(p for p in APP_REPO.glob('*/Resources/' + name) if (p.parent.parent / 'App').exists())
        dst_dir = next(p for p in app.glob('*/Resources') if (p.parent / 'App').exists())
        subprocess.run(['cp', '-c', str(src), str(dst_dir / name)], check=True)
    pbx = app / 'Verkeier.xcodeproj/project.pbxproj'
    text = pbx.read_text()
    block = re.compile(r'(^\t\tE8456D74306913BE00EC1050 /\* XCRemoteSwiftPackageReference "MobiliteitKit" \*/ = \{\n)(.*?)(^\t\t\};\n)', re.S | re.M)
    assert len(block.findall(text)) == 1
    text = block.sub(lambda m: m.group(1) + f'\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = "{engine}";\n' + m.group(3), text)
    pbx.write_text(text)
    resolved = app / 'Verkeier.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    data = json.loads(resolved.read_text())
    data['pins'] = [p for p in data['pins'] if p['identity'] != 'mobiliteitkit']
    resolved.write_text(json.dumps(data, indent=2) + '\n')
    (arm_dir / 'ARM.txt').write_text(f'app {app_rev}, engine {engine_rev} + {engine_overlay}\n')
    print(arm_dir)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:])

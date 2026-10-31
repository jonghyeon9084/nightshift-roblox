"""Compile and exercise current rooftop builder with a limited offline fake."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
test = root / 'tools/advertising/tests'
builder = root / 'tools/advertising/BuildRooftopBillboards.luau'
luau = root / 'tools/world/.validation/luau-0.745'
subprocess.run([str(luau / 'luau-compile.exe'), str(builder.relative_to(root))], cwd=root, check=True, stdout=subprocess.DEVNULL)
bundle = (test / 'rooftop-fake.luau').read_text(encoding='utf-8-sig')
bundle += '\nlocal module=(function()\n' + builder.read_text(encoding='utf-8-sig') + '\nend)()\n'
bundle += (test / 'rooftop.spec.luau').read_text(encoding='utf-8-sig')
with tempfile.TemporaryDirectory(prefix='nightshift-rooftop-') as folder:
    path = Path(folder) / 'test.luau'
    path.write_text(bundle, encoding='utf-8')
    subprocess.run([str(luau / 'luau.exe'), str(path)], check=True)

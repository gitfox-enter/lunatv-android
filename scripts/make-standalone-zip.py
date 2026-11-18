"""Build assets/lunatv.zip from the Next standalone output (v2).

pnpm's standalone output symlinks top-level packages (next, react, ...) into
its .pnpm store. This walker writes REAL file bytes under EVERY reachable
path — the symlink's own path (node_modules/next/...) AND the store path
(node_modules/.pnpm/...) — so the extracted tree on the phone is fully
self-contained with no symlinks at all (Bun resolves node_modules/next
directly). Cycles are guarded by the chain of realpaths on the current walk.
"""
import os
import zipfile

ROOT = r"D:\WorkBuddy\lunatv-port"
src = os.path.join(ROOT, r"vendor\lunatv\.next\standalone")
dst = os.path.join(ROOT, r"lunatv-android\app\src\main\assets\lunatv.zip")

count = 0
MAX_FILES = 60000


def walk_add(dirpath, relbase, chain, zf):
    global count
    if count > MAX_FILES:
        return
    rp = os.path.realpath(dirpath)
    if rp in chain:
        return  # cycle
    chain = chain | {rp}
    for entry in os.listdir(dirpath):
        p = os.path.join(dirpath, entry)
        relrel = (relbase + "/" + entry) if relbase else entry
        if os.path.isdir(p):
            walk_add(p, relrel, chain, zf)
        else:
            relrel = relrel.replace(os.sep, "/")
            zinfo = zipfile.ZipInfo(relrel, date_time=(2026, 11, 17, 0, 0, 0))
            zinfo.compress_type = zipfile.ZIP_DEFLATED
            zinfo.external_attr = 0o644 << 16
            with open(p, "rb") as f:
                zf.writestr(zinfo, f.read())
            count += 1


written = set()

# Bun does not implement runtime.context.addEventListener (Next's middleware
# sandbox uses it), so every request through middleware 500s. The fix is a
# try/catch around the two calls in next's sandbox context.js. A fresh
# node_modules install loses the edit, so the zip builder re-applies it here —
# this is REQUIRED, not cosmetic.
SANDBOX_REL = "node_modules/next/dist/server/web/sandbox/context.js"
SANDBOX_OLD = (
    'const decorateUnhandledError = getDecorateUnhandledError(runtime);\n'
    '    runtime.context.addEventListener("error", decorateUnhandledError);\n'
    '    const decorateUnhandledRejection = getDecorateUnhandledRejection(runtime);\n'
    '    runtime.context.addEventListener("unhandledrejection", decorateUnhandledRejection);'
)
SANDBOX_NEW = (
    'const decorateUnhandledError = getDecorateUnhandledError(runtime);\n'
    '    // Port patch (Bun): try/catch - Bun\'s vm context lacks addEventListener.\n'
    '    try {\n'
    '      runtime.context.addEventListener("error", decorateUnhandledError);\n'
    '    } catch (e) {}\n'
    '    const decorateUnhandledRejection = getDecorateUnhandledRejection(runtime);\n'
    '    try {\n'
    '      runtime.context.addEventListener("unhandledrejection", decorateUnhandledRejection);\n'
    '    } catch (e) {}'
)


def maybe_patch(content: str, rel: str) -> str:
    if rel.endswith(SANDBOX_REL) and SANDBOX_OLD in content:
        print(f"  [patch] 应用 Bun middleware 补丁: {rel}")
        return content.replace(SANDBOX_OLD, SANDBOX_NEW, 1)
    return content


def write_file(realpath, relrel, zf):
    global count
    relrel = relrel.replace(os.sep, "/")
    if relrel in written:
        return
    written.add(relrel)
    zinfo = zipfile.ZipInfo(relrel, date_time=(2026, 11, 17, 0, 0, 0))
    zinfo.compress_type = zipfile.ZIP_DEFLATED
    zinfo.external_attr = 0o644 << 16
    with open(realpath, "rb") as f:
        content = f.read()
    try:
        content = maybe_patch(content.decode("utf-8"), relrel).encode("utf-8")
    except UnicodeDecodeError:
        pass
    zf.writestr(zinfo, content)
    count += 1


def walk_add(dirpath, relbase, chain, zf):
    global count
    if count > MAX_FILES:
        return
    rp = os.path.realpath(dirpath)
    if rp in chain:
        return  # cycle
    chain = chain | {rp}
    for entry in os.listdir(dirpath):
        p = os.path.join(dirpath, entry)
        relrel = (relbase + "/" + entry) if relbase else entry
        if os.path.isdir(p):
            walk_add(p, relrel, chain, zf)
        else:
            write_file(p, relrel, zf)


def flatten_pnpm(pnpm_dir, zf):
    """Mirror every .pnpm/<pkg>@ver/node_modules/<name> to node_modules/<name>.

    pnpm's isolated layout resolves a package's dependencies through SIBLING
    dirs inside the store (only reachable via the junction's physical path on
    the desktop). The extracted phone tree is all-real-files, so a flat
    node_modules (npm-style) is what makes resolution work there. First
    version of a name wins; top-level entries were written first.
    """
    global count
    added = 0
    for pkg in sorted(os.listdir(pnpm_dir)):
        nm = os.path.join(pnpm_dir, pkg, "node_modules")
        if not os.path.isdir(nm):
            continue
        for name in os.listdir(nm):
            target = os.path.join(nm, name)
            if not os.path.isdir(target):
                continue
            relbase = "node_modules/" + name.replace(os.sep, "/")
            chain = frozenset()
            # walk this package dir without the global visited set — files
            # already written under this relbase are skipped by `written`
            stack = [(target, relbase, chain)]
            while stack:
                d, rb, ch = stack.pop()
                rpd = os.path.realpath(d)
                if rpd in ch:
                    continue
                ch = ch | {rpd}
                try:
                    entries = os.listdir(d)
                except OSError:
                    continue
                for e in entries:
                    p = os.path.join(d, e)
                    rr = (rb + "/" + e) if rb else e
                    if os.path.isdir(p):
                        stack.append((p, rr, ch))
                    else:
                        before = count
                        write_file(p, rr, zf)
                        if count > before:
                            added += 1
    return added


with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    walk_add(src, "", frozenset(), z)
    pnpm = os.path.join(src, "node_modules", ".pnpm")
    if os.path.isdir(pnpm):
        added = flatten_pnpm(pnpm, z)
        print(f"扁平镜像补充: {added} 文件")

print(f"打包完成: {count} 文件, {os.path.getsize(dst):,} bytes")
with zipfile.ZipFile(dst) as z:
    names = z.namelist()
    probes = [
        "server.js",
        "node_modules/next/package.json",
        "node_modules/react/package.json",
        "node_modules/react-dom/package.json",
        "node_modules/styled-jsx/package.json",
        "node_modules/.pnpm/next@14.2.35_@babel+core@7._a9a5fd521b0b0632616fa4cf1340d6c9/node_modules/next/package.json",
        ".next/server/app/page.js",
        ".next/static/",
    ]
    for probe in probes:
        hits = [n for n in names if n == probe or n.startswith(probe)]
        print(f"{probe}: {'OK ' + str(len(hits)) if hits else '缺失!'}")

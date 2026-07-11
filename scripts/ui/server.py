#!/usr/bin/env python3
#
# server.py — local web UI backend for the skill store.
#
# Reads come straight from the manifests + directory scans; every mutation
# shells out to the scripts under scripts/, which stay the single source of
# truth for behavior. Start it via scripts/ui/serve.sh, which generates the
# auth token and opens the browser.
#
# Security model (single user, localhost):
#   - binds 127.0.0.1 only; the Host header must be 127.0.0.1/localhost
#   - every /api request needs X-Auth-Token == $SKILLS_UI_TOKEN
#   - fixed endpoints only; arguments are whitelist-validated and passed as
#     argv arrays (never through a shell)
#   - mutations run one at a time (global lock -> 409 busy)
#
# Usage: SKILLS_UI_TOKEN=<token> python3 server.py [--port <n>]
#        (--port 0 picks a free port; the chosen URL is printed as "ready: <url>")

import hmac
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
STORE_DIR = REPO_ROOT / '.agents' / 'skills'
SCRIPTS_DIR = REPO_ROOT / 'scripts'

TOKEN = os.environ.get('SKILLS_UI_TOKEN', '')
MUT_LOCK = threading.Lock()

HOST_RE = re.compile(r'^(127\.0\.0\.1|localhost)(:\d+)?$')
SEG_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]*$')
REF_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._/-]*$')


class ApiError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def code_root():
    return os.environ.get('SKILLS_CODE_ROOT') or os.path.expanduser('~/Documents/code')


def allowed_roots():
    return [os.path.realpath(code_root()),
            os.path.realpath(os.path.expanduser('~/Documents'))]


# --- reads: manifests + filesystem -------------------------------------------

def read_manifest_skills(path):
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return {}
    return data.get('skills') or {}


def read_plain_lines(path):
    try:
        text = Path(path).read_text()
    except OSError:
        return []
    out = []
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            out.append(line)
    return out


def skill_description(skill_dir):
    try:
        lines = (skill_dir / 'SKILL.md').read_text(errors='replace').splitlines()
    except OSError:
        return None
    if not lines or lines[0].strip() != '---':
        return None
    for line in lines[1:80]:
        if line.strip() == '---':
            break
        if line.startswith('description:'):
            return line.split(':', 1)[1].strip().strip('"\'') or None
    return None


def link_into_store(entry):
    try:
        raw = os.readlink(entry)
    except OSError:
        return False
    if raw.startswith(str(STORE_DIR) + os.sep):
        return True
    return os.path.realpath(entry) == os.path.realpath(STORE_DIR / entry.name)


def scan_project(path):
    links = []
    d = Path(path) / '.agents' / 'skills'
    if d.is_dir():
        for e in sorted(d.iterdir()):
            if e.is_symlink():
                links.append({'name': e.name,
                              'ok': (e / 'SKILL.md').is_file(),
                              'intoStore': link_into_store(e)})
    return {'path': path, 'exists': Path(path).is_dir(), 'links': links}


def scan_global():
    links = []
    d = Path(os.path.expanduser('~')) / '.agents' / 'skills'
    if d.is_dir():
        for e in sorted(d.iterdir()):
            if e.is_symlink() and link_into_store(e):
                links.append({'name': e.name, 'ok': (e / 'SKILL.md').is_file()})
    return {'links': links}


def run_script(rel, args, lock=True, timeout=600):
    argv = [str(SCRIPTS_DIR / rel)] + list(args)
    if lock and not MUT_LOCK.acquire(blocking=False):
        raise ApiError(409, 'busy: another operation is running')
    started = time.monotonic()
    try:
        res = subprocess.run(argv, cwd=str(REPO_ROOT), capture_output=True,
                             text=True, timeout=timeout)
        code, out, err = res.returncode, res.stdout, res.stderr
    except subprocess.TimeoutExpired:
        code, out, err = -1, '', 'timeout after %ss' % timeout
    except OSError as e:
        code, out, err = -1, '', str(e)
    finally:
        if lock:
            MUT_LOCK.release()
    return {'exitCode': code,
            'cmd': ['scripts/' + rel] + list(args),
            'stdout': out,
            'stderr': err,
            'durationMs': int((time.monotonic() - started) * 1000)}


def build_state():
    lock = read_manifest_skills(REPO_ROOT / 'skills-lock.json')
    authored = set(read_plain_lines(REPO_ROOT / 'authored.txt'))
    external = read_manifest_skills(REPO_ROOT / 'external.json')
    registered = read_plain_lines(REPO_ROOT / 'links.txt')

    entries = {}
    non_skill = []
    if STORE_DIR.is_dir():
        for e in sorted(STORE_DIR.iterdir()):
            if e.name.startswith('.'):
                continue
            if (e / 'SKILL.md').is_file() or e.is_symlink():
                entries[e.name] = e
            elif e.is_dir():
                non_skill.append(e.name)
    for name in external:  # in the manifest but not yet materialized
        entries.setdefault(name, STORE_DIR / name)

    projects = [scan_project(p) for p in registered]
    glob = scan_global()

    linked_in = {}
    for proj in projects:
        for l in proj['links']:
            if l['intoStore']:
                linked_in.setdefault(l['name'], []).append(proj['path'])
    for l in glob['links']:
        linked_in.setdefault(l['name'], []).append('GLOBAL')

    skills = []
    for name, entry in sorted(entries.items()):
        if name in external:
            source = 'external'
        elif name in lock:
            source = 'npx'
        elif name in authored:
            source = 'authored'
        else:
            source = 'orphan'
        info = {'name': name,
                'source': source,
                'package': (lock.get(name) or {}).get('source'),
                'description': skill_description(entry),
                'linkedIn': linked_in.get(name, []),
                'external': None}
        if source == 'external':
            meta = external.get(name) or {}
            info['external'] = {
                'repo': meta.get('repo'),
                'ref': meta.get('ref'),
                'skillPath': meta.get('skillPath'),
                'cloneTarget': os.readlink(entry) if entry.is_symlink() else None,
                'symlinkOk': (entry / 'SKILL.md').is_file()}
        skills.append(info)

    by_pkg = {}
    for name, meta in lock.items():
        by_pkg.setdefault(meta.get('source') or '?', []).append(name)
    packages = [{'name': k, 'skills': sorted(v)} for k, v in sorted(by_pkg.items())]

    return {
        'store': {'root': str(REPO_ROOT), 'skills': skills, 'nonSkillDirs': non_skill},
        'packages': packages,
        'projects': projects,
        'global': glob,
        'health': {
            'doctor': run_script('store/doctor.sh', [], lock=False, timeout=60),
            'packagesMd': run_script('store/gen-packages.sh', ['--check'], lock=False, timeout=60),
        },
    }


# --- argument whitelists ------------------------------------------------------

def val_str_list(v, what, validator, limit=200):
    if not isinstance(v, list) or not v or len(v) > limit:
        raise ApiError(400, '%s must be a non-empty list' % what)
    out = []
    for s in v:
        if not isinstance(s, str):
            raise ApiError(400, '%s entries must be strings' % what)
        out.append(validator(s))
    return out


def val_item(s):
    """A skill name or an owner/repo package name."""
    parts = s.split('/')
    if not 1 <= len(parts) <= 2 or not all(SEG_RE.match(p) for p in parts):
        raise ApiError(400, 'bad skill/package name: %r' % s)
    return s


def val_name(s):
    if not SEG_RE.match(s):
        raise ApiError(400, 'bad skill name: %r' % s)
    return s


def val_target(v):
    if not isinstance(v, str):
        raise ApiError(400, 'target must be an absolute path (or ~/…)')
    if v.startswith('~'):
        v = os.path.expanduser(v)
    if not v.startswith('/'):
        raise ApiError(400, 'target must be an absolute path (or ~/…)')
    q = os.path.normpath(v)
    if q in read_plain_lines(REPO_ROOT / 'links.txt'):
        return q
    real = os.path.realpath(q)
    for root in allowed_roots():
        if real == root or real.startswith(root + os.sep):
            return q
    raise ApiError(400, 'target not allowed: must be registered in links.txt '
                        'or live under %s' % code_root())


def val_repo(s):
    if (not isinstance(s, str) or not s or s[0] == '-'
            or any(c.isspace() or ord(c) < 32 for c in s)):
        raise ApiError(400, 'bad repo')
    if re.fullmatch(r'[A-Za-z0-9._-]+/[A-Za-z0-9._-]+', s):
        return s
    if s.startswith(('https://', 'http://', 'git@', 'ssh://', 'file:///')):
        return s
    raise ApiError(400, 'bad repo: expected owner/repo, an https/ssh URL, or file:///')


def val_relpath(s):
    if (not isinstance(s, str) or not s or s[0] in ('/', '-')
            or any(c.isspace() and c != ' ' or ord(c) < 32 for c in s)):
        raise ApiError(400, 'bad path: %r' % s)
    if any(p in ('', '.', '..') for p in s.split('/')):
        raise ApiError(400, 'bad path: %r' % s)
    return s


def val_ref(s):
    if not isinstance(s, str) or not REF_RE.match(s):
        raise ApiError(400, 'bad ref: %r' % s)
    return s


# --- mutation endpoints (fixed argv mapping, one per script) -------------------

def target_or_global(body, args):
    """Append -g or the validated target; exactly one of the two."""
    if body.get('global'):
        if body.get('target'):
            raise ApiError(400, 'pass either target or global, not both')
        args.append('-g')
    else:
        args.append(val_target(body.get('target')))
    return args


def api_link(body):
    args = ['-f'] if body.get('force') else []
    target_or_global(body, args)
    return run_script('project/link-skill.sh',
                      args + val_str_list(body.get('items'), 'items', val_item))


def api_unlink(body):
    args = ['-n'] if body.get('dryRun') else []
    target_or_global(body, args)
    return run_script('project/unlink-skill.sh',
                      args + val_str_list(body.get('items'), 'items', val_item))


def api_mark_authored(body):
    return run_script('store/mark-authored.sh',
                      val_str_list(body.get('names'), 'names', val_name))


def api_external_add(body):
    args = ['-f'] if body.get('force') else []
    if body.get('ref'):
        args += ['-r', val_ref(body['ref'])]
    args += [val_repo(body.get('repo')), val_relpath(body.get('skillPath'))]
    if body.get('name'):
        args.append(val_name(body['name']))
    return run_script('store/add-external.sh', args)


def api_external_remove(body):
    return run_script('store/remove-external.sh',
                      val_str_list(body.get('names'), 'names', val_name))


def api_external_sync(body):
    return run_script('store/sync-external.sh',
                      ['--no-pull'] if body.get('noPull') else [])


def api_register(body):
    args = ['-r'] if body.get('remove') else []
    return run_script('project/register.sh',
                      args + val_str_list(body.get('paths'), 'paths', val_target, limit=50))


def api_prune(body):
    args = ['-n'] if body.get('dryRun') else []
    return run_script('project/prune-skills.sh', target_or_global(body, args))


def api_prune_all(body):
    args = ['-n'] if body.get('dryRun') else []
    if body.get('global'):
        args.append('-g')
    return run_script('project/prune-all.sh', args)


def api_gen_packages(body):
    return run_script('store/gen-packages.sh', [])


def api_doctor(body):
    return run_script('store/doctor.sh', [])


POST_ROUTES = {
    '/api/link': api_link,
    '/api/unlink': api_unlink,
    '/api/mark-authored': api_mark_authored,
    '/api/external/add': api_external_add,
    '/api/external/remove': api_external_remove,
    '/api/external/sync': api_external_sync,
    '/api/register': api_register,
    '/api/prune': api_prune,
    '/api/prune-all': api_prune_all,
    '/api/gen-packages': api_gen_packages,
    '/api/doctor': api_doctor,
}


# --- read endpoints -----------------------------------------------------------

def api_complete_path(query):
    prefix = (query.get('prefix') or [''])[0]
    if prefix.startswith('~'):
        prefix = os.path.expanduser(prefix)
    if not prefix.startswith('/'):
        return {'dirs': [code_root()]}
    base, frag = os.path.split(prefix)
    base_real = os.path.realpath(base)
    if not any(base_real == r or base_real.startswith(r + os.sep)
               for r in allowed_roots()):
        return {'dirs': []}
    dirs = []
    try:
        names = sorted(os.listdir(base))
    except OSError:
        return {'dirs': []}
    for n in names:
        if n.startswith('.') or not n.startswith(frag):
            continue
        full = os.path.join(base, n)
        if os.path.isdir(full):
            dirs.append(full)
        if len(dirs) >= 20:
            break
    return {'dirs': dirs}


SKILLMD_RE = re.compile(r'^/api/skill/([A-Za-z0-9][A-Za-z0-9._-]*)/skillmd$')


# --- HTTP plumbing --------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = 'SkillsUI'
    protocol_version = 'HTTP/1.1'

    def send_json(self, code, obj):
        body = json.dumps(obj).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, code, text, ctype='text/plain'):
        body = text.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', ctype + '; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def guard(self, need_token=True):
        if not HOST_RE.match(self.headers.get('Host', '')):
            raise ApiError(403, 'bad Host header')
        if need_token:
            tok = self.headers.get('X-Auth-Token', '')
            if not (TOKEN and hmac.compare_digest(tok, TOKEN)):
                raise ApiError(401, 'missing or wrong X-Auth-Token')

    def read_body(self):
        if not self.headers.get('Content-Type', '').startswith('application/json'):
            raise ApiError(415, 'Content-Type must be application/json')
        try:
            n = int(self.headers.get('Content-Length') or 0)
        except ValueError:
            n = 0
        if not 0 < n <= 65536:
            raise ApiError(400, 'bad Content-Length')
        try:
            body = json.loads(self.rfile.read(n))
        except ValueError:
            raise ApiError(400, 'invalid JSON body')
        if not isinstance(body, dict):
            raise ApiError(400, 'body must be a JSON object')
        return body

    def do_GET(self):
        try:
            url = urllib.parse.urlparse(self.path)
            path = urllib.parse.unquote(url.path)
            if path in ('/', '/index.html'):
                self.guard(need_token=False)
                try:
                    html = (SCRIPT_DIR / 'index.html').read_text()
                except OSError:
                    raise ApiError(500, 'index.html missing next to server.py')
                return self.send_text(200, html, 'text/html')
            if not path.startswith('/api/'):
                raise ApiError(404, 'not found')
            self.guard()
            if path == '/api/state':
                return self.send_json(200, build_state())
            if path == '/api/complete-path':
                return self.send_json(200, api_complete_path(
                    urllib.parse.parse_qs(url.query)))
            m = SKILLMD_RE.match(path)
            if m:
                f = STORE_DIR / m.group(1) / 'SKILL.md'
                if not f.is_file():
                    raise ApiError(404, 'no such skill')
                return self.send_text(200, f.read_text(errors='replace'))
            raise ApiError(404, 'not found')
        except ApiError as e:
            self.send_json(e.code, {'error': str(e)})
        except Exception as e:  # keep the server alive; surface the cause
            self.send_json(500, {'error': '%s: %s' % (type(e).__name__, e)})

    def do_POST(self):
        try:
            path = urllib.parse.unquote(urllib.parse.urlparse(self.path).path)
            self.guard()
            handler = POST_ROUTES.get(path)
            if handler is None:
                raise ApiError(404, 'not found')
            self.send_json(200, handler(self.read_body()))
        except ApiError as e:
            self.send_json(e.code, {'error': str(e)})
        except Exception as e:
            self.send_json(500, {'error': '%s: %s' % (type(e).__name__, e)})


def main(argv):
    port = 7331
    i = 0
    while i < len(argv):
        if argv[i] in ('-h', '--help'):
            print(__doc__ or 'see scripts/ui/serve.sh')
            return 0
        if argv[i] == '--port' and i + 1 < len(argv):
            port = int(argv[i + 1])
            i += 2
            continue
        print('error: unknown option: %s' % argv[i], file=sys.stderr)
        return 2
    if not TOKEN:
        print('error: SKILLS_UI_TOKEN not set; start via scripts/ui/serve.sh',
              file=sys.stderr)
        return 2
    srv = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    print('ready: http://127.0.0.1:%d/' % srv.server_address[1], flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

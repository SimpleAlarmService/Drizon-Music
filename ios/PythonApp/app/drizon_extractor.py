"""Entry point called from Swift: one JSON request in, one JSON response out.

    handle('{"op": "search", "query": "...", "limit": 20}')
    handle('{"op": "stream", "videoId": "...", "clientType": "WEB", "quality": "high"}')
    handle('{"op": "update"}')   # fetch newer yt-dlp from PyPI; applies on next launch

Never raises: always returns {"ok": true, "data": ...} or {"ok": false, "error": "..."}.
"""
from __future__ import annotations

import glob
import hashlib
import json
import os
import sys
import traceback
import urllib.request

# ── Overlay: newer yt-dlp wheels downloaded at runtime take precedence ────────
# (pure-Python wheels are zip-importable). Must happen before `import yt_dlp`.
_OVERLAY = os.environ.get('DRIZON_OVERLAY_DIR', '')
if _OVERLAY and os.path.isdir(_OVERLAY):
    for _whl in sorted(glob.glob(os.path.join(_OVERLAY, '*.whl')), reverse=True):
        if _whl not in sys.path:
            sys.path.insert(0, _whl)

import drizon_jsc  # noqa: E402,F401  (registers the JavaScriptCore challenge solver)
import yt_dlp  # noqa: E402

# Flutter-side ClientType → yt-dlp YouTube player clients (None = yt-dlp default).
_CLIENTS = {
    'ANDROID': None,
    'WEB': ['web', 'web_safari'],
    'TV': ['tv_samsung', 'tv'],
}

# AVPlayer cannot decode WebM/Opus, so every selector prefers AAC in MP4/M4A (or HLS).
_FORMATS = {
    'low': 'worstaudio[ext=m4a]/bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/ba/b',
    'medium': 'bestaudio[ext=m4a][abr<=130]/bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/ba/b',
    'high': 'bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/ba/b',
}


def _opts(extra=None, client_type='ANDROID'):
    opts = {
        'quiet': True,
        'no_warnings': True,
        'noprogress': True,
        'skip_download': True,
        'noplaylist': True,
        'color': {'stdout': 'never', 'stderr': 'never'},
        'socket_timeout': 20,
        'retries': 2,
        'extractor_retries': 1,
        # No external JS runtime: the JavaScriptCore provider handles challenges.
        'js_runtimes': {},
        'remote_components': [],
        'cachedir': os.environ.get('DRIZON_CACHE_DIR') or False,
    }
    clients = _CLIENTS.get(client_type)
    if clients:
        opts['extractor_args'] = {'youtube': {'player_client': clients}}
    if extra:
        opts.update(extra)
    return opts


def _artist(info) -> str:
    name = info.get('channel') or info.get('uploader') or info.get('artist') or ''
    return name[:-8] if name.endswith(' - Topic') else name


def _fmt_duration(sec: int) -> str:
    return f'{sec // 60}:{sec % 60:02d}'


def _thumb(video_id: str) -> str:
    return f'https://i.ytimg.com/vi/{video_id}/mqdefault.jpg'


def _search(req):
    query = (req.get('query') or '').strip()
    limit = int(req.get('limit') or 20)
    if not query:
        return []
    with yt_dlp.YoutubeDL(_opts({'extract_flat': True})) as ydl:
        info = ydl.extract_info(f'ytsearch{limit}:{query}', download=False)
    out = []
    for e in (info or {}).get('entries') or []:
        vid = e.get('id')
        if not vid or e.get('live_status') in ('is_live', 'is_upcoming'):
            continue
        dur = int(e.get('duration') or 0)
        out.append({
            'videoId': vid,
            'title': e.get('title') or 'Unknown',
            'artist': _artist(e),
            'thumbnail': _thumb(vid),
            'duration': _fmt_duration(dur),
            'durationSec': dur,
        })
    return out


def _stream(req):
    vid = req['videoId']
    fmt = _FORMATS.get(req.get('quality') or 'high', _FORMATS['high'])
    opts = _opts({'format': fmt}, client_type=req.get('clientType') or 'ANDROID')
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(f'https://www.youtube.com/watch?v={vid}', download=False)
    url = info.get('url')
    if not url:  # should not happen with a non-merging selector
        reqf = info.get('requested_formats') or []
        url = (reqf[0].get('url') if reqf else None)
    if not url:
        raise RuntimeError('yt-dlp returned no playable URL')
    return {
        'url': url,
        'headers': {k: str(v) for k, v in (info.get('http_headers') or {}).items()},
        'ext': info.get('ext'),
    }


def _video_formats(info):
    """Normalise yt-dlp formats to the shape all platforms return to Dart:
    {headers, hls, formats: [{url, kind: muxed|video|audio, ext, height, bitrate, vcodec, acodec}]}
    """
    out, hls = [], None
    for f in info.get('formats') or []:
        proto = f.get('protocol') or ''
        vcodec, acodec = f.get('vcodec') or 'none', f.get('acodec') or 'none'
        if proto.startswith('m3u8'):
            # AVPlayer plays YouTube's HLS natively (adaptive, up to 1080p+).
            if hls is None and vcodec != 'none':
                hls = f.get('manifest_url') or f.get('url')
            continue
        if not proto.startswith('http') or not f.get('url'):
            continue  # storyboards (mhtml), DASH manifests, etc.
        if vcodec == 'none' and acodec == 'none':
            continue
        kind = 'muxed' if vcodec != 'none' and acodec != 'none' else ('audio' if vcodec == 'none' else 'video')
        out.append({
            'url': f['url'],
            'kind': kind,
            'ext': f.get('ext') or '',
            'height': int(f.get('height') or 0),
            'bitrate': int((f.get('tbr') or f.get('abr') or 0) * 1000),
            'vcodec': '' if vcodec == 'none' else vcodec,
            'acodec': '' if acodec == 'none' else acodec,
        })
    return {
        'headers': {k: str(v) for k, v in (info.get('http_headers') or {}).items()},
        'hls': hls,
        'formats': out,
        'title': info.get('title'),
        'durationSec': int(info.get('duration') or 0),
    }


def _video(req):
    vid = req['videoId']
    # Any selector works: we return the full format list and Dart chooses.
    opts = _opts({'format': 'b/bv*'}, client_type=req.get('clientType') or 'ANDROID')
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(f'https://www.youtube.com/watch?v={vid}', download=False)
    return _video_formats(info)


def _http_json(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)


def _fetch_wheel(pkg, version=None):
    meta = _http_json(f'https://pypi.org/pypi/{pkg}/{version}/json' if version
                      else f'https://pypi.org/pypi/{pkg}/json')
    ver = meta['info']['version']
    wheel = next(u for u in meta['urls'] if u['packagetype'] == 'bdist_wheel'
                 and u['filename'].endswith('py3-none-any.whl'))
    os.makedirs(_OVERLAY, exist_ok=True)
    dest = os.path.join(_OVERLAY, wheel['filename'])
    if not os.path.exists(dest):
        with urllib.request.urlopen(wheel['url'], timeout=120) as r:
            data = r.read()
        if hashlib.sha256(data).hexdigest() != wheel['digests']['sha256']:
            raise RuntimeError(f'checksum mismatch for {wheel["filename"]}')
        with open(dest + '.tmp', 'wb') as f:
            f.write(data)
        os.replace(dest + '.tmp', dest)
    return ver, meta


def _update(_req):
    if not _OVERLAY:
        raise RuntimeError('overlay directory not configured')
    ver, meta = _fetch_wheel('yt-dlp')
    # yt-dlp pins the exact yt-dlp-ejs it was tested with.
    for dep in meta['info'].get('requires_dist') or []:
        if dep.startswith('yt-dlp-ejs==') and 'extra == \'default\'' in dep:
            _fetch_wheel('yt-dlp-ejs', dep.split('==')[1].split(';')[0].strip())
            break
    # Keep only the newest wheel of each package.
    for pkg in ('yt_dlp-', 'yt_dlp_ejs-'):
        wheels = sorted(glob.glob(os.path.join(_OVERLAY, pkg + '*.whl')))
        for old in wheels[:-1]:
            os.remove(old)
    return {'installed': ver, 'running': yt_dlp.version.__version__,
            'restartRequired': ver != yt_dlp.version.__version__}


def _version(_req):
    return {'ytdlp': yt_dlp.version.__version__}


_OPS = {'search': _search, 'stream': _stream, 'video': _video, 'update': _update, 'version': _version}


def handle(request_json: str) -> str:
    try:
        req = json.loads(request_json)
        return json.dumps({'ok': True, 'data': _OPS[req['op']](req)})
    except BaseException as e:  # noqa: BLE001 — must never propagate into C
        msg = str(e).strip().splitlines()[-1] if str(e).strip() else type(e).__name__
        sys.stderr.write(traceback.format_exc())
        return json.dumps({'ok': False, 'error': msg})

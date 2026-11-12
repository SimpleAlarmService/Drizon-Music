"""Host-side tests for the embedded Python layer (no iPhone needed).

    pip install --target ios/PythonApp/app_packages yt-dlp yt-dlp-ejs   # or run setup_python.sh
    python3 -m unittest discover -s ios/PythonApp/tests -v
"""
import ctypes
import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'app'), str(ROOT / 'app_packages')]

import drizon_extractor as extractor  # noqa: E402
import drizon_jsc as jsc  # noqa: E402
from yt_dlp.extractor.youtube.jsc._registry import _jsc_providers  # noqa: E402


class HandleContract(unittest.TestCase):
    def test_version(self):
        out = json.loads(extractor.handle('{"op": "version"}'))
        self.assertTrue(out['ok'])
        self.assertRegex(out['data']['ytdlp'], r'^\d{4}\.\d{2}\.\d{2}')

    def test_never_raises(self):
        for bad in ('not json', '{}', '{"op": "nope"}', '{"op": "stream"}'):
            out = json.loads(extractor.handle(bad))
            self.assertFalse(out['ok'], bad)
            self.assertTrue(out['error'], bad)

    def test_empty_search_is_empty(self):
        out = json.loads(extractor.handle('{"op": "search", "query": "  "}'))
        self.assertEqual(out, {'ok': True, 'data': []})

    def test_formats_never_pick_webm_first(self):
        # AVPlayer cannot decode WebM/Opus.
        for fmt in extractor._FORMATS.values():
            self.assertTrue(fmt.startswith(('bestaudio[ext=m4a]', 'worstaudio[ext=m4a]')))


class JavaScriptCoreProvider(unittest.TestCase):
    def test_registered(self):
        self.assertIn('JavaScriptCore', _jsc_providers.value)

    def test_native_callbacks_roundtrip_through_ctypes(self):
        """Same mechanism Swift uses: raw C function pointers handed over as integers."""
        libc = ctypes.CDLL(None)
        libc.strdup.restype = ctypes.c_void_p
        libc.strdup.argtypes = [ctypes.c_char_p]
        seen = []

        @ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_char_p)
        def fake_eval(script):
            seen.append(script)
            return libc.strdup(json.dumps({'type': 'ok', 'len': len(script)}).encode())

        free_ptr = ctypes.cast(libc.free, ctypes.c_void_p).value
        eval_ptr = ctypes.cast(fake_eval, ctypes.c_void_p).value
        jsc.install_native(eval_ptr, free_ptr)

        self.assertEqual(json.loads(jsc._evaluate('console.log(1)')), {'type': 'ok', 'len': len('console.log(1)')})
        self.assertEqual(seen, [b'console.log(1)'])
        jsc.install_python(None)

    def test_unavailable_until_installed(self):
        jsc.install_python(None)
        provider_cls = _jsc_providers.value['JavaScriptCore']
        provider = provider_cls.__new__(provider_cls)
        provider._available = True
        self.assertFalse(provider.is_available())
        jsc.install_python(lambda s: '{}')
        self.assertTrue(provider.is_available())
        jsc.install_python(None)


if __name__ == '__main__':
    unittest.main()

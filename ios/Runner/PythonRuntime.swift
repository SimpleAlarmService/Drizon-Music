import Foundation

/// Embedded CPython running yt-dlp (see ios/PythonApp/app/drizon_extractor.py).
///
/// All calls go through `request(_:)`, which runs on a dedicated thread with a
/// large stack: yt-dlp recurses deeply and the default 512 KB dispatch-thread
/// stack is not enough. The GIL is released after startup, so any thread may call.
final class PythonRuntime {
    static let shared = PythonRuntime()

    struct PythonError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let startLock = NSLock()
    private var started = false

    // MARK: Public

    /// Start the interpreter in the background so the first search isn't slow.
    func warmUp() {
        run { [self] in _ = try? ensureStarted() }
    }

    /// Send {"op": ...} to drizon_extractor.handle and return its `data`.
    func request(_ payload: [String: Any], completion: @escaping (Result<Any, Error>) -> Void) {
        run { [self] in
            do {
                try ensureStarted()
                let json = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
                let out = try callString(module: "drizon_extractor", function: "handle", arg: json)
                guard let obj = try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any] else {
                    throw PythonError(message: "Malformed extractor response")
                }
                if obj["ok"] as? Bool == true {
                    completion(.success(obj["data"] ?? NSNull()))
                } else {
                    throw PythonError(message: obj["error"] as? String ?? "Extractor failed")
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: Threading

    private func run(_ block: @escaping () -> Void) {
        let t = Thread(block: block)
        t.stackSize = 16 * 1024 * 1024
        t.qualityOfService = .userInitiated
        t.start()
    }

    // MARK: Startup

    private func ensureStarted() throws {
        startLock.lock()
        defer { startLock.unlock() }
        if started { return }

        guard let resources = Bundle.main.resourcePath else {
            throw PythonError(message: "Bundle resource path missing")
        }
        let home = resources + "/python"
        let libRoot = home + "/lib"
        guard let pyDir = (try? FileManager.default.contentsOfDirectory(atPath: libRoot))?
            .first(where: { $0.hasPrefix("python3.") }) else {
            throw PythonError(message: "Python standard library not found in bundle (run ios/scripts/setup_python.sh)")
        }
        let stdlib = "\(libRoot)/\(pyDir)"

        let fm = FileManager.default
        let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                 appropriateFor: nil, create: true).appendingPathComponent("ytdlp")
        let caches = try fm.url(for: .cachesDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true).appendingPathComponent("ytdlp")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try fm.createDirectory(at: caches, withIntermediateDirectories: true)

        setenv("PYTHONHOME", home, 1)
        setenv("PYTHONPATH", [stdlib, stdlib + "/lib-dynload", resources + "/app", resources + "/app_packages"]
            .joined(separator: ":"), 1)
        // The app bundle is read-only, so bytecode goes to the Caches directory instead.
        // yt-dlp has thousands of extractor modules; without this cache every launch
        // would re-compile them all.
        setenv("PYTHONPYCACHEPREFIX", caches.appendingPathComponent("pycache").path, 1)
        setenv("PYTHONUNBUFFERED", "1", 1)
        setenv("DRIZON_OVERLAY_DIR", support.path, 1)
        setenv("DRIZON_CACHE_DIR", caches.path, 1)
        // iOS has no system CA bundle for Python's ssl module; certifi ships one in app_packages.
        setenv("SSL_CERT_FILE", resources + "/app_packages/certifi/cacert.pem", 1)

        Py_InitializeEx(0) // 0: don't install signal handlers
        guard Py_IsInitialized() != 0 else {
            throw PythonError(message: "Py_Initialize failed")
        }

        // Importing drizon_extractor registers the JavaScriptCore challenge solver;
        // hand it our evaluator before anything else runs.
        let evalAddr = UInt64(UInt(bitPattern: unsafeBitCast(drizonJSEval, to: Int.self)))
        let freeAddr = UInt64(UInt(bitPattern: unsafeBitCast(drizonJSFree, to: Int.self)))
        try callInstallNative(evalAddr: evalAddr, freeAddr: freeAddr)

        _ = PyEval_SaveThread() // release the GIL; callers use PyGILState_Ensure
        started = true
    }

    // MARK: C-API helpers (each acquires the GIL)

    private func callInstallNative(evalAddr: UInt64, freeAddr: UInt64) throws {
        let gil = PyGILState_Ensure()
        defer { PyGILState_Release(gil) }
        guard let mod = PyImport_ImportModule("drizon_jsc") else { throw lastError("import drizon_jsc") }
        defer { Py_DecRef(mod) }
        guard let fn = PyObject_GetAttrString(mod, "install_native") else { throw lastError("install_native") }
        defer { Py_DecRef(fn) }
        guard let args = PyTuple_New(2) else { throw lastError("tuple") }
        defer { Py_DecRef(args) }
        PyTuple_SetItem(args, 0, PyLong_FromUnsignedLongLong(evalAddr)) // steals
        PyTuple_SetItem(args, 1, PyLong_FromUnsignedLongLong(freeAddr))
        guard let res = PyObject_Call(fn, args, nil) else { throw lastError("install_native call") }
        Py_DecRef(res)
    }

    private func callString(module: String, function: String, arg: String) throws -> String {
        let gil = PyGILState_Ensure()
        defer { PyGILState_Release(gil) }
        guard let mod = PyImport_ImportModule(module) else { throw lastError("import \(module)") }
        defer { Py_DecRef(mod) }
        guard let fn = PyObject_GetAttrString(mod, function) else { throw lastError(function) }
        defer { Py_DecRef(fn) }
        guard let args = PyTuple_New(1) else { throw lastError("tuple") }
        defer { Py_DecRef(args) }
        guard let pyArg = PyUnicode_FromString(arg) else { throw lastError("string") }
        PyTuple_SetItem(args, 0, pyArg) // steals
        guard let res = PyObject_Call(fn, args, nil) else { throw lastError("\(module).\(function)") }
        defer { Py_DecRef(res) }
        guard let c = PyUnicode_AsUTF8(res) else { throw lastError("result decode") }
        return String(cString: c)
    }

    /// Caller must hold the GIL. Consumes the pending Python exception, if any.
    private func lastError(_ context: String) -> PythonError {
        var text = context
        if let exc = PyErr_GetRaisedException() {
            if let s = PyObject_Str(exc), let c = PyUnicode_AsUTF8(s) {
                text += ": " + String(cString: c)
            }
            Py_DecRef(exc)
        }
        return PythonError(message: text)
    }
}

import Foundation
import JavaScriptCore

/// Evaluates yt-dlp's EJS challenge-solver scripts with the system JavaScriptCore.
///
/// The script is a self-contained program that ends with
/// `console.log(JSON.stringify(jsc({...})))`, so we only need to provide a
/// `console` that captures output. Any JS failure becomes the error JSON that
/// yt-dlp's solver understands: {"type": "error", "error": "..."}.
enum JSSolver {
    static func evaluate(_ script: String) -> String {
        guard let context = JSContext() else {
            return errorJSON("Could not create JSContext")
        }
        var output = ""
        var failure: String?

        context.exceptionHandler = { _, exception in
            failure = exception?.toString() ?? "Unknown JavaScript exception"
        }
        let emit: @convention(block) (String) -> Void = { line in
            output += line + "\n"
        }
        context.setObject(unsafeBitCast(emit, to: AnyObject.self), forKeyedSubscript: "__drizonEmit" as NSString)
        context.evaluateScript("""
        var console = {
          log: function () { __drizonEmit(Array.prototype.join.call(arguments, ' ')); },
          warn: function () {}, error: function () {}, info: function () {}, debug: function () {}
        };
        """)

        context.evaluateScript(script)

        if let failure { return errorJSON(failure) }
        if output.isEmpty { return errorJSON("Solver produced no output") }
        return output
    }

    private static func errorJSON(_ message: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: ["type": "error", "error": message])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? #"{"type":"error","error":"unknown"}"#
    }
}

// C-callable entry points handed to Python as raw function pointers (see
// drizon_jsc.install_native). Global `let`s keep them alive for the process lifetime.
let drizonJSEval: @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? = { script in
    guard let script else { return nil }
    return strdup(JSSolver.evaluate(String(cString: script)))
}

let drizonJSFree: @convention(c) (UnsafeMutableRawPointer?) -> Void = { pointer in
    free(pointer)
}

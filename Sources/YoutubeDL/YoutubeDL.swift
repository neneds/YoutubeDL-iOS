//
//  Copyright (c) 2020 Changbeom Ahn
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation
import PythonKit
import PythonSupport
import AVFoundation

public typealias TimeRange = Range<TimeInterval>

// https://github.com/pvieito/PythonKit/pull/30#issuecomment-751132191
let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)

func loadSymbol<T>(_ name: String) -> T {
    unsafeBitCast(dlsym(RTLD_DEFAULT, name), to: T.self)
}

let Py_IsInitialized: @convention(c) () -> Int32 = loadSymbol("Py_IsInitialized")

public struct Info: Codable {
    public var id: String
    public var title: String
    public var formats: [Format]
    public var description: String?
    public var upload_date: String?
    public var uploader: String?
    public var uploader_id: String?
    public var uploader_url: String?
    public var channel_id: String?
    public var channel_url: String?
    public var duration: Int
    public var view_count: Int?
    public var average_rating: Double?
    public var age_limit: Int?
    public var webpage_url: String?
    public var categories: [String]?
    public var tags: [String]?
    public var playable_in_embed: Bool?
    public var is_live: Bool?
    public var was_live: Bool?
    public var live_status: String?
    public var release_timestamp: Int?
    
    public struct Chapter: Codable {
        public var title: String?
        public var start_time: TimeInterval?
        public var end_time: TimeInterval?
    }
    
    public var chapters: [Chapter]?
    public var like_count: Int?
    public var channel: String?
    public var availability: String?
    public var __post_extractor: String?
    public var original_url: String?
    public var webpage_url_basename: String
    public var extractor: String?
    public var extractor_key: String?
    public var playlist: [String]?
    public var playlist_index: Int?
    public var thumbnail: String?
    public var display_id: String?
    public var duration_string: String?
    public var requested_subtitles: [String]?
    public var __has_drm: Bool?
}

public extension Info {
    var safeTitle: String { title.replacingOccurrences(of: "/", with: "_") }
}

public struct Format: Codable {
    public var asr: Int?
    public var filesize: Int?
    public var format_id: String
    public var format_note: String
    public var fps: Int?
    public var height: Int?
    public var quality: Int?
    public var tbr: Double?
    public var url: String
    public var width: Int?
    public var language: String?
    public var language_preference: Int?
    public var ext: String
    public var vcodec: String
    public var acodec: String
    public var dynamic_range: String?
    public var abr: Double?
    public var vbr: Double?
    
    public struct DownloaderOptions: Codable {
        public var http_chunk_size: Int
    }
    
    public var downloader_options: DownloaderOptions?
    public var container: String?
    public var `protocol`: String
    public var audio_ext: String
    public var video_ext: String
    public var format: String
    public var resolution: String
    public var http_headers: [String: String]
}

let chunkSize: Int64 = 10_485_760 // https://github.com/yt-dlp/yt-dlp/blob/720c309932ea6724223d0a6b7781a0e92a74262c/yt_dlp/extractor/youtube.py#L2552

public extension Format {
    var urlRequest: URLRequest? {
        guard let url = URL(string: url) else {
            return nil
        }
        var request = URLRequest(url: url)
        for (field, value) in http_headers {
            request.addValue(value, forHTTPHeaderField: field)
        }
        
        return request
    }
    
    var isAudioOnly: Bool { vcodec == "none" }
    
    var isVideoOnly: Bool { acodec == "none" }
}

public let defaultOptions: PythonObject = [
    "format": "best,best[height<=720],best[height<=480]",
    "nocheckcertificate": true,
    "verbose": true,
]

public enum YoutubeDLError: Error {
    case noPythonModule
    case canceled
}

open class YoutubeDL: NSObject {
    public struct Options: OptionSet, Codable {
        public let rawValue: Int
        
        public static let noRemux       = Options(rawValue: 1 << 0)
        public static let noTranscode   = Options(rawValue: 1 << 1)
        public static let chunked       = Options(rawValue: 1 << 2)
        public static let background    = Options(rawValue: 1 << 3)

        public static let all: Options = [.noRemux, .noTranscode, .chunked, .background]
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
    
    struct Download: Codable {
        var formats: [Format]
        var directory: URL
        var safeTitle: String
        var options: Options
        var timeRange: TimeRange?
        var bitRate: Double?
        var transcodePending: Bool
    }
    
    public static var shouldDownloadPythonModule: Bool {
        do {
            _ = try YoutubeDL()
            return false
        }
        catch YoutubeDLError.noPythonModule {
            return true
        }
        catch {
            guard let error = error as? PythonError,
                  case let .exception(e, _) = error,
                  e.description == "No module named 'youtube_dl'" else { // FIXME: better way?
                return false
            }
            return true
        }
    }
    
    public static let latestDownloadURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp")!
    
    public static var pythonModuleURL: URL = {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("io.github.kewlbear.youtubedl-ios") else { fatalError() }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        catch {
            fatalError(error.localizedDescription)
        }
        return directory.appendingPathComponent("yt_dlp")
    }()
        
    public var version: String?
    
    public lazy var downloader = Downloader.shared
    
//    public var videoExists: Bool { FileManager.default.fileExists(atPath: Kind.videoOnly.url.path) }
    
    public lazy var downloadsDirectory: URL = downloader.directory {
        didSet { downloader.directory = downloadsDirectory }
    }
    
    internal var pythonObject: PythonObject?

    internal var options: PythonObject?
    
    lazy var finished: AsyncStream<URL> = {
        AsyncStream { continuation in
            finishedContinuation = continuation
        }
    }()
    
    var finishedContinuation: AsyncStream<URL>.Continuation?
    
    var keepIntermediates = false
        

    func loadPythonModule(downloadPythonModule: Bool = true) async throws -> PythonObject {
        if Py_IsInitialized() == 0 {
            PythonSupport.initialize()
        }
        
        if !FileManager.default.fileExists(atPath: Self.pythonModuleURL.path) {
            guard downloadPythonModule else {
                throw YoutubeDLError.noPythonModule
            }
            try await Self.downloadPythonModule()
        }
        
        let sys = try Python.attemptImport("sys")
        if !(Array(sys.path) ?? []).contains(Self.pythonModuleURL.path) {
            injectFakePopen()
            
            sys.path.insert(1, Self.pythonModuleURL.path)
        }
        
        let pythonModule = try Python.attemptImport("yt_dlp")
        version = String(pythonModule.version.__version__)
        return pythonModule
    }
    
    private func injectFakePopen() {
        runSimpleString("""
            class Pop:
                def __init__(self, args, bufsize=-1, executable=None,
                             stdin=None, stdout=None, stderr=None,
                             preexec_fn=None, close_fds=True,
                             shell=False, cwd=None, env=None, universal_newlines=None,
                             startupinfo=None, creationflags=0,
                             restore_signals=True, start_new_session=False,
                             pass_fds=(), *, user=None, group=None, extra_groups=None,
                             encoding=None, errors=None, text=None, umask=-1, pipesize=-1):
                    raise OSError("Popen is not supported")
            
                def communicate(self, input=None, timeout=None):
                    pass
            
                def kill(self):
                    pass

                def wait(self):
                    pass

            import subprocess
            subprocess.Popen = Pop
            """)
    }
    
    private func makePythonObject(_ options: PythonObject? = nil, initializePython: Bool = true) async throws -> PythonObject {
        let pythonModule = try await loadPythonModule()
        pythonObject = pythonModule.YoutubeDL(options ?? defaultOptions)
        self.options = options ?? defaultOptions
        return pythonObject!
    }
        
    open func extractInfo(url: URL) async throws -> ([Format], Info) {
        let pythonObject: PythonObject
        if let _pythonObject = self.pythonObject {
            pythonObject = _pythonObject
        } else {
            pythonObject = try await makePythonObject()
        }

        print(#function, url)
        let info = try pythonObject.extract_info.throwing.dynamicallyCall(withKeywordArguments: ["": url.absoluteString, "download": false, "process": true])
//        print(#function, "throttled:", pythonObject.throttled)
        
        let format_selector = pythonObject.build_format_selector(options!["format"])
        let formats_to_download = format_selector(info)
        var formats: [Format] = []
        let decoder = PythonDecoder()
        for format in formats_to_download {
            let format = try decoder.decode(Format.self, from: format)
            formats.append(format)
        }
        
        return (formats, try decoder.decode(Info.self, from: info))
    }
    
  
    fileprivate static func movePythonModule(_ location: URL) throws {
        removeItem(at: pythonModuleURL)
        
        try FileManager.default.moveItem(at: location, to: pythonModuleURL)
    }
    
    public static func downloadPythonModule(from url: URL = latestDownloadURL, completionHandler: @escaping (Swift.Error?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { (location, response, error) in
            guard let location = location else {
                completionHandler(error)
                return
            }
            do {
                try movePythonModule(location)

                completionHandler(nil)
            }
            catch {
                print(#function, error)
                completionHandler(error)
            }
        }
        
        task.resume()
    }
    
    public static func downloadPythonModule(from url: URL = latestDownloadURL) async throws {
        let stopWatch = StopWatch(); defer { stopWatch.report() }
        if #available(iOS 15.0, *) {
            let (location, _) = try await URLSession.shared.download(from: url)
            try movePythonModule(location)
        } else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                downloadPythonModule(from: url) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }
}

let av1CodecPrefix = "av01."

public extension Format {
    var isRemuxingNeeded: Bool { isVideoOnly || isAudioOnly }
    
    var isTranscodingNeeded: Bool {
        self.ext == "mp4"
        ? (self.vcodec).hasPrefix(av1CodecPrefix)
            : self.ext != "m4a"
    }
}

extension URL {
    var part: URL {
        appendingPathExtension("part")
    }
    
    var title: String {
        let name = deletingPathExtension().lastPathComponent
        guard let range = name.range(of: Kind.separator, options: [.backwards]) else { return name }
        return String(name[..<range.lowerBound])
    }
}

extension URLSessionDownloadTask {
    var info: String {
        "\(taskDescription ?? "no task description") \(originalRequest?.value(forHTTPHeaderField: "Range") ?? "no range")"
    }
}

func yt_dlp(argv: [String], progress: (([String: PythonObject]) -> Void)? = nil, log: ((String, String) -> Void)? = nil) async throws {
    let yt_dlp = try await YoutubeDL().loadPythonModule()
    
    let (parser, opts, all_urls, ydl_opts) = try yt_dlp.parse_options.throwing.dynamicallyCall(withKeywordArguments: ["argv": argv])
        .tuple4
    
    // https://github.com/yt-dlp/yt-dlp#adding-logger-and-progress-hook
    
    if let log {
        let MyLogger = PythonClass("MyLogger", members: [
            "debug": PythonInstanceMethod { params in
                let isDebug = String(params[1])!.hasPrefix("[debug] ")
                log(isDebug ? "debug" : "info", String(params[1]) ?? "")
                return Python.None
            },
            "info": PythonInstanceMethod { params in
                log("info", String(params[1]) ?? "")
                return Python.None
            },
            "warning": PythonInstanceMethod { params in
                log("warning", String(params[1]) ?? "")
                return Python.None
            },
            "error": PythonInstanceMethod { params in
                log("error", String(params[1]) ?? "")
                return Python.None
            },
        ])
            .pythonObject
        
        ydl_opts["logger"] = MyLogger()
    }
    
    if let progress {
        let hook = PythonFunction { (d: PythonObject) in
            let dict: [String: PythonObject] = Dictionary(d) ?? [:]
            progress(dict)
            return Python.None
        }
            .pythonObject
        
        ydl_opts["progress_hooks"] = [hook]
    }
    
    let ydl = yt_dlp.YoutubeDL(ydl_opts)
    
    parser.destroy()
    
    try ydl.download.throwing.dynamicallyCall(withArguments: all_urls)
}

//
//  Copyright (c) 2021 Changbeom Ahn
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

import XCTest
@testable import YoutubeDL
import PythonKit
import PythonSupport
    
final class YoutubeDL_iOSTests: XCTestCase {
    func testPy_IsInitialized() {
        XCTAssertEqual(Py_IsInitialized(), 0)
        PythonSupport.initialize()
        XCTAssertEqual(Py_IsInitialized(), 1)
    }
    
    func testExtractInfo() async throws {
        let youtubeDL = YoutubeDL()
        let (formats, info) = try await youtubeDL.extractInfo(url: URL(string: "https://www.youtube.com/watch?v=WdFj7fUnmC0")!)
        print(formats, info)
        XCTAssertEqual(info.title, "YoutubeDL iOS app demo")
        XCTAssertGreaterThan(formats.count, 0)
    }

    func testError() async throws {
        let youtubeDL = YoutubeDL()
        do {
            _ = try await youtubeDL.extractInfo(url: URL(string: "https://apple.com")!)
        } catch {
            guard let pyError = error as? PythonError, case let .exception(exception, traceback: traceback) = pyError else {
                throw error
            }
            print(exception, traceback ?? "nil")
            let message = String(exception.args[0]) ?? ""
            XCTAssert(message.contains("Unsupported URL: "))
        }
    }

    func testPythonDecoder() async throws {
        let youtubeDL = YoutubeDL()
        let (formats, info) = try await youtubeDL.extractInfo(url: URL(string: "https://www.youtube.com/watch?v=WdFj7fUnmC0")!)
        print(formats, info)
    }
    
    func testDirect() async throws {
        print(FileManager.default.currentDirectoryPath)
        try await yt_dlp(argv: [
            "-F",
//            "-f", "bestvideo+bestaudio[ext=m4a]/best",
            "https://m.youtube.com/watch?v=ezEYcU9Pp_w",
            "--no-check-certificates",
        ], progress: { dict in
            print(#function, dict["status"] ?? "no status?", dict["filename"] ?? "no filename?", dict["elapsed"] ?? "no elapsed", dict.keys)
        }, log: { level, message in
            print(#function, level, message)
        })
    }
    
    static var allTests = [
        ("testExtractInfo", testExtractInfo),
    ]
}

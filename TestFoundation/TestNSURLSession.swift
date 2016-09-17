// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//


#if DEPLOYMENT_RUNTIME_OBJC || os(Linux)
import Foundation
import XCTest
#else
import SwiftFoundation
import SwiftXCTest
#endif

class TestURLSession : XCTestCase {

    static var allTests: [(String, (TestURLSession) -> () throws -> Void)] {
        return [
            ("test_getHttp",                test_getHttp),
            ("test_getHttps",               test_getHttps),
            ("test_getGzipped",             test_getGzipped),
            ("test_getDeflated",            test_getDeflated),
            ("test_getDataURIText",         test_getDataURIText),
            ("test_getDataURIBase64",       test_getDataURIBase64),

            ("test_ftp",                    test_ftp),
            ("test_post",                   test_post),
            ("test_postJson",               test_postJson),
            ("test_postStream",             test_postStream),
            ("test_404",                    test_404),
            ("test_basicAuth",              test_basicAuth),
            ("test_basicAuthRetry",         test_basicAuthRetry),
            ("test_digestAuth",             test_digestAuth),
            ("test_digestAuthRetry",        test_digestAuthRetry),
            ("test_redirectChain",          test_redirectChain),
            ("test_modifiedRedirect",       test_modifiedRedirect),
            ("test_blockedRedirect",        test_blockedRedirect),

            ("test_sessionTimeoutPass1",    test_sessionTimeoutPass1),
            ("test_sessionTimeoutPass2",    test_sessionTimeoutPass2),
            ("test_sessionTimeoutFail",     test_sessionTimeoutFail),
            ("test_requestTimeoutPass",     test_requestTimeoutPass),
            ("test_requestTimeoutFail",     test_requestTimeoutFail),

//            ("test_invalidateSession",      test_invalidateSession),
//            ("test_invalidateAndFinishSession", test_invalidateAndFinishSession),
//            ("test_invalidateAndCancelSession", test_invalidateAndCancelSession),
        ]
    }


    //Request data from a URL with one of the 4 data task APIs, verify that the result contains the expected value at the given JSON path
    func test_get(url: String, resultPath: [String], expected: Any) {
        for api in 0..<4 {
            let sess = Session(testCase: self)
            switch api {
                case 0: sess.runDataTask(with: url)
                case 1: sess.runDataTask(with: URLRequest(url: URL(string: url)!))
                case 2: sess.runCallbackDataTask(with: url)
                case 3: sess.runCallbackDataTask(with: URLRequest(url: URL(string: url)!))
                default: fatalError()
            }

            if let expected = expected as? String {
                XCTAssertEqual(expected, sess.jsonString(at: resultPath))
            } else if let expected = expected as? Bool {
                XCTAssertEqual(expected, sess.jsonBool(at: resultPath))
            } else {
                assertionFailure()
            }
        }
    }

    //Request data from a URL with one of the 4 data task APIs, verify it returns the expected string.  
    func test_get(url: String, expected: String) {
        for api in 0..<4 {
            let sess = Session(testCase: self)
            switch api {
                case 0: sess.runDataTask(with: url)
                case 1: sess.runDataTask(with: URLRequest(url: URL(string: url)!))
                case 2: sess.runCallbackDataTask(with: url)
                case 3: sess.runCallbackDataTask(with: URLRequest(url: URL(string: url)!))
                default: fatalError()
            }
            XCTAssertEqual(expected, sess.receivedString)
        }
    }

    //http GET request
    func test_getHttp()         { test_get(url: "http://httpbin.org/get",       resultPath: ["url"],        expected: "http://httpbin.org/get") }
    //https GET request
    func test_getHttps()        { test_get(url: "https://httpbin.org/get",      resultPath: ["url"],        expected: "https://httpbin.org/get") }
    //http GET request returning gzipped body
    func test_getGzipped()      { test_get(url: "https://httpbin.org/gzip",     resultPath: ["gzipped"],    expected: true) }
    //http GET request returning deflated body. Verify we get back the data we expected.
    func test_getDeflated()     { test_get(url: "https://httpbin.org/deflate",  resultPath: ["deflated"],   expected: true) }
    //data URI in urlencoded form
    func test_getDataURIText()  { test_get(url: "data:text/plain;charset=utf-8,%21%40%C2%A3%24%25%5E%26%2A%28%29_%2B", expected: "!@£$%^&*()_+") }
    //data URI in base64 form
    func test_getDataURIBase64(){ test_get(url: "data:text/plain;charset=utf-8;base64,IUDCoyQlXiYqKClfKw==", expected: "!@£$%^&*()_+") }


    //POST some form data to a URL, via both http and https
    //Verify the data was posted as expected, verify the default content-type header was added.
    func test_post() {
        for scheme in ["http", "https"] {
            let body = "something=happening"
            let sess = Session(testCase: self)
            var req = URLRequest(url: URL(string: "\(scheme)://httpbin.org/post")!)
            req.httpMethod = "POST"
            req.httpBody = body.data(using: .ascii)
            sess.runDataTask(with: req)
            XCTAssertEqual(sess.jsonString(at: ["url"]), "\(scheme)://httpbin.org/post")
            XCTAssertEqual(sess.jsonString(at: ["headers","Content-Type"]), "application/x-www-form-urlencoded")
            XCTAssertEqual(sess.jsonString(at: ["form","something"]), "happening")
        }
    }

    //POST some JSON to a URL
    //Verify the data was posted as expected, verify our content-type header was not overridden.
    func test_postJson() {
        let body = "{\"nothing\":\"doing\"}"
        let sess = Session(testCase: self)
        var req = URLRequest(url: URL(string: "http://httpbin.org/post")!)
        req.httpMethod = "POST"
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        sess.runDataTask(with: req)
        XCTAssertEqual(sess.jsonString(at: ["url"]), "http://httpbin.org/post")
        XCTAssertEqual(sess.jsonString(at: ["headers","Content-Type"]), "application/json")
        XCTAssertEqual(sess.jsonString(at: ["json","nothing"]), "doing")
    }

    func test_postStream() {
        let filler = String.init(repeating: "nom", count: 1000)     //~10k
        let body = ("om=" + filler).data(using: .utf8)!

        let sess = Session(testCase: self)
        var req = URLRequest(url: URL(string: "http://httpbin.org/post")!)
        req.httpMethod = "POST"
        req.httpBodyStream = InputStream(data: body)
        sess.runDataTask(with: req)
        XCTAssertEqual(sess.jsonString(at: ["url"]), "http://httpbin.org/post")
        XCTAssertEqual(sess.jsonString(at: ["headers","Content-Type"]), "application/x-www-form-urlencoded")
        XCTAssertEqual(sess.jsonString(at: ["form","om"]), filler)
    }


    //AFAICT, Old-Skool-Foundation's URLRequest.timeoutInterval is somewhat magical.
    //It returns 60 by default, but it does NOT actually take effect and override the session config timeout unless you set it to something yourself, eg:
    //    request.timeoutInterval = request.timeoutInterval
    //Not sure what the default value of '60' actually signifies.
    func test_timeout(sessionTimeout: TimeInterval, requestTimeout: TimeInterval?, shouldSucceed: Bool, url: String = "http://httpbin.org/delay/10") {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = sessionTimeout
        let sess = Session(testCase: self, configuration: config)
        let expect = expectation(description: "Data task completed")
        var result: Error?
        sess.taskDidComplete = { _, error in
            result = error
            expect.fulfill()
        }
        var req = URLRequest(url: URL(string: url)!)
        if let requestTimeout = requestTimeout {
            req.timeoutInterval = requestTimeout
        }
        let task = sess.session.dataTask(with: req)
        task.resume()
        waitForExpectations(timeout: 15)
        if shouldSucceed {
            XCTAssertNil(result)
        } else {
            XCTAssertNotNil(result)
        }
    }

    //Hit a slow URL with a too-short session timeout. Load should fail.
    func test_sessionTimeoutFail() { test_timeout(sessionTimeout: 5,  requestTimeout: nil, shouldSucceed: false) }
    //Hit a slow URL with a long-enough session timeout. Load should succeed.
    func test_sessionTimeoutPass1() { test_timeout(sessionTimeout: 15, requestTimeout: nil, shouldSucceed: true) }
    //URL takes 10s to load, but supplies data at 1s intervals. Session timeout is 5s. Load should succeed (ie. timeout should apply to inactivity, not entire transfer duration)
    func test_sessionTimeoutPass2() { test_timeout(sessionTimeout: 5, requestTimeout: nil, shouldSucceed: true, url: "http://httpbin.org/drip?duration=10&numbytes=10&code=200") }
    //Hit a slow URL with a long-enough session timeout, but a too-short request timeout. Load should fail (ie. request timeout has precedence)
    func test_requestTimeoutFail() { test_timeout(sessionTimeout: 15, requestTimeout: 5,  shouldSucceed: false) }
    //Hit a slow URL with a too-short session timeout, but a long-enough request timeout. Load should succeed (ie. request timeout has precedence)
    func test_requestTimeoutPass() { test_timeout(sessionTimeout: 5,  requestTimeout: 15, shouldSucceed: true) }

    //Hits a URL with either basic or digest auth. Sends the wrong credentials 0 or more times, then the correct ones.
    //Verify we get challenged on wrong credentials, and eventually get the authenticated page.
    func test_auth(type: String, tries: Int) {
        let (user,pass) = ("Get","Schwifty")
        let sess = Session(testCase: self)

        var tries = tries
        sess.taskDidReceiveChallenge = { task, challenge, completion in
            if tries > 1 {
                tries -= 1
                completion(.useCredential, URLCredential(user: "Ehrmagerd", password: "Pehswerd", persistence: .none))
            } else {
                completion(.useCredential, URLCredential(user: user, password: pass, persistence: .none))
            }
        }
        sess.runDataTask(with: "http://httpbin.org/\(type)/\(user)/\(pass)")
        XCTAssertEqual(tries, 1)
        XCTAssertEqual(sess.jsonBool(at: ["authenticated"]), true)
    }

    func test_basicAuth()       { test_auth(type: "basic-auth", tries: 1) }
    func test_basicAuthRetry()  { test_auth(type: "basic-auth", tries: 3) }
    func test_digestAuth()      { test_auth(type: "digest-auth/auth", tries: 1) }
    func test_digestAuthRetry() { test_auth(type: "digest-auth/auth", tries: 3) }

    //GET request returning a 404 status code. Verify we get the correct code reported.
    func test_404() {
        let sess = Session(testCase: self)
        sess.runDataTask(with: "http://httpbin.org/status/404")
        XCTAssertEqual(sess.events.first?.name, "dataTaskDidReceiveResponse")
        let response = sess.events.first!.parameters[1] as! HTTPURLResponse
        XCTAssertEqual(response.statusCode, 404)
    }

    //Hit a chain of 4 * 302 redirections, finally landing at http://httpbin.org/get.
    //Check we get the expected 4 delegate calls, and arrive correctly.
    //Verify that redirection requests inherit timeout from original request.
    func test_redirectChain() {
        let sess = Session(testCase: self)
        sess.taskWillPerformHTTPRedirection = { task, response, newRequest, completion in
            sess.receivedData = nil
            XCTAssertEqual(newRequest.timeoutInterval, task.originalRequest!.timeoutInterval)
            completion(newRequest)
        }
        sess.runDataTask(with: URLRequest(url: URL(string: "http://httpbin.org/redirect/4")!))
        XCTAssertEqual(sess.jsonString(at: ["url"]), "http://httpbin.org/get")
        let numRedirects = sess.events.filter{ $0.name == "taskWillPerformHTTPRedirection" }.count
        XCTAssertEqual(numRedirects, 4)
    }

    //Hits a 302 redirection URL sending us to swift.org. Catch the redirection, and instead go to a httpbin.org page.
    //Check we arrive at the modified destination.
    func test_modifiedRedirect() {
        let sess = Session(testCase: self)
        sess.taskWillPerformHTTPRedirection = { task, response, newRequest, completion in
            sess.receivedData = nil
            let modifiedRequest = URLRequest(url: URL(string: "http://httpbin.org/get?modified_url=yup")!)
            completion(modifiedRequest)
        }
        sess.runDataTask(with: "http://httpbin.org/redirect-to?url=http%3A%2F%2Fswift.org%2F")
        XCTAssertEqual(sess.jsonString(at: ["args","modified_url"]), "yup")
    }

    //Hits a 302 redirection URL sending us to swift.org. Indicate via a delegate method that we don't want to follow it.
    //Check that the 302 itself is what's delivered to us.
    //NB: Right now, corelibs-foundation delivers the response first, *then* the redirect, which is the opposite of Mac/iOS.
    //The latter order is kinda hinted at in the docs but not explicitly promised - it says you can pass nil to the redirect
    //callback, which will cause the 302 to be delivered as response.
    func test_blockedRedirect() {
        let sess = Session(testCase: self)
        sess.taskWillPerformHTTPRedirection = { task, response, newRequest, completion in
            completion(nil)
        }
        sess.runDataTask(with: "http://httpbin.org/redirect-to?url=http%3A%2F%2Fswift.org%2F")
        XCTAssertEqual(sess.eventSequence, "taskWillPerformHTTPRedirection,dataTaskDidReceiveResponse,taskDidComplete")
        if sess.eventSequence == "taskWillPerformHTTPRedirection,dataTaskDidReceiveResponse,taskDidComplete" {
            let response = sess.events[1].parameters[1] as! HTTPURLResponse
            XCTAssertEqual(response.statusCode, 302)
        }
    }

/*
    invalidateAndCancel, finishTasksAndInvalidate not yet implemented.
    How to import DispatchQueue?

    //Create a session, then invalidate it.
    //Ensure we get the right delegate event.
    func test_invalidateSession() {
        let sess = Session(testCase: self)
        let becameInvalid = expectation(description: "Session didBecomeInvalidWithError")
        sess.didBecomeInvalid = { _ in becameInvalid.fulfill() }
        sess.session.invalidateAndCancel()
        waitForExpectations(timeout: 10)
    }

    //Hit a slow-to-respond URL. Before it responds, call finishTasksAndInvalidate on the session.
    //Ensure the task succeeds successfully before the didBecomeInvalid event arrives.
    func test_invalidateAndFinishSession() {
        let sess = Session(testCase: self)
        let session = sess.session!
        DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 1.0) {
            session.finishTasksAndInvalidate()
        }
        sess.runDataTask(with: "http://httpbin.org/delay/2")
        XCTAssertEqual(sess.jsonString(at: ["url"]), "http://httpbin.org/delay/2")
        XCTAssertEqual(sess.events.last?.name, "didBecomeInvalid")
    }

    //Hit a slow-to-respond URL. Before it responds, call finishTasksAndInvalidate on the session.
    //Ensure the task fails with an error before the didBecomeInvalid event arrives.
    func test_invalidateAndCancelSession() {
        let sess = Session(testCase: self)
        let session = sess.session!
        DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 1.0) {
            session.invalidateAndCancel()
        }
        sess.runDataTask(with: "http://httpbin.org/delay/2", expectError: true)
        XCTAssertEqual(sess.events.last?.name, "didBecomeInvalid")
    }
*/

    //Request a file via anonymous FTP, check we get the expected content.
    func test_ftp() {
        let sess = Session(testCase: self)
        sess.runDataTask(with: "ftp://ftp.debian.org/debian/README")
        XCTAssertNotNil(sess.response)
        XCTAssertNotNil(sess.receivedData)
        if let data = sess.receivedData {
            let readme = String(data: data, encoding: .ascii)
            XCTAssertNotNil(readme)
            XCTAssertEqual(readme?.hasPrefix("See http://www.debian.org/ for information about Debian GNU/Linux."), true
            )
        }
    }



    //Records all delegate callbacks, and dispatches them to configurable callbacks.
    class Session: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionDownloadDelegate, URLSessionStreamDelegate {

        weak var testCase: XCTestCase!
        var session: URLSession!

        init(testCase: XCTestCase, configuration: URLSessionConfiguration = URLSessionConfiguration.default) {
            super.init()
            self.testCase = testCase
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        }

        func runDataTask(with request: URLRequest, expectError: Bool = false, timeout: TimeInterval = 8) {
            var request = request
            request.timeoutInterval = timeout
            let expect = testCase.expectation(description: "Data task completed")
            var result: Error?
            self.taskDidComplete = { _, error in
                result = error
                expect.fulfill()
            }
            let task = session.dataTask(with: request)
            task.resume()
            testCase.waitForExpectations(timeout: request.timeoutInterval + 4)
            if expectError {
                XCTAssertNotNil(result)
            } else {
                XCTAssertNil(result)
            }
        }

        func runDataTask(with url: String, expectError: Bool = false) {
            guard let url = URL(string: url) else { fatalError() }
            let expect = testCase.expectation(description: "Data task completed")
            var result: Error?
            self.taskDidComplete = { _, error in
                result = error
                expect.fulfill()
            }
            let task = session.dataTask(with: url)
            task.resume()
            testCase.waitForExpectations(timeout: session.configuration.timeoutIntervalForRequest + 4)
            if expectError {
                XCTAssertNotNil(result)
            } else {
                XCTAssertNil(result)
            }
        }

        func runCallbackDataTask(with request: URLRequest, expectError: Bool = false, timeout: TimeInterval = 8) {
            var request = request
            request.timeoutInterval = timeout
            let expect = testCase.expectation(description: "Data task completed")
            var result: Error?
            let task = session.dataTask(with: request) { data, response, error in
                self.receivedData = data
                self.response = response
                result = error
                expect.fulfill()
            }
            task.resume()
            testCase.waitForExpectations(timeout: request.timeoutInterval + 4)
            if expectError {
                XCTAssertNotNil(result)
            } else {
                XCTAssertNil(result)
            }
        }

        func runCallbackDataTask(with url: String, expectError: Bool = false) {
            guard let url = URL(string: url) else { fatalError() }
            let expect = testCase.expectation(description: "Data task completed")
            var result: Error?
            let task = session.dataTask(with: url) { data, response, error in
                self.receivedData = data
                self.response = response
                result = error
                expect.fulfill()
            }
            task.resume()
            testCase.waitForExpectations(timeout: session.configuration.timeoutIntervalForRequest + 4)
            if expectError {
                XCTAssertNotNil(result)
            } else {
                XCTAssertNil(result)
            }
        }

        var events: [(name: String, parameters: [Any])] = []
        func log(_ name: String, _ parameters: Any...) {
            events.append((name: name, parameters: parameters))
        }

        var eventSequence: String {
            return events.map{ $0.name }.joined(separator: ",")
        }

        var error: Error?
        var receivedData: Data?
        var response: URLResponse?

        //URLSessionDelegate
        var didBecomeInvalid: ((Error?) -> Void)?
        var didReceiveChallenge: ((URLAuthenticationChallenge,(URLSession.AuthChallengeDisposition, URLCredential?)->Void) -> Void)? = { _, completion in completion(.performDefaultHandling, nil) }

        //URLSessionTaskDelegate
        var taskWillPerformHTTPRedirection: ((URLSessionTask, HTTPURLResponse, URLRequest, (URLRequest?)->Void) -> Void)? = { _, _, request, completion in completion(request) }
        var taskDidReceiveChallenge: ((URLSessionTask, URLAuthenticationChallenge, (URLSession.AuthChallengeDisposition, URLCredential?)->Void) -> Void)? = { _, _, completion in completion(.performDefaultHandling, nil) }
        var taskNeedNewBodyStream: ((URLSessionTask, (InputStream?)->Void) -> Void)? = { _, completion in completion(nil) }
        var taskDidSendBodyData: ((URLSessionTask, Int64, Int64, Int64) -> Void)?
        var taskDidComplete: ((URLSessionTask, Error?) -> Void)?

        //URLSessionDataDelegate
        var dataTaskDidReceiveResponse: ((URLSessionDataTask, URLResponse, (URLSession.ResponseDisposition)->Void) -> Void)? = { _, _, completion in completion(.allow) }
        var dataTaskDidBecomeDownloadTask: ((URLSessionDataTask, URLSessionDownloadTask) -> Void)?
        var dataTaskDidBecomeStreamTask: ((URLSessionDataTask, URLSessionStreamTask) -> Void)?
        var dataTaskDidReceiveData: ((URLSessionDataTask, Data) -> Void)?
        var dataTaskWillCacheResponse: ((URLSessionDataTask, CachedURLResponse, (CachedURLResponse?)->Void) -> Void)? = { _, response, completion in completion(response) }

        //URLSessionDownloadDelegate
        var downloadTaskDidFinishDownloading: ((URLSessionDownloadTask, URL) -> Void)?
        var downloadTaskDidWriteData: ((URLSessionDownloadTask, Int64, Int64, Int64) -> Void)?
        var downloadTaskDidResume: ((URLSessionDownloadTask, Int64, Int64) -> Void)?

        //URLSessionStreamDelegate
        var streamTaskWriteClosed: ((URLSessionStreamTask) -> Void)?
        var streamTaskBetterRouteDiscovered: ((URLSessionStreamTask) -> Void)?
        var streamTaskDidBecomeStreams: ((URLSessionStreamTask, InputStream, OutputStream) -> Void)?

        public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
            log("didBecomeInvalid", error)
            self.error = error
            didBecomeInvalid?(error)
        }
        public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            log("didReceiveChallenge")
            didReceiveChallenge?(challenge, completionHandler)
        }
        public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            log("taskWillPerformHTTPRedirection", task, response, request)
            taskWillPerformHTTPRedirection?(task, response, request, completionHandler)
        }
        public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            log("taskDidReceiveChallenge", task, challenge)
            taskDidReceiveChallenge?(task, challenge, completionHandler)
        }
        public func urlSession(_ session: URLSession, task: URLSessionTask, needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
            log("taskNeedNewBodyStream", task)
            taskNeedNewBodyStream?(task, completionHandler)
        }
        public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            log("taskNeedNewBodyStream", task, bytesSent, totalBytesSent, totalBytesExpectedToSend)
            taskDidSendBodyData?(task, bytesSent, totalBytesSent, totalBytesExpectedToSend)
        }
        public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) -> Void {
            log("taskDidComplete", task, error)
            self.error = error
            taskDidComplete?(task, error)
        }
        public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            log("dataTaskDidReceiveResponse", dataTask, response)
            self.response = response
            dataTaskDidReceiveResponse?(dataTask, response, completionHandler)
        }
        public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome downloadTask: URLSessionDownloadTask) {
            log("dataTaskDidBecomeDownloadTask", dataTask, downloadTask)
            dataTaskDidBecomeDownloadTask?(dataTask, downloadTask)
        }
        public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didBecome streamTask: URLSessionStreamTask) {
            log("dataTaskDidBecomeStreamTask", dataTask, streamTask)
            dataTaskDidBecomeStreamTask?(dataTask, streamTask)
        }
        public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            log("dataTaskDidReceiveData", dataTask, data)
            self.receivedData = self.receivedData ?? Data()
            self.receivedData!.append(data)
            dataTaskDidReceiveData?(dataTask, data)
        }
        public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse, completionHandler: @escaping (CachedURLResponse?) -> Void) {
            log("dataTaskWillCacheResponse", dataTask, proposedResponse)
            dataTaskWillCacheResponse?(dataTask, proposedResponse, completionHandler)
        }
        public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            log("downloadTaskDidFinishDownloading", downloadTask, location)
            downloadTaskDidFinishDownloading?(downloadTask, location)
        }
        public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            log("downloadTaskDidWriteData", downloadTask, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
            downloadTaskDidWriteData?(downloadTask, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
        }
        public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
            log("downloadTaskDidResume", downloadTask, fileOffset, expectedTotalBytes)
            downloadTaskDidResume?(downloadTask, fileOffset, expectedTotalBytes)
        }
        public func urlSession(_ session: URLSession, writeClosedFor streamTask: URLSessionStreamTask) {
            log("streamTaskWriteClosed", streamTask)
            streamTaskWriteClosed?(streamTask)
        }
        public func urlSession(_ session: URLSession, betterRouteDiscoveredFor streamTask: URLSessionStreamTask) {
            log("streamTaskBetterRouteDiscovered", streamTask)
            streamTaskBetterRouteDiscovered?(streamTask)
        }
        public func urlSession(_ session: URLSession, streamTask: URLSessionStreamTask, didBecome inputStream: InputStream, outputStream: OutputStream) {
            log("streamTaskDidBecomeStreams", streamTask, inputStream, outputStream)
            streamTaskDidBecomeStreams?(streamTask, inputStream, outputStream)
        }

        //Interpret receivedData as utf8
        var receivedString: String? {
            if let data = receivedData {
                return String(data: data, encoding: .utf8)
            } else {
                return nil
            }
        }
        

        var receivedJSON: Any? {
            guard let data = receivedData else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
        func jsonValue(at path: [Any]) -> Any? {
            guard var currentNode = receivedJSON else { return nil }
            for key in path {
                if let stringKey = key as? String {
                    guard let dictionary = currentNode as? [String: Any], let value = dictionary[stringKey] else { return nil }
                    currentNode = value
                } else if let intKey = key as? Int {
                    guard let array = currentNode as? [Any], intKey >= 0, intKey < array.count else { return nil }
                    currentNode = array[intKey]
                } else {
                    return nil
                }
            }
            return currentNode
        }
        func jsonString(at path: [Any]) -> String? { return jsonValue(at: path) as? String }
        func jsonBool(at path: [Any]) -> Bool? { return jsonValue(at: path) as? Bool }
    }
}

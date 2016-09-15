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
            ("test_GET", test_GET),
            ("test_GET_gzip", test_GET_gzip),
            ("test_data_URI", test_data_URI),
            ("test_POST", test_POST),
            ("test_POST_JSON", test_POST_JSON),
            ("test_404", test_404),
            ("test_basic_auth_1", test_basic_auth_1),
            ("test_basic_auth_2", test_basic_auth_2),
            ("test_digest_auth_1", test_digest_auth_1),
            ("test_digest_auth_2", test_digest_auth_2),
            ("test_redirect_x_4", test_redirect_x_4),
            ("test_modified_redirect", test_modified_redirect),
            ("test_blocked_redirect", test_blocked_redirect),
//            ("test_invalidate_session", test_invalidate_session),
//            ("test_invalidate_and_finish_session", test_invalidate_and_finish_session),
//            ("test_invalidate_and_cancel_session", test_invalidate_and_cancel_session),
            ("test_ftp", test_ftp),
        ]
    }

    //Hit a URL, check we get the expected content.
    func test_GET() {
        for scheme in ["http", "https"] {
            let address = "\(scheme)://httpbin.org/get"
            let sd = SessionDelegate(testCase: self)
            sd.runDataTask(with: address)
            XCTAssertEqual(sd.jsonString(at: ["url"]), address)
        }
    }

    //Hit a URL returning gzipped content, check we get the expected content.
    func test_GET_gzip() {
        let sd = SessionDelegate(testCase: self)
        sd.runDataTask(with: "http://httpbin.org/gzip")
        XCTAssertEqual(sd.jsonBool(at: ["gzipped"]), true)
    }

    func test_data_URI() {
        let addresses = [
            "data:text/plain;charset=utf-8;base64,IUDCoyQlXiYqKClfKw==" : "!@£$%^&*()_+",
            "data:text/plain;charset=utf-8,%21%40%C2%A3%24%25%5E%26%2A%28%29_%2B" : "!@£$%^&*()_+"
        ]
        for (uri, expected) in addresses {
            let sd = SessionDelegate(testCase: self)
            sd.runDataTask(with: uri)
            XCTAssertEqual(sd.receivedString, expected)
        }
    }

    //POST some form data to a URL, via both http and https
    //Verify the data was posted as expected, verify the default content-type header was added.
    func test_POST() {
        for scheme in ["http", "https"] {
            let body = "something=happening"
            let sd = SessionDelegate(testCase: self)
            var req = URLRequest(url: URL(string: "\(scheme)://httpbin.org/post")!)
            req.httpMethod = "POST"
            req.httpBody = body.data(using: .ascii)
            sd.runDataTask(with: req)
            XCTAssertEqual(sd.jsonString(at: ["url"]), "\(scheme)://httpbin.org/post")
            XCTAssertEqual(sd.jsonString(at: ["headers","Content-Type"]), "application/x-www-form-urlencoded")
            XCTAssertEqual(sd.jsonString(at: ["form","something"]), "happening")
        }
    }

    //POST some JSON to a URL
    //Verify the data was posted as expected, verify our content-type header was not overridden.
    func test_POST_JSON() {
        let body = "{\"nothing\":\"doing\"}"
        let sd = SessionDelegate(testCase: self)
        var req = URLRequest(url: URL(string: "http://httpbin.org/post")!)
        req.httpMethod = "POST"
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        sd.runDataTask(with: req)
        XCTAssertEqual(sd.jsonString(at: ["url"]), "http://httpbin.org/post")
        XCTAssertEqual(sd.jsonString(at: ["headers","Content-Type"]), "application/json")
        XCTAssertEqual(sd.jsonString(at: ["json","nothing"]), "doing")
    }

    //Hits a URL with either basic or digest auth. Sends the wrong credentials 0 or more times, then the correct ones.
    //Verify we get challenged on wrong credentials, and eventually get the authenticated page.
    func test_auth(type: String, tries: Int) {
        let (user,pass) = ("Get","Schwifty")
        let sd = SessionDelegate(testCase: self)

        var tries = tries
        sd.taskDidReceiveChallenge = { task, challenge, completion in
            if tries > 1 {
                tries -= 1
                completion(.useCredential, URLCredential(user: "Ehrmagerd", password: "Pehswerd", persistence: .none))
            } else {
                completion(.useCredential, URLCredential(user: user, password: pass, persistence: .none))
            }
        }
        sd.runDataTask(with: "http://httpbin.org/\(type)/\(user)/\(pass)")
        XCTAssertEqual(tries, 1)
        XCTAssertEqual(sd.jsonBool(at: ["authenticated"]), true)
    }
    
    func test_basic_auth_1() { test_auth(type: "basic-auth", tries: 1) }
    func test_basic_auth_2() { test_auth(type: "basic-auth", tries: 3) }
    func test_digest_auth_1() { test_auth(type: "digest-auth/auth", tries: 1) }
    func test_digest_auth_2() { test_auth(type: "digest-auth/auth", tries: 3) }

    //Hit a 404 URL, check we get the right status code back.
    func test_404() {
        let sd = SessionDelegate(testCase: self)
        sd.runDataTask(with: "http://httpbin.org/status/404")
        XCTAssertEqual(sd.events.first?.name, "dataTaskDidReceiveResponse")
        let response = sd.events.first!.parameters[1] as! HTTPURLResponse
        XCTAssertEqual(response.statusCode, 404)
    }

    //Hit a chain of 4 * 302 redirections, finally landing at http://httpbin.org/get.
    //Check we get the expected 4 delegate calls, and arrive correctly.
    func test_redirect_x_4() {
        let sd = SessionDelegate(testCase: self)
        sd.taskWillPerformHTTPRedirection = { task, response, newRequest, completion in
            sd.receivedData = nil
            completion(newRequest)
        }
        sd.runDataTask(with: "http://httpbin.org/redirect/4")
        XCTAssertEqual(sd.jsonString(at: ["url"]), "http://httpbin.org/get")
        let numRedirects = sd.events.filter{ $0.name == "taskWillPerformHTTPRedirection" }.count
        XCTAssertEqual(numRedirects, 4)
    }

    //Hits a 302 redirection URL sending us to swift.org. Catch the redirection, and instead go to a httpbin.org page.
    //Check we arrive at the modified destination.
    func test_modified_redirect() {
        let sd = SessionDelegate(testCase: self)
        sd.taskWillPerformHTTPRedirection = { task, response, newRequest, completion in
            sd.receivedData = nil
            let modifiedRequest = URLRequest(url: URL(string: "http://httpbin.org/get?modified_url=yup")!)
            completion(modifiedRequest)
        }
        sd.runDataTask(with: "http://httpbin.org/redirect-to?url=http%3A%2F%2Fswift.org%2F")
        XCTAssertEqual(sd.jsonString(at: ["args","modified_url"]), "yup")
    }

    //Hits a 302 redirection URL sending us to swift.org. Indicate via a delegate method that we don't want to follow it.
    //Check that the 302 itself is what's delivered to us.
    //NB: Right now, corelibs-foundation delivers the response first, *then* the redirect, which is the opposite of Mac/iOS.
    //The latter order is kinda hinted at in the docs but not explicitly promised - it says you can pass nil to the redirect
    //callback, which will cause the 302 to be delivered as response.
    func test_blocked_redirect() {
        let sd = SessionDelegate(testCase: self)
        sd.taskWillPerformHTTPRedirection = { task, response, newRequest, completion in
            completion(nil)
        }
        sd.runDataTask(with: "http://httpbin.org/redirect-to?url=http%3A%2F%2Fswift.org%2F")
        XCTAssertEqual(sd.eventSequence, "taskWillPerformHTTPRedirection,dataTaskDidReceiveResponse,taskDidComplete")
        if sd.eventSequence == "taskWillPerformHTTPRedirection,dataTaskDidReceiveResponse,taskDidComplete" {
            let response = sd.events[1].parameters[1] as! HTTPURLResponse
            XCTAssertEqual(response.statusCode, 302)
        }
    }

/*
    invalidateAndCancel, finishTasksAndInvalidate not yet implemented.
    How to import DispatchQueue?

    //Create a session, then invalidate it.
    //Ensure we get the right delegate event.
    func test_invalidate_session() {
        let sd = SessionDelegate(testCase: self)
        let becameInvalid = expectation(description: "Session didBecomeInvalidWithError")
        sd.didBecomeInvalid = { _ in becameInvalid.fulfill() }
        sd.session.invalidateAndCancel()
        waitForExpectations(timeout: 10)
    }

    //Hit a slow-to-respond URL. Before it responds, call finishTasksAndInvalidate on the session.
    //Ensure the task succeeds successfully before the didBecomeInvalid event arrives.
    func test_invalidate_and_finish_session() {
        let sd = SessionDelegate(testCase: self)
        let session = sd.session!
        DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 1.0) {
            session.finishTasksAndInvalidate()
        }
        sd.runDataTask(with: "http://httpbin.org/delay/2")
        XCTAssertEqual(sd.jsonString(at: ["url"]), "http://httpbin.org/delay/2")
        XCTAssertEqual(sd.events.last?.name, "didBecomeInvalid")
    }

    //Hit a slow-to-respond URL. Before it responds, call finishTasksAndInvalidate on the session.
    //Ensure the task fails with an error before the didBecomeInvalid event arrives.
    func test_invalidate_and_cancel_session() {
        let sd = SessionDelegate(testCase: self)
        let session = sd.session!
        DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 1.0) {
            session.invalidateAndCancel()
        }
        sd.runDataTask(with: "http://httpbin.org/delay/2", expectError: true)
        XCTAssertEqual(sd.events.last?.name, "didBecomeInvalid")
    }
*/

    //Request a file via anonymous FTP, check we get the expected content.
    func test_ftp() {
        let sd = SessionDelegate(testCase: self)
        sd.runDataTask(with: "ftp://ftp.debian.org/debian/README")
        XCTAssertNotNil(sd.response)
        XCTAssertNotNil(sd.receivedData)
        if let data = sd.receivedData {
            let readme = String(data: data, encoding: .ascii)
            XCTAssertNotNil(readme)
            XCTAssertEqual(readme?.hasPrefix("See http://www.debian.org/ for information about Debian GNU/Linux."), true
            )
        }
    }



    //Records all delegate callbacks, and dispatches them to configurable callbacks.
    class SessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionDownloadDelegate, URLSessionStreamDelegate {

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
            runDataTask(with: URLRequest(url: URL(string: url)!), expectError: expectError)
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

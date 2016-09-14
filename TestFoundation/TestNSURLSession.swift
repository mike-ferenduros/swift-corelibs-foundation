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
            ("test_GET_https", test_GET_https),
            ("test_404", test_404),
            ("test_basic_auth_1", test_basic_auth_1),
            ("test_basic_auth_2", test_basic_auth_2),
            ("test_digest_auth_1", test_digest_auth_1),
            ("test_digest_auth_2", test_digest_auth_2),
            ("test_redirect_x_4", test_redirect_x_4),
            ("test_modified_redirect", test_modified_redirect),
        ]
    }



    //Hit a URL, check we get the expected content.
    func test_GET() {
        let sd = SessionDelegate(testCase: self)
        let error = sd.runDataTask(with: "http://httpbin.org/get")
        XCTAssertNil(error)
        XCTAssertEqual(sd.jsonString(at: ["url"]), "http://httpbin.org/get")
    }

    //Hit an https URL, check we get the expected content.
    func test_GET_https() {
        let sd = SessionDelegate(testCase: self)
        let error = sd.runDataTask(with: "https://httpbin.org/get")
        XCTAssertNil(error)
        XCTAssertEqual(sd.jsonString(at: ["url"]), "https://httpbin.org/get")
    }
    
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
        let error = sd.runDataTask(with: "http://httpbin.org/\(type)/\(user)/\(pass)")
        XCTAssertNil(error)
        XCTAssertEqual(sd.jsonBool(at: ["authenticated"]), true)
    }
    
    func test_basic_auth_1() { test_auth(type: "basic-auth", tries: 1) }
    func test_basic_auth_2() { test_auth(type: "basic-auth", tries: 3) }
    func test_digest_auth_1() { test_auth(type: "digest-auth/auth", tries: 1) }
    func test_digest_auth_2() { test_auth(type: "digest-auth/auth", tries: 3) }

    //Hit a 404 URL, check we get the right status code back.
    func test_404() {
        let sd = SessionDelegate(testCase: self)
        let error = sd.runDataTask(with: "http://httpbin.org/status/404")
        XCTAssertNil(error)
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
        let error = sd.runDataTask(with: "http://httpbin.org/redirect/4")
        XCTAssertNil(error)
        XCTAssertEqual(sd.jsonString(at: ["url"]), "http://httpbin.org/get")
        let numRedirects = sd.events.filter{ $0.name == "taskWillPerformHTTPRedirection" }.count
        XCTAssertEqual(numRedirects, 4)
    }

    //Hits a 302 redirection URL sending us to swift.org. Catch the redirection, and instead go to a httpbin.org page.
    //Check we arrive at the modified destination URL.
    func test_modified_redirect() {
        let sd = SessionDelegate(testCase: self)
        sd.taskWillPerformHTTPRedirection = { task, response, newRequest, completion in
            sd.receivedData = nil
            let modifiedRequest = URLRequest(url: URL(string: "http://httpbin.org/get?modified_url=yup")!)
            completion(modifiedRequest)
        }
        let error = sd.runDataTask(with: "http://httpbin.org/redirect-to?url=http%3A%2F%2Fswift.org%2F")
        XCTAssertNil(error)
        XCTAssertEqual(sd.jsonString(at: ["args","modified_url"]), "yup")
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

        func runDataTask(with request: URLRequest, timeout: TimeInterval = 8) -> Error? {
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
            return result
        }

        func runDataTask(with url: String) -> Error? {
            return runDataTask(with: URLRequest(url: URL(string: url)!))
        }

        var events: [(name: String, parameters: [Any])] = []
        func log(_ name: String, _ parameters: Any...) {
            events.append((name: name, parameters: parameters))
        }

        var eventSequence: String {
            let names = events.map{ $0.name }
            let deduped = names.reduce([]) { (names: [String], name: String) -> [String] in
                if let last = names.last, last == name {
                    return names
                } else {
                    return names + [name]
                }
            }
            return deduped.joined(separator: ",")
        }

        var error: Error?
        var receivedData: Data?

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

        //This is a common enough thing to do that we should make it easy
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

import Foundation
import KeepGreenKit

/// One HTTP/1.1 request, as much of it as the remote API needs.
struct HTTPRequest {
    /// Upper case, e.g. "GET".
    let method: String

    /// Without the query string, e.g. "/v1/status".
    let path: String

    /// Header names in lower case.
    let headers: [String: String]

    let body: Data

    enum ParseResult {
        case incomplete
        case request(HTTPRequest)
        case failure(HTTPResponse)
    }

    static let maxHeaderBytes = 8192
    static let maxBodyBytes = 4096

    /// Parses `buffer` once it holds a whole request. Never reads past Content-Length.
    static func parse(_ buffer: Data) -> ParseResult {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > maxHeaderBytes
                ? .failure(.error(400, "The request headers are too large."))
                : .incomplete
        }

        let headerData = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
        guard headerData.count <= maxHeaderBytes, let headerText = String(data: headerData, encoding: .utf8) else {
            return .failure(.error(400, "Malformed request."))
        }

        var lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else {
            return .failure(.error(400, "Malformed request line."))
        }

        var target = String(requestLine[1])
        if let query = target.firstIndex(of: "?") {
            target = String(target[..<query])
        }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else {
                return .failure(.error(400, "Malformed header."))
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        if headers["transfer-encoding"] != nil {
            return .failure(.error(400, "Chunked request bodies aren't supported. Send a Content-Length."))
        }

        var length = 0
        if let declared = headers["content-length"] {
            guard let value = Int(declared), value >= 0 else {
                return .failure(.error(400, "Invalid Content-Length."))
            }
            length = value
        }
        guard length <= maxBodyBytes else {
            return .failure(.error(400, "The request body is larger than 4 KB."))
        }

        let bodyStart = headerEnd.upperBound
        guard buffer.endIndex - bodyStart >= length else { return .incomplete }

        return .request(HTTPRequest(
            method: String(requestLine[0]).uppercased(),
            path: target,
            headers: headers,
            body: buffer.subdata(in: bodyStart..<(bodyStart + length))))
    }
}

/// A JSON response that closes the connection, as the remote API requires.
struct HTTPResponse {
    let status: Int
    let body: Data

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        // Default keys are camelCase, matching docs/remote-api.md.
        let body = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, body: body)
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        json(RemoteError(error: message), status: status)
    }

    func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(HTTPResponse.reason(for: status))\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"

        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 429: return "Too Many Requests"
        case 503: return "Service Unavailable"
        default: return "Error"
        }
    }
}

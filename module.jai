// SimpleHTTP v0.3
// Smári McCarthy <smari@ecosophy.is>
//
// See README.md for details.
//
// Module parameters:
//   - USE_REGEX:   Whether to depend on the Uniform regex library.
//   - USE_LOGGING: Whether to log accesses.
//
#module_parameters(USE_REGEX := true, USE_LOGGING := true);

HTTP_404_DEFAULT :: "<html><body><h1>404 File not found</h1></body></html>";

HTTPVerbs :: enum_flags {
    GET; POST; PUT; DELETE; PATCH;
    TRACE; OPTIONS; CONNECT; HEAD;
}

HTTPRouteHandler :: #type (client: *HTTPRequest) -> HTTPResponse;

HTTPRoute :: struct {
    path            : string;
    #if USE_REGEX {
        regex_path      : bool;
        regex           : Regexp;
    }
    accept_verbs    : HTTPVerbs;
    handler         : HTTPRouteHandler;
}

HTTPServer :: struct {
    socket          : s32;
    listen_host     : string;
    listen_port     : u16;
    shutdown        : bool;
    routes          : [..]HTTPRoute;
}

HTTPHeader :: struct {
    key             : string;
    value           : string;
}

HTTPRequest :: struct {
    verb            : HTTPVerbs;
    uri             : string;
    protocol        : string;
    headers         : [..]HTTPHeader;
    url_captures    : []string;
    url_params      : Table(string, string);
    body            : string;
    client          : HTTPClientConnection;
}

HTTPResponse :: struct {
    status          : u32;
    headers         : [..]HTTPHeader;
    body            : string;
}

HTTPClientConnection :: struct {
    socket          : s32;
    address         : sockaddr_in;
}

HTTPServerError :: enum {
    NoProblem;     // Not an error!
    Socket;        // Some Socket Error.
    Access;        // Trying to use privileged resources without permission
    AddressInUse;  // Address in use.
    Accept;        // Error accepting connection.
    SocketRead;    // Error reading from client socket.
    RequestTooBig; // We have arbitrary restrictions on request size. Sorry!
    NotHTTP;       // Not a correctly formatted HTTP request.
    UnknownVerb;   // Request had unknown verb associated.
    Spurious;      // Spurious request; probably malformed.
}

BUFFER_MAX :: 65536;

http_register_url :: (server: *HTTPServer, path: string, accept_verbs: HTTPVerbs, handler: HTTPRouteHandler) {
    r : HTTPRoute;
    r.path = path;
    #if USE_REGEX {
        r.regex = compile(r.path);
    }
    r.accept_verbs = accept_verbs;
    r.handler = handler;
    array_add(*server.routes, r);
}


http_get_status_text :: (status: int) -> string {
    // TODO: This is a partial list.
    if status == {
        case 200; return "OK";
        case 400; return "Bad Request";
        case 401; return "Unauthorized";
        case 403; return "Forbidden";
        case 404; return "Not Found";
        case 418; return "I'm a teapot";
        case; return "Confused";
    }
}


http_response_header_add :: (response: *HTTPResponse, header: string, content: string) {
    h : HTTPHeader;
    h.key = copy_string(header);
    h.value = copy_string(content);
    array_add(*response.headers, h);
}


http_send_response :: (request: *HTTPRequest, response: HTTPResponse) {
    write(request.client.socket, "HTTP/1.0 % %\r\n", response.status, http_get_status_text(response.status));
    for h:response.headers {
        write(request.client.socket, "%: %\r\n", h.key, h.value);
    }
    write(request.client.socket, "\r\n");
    write(request.client.socket, response.body);
}


http_handle_request :: (server: *HTTPServer) -> HTTPServerError {
    req : [BUFFER_MAX]u8;
    request := New(HTTPRequest);
    defer free(request);
    client  : HTTPClientConnection;

    client.socket, client.address = accept(server.socket);
    if client.socket < 0 { return .Accept; }
    defer close(client.socket);

    n := read(client.socket, *req, BUFFER_MAX);
    if n < 0           return .SocketRead;
    if n >= BUFFER_MAX return .RequestTooBig;
    if req[0] == 0     return .Spurious;

    request.client = client;

    requestbody := to_string(req);

    found, header, body := split_from_left(requestbody, "\r\n\r\n");
    if !found return .NotHTTP;

    request.body = body;
    headers := split(header, "\r\n");

    for i:1..headers.count-1 {
        h : HTTPHeader;
        found, k, v := split_from_left(headers[i], ":");
        h.key   = copy_string(trim(k));
        h.value = copy_string(trim(v));
        array_add(*request.headers, h);
    }
    defer array_reset(*request.headers);

    firstline := headers[0];
    verb, uri, protocol : string;

    found, verb, firstline  = split_from_left(firstline, " ");
    found, uri, protocol    = split_from_left(firstline, " ");

    response: HTTPResponse;

    if verb == {
        case "GET";     request.verb = .GET;
        case "POST";    request.verb = .POST;
        case "PUT";     request.verb = .PUT;
        case "DELETE";  request.verb = .DELETE;
        case "PATCH";   request.verb = .PATCH;
        case "TRACE";   request.verb = .TRACE;
        case "OPTIONS"; request.verb = .OPTIONS;
        case "CONNECT"; request.verb = .CONNECT;
        case "HEAD";    request.verb = .HEAD;
        case; {
            response.status = 400;
            http_send_response(request, response);
            return .UnknownVerb;
        }
    }

    url_params : string;
    found, uri, url_params  = split_from_left(uri, "?");
    if found {
        parse_url_params(request, url_params);
    }

    request.uri      = copy_string(uri);
    request.protocol = copy_string(protocol);
    defer free(request.uri);
    defer free(request.protocol);
    defer table_reset(*request.url_params);

    for route:server.routes {
        #if USE_REGEX {
            matched, captures := match(request.uri, route.regex);
            defer array_free(captures);
            if matched && (request.verb & route.accept_verbs) {
                request.url_captures = captures;
                response = route.handler(request);
                break;
            }
        } else {
            if request.uri == route.path && (request.verb & route.accept_verbs) {
                response = route.handler(request);
                break;
            }
        }
    }

    if !response.status {
        response.status = 404;
        response.body = HTTP_404_DEFAULT;
    }

    #if USE_LOGGING log("[%] [%] % %\n", to_string(client.address), response.status, request.verb, request.uri);

    http_send_response(request, response);

    //free(response.body);
    array_reset(*response.headers);

    return .NoProblem;
}


http_server_setup :: (listen_host: string, listen_port: u16) -> HTTPServer {
    server : HTTPServer;

    server.listen_host = listen_host;
    server.listen_port = listen_port;

    return server;
}


http_server_run :: (server: *HTTPServer) -> HTTPServerError {
    server.socket = socket(AF_INET, SOCK_STREAM, 0);
    if server.socket < 0 {
        return .Socket;
    }

    optval : u32 = 1;
    if setsockopt(server.socket, SOL_SOCKET, SO_REUSEADDR, *optval, 4) < 0 {
        return .Socket;
    }

    if bind(server.socket, server.listen_host, server.listen_port) < 0 {
        err := errno();
        if err == {
            case EACCES; return .Access;
            case EADDRINUSE; return .AddressInUse;
            case; return .Socket;
        }
    }
    if listen(server.socket, 5) < 0 return .Socket;

    defer close(server.socket);

    while !server.shutdown {
        http_handle_request(server);
    }

    print("Serer shut down.\n");

    return .NoProblem;
}


param_in_query :: (request: *HTTPRequest, param: string) -> bool {
    val, found := table_find(*request.url_params, param);
    return found;
}

get_param_string :: (request: *HTTPRequest, param: string, default: string = "") -> string, bool {
    val, found := table_find(*request.url_params, param);
    if !found return default, false;
    return val, true;
}

get_param_int :: (request: *HTTPRequest, param: string, default: int = 0) -> int, bool {
    val, found := table_find(*request.url_params, param);
    if !found return default, false;
    return string_to_int(val), true;
}

get_param_float :: (request: *HTTPRequest, param: string, default: float = 0.0) -> float, bool {
    val, found := table_find(*request.url_params, param);
    if !found return default, false;
    return string_to_float(val), true;
}


#scope_file

parse_url_params :: (request: *HTTPRequest, params: string) {
    // TODO: Decode URI components correctly.
    paramset := split(params, "&");
    for paramset {
        found, key, value := split_from_left(it, "=");
        if found {
            table_add(*request.url_params, key, value);
        } else {
            log_error("Problematic parameter '%'\n", it);
        }
    }
}


decode_uri_component :: (s: string) {
    regex : Regexp = compile("(%([0-9a-f]{2}))+");
    matched, captures := match(s, regex);
    /*
    enc ? ((s, enc) => {
        let regex = /(%([0-9a-f]{2}))+/gi;
        let res = null, lastIdx = 0, parts = [];
        while (res = regex.exec(s)) {
            parts.push(s.substring(lastIdx, regex.lastIndex - res[0].length));
            parts.push(iconv.decode(new Buffer(res[0].split(/%([0-9a-f]{2})/i).reduce((buff, v) => {
                if (v !== '') buff.push(parseInt(v, 16));
                return buff;
            }, [])), enc));
            lastIdx = regex.lastIndex;
        }
        parts.push(s.substring(lastIdx, s.length));
        return parts.join('');
    })(s, enc) : (s => s.split(/(%u[0-9a-f]{4})/gi).map(v =>
        v.match(/%u[0-9a-f]{4}/gi) ? unescape(v) : decodeURIComponent(v)).join(''))(s);
    */
}


#scope_file
#import "POSIX";
#import "Socket";
#import "Basic";
#import "String";
#import "Hash_Table";
#if USE_REGEX {
    #import "uniform";
}

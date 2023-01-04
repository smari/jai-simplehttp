// SimpleHTTP v0.3.1
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
    server          : *HTTPServer;
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
        case 500; return "Internal server error";
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


http_accept_client :: (server: *HTTPServer) -> *HTTPRequest {
    client  : HTTPClientConnection;

    client.socket, client.address = accept(server.socket);
    if client.socket < 0 {
        return null; 
    }
    request := New(HTTPRequest);
    request.client = client;
    request.server = server;
    return request;
}


http_handle_request :: (request: *HTTPRequest) -> HTTPServerError {
    req : [BUFFER_MAX]u8;

    // TODO: Handle longer requests
    n := read(request.client.socket, *req, BUFFER_MAX);
    if n < 0           return .SocketRead;
    if n >= BUFFER_MAX return .RequestTooBig;
    if req[0] == 0     return .Spurious;

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

    for route:request.server.routes {
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

    #if USE_LOGGING log("[%] [%] % %\n", to_string(request.client.address), response.status, request.verb, request.uri);

    http_send_response(request, response);

    close(request.client.socket);
    free_request(request);
    free_response(response);

    return .NoProblem;
}


free_response :: (response: HTTPResponse) {
    //free(response.body);
    array_reset(*response.headers);
}

free_request :: (request: *HTTPRequest) {
    free(request.uri);
    free(request.protocol);
    for request.headers {
        free(it.key);
        free(it.value);
    }
    array_reset(*request.headers);
    table_reset(*request.url_params);
    deinit(*request.url_params);
    free(request);
}


http_server_setup :: (listen_host: string, listen_port: u16) -> HTTPServer {
    server : HTTPServer;

    server.listen_host = listen_host;
    server.listen_port = listen_port;

    return server;
}


http_server_listen :: (server: *HTTPServer) -> HTTPServerError {
    server.socket = socket(AF_INET, .SOCK_STREAM, 0);
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

    return .NoProblem;  
}


http_server_run_single_threaded :: (server: *HTTPServer) -> HTTPServerError {
    started := http_server_listen(server);
    if started != .NoProblem { return started; }
    defer close(server.socket);

    while !server.shutdown {
        request := http_accept_client(server);
        if request == null continue;
        http_handle_request(server, request);
    }

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

get_param_float_array :: (request: *HTTPRequest, param: string) -> []float, bool {
    val, found := table_find(*request.url_params, param);
    if !found return float.[], false;
    str_vals := split(val, ",");
    vals : []float;
    vals.data  = alloc(str_vals.count * size_of(float));
    vals.count = str_vals.count;
    for str_vals {
        vals[it_index] = string_to_float(it);
    }
    return vals, true;
}

get_param_int_array :: (request: *HTTPRequest, param: string) -> []int, bool {
    val, found := table_find(*request.url_params, param);
    if !found return int.[], false;
    str_vals := split(val, ",");
    vals : []int;
    vals.data  = alloc(str_vals.count * size_of(int));
    vals.count = str_vals.count;
    for str_vals {
        vals[it_index] = string_to_int(it);
    }
    return vals, true;
}

get_param_hex_int_array :: (request: *HTTPRequest, param: string) -> []int, bool {
    val, found := table_find(*request.url_params, param);
    if !found return int.[], false;
    str_vals := split(val, ",");
    vals : []int;
    vals.data  = alloc(str_vals.count * size_of(int));
    vals.count = str_vals.count;
    for str_vals {
        vals[it_index] = string_to_int(it, base=16);
    }
    return vals, true;
}

get_param_string_array :: (request: *HTTPRequest, param: string) -> []string, bool {
    val, found := table_find(*request.url_params, param);
    if !found return string.[], false;
    str_vals := split(copy_string(val), ",");
    return str_vals, true;
}

#scope_file

parse_url_params :: (request: *HTTPRequest, params: string) {
    // TODO: Decode URI components correctly.
    paramset := split(params, "&");
    for paramset {
        found, key, value := split_from_left(it, "=");
        if found {
            key   = decode_uri_component(key);
            value = decode_uri_component(value);
            table_add(*request.url_params, key, value);
        } else {
            log_error("Problematic parameter '%'\n", it);
        }
    }
}


is_hex_digit :: (c: u8) -> bool {
    return (c >= #char "0" && c <= #char "9")
        || (c >= #char "a" && c <= #char "f")
        || (c >= #char "A" && c <= #char "F");
}

#scope_export
decode_uri_component :: (s: string) -> string {
    // Note: We allocate the same length as the
    //       original string, as we are guaranteed
    //       that the decoded string is of equal
    //       or lesser length.
    //       For space efficiency, we could buffer
    //       the output string and allocate exactly
    //       the number of bytes needed, but it 
    //       barely matters...
    in   := s;
    out  : string;
    out.data = alloc(in.count);
    out.count = 1;

    while in.count > 0 {
        if (in[0] == #char "%" && in.count >= 2 
         && is_hex_digit(in[1]) && is_hex_digit(in[2])
        ) {
            a := in[1];
            b := in[2];

            if a >= #char "a"
                a -= #char "a" - #char "A";
            if a >= #char "A"
                a -= #char "A" - 10;
            else
                a -= #char "0";

            if b >= #char "a"
                b -= #char "a" - #char "A";
            if b >= #char "A"
                b -= #char "A" - 10;
            else
                b -= #char "0";

            out[out.count-1] = 16*a+b;
            out.count += 1;
            advance(*in, 3);
        } else if in[0] == #char "+" {
            out[out.count-1] = #char " ";
            out.count += 1;
            advance(*in);
        } else {
            out[out.count-1] = in[0];
            out.count += 1;
            advance(*in);
        }
    }
    out.count -= 1;
    return out;
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

write :: inline (fd: s32, msg: string) -> s64 {
    return write(fd, cast(*void) msg.data, cast(size_t) msg.count);
}

write :: inline (fd: s32, buf: string, args: ..Any) -> s64 {
    tmp := tprint(buf, ..args);
    return write(fd, tmp.data, cast(size_t) tmp.count);
}

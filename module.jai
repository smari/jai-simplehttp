HTTP_404_DEFAULT :: "<html><body><h1>404 File not found</h1></body></html>";

HTTPVerbs :: enum_flags {
    GET; POST; PUT; DELETE; PATCH; 
    TRACE; OPTIONS; CONNECT; HEAD;
}

HTTPRouteHandler :: #type (client: *HTTPRequest) -> HTTPResponse;

HTTPRoute :: struct {
    path            : string;
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
}


BUFFER_MAX :: 65536;


http_register_url :: (server: *HTTPServer, path: string, accept_verbs: HTTPVerbs, handler: HTTPRouteHandler) {
    r : HTTPRoute;
    r.path = path;
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


http_send_response :: (request: *HTTPRequest, response: HTTPResponse) {
    write(request.client.socket, "HTTP/1.0 % %\r\n", response.status, http_get_status_text(response.status));
    for h:response.headers {
        write(request.client.socket, "%: %\r\n", h.key, h.value);
    }
    write(request.client.socket, "\r\n");
    write(request.client.socket, response.body);
    close(request.client.socket);
}


http_handle_request :: (server: *HTTPServer) -> HTTPServerError {
    req : [BUFFER_MAX]u8;
    request := New(HTTPRequest);
    defer free(request);
    client  : HTTPClientConnection;

    client.socket, client.address = accept(server.socket);
    if client.socket < 0 { return .Accept; }

    n := read(client.socket, *req, BUFFER_MAX);
    if n < 0           return .SocketRead;
    if n >= BUFFER_MAX return .RequestTooBig;

    request.client = client;

    requestbody := to_string(req);

    found, header, body := split_from_left(requestbody, "\r\n\r\n");
    request.body = body;
    headers := split(header, "\r\n");

    for i:1..headers.count-1 {
        h : HTTPHeader;
        found, k, v := split_from_left(headers[i], ":");
        h.key = copy_string(trim(k));
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
        case; response.status = 400;
    }

    request.uri      = copy_string(uri);
    request.protocol = copy_string(protocol);
    defer free(request.uri);
    defer free(request.protocol);

    for route:server.routes {
        if request.uri == route.path && (request.verb & route.accept_verbs) {
            response = route.handler(request);
            break;
        }
    }

    if !response.status {
        response.status = 404;
        response.body = HTTP_404_DEFAULT;
    }

    http_send_response(request, response);

    // TODO: Here we leak the memory from the response, mostly the body. 
    //       This is bad! Let's figure out a better way to do this.

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

    return .NoProblem;
}


#scope_file
#import "POSIX";
#import "Socket";
#import "Basic";
#import "String";

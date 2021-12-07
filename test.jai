#import "SimpleHTTP";
#import "Basic";

root :: (client: *HTTPRequest) -> HTTPResponse {
    response : HTTPResponse;
    response.status = 200;
    response.body = "<html><head></head><body>Hello, world!</body></html>";
    return response;
}


post_only :: (client: *HTTPRequest) -> HTTPResponse {
    response : HTTPResponse;
    response.status = 200;
    response.body = "<html><head></head><body>Post response!</body></html>";
    return response;
}


main :: () {
    server := http_server_setup("0.0.0.0", 2101);
    http_register_url(*server, "/", .GET, root);
    http_register_url(*server, "/post/", .POST, post_only);

    print("Starting server on %:%\n", server.listen_host, server.listen_port);
    err := http_server_run(*server);
    if err != .NoProblem {
        print("Server error: %\n", err);
    }
}

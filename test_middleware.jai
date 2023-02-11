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


my_verbose_middleware :: (request: *HTTPRequest) -> HTTPMiddlewareResult {
    // This test middleware will just print out all the request headers.
    for request.headers {
        print("  IN> %: %\n", it.key, it.value);
    } 

    res : HTTPMiddlewareResult;
    res.error = false;
    return res;
}

my_error_middleware :: (request: *HTTPRequest) -> HTTPMiddlewareResult {
    // This test middleware will check if DNT header is set to 1, and
    // reject if it is.
    // To test: 
    //  curl http://localhost:2101/                     # Doesn't reject
    //  curl http://localhost:2101/ --header "DNT:1"    # Rejects

    res : HTTPMiddlewareResult;
    res.error = false;

    for request.headers {
        if it.key == "DNT" {
            res.error = true;
            res.response.status = 400;
            res.response.body = "We want to spy on you, but you won't let us!";
            return res;
        }
    } 

    return res;
}


my_postprocessing_middleware :: (response: *HTTPResponse) -> HTTPMiddlewareResult {
    // This test middleware will just add a response header to the outgoing response
    res : HTTPMiddlewareResult;
    res.error = false;

    http_response_header_add(response, "X-I-Like-Dancing", "But mostly swing");

    return res;
}


my_verbose_response_middleware :: (response: *HTTPResponse) -> HTTPMiddlewareResult {
    // This test middleware will just add a response header to the outgoing response
    res : HTTPMiddlewareResult;
    res.error = false;

    for response.headers {
        print(" OUT< %: %\n", it.key, it.value);
    } 

    return res;
}


main :: () {
    print("Now starting test server:\n");

    server := http_server_setup("0.0.0.0", 2101);

    http_register_request_middleware(*server, my_verbose_middleware);
    http_register_request_middleware(*server, my_error_middleware);

    http_register_response_middleware(*server, my_postprocessing_middleware);
    http_register_response_middleware(*server, my_verbose_response_middleware);

    http_register_url(*server, "/", .GET, root);
    http_register_url(*server, "/post/", .POST, post_only);

    print("Starting server on %:%\n", server.listen_host, server.listen_port);
    err := http_server_run_single_threaded(*server);
    if err != .NoProblem {
        print("Server error: %\n", err);
    }
}


#import "SimpleHTTP"(USE_MIDDLEWARE=false);
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


urldecode_test :: () {
    tests := string.[
        "hello",            "hello",
        "hello+world",      "hello world",
        "hello%20world",    "hello world",
        "%3Chtml%3e",       "<html>"
    ];

    passed := 0;
    failed := 0;

    for i:0..(tests.count/2)-1 {
        in  := tests[2*i];
        out := tests[2*i+1];
        if out != decode_uri_component(in) {
            print("Test: Failed decoding '%'\n", in);
            failed += 1;
        } else {
            passed += 1;
        }
    }
    print("URLDecode test done.\n - Passed: %\n - Failed: %\n", passed, failed);
}

main :: () {
    print("Running some tests:\n");
    urldecode_test();

    print("Now starting test server:\n");

    server := http_server_setup("0.0.0.0", 2101);
    http_register_url(*server, "/", .GET, root);
    http_register_url(*server, "/post/", .POST, post_only);

    print("Starting server on %:%\n", server.listen_host, server.listen_port);
    err := http_server_run_single_threaded(*server);
    if err != .NoProblem {
        print("Server error: %\n", err);
    }
}

#load "module.jai";

root :: (client: *HTTPRequest) -> HTTPResponse {
    response : HTTPResponse;
    response.status = 200;
    response.body = "<html><head></head><body>Hello, world!</body></html>";
    return response;
}


main :: () {
    server := http_server_setup("0.0.0.0", 2101);
    http_register_url(*server, "/", .GET, root);
    http_server_run(*server);
}

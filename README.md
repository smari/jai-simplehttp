# Super basic HTTP server library

A super simple HTTP server library for Jai. 

Not intended to solve all of your problems, but it might allow you
to serve some stuff over HTTP.

This has intentionally been kept as close to oversimplified as possible.
First, because [Cavy](https://github.com/smari/Cavy), which I wrote while
sick with Covid, was never correctly scoped and was kind of silly. But fun.
Second, and more importantly, because these kinds of things tend to get
overly complicated alarmingly fast.

Anyway, enjoy.

## Usage

A very basic example is available in `test.jai`. Compile it with `jai test.jai -import_dir ../` or equivalent.

By default, the library relies on the [Uniform](https://github.com/rluba/uniform) regex library. However,
this dependency is optional and can be turned off with the `USE_REGEX` module parameter. For instance:

```
#import "SimpleHTTP" (USE_REGEX=false);
```

Another parameter (used the same way) is `USE_LOGGING`. It defaults to on, and will cause a `log` call to be made
for each valid HTTP request.

## Middleware

We now support both request and response middleware. This barely counts as simple anymore, but here we are.
Check out `test_middleware.jai` for usage, compiled the same way as `test.jai`.

Middleware can similarly be turned off by setting `USE_MIDDLEWARE` to `false`.

## Author

Smári McCarthy.

## License

Public Domain.

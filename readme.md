
<img align="right" src="doc/qoiz.svg">

A simple and fast implementation of the QOI image format decoder and encoder.

## Examples

```zig
const qoiz = @import("qoiz");

test "image init reader" {
    const file = try fs.cwd().openFile("src/bench/data/dice.qoi", .{});
    defer file.close();

    const image = try qoiz.Image(.rgb).initReader(testing.allocator, file.reader());
    defer image.deinit();
}
```

## Benchmark

```console
$ zig build bench --release=fast -- qoiz 1028
         dice : dec.  1.182ms ±σ  0.046ms | enc.  2.258ms ±σ  1.181ms
     edgecase : dec.  0.015ms ±σ  0.001ms | enc.  0.038ms ±σ  0.015ms
      kodim10 : dec.  3.760ms ±σ  0.136ms | enc.  7.463ms ±σ  3.744ms
      kodim23 : dec.  3.696ms ±σ  0.035ms | enc.  7.384ms ±σ  3.695ms
     qoi_logo : dec.  0.078ms ±σ  0.002ms | enc.  0.188ms ±σ  0.078ms
     testcard : dec.  0.123ms ±σ  0.004ms | enc.  0.255ms ±σ  0.123ms
testcard_rgba : dec.  0.132ms ±σ  0.004ms | enc.  0.271ms ±σ  0.132ms
wikipedia_008 : dec.  9.707ms ±σ  0.167ms | enc. 19.508ms ±σ  9.680ms
         zero : dec.  0.378ms ±σ  0.023ms | enc.  0.772ms ±σ  0.378ms
```

Another library for zig made by @ikskuh
```console
$ zig build bench --release=fast -- zigqoi 1028
         dice : dec.  2.477ms ±σ  0.086ms | enc.  2.617ms ±σ  2.471ms
     edgecase : dec.  0.019ms ±σ  0.001ms | enc.  0.064ms ±σ  0.019ms
      kodim10 : dec.  4.468ms ±σ  0.082ms | enc.  6.644ms ±σ  4.462ms
      kodim23 : dec.  4.502ms ±σ  0.131ms | enc.  6.668ms ±σ  4.486ms
     qoi_logo : dec.  0.117ms ±σ  0.004ms | enc.  0.333ms ±σ  0.117ms
     testcard : dec.  0.162ms ±σ  0.005ms | enc.  0.321ms ±σ  0.162ms
testcard_rgba : dec.  0.178ms ±σ  0.004ms | enc.  0.309ms ±σ  0.178ms
wikipedia_008 : dec. 12.448ms ±σ  0.251ms | enc. 16.965ms ±σ 12.387ms
         zero : dec.  0.542ms ±σ  0.011ms | enc.  1.062ms ±σ  0.542ms
```

Reference implementation in C
```console
$ zig build bench --release=fast -- reference 1028
         dice : dec.  1.236ms ±σ  0.046ms | enc.  1.535ms ±σ  1.235ms
     edgecase : dec.  0.027ms ±σ  0.002ms | enc.  0.037ms ±σ  0.027ms
      kodim10 : dec.  3.230ms ±σ  0.065ms | enc.  3.157ms ±σ  3.226ms
      kodim23 : dec.  3.165ms ±σ  0.055ms | enc.  3.021ms ±σ  3.162ms
     qoi_logo : dec.  0.148ms ±σ  0.005ms | enc.  0.246ms ±σ  0.148ms
     testcard : dec.  0.139ms ±σ  0.005ms | enc.  0.191ms ±σ  0.139ms
testcard_rgba : dec.  0.146ms ±σ  0.005ms | enc.  0.204ms ±σ  0.146ms
wikipedia_008 : dec.  8.343ms ±σ  0.123ms | enc.  9.346ms ±σ  8.329ms
         zero : dec.  0.496ms ±σ  0.015ms | enc.  0.766ms ±σ  0.496ms
```

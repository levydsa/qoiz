
# `qoiz`

A simple implementation of the QOI image format decoder and encoder.

The implementation is centered around the concept of:

- Span
    Group of pixels with the same value.

- Chunks
    Regular QOI Chunk

- Image
    Holds the format and pixels information of a image.

Raw Image -> Span Iterator -> Chunk Iterator -> QOI Image

QOI Image -> Chunk Iterator -> Span Iterator -> Raw Image

## Benchmark

```console
$ zig build bench -Doptimize=ReleaseFast
bench.Impl.reference: 1888ms
        testcard.qoi: 166μs±48
        kodim10.qoi: 3453μs±285
        dice.qoi: 1399μs±276
        wikipedia_008.qoi: 9924μs±723
        zero.qoi: 513μs±95
        edgecase.qoi: 24μs±4
        testcard_rgba.qoi: 181μs±71
        kodim23.qoi: 3430μs±346
        qoi_logo.qoi: 159μs±41
bench.Impl.qoiz: 1955ms
        testcard.qoi: 227μs±81
        kodim10.qoi: 4051μs±488
        dice.qoi: 1765μs±330
        wikipedia_008.qoi: 10768μs±704
        zero.qoi: 667μs±143
        edgecase.qoi: 42μs±13
        testcard_rgba.qoi: 207μs±40
        kodim23.qoi: 4183μs±254
        qoi_logo.qoi: 212μs±69
bench.Impl.zigqoi: 2281ms
        testcard.qoi: 284μs±94
        kodim10.qoi: 5334μs±585
        dice.qoi: 3035μs±353
        wikipedia_008.qoi: 13790μs±869
        zero.qoi: 877μs±217
        edgecase.qoi: 36μs±11
        testcard_rgba.qoi: 231μs±33
        kodim23.qoi: 5518μs±386
        qoi_logo.qoi: 227μs±54
```

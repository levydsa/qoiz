
# `qoiz`

Decoder from the qoi image format.
Encoder isn't ready yet :(

## Benchmark

```console
$ zig build bench -Doptimize=ReleaseFast
bench.Impl.reference: 1881ms
        testcard.qoi: 145μs±36
        kodim10.qoi: 3380μs±190
        dice.qoi: 1358μs±142
        wikipedia_008.qoi: 10150μs±820
        zero.qoi: 484μs±65
        edgecase.qoi: 41μs±21
        testcard_rgba.qoi: 168μs±47
        kodim23.qoi: 3408μs±317
        qoi_logo.qoi: 159μs±42
bench.Impl.qoi: 1965ms
        testcard.qoi: 216μs±66
        kodim10.qoi: 4110μs±347
        dice.qoi: 1672μs±312
        wikipedia_008.qoi: 10548μs±858
        zero.qoi: 677μs±128
        edgecase.qoi: 71μs±44
        testcard_rgba.qoi: 225μs±73
        kodim23.qoi: 4090μs±494
        qoi_logo.qoi: 213μs±78
bench.Impl.zigqoi: 2252ms
        testcard.qoi: 254μs±76
        kodim10.qoi: 5212μs±293
        dice.qoi: 2760μs±214
        wikipedia_008.qoi: 13608μs±1130
        zero.qoi: 792μs±55
        edgecase.qoi: 50μs±23
        testcard_rgba.qoi: 345μs±154
        kodim23.qoi: 5121μs±531
        qoi_logo.qoi: 254μs±85
```

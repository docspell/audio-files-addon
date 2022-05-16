# Docspell with audio files

This is a simple addon for [Docspell](https://docspell.org) to add
support for audio files. It uses external tools like ffmpeg and stt to
extract text from an audio file. It uses wkhtmltopdf to create a pdf
file.

The result is a preview + pdf and indexed text in the Docspell dms.

*Note: The accuracy of text extraction depends on the used models. For
simplicty this addon uses pre-trained models. For better results, you
need to train your own models.*


## Prerequisites

This addon supports these runners: `nix-flake` and `trivial`. An
internet connection is required to download the model files.

It is recommended to install [nix](https://nixos.org) on the machine
running joex. This allows to use the `nix-flake` runner which can
build the addon with all dependencies automatically.

Otherwise, for the trivial runner, you need to install these tools
manually: curl, ffmpeg, [stt](https://github.com/coqui-ai/STT)
(v0.9.x) and wkhtmltopdf. The latter should already be available since
it is a requirement for joex itself.

Only `x86_64` archtiecture is supported, because nixpkgs doesn't
provide `stt` for other architectures.


## Usage

Currently there is nothing to configure. Just install the addon and
add it to a run configuration.


## Testing

Install [direnv](https://direnv.net/) and [nix](https://nixos.org) and
allow the source root via `direnv allow`. This applies the `devShell`
settings from `flake.nix`. Then build the addon:

```
nix build
```

Now you can run it:

```
./result/bin/audio-files-addon
```

It will run on the test files provided in `test/` and put results in
`test/tmp`.

For quicker turnaround you can also run the source file itself. This
works, because `devShell` puts all required binaries in path.

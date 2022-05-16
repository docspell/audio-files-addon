{ stdenv, bash, cacert, curl, stt, wkhtmltopdf, ffmpeg, guile, guile-json, lib, name }:

stdenv.mkDerivation {
  inherit name;
  src = lib.sources.cleanSource ../.;

  buildInputs = [ guile guile-json ];

  patchPhase = ''
    TARGET=src/addon.scm
    sed -i 's,\*curl\* "curl",\*curl\* "${curl}/bin/curl",g' $TARGET
    sed -i 's,\*ffmpeg\* "ffmpeg",\*ffmpeg\* "${ffmpeg}/bin/ffmpeg",g' $TARGET
    sed -i 's,\*stt\* "stt",\*stt\* "${stt}/bin/stt",g' $TARGET
    sed -i 's,\*wkhtmltopdf\* "wkhtmltopdf",\*wkhtmltopdf\* "${wkhtmltopdf}/bin/wkhtmltopdf",g' $TARGET
  '';

  buildPhase = ''
    guild compile -o ${name}.go src/addon.scm
  '';


  # module name must be same as <filename>.go
  installPhase = ''
    mkdir -p $out/{bin,lib}
    cp ${name}.go $out/lib/

    cat > $out/bin/${name} <<-EOF
    #!${bash}/bin/bash
    export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
    exec -a "${name}" ${guile}/bin/guile -C ${guile-json}/share/guile/ccache -C $out/lib -e '(${name}) main' -c "" \$@
    EOF
    chmod +x $out/bin/${name}
  '';
}

{
  lib,
  stdenv,
  fetchgit,
  makeWrapper,
  perl536,
  proxmox-widget-toolkit,
  proxmox-acme,
  pve-docs,
  pve-ha-manager,
  pve-http-server,
  cdrkit,
  ceph,
  gnupg,
  graphviz,
  gzip,
  nodePackages,
  openvswitch,
  openssh,
  pve-qemu,
  pve-qemu-server,
  tzdata,
  pve-novnc,
  pve-xtermjs,
  iproute2,
  termproxy,
  shadow,
  wget,
  bash,
  zstd,
  system-sendmail, rsync, busybox, cstream, lvm2
}:

let
  perlDeps = with perl536.pkgs; [
    FileReadBackwards
    NetDNS
    PodParser
    TemplateToolkit
    proxmox-acme
    pve-ha-manager
    pve-http-server
    pve-qemu-server
  ];

  perlEnv = perl536.withPackages (_: perlDeps);
in

perl536.pkgs.toPerlModule (
  stdenv.mkDerivation rec {
    pname = "pve-manager";
    version = "8.2.4";

    src = fetchgit {
      url = "https://git.proxmox.com/git/${pname}.git";
      rev = "faa83925c96413258b9a02c4de89442adeff9215";
      hash = "sha256-onNnxvQ7YrdnrFpl+z7Z+xUyEZsMcU6Qxn/kjYLan+8=";
    };

    patches = [
      ./0001-no-apt-update.patch
      ./0002-no-repo-status.patch
    ];

    postPatch = ''
      sed -i {defines.mk,configs/Makefile} -e "s,/usr,,"
      sed -i Makefile \
        -e '/GITVERSION/d' \
        -e "/default.mk/d" \
        -e '/pkg-info/d' \
        -e '/log/d' \
        -e '/architecture/d' \
        -e 's/aplinfo PVE bin www services configs network-hooks test/PVE bin www configs test/'
      sed -i bin/Makefile -e '/pod2man/,+1d' -e '/install -d \$(MAN1DIR)/,+7d'
      patchShebangs configs/country.pl
      sed -i configs/country.pl -e "s|/usr|${tzdata}|"
      #cp PVE/pvecfg.pm{.in,}
      sed -i www/manager6/Makefile -e "/ESLINT/d" -e "s|/usr/bin/asciidoc-pve|${pve-docs}/bin/asciidoc-pve|"
    '';

    buildInputs = [
      perlEnv
      nodePackages.eslint
      graphviz
      makeWrapper
    ];
    propagatedBuildInputs = perlDeps;

    makeFlags = [
      "DESTDIR=$(out)"
      "PVERELEASE=8.0"
      "VERSION=${version}"
      "REPOID=nixos"
      "PERLLIBDIR=$(out)/${perl536.libPrefix}/${perl536.version}"
      "WIDGETKIT=${proxmox-widget-toolkit}/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
      "BASH_COMPLETIONS="
      "ZSH_COMPLETIONS="
      "CLI_MANS="
      "SERVICE_MANS="
    ];

    postInstall = ''
      rm -r $out/var $out/bin/pve{upgrade,update,version,7to8}
      sed -i $out/{bin/*,share/pve-manager/helpers/pve-startall-delay} -e "s/-T//"
    '';

    postFixup = ''
      find $out/lib -type f | xargs sed -i \
        -e "/API2::APT/d" \
        -e "/ENV{'PATH'}/d" \
        -e "s|/usr/share/javascript|${pve-http-server}/share/javascript|" \
        -e "s|/usr/share/fonts-font-awesome|${pve-http-server}/share/fonts-font-awesome|" \
        -e "s|/usr/share/pve-manager|$out/share/pve-manager|" \
        -e "s|/usr/share/zoneinfo|${tzdata}/share/zoneinfo|" \
        -e "s|/usr/share/pve-xtermjs|${pve-xtermjs}/share/pve-xtermjs|" \
        -Ee "s|(/usr)?/s?bin/||" \
        -e "s|/usr/share/novnc-pve|${pve-novnc}/share/webapps/novnc|" \
        -e "s|/usr/share/perl5/.plug|${pve-qemu-server}/${perl536.libPrefix}/${perl536.version}/\$plug|"


      find $out/bin -type f | xargs sed -i \
        -e "/ENV{'PATH'}/d"

      for bin in $out/{bin/*,share/pve-manager/helpers/pve-startall-delay}; do
        wrapProgram $bin \
          --prefix PATH : ${
            lib.makeBinPath [
              ceph
              cdrkit ## cloud-init
              gzip
              openssh
              gnupg
              openvswitch
              pve-qemu
              iproute2
              termproxy
              pve-ha-manager
              shadow
              wget

              ## dependencies of backup and restore
              bash zstd system-sendmail rsync busybox cstream lvm2
            ]
          } \
          --prefix PERL5LIB : $out/${perl536.libPrefix}/${perl536.version}
      done      
    '';

    passthru.updateScript = [
      ../update.py
      pname
      "--url"
      src.url
    ];

    meta = with lib; {
      description = "The Proxmox VE Manager API and Web UI repository";
      homepage = "https://git.proxmox.com/?p=pve-manager.git";
      license = licenses.agpl3Plus;
      maintainers = with maintainers; [
        camillemndn
        julienmalka
      ];
      platforms = platforms.linux;
    };
  }
)

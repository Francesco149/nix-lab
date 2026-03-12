{
  nut.ssh.authorizedKeys = [
    # workstation
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF0Hj5jOmw03+LxHO7xOkcPSMknxRXflt+qznZ0SRCQG headpats@cutestation"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOggpEtx3bYTi/Qr59aaAi2RyAwvsBv04tyPVPGd/9j4 headpats@DESKTOP-2FRVAC7"
    # streaming pc
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNTISALC2cQaRAtgsLUK1V5Ko1s8eO8/1WHkdnH/ifiglrbftmfZ72HHSSht54lUsRR6CvGnDRQPJfySI1xCHhg= loli@HCUP"
    # laptop
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINJqIAtWyhxUgDI8G9oSyzxEtMggUkBcOcYBfonad6RI deeznuts@MOOPLASTORY"
    # proxmox
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEIRmdPK45tD5E9LWrQlU0Cvh/l/31ceXT6tlwBBLwG4 headpats@proxmox"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC3GITt7Z4V/IwnPKmFEpz7KVXXkcyiDaZvg59lbmcTlamMuHopMGXEdh7u1qKWqkr+agNxaqWpAConEsCwX5GFRaOe/LQFHVneOArXWS/p1xw+ywxlgA8NabsQUlg7GsKW5LbJyALZiS5CCTdEz2yCk/NauR9MMXUNW/ZJEN2QrYNZloYiRLY8XCNMNZPwhaPH4rd/K1Am1ZuTPlyjTfkTEyLRCF025KIMNe16ll2DT9HxHE8dFsenxpj2Jgt9e7wch5Pg5h6L4S83++fEYBxsdXrEPC2Yz7WYc6io7dLk31kUGH0QpCelLyELiWpltnQ8OBJKpHBVQpA5HlQtK5I4uujRG0gtVAMflwkqwh69ahK4fy0+8ESUhC4ACH4AqURFrEOqamXwPIqHgU+8zoS2+kmKD0LmU8O2RSE0CUw55b2f358QACA94QfQX3gPonvdP1gQjK9ODcFrApnDaqyK1kZ4Wno7W1NrOkJE7rbukRaivp0conSKgaOGNFs3tkkSF6HPjddKqHNGMRttZp3d5HoK78h+0EBbryAiQ5EFIEj27eO/qG2iEykXN7rig1ezVkW9kA9vcP3HJyePpTPQQteEdL7ztLZfuUDmr8KNzoPK/L+X1kS+oRS8EjHVOvSVaWkRWGeJn1/8yKKUWBQG96mlPLkeKX7PYlKaCZxeSQ== root@proxmox"
    # dockge + openvscode-server dev vm
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO51fsBkesFI7L3+AH2gcn+lEx9S0XzVRcYf6tFujvIr root@code"
  ];

  # always skip key verification for new VMs
  programs.ssh.extraConfig = ''
    Host nixos
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
  '';
}

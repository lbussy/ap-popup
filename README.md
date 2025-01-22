# AP Pop-Up

AP Pop-Up is set of tools to work with `nmcli` to enable WiFi management.  This started as a "please start an access point so I can `ssh` in to my headless Pi when there are no known networks available" project.  As things do, I kept "improving", and I will never get my time back, so I share it here in the hopes that someone will benefit from it.

## Running the Installer

The installer, uninstaller, and upgrades may be invoked via:

**Install (or upgrade) normally:**
``` bash
curl -fsSL https://raw.githubusercontent.com/lbussy/ap-popup/refs/heads/main/scripts/install.sh | sudo bash 
```

**Install (or upgrade) with verbose debug:**
``` bash
curl -fsSL https://raw.githubusercontent.com/lbussy/ap-popup/refs/heads/main/scripts/install.sh | sudo bash -s -- debug
```

**Uninstall:**
``` bash
curl -fsSL https://raw.githubusercontent.com/lbussy/ap-popup/refs/heads/main/scripts/install.sh | sudo bash -s -- uninstall
```

**Uninstall with verbose debug:**
``` bash
curl -fsSL https://raw.githubusercontent.com/lbussy/ap-popup/refs/heads/main/scripts/install.sh | sudo bash -s -- uninstall debug
```

(Note: The uninstall commands use the same script with an 'uninstall' argument.)

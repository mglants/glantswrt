# Cudy flash helper

[`flash_wr3000p.sh`](flash_wr3000p.sh) automates a two-stage flash flow for supported Cudy routers:

1. log into the stock HTTPS web UI
2. upload a signed factory image from [`signed/`](signed)
3. wait for the device to boot into OpenWrt
4. upload a final OpenWrt sysupgrade image from [`openwrt/`](openwrt)
5. run `sysupgrade -n`

## Supported image layout

The script now supports different router image names by model basename.

Default model:
- `wr3000p`

Default path mapping:
- signed image: [`signed/<model>.bin`](signed)
- sysupgrade image: [`openwrt/<model>.bin`](openwrt)

Examples with the current repository contents:
- [`signed/wr3000p.bin`](https://drive.google.com/drive/folders/1BKVarlwlNxf7uJUtRhuMGUqeCa5KpMnj) from Cudy Signed images
- [`openwrt/wr3000p.bin`](https://github.com/mglants/glantswrt) Official OpenWrt Sysipgrade of custom

If the automatic mapping is not suitable, you can override each image path explicitly.

## Requirements

Required tools:
- `bash`
- `curl`
- `ssh`
- `scp`
- `ping`

Optional:
- `sshpass` when OpenWrt already has a non-empty root password and you pass `--openwrt-pass`
- one of `sha256sum`, `openssl`, or `python3` for password hashing

## Usage

Default model:

```bash
bash ./flash_wr3000p.sh --stock-pass 'your-current-stock-password'
```

Select another model by basename:

```bash
bash ./flash_wr3000p.sh \
  --model wr3000h \
  --stock-pass 'your-current-stock-password'
```

Override firmware image paths explicitly:

```bash
bash ./flash_wr3000p.sh \
  --signed-fw signed/wr3000s.bin \
  --openwrt-fw openwrt/custom-wr3000s-sysupgrade.bin \
  --stock-pass 'your-current-stock-password'
```

Enable debug logging:

```bash
DEBUG=1 bash ./flash_wr3000p.sh --stock-pass 'your-current-stock-password'
```

## Options

- `--model NAME` — router model basename used to derive default image paths
- `--signed-fw PATH` — signed factory image path relative to the script directory
- `--openwrt-fw PATH` — OpenWrt sysupgrade image path relative to the script directory
- `--stock-user USER` — stock firmware username, default `admin`
- `--stock-pass PASS` — current stock firmware password
- `--stock-new-pass PASS` — password to set when the stock firmware is still on the first-boot wizard
- `--openwrt-pass PASS` — OpenWrt root password if passwordless SSH is not available
- `--stock-ip IP` — stock firmware address, default `192.168.10.1`
- `--openwrt-ip IP` — OpenWrt address after first reboot, default `192.168.1.1`
- `--stock-timezone TZ` — timezone sent through the stock wizard/login flow
- `--timeout SEC` — timeout per wait stage

## Workflow details

### 1. Stock login

The script connects to the stock UI at `https://192.168.10.1` by default and handles two states:

- first-boot password creation wizard
- existing password login form

The login flow in [`stock_login()`](flash_wr3000p.sh:189) computes the password hash expected by the Cudy UI and keeps the authenticated cookie for later upload requests.

### 2. Signed image upload

The script uploads the selected signed image through the stock upgrade flow in [`flash_signed_from_stock()`](flash_wr3000p.sh:326).

### 3. Boot into OpenWrt

After the signed image is flashed, the script waits for ping and SSH on the OpenWrt address.

### 4. Final sysupgrade

The selected sysupgrade image is copied to `/tmp/sysupgrade.bin`, then the script runs `sysupgrade -n /tmp/sysupgrade.bin`.

The SSH session dropping during this step is expected.

## Troubleshooting

### `HTTP 403 Forbidden` during stock login

This usually means the current stock password is wrong.

Use:

```bash
bash ./flash_wr3000p.sh --stock-pass 'real-current-password'
```

If the router is on the first-boot wizard, you can also define the password to set:

```bash
bash ./flash_wr3000p.sh \
  --stock-pass admin \
  --stock-new-pass 'NewTempPassword123!'
```

### Script stops after fetching the login page

Run with debug enabled:

```bash
DEBUG=1 bash ./flash_wr3000p.sh --stock-pass 'your-current-stock-password'
```

### OpenWrt SSH requires a password

Pass the root password so [`wait_for_ssh()`](flash_wr3000p.sh:159) and [`openwrt_scp()`](flash_wr3000p.sh:390) can use `sshpass`:

```bash
bash ./flash_wr3000p.sh \
  --stock-pass 'your-current-stock-password' \
  --openwrt-pass 'your-openwrt-root-password'
```

### Sysupgrade disconnects with connection failed

That is normally expected. [`sysupgrade`](flash_wr3000p.sh:492) terminates the SSH session while rebooting.

## Notes

- Keep only the image pairs you actually trust for your hardware revision.
- The script does not validate that a chosen model matches the connected router.
- Verify hardware revision and image compatibility before flashing.

# Vagrant PHP 8.5 Box (Debian)

## Requirements
Install Vagrant:
- [Vagrant](https://www.vagrantup.com/)
- [VirtualBox](https://www.virtualbox.org/)

## Usage

```bash
vagrant up        # Start and provision the box
vagrant ssh       # SSH into the box
vagrant halt      # Stop the box
vagrant destroy   # Delete the box
```

## PHP Test
After `vagrant up`, open your browser at:
https://local.pixelfed.dev

(Add `192.168.56.20 local.pixelfed.dev` to your host machine's `/etc/hosts` file.)

## SSL / Let's Encrypt

SSL is configured via variables at the top of `provision.sh`:

| Variable            | Description                                                        |
|---------------------|--------------------------------------------------------------------|
| `ssl_mode`          | `"selfsigned"` (default, works offline) or `"letsencrypt"`         |
| `app_domain`        | Domain name for the site (default: `local.pixelfed.dev`)           |
| `letsencrypt_email` | Required when `ssl_mode=letsencrypt` (e.g. `admin@pixelfed.dev`)  |

### Self-signed (default – local development)
Works out of the box. Your browser will show a certificate warning.

### Let's Encrypt (production / publicly reachable domain)
1. Set `ssl_mode="letsencrypt"` in `provision.sh`
2. Set `app_domain` to your publicly reachable domain
3. Set `letsencrypt_email` to a valid email address
4. Make sure port 80 is reachable from the internet (required for HTTP-01 challenge)
5. Run `vagrant provision`

Certbot will automatically obtain a certificate and configure Apache to redirect HTTP → HTTPS.

## Install something in the box
Edit `provision.sh` and add your package to the `apt-get install` line,
then run `vagrant reload --provision`.
or: `vagrant provision`


```
vagrant rsync-auto
```
to auto sync whatever files you are changing
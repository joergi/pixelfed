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

## add url to /etc/hosts
Add `192.168.56.20 local.pixelfed.test` to your host machine's `/etc/hosts` file.)
(don't use .dev, it's not working as it's preserved.)


## PHP Test
After `vagrant up`, open your browser at:
https://local.pixelfed.test


## SSL / Let's Encrypt

SSL is configured via variables at the top of `provision.sh`:
Not tested yet with let's encrypt

| Variable            | Description                                                        |
|---------------------|--------------------------------------------------------------------|
| `ssl_mode`          | `"selfsigned"` (default, works offline) or `"letsencrypt"`         |
| `app_domain`        | Domain name for the site (default: `local.pixelfed.test`)          |
| `letsencrypt_email` | Required when `ssl_mode=letsencrypt` (e.g. `admin@pixelfed.dev`)  |

### Self-signed (default – local development)
Works out of the box. Your browser will show a certificate warning (`MOZILLA_PKIX_ERROR_SELF_SIGNED_CERT` in Firefox).
Click **Advanced…** → **Accept the Risk and Continue** to proceed.


### Let's Encrypt (production / publicly reachable domain - not tested yet)
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

## Check if Redis is working
```bash
vagrant ssh
redis-check          # alias: pings Redis and prints status
redis-cli ping       # expect: PONG
redis-cli info server  # full server info
```

## After the start, create a user
```bash
vagrant ssh
pf                       # shortcut for cd /var/www/html/pixelfed
php artisan user:create
```

## Useful shell aliases
These aliases are available after `vagrant ssh`:

| Alias        | Command                                                     |
|--------------|-------------------------------------------------------------|
| `pf`         | `cd /var/www/html/pixelfed`                                 |
| `l`          | `ls -alh`                                                   |
| `e`          | `exit`                                                      |
| `logs`       | `sudo tail -f /var/log/apache2/*.log`                       |
| `logs-app`   | `tail -f /var/www/html/pixelfed/storage/logs/laravel.log`   |
| `logs-ssl`   | `sudo tail -f /var/log/apache2/pixelfed-ssl-error.log`      |
| `redis-check`| `redis-cli ping` + status message                           |
